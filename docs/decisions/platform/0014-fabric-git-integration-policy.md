# ADR-0014: Fabric Git Integration Policy

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Fabric workspaces can be connected to git repositories to version-control notebooks,
pipelines, and semantic models. Without a clear policy, teams are uncertain about:

- Which Fabric items belong in git vs. which are managed by Terraform
- How to map git branches to Fabric workspaces
- Whether to enable git integration per workspace or per capacity
- What happens to data when switching branches

This leads to inconsistent git workflows, accidental overwrites, and confusion about
the source of truth for workspace configuration.

## Decision

**Git integration scope:** Enabled per workspace, not at capacity level.

**Branch-to-workspace mapping:**
- `main` branch → production workspaces
- `dev` branch → development workspaces
- Feature branches → temporary dev workspaces (created manually as needed)

**In git (Fabric Git integration manages these):**
- Spark notebooks (`.py`, `.ipynb`, `.scala`)
- Pipeline JSON definitions
- TMDL semantic model definitions
- Dataflow JSON (Dataflow Gen2)

**Not in git (Terraform manages these):**
- Data in Lakehouse tables
- Lakehouse metadata (table schemas, partitions)
- Capacity configuration (SKU, region, autoscale)
- Workspace permissions and role assignments
- Data pipeline schedules and triggers

**Branch protection:**
- `main` is protected: requires PR approval, no direct commits
- `dev` is unprotected: allows direct commits during development
- Feature branches follow standard git-flow conventions

## Alternatives Considered

### Alternative A: Capacity-level git integration
- **Pros:** Simpler configuration, one integration per capacity instead of per workspace
- **Cons:** All workspaces in the capacity must share the same repository and branch mapping; limits flexibility for multi-team or multi-project capacities

### Alternative B: Everything in git (including Terraform configs)
- **Pros:** Single source of truth, all infrastructure and code in one repository
- **Cons:** Fabric git integration cannot manage Terraform resources; mixing IaC with notebooks creates confusion about deployment tools; workspace permissions and schedules are not supported by Fabric git sync

### Alternative C: Notebooks only, pipeline JSON in Terraform
- **Pros:** Terraform can version control pipeline definitions as code
- **Cons:** Fabric UI cannot edit pipelines that are Terraform-managed; developers must use Terraform for pipeline changes instead of Fabric Studio

### Alternative D: Git integration disabled, all version control via Terraform
- **Pros:** Single tool (Terraform) for all infrastructure and configuration
- **Cons:** Notebook development workflow requires exporting from Fabric, committing to git, then Terraform apply — much slower than native git sync; TMDL models lose line-by-line diff capability

## Consequences

### Positive
- Notebooks and pipelines are version-controlled and code-reviewed before production deployment
- Branch-to-workspace mapping creates a clear promotion path: feature → dev → main → prod
- Separation of concerns: Fabric git integration manages code, Terraform manages infrastructure
- TMDL semantic models gain full git history and diff capability

### Negative
- Two tools (Fabric git integration + Terraform) must be kept in sync for each workspace
- Data in Lakehouse tables is not versioned — schema changes require manual coordination
- Pipeline schedules and triggers must be managed separately from pipeline definitions

### Risks
- If a workspace is disconnected from git and reconnected to a different branch, Fabric overwrites local changes
- Fabric git integration does not support all item types (e.g., KQL databases, Real-Time Intelligence items)
- Merge conflicts in pipeline JSON can be difficult to resolve manually

## References

- `templates/AGENTS-fabric.md` — superseded platform template
- `templates/AGENTS.md` — universal template that references this ADR
- Fabric git integration documentation: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/intro-to-git-integration
