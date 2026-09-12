# Writing Queries

A Lotus statement for a ClickHouse source is ordinary SQL text, so most of what you know from a Postgres source carries over. This guide covers the parts that do not: how parameters are spelled, what Lotus wraps around your SQL on the way to the server, and the ClickHouse-specific edges that will surprise you the first time.

## Parameters are typed, and 0-indexed

ClickHouse's HTTP interface binds parameters by name and type, not by position marker. The dialect emits them as `{$N:Type}`, where `N` is the 0-based position in the params list:

```sql
SELECT * FROM events
WHERE user_id = {$0:Int64}
  AND event_date >= {$1:Date}
```

```elixir
Lotus.run_statement(sql, [42, ~D[2026-01-01]], repo: "clickhouse")
```

You rarely write these by hand — Lotus generates them from `{{var}}` templates — but they show up in `EXPLAIN` output, in error messages, and in the paginated SQL, so it is worth recognising them. Note the off-by-one against the params list: `{$0:...}` is the first parameter.

The type in the placeholder is not decoration. ClickHouse parses the parameter value according to it, and a mismatch against the column is an error rather than a coercion.

### How Lotus picks the type

`{{var}}` substitution runs each variable through `param_placeholder/3`, which maps the Lotus type atom that core resolved for that variable:

| Lotus type | ClickHouse placeholder type |
|---|---|
| `:integer` | `Int64` |
| `:float` | `Float64` |
| `:boolean` | `Bool` |
| `:date` | `Date` |
| `:datetime` | `DateTime` |
| `:text`, `:string` | `String` |
| `:decimal`, `:uuid`, `:json`, `:binary` | `String` |
| anything else, or no type at all | `String` |

Core resolves that atom in this order: the type it inferred from the column the variable is compared against (looked up through the schema and `db_type_to_lotus_type/1`), then the variable's declared type, then nothing.

Two consequences:

- **An unbound, undeclared variable becomes a `String`.** If it is compared against a numeric column, ClickHouse rejects the comparison rather than coercing it. Declare the variable's type on the saved query when core cannot infer it from context — for example when the variable sits inside a function call rather than beside a column.
- **`Decimal` and `UUID` columns need help.** Both bind as `String`, because that is the safest wire form. If ClickHouse complains about the comparison, wrap the placeholder: `WHERE id = toUUID({{id}})`, `WHERE amount > toDecimal64({{amount}}, 2)`.

## Variables

Lotus's `{{var}}` and `[[ ... ]]` syntax works as documented in the core [advanced variables guide](https://hexdocs.pm/lotus/advanced-variables.html). What is dialect-specific is the rewriting `transform_statement/1` does first.

### Quoted scalars are unquoted for you

```sql
SELECT * FROM users WHERE email = '{{email}}'
```

becomes

```sql
SELECT * FROM users WHERE email = {{email}}
```

before substitution, so the value binds as a parameter instead of being spliced into a string literal. This only fires when the quotes contain exactly one bare variable and nothing else.

### Wildcards become concatenation

```sql
WHERE name LIKE '%{{q}}%'
```

becomes

```sql
WHERE name LIKE '%' || {{q}} || '%'
```

ClickHouse reads `||` as string concatenation, so the search term stays a parameter and the wildcards stay literal. The left-only (`'%{{q}}'`) and right-only (`'{{q}}%'`) forms are handled the same way. ClickHouse also has `ILIKE` if you want case-insensitive matching.

### Optional clauses

`[[ ... ]]` blocks are resolved by core before the adapter sees the statement, so they behave exactly as they do for Postgres: a block whose variables are all missing, `nil` or `""` is dropped, otherwise the brackets are stripped. The usual `WHERE 1 = 1` anchor applies:

```sql
SELECT event_name, count() AS events
FROM events
WHERE 1 = 1
  [[AND event_date >= {{from}}]]
  [[AND user_id = {{user_id}}]]
GROUP BY event_name
ORDER BY events DESC
```

### Dates and intervals

Core rewrites Postgres's `INTERVAL '{{n}} days'` into a `make_interval` call for sources that have one. ClickHouse does not — `supports_feature?(:make_interval)` is `false` — and no ClickHouse equivalent is substituted in its place. A variable left inside a quoted interval literal will *not* be bound; it will sit there as text.

Use a ClickHouse date function that takes an expression instead:

```sql
WHERE event_date >= subtractDays(today(), {{days}})
```

`subtractDays`, `subtractMonths`, `toStartOfDay`, `date_diff`, `toDate` and the rest of the family are all in the editor's completion list.

## What the pipeline wraps around your SQL

Filters, sorts and pagination from the result table do not edit your SQL — they nest it. In order, and only when the corresponding option is present:

1. **Filters** wrap it in a CTE and re-select:

   ```sql
   WITH _base AS (<your SQL>) SELECT * FROM _base WHERE "region" = {$0:String}
   ```

   The filter's ClickHouse type is inferred from the Elixir value at this point (binary → `String`, integer → `Int64`, float → `Float64`, boolean → `Bool`, `Date` → `Date`, `DateTime`/`NaiveDateTime` → `DateTime`, `Decimal` → `String`), not from the column. Supported operators are `:eq`, `:neq`, `:gt`, `:lt`, `:gte`, `:lte`, `:like`, `:is_null` and `:is_not_null`; a filter whose value is `nil` collapses to `IS NULL` / `IS NOT NULL` rather than binding a parameter.

