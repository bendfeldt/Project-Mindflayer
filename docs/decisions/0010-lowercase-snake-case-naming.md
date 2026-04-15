# ADR-0010: Lowercase Snake_case as Universal Naming Convention

**Status:** Accepted
**Date:** 2026-04-09
**Deciders:** Michael Bendfeldt

## Context

Client engagements use different naming styles inherited from their platforms and
prior history: dbx-lighthouse uses lowercase snake_case throughout; NBEX SSMS uses
PascalCase; fab-AquaVilla uses PascalCase in the curated layer. Having multiple casing
conventions within the consultant's toolkit creates inconsistency across engagements
and makes shared patterns harder to apply directly.

## Decision

**Lowercase snake_case is the canonical naming convention for all new objects** —
tables, columns, schemas, keys, and views — regardless of target platform.

This applies to:
- Schema names: `dim`, `fact`, `bridge`, `landing`, `base`
- Table names: `dim.customer`, `fact.general_ledger_actual`, `bridge.asset_2_legal_entity`
- Column names: `customer_id`, `calendar_order_date_id`, `sales_gross_amount_dkk`
- Surrogate key: `{entity}_id`
- Business key: `{entity}_key`
- FK in fact: `{entity}_{role}_id`
- Boolean flags: `{entity}_is_{condition}`
- Audit columns: `lh_created_date`, `lh_is_current`, `lh_valid_from`

### Class suffix vocabulary (the `{class}` component from ADR-0005)

| Suffix | Meaning | Example |
|---|---|---|
| `_id` | Surrogate/foreign key (integer) | `customer_id`, `calendar_order_date_id` |
| `_key` | Business key (stable source identifier) | `customer_key`, `calendar_key` |
| `_code` | Code value (not a key; rename from source) | `asset_brand_code`, `asset_status_code` |
| `_name` | Human-readable label | `asset_brand_name`, `customer_name` |
| `_number` | Numeric identifier from source | `employee_number`, `invoice_number` |
| `_description` | Free-text description | `product_description` |
| `_date` | Calendar date | `asset_acquisition_date`, `order_date` |
| `_amount_{ccy}` | Monetary amount with currency | `sales_gross_amount_dkk`, `portfolio_value_amount_eur` |
| `_quantity` | Count of physical units | `sales_quantity`, `order_quantity` |
| `_count` | Count of records/events | `employee_count`, `transaction_count` |
| `_rate` | Rate or ratio (0–1 or 0–100) | `occupancy_rate`, `discount_rate` |
| `_duration_days` | Duration in days | `lease_duration_days` |
| `_is_{condition}` | Boolean flag | `calendar_is_week_day`, `asset_is_deleted` |
| `_utc` | Timestamp in UTC | `event_created_at_utc` |
| `_cet` | Timestamp in CET | `report_generated_at_cet` |

**Code+Name pair rule:** whenever a `_code` column exists, a `_name` column with the same
entity and qualifier prefix must accompany it. Example: `asset_brand_code` requires
`asset_brand_name` in the same table.

### SQL Server / T-SQL compatibility

On platforms with case-insensitive default collation (SQL Server, Fabric Warehouse), lowercase
snake_case works without modification. Use bracket quoting `[schema].[table_name]` when the
object name conflicts with a reserved T-SQL keyword (e.g., `[order]`, `[group]`).

### Legacy/inherited conventions

The PascalCase patterns in NBEX SSMS and fab-AquaVilla curated layer are retained as-is
in those existing repos (do not rename live production objects). All new objects within
those engagements follow the snake_case standard; divergences are flagged during code review.

## Alternatives Considered

### Alternative A: Follow platform convention (snake_case for PySpark, PascalCase for T-SQL)
- **Pros:** Each platform looks "native"; no mental translation when reading DDL
- **Cons:** Different conventions per engagement; patterns from one repo cannot be applied
  directly to another; cross-platform refactoring is harder; the skill and templates would
  need dual-track examples

### Alternative B: PascalCase everywhere
- **Pros:** Consistent with SQL Server/T-SQL tradition; many BI tools display PascalCase well
- **Cons:** PySpark and Spark SQL are case-insensitive by convention but prefer lowercase;
  Databricks Unity Catalog normalises to lowercase; mixed case in Python variable names is
  inconsistent with PEP 8

### Alternative C: Lowercase snake_case everywhere — chosen
- **Pros:** Works natively in PySpark, Spark SQL, and standard SQL; compatible with T-SQL via
  collation and quoting; single standard across all engagements; skill and templates only
  need one set of examples
- **Cons:** Departs from SQL Server/T-SQL convention; existing PascalCase repos require
  a transition strategy for new objects

## Consequences

### Positive
- All skill DDL examples use a single casing standard
- New engagement onboarding is unambiguous: always snake_case
- Cross-platform pattern reuse is direct — no mental translation needed

### Negative
- NBEX and AquaVilla have a coexistence period where old objects are PascalCase and
  new ones are snake_case
- T-SQL tooling (SSMS, Redgate) that auto-completes in PascalCase needs configuration

### Risks
- A T-SQL view referencing both a snake_case new table and a PascalCase old table may
  confuse engineers — mitigate by documenting the transition boundary in AGENTS.md

## References

- ADR-0005 — entity-prefix column naming (`{entity}_{qualifier}_{class}` structure)
- ADR-0006 — surrogate/business key naming (`{entity}_id` / `{entity}_key`)
- ADR-0007 — audit column naming (`lh_` prefix, lowercase)
- `/skills/kimball-model/SKILL.md` — Naming Conventions section
