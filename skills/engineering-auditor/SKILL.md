---
name: engineering-auditor
description: Audit software, data, analytics, infrastructure, and platform repositories across data engineering, analytics engineering, software engineering, security, compliance, governance, performance, modularity, and maintainability. Use when reviewing a repository, subdirectory, file set, local pull-request diff, pipeline, SQL or dbt project, application, infrastructure-as-code, CI/CD configuration, or technical solution to produce evidence-based, prioritized remediation recommendations.
---

# Engineering Auditor

Perform a read-only engineering audit. Inspect, understand, identify, prioritize, and recommend. Do not modify production code unless the user separately authorizes remediation after reviewing the findings.

## Audit workflow

1. Confirm the requested scope: repository, subdirectory, explicit files, or local change/PR diff with repository context.
2. Read repository instructions. Never read prohibited secret-bearing files or values.
3. Run `scripts/repository_inventory.py` against the scope, then verify its technology detection through targeted inspection.
4. Map architecture, data flow, module boundaries, existing standards, and configured test, lint, security, and build tooling before recommending anything new.
5. Read [the audit framework](references/audit-framework.md) and only the applicable domain references:
   - [Data engineering](references/data-engineering.md)
   - [Analytics engineering](references/analytics-engineering.md)
   - [Software engineering](references/software-engineering.md)
   - [Security](references/security.md)
   - [Compliance and governance](references/compliance-governance.md)
   - [Performance](references/performance.md)
6. Consolidate the same root cause into one cross-domain finding. Prefer material findings over exhaustive style commentary.
7. Apply [severity, confidence, priority, and effort](references/finding-severity.md).
8. Write the report using [the output contract](references/output-format.md), then run `scripts/validate_audit_report.py` against it.

## Evidence rules

- Support every material finding with repository evidence and precise file/line locations whenever available.
- State what is wrong, why it matters, how serious and certain it is, what should change, the expected benefit, and implementation effort.
- Distinguish correctness defects from preferences, confirmed vulnerabilities from unsafe patterns, and measured performance problems from probable or speculative opportunities.
- Use `Evidence not found in repository` only when absence is itself relevant; identify what organizational verification remains.
- Never claim legal or regulatory compliance from repository inspection alone.
- Do not infer runtime behavior that static evidence cannot establish. Lower confidence or request measurement instead.
- Before asserting an exact token, syntax, or correctness defect, reread the targeted source without summarization and run the repository's native parser, compiler, or validator where available. Never reconstruct source code from abbreviated tool output.

## Recommendation rules

- Prefer deletion, existing repository patterns, standard-library capabilities, and existing dependencies before adding abstractions or tools.
- Recommend reuse only when it reduces inconsistency, risk, duplicated change, or testing cost.
- Keep audit mode separate from remediation mode. Do not edit production code, create external resources, authenticate, deploy, or mutate shared state during an audit.
- If no material findings exist, say so explicitly; never invent findings to populate the report.

## Script usage

```bash
python3 scripts/repository_inventory.py --root <repository-or-subdirectory>
python3 scripts/repository_inventory.py --root <repository> --file path/to/a.py --file path/to/b.sql
python3 scripts/validate_audit_report.py <audit-report.md>
```

On native Windows, invoke the same scripts with `python` instead of `python3`.

Resolve script paths relative to this skill directory, not the current working directory.
