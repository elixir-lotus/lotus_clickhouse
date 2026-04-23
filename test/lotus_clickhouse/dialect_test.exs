defmodule Lotus.ClickHouse.DialectTest do
  use ExUnit.Case, async: true

  alias Lotus.Query.Statement
  alias Lotus.Source.Adapters.Ecto.Dialects.ClickHouse, as: Dialect

  describe "source identity" do
    test "source_type" do
      assert Dialect.source_type() == :clickhouse
    end

    test "ecto_adapter" do
      assert Dialect.ecto_adapter() == Ecto.Adapters.ClickHouse
    end

    test "query_language" do
      assert Dialect.query_language() == "sql:clickhouse"
    end
  end

  describe "quote_identifier/1" do
    test "wraps in double quotes" do
      assert Dialect.quote_identifier("users") == ~s("users")
    end

    test "escapes embedded double quotes" do
      assert Dialect.quote_identifier(~s(my"col)) == ~s("my""col")
    end
  end

  describe "param_placeholder/3" do
    test "generates 0-indexed typed placeholder" do
      assert Dialect.param_placeholder(1, "x", :text) == "{$0:String}"
      assert Dialect.param_placeholder(2, "y", :integer) == "{$1:Int64}"
      assert Dialect.param_placeholder(3, "z", :float) == "{$2:Float64}"
    end

    test "maps all Lotus types to ClickHouse param types" do
      assert Dialect.param_placeholder(1, nil, :boolean) == "{$0:Bool}"
      assert Dialect.param_placeholder(1, nil, :date) == "{$0:Date}"
      assert Dialect.param_placeholder(1, nil, :datetime) == "{$0:DateTime}"
      assert Dialect.param_placeholder(1, nil, :uuid) == "{$0:String}"
      assert Dialect.param_placeholder(1, nil, :decimal) == "{$0:String}"
      assert Dialect.param_placeholder(1, nil, nil) == "{$0:String}"
    end
  end

  describe "limit_offset_placeholders/2" do
    test "generates UInt64 placeholders" do
      assert Dialect.limit_offset_placeholders(3, 4) == {"{$2:UInt64}", "{$3:UInt64}"}
    end
  end

  describe "limit_query/2" do
    test "wraps statement in subquery with LIMIT" do
      sql = Dialect.limit_query("SELECT * FROM users", 10)
      assert sql == "SELECT * FROM (SELECT * FROM users) AS t LIMIT 10"
    end
  end

  describe "execute_in_transaction/3" do
    @describetag :integration

    test "executes callback and returns its result" do
      assert {:ok, 42} =
               Dialect.execute_in_transaction(Lotus.ClickHouse.Test.Repo, fn -> 42 end, [])
    end

    test "returns error tuple on exception" do
      assert {:error, _} =
               Dialect.execute_in_transaction(
                 Lotus.ClickHouse.Test.Repo,
                 fn -> raise "boom" end,
                 []
               )
    end
  end

  describe "format_error/1" do
    test "formats Ch.Error with code" do
      error = %Ch.Error{code: 62, message: "Syntax error"}
      assert Dialect.format_error(error) == "ClickHouse Error (62): Syntax error"
    end

    test "formats Ch.Error without code" do
      error = %Ch.Error{code: nil, message: "Something failed"}
      assert Dialect.format_error(error) == "ClickHouse Error: Something failed"
    end

    test "formats binary error" do
      assert Dialect.format_error("plain text") == "plain text"
    end
  end

  describe "handled_errors/0" do
    test "includes Ch.Error" do
      assert Ch.Error in Dialect.handled_errors()
    end

    test "includes DBConnection.ConnectionError" do
      assert DBConnection.ConnectionError in Dialect.handled_errors()
    end
  end

  describe "builtin_denies/1" do
    setup do
      %{denies: Dialect.builtin_denies(Lotus.ClickHouse.Test.Repo)}
    end

    test "denies system schema", %{denies: denies} do
      assert {"system", ~r/.*/} in denies
    end

    test "denies INFORMATION_SCHEMA", %{denies: denies} do
      assert {"INFORMATION_SCHEMA", ~r/.*/} in denies
    end

    test "denies lotus internal tables", %{denies: denies} do
      assert {nil, "lotus_queries"} in denies
      assert {nil, "lotus_dashboards"} in denies
    end
  end

  describe "builtin_schema_denies/1" do
    test "includes system schemas" do
      denies = Dialect.builtin_schema_denies(Lotus.ClickHouse.Test.Repo)
      assert "system" in denies
      assert "INFORMATION_SCHEMA" in denies
      assert "information_schema" in denies
    end
  end

  describe "default_schemas/1" do
    test "returns configured database" do
      schemas = Dialect.default_schemas(Lotus.ClickHouse.Test.Repo)
      assert [db] = schemas
      assert db =~ "lotus_test"
    end
  end

  describe "supports_feature?/1" do
    test "supports arrays and json" do
      assert Dialect.supports_feature?(:arrays)
      assert Dialect.supports_feature?(:json)
    end

    test "does not support postgres-specific features" do
      refute Dialect.supports_feature?(:schema_hierarchy)
      refute Dialect.supports_feature?(:search_path)
      refute Dialect.supports_feature?(:make_interval)
    end
  end

  describe "db_type_to_lotus_type/1" do
    test "integer types" do
      for type <-
            ~w(UInt8 UInt16 UInt32 UInt64 Int8 Int16 Int32 Int64 UInt128 UInt256 Int128 Int256) do
        assert Dialect.db_type_to_lotus_type(type) == :integer, "expected #{type} -> :integer"
      end
    end

    test "float types" do
      assert Dialect.db_type_to_lotus_type("Float32") == :float
      assert Dialect.db_type_to_lotus_type("Float64") == :float
    end

    test "decimal types" do
      assert Dialect.db_type_to_lotus_type("Decimal(10,2)") == :decimal
      assert Dialect.db_type_to_lotus_type("Decimal32(4)") == :decimal
      assert Dialect.db_type_to_lotus_type("Decimal64(8)") == :decimal
      assert Dialect.db_type_to_lotus_type("Decimal128(18)") == :decimal
    end

    test "string types" do
      assert Dialect.db_type_to_lotus_type("String") == :text
      assert Dialect.db_type_to_lotus_type("FixedString(32)") == :text
    end

    test "date and datetime types" do
      assert Dialect.db_type_to_lotus_type("Date") == :date
      assert Dialect.db_type_to_lotus_type("Date32") == :date
      assert Dialect.db_type_to_lotus_type("DateTime") == :datetime
      assert Dialect.db_type_to_lotus_type("DateTime64(3)") == :datetime
    end

    test "boolean type" do
      assert Dialect.db_type_to_lotus_type("Bool") == :boolean
    end

    test "uuid type" do
      assert Dialect.db_type_to_lotus_type("UUID") == :uuid
    end

    test "json types" do
      assert Dialect.db_type_to_lotus_type("JSON") == :json
      assert Dialect.db_type_to_lotus_type("Map(String,String)") == :json
    end

    test "enum types" do
      assert Dialect.db_type_to_lotus_type("Enum8('a'=1,'b'=2)") == :enum
      assert Dialect.db_type_to_lotus_type("Enum16('x'=1)") == :enum
    end

    test "Nullable wrapper delegates to inner type" do
      assert Dialect.db_type_to_lotus_type("Nullable(UInt32)") == :integer
      assert Dialect.db_type_to_lotus_type("Nullable(String)") == :text
      assert Dialect.db_type_to_lotus_type("Nullable(DateTime)") == :datetime
    end

    test "LowCardinality wrapper delegates to inner type" do
      assert Dialect.db_type_to_lotus_type("LowCardinality(String)") == :text
      assert Dialect.db_type_to_lotus_type("LowCardinality(UInt8)") == :integer
    end

    test "nested wrappers" do
      assert Dialect.db_type_to_lotus_type("LowCardinality(Nullable(String))") == :text
    end

    test "Array type" do
      assert Dialect.db_type_to_lotus_type("Array(String)") == {:array, :text}
      assert Dialect.db_type_to_lotus_type("Array(UInt64)") == {:array, :integer}
    end

    test "unknown type defaults to :text" do
      assert Dialect.db_type_to_lotus_type("IntervalDay") == :text
      assert Dialect.db_type_to_lotus_type("IPv4") == :text
    end
  end

  describe "transform_statement/1" do
    defp t(sql) do
      Dialect.transform_statement(%Statement{text: sql, params: []}).text
    end

    test "rewrites '%{{var}}%' into pipe concatenation" do
      assert t("SELECT * FROM users WHERE name LIKE '%{{q}}%'") ==
               "SELECT * FROM users WHERE name LIKE '%' || {{q}} || '%'"
    end

    test "rewrites '{{var}}%' (right wildcard)" do
      assert t("SELECT * FROM users WHERE name LIKE '{{q}}%'") ==
               "SELECT * FROM users WHERE name LIKE {{q}} || '%'"
    end

    test "rewrites '%{{var}}' (left wildcard)" do
      assert t("SELECT * FROM users WHERE name LIKE '%{{q}}'") ==
               "SELECT * FROM users WHERE name LIKE '%' || {{q}}"
    end

    test "strips single-quote wrapper around bare variable" do
      assert t("SELECT * FROM users WHERE email = '{{email}}'") ==
               "SELECT * FROM users WHERE email = {{email}}"
    end

    test "leaves plain string literals unchanged" do
      sql = "SELECT * FROM users WHERE email = 'user@example.com'"
      assert t(sql) == sql
    end

    test "leaves SQL with no templates unchanged" do
      sql = "SELECT 1 AS num"
      assert t(sql) == sql
    end
  end

  describe "editor_config/0" do
    test "returns sql language with all required keys" do
      config = Dialect.editor_config()
      required_keys = [:language, :keywords, :types, :functions, :context_boundaries]
      for key <- required_keys, do: assert(Map.has_key?(config, key), "missing key: #{key}")
      assert config.language == "sql"
    end

    test "includes ClickHouse-specific keywords" do
      config = Dialect.editor_config()
      keywords = Enum.map(config.keywords, &String.upcase/1)
      assert "PREWHERE" in keywords
      assert "FINAL" in keywords
      assert "SAMPLE" in keywords
      assert "SETTINGS" in keywords
      assert "FORMAT" in keywords
      assert "ENGINE" in keywords
    end

    test "includes ClickHouse type system" do
      config = Dialect.editor_config()
      types = config.types
      assert "UInt8" in types
      assert "UInt64" in types
      assert "Float64" in types
      assert "Array" in types
      assert "LowCardinality" in types
      assert "Nullable" in types
      assert "DateTime64" in types
    end

    test "includes comprehensive ClickHouse functions" do
      config = Dialect.editor_config()
      names = Enum.map(config.functions, & &1.name)
      assert "uniq" in names
      assert "uniqExact" in names
      assert "groupArray" in names
      assert "argMax" in names
      assert "quantile" in names
      assert "arrayJoin" in names
      assert "arrayMap" in names
      assert "arrayFilter" in names
      assert "toDate" in names
      assert "toDateTime" in names
      assert "formatDateTime" in names
      assert "splitByChar" in names
      assert "extractAll" in names
      assert "toUInt32" in names
      assert "toString" in names
      assert length(config.functions) >= 100
    end

    test "functions have required fields" do
      config = Dialect.editor_config()

      for func <- config.functions do
        assert is_binary(func.name), "function missing name"
        assert is_binary(func.detail), "function #{func.name} missing detail"
        assert is_binary(func.args), "function #{func.name} missing args"
      end
    end

    test "includes ClickHouse-specific context boundaries" do
      config = Dialect.editor_config()
      assert "prewhere" in config.context_boundaries
      assert "final" in config.context_boundaries
      assert "sample" in config.context_boundaries
      assert "settings" in config.context_boundaries
      assert "format" in config.context_boundaries
    end
  end
end
