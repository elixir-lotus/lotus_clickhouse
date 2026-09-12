# Lotus ClickHouse

**ClickHouse source adapter for [Lotus](https://github.com/elixir-lotus/lotus).** Run Lotus queries, dashboards, and AI-assisted exploration against a ClickHouse cluster the same way you would against Postgres, MySQL, or SQLite.

A Lotus statement here is ordinary SQL text, but it is ClickHouse SQL: typed `{$0:Type}` placeholders instead of `$1`, no transactions, and a read-only guarantee the server enforces rather than the session — see [Writing Queries](guides/writing-queries.md).

> **0.1.0 — first release.** The adapter is complete against the `Lotus.Source.Adapters.Ecto.Dialect` contract in Lotus v1 and its integration suite runs against a live ClickHouse server, but its own surface — the type mapping, the editor configuration, the safety defaults — has no production users yet and may still move. Pin accordingly.

## Installation

Add both `lotus` and `lotus_clickhouse` to your `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 1.0"},
    {:lotus_clickhouse, "~> 0.1"}
  ]
end
```

This pulls in `ecto_ch` (the Ecto adapter for ClickHouse) and `ch` (the underlying HTTP driver). Requires Elixir 1.18 or later. CI runs the suite on Elixir 1.18, 1.19 and 1.20 against ClickHouse 24.8.

## Configuring a data source

A ClickHouse source is a plain Ecto repo, exactly like a Postgres one:

```elixir
defmodule MyApp.ClickHouseRepo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.ClickHouse
end
```

```elixir
config :my_app, MyApp.ClickHouseRepo,
  hostname: "localhost",
  port: 8123,
  scheme: "http",
  database: "analytics",
  username: "default",
  password: "secret",
  pool_size: 5

config :lotus,
  storage_repo: MyApp.Repo,
  default_source: "postgres",
  source_adapters: [Lotus.Source.Adapters.ClickHouse],
  data_sources: %{
    "postgres"   => MyApp.Repo,
    "clickhouse" => MyApp.ClickHouseRepo
  }
```

Listing the adapter in `:source_adapters` is what makes the repo resolvable. The generated `can_handle?/1` claims any repo whose `__adapter__/0` is `Ecto.Adapters.ClickHouse`, so `:data_sources` entries stay bare repo modules — no map form, no `:adapter` key.

Then start the repo in your supervision tree alongside your other repos. Full walkthrough in [Installation](guides/installation.md).

## What works

- **Query execution** through `repo.query/3`, returning `%{columns:, rows:, num_rows:}`. `execute_query/4` is the one callback this package overrides rather than inheriting, because ClickHouse has no transactions (see below).
- **Server-enforced read-only.** Every query goes out with ClickHouse's `readonly: 1` per-query setting, so the server rejects `INSERT` / `CREATE` / `DROP` / `ALTER` / `TRUNCATE` with error 164 (READONLY). That is a stronger guarantee than a session-level `SET TRANSACTION READ ONLY`, and it is checked by integration tests for all five statement kinds.
- **Typed parameters.** `param_placeholder/3` emits ClickHouse's `{$N:Type}` form (0-indexed), mapping Lotus type atoms to `String`, `Int64`, `Float64`, `Bool`, `Date` and `DateTime`. `limit_offset_placeholders/2` emits `UInt64`.
- **Filters, sorts and pagination** on the shared Ecto SQL injectors: filters wrap the statement in a `WITH _base AS (...)` CTE and append `WHERE`, sorts wrap it in `WITH _sorted AS (...)` and append `ORDER BY`, pagination wraps it in `SELECT * FROM (...) AS lotus_sub LIMIT ? OFFSET ?`. Supported operators are the core nine: `:eq`, `:neq`, `:gt`, `:lt`, `:gte`, `:lte`, `:like`, `:is_null`, `:is_not_null`.
- **Exact counts** via core's count-spec strategy: `count: :exact` puts a `SELECT COUNT(*) FROM (...)` statement in `statement.meta[:count_spec]` for the caller to run through the same adapter.
- **Statement rewriting** for Lotus's `{{var}}` templates — `'%{{q}}%'` becomes `'%' || {{q}} || '%'` (ClickHouse takes `||` as concatenation), and `'{{email}}'` sheds its quotes so the value binds as a parameter instead of landing inside a string literal.
- **Schema introspection** against `system.databases`, `system.tables` and `system.columns`. `describe_table/3` reports the raw ClickHouse type string, nullability (from the `Nullable(...)` wrapper), the default *kind* rather than the default expression, and primary-key membership from `is_in_primary_key`. Views and materialized views are excluded unless the caller asks for them.
- **Visibility preflight.** `extract_accessed_resources/2` runs `EXPLAIN AST` and scrapes `TableIdentifier` nodes, resolving aliases back to real table names, so Lotus's visibility rules are actually enforced for this source. If `EXPLAIN AST` fails it falls back to a `FROM` / `JOIN` regex over the SQL text.
- **Query plans.** `query_plan/3` runs plain `EXPLAIN` (also with `readonly: 1`) and joins the rows into one string.
- **Type mapping** covering the integer, float, decimal, string, date, UUID, JSON, map, enum and IP families, recursively through the `Nullable`, `LowCardinality` and `Array` wrappers. Anything unrecognised maps to `:text`.
- **AI integration** — `ai_context/0` declares `sql:clickhouse`, an example query, ClickHouse syntax notes (`PREWHERE`, `FINAL`, approximate aggregations, `SETTINGS`), error-pattern hints for codes 60, 47, 62 and 164 plus memory-limit failures, and `generation`, `optimization` and `explanation` all enabled.
- **Editor support** — 370 ClickHouse function completions with signatures, plus ClickHouse keywords, the full type vocabulary, and `prewhere` / `final` / `sample` / `settings` / `format` as context boundaries.

## What this adapter does differently, or not at all

- **No transactions.** `ecto_ch` does not implement `Ecto.Adapter.Transaction`. `execute_in_transaction/3` checks a connection out of the pool and runs the function on it; there is no rollback, and `execute_query/4` therefore bypasses core's shared helper, which expects `repo.rollback/1` to exist. In practice this costs nothing, because Lotus uses this source read-only.
- **No schema hierarchy.** `supports_feature?(:schema_hierarchy)` is `false`, the same answer MySQL gives: the database is configured on the repo rather than browsed, and `default_schemas/1` returns just that one database. `hierarchy_label/0` is still `"Databases"` for the label the UI prints. ClickHouse itself will happily run `other_db.table`, but a table outside the repo's database is not in `default_schemas/1`, so visibility rules have to allow it explicitly.
- **No search path.** `supports_feature?(:search_path)` is `false` and `set_search_path/2` is a no-op — a caller-supplied `:search_path` is ignored for this source.
- **No statement timeout.** `set_statement_timeout/2` is a no-op. The `:timeout` option bounds the HTTP client, not the server: a runaway query can keep burning ClickHouse CPU after the caller has given up. If that matters, put `SETTINGS max_execution_time = N` in the query, or set a server-side limit on the repo's `:settings` or the ClickHouse user profile.
- **No `make_interval`.** `supports_feature?(:make_interval)` is `false`, so core's Postgres `INTERVAL '{{n}} days'` rewrite does not apply. Write date arithmetic with ClickHouse functions instead — `subtractDays(today(), {{days}})`. See [Writing Queries](guides/writing-queries.md#dates-and-intervals).
- **Arrays are declared but not bound as one value.** `supports_feature?(:arrays)` is `true` because ClickHouse has a real `Array` type, but list variables still expand into N placeholders through core's shared SQL path. Binding a whole list as a single parameter is not something this dialect emits a type for.
- **Introspection reads `system.*`, which is also denied.** `builtin_denies/1` blocks the `system` database outright, so a query cannot read it — but the adapter's own introspection queries go straight to `repo.query!/2` and are not subject to those rules. That is the intended split; it is worth knowing the deny list is about *user* statements.
- **Identifier quoting is double quotes.** `quote_identifier/1` emits `"col"`, doubling any embedded `"`. ClickHouse accepts backticks too, and its own docs lean on them, but everything this adapter generates uses double quotes.

## Safety

Two independent layers, and they block different things.

**Core's SQL sanitizer** (`sanitize_query/3`, shared by every Ecto-backed adapter) rejects multi-statement input and, when `read_only` is set, any statement matching `\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|VACUUM|ANALYZE|CALL|LOCK)\b`. It is a keyword regex, so it is blunt in both directions: a column literally named `analyze_count` in a `SELECT` trips it, and it knows nothing of ClickHouse-specific mutations such as `OPTIMIZE` or `SYSTEM`.

**ClickHouse's `readonly=1`** is what actually stops writes. It is a server setting applied to every query the adapter executes, and it covers the ClickHouse-specific verbs the regex misses. Both layers are lifted together by `read_only: false`, which exists for controlled callers such as the test harness inserting fixtures.

Separately, `builtin_denies/1` hides relations from queries before any host visibility rule is consulted: the whole `system`, `INFORMATION_SCHEMA` and `information_schema` databases, plus the Ecto migration table (from the repo's `:migration_source`, defaulting to `schema_migrations`) and the six `lotus_*` metadata tables — each listed both unqualified and qualified with the repo's configured database. `builtin_schema_denies/1` keeps the same three system databases out of schema listings.

One caveat worth stating plainly: the AI syntax notes and error patterns above only reach the LLM prompt if you also list this adapter in `config :lotus, :trusted_source_adapters`. Otherwise core strips the context down to `:language` alone.

## Development

```bash
mix deps.get
mix test.setup   # docker compose up -d
mix test
```

The docker-compose service publishes ClickHouse on **non-standard host ports — 9123 for HTTP and 9100 for the native protocol** — so it does not collide with a ClickHouse you may already be running on 8123. The test repo in `config/test.exs` expects exactly that: `localhost:9123`, user `default`, password `clickhouse`, database `lotus_test`.

Nearly the whole suite needs that server. Only `test/lotus_clickhouse/dialect_test.exs` is pure; `test/test_helper.exs` connects and creates the `test_users`, `test_posts` and `test_events` tables before any test runs, so with no server up the suite fails at startup rather than skipping. Lotus's own metadata tables live in an in-memory SQLite repo, so no second server is needed. Tests are `async: false` throughout — ClickHouse has no `Ecto.Adapters.SQL.Sandbox`, so isolation is a `TRUNCATE` between tests.

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
```

## Guides

- [Installation](guides/installation.md) — step-by-step setup, connection options, ClickHouse Cloud.
- [Writing Queries](guides/writing-queries.md) — placeholders, variables, what the pipeline wraps around your SQL, and the ClickHouse-specific pitfalls.
- [How It Works](guides/how-it-works.md) — the adapter/dialect split and every callback, for anyone reading or extending the code.

## License

MIT — see [LICENSE](https://github.com/elixir-lotus/lotus_clickhouse/blob/main/LICENSE).
