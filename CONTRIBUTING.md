# Contributing to Lotus ClickHouse

Thank you for helping. This page says what to open (an issue, a pull
request, or a security report), what a pull request needs, and what the
maintainers keep for themselves. How to start the ClickHouse server the
tests need, and how to run them, is in the README, under
[Development](README.md#development).

This package is the ClickHouse source adapter for
[Lotus](https://github.com/elixir-lotus/lotus). A problem that shows up
with every source, not only ClickHouse, belongs in the Lotus repository,
and its [contributing guide](https://github.com/elixir-lotus/lotus/blob/main/guides/contributing.md)
covers the parts of the pipeline this adapter plugs into.

## Questions, bugs and ideas

- **A bug.** Open an issue with the bug report form. The query that shows
  it, the error ClickHouse or Lotus returned, and the versions of the
  server and the driver are the most useful things you can give.
- **An idea or a change of behaviour.** Open an issue with the feature
  request form, and say the problem before the solution.
- **A security problem.** Do not open an issue. See
  [SECURITY.md](SECURITY.md).

Search the open and closed issues first: the idea may already be planned,
or turned down for a reason given there.

## When a pull request needs an issue first

Open an issue, and agree on the change there, before a pull request that:

- adds a feature, an option or a callback, or a ClickHouse type to the
  type mapping;
- changes what the adapter does or its public API: the SQL it generates,
  the read-only guarantee, the deny lists, what introspection reports;
- adds a dependency, or changes the supported versions of Lotus,
  `ecto_ch`, `ch` or ClickHouse;
- touches many files, or needs a design decision.

A pull request does not need an issue when it is small and its reason is
plain from the diff: a typo, a broken link, a wrong sentence in a guide,
or a bug fix with a test that fails without it. When in doubt, open the
issue: a short discussion costs less than a pull request that is not
merged.

A pull request with an issue says so: `Fixes #123` or `Closes #123`.

## A pull request

- **One change.** A fix, a guide for an unrelated case and a README edit
  are three pull requests. Each is reviewed, reverted and released on its
  own.
- **Why, not only what.** The description says the problem the change
  solves, for whom, and what happened before it: an error, a wrong
  result, a query ClickHouse rejected. Say which ClickHouse version you
  saw it on.
- **Tests.** A bug fix has a test that fails on `main` and passes with
  the fix. A feature has tests of what it does, and of its errors. A
  change to the SQL the adapter sends to ClickHouse is tested against
  the live server (`test/integration/`), not only as a string.
- **Docs.** A change a user can see updates the README or the guide it
  belongs to, and adds an entry under `## [Unreleased]` at the top of
  [CHANGELOG.md](CHANGELOG.md) (add that heading if it is not there).
- **The checks pass.** CI runs them on Elixir 1.18, 1.19 and 1.20 against
  ClickHouse 24.8; run them first, with the server from `mix test.setup`
  up:

  ```sh
  mix format --check-formatted
  mix compile --warnings-as-errors
  mix credo --strict
  mix test
  ```

  `mix test` needs the ClickHouse server: with none running, the suite
  fails at startup rather than skipping.

The pull request template has these as a checklist.

## What the maintainers keep

- **Releases.** The version in `mix.exs`, the release headings of the
  changelog and the tags are changed by the maintainers, at a release.

## Style

Match the code around your change: its naming, its comments and the way
its guides are written. `mix format` and `mix credo --strict` settle the
rest.

## License

By contributing, you agree that your contribution is released under the
MIT License of the project (see [LICENSE](https://github.com/elixir-lotus/lotus_clickhouse/blob/main/LICENSE)).
