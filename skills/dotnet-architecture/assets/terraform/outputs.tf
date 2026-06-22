###############################################################################
# outputs.tf
#
# Surfaced for the CD pipeline (the app deploy job reads web_app_name) and for
# operators. No secret values are output.
###############################################################################

output "resource_group_name" {
  description = "Resource group containing all environment resources."
  value       = azurerm_resource_group.main.name
}

output "web_app_name" {
  description = "App Service name -- consumed by cd-app.yml for the deploy step."
  value       = azurerm_linux_web_app.main.name
}

output "web_app_default_hostname" {
  description = "Default public hostname of the web app."
  value       = azurerm_linux_web_app.main.default_hostname
}

output "app_identity_client_id" {
  description = "Client ID of the app's User-Assigned Managed Identity."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "app_identity_principal_id" {
  description = "Principal (object) ID of the app's User-Assigned Managed Identity."
  value       = azurerm_user_assigned_identity.app.principal_id
}

output "key_vault_uri" {
  description = "Key Vault data-plane URI."
  value       = azurerm_key_vault.main.vault_uri
}

output "application_insights_connection_string" {
  description = "App Insights connection string (treat as sensitive)."
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "postgres_fqdn" {
  description = "PostgreSQL Flexible Server FQDN (null when Postgres is disabled)."
  value       = var.enable_postgres ? azurerm_postgresql_flexible_server.main[0].fqdn : null
}
