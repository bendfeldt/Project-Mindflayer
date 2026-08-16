# Audit Report Contract

Use this order:

1. `## Executive Assessment`
2. `## Repository and Technology Overview`
3. `## Engineering Scorecard`
4. `## Prioritized Findings`
5. `## Remediation Roadmap`
6. `## Architecture and Modularity Recommendations`

Include scorecard rows for Data Engineering, Analytics Engineering, Software Engineering, Security, Compliance and Governance, Performance and Efficiency, and Maintainability and Modularity. Use whole-number `/10` scores or `Not assessed`. Explain each score with evidence; do not imply scientific precision.

Order findings by priority, severity, confidence, and expected impact. Use one cross-domain finding per root cause:

```markdown
### AUD-001 — Duplicate API ingestion behavior

**Domains:** Data Engineering, Software Engineering
**Category:** Reuse and maintainability
**Severity:** Medium
**Confidence:** High
**Priority:** P2
**Location:** `pipelines/customer.py:88`; `pipelines/order.py:61`
**Evidence:** Both pipelines independently implement equivalent pagination, retry, and response normalization.
**Problem:** The same integration contract is maintained in multiple implementations.
**Why it matters:** Fixes and API changes must be repeated and may diverge.
**Recommendation:** Extract the shared transport behavior behind one explicit ingestion component while keeping source-specific mapping separate.
**Suggested design:** Add a small API client module for pagination and retry; inject source-specific normalization functions.
**Expected benefit:** Consistent recovery behavior, one change point, and simpler integration tests.
**Implementation effort:** Small
```

Every material finding must contain every field. Use `Suggested design: No structural change required; ...` when remediation is local.

If no material findings exist, write exactly `No material findings identified.` under `## Prioritized Findings`; still document scope, checks, strengths, limitations, and applicable scores.

The roadmap should group findings into immediate, near-term, and later work without repeating their full evidence. Architecture recommendations must reference findings or say that no structural change is warranted.
