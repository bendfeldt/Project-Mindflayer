# ADR-0011: Safety Rules for All Agents

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Project-Mindflayer is a consultant toolkit that installs AI-agent configurations across multiple client engagements. Safety rules — which prevent agents from exposing secrets, running destructive commands, or deploying without confirmation — were previously duplicated verbatim in every per-platform AGENTS.md template (`AGENTS-fabric.md`, `AGENTS-databricks.md`, `AGENTS-terraform.md`) and implicitly embedded in the global instructions.

This duplication created three problems:

1. **Drift risk:** Any change to safety rules required updating 3+ files identically
2. **No rationale capture:** The rules existed as prose blocks with no decision record explaining why each rule exists
3. **Ambiguity on scope:** It was unclear whether safety rules were platform-specific or universal across all agents and engagements

Safety rules must be universal. Regardless of which agent (Claude, Codex, Gemini, Cursor, Copilot) or which consultant is working in a repo, the same protections must apply. The rules protect client data, prevent accidental destruction, and enforce human-in-the-loop for state changes.

## Decision

Establish the following 11 safety rules as a single authoritative ADR. Every repo-level `AGENTS.md` references this ADR. The global `AGENTS.md` also references it.

### Safety Rules — All Agents

These rules apply regardless of which coding agent is used on this repo.

- **NEVER** read, display, log, or expose `.env` files, secrets, credentials, tokens, or private keys
- **NEVER** read files matching: `*.env*`, `*secret*`, `*credential*`, `*.pem`, `*.key`, `*.pfx`, `*.p12`, `*token*`, `.netrc`, `.pgpass`, `*.tfvars`
- **NEVER** output values of environment variables containing SECRET, TOKEN, KEY, PASSWORD, or CREDENTIAL
- **NEVER** run deploy, apply, destroy, or other state-changing commands without explicit human confirmation
- **NEVER** run destructive file operations (`rm -rf`, etc.) without explicit human confirmation
- **NEVER** push to remote repositories without explicit human confirmation
- When referencing secrets in code, always use vault lookups or environment variable references — never literal values
- If you need to verify a secret exists, check for the file or variable name only — never output its value

## Alternatives Considered

### Alternative A: Keep rules inline in every AGENTS.md (status quo)
- **Pros:** Rules are immediately visible when reading any repo's AGENTS.md; no indirection
- **Cons:** Duplication across 3 platform templates; drift risk when rules evolve; no captured rationale; changes require touching multiple files

### Alternative B: Rules live only in global AGENTS.md
- **Pros:** Single location; no duplication
- **Cons:** A teammate working in a repo without the global toolkit installed has no safety rules; repo-level instructions would be incomplete; violates the principle that repo context must be self-contained

### Alternative C: Single ADR referenced by global + every repo (chosen)
- **Pros:** Single source of truth; no drift possible; rationale and alternatives are captured; easy to supersede when rules evolve; repo and global contexts both point to the same authoritative source
- **Cons:** AGENTS.md readers must follow a reference to see the rules (minor indirection)

## Consequences

### Positive
- **Single source of truth:** Changes to safety rules require updating exactly one file
- **No drift possible:** Every repo and the global config reference the same ADR
- **Rationale captured:** Future consultants and agents understand why each rule exists
- **Easy to supersede:** When rules evolve, a new ADR supersedes this one and all references update atomically
- **Cross-agent consistency:** All supported agents (Claude, Codex, Gemini, Cursor, Copilot) enforce the same protections

### Negative
- **Minor indirection:** AGENTS.md readers see a reference to this ADR rather than the rules inline; requires following the link to see the full text
- **Requires global install:** The reference path (`~/.ai-toolkit/docs/decisions/platform/0011-safety-rules-for-all-agents.md`) only resolves if the consultant has installed the global toolkit

### Risks
- **Missing global install:** If a teammate has no `~/.ai-toolkit/` installed, the reference path doesn't resolve and the agent cannot read the rules
  - **Mitigation:** `/setup-repo` and `install.sh --project` enforce global-first installation; documentation emphasizes that global install is a prerequisite for any project work

## References

- `templates/AGENTS-fabric.md` — fabric platform template that previously contained inline safety rules
- `templates/AGENTS-databricks.md` — databricks platform template that previously contained inline safety rules
- `templates/AGENTS-terraform.md` — terraform platform template that previously contained inline safety rules
- `global/AGENTS.md` — global instructions that also reference these rules
- ADR-0001 — established `AGENTS.md` as the universal cross-platform repo instruction file
