defmodule Lotus.ClickHouse.AdapterTest do
  use ExUnit.Case, async: false

  alias Lotus.ClickHouse.Test.Repo
  alias Lotus.Query.Statement
  alias Lotus.Source.Adapter, as: AdapterStruct
  alias Lotus.Source.Adapters.ClickHouse, as: Adapter

  describe "can_handle?/1" do
    test "returns true for ClickHouse repo" do
      assert Adapter.can_handle?(Repo)
    end

    test "returns false for non-ClickHouse repo" do
      refute Adapter.can_handle?(Lotus.ClickHouse.Test.LotusRepo)
    end

    test "returns false for non-module" do
      refute Adapter.can_handle?("not a module")
      refute Adapter.can_handle?(123)
    end
  end

  describe "wrap/2" do
    test "creates adapter struct with correct fields" do
      adapter = Adapter.wrap("clickhouse", Repo)

      assert %AdapterStruct{} = adapter
      assert adapter.name == "clickhouse"
      assert adapter.module == Adapter
      assert adapter.state == Repo
      assert adapter.source_type == :clickhouse
    end
  end

  describe "source identity" do
    test "source_type returns :clickhouse" do
      assert Adapter.source_type(Repo) == :clickhouse
    end

    test "query_language returns sql:clickhouse" do
      assert Adapter.query_language(Repo) == "sql:clickhouse"
    end

    test "hierarchy_label returns Databases" do
      assert Adapter.hierarchy_label(Repo) == "Databases"
    end
  end

  describe "supports_feature?/2" do
    test "supports arrays" do
      assert Adapter.supports_feature?(Repo, :arrays)
    end

    test "supports json" do
      assert Adapter.supports_feature?(Repo, :json)
    end

    test "does not support schema_hierarchy" do
      refute Adapter.supports_feature?(Repo, :schema_hierarchy)
    end

    test "does not support search_path" do
      refute Adapter.supports_feature?(Repo, :search_path)
    end
  end

  describe "health_check/1" do
    test "returns :ok for running ClickHouse" do
      assert :ok = Adapter.health_check(Repo)
    end
  end

  describe "execute_query/4" do
    test "executes a simple SELECT" do
      assert {:ok, result} = Adapter.execute_query(Repo, "SELECT 1 AS num", [], [])
      assert result.columns == ["num"]
      assert result.rows == [[1]]
      assert result.num_rows == 1
    end

    test "returns error for invalid SQL" do
      assert {:error, message} = Adapter.execute_query(Repo, "INVALID SQL", [], [])
      assert is_binary(message)
    end
  end

  describe "SQL generation" do
    test "quote_identifier wraps in double quotes" do
      assert Adapter.quote_identifier(Repo, "users") == ~s("users")
    end

    test "quote_identifier escapes internal quotes" do
      assert Adapter.quote_identifier(Repo, ~s(my"col)) == ~s("my""col")
    end

    test "limit_query wraps statement" do
      statement = %Statement{adapter: Adapter, body: "SELECT * FROM users", params: []}

      assert %Statement{body: body} = Adapter.limit_query(Repo, statement, 10)
      assert body == "SELECT * FROM (SELECT * FROM users) AS t LIMIT 10"
    end
  end
end
