## Why

<!-- The problem this solves, for whom, and what happened before it (an error, a wrong result, a query ClickHouse rejected). -->

Fixes #<!-- the issue; see CONTRIBUTING.md for when a pull request needs one -->

## What

<!-- The change, in a few lines. -->

## How it was tested

<!-- The tests added, the ClickHouse version you ran them against, and what you ran by hand. -->

## Checklist

- [ ] One change: anything unrelated is in its own pull request.
- [ ] A bug fix has a test that fails on `main` and passes here.
- [ ] `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo --strict` and `mix test` (with the ClickHouse server from `mix test.setup` up) pass.
- [ ] The README or guides and the `[Unreleased]` section of `CHANGELOG.md` are updated, for a change a user can see.
- [ ] Says so here if it changes the public API, the SQL the adapter generates, or the read-only and deny-list behaviour.
- [ ] No changes to the version in `mix.exs` or the changelog's release headings (the maintainers keep those).
