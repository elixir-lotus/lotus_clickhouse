# How It Works

This guide is for anyone reading, extending or debugging the adapter. It walks the two modules callback by callback and explains where the ClickHouse-specific behaviour actually lives.

If you only want to write queries, [Writing Queries](writing-queries.md) is the shorter path.

## The adapter / dialect split

```
lib/
  lotus_clickhouse.ex                                           # Lotus.ClickHouse — namespace module, no behaviour
  lotus/source/adapters/
    click_house.ex                                              # Lotus.Source.Adapters.ClickHouse
    ecto/dialects/
      click_house.ex                                            # ...Ecto.Dialects.ClickHouse
      click_house/editor_config.ex                              # ...Ecto.Dialects.ClickHouse.EditorConfig
```

Lotus core offers two paths for a custom source. This package takes the SQL one: implement `Lotus.Source.Adapters.Ecto.Dialect` and let core's shared Ecto machinery supply the rest.

```elixir
defmodule Lotus.Source.Adapters.ClickHouse do
  use Lotus.Source.Adapters.Ecto,
    dialect: Lotus.Source.Adapters.Ecto.Dialects.ClickHouse
end
```

That one `use` injects an implementation of every `Lotus.Source.Adapter` callback — registration, execution, introspection, SQL generation, visibility, lifecycle, pipeline, validation, identity, presentation and type mapping — each one either delegating to the dialect or calling a shared helper on `Lotus.Source.Adapters.Ecto`. The macro also asserts at compile time that the named dialect declares the `Dialect` behaviour. Every injected callback is `defoverridable`.

The dialect is the whole of this package's behaviour. The adapter module overrides exactly one callback.

### Why `execute_query/4` is overridden

Core's shared `do_execute_query/5` runs the query inside `execute_in_transaction/3` and signals failure with `repo.rollback/1`. `ecto_ch` does not implement `Ecto.Adapter.Transaction`, so `repo.rollback/1` does not exist and that path cannot be used.

The override does the minimum instead:

```elixir
def execute_query(repo, sql, params, opts) do
  timeout = Keyword.get(opts, :timeout, 15_000)
  read_only = Keyword.get(opts, :read_only, true)

  query_opts = [timeout: timeout]
  query_opts =
    if read_only, do: Keyword.put(query_opts, :settings, readonly: 1), else: query_opts

  case repo.query(sql, params, query_opts) do
    {:ok, %{columns: cols, rows: rows} = raw} -> ...
    {:error, err} -> {:error, Dialect.format_error(err)}
  end
end
```

Two differences from core's version are worth noting. It attaches ClickHouse's `readonly: 1` setting, which is this adapter's read-only enforcement — there is no session to put into read-only mode. And it does not honour an incoming `:search_path`, which is consistent with `supports_feature?(:search_path)` answering `false`.

The result map carries `:columns`, `:rows` and `:num_rows` only; core's Postgres path additionally forwards `:command`, `:connection_id` and `:messages`, which the `ch` driver has no equivalents for.

`transaction/3`, meanwhile, is the injected default and calls the dialect's `execute_in_transaction/3`, which checks a connection out of the pool with `repo.checkout/2` and returns `{:ok, result}`. It is a connection scope, not a transaction: nothing is atomic and nothing can be rolled back. For a read-only analytics source that costs nothing.

## Where a query goes

Running a saved query through `Lotus.run_query/2`:

