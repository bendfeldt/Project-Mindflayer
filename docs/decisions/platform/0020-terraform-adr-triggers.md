# ADR-0020: Terraform ADR Triggers — When Client-Level Documentation Is Required

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Not every Terraform decision requires an Architecture Decision Record. Routine
changes (resource property updates, scaling adjustments, tagging changes) are
self-documenting through git history and pull request discussions. However,
structural decisions—those that affect multiple environments, change authentication
posture, introduce new dependencies, or alter blast radius—need explicit documentation
so that future maintainers understand the rationale and constraints.

The question was which categories of Terraform changes require a formal ADR in the
client repo's `docs/decisions/` directory versus which can proceed with only PR
review and commit messages.

## Decision

A client-level ADR is required for these categories of change:

1. **New modules** — when introducing a new Terraform module (either third-party or custom). Document: purpose, alternatives considered, provider selection, and compatibility requirements.

2. **Provider or service selection** — when adopting a new Terraform provider or choosing between competing Azure/GCP services (e.g., Azure Storage vs. GCS, Cosmos DB vs. Cloud Spanner). Document: comparison matrix, cost implications, feature gaps, and lock-in risks.

3. **State backend changes** — when migrating state storage location, changing locking mechanism, or moving from local to remote state. Document: migration steps, rollback plan, downtime window, and verification procedure.

4. **Authentication approach changes** — when switching between Service Principal, OIDC, Managed Identity, or human credential patterns. Document: security posture comparison, audit trail changes, rotation policy, and break-glass procedure.

5. **Cross-environment blast radius** — anything that shares state or configuration across dev/test/prod (shared Key Vault, centralized networking, single subscription). Document: failure modes, isolation boundaries, and incident response.

Routine changes that do NOT require an ADR: resource property updates, scaling
adjustments, tagging, IAM role assignments within existing patterns, version bumps
for providers or modules.

## Alternatives Considered

### Alternative A: ADR for every Terraform change
- **Pros:** Complete historical record; no ambiguity about when to document
- **Cons:** ADR fatigue; slows down routine updates; signal-to-noise ratio drops; team stops reading ADRs

### Alternative B: No formal ADR triggers, rely on PR review
- **Pros:** Minimal process overhead; team decides case-by-case
- **Cons:** Inconsistent documentation; decision rationale lost when team members leave; six months later no one remembers why the state backend was chosen

### Alternative C: Checklist-based triggers (chosen)
- **Pros:** Clear guidance on when documentation is required; preserves high-signal ADRs for structural decisions
- **Cons:** Requires judgment calls on edge cases (e.g., "is this module 'new' or a refactor?")

## Consequences

### Positive
- Client repos contain decision records for the changes that actually matter—structural, cross-environment, and security-sensitive decisions
- Onboarding engineers can understand "why this way" by reading ADRs rather than spelunking through 200 closed PRs
- Reduced cognitive load during routine updates—no need to debate whether a scaling change needs an ADR

### Negative
- Judgment calls required: is a minor provider addition a "service selection" decision or just a small enhancement? When in doubt, the team must decide.
- If ADRs are not kept up-to-date (e.g., a later change contradicts an earlier ADR), the documentation becomes misleading

### Risks
- If the ADR trigger list is too narrow, important decisions go undocumented
- If the ADR trigger list is too broad, ADR fatigue sets in and the practice is abandoned
- A new team member unfamiliar with the triggers may skip documentation—mitigated by including the trigger list in `AGENTS.md` so AI agents remind during PR review

## References

- `templates/AGENTS.md` — universal repo instruction file (includes ADR triggers)
- `templates/AGENTS-terraform.md` — superseded platform-specific template (line 54-56: "ADR Triggers" section extracted to this ADR)
- ADR-0019 — Terraform Module Structure and Operating Model (documents standard structure that ADRs extend)
