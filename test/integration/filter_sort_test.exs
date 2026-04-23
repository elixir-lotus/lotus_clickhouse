defmodule Lotus.ClickHouse.Integration.FilterSortTest do
  use Lotus.ClickHouse.Case, async: false

  alias Lotus.ClickHouse.Test.Fixtures
  alias Lotus.Query.Statement
  alias Lotus.Source.Adapter, as: AdapterStruct
  alias Lotus.Source.Adapters.ClickHouse, as: Adapter
  alias Lotus.Source.Adapters.Ecto.Dialects.ClickHouse, as: Dialect

  setup do
    Fixtures.insert_user(%{name: "Alice", email: "alice@sort.com", age: 30, active: 1})
    Fixtures.insert_user(%{name: "Bob", email: "bob@sort.com", age: 25, active: 1})
    Fixtures.insert_user(%{name: "Charlie", email: "charlie@sort.com", age: 35, active: 0})
    Fixtures.insert_user(%{name: "Diana", email: "diana@sort.com", age: 28, active: 1})
    Fixtures.insert_user(%{name: "Eve", email: "eve@sort.com", age: 32, active: 0})

    :ok
  end

  # NOTE: FilterInjector wraps the query in a CTE:
  #   WITH _base AS (<original>) SELECT * FROM _base WHERE ...
  # So the original query must SELECT all columns that filters reference.
  # In practice, Lotus users write `SELECT *` or include filter columns.

  defp stmt(sql, params \\ []),
    do: %Statement{adapter: Adapter, text: sql, params: params}

  describe "apply_filters/2 with real data" do
    test "filters by equality" do
      base_sql = "SELECT * FROM test_users WHERE email LIKE '%@sort.com' ORDER BY name"

      filtered =
        Dialect.apply_filters(stmt(base_sql), [
          %Lotus.Query.Filter{column: "active", op: :eq, value: 1}
        ])

      assert {:ok, result} =
               Adapter.execute_query(Repo, filtered.text, filtered.params, [])

      names = Enum.map(result.rows, fn row -> Enum.at(row, 1) end)
      assert "Alice" in names
      assert "Bob" in names
      assert "Diana" in names
      refute "Charlie" in names
      refute "Eve" in names
    end

    test "filters by greater than" do
      base_sql = "SELECT * FROM test_users WHERE email LIKE '%@sort.com' ORDER BY name"

      filtered =
        Dialect.apply_filters(stmt(base_sql), [
          %Lotus.Query.Filter{column: "age", op: :gt, value: 30}
        ])

      assert {:ok, result} =
               Adapter.execute_query(Repo, filtered.text, filtered.params, [])

      names = Enum.map(result.rows, fn row -> Enum.at(row, 1) end)
      assert "Charlie" in names
      assert "Eve" in names
      refute "Alice" in names
      refute "Bob" in names
    end

    test "filters by string LIKE" do
      base_sql = "SELECT * FROM test_users WHERE email LIKE '%@sort.com' ORDER BY name"

      filtered =
        Dialect.apply_filters(stmt(base_sql), [
          %Lotus.Query.Filter{column: "name", op: :like, value: "%li%"}
        ])

      assert {:ok, result} =
               Adapter.execute_query(Repo, filtered.text, filtered.params, [])

      names = Enum.map(result.rows, fn row -> Enum.at(row, 1) end)
      assert "Alice" in names
      assert "Charlie" in names
      refute "Bob" in names
    end

    test "multiple filters combined with AND" do
      base_sql = "SELECT * FROM test_users WHERE email LIKE '%@sort.com' ORDER BY name"

      filtered =
        Dialect.apply_filters(stmt(base_sql), [
          %Lotus.Query.Filter{column: "active", op: :eq, value: 1},
          %Lotus.Query.Filter{column: "age", op: :gte, value: 28}
        ])

      assert {:ok, result} =
               Adapter.execute_query(Repo, filtered.text, filtered.params, [])

      names = Enum.map(result.rows, fn row -> Enum.at(row, 1) end)
      assert "Alice" in names
      assert "Diana" in names
      refute "Bob" in names
      refute "Charlie" in names
    end
  end

  describe "apply_sorts/2 with real data" do
    test "sorts ascending by name" do
      base_sql = "SELECT name FROM test_users WHERE email LIKE '%@sort.com'"

      sorted =
        Dialect.apply_sorts(stmt(base_sql), [
          %Lotus.Query.Sort{column: "name", direction: :asc}
        ])

      assert {:ok, result} = Adapter.execute_query(Repo, sorted.text, sorted.params, [])

      names = Enum.map(result.rows, fn [name] -> name end)
      assert names == ["Alice", "Bob", "Charlie", "Diana", "Eve"]
    end

    test "sorts descending by age" do
      base_sql = "SELECT name, age FROM test_users WHERE email LIKE '%@sort.com'"

      sorted =
        Dialect.apply_sorts(stmt(base_sql), [
          %Lotus.Query.Sort{column: "age", direction: :desc}
        ])

      assert {:ok, result} = Adapter.execute_query(Repo, sorted.text, sorted.params, [])

      ages = Enum.map(result.rows, fn [_name, age] -> age end)
      assert ages == [35, 32, 30, 28, 25]
    end
  end

  describe "filters + sorts + pagination combined" do
    test "full pipeline: filter, sort, then paginate" do
      base_sql = "SELECT * FROM test_users WHERE email LIKE '%@sort.com'"

      paged =
        stmt(base_sql)
        |> Dialect.apply_filters([
          %Lotus.Query.Filter{column: "active", op: :eq, value: 1}
        ])
        |> Dialect.apply_sorts([
          %Lotus.Query.Sort{column: "age", direction: :asc}
        ])
        |> then(&AdapterStruct.apply_pagination(adapter_struct(), &1, limit: 2, offset: 0))

      assert {:ok, result} =
               Adapter.execute_query(Repo, paged.text, paged.params, [])

      assert result.num_rows == 2

      # Filtered to active=1 (Alice 30, Bob 25, Diana 28), sorted by age asc
      # Result has all columns from SELECT *, extract name and age by column index
      name_idx = Enum.find_index(result.columns, &(&1 == "name"))
      age_idx = Enum.find_index(result.columns, &(&1 == "age"))

      rows = Enum.map(result.rows, fn row -> {Enum.at(row, name_idx), Enum.at(row, age_idx)} end)
      assert rows == [{"Bob", 25}, {"Diana", 28}]
    end
  end

  defp adapter_struct do
    %AdapterStruct{
      name: "ch_test",
      module: Adapter,
      state: Repo,
      source_type: :clickhouse
    }
  end
end
