# ADR-0013: Fabric Semantic Model Design Standards

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Fabric semantic models (formerly Power BI datasets) can be stored as PBIX files or as
TMDL (Tabular Model Definition Language) in git. They can connect to data sources via
Import, DirectQuery, or DirectLake modes. Without a default pattern, client repos
make inconsistent choices about storage format and connection mode, leading to:

- PBIX files that cannot be diff'd or code-reviewed in git
- Import mode models that require manual refresh schedules
- DirectQuery models that place heavy query load on source systems
- Inconsistent naming that obscures the relationship between models and reports

## Decision

**Storage format:** TMDL in git. All semantic models are version-controlled as text.

**Connection mode:** DirectLake preferred. Fall back to Import only when DirectLake
is not supported (e.g., source is external SQL Server, not Fabric Lakehouse).

**Naming conventions:**
- Semantic models: `SM_{Domain}` (e.g., `SM_Sales`, `SM_Inventory`)
- Reports: `RPT_{Domain}_{Name}` (e.g., `RPT_Sales_Monthly`, `RPT_Inventory_Status`)

**Design principles:**
- One semantic model per business domain (not per report)
- Reports connect via live connection (no embedded models)
- Model measures and calculations live in the semantic model, not in report visuals

## Alternatives Considered

### Alternative A: PBIX files in git
- **Pros:** Native Power BI format, easier for report authors to edit locally
- **Cons:** Binary format cannot be diff'd or code-reviewed; merge conflicts are unresolvable; no line-by-line change history

### Alternative B: Import mode as default
- **Pros:** Fast query performance, no dependency on source system uptime, supports data from any source
- **Cons:** Requires scheduled refresh, data is always stale by at least the refresh interval, duplicates storage, increases capacity costs

### Alternative C: DirectQuery mode
- **Pros:** Always queries live data, no refresh schedule needed, no data duplication
- **Cons:** Places query load on source system, slower performance, limited DAX function support, not optimized for Fabric Lakehouse

### Alternative D: DirectLake mode (chosen)
- **Pros:** Queries live Delta tables from Lakehouse with near-Import performance, no refresh schedule, no data duplication, optimized for Fabric
- **Cons:** Only works with Fabric Lakehouse sources, not external systems

## Consequences

### Positive
- TMDL enables code review, diff comparison, and line-by-line change tracking
- DirectLake provides Import-like performance with DirectQuery-like freshness
- Naming convention makes semantic model / report relationships explicit
- One model per domain encourages reuse and reduces redundant measure definitions

### Negative
- TMDL requires tooling (Tabular Editor or VS Code extension) to author effectively
- DirectLake restricts semantic models to Fabric Lakehouse sources only
- Teams must manage model versioning and downstream report dependencies manually

### Risks
- If DirectLake performance degrades under heavy concurrency, Import mode may become necessary
- TMDL tooling ecosystem is less mature than PBIX, may require training investment
- Composite models (DirectLake + Import) are not addressed by this ADR and may require per-client decisions

## References

- `templates/AGENTS-fabric.md` — superseded platform template
- `templates/AGENTS.md` — universal template that references this ADR
- TMDL documentation: https://learn.microsoft.com/en-us/power-bi/developer/projects/projects-overview
- DirectLake documentation: https://learn.microsoft.com/en-us/power-bi/enterprise/directlake-overview
