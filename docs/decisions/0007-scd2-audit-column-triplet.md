# ADR-0007: SCD2 Audit Column Triplet Pattern

**Status:** Accepted
**Date:** 2026-04-09
**Deciders:** Michael Bendfeldt

## Context

SCD Type 2 dimensions track historical attribute values by adding a new row for each change
rather than overwriting. This requires three tracking columns to mark the validity period
of each row. Additionally, all dimension and fact tables carry general audit columns that
record when rows were created or modified by the warehouse process — these are distinct
from SCD2 tracking but travel alongside it.

Both dbx-lighthouse and fab-AquaVilla use the same `lh_`-prefixed column names (shared
framework). NBEX SSMS uses `DW`-prefixed column names. The column structure is identical
across all three; only the prefix differs.

## Decision

### SCD2 tracking columns (triplet)

Every SCD2 dimension carries exactly these three columns, grouped at the end of the schema,
after all business attribute columns and before the general audit block:

| Column | Type | Current row value | Expired row value |
|---|---|---|---|
| `lh_valid_from` | TIMESTAMP | Load timestamp | Original load timestamp |
| `lh_valid_to` | TIMESTAMP | `9999-12-31 23:59:59` | Expiry timestamp |
| `lh_is_current` | BOOLEAN | `TRUE` | `FALSE` |

### General audit columns

All dimension and fact tables (SCD1 and SCD2) carry these columns:

| Column | Type | Purpose |
|---|---|---|
| `lh_created_date` | TIMESTAMP | When this row was first written to the warehouse |
| `lh_modified_date` | TIMESTAMP | When this row was last updated by the ETL |
| `lh_is_deleted` | BOOLEAN | Soft delete flag — `FALSE` unless source record no longer exists |

### Validation columns (dimensions only, optional)

When a quarantine/validation pattern is in use:

| Column | Type | Purpose |
|---|---|---|
| `lh_quarantine_rules` | STRING | Rules that caused quarantine (NULL if clean) |
| `lh_is_quarantined` | BOOLEAN | Whether the row failed validation |

### Prefix convention

The `lh_` prefix identifies these as warehouse framework columns — not business attributes.
No business column may use the `lh_` prefix. This convention is shared between the
Lighthouse (Databricks) and AquaVilla (Fabric) frameworks. When working in a SQL Server
context with an existing `DW`-prefixed convention, maintain that prefix for consistency
within that engagement but document it as an equivalent pattern.

### Sentinel values

- `valid_to` for current rows: `9999-12-31 23:59:59` (never NULL)
- Unknown member row: `lh_valid_from = '1900-01-01 00:00:00'`, `lh_valid_to = '9999-12-31 23:59:59'`,
  `lh_is_current = TRUE`

## Alternatives Considered

### Alternative A: NULL for valid_to on current rows
- **Pros:** Marginally more storage-efficient; semantically correct (no expiry = NULL)
- **Cons:** Every query filtering for current rows requires `WHERE valid_to IS NULL`; this
  breaks range-based time-travel queries; all three client repos explicitly avoided this

### Alternative B: is_current only (no valid_from/valid_to)
- **Pros:** Simplest structure; easy to filter current
- **Cons:** Impossible to answer "what was the value on date X?"; not true SCD2 — just a soft-delete pattern

### Alternative C: Triplet (valid_from, valid_to, is_current) — chosen
- **Pros:** Enables both current-row queries (via `is_current`) and point-in-time queries
  (via `valid_from <= date < valid_to`); is_current is a performance shortcut for the
  common case without requiring date arithmetic
- **Cons:** Three columns instead of one; is_current is technically redundant given valid_to

## Consequences

### Positive
- Point-in-time queries work without special cases
- Current-row queries are fast via the `is_current` index
- The triplet is unambiguous across engineers and BI tools

### Negative
- Three columns per SCD2 dimension vs. one (is_current only)
- ETL must set all three on every INSERT and UPDATE

### Risks
- If `is_current` and the valid_to date become inconsistent (ETL bug), queries
  will return wrong results — mitigated by testing `is_current = (valid_to = '9999-12-31 23:59:59')` after every load

## References

- ADR-0006 — surrogate key and unknown member row (sk = -1 also carries audit triplet)
- `/skills/kimball-model/SKILL.md` — SCD Type 2 section, DDL pattern with lh_ columns
