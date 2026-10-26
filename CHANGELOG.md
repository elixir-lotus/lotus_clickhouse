# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **A form that connects a ClickHouse source from the app.** With Lotus v2,
  `Lotus.Source.Connections.kinds/0` lists `"clickhouse"` with its fields
  (host, port, database, user, password, HTTPS), so a host or Lotus Pro can
  let people connect a ClickHouse server without a repo in the config. A
  test logs in with a query, since Ch connects over HTTP without
  authenticating.

### Changed

- **Requires Lotus v2.** The adapter now builds against Lotus core `main`
  (v2) and drops the Lotus v1 compatibility guard; stay on 0.2.0 for
  Lotus 1.3.

### Fixed

- **`{{var}}` templates follow ClickHouse's lexical rules.** The editor
  config declares a `:dialect_spec` (double-quote and backtick identifiers,
  backslash escapes in strings, `#` comments, `$$` strings), and
  `transform_statement/1` tokenizes with the profile Lotus v2 derives from
  it. Lotus v2's ANSI fallback ended a string at `\'`, so in
  `WHERE name = 'O\'Brien' AND email = '{{email}}'` the variable was read
  as part of a literal and left quoted; a variable inside a `#` comment or
  a backtick identifier was rewritten as code.

## [0.2.0] - 2026-10-17

The adapter reports column comments and table row estimates, which Lotus 1.3's
AI assistant and MCP server show, and moves to the `Lotus.SQL` helpers.
Requires Lotus `~> 1.3`.

### Added

- `describe_table/3` reports each column's comment (`system.columns.comment`)
  as `:comment`. ClickHouse has no foreign keys, so no column carries
  `:references`.
- `table_row_estimates/2`: the row count of every table in the given
  databases from `system.tables.total_rows`. MergeTree and the other engines
  that know their size keep this count, so reading it needs no scan. Tables
  without it (views, `Merge`, `Distributed`) are left out. Lotus's
  `table_row_estimates/2` and the MCP server's `list_tables` use it.

### Changed

- Requires Lotus `~> 1.3`, which adds `table_row_estimates/2` and the
  `:comment` column key (elixir-lotus/lotus#324).
- The dialect uses `Lotus.SQL.FilterInjector`, `Lotus.SQL.SortInjector` and
  `Lotus.SQL.Transformer`, which replace the deprecated
  `Lotus.Source.Adapters.Ecto.SQL.*` modules since Lotus 1.2.

## [0.1.0] - 2026-09-12

First release. Requires Lotus `~> 1.0`.

This adapter was written while Lotus core was reworked to support data
sources beyond Postgres, MySQL and SQLite, and it is the reference for an
Ecto-backed source on a dialect Lotus does not ship. It is complete against
the v1 adapter contract and its suite runs against a live server, but its own
surface — the dialect's type mapping, the editor configuration, the safety
defaults — has no production users yet, so it starts at 0.1.0 rather than
claiming a stable API.

### Fixed

- **Filter placeholders are typed from the value that binds to them.** A
  ClickHouse placeholder carries its own type, so the dialect derived each
  one from the matching value. It counted every filter, but a null test
  (`is_null`, `is_not_null`, or any filter whose value is `nil`) binds no
  parameter, so one of those shifted every placeholder after it onto the
  wrong value and the server rejected the query on a type mismatch.
- **An AST scan that finds no tables no longer reads as "touches nothing".**
  `extract_accessed_resources/2` runs `EXPLAIN AST` and scans for table
  nodes. Core treats an empty relation set as "nothing to check", which is
  right for `SELECT 1` and a visibility bypass for anything else, so a
  ClickHouse release that renames the node or an identifier shape the scan
  misses would have quietly disabled the rules. It now falls back to the SQL
  scan when the statement plainly reads from something.
- **`describe_table/3` reports a column's default expression** rather than
  its `default_kind`, which showed every defaulted column as `"DEFAULT"`.
- **The editor gets the `sql:clickhouse` language identifier**, not a bare
  `"sql"`. The editor reads the part after the colon to choose a tokenizer,
  so the ClickHouse keywords, types and function completions this adapter
  ships were being dropped.
- **A list value binds as `Array(T)`** instead of falling through to
  `String`, so `supports_feature?(:arrays)` is a promise the dialect can
  keep.

### Added

- `Lotus.Source.Adapters.ClickHouse`, a ClickHouse source adapter built on the
  Ecto dialect contract, so ClickHouse sources work anywhere a Lotus source
  works: query execution, the schema explorer, dashboards and AI-assisted
  exploration.
- `Lotus.Source.Adapters.Ecto.Dialects.ClickHouse`, with ClickHouse-native
  identifier quoting, `{$0:Type}` parameter placeholders, `EXPLAIN` query
  plans, and a full `db_type_to_lotus_type/1` mapping covering the integer,
  float, decimal, date, string, array, map and tuple families.
- Editor support: ClickHouse keywords, types and functions via
  `editor_config/0`, reported under the `sql:clickhouse` query language.
- Feature reporting through `supports_feature?/1`: arrays, JSON and
  query-populated dropdown options are supported; schema hierarchy, search
  path and `make_interval` are not.
- Safety defaults: `builtin_denies/1` and `builtin_schema_denies/1` keep the
  `system` database and the migration table out of reach.

[0.1.0]: https://github.com/elixir-lotus/lotus_clickhouse/releases/tag/v0.1.0
