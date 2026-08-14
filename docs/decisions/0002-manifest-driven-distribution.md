# ADR-0002: Manifest-driven distribution

**Status:** Accepted  
**Date:** 2026-08-13

## Context

Independent file arrays in install, sync, checks, tests, and documentation routinely diverge.

## Decision

`manifest.tsv` is the canonical inventory. Each row declares `path`, `type`, lifecycle `version`, `consumers`, and uninstall `ownership`. Lifecycle tools and completeness tests derive their artifact sets from it.

Toolkit release versions, template schema versions, and skill lifecycle versions are independent. The installer writes the toolkit release stamp only after all requested artifacts succeed.

## Consequences

- Adding a distributable requires one inventory change.
- Remote installation can fetch and interpret the manifest without additional dependencies.
- The tab-separated schema is deliberately simple enough for portable shell tooling.

