---
name: kimball-model
description: >
  Design and implement Kimball-style dimensional models. Use when the user mentions
  "dimensional model", "star schema", "fact table", "dimension table", "SCD",
  "slowly changing dimension", "conformed dimension", "bus matrix", "grain",
  "Kimball", "surrogate key", or discusses designing data warehouse tables. Also
  trigger for medallion architecture modeling (bronze/silver/gold), data vault to
  Kimball translation, or when the user asks about modeling patterns for
  Databricks, Fabric, dbt, or Trino. Not project-specific — applies to any
  data platform engagement.
---

# Kimball Dimensional Modeling

Design dimensional models that are query-friendly, business-aligned, and
maintainable across platform changes. These patterns apply whether you're
building in Databricks, Microsoft Fabric, dbt, or a Trino-based lakehouse.

## Platform-Aware Output

The dimensional modeling principles below are universal. However, when generating
DDL, example queries, or implementation code, adapt the syntax to the target platform.

**Platform resolution order:**

1. **Repo AGENTS.md** (preferred) — look for a `platform:` declaration in the project's
   AGENTS.md. When present, use it directly without further detection.
2. **File-based detection** (fallback) — if no platform is declared, infer from project files:

| Signal in project                         | Platform        | Adapt output to          |
|-------------------------------------------|-----------------|--------------------------|
| `dbt_project.yml`, `models/`, `.sql` with `{{ ref() }}` | **dbt Core**    | Jinja SQL, `ref()`, `source()`, schema.yml tests |
| `.py` with `from pyspark` or `spark.sql`, DLT notebooks | **Databricks**  | PySpark / Spark SQL, Delta Lake DDL, Unity Catalog namespaces |
| Fabric lakehouse/warehouse artifacts, `.Notebook`, TMDL | **Microsoft Fabric** | T-SQL or Spark SQL, Fabric lakehouse schemas, semantic model hints |
| `.sql` with `CREATE TABLE ... WITH (format = 'ICEBERG')`, Trino catalogs | **Trino/Iceberg** | Trino SQL, Iceberg partitioning, schema evolution |

3. **Ask** — if neither source resolves the platform, ask: "Which platform are we
   implementing this on?" Don't guess — a wrong assumption leads to rewriting DDL.

When the platform is clear, apply these implementation differences:

### Surrogate Keys

- **dbt**: Use `dbt_utils.generate_surrogate_key()` or `dbt_utils.surrogate_key()`
- **Databricks**: `md5(concat_ws('|', col1, col2))` or `monotonically_increasing_id()` for simple cases
- **Fabric Warehouse**: `IDENTITY(1,1)` columns or hash-based via `HASHBYTES()`
- **Trino**: `uuid()` or hash-based via `xxhash64()`
- **Generic**: Note that the surrogate key strategy depends on the platform

### SCD Type 2

- **dbt**: Use `dbt_utils.snapshot` or `dbt.snapshot()` with `strategy='check'` or `strategy='timestamp'`
- **Databricks**: `MERGE INTO` with Delta Lake, or DLT `APPLY CHANGES INTO`
- **Fabric**: `MERGE` statements in warehouse, or notebook-based for lakehouse
- **Trino/Iceberg**: `MERGE INTO` with Iceberg (requires v2 tables)

### Incremental Loading

- **dbt**: `{{ config(materialized='incremental', unique_key='...') }}`
- **Databricks**: DLT expectations + `APPLY CHANGES`, or manual `MERGE INTO`
- **Fabric**: Pipeline copy activities → lakehouse staging → MERGE
- **Trino**: Trino doesn't natively do incremental — orchestrate via Dagster/Airflow with partition filters

### Date Dimension Generation

- **dbt**: `dbt_date.get_date_dimension()` macro or custom seed + model
- **Databricks**: PySpark `sequence()` + `explode()` or SQL `GENERATE_SERIES` (DBR 14+)
- **Fabric**: T-SQL CTE with recursive date generation or Power Query in Dataflow Gen2
- **Trino**: `UNNEST(SEQUENCE(DATE '2020-01-01', DATE '2030-12-31', INTERVAL '1' DAY))`

If unsure which platform, ask: "Which platform are we implementing this on?"
Don't guess — a wrong assumption leads to rewriting DDL.

