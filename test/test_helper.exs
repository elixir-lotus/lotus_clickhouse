Application.ensure_all_started(:ecto_sqlite3)

# SQLite repo for Lotus internal tables (in-memory, no storage_up needed)
{:ok, _} = Lotus.ClickHouse.Test.LotusRepo.start_link()

sqlite_migrations = Path.join([File.cwd!(), "test/support/sqlite/migrations"])

_ =
  Ecto.Migrator.run(Lotus.ClickHouse.Test.LotusRepo, sqlite_migrations, :up,
    all: true,
    log: false
  )

# ClickHouse repo for adapter tests
{:ok, _} = Lotus.ClickHouse.Test.Repo.start_link()

# Create test tables in ClickHouse
Lotus.ClickHouse.Test.Migrations.up()

ExUnit.start()
