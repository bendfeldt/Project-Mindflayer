# Operating Standards

This document is normative guidance, not a record of historical decisions.

## Security and safety

- Never read or expose `.env*`, `*.tfvars`, private keys, credential files, or secret-bearing environment values.
- Reference secrets through vault lookups or environment-variable names, never literals.
- Read, inspect, validate, lint, and test may be automated. Deploy, destroy, authentication changes, secret mutation, branch deletion, and other shared-state mutations require explicit confirmation.
- Preserve existing user files unless replacement is explicitly authorized; create a timestamped backup before replacement.
- Databricks commands must always include an explicitly user-selected `--profile <name>`. Authentication-changing commands require confirmation.

## Engineering

- Prefer small, explicit, typed, single-purpose implementations.
- Use specific errors with actionable messages; do not swallow failures.
- Keep Dev, Test, and Prod structurally identical and vary configuration only.
- Use workload identity for automation and pin Terraform and provider versions.
- Do not generate readable `*.tfvars`; use non-secret examples plus vault or CI variable references.

## Data and compliance

- Prefer portable medallion and Kimball patterns while documenting vendor-specific lock-in.
- Treat GDPR, NIS2, ISO 27001, DS 484, and applicable public-sector law as design constraints when relevant.
- Put engagement-specific residency, retention, access, and naming rules in the client repository.

