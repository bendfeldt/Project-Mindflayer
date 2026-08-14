# ADR-0001: Universal AGENTS.md guidance

**Status:** Accepted  
**Date:** 2026-08-13

## Context

Supported assistants discover different instruction filenames. Duplicating substantive guidance across those files creates drift.

## Decision

`AGENTS.md` is the substantive repository instruction contract. Runtime-specific instruction files are minimal compatibility shims that point to it and contain only genuinely runtime-specific notes. Installed global baselines contain the portable normative rules directly because no repository `AGENTS.md` is guaranteed to exist.

## Consequences

- Governance changes have one repository source of truth.
- Shims remain compatible with assistant discovery rules.
- Consumers must not add policy or ADR lists to compatibility files.

