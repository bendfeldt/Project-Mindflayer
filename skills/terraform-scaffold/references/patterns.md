# Canonical Terraform patterns

- Pin Terraform and provider versions with explicit compatible constraints and commit the dependency lock file.
- Use one root per independently deployed state boundary; compose small modules beneath it.
- Keep environment parity and pass differences as CI, vault, or non-sensitive configuration.
- Use remote state with locking, encryption, least privilege, and separate state per environment.
- Use OIDC workload identity in CI; do not use long-lived client secrets.
- Mark sensitive variables and outputs, but remember state still contains sensitive values in cleartext to state readers.
- Never generate or inspect environment `*.tfvars`. Provide only a non-sensitive `terraform.tfvars.example` when useful.
- Ignore `.terraform/`, state files, crash logs, plan artifacts, overrides, and all `*.tfvars`; explicitly allow only the example file.
- Validate with format, backend-free initialization, validation, and linting before any plan or mutation.

