import Config

# ClickHouse test repo — the adapter under test
config :lotus_clickhouse, Lotus.ClickHouse.Test.Repo,
  hostname: "localhost",
  port: 9123,
  scheme: "http",
  database: "lotus_test#{System.get_env("MIX_TEST_PARTITION")}",
  username: "default",
  password: "clickhouse",
  pool_size: 5,
  settings: []

# Lightweight SQLite repo for Lotus internal tables (queries, dashboards, etc.)
config :lotus_clickhouse, Lotus.ClickHouse.Test.LotusRepo,
  database: ":memory:",
  pool_size: 1

# Lotus core points at the SQLite repo for metadata storage
config :lotus, storage_repo: Lotus.ClickHouse.Test.LotusRepo
