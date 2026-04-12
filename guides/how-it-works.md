# How It Works

This guide explains the architecture of the ClickHouse adapter and how it integrates with the Lotus execution pipeline.

## Architecture

The adapter consists of two modules:

```
lib/
  lotus_clickhouse/
    adapter.ex    # Lotus.Source.Adapters.ClickHouse  -- entry point, implements Lotus.Source.Adapter
    dialect.ex    # Lotus.Source.Adapters.Ecto.Dialects.ClickHouse   -- ClickHouse-specific SQL and introspection
```

### Adapter module

`Lotus.Source.Adapters.ClickHouse` uses the `Lotus.Source.Adapters.Ecto` macro to inherit all standard Ecto adapter callbacks:

```elixir
defmodule Lotus.Source.Adapters.ClickHouse do
  use Lotus.Source.Adapters.Ecto, dialect: Lotus.Source.Adapters.Ecto.Dialects.ClickHouse
end
```

This single `use` line generates implementations for 30+ callbacks (introspection, SQL generation, safety, lifecycle) that delegate to the dialect module for ClickHouse-specific behavior and to shared Ecto helpers for common logic.

The adapter overrides one callback -- `execute_query/4` -- because ClickHouse does not support database transactions.

### Dialect module

`Lotus.Source.Adapters.Ecto.Dialects.ClickHouse` implements the `Lotus.Source.Adapters.Ecto.Dialect` behaviour with ClickHouse-specific logic for:

- **SQL generation**: Double-quoted identifiers, `{$N:Type}` parameter placeholders
- **Introspection**: Queries against `system.databases`, `system.tables`, `system.columns`
- **Type mapping**: ClickHouse types to Lotus types (with recursive unwrapping of `Nullable`, `LowCardinality`, `Array` wrappers)
- **Error handling**: Formatting `Ch.Error` structs into readable messages
- **Safety**: Deny rules for `system` and `INFORMATION_SCHEMA` schemas

## Query execution flow

When a user runs a query against a ClickHouse data source:

```
1. Lotus.run_statement("SELECT * FROM events", [], repo: "clickhouse")
2. Source resolver finds MyApp.ClickHouseRepo
3. Adapter.can_handle?(MyApp.ClickHouseRepo) -> true  (checks repo.__adapter__() == Ecto.Adapters.ClickHouse)
4. Adapter.wrap("clickhouse", MyApp.ClickHouseRepo) -> %Adapter{source_type: :clickhouse}
5. Pipeline:
   a. sanitize_query    -- regex blocks DML/DDL keywords
   b. apply_filters     -- CTE-wraps query, adds WHERE clause with typed params
   c. apply_sorts       -- CTE-wraps query, adds ORDER BY
   d. apply_window      -- wraps in LIMIT/OFFSET subquery
   e. execute_query     -- repo.query(sql, params, settings: [readonly: 1])
6. ClickHouse server executes query with readonly=1 enforced
7. Result: %{columns: [...], rows: [[...]], num_rows: N}
```

## Parameter format

ClickHouse requires typed parameter placeholders. Unlike PostgreSQL (`$1`) or MySQL (`?`), ClickHouse uses `{$N:Type}` syntax where `N` is 0-indexed and `Type` is a ClickHouse type name:

```sql
SELECT * FROM users WHERE age > {$0:Int64} AND name = {$1:String}
-- params: [25, "Alice"]
```

The dialect infers the ClickHouse type from:
- **Lotus type atoms** (from `param_placeholder/3`): `:text` -> `String`, `:integer` -> `Int64`, etc.
- **Elixir values** (from `apply_filters/3`): `is_binary` -> `String`, `is_integer` -> `Int64`, etc.

## Read-only enforcement

The adapter enforces read-only access through two layers:

### Layer 1: Sanitizer (shared with all Lotus adapters)

The `sanitize_query/3` callback blocks queries containing DML/DDL keywords (`INSERT`, `UPDATE`, `DELETE`, `DROP`, `CREATE`, `ALTER`, `TRUNCATE`) via regex matching. This runs before execution.

### Layer 2: ClickHouse `readonly=1` (server-enforced)

Every query executed through `execute_query/4` includes the ClickHouse `readonly=1` setting:

```elixir
repo.query(sql, params, settings: [readonly: 1])
```

ClickHouse itself rejects any write attempt with error code 164 (READONLY). This is the server-side equivalent of PostgreSQL's `SET TRANSACTION READ ONLY`.

Both layers can be bypassed with `read_only: false` in the opts, which is only used in controlled contexts (e.g., the Lotus test harness inserting fixture data).

## Introspection

Schema discovery queries ClickHouse's `system.*` tables instead of `information_schema`:

| Operation | Query target |
|---|---|
| `list_schemas` | `system.databases` |
| `list_tables` | `system.tables` |
| `get_table_schema` | `system.columns` |
| `resolve_table_schema` | `system.tables` |

System schemas (`system`, `INFORMATION_SCHEMA`) are excluded from introspection results and blocked by deny rules.

## Type mapping

ClickHouse types are mapped to Lotus types with recursive unwrapping of wrapper types:

```
Nullable(String)           -> :text     (unwrap Nullable, map String)
LowCardinality(String)     -> :text     (unwrap LowCardinality, map String)
LowCardinality(Nullable(UInt8)) -> :integer  (unwrap both, map UInt8)
Array(String)              -> {:array, :text}
Array(Nullable(UInt64))    -> {:array, :integer}
```

| ClickHouse type | Lotus type |
|---|---|
| `UInt8/16/32/64`, `Int8/16/32/64` | `:integer` |
| `Float32`, `Float64` | `:float` |
| `Decimal*` | `:decimal` |
| `String`, `FixedString(N)` | `:text` |
| `Date`, `Date32` | `:date` |
| `DateTime`, `DateTime64` | `:datetime` |
| `Bool` | `:boolean` |
| `UUID` | `:uuid` |
| `JSON`, `Map(K,V)` | `:json` |
| `Enum8`, `Enum16` | `:enum` |
| `Array(T)` | `{:array, <mapped T>}` |

## No transaction support

ClickHouse does not support database transactions. The `ecto_ch` driver does not implement `Ecto.Adapter.Transaction`, so `repo.transaction/2` and `repo.rollback/1` are unavailable.

The adapter handles this by:

1. **`execute_in_transaction/3`** in the dialect executes the callback directly without wrapping: `{:ok, fun.()}`
2. **`execute_query/4`** in the adapter bypasses the shared `do_execute_query` helper (which assumes `repo.rollback/1` exists) and calls `repo.query/3` directly

This is safe because ClickHouse is used as a read-only analytics source in Lotus. The transaction wrapper in PostgreSQL/MySQL serves two purposes -- read-only enforcement and atomicity -- and both are addressed differently for ClickHouse (readonly setting for enforcement, no atomicity needed for read-only queries).
