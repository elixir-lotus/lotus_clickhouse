defmodule Lotus.ClickHouse.Integration.IntrospectionTest do
  use Lotus.ClickHouse.Case, async: false

  import Lotus.ClickHouse.Test.DenyAssertions

  alias Lotus.Source.Adapters.ClickHouse, as: Adapter

  @db_config_key :database

  defp test_database, do: Repo.config()[@db_config_key]

  describe "list_schemas/1" do
    test "includes the test database" do
      {:ok, schemas} = Adapter.list_schemas(Repo)
      assert is_list(schemas)
      assert test_database() in schemas
    end

    test "includes default database" do
      {:ok, schemas} = Adapter.list_schemas(Repo)
      assert "default" in schemas
    end

    test "excludes system schemas" do
      {:ok, schemas} = Adapter.list_schemas(Repo)
      refute "system" in schemas
      refute "INFORMATION_SCHEMA" in schemas
      refute "information_schema" in schemas
    end
  end

  describe "list_tables/3" do
    test "finds all test tables" do
      {:ok, tables} = Adapter.list_tables(Repo, [test_database()], [])
      table_names = Enum.map(tables, fn {_schema, name} -> name end)

      assert "test_users" in table_names
      assert "test_posts" in table_names
      assert "test_events" in table_names
    end

    test "returns {database, table} tuples" do
      db = test_database()
      {:ok, tables} = Adapter.list_tables(Repo, [db], [])

      assert Enum.all?(tables, fn {schema, _name} -> schema == db end)
    end

    test "returns empty list for non-existent database" do
      {:ok, tables} = Adapter.list_tables(Repo, ["nonexistent_db_xyz"], [])
      assert tables == []
    end

    test "supports multiple schemas" do
      {:ok, tables} = Adapter.list_tables(Repo, [test_database(), "default"], [])
      databases = tables |> Enum.map(fn {db, _} -> db end) |> Enum.uniq()
      assert test_database() in databases
    end
  end

  describe "describe_table/3" do
    test "returns column metadata for test_users" do
      db = test_database()
      {:ok, columns} = Adapter.describe_table(Repo, db, "test_users")

      assert is_list(columns)
      refute Enum.empty?(columns)

      names = Enum.map(columns, & &1.name)
      assert "id" in names
      assert "name" in names
      assert "email" in names
      assert "age" in names
      assert "active" in names
      assert "metadata" in names
      assert "inserted_at" in names
      assert "updated_at" in names
    end

    test "returns correct types" do
      db = test_database()
      {:ok, columns} = Adapter.describe_table(Repo, db, "test_users")

      by_name = Map.new(columns, &{&1.name, &1})

      assert by_name["id"].type =~ "UInt64"
      assert by_name["name"].type =~ "String"
      assert by_name["email"].type =~ "String"
      assert by_name["age"].type =~ "Nullable(UInt32)"
      assert by_name["active"].type =~ "UInt8"
    end

    test "detects nullable columns" do
      db = test_database()
      {:ok, columns} = Adapter.describe_table(Repo, db, "test_users")

      by_name = Map.new(columns, &{&1.name, &1})

      assert by_name["age"].nullable == true
      assert by_name["name"].nullable == false
      assert by_name["id"].nullable == false
    end

    test "identifies primary key columns" do
      db = test_database()
      {:ok, columns} = Adapter.describe_table(Repo, db, "test_users")

      pk_names = columns |> Enum.filter(& &1.primary_key) |> Enum.map(& &1.name)
      assert "id" in pk_names
    end

    test "returns column metadata for test_posts with array type" do
      db = test_database()
      {:ok, columns} = Adapter.describe_table(Repo, db, "test_posts")

      by_name = Map.new(columns, &{&1.name, &1})

      assert by_name["tags"].type =~ "Array(String)"
      assert by_name["content"].nullable == true
      assert by_name["published_at"].nullable == true
      assert by_name["view_count"].type =~ "UInt64"
    end

    test "returns columns for test_events with composite ORDER BY" do
      db = test_database()
      {:ok, columns} = Adapter.describe_table(Repo, db, "test_events")

      names = Enum.map(columns, & &1.name)
      assert "event_name" in names
      assert "user_id" in names
      assert "properties" in names
      assert "occurred_at" in names
    end
  end

  describe "resolve_table_namespace/3" do
    test "resolves existing table to its database" do
      db = test_database()
      {:ok, schema} = Adapter.resolve_table_namespace(Repo, "test_users", [db])
      assert schema == db
    end

    test "resolves from multiple candidate databases" do
      db = test_database()
      {:ok, schema} = Adapter.resolve_table_namespace(Repo, "test_users", ["default", db])
      assert schema == db
    end

    test "returns nil for non-existent table" do
      db = test_database()
      {:ok, schema} = Adapter.resolve_table_namespace(Repo, "nonexistent_xyz_table", [db])
      assert is_nil(schema)
    end
  end

  describe "default_schemas/1" do
    test "returns the configured database" do
      schemas = Adapter.default_schemas(Repo)
      assert [db] = schemas
      assert db == test_database()
    end
  end

  describe "builtin_denies/1" do
    test "denies system schema tables" do
      denies = Adapter.builtin_denies(Repo)
      assert denies_pattern?(denies, "system")
      assert denies_pattern?(denies, "INFORMATION_SCHEMA")
    end

    test "denies lotus internal tables" do
      denies = Adapter.builtin_denies(Repo)
      assert {nil, "lotus_queries"} in denies
      assert {nil, "lotus_dashboards"} in denies
      assert {nil, "lotus_dashboard_cards"} in denies
    end

    test "denies schema_migrations" do
      denies = Adapter.builtin_denies(Repo)
      assert {nil, "schema_migrations"} in denies
    end
  end
end
