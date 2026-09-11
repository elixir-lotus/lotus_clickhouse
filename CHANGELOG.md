# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - Unreleased

First release. Requires Lotus `~> 1.0`.

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

[1.0.0]: https://github.com/elixir-lotus/lotus_clickhouse/releases/tag/v1.0.0
