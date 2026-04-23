# Lotus ClickHouse

**ClickHouse source adapter for [Lotus](https://github.com/elixir-lotus/lotus).** Run Lotus queries, dashboards, and AI-assisted exploration against a ClickHouse cluster the same way you would against Postgres, MySQL, or SQLite.

## Features

- Full [Lotus source adapter](https://hexdocs.pm/lotus/source-adapters.html) implementation
- Schema introspection via ClickHouse `system.*` tables
- Type mapping for all major ClickHouse types (including `Nullable`, `LowCardinality`, `Array` wrappers)
- Server-enforced read-only mode via ClickHouse's `readonly=1` per-query setting
- Filter, sort, pagination, and variable substitution on the Lotus pipeline
- `EXPLAIN` plan generation via `query_plan/4`
- Full `Lotus.AI` integration — generation, optimization, and explanation capabilities with ClickHouse-specific syntax notes (PREWHERE, FINAL, approximate aggregations, column-oriented patterns)
- 300+ function completions in the query editor via the shipped `EditorConfig`

## Installation

Add `lotus_clickhouse` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:lotus, "~> 1.0"},
    {:lotus_clickhouse, "~> 1.0"}
  ]
end
```

## Configuration

### 1. Define an Ecto repo for ClickHouse

```elixir
# lib/my_app/clickhouse_repo.ex
defmodule MyApp.ClickHouseRepo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.ClickHouse
end
```

### 2. Configure the repo

```elixir
# config/config.exs
config :my_app, MyApp.ClickHouseRepo,
  hostname: "localhost",
  port: 8123,
  scheme: "http",
  database: "analytics",
  username: "default",
  password: "secret",
  pool_size: 5
```

### 3. Register the adapter with Lotus

```elixir
# config/config.exs
config :lotus,
  storage_repo: MyApp.Repo,
  default_source: "postgres",
  source_adapters: [Lotus.Source.Adapters.ClickHouse],
  data_sources: %{
    "postgres" => MyApp.Repo,
    "clickhouse" => MyApp.ClickHouseRepo
  }
```

### 4. Start the ClickHouse repo in your supervision tree

```elixir
# lib/my_app/application.ex
children = [
  MyApp.Repo,
  MyApp.ClickHouseRepo,
  # ...
]
```

### 5. Query your ClickHouse data

Visit `/lotus` in your Phoenix app, select the "clickhouse" data source, and run queries against your ClickHouse tables.

## Read-Only Safety

All queries executed through the adapter run with ClickHouse's `readonly=1` setting enabled by default. This is a **server-enforced** guarantee -- ClickHouse itself rejects any write operation (INSERT, CREATE, DROP, ALTER, TRUNCATE) with error code 164 (READONLY). This replaces the `SET TRANSACTION READ ONLY` pattern used by PostgreSQL and MySQL adapters.

## Guides

- [Installation](guides/installation.md) -- step-by-step setup
- [How It Works](guides/how-it-works.md) -- architecture and adapter internals

## Development

### Requirements

- Elixir 1.17+
- OTP 25+
- Docker (for ClickHouse test instance)

### Setup

```bash
git clone https://github.com/elixir-lotus/lotus_clickhouse.git
cd lotus_clickhouse
mix deps.get
docker compose up -d
mix test
```

### Running tests

```bash
# Start ClickHouse
docker compose up -d

# Run the full suite
mix test

# With trace output
mix test --trace
```

### Code quality

```bash
mix compile --warnings-as-errors
mix format --check-formatted
mix credo --strict
```

## License

MIT License. See [LICENSE](LICENSE) for details.
