# ADR-0005: Entity-Prefix Column Naming as the Default Convention

**Status:** Accepted
**Date:** 2026-04-09
**Deciders:** Michael Bendfeldt

## Context

Dimensional models frequently join many dimension tables to a single fact table. Without
a naming discipline, column names like `name`, `amount`, `code`, `status` become ambiguous
— they could belong to any entity in the query. This problem compounds in wide denormalized
models and in BI tools where columns from multiple tables appear side by side.

Three client engagements (dbx-lighthouse, fab-AquaVilla, NBEX) independently evolved to
the same pattern: every column carries the entity name as its prefix.

## Decision

All columns in dimension and fact tables will follow the three-part structure:

```
{entity}_{qualifier}_{class}
```

- **entity**: the business object the column describes (e.g., `customer`, `calendar`, `sales`)
- **qualifier**: optional additional specification (e.g., `order_date`, `gross`, `first`)
- **class**: what the value represents (see ADR-0010 for the full class suffix vocabulary)

No column may be named by its class alone. `amount` is not a valid column name.
`sales_gross_amount_dkk` is.

The entity prefix is the entity that *owns* the attribute — not the table it sits in.
When a foreign key from `dim_customer` appears in `fact_sales`, the column retains
`customer_id` (not `fact_sales_customer_id`).

## Alternatives Considered

### Alternative A: No prefix — natural names only
- **Pros:** Short, readable in isolation (`amount`, `city`, `is_active`)
- **Cons:** Ambiguous in joins; `SELECT *` from a star schema produces collisions; BI tools
  show duplicate column names; impossible to know which entity a column describes without
  looking at its table

### Alternative B: Table prefix on every column (e.g., `fact_sales_amount`)
- **Pros:** Fully unambiguous
- **Cons:** Extremely verbose and redundant; the schema/table already carries the table context;
  entity prefix is what carries semantic meaning, not the full table name

### Alternative C: Entity prefix — chosen
- **Pros:** Self-documenting in JOINs and SELECT *; matches business vocabulary; consistent
  across dimension and fact tables; works in denormalized export models
- **Cons:** Column names become longer; requires discipline to maintain the entity name
  consistently across layers

## Consequences

### Positive
- Query results are self-documenting — rows identify themselves without schema inspection
- Column name collisions are eliminated in wide joins
- The entity in a column name is always the business entity, enabling consistent BI labeling

### Negative
- Column names are verbose (intentionally)
- New contributors must understand which entity owns an attribute before naming columns

### Risks
- If the entity name changes (e.g., `customer` → `client`), all derived columns must be
  renamed — mitigated by using conformed entity names from the start

## References

- ADR-0010 — class suffix vocabulary (the allowed values for the `{class}` component)
- `/skills/kimball-model/SKILL.md` — Column Pattern Reference section
- dbx-lighthouse `/documentation/features/conventions.md` — source of the original pattern
