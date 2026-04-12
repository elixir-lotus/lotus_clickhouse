defmodule Lotus.ClickHouse.Case do
  @moduledoc """
  Test case template for ClickHouse adapter tests.

  Truncates all test tables before each test to ensure isolation.
  All tests run with `async: false` since ClickHouse does not
  support Ecto.Adapters.SQL.Sandbox.
  """

  use ExUnit.CaseTemplate

  alias Lotus.ClickHouse.Test.Repo

  @test_tables ~w(test_users test_posts test_events)

  using do
    quote do
      alias Lotus.ClickHouse.Test.Repo
    end
  end

  setup do
    truncate_test_tables()
    :ok
  end

  defp truncate_test_tables do
    for table <- @test_tables do
      Repo.query!("TRUNCATE TABLE IF EXISTS #{table}")
    end
  end
end
