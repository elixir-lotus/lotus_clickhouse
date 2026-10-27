defmodule Lotus.ClickHouse.Integration.DeniedFunctionsTest do
  @moduledoc """
  Runs statements through the whole Lotus pipeline (sanitize, preflight,
  execution) against the live server: every function the dialect denies is
  refused before it reaches ClickHouse, however it is written.
  """

  use Lotus.ClickHouse.Case, async: false

  alias Lotus.Source.Adapters.Ecto.Dialects.ClickHouse, as: Dialect

  defp run(sql), do: Lotus.run_statement(sql, [], repo: "clickhouse")

  defp assert_refused(sql, name) do
    assert {:error, message} = run(sql), "expected #{inspect(sql)} to be refused"
    assert message == "Only read-only queries are allowed: #{name}() is not", message
  end

  # One call of each denied function, as ClickHouse 24.8 takes it, and the
  # name the refusal gives.
  @calls [
    {"SELECT * FROM file('data.csv')", "file"},
    {"SELECT file('data.csv')", "file"},
    {"SELECT * FROM fileCluster('default', 'data.csv')", "filecluster"},
    {"SELECT * FROM s3('https://bucket.s3.amazonaws.com/data.csv')", "s3"},
    {"SELECT * FROM s3Cluster('default', 'https://bucket.s3.amazonaws.com/d.csv')", "s3cluster"},
    {"SELECT * FROM gcs('https://storage.googleapis.com/b/d.csv')", "gcs"},
    {"SELECT * FROM cosn('https://b.cos.myqcloud.com/d.csv')", "cosn"},
    {"SELECT * FROM oss('https://b.oss.aliyuncs.com/d.csv')", "oss"},
    {"SELECT * FROM azureBlobStorage('conn', 'container', 'd.csv')", "azureblobstorage"},
    {"SELECT * FROM azureBlobStorageCluster('default', 'conn', 'c', 'd.csv')",
     "azureblobstoragecluster"},
    {"SELECT * FROM hdfs('hdfs://nn:9000/d.csv')", "hdfs"},
    {"SELECT * FROM hdfsCluster('default', 'hdfs://nn:9000/d.csv')", "hdfscluster"},
    {"SELECT * FROM hive('thrift://h:9083', 'db', 't', 'a String', 'a')", "hive"},
    {"SELECT * FROM deltaLake('https://bucket/table')", "deltalake"},
    {"SELECT * FROM iceberg('https://bucket/table')", "iceberg"},
    {"SELECT * FROM hudi('https://bucket/table')", "hudi"},
    {"SELECT * FROM url('http://example.com/data.csv')", "url"},
    {"SELECT * FROM urlCluster('default', 'http://example.com/data.csv')", "urlcluster"},
    {"SELECT * FROM remote('other:9000', system.one)", "remote"},
    {"SELECT * FROM remoteSecure('other:9440', system.one)", "remotesecure"},
    {"SELECT * FROM cluster('default', system.one)", "cluster"},
    {"SELECT * FROM clusterAllReplicas('default', system.one)", "clusterallreplicas"},
    {"SELECT * FROM mysql('db:3306', 'app', 'users', 'u', 'p')", "mysql"},
    {"SELECT * FROM postgresql('db:5432', 'app', 'users', 'u', 'p')", "postgresql"},
    {"SELECT * FROM mongodb('db:27017', 'app', 'users', 'u', 'p', 'a String')", "mongodb"},
    {"SELECT * FROM redis('db:6379', 'k', 'k String')", "redis"},
    {"SELECT * FROM sqlite('/tmp/app.db', 'users')", "sqlite"},
    {"SELECT * FROM jdbc('jdbc:mysql://db/app', 'users')", "jdbc"},
    {"SELECT * FROM odbc('DSN=app', 'users')", "odbc"},
    {"SELECT * FROM executable('script.sh', 'TSV', 'a String')", "executable"},
    {"SELECT * FROM input('a String')", "input"},
    {"SELECT * FROM merge('lotus_test', '.*')", "merge"},
    {"SELECT * FROM mergeTreeIndex('lotus_test', 'test_users')", "mergetreeindex"},
    {"SELECT * FROM loop('lotus_test', 'test_users') LIMIT 1", "loop"},
    {"SELECT * FROM timeSeriesData('lotus_test', 'ts')", "timeseriesdata"},
    {"SELECT * FROM dictionary('dict')", "dictionary"},
    {"SELECT dictGet('dict', 'name', 1)", "dictget"},
    {"SELECT dictGetOrDefault('dict', 'name', 1, '')", "dictgetordefault"},
    {"SELECT dictHas('dict', 1)", "dicthas"},
    {"SELECT dictIsIn('dict', 1, 2)", "dictisin"},
    {"SELECT joinGet('lotus_test.j', 'v', 1)", "joinget"},
    {"SELECT joinGetOrNull('lotus_test.j', 'v', 1)", "joingetornull"},
    {"SELECT hasColumnInTable('system', 'users', 'name')", "hascolumnintable"},
    {"SELECT catboostEvaluate('/model.bin', 1)", "catboostevaluate"},
    {"SELECT sleep(1)", "sleep"},
    {"SELECT sleepEachRow(1) FROM numbers(3)", "sleepeachrow"}
  ]

  describe "denied functions" do
    for {sql, name} <- @calls do
      test "refuses #{sql}" do
        assert_refused(unquote(sql), unquote(name))
      end
    end

    test "every denied name has a call above" do
      patterns =
        Enum.map(Dialect.denied_functions(), fn name ->
          ~r/\A#{name |> Regex.escape() |> String.replace("\\*", "\\w*")}\z/
        end)

      for pattern <- patterns do
        assert Enum.any?(@calls, fn {_sql, name} -> Regex.match?(pattern, name) end),
               "no test calls #{Regex.source(pattern)}"
      end
    end

    test "refuses them in any case" do
      assert_refused("SELECT FiLe('data.csv')", "file")
      assert_refused("SELECT * FROM URL('http://example.com/d.csv')", "url")
      assert_refused("SELECT DICTGET('dict', 'name', 1)", "dictget")
    end

    test "refuses a double-quoted name, which ClickHouse calls" do
      assert_refused(~s{SELECT "file"('data.csv')}, "file")
    end

    test "refuses a backtick-quoted name, which ClickHouse calls" do
      assert_refused("SELECT `file`('data.csv')", "file")
      assert_refused("SELECT * FROM `remote`('other:9000', system.one)", "remote")
    end

    test "refuses a call with space before the parenthesis" do
      assert_refused("SELECT file ('data.csv')", "file")
    end

    test "refuses a call after a backslash-escaped quote" do
      assert_refused(~S"SELECT 'it\'s', file('data.csv') -- '", "file")
    end

    test "refuses a call on the line after a # comment" do
      assert_refused("SELECT 1 # don't\n, file('data.csv')", "file")
    end
  end

  describe "functions left alone" do
    test "generators and local table functions run" do
      assert {:ok, %{rows: [[0], [1]]}} = run("SELECT * FROM numbers(2)")
      assert {:ok, %{rows: [[1]]}} = run("SELECT * FROM values('a UInt8', 1)")
      assert {:ok, %{num_rows: 1}} = run("SELECT * FROM generateRandom('a Int8') LIMIT 1")
    end

    test "a -Merge combinator or a longer name is not a denied function" do
      assert {:ok, %{rows: [[3]]}} =
               run("SELECT uniqMerge(s) FROM (SELECT uniqState(number) AS s FROM numbers(3))")

      assert {:ok, %{rows: [["example.com"]]}} =
               run("SELECT domain('http://example.com/') AS url")
    end

    test "a name in a string, a comment or as an alias is not a call" do
      assert {:ok, %{rows: [["file('x')"]]}} = run("SELECT 'file(''x'')' AS file")
      assert {:ok, %{rows: [[1]]}} = run("SELECT 1 -- file('x')")
      assert {:ok, %{rows: [[1]]}} = run("SELECT 1 # file('x')")
    end

    test "system tables stay refused by visibility, inside view() too" do
      assert {:error, "Query touches blocked table(s): system.users"} =
               run("SELECT * FROM system.users")

      assert {:error, "Query touches blocked table(s): system.users"} =
               run("SELECT * FROM view(SELECT name FROM system.users)")
    end
  end
end
