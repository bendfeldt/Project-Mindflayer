---
name: kimball-model
description: >
  Design and implement Kimball-style dimensional models. Use when the user mentions
  "dimensional model", "star schema", "fact table", "dimension table", "SCD",
  "slowly changing dimension", "conformed dimension", "bus matrix", "grain",
  "Kimball", "surrogate key", or discusses designing data warehouse tables. Also
  trigger for medallion architecture modeling, data vault to Kimball translation,
  or when the user asks about modeling patterns for Databricks, Fabric, or SQL Server.
  Not project-specific — applies to any data platform engagement.
version: 1.0.0
updated: 2026-04-23
---

# Kimball Dimensional Modeling

Design dimensional models that are query-friendly, business-aligned, and
maintainable across platform changes. These patterns apply whether you're
building in Databricks, Microsoft Fabric, or SQL Server.

## Platform-Aware Output

The dimensional modeling principles below are universal. When generating DDL,
example queries, or implementation code, adapt the syntax to the target platform.

**Platform resolution order:**

1. **Repo AGENTS.md** (preferred) — look for a `platform:` declaration in the project's
   AGENTS.md. When present, use it directly without further detection.
2. **File-based detection** (fallback) — infer from project files:

| Signal in project                         | Platform        | Adapt output to          |
|-------------------------------------------|-----------------|--------------------------|
| `.py` with `from pyspark` or `spark.sql`, DLT notebooks | **Databricks**  | PySpark / Spark SQL, Delta Lake DDL, Unity Catalog namespaces |
| Fabric lakehouse/warehouse artifacts, `.Notebook`, TMDL | **Microsoft Fabric** | T-SQL or Spark SQL, Fabric lakehouse schemas, semantic model hints |
| AGENTS.md `platform: sqlserver`, `.sql` with T-SQL patterns | **SQL Server** | T-SQL DDL, `[schema].[table]` bracket quoting, `IDENTITY(1,1)` |

3. **Ask** — if neither source resolves the platform, ask: "Which platform are we
   implementing this on?" Don't guess.

When the platform is clear, apply these implementation differences:

### Surrogate Keys

- **Databricks**: `BIGINT GENERATED ALWAYS AS IDENTITY` (Unity Catalog) or `monotonically_increasing_id()`
- **Fabric Warehouse**: `INT IDENTITY(1,1)`
- **SQL Server**: `INT IDENTITY(1,1)` or `BIGINT IDENTITY(1,1)`

### SCD Type 2

- **Databricks**: `MERGE INTO` with Delta Lake, or DLT `APPLY CHANGES INTO`
- **Fabric**: `MERGE` in warehouse, or notebook-based for lakehouse
- **SQL Server**: `MERGE INTO` in T-SQL

### Incremental Loading

- **Databricks**: DLT expectations + `APPLY CHANGES`, or manual `MERGE INTO`
- **Fabric**: Pipeline copy activities → lakehouse staging → MERGE
- **SQL Server**: ADF pipeline with watermark pattern → staging table → `MERGE INTO`

### Date Dimension Generation

- **Databricks**: PySpark `sequence()` + `explode()` or SQL `GENERATE_SERIES` (DBR 14+)
- **Fabric**: T-SQL CTE with recursive date generation or Power Query in Dataflow Gen2
- **SQL Server**: T-SQL recursive CTE or a numbers table cross join

## Core Concepts (Quick Reference)

- **Grain** — The single most important decision. What does one row represent?
  Define it before anything else. Write it as a sentence: "One row represents
  one [business event] at [level of detail]."

- **Fact tables** — Store measurements (metrics) at the declared grain.
  Foreign keys to dimensions. Additive, semi-additive, or non-additive measures.

- **Dimension tables** — Store descriptive context. Wide and denormalized.
  Business-friendly column names. Include surrogate keys and business keys.

- **Conformed dimensions** — Shared across fact tables. Same keys, same
  attributes, same meaning. Essential for cross-process analytics.

- **Surrogate keys** — Integer synthetic keys that insulate the warehouse from
  source system key changes. Never use natural keys as the primary join key.

## Design Workflow

When asked to design a dimensional model:

1. **Identify the business process** — What are we measuring?
2. **Declare the grain** — State it explicitly. Get user confirmation before proceeding.
3. **Identify dimensions** — Who, what, where, when, why, how?
4. **Identify facts** — What numeric measurements occur at this grain?
5. **Check for conformed dimensions** — Does this model share dimensions with existing models?
6. **Handle slowly changing dimensions** — Determine SCD type per attribute.
7. **Draw it out** — Present the model as a concise table listing before writing any DDL.

## Naming Conventions

