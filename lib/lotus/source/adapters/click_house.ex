defmodule Lotus.Source.Adapters.ClickHouse do
  @moduledoc false

  use Lotus.Source.Adapters.Ecto,
    dialect: Lotus.Source.Adapters.Ecto.Dialects.ClickHouse

  alias Lotus.Source.Adapters.Ecto.Dialects.ClickHouse, as: Dialect

  # ClickHouse has no transaction support (ecto_ch does not implement
  # Ecto.Adapter.Transaction), so we bypass do_execute_query which
  # assumes repo.rollback/1 is available.
  #
  # Read-only enforcement: ClickHouse's `readonly=1` per-query setting
  # replaces the Postgres/MySQL pattern of `SET TRANSACTION READ ONLY`.
  # The server itself rejects any write attempt with error 164 (READONLY).
  @impl true
  def execute_query(repo, sql, params, opts) do
    timeout = Keyword.get(opts, :timeout, 15_000)
    read_only = Keyword.get(opts, :read_only, true)

    query_opts = [timeout: timeout]

    query_opts =
      if read_only, do: Keyword.put(query_opts, :settings, readonly: 1), else: query_opts

    case repo.query(sql, params, query_opts) do
      {:ok, %{columns: cols, rows: rows} = raw} ->
        num_rows = Map.get(raw, :num_rows, length(rows || []))
        {:ok, %{columns: cols, rows: rows, num_rows: num_rows}}

      {:error, err} ->
        {:error, Dialect.format_error(err)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