## Core Concepts (Quick Reference)

- **Grain** — The single most important decision. What does one row represent?
  Define it before anything else. Write it as a sentence: "One row represents
  one [business event] at [level of detail]."

- **Fact tables** — Store measurements (metrics) at the declared grain.
  Foreign keys to dimensions. Additive, semi-additive, or non-additive measures.

- **Dimension tables** — Store descriptive context. Wide and denormalized.
  Business-friendly column names. Include surrogate keys.

- **Conformed dimensions** — Shared across fact tables. Same keys, same
  attributes, same meaning. Essential for cross-process analytics.

- **Surrogate keys** — Integer or hash-based synthetic keys that insulate the
  warehouse from source system key changes. Never use natural keys as the
  primary join key in the dimensional model.

## Design Workflow

When asked to design a dimensional model:

1. **Identify the business process** — What are we measuring? (Orders, visits,
   claims, deliveries, etc.)
2. **Declare the grain** — State it explicitly as a sentence. Get user
   confirmation before proceeding.
3. **Identify dimensions** — Who, what, where, when, why, how?
4. **Identify facts** — What numeric measurements occur at this grain?
5. **Check for conformed dimensions** — Does this model share dimensions with
   existing models? (Date, Customer, Product, Geography, etc.)
6. **Handle slowly changing dimensions** — Determine SCD type per attribute.
7. **Draw it out** — Present the model as a concise table listing or diagram
   before writing any DDL or dbt models.

## Naming Conventions

Use these prefixes consistently across all engagements:

| Prefix   | Usage                | Example              |
|----------|----------------------|----------------------|
| `fct_`   | Fact tables          | `fct_orders`         |
| `dim_`   | Dimension tables     | `dim_customer`       |
| `brg_`   | Bridge tables        | `brg_customer_group` |
| `stg_`   | Staging (bronze/silver) | `stg_orders`      |
| `int_`   | Intermediate transforms | `int_orders_enriched` |

Column naming:
- Surrogate keys: `{table}_sk` (e.g., `customer_sk`)
- Natural/business keys: `{table}_bk` or descriptive name (e.g., `customer_number`)
- Foreign keys: match the target dimension's surrogate key name
- Dates: `{event}_date` (e.g., `order_date`)
- Timestamps: `{event}_at` (e.g., `created_at`)
- Booleans: `is_{condition}` (e.g., `is_active`)
- Measures: descriptive with unit hint (e.g., `order_amount_dkk`, `quantity_ordered`)

## Slowly Changing Dimensions

### SCD Type 1 — Overwrite

- Use when: historical values don't matter (e.g., correcting a typo)
- Implementation: Simple UPDATE on the dimension row

### SCD Type 2 — Track History

- Use when: you need to analyze against the value that was true *at the time*
  (e.g., customer address for delivery analysis)
- Required columns: `valid_from`, `valid_to`, `is_current`
- `valid_to` for the current row: use a far-future date (`9999-12-31`), not NULL
- Surrogate key changes with each new version

```sql
-- SCD2 dimension structure
CREATE TABLE dim_customer (
    customer_sk       BIGINT,         -- Surrogate key (new per version)
    customer_bk       STRING,         -- Business key (stable)
    customer_name     STRING,
    address_line1     STRING,         -- SCD2 tracked
    city              STRING,         -- SCD2 tracked
    segment           STRING,         -- SCD1 overwrite
    valid_from        DATE,
    valid_to          DATE,           -- 9999-12-31 for current
    is_current        BOOLEAN
);
```

### SCD Type 3 — Previous Value Column

- Use when: you only need "current" and "previous" (e.g., `current_region`, `previous_region`)
- Rare in practice. Prefer Type 2 unless storage/complexity is a real concern.

## Medallion Mapping

The medallion architecture (bronze → silver → gold) maps naturally to the
dimensional modeling workflow:

| Layer      | Purpose                        | Modeling Stage              |
|------------|--------------------------------|-----------------------------|
| **Bronze** | Raw ingestion, 1:1 with source | `stg_` staging models       |
| **Silver** | Cleansed, typed, deduplicated  | `int_` intermediate models  |
| **Gold**   | Business-ready dimensional model | `fct_` and `dim_` models  |

## Implementation Patterns by Platform

