defmodule Lotus.ClickHouse.Test.LotusRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :lotus_clickhouse,
    adapter: Ecto.Adapters.SQLite3
end
