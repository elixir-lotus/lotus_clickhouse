defmodule Lotus.ClickHouse.Integration.QueryExecutionTest do
  use Lotus.ClickHouse.Case, async: false

  alias Lotus.ClickHouse.Test.Fixtures
  alias Lotus.Query.Statement
  alias Lotus.Source.Adapters.ClickHouse, as: Adapter

  defp stmt(sql), do: %Statement{adapter: Adapter, text: sql, params: []}

  describe "simple query execution" do
    test "returns columns, rows, num_rows" do
      assert {:ok, result} = Adapter.execute_query(Repo, "SELECT 1 AS a, 2 AS b", [], [])
      assert result.columns == ["a", "b"]
      assert result.rows == [[1, 2]]
      assert result.num_rows == 1
    end

    test "returns multiple rows" do
      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 "SELECT number FROM system.numbers LIMIT 3",
                 [],
                 read_only: false
               )

      assert result.columns == ["number"]
      assert result.num_rows == 3
      assert result.rows == [[0], [1], [2]]
    end

    test "returns error for bad SQL" do
      assert {:error, msg} = Adapter.execute_query(Repo, "SELECT FROM WHERE", [], [])
      assert is_binary(msg)
      assert msg =~ "ClickHouse Error"
    end
  end

  describe "query execution with real data" do
    setup do
      u1 = Fixtures.insert_user(%{name: "Alice", email: "alice@test.com", age: 25, active: 1})
      u2 = Fixtures.insert_user(%{name: "Bob", email: "bob@test.com", age: 35, active: 1})
      u3 = Fixtures.insert_user(%{name: "Charlie", email: "charlie@test.com", age: 28, active: 0})

      %{users: [u1, u2, u3]}
    end

    test "queries inserted data back with parameterized WHERE", %{users: [u1 | _]} do
      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 "SELECT name, email FROM test_users WHERE id = {$0:UInt64}",
                 [u1.id],
                 []
               )

      assert result.columns == ["name", "email"]
      assert result.num_rows == 1
      assert [[u1.name, u1.email]] == result.rows
    end

    test "queries multiple rows with filter" do
      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 "SELECT name FROM test_users WHERE active = 1 ORDER BY name",
                 [],
                 []
               )

      assert result.num_rows == 2
      assert [["Alice"], ["Bob"]] = result.rows
    end

    test "handles NULL values correctly" do
      # Insert with NULL age via raw SQL (ClickHouse requires explicit NULL)
      id = System.unique_integer([:positive])

      Repo.query!(
        "INSERT INTO test_users (id, name, email, age) VALUES (#{id}, 'NullUser', 'null@test.com', NULL)"
      )

      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 "SELECT name, age FROM test_users WHERE email = {$0:String}",
                 ["null@test.com"],
                 []
               )

      assert result.num_rows == 1
      assert [["NullUser", nil]] = result.rows
    end

    test "aggregation queries" do
      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 "SELECT count() AS cnt, avg(age) AS avg_age FROM test_users WHERE active = 1",
                 [],
                 []
               )

      assert result.columns == ["cnt", "avg_age"]
      assert result.num_rows == 1
      [[count, avg_age]] = result.rows
      assert count == 2
      assert avg_age == 30.0
    end

    test "GROUP BY queries" do
      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 """
                 SELECT active, count() AS cnt
                 FROM test_users
                 GROUP BY active
                 ORDER BY active
                 """,
                 [],
                 []
               )

      assert result.columns == ["active", "cnt"]
      assert result.num_rows == 2
      assert [[0, 1], [1, 2]] = result.rows
    end
  end

  describe "query execution with posts (JOINs)" do
    setup do
      user = Fixtures.insert_user(%{name: "Author", email: "author@test.com"})

      p1 =
        Fixtures.insert_post(%{
          title: "First Post",
          content: "Hello",
          user_id: user.id,
          published: 1,
          view_count: 100
        })

      p2 =
        Fixtures.insert_post(%{
          title: "Second Post",
          content: "World",
          user_id: user.id,
          published: 0,
          view_count: 50
        })

      p3 =
        Fixtures.insert_post(%{
          title: "Third Post",
          content: "Foo",
          user_id: user.id,
          published: 1,
          view_count: 200
        })

      %{user: user, posts: [p1, p2, p3]}
    end

    test "JOIN queries return correct results", %{user: _user} do
      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 """
                 SELECT u.name, p.title
                 FROM test_users u
                 INNER JOIN test_posts p ON u.id = p.user_id
                 WHERE p.published = 1
                 ORDER BY p.title
                 """,
                 [],
                 []
               )

      assert result.columns == ["name", "title"]
      assert result.num_rows == 2
      assert [["Author", "First Post"], ["Author", "Third Post"]] = result.rows
    end

    test "subqueries return correct results", %{user: _user} do
      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 """
                 SELECT name FROM test_users
                 WHERE id IN (
                   SELECT user_id FROM test_posts WHERE published = 1
                 )
                 """,
                 [],
                 []
               )

      assert result.num_rows == 1
      assert [["Author"]] = result.rows
    end

    test "CTE queries return correct results" do
      assert {:ok, result} =
               Adapter.execute_query(
                 Repo,
                 """
                 WITH post_stats AS (
                   SELECT user_id, count() AS post_count, sum(view_count) AS total_views
                   FROM test_posts
                   GROUP BY user_id
                 )
                 SELECT u.name, ps.post_count, ps.total_views
                 FROM test_users u
                 INNER JOIN post_stats ps ON u.id = ps.user_id
                 """,
                 [],
                 []
               )

      assert result.columns == ["name", "post_count", "total_views"]
      assert result.num_rows == 1
      [row] = result.rows
      assert [_, 3, 350] = row
    end
  end

  describe "read-only enforcement" do
    test "blocks INSERT via ClickHouse readonly=1 by default" do
      assert {:error, msg} =
               Adapter.execute_query(
                 Repo,
                 "INSERT INTO test_users (id, name, email) VALUES (999, 'x', 'x@x.com')",
                 [],
                 []
               )

      assert msg =~ "READONLY"
    end

    test "blocks CREATE TABLE via readonly=1" do
      assert {:error, msg} =
               Adapter.execute_query(
                 Repo,
                 "CREATE TABLE should_not_exist (id UInt64) ENGINE = MergeTree() ORDER BY id",
                 [],
                 []
               )

      assert msg =~ "READONLY"
    end

    test "blocks DROP TABLE via readonly=1" do
      assert {:error, msg} =
               Adapter.execute_query(
                 Repo,
                 "DROP TABLE IF EXISTS test_users",
                 [],
                 []
               )

      assert msg =~ "READONLY"
    end

    test "blocks ALTER TABLE via readonly=1" do
      assert {:error, msg} =
               Adapter.execute_query(
                 Repo,
                 "ALTER TABLE test_users ADD COLUMN new_col String",
                 [],
                 []
               )

      assert msg =~ "READONLY"
    end

    test "blocks TRUNCATE via readonly=1" do
      assert {:error, msg} =
               Adapter.execute_query(
                 Repo,
                 "TRUNCATE TABLE test_users",
                 [],
                 []
               )

      assert msg =~ "READONLY"
    end

    test "allows writes when read_only: false" do
      id = System.unique_integer([:positive])

      assert {:ok, _} =
               Adapter.execute_query(
                 Repo,
                 "INSERT INTO test_users (id, name, email) VALUES (#{id}, 'writable', 'w@w.com')",
                 [],
                 read_only: false
               )
    end
  end

  describe "query_plan/4" do
    test "returns explain output for simple query" do
      assert {:ok, plan} = Adapter.query_plan(Repo, "SELECT 1", [], [])
      assert is_binary(plan)
      assert plan != ""
    end

    test "returns explain output for table query" do
      Fixtures.insert_user(%{name: "Explain", email: "explain@test.com"})

      assert {:ok, plan} =
               Adapter.query_plan(Repo, "SELECT * FROM test_users WHERE active = 1", [], [])

      assert is_binary(plan)
    end
  end

  describe "sanitize_query/3" do
    test "allows SELECT" do
      assert :ok = Adapter.sanitize_query(Repo, stmt("SELECT 1"), [])
    end

    test "allows complex SELECT" do
      sql = """
      SELECT u.name, p.title
      FROM test_users u
      JOIN test_posts p ON u.id = p.user_id
      WHERE u.active = 1
      LIMIT 10
      """

      assert :ok = Adapter.sanitize_query(Repo, stmt(sql), [])
    end

    test "blocks INSERT by default" do
      assert {:error, _} = Adapter.sanitize_query(Repo, stmt("INSERT INTO t VALUES (1)"), [])
    end

    test "blocks DELETE by default" do
      assert {:error, _} = Adapter.sanitize_query(Repo, stmt("DELETE FROM test_users"), [])
    end

    test "blocks multi-statement" do
      assert {:error, _} = Adapter.sanitize_query(Repo, stmt("SELECT 1; DROP TABLE t"), [])
    end

    test "allows DML when read_only: false" do
      assert :ok =
               Adapter.sanitize_query(Repo, stmt("INSERT INTO t VALUES (1)"), read_only: false)
    end
  end

  describe "health_check/1" do
    test "returns :ok when ClickHouse is running" do
      assert :ok = Adapter.health_check(Repo)
    end
  end

  describe "error handling" do
    test "format_error returns readable string for ClickHouse errors" do
      error = %Ch.Error{code: 62, message: "Syntax error"}
      assert Adapter.format_error(Repo, error) =~ "ClickHouse Error (62)"
    end

    test "handled_errors includes Ch.Error" do
      errors = Adapter.handled_errors(Repo)
      assert Ch.Error in errors
    end
  end
end
