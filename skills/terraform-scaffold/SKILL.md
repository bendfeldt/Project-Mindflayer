---
name: terraform-scaffold
description: Scaffold a portable, pinned Terraform repository or module with workload-identity CI and safe secret handling.
---

# Terraform Scaffold

Read [canonical Terraform patterns](references/patterns.md), then load only the relevant provider reference.

1. Confirm cloud, providers, state backend, environments, CI platform, and module boundary.
2. Present the proposed file tree and version pins for approval.
3. Generate valid HCL and YAML with one root configuration and composable modules.
4. Use workload identity in CI and vault or CI-variable references for sensitive inputs.
5. Generate `terraform.tfvars.example` only with non-sensitive placeholders; never generate readable environment `*.tfvars`.
6. Run `terraform fmt -check`, `terraform init -backend=false`, `terraform validate`, and available linters.

Do not run plan, apply, import, state mutation, authentication, or deployment without separate approval.
