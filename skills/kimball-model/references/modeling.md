# Canonical Kimball patterns

The grain is a sentence describing exactly one fact row. Confirm it before physical design.

- Facts contain measurements at the declared grain and foreign keys to dimensions.
- Dimensions contain descriptive context and use surrogate keys to isolate source-key changes.
- Reuse conformed dimensions only when keys, attributes, and meaning are truly shared.
- Use an explicit unknown member for unresolved references.
- Choose SCD behavior per attribute: Type 1 for correction, Type 2 for required history, Type 0 for immutable values.
- Type 2 rows use effective timestamps, an exclusive end timestamp, and one current-row indicator with non-overlapping intervals.
- Role-playing dimensions reuse one physical dimension with role-specific foreign-key names.
- Validate uniqueness, referential integrity, interval overlap, current-row cardinality, and additive behavior.

Use lowercase snake_case unless repository guidance explicitly overrides it. Keep the logical model portable; isolate platform-specific identity, merge, and date syntax.

