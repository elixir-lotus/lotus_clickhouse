defmodule Lotus.Source.Adapters.Ecto.Dialects.ClickHouse do
  @moduledoc """
  `Lotus.Source.Adapters.Ecto.Dialect` implementation for ClickHouse.

  Everything that differs from the SQL dialects Lotus ships lives here:

    * **Identifiers and parameters** — double-quoted identifiers, and ClickHouse's
      `{$0:Type}` placeholders rather than `$1` or `?`.
    * **Type mapping** — `db_type_to_lotus_type/1` covers the integer,
      float, decimal, date, string, array, map and tuple families, through
      the `Nullable` and `LowCardinality` wrappers.
    * **Query plans** — `query_plan/4` runs `EXPLAIN`.
    * **Safety defaults** — `builtin_denies/1` and `builtin_schema_denies/1`
      keep the `system` database and the migration table out of reach,
      before any host visibility rule is considered.
    * **Editor and AI** — ClickHouse keywords, types and functions, and an
      `ai_context/0` carrying the syntax notes that keep a model away from
      the patterns that perform badly here (`PREWHERE`, `FINAL`,
      approximate aggregations, column-oriented shapes).

  Host applications do not call this module. It is reached through
  `Lotus.Source.Adapters.ClickHouse`, which the Lotus pipeline drives.
  """

  @behaviour Lotus.Source.Adapters.Ecto.Dialect

  alias Lotus.Query.Statement
  alias Lotus.Source.Adapters.Ecto, as: EctoAdapter
  alias Lotus.Source.Adapters.Ecto.Dialects.ClickHouse.EditorConfig
  alias Lotus.Source.Adapters.Ecto.SQL.FilterInjector
  alias Lotus.Source.Adapters.Ecto.SQL.SortInjector
  alias Lotus.Source.Adapters.Ecto.SQL.Transformer

  @ch_error Module.concat([:Ch, :Error])

  # ---------------------------------------------------------------------------
  # Source Identity
  # ---------------------------------------------------------------------------

  @impl true
  def source_type, do: :clickhouse

  @impl true
  def ecto_adapter, do: Ecto.Adapters.ClickHouse

  @impl true
  def query_language, do: "sql:clickhouse"

  @impl true
  def limit_query(%Statement{body: sql} = statement, limit) do
    %{statement | body: "SELECT * FROM (#{sql}) AS t LIMIT #{limit}"}
  end

  # ---------------------------------------------------------------------------
  # Session Management
  # ---------------------------------------------------------------------------

  @impl true
  def execute_in_transaction(repo, fun, opts) do
    timeout = Keyword.get(opts, :timeout, 15_000)
    {:ok, repo.checkout(fun, timeout: timeout)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @impl true
  def set_statement_timeout(_repo, _timeout_ms), do: :ok

  @impl true
  def set_search_path(_repo, _search_path), do: :ok

  # ---------------------------------------------------------------------------
  # Error Handling
  # ---------------------------------------------------------------------------

  @impl true
  def format_error(%{__struct__: mod} = e) when mod == @ch_error do
    case e do
      %{code: code, message: message} when is_integer(code) ->
        "ClickHouse Error (#{code}): #{message}"

      %{message: message} ->
        "ClickHouse Error: #{message}"

      _ ->
        Exception.message(e)
    end
  end

  def format_error(%DBConnection.ConnectionError{message: message}),
    do: "Connection error: #{message}"

  def format_error(other) when is_binary(other), do: other
  def format_error(other), do: inspect(other)

  # ---------------------------------------------------------------------------
  # SQL Generation
  # ---------------------------------------------------------------------------

  @impl true
  def quote_identifier(identifier) do
    escaped = String.replace(identifier, "\"", "\"\"")
    ~s("#{escaped}")
  end

  @impl true
  def param_placeholder(idx, _var, type) do
    ch_type = lotus_type_to_ch_param(type)
    "{$#{idx - 1}:#{ch_type}}"
  end

  @impl true
  def limit_offset_placeholders(limit_idx, offset_idx) do
    {"{$#{limit_idx - 1}:UInt64}", "{$#{offset_idx - 1}:UInt64}"}
  end

  @impl true
  def apply_filters(%Statement{body: sql, params: params} = statement, filters) do
    # A placeholder carries its own type here, so the type has to be derived
    # from the value that will land in it. `FilterInjector` emits no parameter
    # for a null test, so counting every filter would shift each index after
    # the first one and type a placeholder from the wrong value.
    filter_values = filters |> Enum.filter(&binds_parameter?/1) |> Enum.map(& &1.value)
    all_values = params ++ filter_values

    placeholder_fn = fn idx ->
      value = Enum.at(all_values, idx - 1)
      "{$#{idx - 1}:#{ch_type_for_value(value)}}"
    end

    {new_sql, new_params} =
      FilterInjector.apply(sql, params, filters, &quote_identifier/1, placeholder_fn)

    %{statement | body: new_sql, params: new_params}
  end

  # Mirrors the clauses in `Lotus.Source.Adapters.Ecto.SQL.FilterInjector` that
  # build a condition without a parameter.
  defp binds_parameter?(%{op: op}) when op in [:is_null, :is_not_null], do: false
  defp binds_parameter?(%{value: nil}), do: false
  defp binds_parameter?(_filter), do: true

  @impl true
  def apply_sorts(%Statement{body: sql} = statement, sorts) do
    %{statement | body: SortInjector.apply(sql, sorts, &quote_identifier/1)}
  end

  @impl true
  def query_plan(repo, %Statement{body: sql, params: params}, _opts) do
    case repo.query("EXPLAIN " <> sql, params, settings: [readonly: 1]) do
      {:ok, %{rows: rows}} ->
        text = Enum.map_join(rows, "\n", fn [line] -> line end)
        {:ok, text}

      {:error, err} ->
        {:error, format_error(err)}
    end
  end

  # ---------------------------------------------------------------------------
  # Safety & Visibility
  # ---------------------------------------------------------------------------

  @impl true
  def builtin_denies(repo) do
    ms = repo.config()[:migration_source] || "schema_migrations"
    database = repo.config()[:database]

    base_denies = [
      {"system", ~r/.*/},
      {"INFORMATION_SCHEMA", ~r/.*/},
      {"information_schema", ~r/.*/},
      {nil, ms},
      {nil, "lotus_queries"},
      {nil, "lotus_query_visualizations"},
      {nil, "lotus_dashboards"},
      {nil, "lotus_dashboard_cards"},
      {nil, "lotus_dashboard_filters"},
      {nil, "lotus_dashboard_card_filter_mappings"}
    ]

    if database do
      base_denies ++
        [
          {database, ms},
          {database, "lotus_queries"},
          {database, "lotus_query_visualizations"},
          {database, "lotus_dashboards"},
          {database, "lotus_dashboard_cards"},
          {database, "lotus_dashboard_filters"},
          {database, "lotus_dashboard_card_filter_mappings"}
        ]
    else
      base_denies
    end
  end

  @impl true
  def builtin_schema_denies(_repo) do
    ["system", "INFORMATION_SCHEMA", "information_schema"]
  end

  @impl true
  def default_schemas(repo) do
    database = repo.config()[:database] || "default"
    [database]
  end

  @impl true
  def extract_accessed_resources(repo, %Statement{body: sql, params: params}) do
    default_db = repo.config()[:database] || "default"
    alias_map = EctoAdapter.parse_alias_map(sql)
    explain_sql = "EXPLAIN AST " <> sql

    relations =
      case repo.query(explain_sql, params, settings: [readonly: 1]) do
        {:ok, %{rows: rows}} ->
          rows
          |> extract_tables_from_ast(default_db, alias_map)
          |> reconcile_with_sql(sql, default_db, alias_map)

        {:error, _err} ->
          extract_tables_from_sql_fallback(sql, default_db, alias_map)
      end

    {:ok, relations}
  rescue
    _ ->
      {:ok,
       extract_tables_from_sql_fallback(sql, default_db(repo), EctoAdapter.parse_alias_map(sql))}
  end

  # An empty relation set means "this query reads nothing", and core's
  # preflight lets it straight through. That is the right answer for
  # `SELECT 1`, and a visibility bypass for anything else: a ClickHouse
  # release that renames the AST node, or an identifier shape the scan does
  # not match, would silently produce it. So when the statement plainly reads
  # from something, fall back to the SQL scan rather than reporting nothing.
  defp reconcile_with_sql(relations, sql, default_db, alias_map) do
    if MapSet.size(relations) == 0 and reads_from_something?(sql) do
      extract_tables_from_sql_fallback(sql, default_db, alias_map)
    else
      relations
    end
  end

  defp reads_from_something?(sql), do: Regex.match?(~r/\b(?:FROM|JOIN)\b/i, sql)

  defp default_db(repo), do: repo.config()[:database] || "default"

  defp extract_tables_from_ast(rows, default_db, alias_map) do
    table_identifier =
      ~r/TableIdentifier\s+(?:([a-zA-Z_][a-zA-Z0-9_]*)\.)?([a-zA-Z_][a-zA-Z0-9_]*)/

    rows
    |> Enum.flat_map(fn [line] -> Regex.scan(table_identifier, line) end)
    |> Enum.map(fn
      [_, "", table] -> {default_db, resolve_table(table, alias_map)}
      [_, schema, table] -> {EctoAdapter.normalize_ident(schema), resolve_table(table, alias_map)}
    end)
    |> MapSet.new()
  end

  defp extract_tables_from_sql_fallback(sql, default_db, alias_map) do
    table_regex =
      ~r/(?:FROM|JOIN)\s+(?:([`"]?)([a-zA-Z_][a-zA-Z0-9_]*)\1\.)?([`"]?)([a-zA-Z_][a-zA-Z0-9_]*)\3(?:\s+(?:AS\s+)?[a-zA-Z_][a-zA-Z0-9_]*)?/i

    Regex.scan(table_regex, sql)
    |> Enum.map(fn
      [_, _, schema, _, table] when schema != "" ->
        {EctoAdapter.normalize_ident(schema), resolve_table(table, alias_map)}

      [_, _, "", _, table] ->
        {default_db, resolve_table(table, alias_map)}

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp resolve_table(table, alias_map) do
    table
    |> EctoAdapter.normalize_ident()
    |> EctoAdapter.resolve_alias(alias_map)
  end

  # ---------------------------------------------------------------------------
  # Introspection
  # ---------------------------------------------------------------------------

  @impl true
  def list_schemas(repo) do
    sql = """
    SELECT name
    FROM system.databases
    WHERE name NOT IN ('system', 'INFORMATION_SCHEMA', 'information_schema')
    ORDER BY name
    """

    %{rows: rows} = repo.query!(sql)
    Enum.map(rows, fn [schema] -> schema end)
  end

  @impl true
  def list_tables(repo, schemas, include_views?) do
    placeholders =
      schemas
      |> Enum.with_index()
      |> Enum.map_join(",", fn {_s, i} -> "{$#{i}:String}" end)

    engine_filter =
      if include_views?,
        do: "",
        else: " AND engine NOT IN ('MaterializedView', 'View')"

    sql = """
    SELECT database, name
    FROM system.tables
    WHERE database IN (#{placeholders})#{engine_filter}
    ORDER BY database, name
    """

    %{rows: rows} = repo.query!(sql, schemas)
    Enum.map(rows, fn [schema, table] -> {schema, table} end)
  end

  @impl true
  def describe_table(repo, schema, table) do
    sql = """
    SELECT
      name,
      type,
      position,
      default_expression,
      is_in_primary_key
    FROM system.columns
    WHERE database = {$0:String} AND table = {$1:String}
    ORDER BY position
    """

    %{rows: rows} = repo.query!(sql, [schema, table])

    Enum.map(rows, fn [name, type, _position, default_expression, is_pk] ->
      %{
        name: name,
        type: format_ch_type(type),
        nullable: nullable?(type),
        default: if(default_expression != "", do: default_expression, else: nil),
        primary_key: is_pk == 1
      }
    end)
  end

  @impl true
  def resolve_table_namespace(repo, table, schemas) do
    placeholders =
      schemas
      |> Enum.with_index(1)
      |> Enum.map_join(",", fn {_s, i} -> "{$#{i}:String}" end)

    sql = """
    SELECT database
    FROM system.tables
    WHERE name = {$0:String} AND database IN (#{placeholders})
    LIMIT 1
    """

    params = [table | schemas]

    case repo.query(sql, params) do
      {:ok, %{rows: [[schema]]}} -> schema
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Optional Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def supports_feature?(:arrays), do: true
  def supports_feature?(:json), do: true
  def supports_feature?(:schema_hierarchy), do: false
  def supports_feature?(:search_path), do: false
  def supports_feature?(:make_interval), do: false
  def supports_feature?(:dynamic_options), do: true
  def supports_feature?(_), do: false

  @impl true
  def hierarchy_label, do: "Databases"

  @impl true
  def example_query(table, _schema) do
    "SELECT * FROM #{table} LIMIT 100"
  end

  @impl true
  def transform_statement(%Statement{body: sql} = statement) do
    new_sql =
      sql
      |> Transformer.transform_wildcards(:pipe)
      |> Transformer.strip_quoted_variables()

    %{statement | body: new_sql}
  end

  @impl true
  def needs_preflight?(%Statement{body: sql}) when is_binary(sql) do
    trimmed = sql |> String.trim_leading() |> String.upcase()
    not String.starts_with?(trimmed, ["EXPLAIN", "SHOW", "DESCRIBE", "DESC "])
  end

  def needs_preflight?(_), do: true

  @impl true
  def ai_context do
    {:ok,
     %{
       language: query_language(),
       example_query:
         "SELECT user_id, count() AS events FROM events WHERE event_date >= today() - 7 GROUP BY user_id ORDER BY events DESC LIMIT 100",
       syntax_notes: clickhouse_syntax_notes(),
       error_patterns: [
         %{
           pattern: ~r/Code:\s*60/,
           hint: "Table not found. Check the database.table name via list_tables()."
         },
         %{
           pattern: ~r/Code:\s*47/,
           hint: "Column not found. Check the column name via describe_table()."
         },
         %{
           pattern: ~r/Code:\s*62/,
           hint:
             "Query syntax error. Check the ClickHouse SQL grammar — some constructs differ from standard SQL."
         },
         %{
           pattern: ~r/Code:\s*164|READONLY/,
           hint:
             "Write attempted on a read-only query. Lotus enforces readonly=1 — only SELECT/EXPLAIN/SHOW/DESCRIBE are allowed."
         },
         %{
           pattern: ~r/Memory limit.*exceeded/i,
           hint:
             "Query exceeded memory limit. Try narrowing the WHERE clause, adding PREWHERE, or using approximate functions (uniq instead of count(DISTINCT))."
         }
       ],
       capabilities: %{
         generation: true,
         optimization: true,
         explanation: true
       }
     }}
  end

  defp clickhouse_syntax_notes do
    """
    ClickHouse SQL is column-oriented and optimized for analytics. \
    Use double-quoted identifiers for tables and columns. \
    Prefer `PREWHERE` over `WHERE` when filtering on columns that prune partitions early. \
    Avoid `SELECT *` on wide tables — name columns explicitly. \
    Dates: `today()`, `now()`, `toDate()`, `toStartOfDay()`, `dateDiff()`. \
    Arrays: `arrayJoin(array)` unpacks to rows, `groupArray()` aggregates. \
    Approximate functions (`uniq`, `uniqExact`, `quantile`) are much cheaper than exact equivalents for large datasets. \
    ClickHouse has no transactions; `readonly=1` setting is enforced per-query automatically. \
    `FINAL` forces deduplication on `ReplacingMergeTree`/`CollapsingMergeTree` — use sparingly, it's expensive. \
    Use `SETTINGS` clause for per-query tuning (e.g. `SETTINGS max_execution_time=30`).\
    """
  end

  @impl true
  def db_type_to_lotus_type(db_type) when is_binary(db_type) do
    db_type
    |> unwrap_type()
    |> ch_scalar_type()
  end

  @impl true
  def editor_config, do: EditorConfig.config()

  # ---------------------------------------------------------------------------
  # Private: Type Mapping
  # ---------------------------------------------------------------------------

  defp unwrap_type("Nullable(" <> rest), do: unwrap_type(String.trim_trailing(rest, ")"))
  defp unwrap_type("LowCardinality(" <> rest), do: unwrap_type(String.trim_trailing(rest, ")"))
  defp unwrap_type(type), do: String.downcase(type)

  defp ch_scalar_type("array(" <> rest) do
    inner = String.trim_trailing(rest, ")")
    {:array, db_type_to_lotus_type(inner)}
  end

  defp ch_scalar_type("bool"), do: :boolean
  defp ch_scalar_type("uint8"), do: :integer
  defp ch_scalar_type("uint16"), do: :integer
  defp ch_scalar_type("uint32"), do: :integer
  defp ch_scalar_type("uint64"), do: :integer
  defp ch_scalar_type("uint128"), do: :integer
  defp ch_scalar_type("uint256"), do: :integer
  defp ch_scalar_type("int8"), do: :integer
  defp ch_scalar_type("int16"), do: :integer
  defp ch_scalar_type("int32"), do: :integer
  defp ch_scalar_type("int64"), do: :integer
  defp ch_scalar_type("int128"), do: :integer
  defp ch_scalar_type("int256"), do: :integer
  defp ch_scalar_type("float32"), do: :float
  defp ch_scalar_type("float64"), do: :float
  defp ch_scalar_type("decimal" <> _), do: :decimal
  defp ch_scalar_type("string"), do: :text
  defp ch_scalar_type("fixedstring" <> _), do: :text
  defp ch_scalar_type("date"), do: :date
  defp ch_scalar_type("date32"), do: :date
  defp ch_scalar_type("datetime" <> _), do: :datetime
  defp ch_scalar_type("uuid"), do: :uuid
  defp ch_scalar_type("json"), do: :json
  defp ch_scalar_type("object('json')"), do: :json
  defp ch_scalar_type("map(" <> _), do: :json
  defp ch_scalar_type("enum8" <> _), do: :enum
  defp ch_scalar_type("enum16" <> _), do: :enum
  defp ch_scalar_type("ipv4"), do: :text
  defp ch_scalar_type("ipv6"), do: :text
  defp ch_scalar_type(_), do: :text

  defp lotus_type_to_ch_param(:text), do: "String"
  defp lotus_type_to_ch_param(:string), do: "String"
  defp lotus_type_to_ch_param(:integer), do: "Int64"
  defp lotus_type_to_ch_param(:float), do: "Float64"
  defp lotus_type_to_ch_param(:decimal), do: "String"
  defp lotus_type_to_ch_param(:boolean), do: "Bool"
  defp lotus_type_to_ch_param(:date), do: "Date"
  defp lotus_type_to_ch_param(:datetime), do: "DateTime"
  defp lotus_type_to_ch_param(:uuid), do: "String"
  defp lotus_type_to_ch_param(:binary), do: "String"
  defp lotus_type_to_ch_param(:json), do: "String"
  # `supports_feature?(:arrays)` says a list can bind as one value, so the
  # element type has to survive into the placeholder. Core expands lists into
  # one placeholder each today, which is why this went unnoticed.
  defp lotus_type_to_ch_param({:array, inner}), do: "Array(#{lotus_type_to_ch_param(inner)})"
  defp lotus_type_to_ch_param(nil), do: "String"
  defp lotus_type_to_ch_param(_), do: "String"

  defp ch_type_for_value([]), do: "Array(String)"

  defp ch_type_for_value([head | _] = list) when is_list(list),
    do: "Array(#{ch_type_for_value(head)})"

  defp ch_type_for_value(v) when is_binary(v), do: "String"
  defp ch_type_for_value(v) when is_integer(v), do: "Int64"
  defp ch_type_for_value(v) when is_float(v), do: "Float64"
  defp ch_type_for_value(v) when is_boolean(v), do: "Bool"
  defp ch_type_for_value(%Date{}), do: "Date"
  defp ch_type_for_value(%DateTime{}), do: "DateTime"
  defp ch_type_for_value(%NaiveDateTime{}), do: "DateTime"
  defp ch_type_for_value(%Decimal{}), do: "String"
  defp ch_type_for_value(nil), do: "Nullable(String)"
  defp ch_type_for_value(_), do: "String"

  defp format_ch_type(type), do: type

  defp nullable?("Nullable(" <> _), do: true
  defp nullable?(_), do: false
end
