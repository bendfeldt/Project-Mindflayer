# ADR-0012: Fabric Medallion Layer Architecture

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Microsoft Fabric supports both Lakehouse (Delta Lake) and Warehouse (SQL) as data
storage and serving layers. Without a default architecture, client repos make inconsistent
choices about where data lands, where it is transformed, and where it is served from.
This leads to confusion about when to use each technology and creates inconsistent
patterns across engagements.

The medallion architecture pattern (Bronze → Silver → Gold) is widely adopted in
Databricks, but Fabric workspaces encourage verb-based naming (Ingest, Transform,
Persist, Serve, Report) that better reflects data flow than metal tier metaphors.

## Decision

We adopt a five-layer verb-based medallion architecture for Fabric engagements:

```
Ingest    ← Pipelines, Dataflows, Shortcuts (raw data ingestion)
Transform ← Spark notebooks (cleansing, enrichment)
Persist   ← Lakehouse (Delta tables as system of record)
Serve     ← Warehouse (SQL views, optimized for queries)
Report    ← Power BI reports (visualization layer)
```

**Lakehouse vs. Warehouse rules:**
- Data lands and is stored in Lakehouse (Delta tables)
- Data is served from Warehouse (SQL views sourced from Lakehouse tables)
- Semantic models source from Warehouse views, not Lakehouse tables directly

**Workspace naming:** `{ClientPrefix}-{Env}-{Verb}` (e.g., `PN-Prod-Persist`)
**Lakehouse naming:** `{ClientPrefix}{Env}{Verb}` (e.g., `PNProdPersist`)
**Warehouse naming:** `{ClientPrefix}{Env}Serve` (e.g., `PNProdServe`)

## Alternatives Considered

### Alternative A: Bronze/Silver/Gold medallion (Databricks style)
- **Pros:** Industry standard, widely recognized, aligns with Databricks patterns
- **Cons:** "Bronze/Silver/Gold" are abstract metaphors that don't describe what happens in each layer; less intuitive for new team members; Fabric workspaces favor verb-based naming

### Alternative B: Warehouse-only architecture
- **Pros:** Simpler mental model with one storage technology; SQL-native teams can work without learning Spark/Delta
- **Cons:** Warehouses lack native support for streaming, change data capture, and versioned Delta tables; less cost-effective for large raw data volumes; semantic models benefit from DirectLake mode which requires Lakehouse

### Alternative C: Lakehouse-only architecture (chosen path variant)
- **Pros:** Single storage technology, leverages DirectLake for semantic models, optimized for large-scale analytics
- **Cons:** SQL-native teams must learn Spark notebooks; lacks SQL-optimized query performance for ad-hoc reporting; warehouse provides better concurrency and query optimization for BI tools

## Consequences

### Positive
- Clear separation of concerns: Lakehouse stores data, Warehouse serves queries
- DirectLake semantic models benefit from Lakehouse storage while BI users query via Warehouse
- Verb-based naming is self-documenting and aligns with Fabric workspace conventions
- Pattern is portable across clients with only prefix and environment changes

### Negative
- Introduces two storage technologies instead of one, increasing operational complexity
- Requires maintaining views in Warehouse that mirror Lakehouse tables
- Teams must understand both Delta Lake and SQL Warehouse semantics

### Risks
- If Warehouse views are not kept in sync with Lakehouse schema changes, downstream reports break
- DirectLake mode may require revisiting this pattern if Microsoft changes licensing or performance characteristics

## References

- `templates/AGENTS-fabric.md` — superseded platform template
- `templates/AGENTS.md` — universal template that references this ADR
- Fabric Lakehouse documentation: https://learn.microsoft.com/en-us/fabric/data-engineering/lakehouse-overview
- Fabric Warehouse documentation: https://learn.microsoft.com/en-us/fabric/data-warehouse/data-warehousing
