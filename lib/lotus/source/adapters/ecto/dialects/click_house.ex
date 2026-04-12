defmodule Lotus.Source.Adapters.Ecto.Dialects.ClickHouse do
  @moduledoc false

  @behaviour Lotus.Source.Adapters.Ecto.Dialect

  alias Lotus.SQL.FilterInjector
  alias Lotus.SQL.SortInjector

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
  def limit_query(statement, limit) do
    "SELECT * FROM (#{statement}) AS t LIMIT #{limit}"
  end

  # ---------------------------------------------------------------------------
  # Session Management
  # ---------------------------------------------------------------------------

  @impl true
  def execute_in_transaction(_repo, fun, _opts) do
    {:ok, fun.()}
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

  @impl true
  def handled_errors do
    [@ch_error, DBConnection.ConnectionError]
  end

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
  def apply_filters(sql, params, filters) do
    filter_values = Enum.map(filters, & &1.value)
    all_values = params ++ filter_values

    placeholder_fn = fn idx ->
      value = Enum.at(all_values, idx - 1)
      "{$#{idx - 1}:#{ch_type_for_value(value)}}"
    end

    FilterInjector.apply(sql, params, filters, &quote_identifier/1, placeholder_fn)
  end

  @impl true
  def apply_sorts(sql, sorts) do
    SortInjector.apply(sql, sorts, &quote_identifier/1)
  end

  @impl true
  def explain_plan(repo, sql, _params, _opts) do
    case repo.query("EXPLAIN #{sql}", []) do
      {:ok, %{rows: rows}} ->
        text = rows |> Enum.map_join("\n", fn [line] -> line end)
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
  def get_table_schema(repo, schema, table) do
    sql = """
    SELECT
      name,
      type,
      position,
      default_kind,
      is_in_primary_key
    FROM system.columns
    WHERE database = {$0:String} AND table = {$1:String}
    ORDER BY position
    """

    %{rows: rows} = repo.query!(sql, [schema, table])

    Enum.map(rows, fn [name, type, _position, default_kind, is_pk] ->
      %{
        name: name,
        type: format_ch_type(type),
        nullable: nullable?(type),
        default: if(default_kind != "", do: default_kind, else: nil),
        primary_key: is_pk == 1
      }
    end)
  end

  @impl true
  def resolve_table_schema(repo, table, schemas) do
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
  def supports_feature?(_), do: false

  @impl true
  def hierarchy_label, do: "Databases"

  @impl true
  def example_query(table, _schema) do
    "SELECT * FROM #{table} LIMIT 100"
  end

  @impl true
  def transform_sql(sql), do: sql

  @impl true
  def db_type_to_lotus_type(db_type) when is_binary(db_type) do
    db_type
    |> unwrap_type()
    |> ch_scalar_type()
  end

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
  defp lotus_type_to_ch_param(nil), do: "String"
  defp lotus_type_to_ch_param(_), do: "String"

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
