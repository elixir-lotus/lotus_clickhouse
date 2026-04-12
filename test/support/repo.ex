defmodule Lotus.ClickHouse.Test.Repo do
  use Ecto.Repo,
    otp_app: :lotus_clickhouse,
    adapter: Ecto.Adapters.ClickHouse
end
