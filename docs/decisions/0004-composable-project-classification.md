# ADR-0004: Compose project classification and permissions

**Status:** Accepted
**Date:** 2026-08-15

## Context

Repositories can combine infrastructure, data-platform, and data-engineering responsibilities while using multiple vendor ecosystems, tools, runtimes, databases, and languages. The original installer accepted one profile and used it simultaneously as repository classification, generated metadata, join-mode identity, and Claude permission selection.

## Decision

Project types and technologies are independent ordered sets. Project types are descriptive only. Technologies use a declarative catalog and compose technology-specific permission policy. Namespaced component identifiers identify their ecosystem without inheriting parent permissions.

The plural interface is used for new installations. The existing `--profile terraform|databricks|fabric` interface remains an isolated legacy path with unchanged rendering and settings. Join mode parses the new schema first and retains legacy platform parsing as a fallback.

## Alternatives Considered

- Add more mutually exclusive profiles. Rejected because mixed monorepos would still be misclassified and profile combinations would grow exponentially.
- Accept unrestricted free text. Rejected because permissions and deterministic joins require validated canonical identifiers.
- Replace the legacy profile interface. Rejected because repository invariants require existing flags and automation to remain functional.

## Consequences

- Mixed monorepos can describe their responsibilities and technology ecosystems accurately.
- Permission composition remains auditable and extensible without installer case logic.
- Catalog additions require lifecycle-managed registry updates and tests.
- Join mode and regression coverage must support both metadata schemas indefinitely.
