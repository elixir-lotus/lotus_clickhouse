# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
