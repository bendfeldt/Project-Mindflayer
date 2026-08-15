# ADR-0001: Universal AGENTS.md guidance

**Status:** Accepted  
**Date:** 2026-08-13

## Context

Supported assistants discover different instruction filenames. Duplicating substantive guidance across those files creates drift.

## Decision

`AGENTS.md` is the substantive repository instruction contract. Claude and Gemini use one-line imports because their native project filenames differ. Codex, Cursor, and Copilot read `AGENTS.md` directly and receive no repository compatibility shim. Installed global baselines contain the portable normative rules directly because no repository `AGENTS.md` is guaranteed to exist.

Always-loaded guidance contains only universal safety, authorization, workflow, and routing rules. Multi-step procedures live in skills, detailed rationale lives in documentation, and path-specific guidance lives in native scoped-rule mechanisms. Runtime discovery directories contain no instructional scaffolding.

## Consequences

- Governance changes have one repository source of truth.
- Claude and Gemini shims remain exact imports with no independent policy.
- Consumers must not add policy or ADR lists to compatibility files.
- Project guidance keeps a minimal safety floor so it remains safe for contributors without the global baseline.
