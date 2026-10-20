# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/elixir-lotus/lotus_clickhouse/security/advisories/new).

Say what an attacker can do, and how: the query or the variable values,
the Lotus and ClickHouse versions, and the steps. We answer within a
week, agree on a fix and a date, and credit you in the advisory unless
you ask us not to.

## Supported versions

Security fixes are made to the latest release. Lotus ClickHouse is
before 1.0, so a fix is not backported to an earlier minor version.

## What is in scope

The adapter turns a Lotus statement, its variables, filters and sorts
into SQL that it runs against your ClickHouse server, and reports that
server's schema back to Lotus. A problem is in scope when, through this
adapter:

- **query building or escaping** lets a variable, a filter, a sort or an
  identifier change the SQL instead of binding as a value or a quoted
  name: a placeholder, `quote_identifier/1`, or the `{{var}}` rewriting
  that puts a value outside a parameter;
- **read-only enforcement** fails: a statement run without
  `read_only: false` writes, mutates or changes server state, for
  example a query that runs without the `readonly: 1` setting, or a
  verb that gets past both it and Lotus's sanitizer;
- **credentials** leak: the repo's password or connection settings end
  up in an error, a log line, telemetry, the AI context or a result;
- **schema introspection or the preflight** exposes tables it should not:
  `system`, `INFORMATION_SCHEMA`, the migration table or the `lotus_*`
  tables reach a user's query or a schema listing, or a query reads a
  table that Lotus's visibility rules deny because the preflight missed
  it.

Out of scope: which tables a ClickHouse user may read, and the limits on
its queries, are set on the ClickHouse server (users, grants, settings
profiles) and in the host's Lotus visibility rules. A runaway query is
bounded by server settings such as `max_execution_time`, as the README
explains. A bug in Lotus itself, in `ecto_ch` or in `ch` goes to that
project.
