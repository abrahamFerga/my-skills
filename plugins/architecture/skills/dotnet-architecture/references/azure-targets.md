# Azure Service Selection

Pick the smallest set of managed services that meets the requirements. The
scaffold defaults to **App Service + PostgreSQL Flexible Server + Key Vault + App
Insights/Log Analytics + User-Assigned Managed Identity**. Swap individual pieces
using the matrices below; the Terraform in [../assets/terraform/](../assets/terraform/)
is structured so you can toggle/replace resources.

## Compute

| Target | Pick when | Avoid when |
|--------|-----------|-----------|
| **App Service (Linux)** ← default | Modular monolith or a few web apps/APIs; you want PaaS simplicity, slots, easy custom domains/TLS, autoscale. | You need scale-to-zero, fine-grained per-service scaling, or a service mesh. |
| **Azure Container Apps (ACA)** | Several containerized services; want scale-to-zero, revisions, KEDA event scaling, optional Dapr — without running Kubernetes. | A single monolith (App Service is simpler) or you need full K8s control. |
| **AKS** | Many services, custom networking/operators, a platform team that can run Kubernetes. | Small team / few services — operational cost dwarfs the benefit. |
| **Azure Functions** | Event-driven, scheduled, or bursty HTTP glue; consumption billing. | Long-lived stateful web apps or steady high throughput (plan costs add up). |

Decision rule: **monolith → App Service. Handful of services → ACA. Fleet +
platform team → AKS. Triggers/jobs → Functions.** You can mix: monolith on App
Service with a couple of Functions for scheduled work is a common, healthy shape.

App Service plan sizing: `B1` for dev (note: **no Always On** on Basic). For prod,
`P0v3`/`P1v3` (Premium v3) unlock Always On, autoscale, and zone redundancy. The
SKU is the `service_plan_sku` variable in
[../assets/terraform/variables.tf](../assets/terraform/variables.tf).

## Data

| Option | Pick when | Notes |
|--------|-----------|-------|
| **Azure Database for PostgreSQL Flexible Server** ← default | Relational store; you want a single dialect from local to prod (matches Aspire `AddPostgres` and the [`design-architecture`](../../design-architecture/SKILL.md) Postgres guardrail), Postgres extensions, strong EF Core support via `Npgsql`. | Use **Entra-only auth** (`password_auth_enabled = false`) + Managed Identity (no password). Resources: `azurerm_postgresql_flexible_server` + `..._active_directory_administrator` + `..._database`. |
| **Azure SQL Database** (alternative) | You specifically need T-SQL / SQL Server features or tooling, or are migrating an existing SQL Server estate. | Use **Entra-only auth** (`azuread_authentication_only = true`) + Managed Identity (no SQL password). Serverless `GP_S_*` SKUs auto-pause to save cost. Resources: `azurerm_mssql_server` + `..._database`. |
| Cosmos DB | Global distribution, schema-flexible, single-digit-ms at scale, document/graph workloads. | Different consistency/cost model; not a drop-in for relational. |

The scaffold provisions PostgreSQL Flexible Server with
**`password_auth_enabled = false`** (and `active_directory_auth_enabled = true`)
so no password exists. The app's connection string uses the UAMI client id as the
username; Npgsql obtains an Entra access token via the UAMI (`Azure.Identity`) — see
the `app_settings` in [../assets/terraform/main.tf](../assets/terraform/main.tf).
Note the post-provision step: the UAMI must be granted a PostgreSQL role mapped to
its Entra identity. To switch to Azure SQL instead, replace the
`azurerm_postgresql_flexible_server*` resources with `azurerm_mssql_server` +
`..._database` (Entra-only) and update the connection string accordingly. Data
modeling lives in the [`entity-framework-core`](..//development:entity-framework-core)
skill (Npgsql provider).

## Supporting services

| Need | Service | azurerm resource | Auth |
|------|---------|------------------|------|
| Async messaging / pub-sub | **Azure Service Bus** | `azurerm_servicebus_namespace`, `..._queue`, `..._topic` | Managed Identity + RBAC (`Azure Service Bus Data Sender/Receiver`) |
| Cache / distributed lock / output cache | **Azure Cache for Redis** | `azurerm_redis_cache` | Entra auth (Microsoft Entra) where supported, else access key in Key Vault |
| Blobs / queues / files | **Azure Storage** | `azurerm_storage_account`, `..._container` | Managed Identity + `Storage Blob Data Contributor` |
| Secrets store | **Azure Key Vault** | `azurerm_key_vault` (+ `azurerm_key_vault_secret`) | **RBAC** (`rbac_authorization_enabled = true`); grant `Key Vault Secrets User` |
| Logs + metrics backing store | **Log Analytics Workspace** | `azurerm_log_analytics_workspace` | — |
| APM / traces | **Application Insights** (workspace-based) | `azurerm_application_insights` with `workspace_id` | connection string surfaced as app setting |
| Identity / workload identity | **Entra ID + Managed Identity** | `azurerm_user_assigned_identity`, `azurerm_role_assignment` | the whole point — no secrets |
| Container images (if ACA/AKS later) | **Azure Container Registry** | `azurerm_container_registry` | `AcrPull` role to the workload identity |

## Security & identity baseline (non-negotiable)

1. **User-Assigned Managed Identity** is the app's workload identity. It is wired
   into the web app's `identity` block and set as
   `key_vault_reference_identity_id` so Key Vault references resolve under it.
2. **No secrets in app settings or source.** Secrets live in Key Vault; the app
   reads them via the config provider (`AddAzureKeyVault` + `DefaultAzureCredential`)
   or via App Service Key Vault references
   (`@Microsoft.KeyVault(SecretUri=https://<vault>.vault.azure.net/secrets/<name>)`).
3. **RBAC over access policies** on Key Vault (`rbac_authorization_enabled = true`);
   grant the UAMI the **Key Vault Secrets User** role.
4. **Entra-only auth on data** where feasible (PostgreSQL Flexible Server
   `password_auth_enabled = false`; Azure SQL `azuread_authentication_only = true`).
   Tradeoff: every human/principal that connects must be an Entra principal — there
   is no password fallback, so make the DB admin an **Entra group** and add the
   app's UAMI as a DB role/user (a documented post-provision step for Postgres).
5. **HTTPS only + TLS 1.2 minimum** on the web app (`https_only`,
   `minimum_tls_version`).
6. **CI/CD authenticates via OIDC**, never a stored secret — see
   [github-actions.md](github-actions.md).

## Observability baseline

- **Workspace-based App Insights** (`workspace_id` set) so traces/logs/metrics
  land in one Log Analytics workspace you can query with KQL.
- The connection string is surfaced to the app as
  `APPLICATIONINSIGHTS_CONNECTION_STRING`; the app enables it via
  `Azure.Monitor.OpenTelemetry.AspNetCore` (`builder.Services.AddOpenTelemetry()...`
  or `AddServiceDefaults()` from the Aspire skill, which already wires OTel).
- Set Log Analytics `retention_in_days` per environment (`log_retention_days`
  variable) — shorter in dev, longer in prod.

For how these resources are declared and parameterized, see
[terraform.md](terraform.md).
