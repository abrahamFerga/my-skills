###############################################################################
# main.tf
#
# Modular-monolith baseline on Azure App Service (Linux):
#
#   Resource Group
#     ├─ User-Assigned Managed Identity  (the app's workload identity)
#     ├─ Log Analytics Workspace + Application Insights (workspace-based)
#     ├─ Key Vault (RBAC-authorized)  ──grant──▶  UAMI: "Key Vault Secrets User"
#     │     └─ secret: db connection string (when Entra-only auth is NOT used)
#     ├─ App Service Plan (Linux)
#     └─ Linux Web App (.NET 10)  ── identity ▶ UAMI
#           app_settings reference Key Vault + App Insights
#     └─ (optional) PostgreSQL Flexible Server + Database with Entra-only admin
#
# Secrets are NEVER written to app_settings in plaintext. Connection info that
# must be a secret is stored in Key Vault and surfaced via a Key Vault
# reference resolved by the app's User-Assigned Managed Identity.
###############################################################################

data "azurerm_client_config" "current" {}

locals {
  # Deterministic, collision-resistant suffix so globally-unique names hold.
  name_suffix = substr(sha1("${var.app_name}-${var.environment}-${data.azurerm_client_config.current.subscription_id}"), 0, 6)
  base        = "${var.app_name}-${var.environment}"

  tags = merge(
    {
      environment = var.environment
      app         = var.app_name
      managed-by  = "terraform"
    },
    var.tags
  )
}

# --- Resource group --------------------------------------------------------- #
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.base}"
  location = var.location
  tags     = local.tags
}

# --- Workload identity (User-Assigned Managed Identity) --------------------- #
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${local.base}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

# --- Observability ---------------------------------------------------------- #
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.base}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_application_insights" "main" {
  name                = "appi-${local.base}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = local.tags
}

# --- Key Vault (RBAC-authorized) -------------------------------------------- #
resource "azurerm_key_vault" "main" {
  name                = "kv-${var.app_name}-${var.environment}-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Use Azure RBAC for data-plane authorization instead of legacy access
  # policies. Grants are expressed as azurerm_role_assignment below.
  rbac_authorization_enabled = true

  purge_protection_enabled = var.environment == "prod"
  tags                     = local.tags
}

# The web app's identity may READ secrets from the vault.
resource "azurerm_role_assignment" "app_kv_secrets_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# The principal running Terraform must be able to WRITE secrets during apply.
resource "azurerm_role_assignment" "deployer_kv_secrets_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# --- Data tier: PostgreSQL Flexible Server with Entra-only authentication --- #
# Default relational store -- matches local Aspire Postgres (AddPostgres) and the
# design-architecture Postgres guardrail. Azure SQL remains a documented
# alternative (see references/azure-targets.md).
resource "azurerm_postgresql_flexible_server" "main" {
  count                         = var.enable_postgres ? 1 : 0
  name                          = "psql-${var.app_name}-${var.environment}-${local.name_suffix}"
  resource_group_name           = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  version                       = var.postgres_version
  sku_name                      = var.postgres_sku_name
  storage_mb                    = var.postgres_storage_mb
  zone                          = var.zone_redundant ? "1" : null
  public_network_access_enabled = true # tighten to Private Endpoint for prod

  # Entra-only auth: password authentication is disabled, so no admin password
  # exists. The app authenticates with its Managed Identity (Npgsql obtains an
  # Entra access token via the UAMI -- see app_settings below).
  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  tags = local.tags
}

# Entra administrator for the server -- the same admin group used elsewhere.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "main" {
  count               = var.enable_postgres ? 1 : 0
  server_name         = azurerm_postgresql_flexible_server.main[0].name
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = var.postgres_admin_object_id
  principal_name      = var.postgres_admin_login
  principal_type      = "Group" # an Entra group is recommended for the admin
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  count     = var.enable_postgres ? 1 : 0
  name      = "appdb"
  server_id = azurerm_postgresql_flexible_server.main[0].id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# --- Compute: App Service Plan + Linux Web App ------------------------------ #
resource "azurerm_service_plan" "main" {
  name                = "plan-${local.base}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku
  tags                = local.tags
}

resource "azurerm_linux_web_app" "main" {
  name                = "app-${var.app_name}-${var.environment}-${local.name_suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_service_plan.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  # Tell App Service which identity resolves Key Vault references.
  key_vault_reference_identity_id = azurerm_user_assigned_identity.app.id

  site_config {
    always_on              = var.service_plan_sku != "B1" # Always On is unavailable on Basic
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    http2_enabled          = true
    vnet_route_all_enabled = false
    application_stack {
      dotnet_version = "10.0"
    }
  }

  app_settings = merge(
    {
      ASPNETCORE_ENVIRONMENT                = var.environment == "prod" ? "Production" : "Development"
      APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
      # Client id the app uses to pick the right identity at runtime
      # (DefaultAzureCredential / ManagedIdentityCredential).
      AZURE_CLIENT_ID = azurerm_user_assigned_identity.app.client_id
      # Make the UAMI client id available to the Key Vault provider too.
      KeyVault__Uri = azurerm_key_vault.main.vault_uri
    },
    var.enable_postgres ? {
      # Entra-only auth -> no secret in the connection string. Npgsql obtains an
      # Entra access token via the UAMI (Azure.Identity) using AZURE_CLIENT_ID
      # above and supplies it as the password. The UAMI must first be granted a
      # PostgreSQL role mapped to its Entra identity -- a documented
      # post-provision step (CREATE ROLE "<uami-name>" WITH LOGIN IN ROLE
      # azure_ad_user; GRANT on the database).
      ConnectionStrings__Default = "Host=${azurerm_postgresql_flexible_server.main[0].fqdn};Database=${azurerm_postgresql_flexible_server_database.main[0].name};Username=${azurerm_user_assigned_identity.app.client_id};SSL Mode=Require;Trust Server Certificate=true"
    } : {}
  )

  tags = local.tags

  # The plaintext connection string for a password path is intentionally NOT
  # modeled. If you must use password auth, write the password to Key Vault and
  # reference it here as: "@Microsoft.KeyVault(SecretUri=${secret_uri})".
}
