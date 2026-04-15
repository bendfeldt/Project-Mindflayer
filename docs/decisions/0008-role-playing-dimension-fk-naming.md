# ADR-0008: Role-Playing Dimensions via Renamed FK Columns

**Status:** Accepted
**Date:** 2026-04-09
**Deciders:** Michael Bendfeldt

## Context

A single physical dimension (most commonly the calendar/date dimension) is often
referenced multiple times by the same fact table with different business meanings —
e.g., order date, ship date, posting date, document date. This is the "role-playing
dimension" pattern in Kimball modeling.

All three client engagements handle this identically: one physical dimension table,
multiple FK columns in the fact table each encoding both the dimension entity and
the role. The FK column naming differs between snake_case and PascalCase repos,
but the structure is the same.

## Decision

Role-playing dimensions always use **one physical dimension table** with **multiple
FK columns** in the fact table. Each FK column encodes the dimension entity and the
business role in a single column name.

**Column naming pattern (snake_case — canonical):**

```
{dimension}_{role}_id
```

Examples:
- `calendar_order_date_id` — references `dim.calendar`, role = order date
- `calendar_posting_date_id` — references `dim.calendar`, role = posting date
- `calendar_document_date_id` — references `dim.calendar`, role = document date
- `employee_manager_id` — references `dim.employee`, role = manager
- `employee_owner_id` — references `dim.employee`, role = owner

**Role name vocabulary:** Use business-process verbs and nouns. Prefer:
- Date roles: `order_date`, `posting_date`, `document_date`, `creation_date`,
  `shipping_date`, `settlement_date`
- Person roles: `manager`, `owner`, `approver`, `assignee`

Avoid ordinal names (`second_date`, `date_3`) — they carry no business meaning.

**Bridge table naming:**

Many-to-many relationships between two entities use a bridge table named
`{entity_1}_2_{entity_2}` (lowercase snake_case):

```
bridge.asset_2_legal_entity
bridge.employee_2_cost_center
bridge.fund_2_legal_entity
```

The ordering is: the "primary" entity first (the one the relationship originates from).

## Alternatives Considered

### Alternative A: Separate physical dimension table per role
- **Pros:** Each role is its own table; BI tools can reference it without aliases
- **Cons:** Identical data duplicated for each role; conformed dimension integrity breaks
  (updates to the base dimension must be applied to all copies); storage waste

### Alternative B: Views/aliases over one physical table (one physical, many logical)
- **Pros:** Avoids FK naming complexity; BI tools can reference role-named views
- **Cons:** Views add an indirection layer; FK constraints cannot reference views in most
  platforms; still requires the fact FK columns to reference the physical table

### Alternative C: Physical FK columns with role-encoded names — chosen
- **Pros:** One physical table, zero duplication; FK names encode meaning without extra
  objects; works across all platforms; consistent with observed client patterns
- **Cons:** Fact tables with many date roles accumulate multiple FK columns; query authors
  must remember which column maps to which role

## Consequences

### Positive
- Dimension data is never duplicated
- Fact table schema is self-documenting: `calendar_posting_date_id` is unambiguous
- Works with or without FK constraints (critical for Databricks and Fabric which rarely enforce FKs)

### Negative
- Fact tables with 5+ date roles become wide
- BI semantic models may need explicit role aliases to present user-friendly names

### Risks
- If a new role is added to an existing fact table, the FK column must be added and
  historical loads backfilled — plan for extensibility when declaring the grain

## References

- ADR-0005 — entity-prefix column naming (the `{dimension}_{role}_id` pattern follows from this)
- ADR-0006 — surrogate key conventions (role-playing FK always references `{entity}_id`)
- `/skills/kimball-model/SKILL.md` — Client-Validated DDL Patterns section (fact table example)
