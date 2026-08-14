---
name: kimball-model
description: Design Kimball dimensional models, including grain, facts, dimensions, conformance, and slowly changing dimensions.
---

# Kimball Model

Read [the canonical modeling reference](references/modeling.md) before producing a model.

1. Resolve the target platform from repository guidance or ask.
2. Identify the business process and propose an explicit grain for approval.
3. Identify facts, dimensions, conformed dimensions, and attribute-level history requirements.
4. Present the logical star schema and trade-offs before generating DDL.
5. Generate platform-correct, lowercase snake_case implementation only after approval.
6. Validate joins, key uniqueness, unknown members, additive behavior, and SCD tests.

Keep vendor-specific syntax separate from the logical model.
