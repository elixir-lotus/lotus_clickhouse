# The connection form is Lotus v2's (`Lotus.Source.Connections`); under
# Lotus v1 there is nothing to test.
if Code.ensure_loaded?(Lotus.Source.Adapter.Connection) do
  defmodule Lotus.ClickHouse.ConnectionTest do
    use ExUnit.Case, async: false

    alias Lotus.Source.Adapters.ClickHouse
    alias Lotus.Source.Connections

    @settings Application.compile_env!(:lotus_clickhouse, Lotus.ClickHouse.Test.Repo)

    defp form(overrides \\ %{}) do
      Map.merge(
        %{
          "hostname" => @settings[:hostname],
          "port" => to_string(@settings[:port] || 8123),
          "database" => @settings[:database],
          "username" => @settings[:username],
          "password" => @settings[:password]
        },
        overrides
      )
    end

    setup do
      previous = Application.get_env(:lotus, :source_adapters)
      Application.put_env(:lotus, :source_adapters, [ClickHouse])
      Lotus.Config.reload!()

      on_exit(fn ->
        if previous,
          do: Application.put_env(:lotus, :source_adapters, previous),
          else: Application.delete_env(:lotus, :source_adapters)

        Lotus.Config.reload!()
      end)
    end

    test "offers a ClickHouse form" do
      assert %{label: "ClickHouse", module: ClickHouse, fields: fields} =
               Connections.kind("clickhouse")

      assert Enum.map(fields, & &1.key) == [
               :hostname,
               :port,
               :database,
               :username,
               :password,
               :ssl
             ]
    end

    test "HTTPS is Ch's scheme" do
      assert {:ok, %{state: %{config: config}}} =
               Connections.build("events", "clickhouse", %{"hostname" => "ch", "ssl" => "on"})

      assert config[:scheme] == "https"
      refute Keyword.has_key?(config, :ssl)
    end

    test "a test reaches the server and logs in" do
      assert :ok = Connections.test("clickhouse", form())

      assert {:error, message} = Connections.test("clickhouse", form(%{"password" => "nope"}))
      assert message =~ "Authentication failed" or message =~ "password"
    end
  end
end
