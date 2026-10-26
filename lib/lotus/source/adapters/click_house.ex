defmodule Lotus.Source.Adapters.ClickHouse do
  @moduledoc """
  `Lotus.Source.Adapter` implementation for ClickHouse.

  Register it in `:source_adapters` and any repo running
  `Ecto.Adapters.ClickHouse` becomes a Lotus data source, queryable from the
  same editor, dashboards and AI assistant as a Postgres or MySQL source:

      config :lotus,
        source_adapters: [Lotus.Source.Adapters.ClickHouse],
        data_sources: %{"events" => MyApp.ClickHouseRepo}

  The adapter itself is thin. It is built with
  `use Lotus.Source.Adapters.Ecto`, so the Statement pipeline, preflight and
  introspection come from Lotus core, and everything ClickHouse-specific —
  identifier quoting, `{$0:Type}` placeholders, `EXPLAIN` plans, the type
  mapping, the editor configuration and the AI context — lives in
  `Lotus.Source.Adapters.Ecto.Dialects.ClickHouse`.

  That split is the point of the Dialect contract: a SQL engine Lotus does
  not ship support for needs a dialect module, not a whole adapter. See the
  [installation guide](installation.html) to configure it and
  [how it works](how-it-works.html) for the mechanics.
  """

  use Lotus.Source.Adapters.Ecto,
    dialect: Lotus.Source.Adapters.Ecto.Dialects.ClickHouse,
    # The form that connects a ClickHouse source from settings
    # (`Lotus.Source.Connections`). Ch connects over HTTP without logging
    # in, so a test also runs a query.
    connection: [
      kind: "clickhouse",
      label: "ClickHouse",
      test: :query,
      fields: [
        %{
          key: :hostname,
          label: "Host",
          type: :string,
          required: true,
          placeholder: "ch.internal"
        },
        %{key: :port, label: "Port", type: :integer, default: 8123},
        %{key: :database, label: "Database", type: :string, default: "default"},
        %{key: :username, label: "User", type: :string, default: "default"},
        %{key: :password, label: "Password", type: :secret},
        %{key: :ssl, label: "Use HTTPS", type: :boolean, default: false}
      ]
    ]

  alias Lotus.Source.Adapters.Ecto.Dialects.ClickHouse, as: Dialect

  # Ch takes the scheme rather than an SSL flag.
  @impl Lotus.Source.Adapter.Connection
  def from_settings(name, settings) do
    {ssl, settings} = Keyword.pop(settings, :ssl, false)
    super(name, Keyword.put(settings, :scheme, if(ssl, do: "https", else: "http")))
  end

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
