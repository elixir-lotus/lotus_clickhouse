defmodule Lotus.ClickHouseTest do
  use ExUnit.Case

  alias Lotus.ClickHouse.Test.Repo

  test "ClickHouse repo is configured" do
    config = Repo.config()
    assert config[:hostname] == "localhost"
    assert config[:port] == 9123
    assert config[:database] =~ "lotus_test"
  end

  test "ClickHouse responds to SELECT 1" do
    assert {:ok, %{columns: ["1"], rows: [[1]], num_rows: 1}} = Repo.query("SELECT 1")
  end
end