**Canonical standard: lowercase snake_case for all objects on all platforms.**
(See ADR-0010 for rationale. PascalCase in legacy client repos is not the standard.)

### Table naming

| Context | Pattern | Example |
|---|---|---|
| Databricks / SQL Server | Schema-separated | `fact.orders`, `dim.customer` |
| Fabric curated lakehouse | Schema-separated | `fact.retail_sales`, `dim.product` |
| Bridge tables | `bridge.{entity_1}_2_{entity_2}` | `bridge.asset_2_legal_entity` |
| Staging | `stage.{source}_{entity}` | `stage.erp_customers` |

### Column naming

All columns follow `{entity}_{qualifier}_{class}`. No bare class names (`amount`, `name`,
`code` alone are not valid). The entity prefix is the *owning entity*, not the table name.

| Column role | Pattern | Example |
|---|---|---|
| Surrogate key | `{entity}_id` | `customer_id`, `calendar_id` |
| Business key | `{entity}_key` | `customer_key`, `calendar_key` |
| FK in fact (simple) | `{entity}_id` | `customer_id`, `product_id` |
| FK in fact (role-playing) | `{entity}_{role}_id` | `calendar_order_date_id`, `calendar_posting_date_id` |
| Boolean flag | `{entity}_is_{condition}` | `calendar_is_week_day`, `asset_is_deleted` |
| Audit column | `lh_{purpose}` | `lh_created_date`, `lh_is_current` |

All integer FK columns in fact tables carry `DEFAULT -1`, pointing to the unknown member row.

### Column class suffix vocabulary

| Suffix | Meaning | Example |
|---|---|---|
| `_id` | Surrogate/FK key (integer) | `customer_id` |
| `_key` | Business key (source identifier) | `customer_key` |
| `_code` | Code value (not a key) | `asset_brand_code` |
| `_name` | Human-readable label | `asset_brand_name` |
| `_number` | Numeric identifier | `invoice_number` |
| `_description` | Free-text description | `product_description` |
| `_date` | Calendar date | `asset_acquisition_date` |
| `_amount_{ccy}` | Monetary amount | `sales_gross_amount_dkk` |
| `_quantity` | Count of physical units | `sales_quantity` |
| `_count` | Count of records | `employee_count` |
| `_rate` | Rate or ratio | `occupancy_rate` |
| `_duration_days` | Duration in days | `lease_duration_days` |
| `_is_{condition}` | Boolean flag | `calendar_is_week_day` |
| `_utc` / `_cet` | Timezone-qualified timestamp | `event_created_at_utc` |

**Code+Name pair rule:** whenever a `_code` column exists, a `_name` column with the
same entity+qualifier prefix must accompany it (`asset_brand_code` + `asset_brand_name`).

## Slowly Changing Dimensions

### SCD Type 1 — Overwrite

- Use when historical values don't matter (e.g., correcting a typo)
- Implementation: simple UPDATE on the dimension row

### SCD Type 2 — Track History

- Use when you need to analyze against the value that was true *at the time*
- Required columns (the **audit triplet**, grouped at end of schema):

| Column | Type | Current row | Expired row |
|---|---|---|---|
| `lh_valid_from` | TIMESTAMP | load timestamp | original load timestamp |
| `lh_valid_to` | TIMESTAMP | `9999-12-31 23:59:59` | expiry timestamp |
| `lh_is_current` | BOOLEAN | `TRUE` | `FALSE` |

- General audit columns (on all tables, not SCD2-specific):

| Column | Type | Purpose |
|---|---|---|
| `lh_created_date` | TIMESTAMP | When this row was first written |
| `lh_modified_date` | TIMESTAMP | Last ETL update |
| `lh_is_deleted` | BOOLEAN | Soft delete from source |

```sql
-- SCD2 dimension (Spark SQL / Delta Lake)
CREATE TABLE dim.customer (
    customer_id       BIGINT GENERATED ALWAYS AS IDENTITY,
    customer_key      STRING NOT NULL,         -- business key for ETL matching
    customer_name     STRING,
    customer_segment  STRING,                  -- SCD2 tracked
    lh_valid_from     TIMESTAMP NOT NULL,
    lh_valid_to       TIMESTAMP NOT NULL,      -- 9999-12-31 for current row
    lh_is_current     BOOLEAN NOT NULL,
    lh_created_date   TIMESTAMP NOT NULL,
    lh_modified_date  TIMESTAMP NOT NULL,
    lh_is_deleted     BOOLEAN NOT NULL DEFAULT FALSE
) USING DELTA;

-- Unknown member row (always pre-inserted)
INSERT INTO dim.customer VALUES (
    -1, '?', 'Unknown', 'Unknown',
    TIMESTAMP '1900-01-01', TIMESTAMP '9999-12-31 23:59:59', TRUE,
    current_timestamp(), current_timestamp(), FALSE
);
```

