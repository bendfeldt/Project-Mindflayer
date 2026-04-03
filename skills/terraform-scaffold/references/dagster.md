# Dagster Orchestration Patterns

Reference for provisioning Dagster infrastructure alongside data platform resources.
Load this reference when the project involves Dagster for orchestration.

## Dagster Deployment Options

### Docker Compose (development / small deployments)

Terraform doesn't directly manage Docker Compose, but you can provision the
underlying infrastructure (VM, storage, networking) and template the compose file.

### Kubernetes (K3s or AKS/GKE)

The preferred production pattern. Dagster provides a Helm chart; Terraform manages
the cluster and the Helm release.

```hcl
resource "helm_release" "dagster" {
  name             = "${local.name_prefix}-dagster"
  repository       = "https://dagster-io.github.io/helm"
  chart            = "dagster"
  version          = var.dagster_chart_version
  namespace        = "dagster"
  create_namespace = true

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      environment          = var.environment
      postgres_host        = var.dagster_postgres_host
      postgres_password    = var.dagster_postgres_password
      storage_account_name = var.storage_account_name
      storage_account_key  = var.storage_account_key
    })
  ]
}
```

### Key Infrastructure for Dagster

Regardless of deployment method, Dagster needs:

1. **PostgreSQL database** — for the Dagster instance (event log, run storage, schedule storage)
2. **Object storage** — for IO managers (Azure Blob, GCS, MinIO)
3. **Compute** — for the webserver/daemon (always-on) and run workers (can scale)
4. **Secrets** — database credentials, storage keys, API tokens

## Terraform Module: Dagster on Azure

```hcl
# modules/dagster-infra/main.tf

resource "azurerm_postgresql_flexible_server" "dagster" {
  name                          = "${local.name_prefix}-pg-dagster"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = "16"
  administrator_login           = "dagsteradmin"
  administrator_password        = var.postgres_password
  storage_mb                    = 32768
  sku_name                      = var.postgres_sku
  zone                          = "1"
  tags                          = var.common_tags
}

resource "azurerm_postgresql_flexible_server_database" "dagster" {
  name      = "dagster"
  server_id = azurerm_postgresql_flexible_server.dagster.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

resource "azurerm_storage_container" "dagster_io" {
  name                  = "dagster-io"
  storage_account_id    = var.storage_account_id
  container_access_type = "private"
}
```

## Terraform Module: Dagster on K3s (On-Premises)

For on-premises deployments (e.g., Project Hades pattern), provision via Helm on K3s:

```hcl
# modules/dagster-k3s/main.tf

resource "helm_release" "dagster" {
  name             = "dagster"
  repository       = "https://dagster-io.github.io/helm"
  chart            = "dagster"
  version          = var.dagster_chart_version
  namespace        = "orchestration"
  create_namespace = true

  set {
    name  = "dagster-webserver.replicaCount"
    value = "1"
  }

  set {
    name  = "dagster-daemon.replicaCount"
    value = "1"
  }

  set_sensitive {
    name  = "postgresql.postgresqlPassword"
    value = var.postgres_password
  }

  values = [file("${path.module}/values/${var.environment}.yaml")]
}
```

## Dagster + dbt Integration

When using Dagster to orchestrate dbt:

```hcl
# The dbt project is typically a git submodule or separate repo.
# Dagster discovers dbt models via dagster-dbt and represents them as assets.
# Terraform's role: provision the infrastructure Dagster runs on,
# not the Dagster code/definitions themselves.

# Ensure the dbt target warehouse/catalog is provisioned:
resource "databricks_schema" "gold" {
  catalog_name = var.catalog_name
  name         = "gold"
  comment      = "Business-ready dimensional models managed by dbt via Dagster"
}
```

## Environment Separation

Each environment gets its own Dagster instance with its own PostgreSQL database.
Never share a Dagster instance across environments — run isolation matters for
idempotency and auditability.

```hcl
# environments/dev/main.tf
module "dagster" {
  source            = "../../modules/dagster-infra"
  environment       = "dev"
  postgres_sku      = "B_Standard_B1ms"    # Small for dev
  postgres_password = data.azurerm_key_vault_secret.dagster_pg_pw.value
  # ...
}

# environments/prod/main.tf
module "dagster" {
  source            = "../../modules/dagster-infra"
  environment       = "prod"
  postgres_sku      = "GP_Standard_D2s_v3" # Production-grade
  postgres_password = data.azurerm_key_vault_secret.dagster_pg_pw.value
  # ...
}
```
