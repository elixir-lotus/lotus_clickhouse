defmodule Lotus.ClickHouse.Integration.PreflightTest do
  use ExUnit.Case, async: false

  alias Lotus.ClickHouse.Test.Repo
  alias Lotus.Query.Statement
  alias Lotus.Source.Adapter, as: AdapterBehaviour
  alias Lotus.Source.Adapters.ClickHouse, as: Adapter
  alias Lotus.Source.Adapters.Ecto.Dialects.ClickHouse, as: Dialect

  defp stmt(sql), do: %Statement{adapter: Adapter, text: sql, params: []}

  @ch_adapter Adapter.wrap("clickhouse", Repo)

  describe "ClickHouse adapter registration" do
    test "wrap creates correct adapter struct" do
      assert %Lotus.Source.Adapter{} = @ch_adapter
      assert @ch_adapter.name == "clickhouse"
      assert @ch_adapter.module == Adapter
      assert @ch_adapter.source_type == :clickhouse
    end

    test "source_type dispatches correctly" do
      assert AdapterBehaviour.source_type(@ch_adapter) == :clickhouse
    end

    test "query_language dispatches correctly" do
      assert AdapterBehaviour.query_language(@ch_adapter) == "sql:clickhouse"
    end
  end

  describe "ClickHouse adapter dispatch — execute_query" do
    test "executes simple query via adapter dispatch" do
      assert {:ok, result} =
               AdapterBehaviour.execute_query(@ch_adapter, "SELECT 1 AS num", [], [])

      assert result.columns == ["num"]
      assert result.rows == [[1]]
    end

    test "execute_query enforces read-only by default" do
      assert {:error, msg} =
               AdapterBehaviour.execute_query(
                 @ch_adapter,
                 "INSERT INTO test_users (id, name, email) VALUES (777, 'x', 'x@x.com')",
                 [],
                 []
               )

      assert msg =~ "READONLY"
    end
  end

  describe "ClickHouse adapter dispatch — introspection" do
    test "list_schemas returns real schemas" do
      {:ok, schemas} = AdapterBehaviour.list_schemas(@ch_adapter)
      assert is_list(schemas)
      refute Enum.empty?(schemas)
      refute "system" in schemas
    end

    test "list_tables returns real tables" do
      db = Repo.config()[:database]
      {:ok, tables} = AdapterBehaviour.list_tables(@ch_adapter, [db], [])
      table_names = Enum.map(tables, fn {_, name} -> name end)
      assert "test_users" in table_names
    end

    test "describe_table returns real column metadata" do
      db = Repo.config()[:database]
      {:ok, columns} = AdapterBehaviour.describe_table(@ch_adapter, db, "test_users")
      assert is_list(columns)
      names = Enum.map(columns, & &1.name)
      assert "id" in names
      assert "name" in names
    end

    test "resolve_table_namespace finds table in database" do
      db = Repo.config()[:database]
      {:ok, schema} = AdapterBehaviour.resolve_table_namespace(@ch_adapter, "test_users", [db])
      assert schema == db
    end
  end

  describe "ClickHouse adapter dispatch — SQL generation" do
    test "quote_identifier" do
      assert AdapterBehaviour.quote_identifier(@ch_adapter, "users") == ~s("users")
    end

    # `param_placeholder/3` and `limit_offset_placeholders/2` are Ecto-dialect
    # internals in v1 (not on the universal Adapter behaviour). Tested directly
    # on the Dialect module.
    test "param_placeholder (via Dialect)" do
      assert Dialect.param_placeholder(1, "x", :text) == "{$0:String}"
      assert Dialect.param_placeholder(2, "y", :integer) == "{$1:Int64}"
    end

    test "limit_offset_placeholders (via Dialect)" do
      {limit_ph, offset_ph} = Dialect.limit_offset_placeholders(1, 2)
      assert limit_ph == "{$0:UInt64}"
      assert offset_ph == "{$1:UInt64}"
    end
  end

  describe "ClickHouse adapter dispatch — safety" do
    test "builtin_denies includes system tables" do
      denies = AdapterBehaviour.builtin_denies(@ch_adapter)
      assert {"system", ~r/.*/} in denies
    end

    test "builtin_schema_denies includes system schemas" do
      denies = AdapterBehaviour.builtin_schema_denies(@ch_adapter)
      assert "system" in denies
      assert "INFORMATION_SCHEMA" in denies
    end

    test "sanitize_query blocks DML" do
      assert {:error, _} =
               AdapterBehaviour.sanitize_query(@ch_adapter, stmt("DROP TABLE test_users"), [])
    end

    test "sanitize_query allows SELECT" do
      assert :ok =
               AdapterBehaviour.sanitize_query(@ch_adapter, stmt("SELECT * FROM test_users"), [])
    end
  end

  describe "ClickHouse adapter dispatch — lifecycle" do
    test "health_check succeeds" do
      assert :ok = AdapterBehaviour.health_check(@ch_adapter)
    end

    test "disconnect returns ok" do
      assert :ok = AdapterBehaviour.disconnect(@ch_adapter)
    end
  end

  describe "ClickHouse adapter dispatch — features" do
    test "supports arrays" do
      assert AdapterBehaviour.supports_feature?(@ch_adapter, :arrays)
    end

    test "supports json" do
      assert AdapterBehaviour.supports_feature?(@ch_adapter, :json)
    end

    test "does not support search_path" do
      refute AdapterBehaviour.supports_feature?(@ch_adapter, :search_path)
    end

    test "hierarchy_label is Databases" do
      assert AdapterBehaviour.hierarchy_label(@ch_adapter) == "Databases"
    end
  end
end