### dbt Core

```
models/
├── staging/          # Bronze → Silver (stg_)
│   └── source_name/
│       ├── _source.yml
│       ├── stg_orders.sql
│       └── stg_customers.sql
├── intermediate/     # Silver transforms (int_)
│   └── int_orders_enriched.sql
├── marts/            # Gold — dimensional model (fct_, dim_)
│   ├── core/
│   │   ├── dim_customer.sql
│   │   ├── dim_date.sql
│   │   └── fct_orders.sql
│   └── finance/
│       └── fct_revenue.sql
└── _schema.yml       # Tests and documentation
```

Key dbt conventions:
- One model per file
- Staging models: rename, cast, and deduplicate — no joins
- Intermediate models: enrich and combine staging models
- Mart models: final dimensional model with surrogate keys and business logic
- Always define `unique` and `not_null` tests on keys

### Databricks (Unity Catalog + DLT/Spark Declarative Pipelines)

```
catalog: {client}_{environment}        # e.g. kombit_dev
├── schema: bronze                     # Raw ingestion
│   └── stg_orders, stg_customers
├── schema: silver                     # Cleansed + typed
│   └── int_orders_enriched
└── schema: gold                       # Dimensional model
    └── fct_orders, dim_customer, dim_date
```

Key Databricks conventions:
- Use Unity Catalog three-level namespace: `catalog.schema.table`
- DLT for bronze→silver; notebooks or dbt-databricks for silver→gold
- Delta Lake `MERGE INTO` for SCD2 and incremental loads
- `APPLY CHANGES INTO` in DLT for streaming SCD2
- Cluster/warehouse column statistics for query optimization

### Microsoft Fabric

```
Lakehouse: {Client}{Environment}Persist    # e.g. PostNordProdPersist
├── Tables/bronze/                          # Managed Delta tables
│   └── stg_orders, stg_customers
├── Tables/silver/
│   └── int_orders_enriched
└── Tables/gold/
    └── fct_orders, dim_customer, dim_date

Warehouse: {Client}{Environment}Serve       # SQL analytics endpoint
└── Views/gold/                             # Views over lakehouse tables
```

Key Fabric conventions:
- Lakehouse for storage (Delta/Parquet), Warehouse for SQL serving
- Verb-based workspace naming: Ingest → Transform → Persist → Serve → Report
- Notebooks (PySpark) or Dataflow Gen2 for transforms
- Semantic models in the Serve/Report workspace for Power BI
- T-SQL views in Warehouse for conformed dimension access

### Trino + Iceberg

```
catalog: iceberg_{environment}
├── schema: bronze
│   └── stg_orders (Iceberg, partitioned by ingestion_date)
├── schema: silver
│   └── int_orders_enriched (Iceberg)
└── schema: gold
    └── fct_orders, dim_customer (Iceberg, partitioned by date_sk)
```

Key Trino/Iceberg conventions:
- Iceberg v2 tables for `MERGE INTO` support (SCD2, upserts)
- Partition by date or another high-cardinality filter column
- Hidden partitioning (partition transforms) — don't require users to know partition layout
- Schema evolution is non-breaking — add columns freely
- Use dbt-trino adapter when combining dbt + Trino

## Date Dimension

Every dimensional model needs a date dimension. Generate it, don't load it from a source.

Essential columns: `date_sk`, `date_actual`, `day_of_week`, `day_name`,
`month_number`, `month_name`, `quarter`, `year`, `is_weekend`,
`is_holiday`, `fiscal_year`, `fiscal_quarter`.

For Danish contexts: include `iso_week_number` (ISO 8601) — this is what
Danish businesses use, not US week numbering.

## Common Pitfalls to Flag

- **Undeclared grain** — the #1 cause of broken models. Always state it explicitly.
- **Snowflaking dimensions** — resist normalizing dimensions unless there's a
  compelling performance reason. Flat and wide is correct for Kimball.
- **Fact table without surrogate keys on dimensions** — natural keys leak
  source system assumptions into the warehouse.
- **Missing conformed dimensions** — if two fact tables share Customer but use
  different customer tables, analytics across them will be wrong.
- **NULL foreign keys** — use a dedicated "Unknown" or "Not Applicable" dimension
  row (sk = -1) instead of NULLs in fact tables.