2. **Sorts** wrap that in another CTE:

   ```sql
   WITH _sorted AS (<previous>) SELECT * FROM _sorted ORDER BY "created_at" DESC
   ```

   Wrapping rather than appending is what makes sorting work on a statement that already ends in `ORDER BY`, `GROUP BY` or `LIMIT`.

3. **Pagination** wraps it once more:

   ```sql
   SELECT * FROM (<previous>) AS lotus_sub LIMIT {$N:UInt64} OFFSET {$N+1:UInt64}
   ```

   With `count: :exact`, a separate `SELECT COUNT(*) FROM (<previous>) AS lotus_sub` is handed back on the statement's metadata for Lotus to run as a second query — ClickHouse gives no free total alongside the page.

Two things follow from the nesting. Column names you filter or sort on must exist in your statement's **output** columns, not in its source tables. And every layer is a subquery, so ClickHouse optimisations that depend on the shape of the outermost query — `PREWHERE`, `FINAL`, `SAMPLE` — apply to your inner SQL, where you wrote them, and not to the wrapper.

## Read-only, and what that rules out

Every statement goes to the server with ClickHouse's `readonly=1` setting, and the server refuses anything that writes with error 164 (READONLY). Before that, core's shared SQL sanitizer rejects multi-statement input and any statement matching the keyword regex `\b(INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|TRUNCATE|GRANT|REVOKE|VACUUM|ANALYZE|CALL|LOCK)\b`.

That regex is blunt in both directions, and it is worth knowing which way each blunt edge cuts:

- It matches the **word anywhere**, including inside a `SELECT`. A column named `analyze_ms`, or a string literal containing `DELETE`, will be rejected as a write. Alias the column or use a different literal.
- It knows nothing about ClickHouse's own mutating verbs — `OPTIMIZE`, `SYSTEM`, `ATTACH`, `DETACH`, `KILL`, `TRUNCATE`'s cousins. Those get past the regex and are stopped by `readonly=1` at the server. The two layers are complementary, not redundant.

`readonly=1` also blocks changing settings mid-query, so a `SETTINGS` clause that raises a limit will be refused. A `SETTINGS` clause that only *constrains* — `SETTINGS max_execution_time = 30` — is the useful case, and worth adding to any query you expect to be expensive: the adapter sets no server-side execution limit of its own, and the `:timeout` option only bounds the HTTP client.

## Visibility and preflight

Before execution, Lotus asks the adapter which relations the statement touches and checks them against your visibility rules. This dialect answers by running `EXPLAIN AST` against the server and reading `TableIdentifier` nodes out of the plan, resolving aliases (`FROM events AS e`) back to real table names. If `EXPLAIN AST` fails for any reason, it falls back to a `FROM` / `JOIN` regex over the SQL text.

Practical notes:

- Preflight costs a round-trip to ClickHouse for every statement that is not itself an `EXPLAIN`, `SHOW`, `DESCRIBE` or `DESC` — those skip it.
- A table referenced only through a table function (`url(...)`, `remote(...)`, `s3(...)`) or through a dictionary is not a `TableIdentifier` and will not be seen by either the AST scan or the regex. Do not lean on Lotus's visibility rules to fence off those.
- Tables with no database qualifier are attributed to the repo's configured `:database`. A fully qualified `other_db.table` is reported under `other_db`, which is outside `default_schemas/1`, so your rules must allow it explicitly.
- The `system` and `INFORMATION_SCHEMA` databases, the Ecto migration table, and Lotus's own `lotus_*` tables are denied outright before your rules are consulted.

## Errors

Server errors come back as `ClickHouse Error (<code>): <message>`. The codes worth memorising are the ones the AI context also keys on:

| Code | Meaning | Usual cause |
|---|---|---|
| 47 | `UNKNOWN_IDENTIFIER` | Column name — check `describe_table` output |
| 60 | `UNKNOWN_TABLE` | Table name, or a missing database qualifier |
| 62 | `SYNTAX_ERROR` | Standard SQL that ClickHouse does not accept |
| 164 | `READONLY` | A write, or a setting change, under `readonly=1` |

`Memory limit ... exceeded` is the other common one: narrow the `WHERE`, add a `PREWHERE` on a partition-pruning column, or reach for an approximate aggregate — `uniq` instead of `count(DISTINCT ...)`, `quantile` instead of `quantileExact`.

## What the editor gives you

The shipped editor configuration declares the language as `sql:clickhouse` and supplies ClickHouse's keywords, its full type vocabulary — including the `Nullable`, `LowCardinality`, `Array`, `Tuple` and `Map` wrappers — and 370 function completions with signatures, covering the aggregate, array, date, string, conversion, math, conditional, hash, URL, IP, JSON, encoding, geo, null-handling and window families.

It also marks `prewhere`, `final`, `sample`, `settings` and `format` as context boundaries, so column suggestions inside a `PREWHERE` behave like they do inside a `WHERE`.

What it does not supply is a CodeMirror `dialect_spec`, so tokenization falls back to the editor's generic SQL grammar. Backtick-quoted identifiers — legal ClickHouse, and common in its own documentation — may not highlight correctly. Everything this adapter generates uses double quotes.

## Further reading

- [How It Works](how-it-works.md) — the callbacks behind all of the above
- [Lotus advanced variables](https://hexdocs.pm/lotus/advanced-variables.html) — `{{var}}` and `[[ ]]` in full
- [Lotus visibility](https://hexdocs.pm/lotus/visibility.html) — writing the rules preflight checks against
