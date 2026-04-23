defmodule Lotus.ClickHouse.Integration.WindowPaginationTest do
  use Lotus.ClickHouse.Case, async: false

  alias Lotus.ClickHouse.Test.Fixtures
  alias Lotus.Query.Statement
  alias Lotus.Source.Adapter, as: AdapterStruct
  alias Lotus.Source.Adapters.ClickHouse, as: Adapter

  setup do
    Fixtures.insert_user(%{name: "Window A", email: "window_1@example.com", age: 20})
    Fixtures.insert_user(%{name: "Window B", email: "window_2@example.com", age: 25})
    Fixtures.insert_user(%{name: "Window C", email: "window_3@example.com", age: 30})
    Fixtures.insert_user(%{name: "Window D", email: "window_4@example.com", age: 35})
    Fixtures.insert_user(%{name: "Window E", email: "window_5@example.com", age: 40})

    :ok
  end

  defp stmt(sql),
    do: %Statement{adapter: Adapter, text: sql, params: []}

  defp adapter_struct do
    %AdapterStruct{
      name: "ch_test",
      module: Adapter,
      state: Repo,
      source_type: :clickhouse
    }
  end

  describe "apply_pagination/3" do
    test "first page with limit" do
      base_sql = """
      SELECT name FROM test_users
      WHERE email LIKE 'window_%@example.com'
      ORDER BY name
      """

      paged =
        AdapterStruct.apply_pagination(adapter_struct(), stmt(base_sql), limit: 2, offset: 0)

      assert paged.text =~ "LIMIT"
      assert paged.text =~ "OFFSET"

      assert {:ok, result} = Adapter.execute_query(Repo, paged.text, paged.params, [])

      assert result.num_rows == 2
      assert [["Window A"], ["Window B"]] = result.rows
    end

    test "second page with offset" do
      base_sql = """
      SELECT name FROM test_users
      WHERE email LIKE 'window_%@example.com'
      ORDER BY name
      """

      paged =
        AdapterStruct.apply_pagination(adapter_struct(), stmt(base_sql), limit: 2, offset: 2)

      assert {:ok, result} = Adapter.execute_query(Repo, paged.text, paged.params, [])

      assert result.num_rows == 2
      assert [["Window C"], ["Window D"]] = result.rows
    end

    test "last page returns remaining rows" do
      base_sql = """
      SELECT name FROM test_users
      WHERE email LIKE 'window_%@example.com'
      ORDER BY name
      """

      paged =
        AdapterStruct.apply_pagination(adapter_struct(), stmt(base_sql), limit: 2, offset: 4)

      assert {:ok, result} = Adapter.execute_query(Repo, paged.text, paged.params, [])

      assert result.num_rows == 1
      assert [["Window E"]] = result.rows
    end

    test "exact count mode records a count_spec in statement meta" do
      base_sql = """
      SELECT name FROM test_users
      WHERE email LIKE 'window_%@example.com'
      ORDER BY name
      """

      paged =
        AdapterStruct.apply_pagination(adapter_struct(), stmt(base_sql),
          limit: 2,
          offset: 0,
          count: :exact
        )

      count_spec = paged.meta[:count_spec]
      assert is_map(count_spec)
      assert is_binary(count_spec.query)

      # count_spec is executable through the same adapter and yields the total.
      assert {:ok, count_result} =
               Adapter.execute_query(Repo, count_spec.query, count_spec.params, [])

      assert count_result.num_rows == 1
      [[total]] = count_result.rows
      assert total == 5
    end
  end
end
