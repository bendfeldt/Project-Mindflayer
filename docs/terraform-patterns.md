# Terraform Patterns

This is normative, vendor-neutral Terraform guidance.

## Structure

- Use one root module per independently deployed state boundary.
- Compose small, cohesive modules; expose explicit typed inputs and outputs.
- Keep Dev, Test, and Prod structurally identical and vary configuration only.
- Separate state by environment and blast radius.

## Versions and state

- Pin Terraform and providers with explicit compatible constraints.
- Commit the dependency lock file.
- Use encrypted remote state with locking, least privilege, and recovery controls.
- Treat state as sensitive even when variables and outputs are marked sensitive.

## Authentication and configuration

- Use OIDC workload identity for CI/CD; avoid long-lived client secrets.
- Resolve secrets from a vault or protected CI variables.
- Never generate or inspect environment `*.tfvars`. A non-sensitive `terraform.tfvars.example` may document input shape.
- Ignore state, plan files, crash logs, override files, `.terraform/`, and all `*.tfvars` except the example.

## Validation boundary

Formatting, backend-free initialization, validation, linting, and read-only inspection are validation. Planning, applying, importing, state mutation, authentication changes, and deployment require explicit approval appropriate to their side effects.
