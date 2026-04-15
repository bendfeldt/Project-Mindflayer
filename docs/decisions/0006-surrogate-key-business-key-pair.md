# ADR-0006: Surrogate Key + Business Key as Mandatory Dimension Pair

**Status:** Accepted
**Date:** 2026-04-09
**Deciders:** Michael Bendfeldt

## Context

Dimension tables need two distinct identifiers serving different purposes: one for
warehouse joins (insulated from source changes) and one for ETL operations (stable
source identifier used to detect changes and match records across loads).

Using only a natural key exposes the warehouse to source system key changes. Using only
a surrogate key makes it impossible to perform SCD2 matching or cross-system lookups.
All three client engagements enforce both keys on every dimension.

The unknown/missing member pattern also needs standardizing — NULLable FK columns in
fact tables break simple aggregations and require IS NULL special cases everywhere.

## Decision

Every dimension table will carry exactly two key columns:

1. **Surrogate key** (`{entity}_id`): integer, system-generated, auto-incrementing or
   identity. Used for all foreign key relationships in fact tables. Never exposed to
   end users or upstream systems. The unknown/missing member row always has `{entity}_id = -1`.

2. **Business key** (`{entity}_key`): stable source identifier. Used by ETL to match
   incoming records against existing dimension rows. Never used as a FK join column.
   For unknown members, set to `'?'` (string) or `-1` (integer).

All integer FK columns in fact tables carry `DEFAULT -1`, pointing to the unknown member
row. NULL is never permitted in a fact-to-dimension foreign key.

### Calendar dimension exception

The calendar dimension may use a single key where the calendar date expressed as an
integer (`YYYYMMDD`) serves as both the surrogate and business key (e.g., `calendar_id = 20260401`).
This is acceptable only for the calendar dimension because:
- Calendar rows never change (no SCD2 needed)
- The integer date key is fully stable and source-independent

## Alternatives Considered

### Alternative A: Natural key only (no surrogate)
- **Pros:** Simpler schema; direct traceability to source
- **Cons:** Breaks when source renames/reassigns keys; multi-source conforming is impossible;
  requires knowledge of source system conventions in BI tools and queries

### Alternative B: Surrogate key only (no business key)
- **Pros:** Simpler ETL — no matching logic needed for full reloads
- **Cons:** SCD2 requires a stable identifier to match "same record, new version";
  impossible to cross-reference warehouse data back to source without business key

### Alternative C: Surrogate + business key pair — chosen
- **Pros:** Clean separation of warehouse join key vs. ETL matching key; source-agnostic
  joins; enables SCD2; enables multi-source dimension conforming
- **Cons:** Every dimension carries two keys; ETL must maintain the mapping

## Consequences

### Positive
- Fact table joins are insulated from source system key changes
- SCD2 matching is unambiguous — ETL always uses business key for matching
- Unknown members handled consistently via -1 across all dimensions
- NULLable FK columns are eliminated from fact tables

### Negative
- Calendar and other "static" dimensions carry an unused business key (acceptable overhead)
- ETL must maintain a surrogate key lookup for every dimension

### Risks
- If a business key is not truly stable (e.g., source reuses codes), SCD2 matching
  will produce false matches — mitigated by validating business key stability during onboarding

## References

- ADR-0007 — SCD2 audit column triplet (how version rows are tracked)
- ADR-0010 — column naming: `{entity}_id` and `{entity}_key` suffixes
- `/skills/kimball-model/SKILL.md` — SCD Type 2 section and DDL examples
