---
name: terraform-scaffold
description: >
  Scaffold Terraform infrastructure-as-code projects and modules. Use when the user
  asks to "set up Terraform", "scaffold IaC", "create a Terraform module", "bootstrap
  infrastructure", or discusses provisioning cloud resources with code. Covers Azure
  (primary), GCP, and cloud-agnostic patterns. Also trigger when the user mentions
  "microsoft/fabric provider", "azurerm", "google provider", Terraform workspaces,
  remote state, or module structure. Not project-specific — adapts to any client.
---

# Terraform Scaffold

Scaffold production-grade Terraform projects following consistent patterns across
client engagements. The structure should be portable and opinionated about
organization while remaining flexible about cloud provider.

## Project Structure

Use this layout for all new Terraform projects:

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf          # Module calls with dev-specific parameters
│   │   ├── variables.tf     # Variable declarations
│   │   ├── terraform.tfvars # Dev values (NOT committed if contains secrets)
│   │   ├── backend.tf       # Remote state config for dev
│   │   └── outputs.tf
│   ├── test/
│   │   └── (same structure)
│   └── prod/
│       └── (same structure)
├── modules/
│   ├── module-name/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── README.md
│   └── ...
├── .terraform.lock.hcl      # Always commit this
├── .gitignore
└── README.md
```

## Core Principles

1. **Environment parity** — Dev, Test, and Prod are structurally identical. Differences
   are expressed only through variable values, never through different resource definitions.

2. **Modules for reuse** — Any resource group that appears in more than one environment
   or could be reused across clients goes into `modules/`.

3. **Secrets in vaults** — Never hardcode secrets. Reference Azure Key Vault, GCP Secret
   Manager, or OpenBao. Use `data` sources to read secrets at plan time.

4. **Remote state** — Always use remote backends (Azure Storage, GCS, S3).
   State files never live locally or in git.

5. **Explicit provider pinning** — Pin provider and Terraform versions in `required_providers`.

## Provider Patterns

### Azure (azurerm + microsoft/fabric)

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

### GCP

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
```

## Variable Conventions

- Use descriptive names: `storage_account_name`, not `sa_name`
- Always include `description` and `type` on every variable
- Use `validation` blocks for constraints (e.g., allowed regions, naming patterns)
- Group variables logically with comments: `# --- Network ---`, `# --- Storage ---`
- Sensitive variables get `sensitive = true`

```hcl
variable "environment" {
  description = "Deployment environment (dev, test, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}
```

## Naming Convention

Use a consistent naming pattern across all resources:

```
{client_prefix}-{environment}-{resource_type}-{purpose}
```

Example: `kbt-dev-st-datalake`, `pn-prod-kv-secrets`

Express this as a local:

```hcl
locals {
  name_prefix = "${var.client_prefix}-${var.environment}"
}
```

## Tagging

Apply consistent tags to all resources:

```hcl
locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.project_name
    CostCenter  = var.cost_center
  }
}
```

## Module Design

When creating a module:

1. Keep it focused — one module = one logical resource group
2. Expose only what consumers need via `outputs.tf`
3. Include a `README.md` with usage examples
4. Use `variable` defaults sparingly — prefer explicit inputs
5. Never hardcode environment-specific values inside a module

## Scaffolding Workflow

When asked to scaffold a new project:

1. **Ask** which cloud provider(s) and what's being provisioned
2. **Ask** about environments needed (default: dev/test/prod)
3. **Ask** about remote state backend preference
4. **Create** the directory structure above
5. **Generate** skeleton files with proper provider config, backend, and variable structure
6. **Create** a `.gitignore` that excludes `.terraform/`, `*.tfstate`, `*.tfvars` (unless
   the team explicitly wants tfvars in git)
7. **Add** a README with setup instructions

## .gitignore Template

```
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
!terraform.tfvars.example
crash.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
```

## CI/CD Integration

For Azure DevOps pipelines, the standard stages are:

```
terraform init → terraform validate → terraform plan → (manual approval) → terraform apply
```

For GitHub Actions, the same flow applies with environment protection rules on the apply step.

Always output the plan to a file (`-out=tfplan`) and apply from that file — never run
a bare `terraform apply` in CI.

## Platform-Specific References

Load these reference files when the project involves the relevant technology.
Read the appropriate file before generating platform-specific code.

| Context signal                                     | Load reference                  |
|----------------------------------------------------|---------------------------------|
| Azure DevOps, ADO pipelines, YAML pipelines        | `references/azure-devops-pipelines.md` |
| Microsoft Fabric, Fabric workspaces, lakehouse, semantic model | `references/fabric-modules.md` |

These references contain ready-to-use module examples, pipeline templates, and
deployment patterns. Read the relevant file rather than generating from scratch —
the patterns have been validated across engagements.
