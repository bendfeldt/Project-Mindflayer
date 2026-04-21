# ADR-0011: Tech-Stack Conventions as ADRs, One Universal AGENTS.md Template

**Status:** Accepted (supersedes ADR-0003 in part)
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Prior to v2.0.0, the toolkit maintained three per-platform templates: `AGENTS-fabric.md`,
`AGENTS-databricks.md`, and `AGENTS-terraform.md`. Each was ~70 lines and contained:

- Safety rules (duplicated verbatim in all three)
- Platform architecture prose (Fabric medallion flow, Databricks Unity Catalog layout,
  Terraform module structure) embedded directly in the template
- Client-specific tokens (`{CLIENT_NAME}`, `{REPO_TYPE}`, `{prefix}`)

Adding a new platform (e.g. Snowflake, dbt) meant forking yet another template file.
Changes to safety rules required editing three places and risked drift. Platform
conventions were hidden inside template prose with no rationale or decision record.

The question was whether to continue maintaining multiple templates or consolidate
into a single universal template with platform conventions as first-class decisions.

## Decision

We will use ONE universal template (`templates/AGENTS.md`, ~35 lines) with tokens
`{CLIENT_NAME}`, `{PLATFORM}`, `{REPO_TYPE}`, `{prefix}`, and `{ADR_LIST}`.

Platform conventions move to ADRs under `docs/decisions/platform/`:
- `0011-safety-rules-for-all-agents.md` — universal safety rules (secrets, deployments)
- `0012` through `0020` — platform-specific patterns (Fabric medallion, Databricks
  Unity Catalog, Terraform module structure, PySpark conventions, SQL standards, etc.)

At project-setup time, `install.sh` injects the platform-relevant ADR list into the
`{ADR_LIST}` token based on the `--profile` flag. For example, `--profile terraform`
injects the safety ADR plus Terraform-specific ADRs (`0011`, `0013`, `0015`, etc.).

Two-folder numbering is used:
- `docs/decisions/` — toolkit-scope ADRs (design decisions for the installer, skills, and distribution model)
- `docs/decisions/platform/` — platform conventions (safety rules, architecture patterns, coding standards)

## Alternatives Considered

### Alternative A: Keep three templates, add shared-content references
- **Pros:** Minimal disruption; existing repos continue working; no breaking changes
- **Cons:** Still three files to maintain; shared-content mechanism adds indirection; safety rules still duplicated; platform patterns remain hidden prose with no rationale

### Alternative B: Eliminate templates entirely, generate AGENTS.md programmatically
- **Pros:** No template maintenance; all content lives in `install.sh`; ultimate flexibility
- **Cons:** Loses version-header drift detection (no artifact to compare against); generated content is harder to discover and inspect in the repo; installer script becomes a content engine instead of a distribution tool

### Alternative C: One universal template + ADRs (chosen)
- **Pros:** Single template to maintain; safety rules and platform patterns become first-class decisions with rationale; adding a new platform requires writing ADRs, not forking a template; explicit supersession path when conventions evolve; version-header drift detection still works
- **Cons:** Breaking change for v1 repos; legacy-mode handling adds complexity to `install.sh`; contributors must now understand two ADR logs

## Consequences

### Positive
- Single template to maintain regardless of platform count
- Safety rules and platform patterns are now first-class decisions with context and rationale
- Adding a new platform (e.g. Snowflake, dbt, BigQuery) requires writing ADRs, not duplicating a template
- Explicit supersession path when conventions evolve (new ADR supersedes old ADR, not silent edit)
- Version header jumps from 1.0.0 to 2.0.0, making the breaking change explicit

### Negative
- Breaking change for repos with v1 templates — version header jumps to 2.0.0 and
  `check-template-update.sh` will flag them for migration
- Legacy-mode handling adds complexity to `install.sh` (backwards-compat profile inference
  + legacy template name detection)
- Contributors must now understand two ADR logs (toolkit-scope + platform-scope)
- Platform ADR list in `install.sh` must be kept current as new platforms are added

### Risks
- If the platform folder grows to many platforms, keeping the ADR list in `install.sh`
  current becomes a maintenance burden — mitigated by keeping the list in one place
  (the profile case statement in `install_project()`)
- Legacy v1 repos that are abandoned won't auto-migrate — that's by design, but might
  surprise someone returning after 6 months
- If a platform's conventions are split across many ADRs, the injected list becomes
  long and hard to scan — mitigated by keeping platform ADRs focused and atomic

## References

- Superseded-in-part: `docs/decisions/0003-thin-repo-templates-with-version-headers.md`
- Related: `docs/decisions/platform/0011-safety-rules-for-all-agents.md`
- Changed files: `templates/AGENTS.md`, `install.sh`, `skills/setup-repo/SKILL.md`, `tools/check-template-update.sh`
- New platform ADRs: `docs/decisions/platform/0012` through `0020` (Fabric, Databricks,
  Terraform, PySpark, SQL, Power BI, Unity Catalog, DLT, layer naming)
- Cross-platform standard: SKILL.md open standard (skills adapt to both layers automatically)
