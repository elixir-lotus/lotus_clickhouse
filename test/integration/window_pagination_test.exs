defmodule Lotus.ClickHouse.Integration.WindowPaginationTest do
  use Lotus.ClickHouse.Case, async: false

  alias Lotus.ClickHouse.Test.Fixtures
  alias Lotus.Source.Adapters.ClickHouse, as: Adapter

  setup do
    Fixtures.insert_user(%{name: "Window A", email: "window_1@example.com", age: 20})
    Fixtures.insert_user(%{name: "Window B", email: "window_2@example.com", age: 25})
    Fixtures.insert_user(%{name: "Window C", email: "window_3@example.com", age: 30})
    Fixtures.insert_user(%{name: "Window D", email: "window_4@example.com", age: 35})
    Fixtures.insert_user(%{name: "Window E", email: "window_5@example.com", age: 40})

    :ok
  end

  describe "apply_window/4 pagination" do
    test "first page with limit" do
      base_sql = """
      SELECT name FROM test_users
      WHERE email LIKE 'window_%@example.com'
      ORDER BY name
      """

      {paged_sql, paged_params, meta} =
        Adapter.apply_window(Repo, base_sql, [], limit: 2, offset: 0, count: :none)

      assert paged_sql =~ "LIMIT"
      assert paged_sql =~ "OFFSET"

      assert {:ok, result} =
               Adapter.execute_query(Repo, paged_sql, paged_params, [])

      assert result.num_rows == 2
      assert [["Window A"], ["Window B"]] = result.rows

      assert %{limit: 2, offset: 0} = meta.window
    end

    test "second page with offset" do
      base_sql = """
      SELECT name FROM test_users
      WHERE email LIKE 'window_%@example.com'
      ORDER BY name
      """

      {paged_sql, paged_params, _meta} =
        Adapter.apply_window(Repo, base_sql, [], limit: 2, offset: 2, count: :none)

      assert {:ok, result} =
               Adapter.execute_query(Repo, paged_sql, paged_params, [])

      assert result.num_rows == 2
      assert [["Window C"], ["Window D"]] = result.rows
    end

    test "last page returns remaining rows" do
      base_sql = """
      SELECT name FROM test_users
      WHERE email LIKE 'window_%@example.com'
      ORDER BY name
      """

      {paged_sql, paged_params, _meta} =
        Adapter.apply_window(Repo, base_sql, [], limit: 2, offset: 4, count: :none)

      assert {:ok, result} =
               Adapter.execute_query(Repo, paged_sql, paged_params, [])

      assert result.num_rows == 1
      assert [["Window E"]] = result.rows
    end

    test "exact count mode includes total_count metadata" do
      base_sql = """
      SELECT name FROM test_users
      WHERE email LIKE 'window_%@example.com'
      ORDER BY name
      """

      {_paged_sql, _paged_params, meta} =
        Adapter.apply_window(Repo, base_sql, [], limit: 2, offset: 0, count: :exact)

      assert %{limit: 2, offset: 0} = meta.window
      assert meta.total_mode == :exact
      assert meta.total_count == :pending

      # The count_sql should be valid and executable
      assert {:ok, count_result} =
               Adapter.execute_query(Repo, meta.count_sql, meta.count_params, [])

      assert count_result.num_rows == 1
      [[total]] = count_result.rows
      assert total == 5
    end
  end
end