### SCD Type 3 — Previous Value Column

- Use only when you need exactly "current" and "previous" — rare in practice
- Prefer Type 2 unless storage/complexity is a real concern

## Medallion Mapping

Five logical layers map to platform-specific names:

| Logical layer | Databricks schema | Fabric workspace | SQL Server schema | Purpose |
|---|---|---|---|---|
| **ingest** | `{client}_landing_{env}` | `Landing` lakehouse | `stage` (raw) | Source-format, no transforms |
| **prepare** | `{client}_base_{env}` | `Base` lakehouse | `stage` (typed) | Type, validate, deduplicate |
| **enrich** | `{client}_enriched_{env}` | `Enriched` lakehouse | Staging procs | Business rules, consolidation |
| **curate** | `{client}_curated_{env}` | `Curated` lakehouse | `dim` / `fact` schemas | Dimensional model |
| **serve** | `{client}_curated_{env}` | `Serve` workspace | `export*` schemas | Aggregates, semantic model |

Layer boundaries:
- **prepare** = types, rename to snake_case, dedup. No business rules.
- **enrich** = business rules, cross-source consolidation. No dimensional DDL.
- **curate** = `dim_*` and `fact_*` objects, SCD2, surrogate key generation.
- **serve** = aggregations, export views, Power BI semantic model sources.

Notebook naming convention (Fabric): `load_dim_{entity}.notebook`, `load_fact_{entity}.notebook`

## Implementation Patterns by Platform

### Databricks (Unity Catalog + DLT/Spark Declarative Pipelines)

```
catalog: {client}_curated_{env}
├── schema: dim      -- dimension tables
└── schema: fact     -- fact tables
```

Key Databricks conventions:
- Unity Catalog three-level namespace: `catalog.schema.table`
- DLT for prepare layer; notebooks for curate layer
- Delta Lake `MERGE INTO` for SCD2 and incremental loads
- `APPLY CHANGES INTO` in DLT for streaming SCD2

### Microsoft Fabric

```
Workspace: {Client} - Core [{env}]
├── Landing lakehouse     -- ingest layer
├── Base lakehouse        -- prepare layer
├── Curated lakehouse     -- curate layer
└── Serve warehouse       -- serve layer (T-SQL views, semantic model)
```

Key Fabric conventions:
- Curated lakehouse for Delta storage, Serve warehouse for SQL analytics endpoint
- Notebooks (PySpark/snake_case) for transformations; T-SQL views in warehouse for serving
- Semantic models in the Serve workspace for Power BI

### SQL Server

```
SQL Server: {client}
├── schema: dim       -- dimension tables
├── schema: fact      -- fact tables
├── schema: bridge    -- many-to-many relationships
├── schema: stage     -- staging and preparation
└── schema: export    -- serve layer views and exports
```

Key SQL Server conventions:
- Use `[schema].[table_name]` bracket quoting for reserved word conflicts (e.g., `[order]`)
- `IDENTITY(1,1)` for surrogate keys; `MERGE INTO` for SCD2 and incremental loads
- Views in `export` schema as semantic model entry points for Power BI / Analysis Services
- ADF pipelines orchestrate ETL; stored procedures in `stage` for complex transformation rules
- `DW` prefix for audit columns when following the existing NBEX convention (equivalent to `lh_`)

## Date Dimension

Every dimensional model needs a date dimension. Generate it, don't load from a source.

Essential columns (snake_case): `calendar_id`, `calendar_key` (DATE), `calendar_year`,
`calendar_month_of_year`, `calendar_month_name`, `calendar_quarter_of_year`,
`calendar_day_of_week`, `calendar_day_name`, `calendar_is_week_day` (BOOLEAN),
`calendar_is_last_day_of_month` (BOOLEAN), `calendar_week_of_year_iso`.

For Danish contexts: use `calendar_week_of_year_iso` (ISO 8601) — not US week numbering.

## Client-Validated DDL Patterns

Production-ready patterns from client engagements. Use these as the baseline.

### Dimension table (Spark SQL / Delta Lake)

