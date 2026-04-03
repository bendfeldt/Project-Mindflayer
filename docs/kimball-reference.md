# Kimball Modeling Quick Reference

## The Four-Step Design Process

1. **Select the business process** → What are we measuring?
2. **Declare the grain** → One row = one ___?
3. **Identify the dimensions** → Who, what, where, when, why, how?
4. **Identify the facts** → What are the measurements?

## Fact Table Types

| Type              | Description                                    | Example                |
|-------------------|------------------------------------------------|------------------------|
| Transaction       | One row per event at the atomic grain           | fct_orders             |
| Periodic snapshot | One row per entity per period                   | fct_account_monthly    |
| Accumulating      | One row per entity lifecycle, updated over time | fct_claim_processing   |
| Factless          | Records events with no measures                 | fct_student_attendance |

## Measure Additivity

| Type           | Behavior                                      | Example         |
|----------------|-----------------------------------------------|-----------------|
| Additive       | Sum across all dimensions                     | revenue, quantity |
| Semi-additive  | Sum across some dimensions (not time)         | balance, inventory |
| Non-additive   | Cannot be summed                              | ratio, percentage |

## SCD Decision Matrix

| SCD Type | When to use                        | Storage impact |
|----------|------------------------------------|----------------|
| Type 0   | Value never changes (date of birth)| None           |
| Type 1   | Overwrite, history irrelevant      | None           |
| Type 2   | Full history tracking needed       | High           |
| Type 3   | Only current + previous needed     | Low            |

## Junk Dimensions

Combine low-cardinality flags and indicators into a single "junk dimension"
rather than polluting the fact table with multiple boolean/flag columns.

Example: `dim_order_flags` combining `is_rush`, `is_gift_wrapped`, `payment_type_code`

## Degenerate Dimensions

Business identifiers that live in the fact table (no separate dimension table).
Example: `order_number` in `fct_order_lines` — it has no additional attributes
worth storing in a dimension.

## Role-Playing Dimensions

A single physical dimension referenced multiple times from a fact table with
different meanings.

Example: `dim_date` joined as `order_date_sk`, `ship_date_sk`, `delivery_date_sk`.
In dbt, implement as separate views or aliases over the same underlying model.
