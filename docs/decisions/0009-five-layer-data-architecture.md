# ADR-0009: Five-Layer Data Architecture as Standard

**Status:** Accepted
**Date:** 2026-04-09
**Deciders:** Michael Bendfeldt

## Context

The "medallion architecture" (bronze → silver → gold) is a widely used shorthand, but
in production implementations three layers are too coarse. Both dbx-lighthouse and
fab-AquaVilla independently adopted a five-layer pattern. NBEX SSMS maps to an equivalent
structure. The three-layer shorthand obscures important distinctions — particularly
between the enrichment stage (business rules, consolidation) and the curated stage
(dimensional model for consumption) — that lead to modeling decisions being made at the
wrong layer.

## Decision

The standard architecture uses five logical layers. Every engagement should be designed
against all five, even if some layers are thin or combined in the physical implementation:

| Layer | Logical name | Purpose |
|---|---|---|
| 1 | **ingest** | Source-format data; no transforms; exactly as received |
| 2 | **prepare** | Type casting, deduplication, validation, schema normalization |
| 3 | **enrich** | Business rules, consolidation across sources, derived attributes |
| 4 | **curate** | Dimensional model: `dim.*` and `fact.*` tables, ready for analytics |
| 5 | **serve** | Aggregated views, export schemas, semantic model entry point |

### Platform-specific layer mapping

| Logical layer | Databricks (Unity Catalog) | Microsoft Fabric | SQL Server |
|---|---|---|---|
| ingest | `{client}_landing_{env}` catalog / `landing` schema | `Landing` lakehouse | `stage` schema (raw) |
| prepare | `{client}_base_{env}` catalog / `base` or `raw` schema | `Base` lakehouse | `stage` schema (typed) |
| enrich | `{client}_enriched_{env}` catalog / `enriched` schema | `Enriched` lakehouse (optional) | Staging stored procedures |
| curate | `{client}_curated_{env}` catalog / `dim` + `fact` schemas | `Curated` lakehouse | `dim` + `fact` schemas |
| serve | `{client}_curated_{env}` catalog (shared) or separate | `Serve` workspace / Warehouse | `export*` schemas, views |

### Layer boundaries

- **ingest → prepare**: Add types, rename columns to snake_case, remove exact duplicates.
  Do NOT apply business rules here.
- **prepare → enrich**: Apply business rules, consolidate sources, derive calculated
  attributes. Do NOT create dimensional model objects here.
- **enrich → curate**: Build `dim_*` and `fact_*` tables. Apply SCD2. Generate surrogate keys.
  This is the only layer where dimensional model DDL belongs.
- **curate → serve**: Aggregations, cross-fact joins, export denormalisations, semantic model
  sources. Do NOT store raw or intermediate data here.

## Alternatives Considered

### Alternative A: Three-layer medallion (bronze/silver/gold)
- **Pros:** Simple mental model; widely understood in the industry; fewer physical objects
- **Cons:** "Silver" conflates prepare + enrich, leading to business logic appearing too
  early (in what should be a technical cleansing layer); "gold" conflates curated dimensional
  model with serve/export; wrong decisions about where SCD2 and surrogate keys belong

### Alternative B: Two-layer (raw + presentation)
- **Pros:** Maximally simple
- **Cons:** Only viable for small, single-source models; immediately breaks down at scale
  or when multiple sources must be consolidated

### Alternative C: Five-layer — chosen
- **Pros:** Clear separation between technical data quality (prepare) and business logic
  (enrich); explicit boundary for where the dimensional model lives (curate); serve layer
  decoupled from the warehouse structure
- **Cons:** More physical objects; requires understanding which layer each transform belongs to

## Consequences

### Positive
- Business analysts and data engineers have a clear contract: curate = final dimensional model
- Debugging is faster — a data issue can be traced to its originating layer
- The enrich layer can be skipped for simple single-source models without breaking the architecture
- Matches the physical implementation of both active client frameworks (Lighthouse, AquaVilla)

### Negative
- More schemas/lakehouses to provision and manage
- New engineers need to understand the five-layer contract before contributing

### Risks
- If the enrich layer is skipped habitually, business logic accumulates in the prepare layer,
  degrading the architecture over time — mitigate by making the layer boundary explicit in AGENTS.md

## References

- `/skills/kimball-model/SKILL.md` — Medallion Mapping section (updated to five layers)
- dbx-lighthouse `/documentation/features/architecture-and-layers.md` — origin of the five-layer pattern
- fab-AquaVilla architecture documentation — confirms the same pattern on Fabric