```sql
-- dim.product: full pattern with entity-prefix, surrogate+business key,
-- Code+Name pair, lh_ audit columns, SCD2 triplet, unknown member

CREATE TABLE dim.product (
    -- Keys
    product_id              BIGINT GENERATED ALWAYS AS IDENTITY,
    product_key             STRING NOT NULL,        -- stable source identifier
    -- Descriptive attributes
    product_name            STRING,
    product_brand_code      INT,                    -- Code+Name pair
    product_brand_name      STRING,
    product_type_code       INT,                    -- Code+Name pair
    product_type_name       STRING,
    product_status          STRING,
    product_standard_cost   DECIMAL(18,4),
    -- SCD2 triplet
    lh_valid_from           TIMESTAMP NOT NULL,
    lh_valid_to             TIMESTAMP NOT NULL,
    lh_is_current           BOOLEAN NOT NULL,
    -- General audit
    lh_created_date         TIMESTAMP NOT NULL,
    lh_modified_date        TIMESTAMP NOT NULL,
    lh_is_deleted           BOOLEAN NOT NULL DEFAULT FALSE
) USING DELTA;

-- Unknown member (pre-insert before any fact loads)
INSERT INTO dim.product VALUES (
    -1, '?', 'Unknown', NULL, 'Unknown', NULL, 'Unknown', 'Unknown', NULL,
    TIMESTAMP '1900-01-01', TIMESTAMP '9999-12-31 23:59:59', TRUE,
    current_timestamp(), current_timestamp(), FALSE
);
```

### Fact table with role-playing date FKs (Spark SQL)

```sql
-- fact.general_ledger_actual: role-playing calendar dimension,
-- entity-prefixed measures, DEFAULT -1 on all FK columns

CREATE TABLE fact.general_ledger_actual (
    -- Role-playing date FKs (three roles → same dim.calendar)
    calendar_creation_date_id   BIGINT NOT NULL DEFAULT -1,
    calendar_posting_date_id    BIGINT NOT NULL DEFAULT -1,
    calendar_document_date_id   BIGINT NOT NULL DEFAULT -1,
    -- Other dimension FKs
    legal_entity_id             BIGINT NOT NULL DEFAULT -1,
    ledger_account_id           BIGINT NOT NULL DEFAULT -1,
    cost_center_id              BIGINT NOT NULL DEFAULT -1,
    currency_id                 BIGINT NOT NULL DEFAULT -1,
    -- Degenerate dimension (transaction identifier, no dim table)
    general_ledger_actual_unique_code   STRING NOT NULL,
    general_ledger_actual_document_number STRING,
    -- Measures
    general_ledger_actual_amount        DECIMAL(28,12),
    general_ledger_actual_amount_eur    DECIMAL(28,12),
    -- Audit
    lh_created_date             TIMESTAMP NOT NULL,
    lh_modified_date            TIMESTAMP NOT NULL
) USING DELTA;

-- Columnstore-equivalent: Z-ORDER for analytics optimization (Databricks)
-- OPTIMIZE fact.general_ledger_actual ZORDER BY (calendar_posting_date_id, legal_entity_id);
```

### Bridge table

```sql
-- bridge.asset_2_legal_entity: many-to-many between dim.asset and dim.legal_entity
-- Naming convention: {entity_1}_2_{entity_2}

CREATE TABLE bridge.asset_2_legal_entity (
    asset_id                BIGINT NOT NULL DEFAULT -1,
    legal_entity_id         BIGINT NOT NULL DEFAULT -1,
    asset_ownership_share   DECIMAL(5,4),           -- 0.0–1.0, non-additive
    lh_created_date         TIMESTAMP NOT NULL,
    lh_modified_date        TIMESTAMP NOT NULL,
    PRIMARY KEY (asset_id, legal_entity_id)         -- composite PK
) USING DELTA;
```

## Common Pitfalls to Flag

- **Undeclared grain** — the #1 cause of broken models. Always state it explicitly.
- **Snowflaking dimensions** — resist normalizing dimensions unless there's a compelling
  performance reason. Flat and wide is correct for Kimball.
- **Fact table without surrogate keys on dimensions** — natural keys leak source system
  assumptions into the warehouse.
- **Missing conformed dimensions** — if two fact tables share Customer but use different
  customer tables, analytics across them will be wrong.
- **NULL foreign keys** — use a dedicated unknown member row (sk = -1) instead of NULLs.
  All FK columns carry `DEFAULT -1`.
- **Missing business key** — surrogate key alone makes SCD2 matching impossible. Every
  dimension must have both `{entity}_id` and `{entity}_key`.
- **Business logic in prepare layer** — keep prepare strictly technical (types, dedup).
  Business rules belong in enrich.

## Related Decisions

See `docs/decisions/` for the rationale behind these patterns:
ADR-0005 (entity-prefix naming) · ADR-0006 (surrogate+business key pair) ·
ADR-0007 (SCD2 audit triplet) · ADR-0008 (role-playing FK naming) ·
ADR-0009 (five-layer architecture) · ADR-0010 (snake_case universal standard)
