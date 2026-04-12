# Installation

This guide walks through adding ClickHouse as a data source in your Lotus-powered Phoenix application.

## Prerequisites

- A Phoenix application with [Lotus](https://github.com/elixir-lotus/lotus/tree/refactor/pluggable-adapters) installed and configured
- A running ClickHouse instance (local, Docker, or cloud-hosted)
- Elixir 1.17+ / OTP 25+

## Step 1: Add the dependency

Add `lotus_clickhouse` to your `mix.exs`:

```elixir
defp deps do
  [
    {:lotus, "~> 0.16"},
    {:lotus_clickhouse, "~> 0.0.1"}
  ]
end
```

Then fetch:

```bash
mix deps.get
```

This pulls in `ecto_ch` (the Ecto adapter for ClickHouse) and `ch` (the underlying HTTP driver) automatically.

## Step 2: Define a ClickHouse Ecto repo

Create a repo module that uses the ClickHouse Ecto adapter:

```elixir
# lib/my_app/clickhouse_repo.ex
defmodule MyApp.ClickHouseRepo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.ClickHouse
end
```

## Step 3: Configure the repo

Add connection settings for your ClickHouse instance:

```elixir
# config/config.exs (or config/runtime.exs for production)
config :my_app, MyApp.ClickHouseRepo,
  hostname: "localhost",
  port: 8123,
  scheme: "http",
  database: "default",
  username: "default",
  password: "",
  pool_size: 5
```

### Connection options

| Option | Default | Description |
|---|---|---|
| `:hostname` | `"localhost"` | ClickHouse server hostname |
| `:port` | `8123` | HTTP interface port |
| `:scheme` | `"http"` | `"http"` or `"https"` |
| `:database` | `"default"` | Default database to connect to |
| `:username` | `"default"` | ClickHouse user |
| `:password` | `""` | User password |
| `:pool_size` | `5` | Connection pool size |
| `:settings` | `[]` | ClickHouse settings (keyword list) |

## Step 4: Register the adapter with Lotus

Tell Lotus about the ClickHouse adapter and add your ClickHouse repo as a data source:

```elixir
# config/config.exs
config :lotus,
  ecto_repo: MyApp.Repo,            # Where Lotus stores its metadata (PostgreSQL/SQLite)
  default_source: "postgres",        # Your default data source
  source_adapters: [Lotus.Source.Adapters.ClickHouse],
  data_sources: %{
    "postgres" => MyApp.Repo,
    "clickhouse" => MyApp.ClickHouseRepo
  }
```

The `source_adapters` key tells the Lotus source resolver to try `Lotus.Source.Adapters.ClickHouse` when matching repos to adapters. The adapter's `can_handle?/1` callback recognizes any repo using `Ecto.Adapters.ClickHouse`.

## Step 5: Start the repo

Add your ClickHouse repo to your application's supervision tree:

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    MyApp.ClickHouseRepo,
    {Lotus.Supervisor, []},
    MyAppWeb.Endpoint
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Step 6: Verify

Start your Phoenix app and visit the Lotus dashboard. The ClickHouse data source should appear in the source selector. Try a simple query:

```sql
SELECT version()
```

If you see the ClickHouse version string, the adapter is working correctly.

## Multiple ClickHouse instances

You can register multiple ClickHouse databases by creating separate repos:

```elixir
config :lotus,
  source_adapters: [Lotus.Source.Adapters.ClickHouse],
  data_sources: %{
    "postgres" => MyApp.Repo,
    "analytics" => MyApp.AnalyticsRepo,     # ClickHouse analytics cluster
    "logs" => MyApp.LogsRepo                # ClickHouse logs cluster
  }
```

Each repo can point to a different ClickHouse instance with its own credentials and database.

## ClickHouse Cloud

For ClickHouse Cloud or any TLS-enabled ClickHouse instance, use HTTPS:

```elixir
config :my_app, MyApp.ClickHouseRepo,
  hostname: "abc123.clickhouse.cloud",
  port: 8443,
  scheme: "https",
  database: "default",
  username: "default",
  password: System.get_env("CLICKHOUSE_PASSWORD"),
  pool_size: 5
```

## Docker setup for development

If you need a local ClickHouse for development, add a `docker-compose.yml`:

```yaml
services:
  clickhouse:
    image: clickhouse/clickhouse-server:24.8
    ports:
      - "8123:8123"
    environment:
      CLICKHOUSE_DB: default
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: clickhouse
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
```

```bash
docker compose up -d
```

## Next steps

- Read [How It Works](how-it-works.md) to understand the adapter architecture
- Check the [Lotus configuration guide](https://hexdocs.pm/lotus/configuration.html) for visibility rules and caching
- See the [Lotus source adapters guide](https://hexdocs.pm/lotus/source-adapters.html) for advanced adapter patterns
