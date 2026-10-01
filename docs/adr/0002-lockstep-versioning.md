# 0002. Lockstep versioning

Date: 2026-10-01

Status: Accepted

## Context

The workspace has several published modules (ADR 0001). Each module could
have its own version, tags and changelog, or all modules could share one
version.

## Decision

All modules share one version. One tag `vX.Y.Z` releases all of them, and one
`CHANGELOG.md` (git-cliff) describes the release. `mise run release:bump` sets
every module version, every import of a sibling module and the CLI version
constant. `mise run release:check-version` fails when any of them differ. The
release publishes the modules in dependency order: `partiql-value`,
`partiql-syntax`, (`partiql-eval`), `partiql`.

## Consequences

- One release process, one tag and one changelog.
- Users can combine modules of the same version without a compatibility
  matrix.
- A release republishes modules that did not change.
- A change to independent versions later is possible but needs per-module
  tags and changelogs.
