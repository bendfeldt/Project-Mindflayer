# ADR-0016: Databricks Unity Catalog Structure

**Status:** Accepted
**Date:** 2026-04-21
**Deciders:** Michael Bendfeldt

## Context

Databricks Unity Catalog projects require a standardized namespace structure to organize
tables across ingestion, cleansing, and serving layers. The question was how to structure
catalogs and schemas to support multi-environment workflows (dev/test/prod) while
maintaining the medallion architecture pattern.

Without a standard structure, teams create inconsistent naming schemes, mix environments
in a single catalog, or fail to separate sandbox exploration from production assets.

## Decision

We adopt a **catalog-per-environment** structure with **schema-per-layer** organization:

```
catalog: {client}_{env}
├── bronze    ← raw ingestion, no transformations
├── silver    ← cleansed, deduplicated, typed
├── gold      ← dimensional model (Kimball star schemas)
└── sandbox   ← ad-hoc exploration (dev only)
```

Each environment (dev, test, prod) gets its own catalog. The catalog name follows the
pattern `{client}_{environment}` (e.g., `acme_prod`, `acme_dev`).

The four-schema layout aligns with medallion architecture: bronze for raw data, silver
for cleansed, gold for business-ready dimensional models, and sandbox for ephemeral
exploration work.

## Alternatives Considered

### Alternative A: Schema-per-environment, shared catalog
- **Pros:** Single catalog simplifies permissions; fewer catalogs to manage; easier cross-environment queries
- **Cons:** Mixes dev and prod data in same catalog; cannot use catalog-level permissions; backup/restore affects all environments; harder to isolate blast radius
- **Rejected:** Fails to isolate environments at the catalog boundary, making disaster recovery and access control more complex

### Alternative B: Catalog-per-layer (bronze/silver/gold)
- **Pros:** Clean separation of concerns; can permission entire layers independently; aligns with data engineering org structure
- **Cons:** Cross-layer queries require three-part names; dev/test/prod mixed within each catalog; no sandbox isolation; environment promotion requires cross-catalog moves
- **Rejected:** Solves the wrong problem — layer separation is already achieved with schemas; environment isolation is the primary concern

### Alternative C: Flat schema naming (no layers)
- **Pros:** Simpler namespace; no medallion ceremony; direct table names
- **Cons:** No visual separation of raw vs. curated data; harder to apply layer-specific policies (e.g., Photon on gold only); loses medallion architecture benefits
- **Rejected:** Medallion architecture is a core pattern; abandoning it for namespace simplicity is a bad trade

## Consequences

### Positive
- Clear environment isolation at the catalog level — dev cannot accidentally read prod, backup/restore is scoped to one environment
- Catalog-level permissions map cleanly to environment access (e.g., analysts get read on `{client}_prod` only)
- Three-schema medallion layout is immediately recognizable to any Databricks engineer
- Sandbox schema provides a safe space for exploratory work without polluting production namespaces

### Negative
- Cross-environment queries (e.g., comparing dev and prod tables) require catalog switching or three-part names
- Per-catalog Unity Catalog costs may apply depending on Databricks pricing model
- Sandbox schema in production is unused — could be omitted, but consistency across environments simplifies tooling

### Risks
- If a client requires catalog-per-domain architecture (e.g., sales, finance, operations), this pattern must be adapted to `{client}_{domain}_{env}` or nested schemas
- Very large clients may hit Unity Catalog catalog limits (unlikely but possible)

## References

- `templates/AGENTS.md` — universal repo instruction file referencing this ADR per platform
- Superseded `templates/AGENTS-databricks.md` — original source of this convention
- Medallion architecture: bronze (raw) → silver (cleansed) → gold (curated)
- Databricks Unity Catalog best practices: catalog-per-environment is the recommended isolation model