1. `transform_bound_query/3` — the injected default, a pass-through here.
2. `apply_filters/3` → the dialect wraps the SQL in `WITH _base AS (...)` and appends `WHERE`, via core's `FilterInjector` with this dialect's quoting and placeholder functions.
3. `apply_sorts/3` → the dialect wraps that in `WITH _sorted AS (...)` and appends `ORDER BY`, via core's `SortInjector`.
4. `apply_pagination/3` → core's shared helper wraps it in `SELECT * FROM (...) AS lotus_sub LIMIT ? OFFSET ?`, asking the dialect only for the two placeholder strings, and records a `SELECT COUNT(*)` count spec in the statement metadata when `count: :exact` was requested.
5. `Lotus.Runner` takes over: `:before_query` middleware, then `sanitize_query/3` (core's shared multi-statement and DML checks), then `needs_preflight?/2` and visibility preflight, then `transaction/3` wrapping `execute_query/4`.

`transform_statement/1` is not in that list because it fires earlier, in `Lotus.Storage.Query.compile/2`, before `{{var}}` markers are resolved.

## Dialect callbacks, one at a time

### Identity

| Callback | Value |
|---|---|
| `source_type/0` | `:clickhouse` |
| `ecto_adapter/0` | `Ecto.Adapters.ClickHouse` — this is what the generated `can_handle?/1` compares a repo's `__adapter__/0` against |
| `query_language/0` | `"sql:clickhouse"` — the `family:dialect` form core expects; the editor reads the part after the colon to select a tokenizer |
| `limit_query/2` | `SELECT * FROM (<sql>) AS t LIMIT <n>` |
| `hierarchy_label/0` | `"Databases"` |
| `example_query/2` | `SELECT * FROM <table> LIMIT 100` |

`editor_config/0` declares the same `"sql:clickhouse"` string as `query_language/0`. The two must agree; a bare `"sql"` there would cost the editor every ClickHouse keyword and function declared below it.

### Features

```elixir
def supports_feature?(:arrays), do: true
def supports_feature?(:json), do: true
def supports_feature?(:schema_hierarchy), do: false
def supports_feature?(:search_path), do: false
def supports_feature?(:make_interval), do: false
def supports_feature?(:dynamic_options), do: true
def supports_feature?(_), do: false
```

- `:schema_hierarchy` is `false` for the same reason MySQL answers `false`: the database is configured on the repo, not browsed. The UI shows no database picker, even though `hierarchy_label/0` says `"Databases"` for the label it does print.
- `:search_path` is `false`, and `set_search_path/2` is a no-op, so a caller-supplied search path is ignored.
- `:make_interval` is `false`, so core's Postgres `INTERVAL` rewrite is not applied. Nothing is substituted in its place — see [Writing Queries](writing-queries.md#dates-and-intervals).
- `:arrays` is `true` because ClickHouse has a genuine `Array` type. Note that core's shared SQL substitution still expands a list variable into N placeholders regardless, and `param_placeholder/3` has no `Array(...)` form to emit.
- `:dynamic_options` is `true`: a `SELECT` returns a flat column of values, so variable dropdowns can be query-populated.

### SQL generation

`quote_identifier/1` wraps in double quotes and doubles any embedded `"`. ClickHouse accepts backticks as well, and its own documentation prefers them, but nothing this adapter generates uses them.

`param_placeholder/3` and `limit_offset_placeholders/2` emit ClickHouse's `{$N:Type}` form, 0-indexed against the params list — `limit_offset_placeholders/2` always as `UInt64`. The Lotus-to-ClickHouse type table is in [Writing Queries](writing-queries.md#how-lotus-picks-the-type); everything unrecognised, `nil` included, falls back to `String`.

`apply_filters/2` has a wrinkle the other dialects do not: the placeholder type for a filter is inferred from the **Elixir value** rather than from a Lotus type atom, because a result-table filter arrives as a raw value. The dialect therefore builds the combined value list itself and types each placeholder from the value at that index — binary to `String`, integer to `Int64`, float to `Float64`, boolean to `Bool`, `Date`/`DateTime`/`NaiveDateTime` to their ClickHouse namesakes, `Decimal` to `String`.

`query_plan/3` runs `EXPLAIN <sql>` with `readonly: 1` and joins the returned rows with newlines into one string. Parameters are passed through, so a plan can be produced for a statement that still has its placeholders. It is ClickHouse's default `EXPLAIN` — the query-plan view, not `EXPLAIN PIPELINE` or `EXPLAIN ESTIMATE` — and the `opts` argument is ignored.

### Safety and visibility

`builtin_denies/1` returns tuples of `{schema, table_or_pattern}` that core applies before any host visibility rule:

- `{"system", ~r/.*/}`, `{"INFORMATION_SCHEMA", ~r/.*/}` and `{"information_schema", ~r/.*/}` — the whole of each.
- The repo's `:migration_source` (defaulting to `"schema_migrations"`) and the six `lotus_*` metadata tables, each listed twice: once unqualified (`nil` schema) and once qualified with the repo's configured `:database`, when there is one.

`builtin_schema_denies/1` returns the three system database names, keeping them out of schema listings.

`default_schemas/1` returns a single-element list: the repo's `:database`, or `"default"`.

These rules govern *user statements*. The adapter's own introspection goes to `repo.query!/2` directly and reads `system.*` regardless — that is the intended split, not a hole.

`extract_accessed_resources/2` is what makes visibility enforcement real for this source. It runs `EXPLAIN AST <sql>` with `readonly: 1` and scans the returned plan lines for `TableIdentifier <db>.<table>` nodes, attributing unqualified names to the repo's database and resolving aliases back to real table names with core's `parse_alias_map/1` and `resolve_alias/2`. If the `EXPLAIN AST` call fails — or anything in the function raises — it falls back to a `FROM` / `JOIN` regex over the raw SQL.

Both paths see only real table identifiers. A table reached through a table function (`url(...)`, `remote(...)`, `s3(...)`) or a dictionary is not one, and will not be reported.

`needs_preflight?/1` returns `false` for statements whose upcased, left-trimmed body starts with `EXPLAIN`, `SHOW`, `DESCRIBE` or `DESC ` — introspection statements that touch no visible relation. Everything else pays one `EXPLAIN AST` round-trip before it runs.

### Introspection

Everything comes from ClickHouse's `system` database rather than `information_schema`:

| Callback | Source | Notes |
|---|---|---|
| `list_schemas/1` | `system.databases` | Excludes `system`, `INFORMATION_SCHEMA` and `information_schema`; returns every other database on the server |
| `list_tables/3` | `system.tables` | Filtered to the given databases; excludes `engine IN ('MaterializedView', 'View')` unless `include_views?` |
| `describe_table/3` | `system.columns` | Ordered by `position` |
| `resolve_table_namespace/3` | `system.tables` | First database among the candidates that holds a table with this name |

`describe_table/3` reports `:type` as ClickHouse's own type string, wrappers included — `Nullable(UInt32)`, `LowCardinality(String)`, `Array(String)` — which is what core expects, since it feeds that string back through `db_type_to_lotus_type/1`. `:nullable` is `true` only for a literal `Nullable(...)` prefix, so a `LowCardinality(Nullable(String))` column is reported as not nullable. `:primary_key` comes from `is_in_primary_key`, which in ClickHouse means membership of the sorting key rather than a uniqueness constraint. `:default` is the `default_kind` column — the *kind* of default (`DEFAULT`, `MATERIALIZED`, `ALIAS`), not the expression.

### Type mapping

`db_type_to_lotus_type/1` strips wrappers recursively, then matches the scalar:

```
Nullable(String)                 -> :text
LowCardinality(String)           -> :text
LowCardinality(Nullable(UInt8))  -> :integer
Array(String)                    -> {:array, :text}
Array(Nullable(UInt64))          -> {:array, :integer}
```

| ClickHouse type | Lotus type |
|---|---|
| `UInt8/16/32/64/128/256`, `Int8/16/32/64/128/256` | `:integer` |
| `Float32`, `Float64` | `:float` |
| `Decimal`, `Decimal32/64/128/256`, `Decimal(P, S)` | `:decimal` |
| `String`, `FixedString(N)` | `:text` |
| `Date`, `Date32` | `:date` |
| `DateTime`, `DateTime64(N)` | `:datetime` |
| `Bool` | `:boolean` |
| `UUID` | `:uuid` |
| `JSON`, `Object('json')`, `Map(K, V)` | `:json` |
| `Enum8`, `Enum16` | `:enum` |
| `IPv4`, `IPv6` | `:text` |
| `Array(T)` | `{:array, <mapped T>}` |
| anything else | `:text` |

Types with no mapping fall to `:text`, which is the honest answer for a first release but does flatten some real distinctions: `Tuple(...)`, `Nested(...)`, `AggregateFunction(...)`, `Point`/`Ring`/`Polygon`, and the `Interval*` family all arrive as `:text` despite appearing in the editor's type vocabulary. `Map(K, V)` maps to `:json`, which is a closer fit than `:text` but not a structural one.

### Errors

`format_error/1` recognises `Ch.Error` — matched structurally, via `Module.concat([:Ch, :Error])`, so the dialect does not need `ch` compiled to refer to it — and renders `ClickHouse Error (<code>): <message>`, dropping to `ClickHouse Error: <message>` when there is no code. `DBConnection.ConnectionError` becomes `Connection error: <message>`. A binary passes through; anything else is `inspect/1`ed.

### AI context

`ai_context/0` supplies `:language`, `:example_query`, `:syntax_notes`, five `:error_patterns` (codes 60, 47, 62, 164/READONLY, and memory-limit failures) and a `:capabilities` map enabling generation, optimization and explanation.

The syntax notes steer a model away from patterns that perform badly on a column store: prefer `PREWHERE` where it prunes, avoid `SELECT *` on wide tables, use approximate aggregates on large data, treat `FINAL` as expensive, remember there are no transactions.

None of this reaches an LLM unless the host lists `Lotus.Source.Adapters.ClickHouse` in `config :lotus, :trusted_source_adapters`. Otherwise core strips the context to `:language` alone and logs an info-level message once. Core also caps the free-form fields — 2048 bytes for the example query, 1024 for the syntax notes, 20 error patterns — all of which this dialect is comfortably inside.

### Editor configuration

`Lotus.Source.Adapters.Ecto.Dialects.ClickHouse.EditorConfig` supplies the five required keys: the `sql:clickhouse` language, ClickHouse keywords, the type vocabulary including wrapper types, 370 function completions with `%{name, detail, args}` signatures, and `prewhere` / `final` / `sample` / `settings` / `format` as context boundaries.

The two optional keys are absent. `:context_schema` is for JSON DSLs and does not apply. `:dialect_spec` does apply — it forwards tokenizer options to CodeMirror's `SQLDialect.define()`, and CodeMirror ships no ClickHouse grammar for the language identifier to land on — so ClickHouse-specific tokenization, backtick identifiers in particular, is not currently declared.

## Test layout

`test/lotus_clickhouse/dialect_test.exs` is the only file that runs without a server: pure callbacks — quoting, placeholders, type mapping, statement transformation, deny lists, feature answers, editor config.

Everything else needs a live ClickHouse, and so does `test/test_helper.exs`, which connects and creates `test_users`, `test_posts` and `test_events` before the suite starts. There is no skip path; with no server the suite fails at boot. Lotus's own metadata tables live in an in-memory SQLite repo so that no second server is needed.

The integration files cover query execution and read-only enforcement (all five write verbs, plus the `read_only: false` escape), `EXPLAIN` plans, sanitization, introspection against real tables, alias resolution in `extract_accessed_resources/2`, filters and sorts against real rows, and pagination including the exact-count spec.

Tests are `async: false` throughout: ClickHouse has no `Ecto.Adapters.SQL.Sandbox`, so isolation is a `TRUNCATE` of the three test tables between tests. The docker-compose service publishes non-standard host ports — 9123 for HTTP, 9100 for the native protocol — and `config/test.exs` expects `localhost:9123`, database `lotus_test`, user `default`, password `clickhouse`.
