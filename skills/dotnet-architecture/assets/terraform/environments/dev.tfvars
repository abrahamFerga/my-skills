###############################################################################
# environments/dev.tfvars
#
# Apply with:
#   terraform init -backend-config="key=dev.tfstate"
#   terraform plan  -var-file="environments/dev.tfvars"
#   terraform apply -var-file="environments/dev.tfvars"
#
# No secrets here. Replace the <PLACEHOLDER> values.
###############################################################################

environment = "dev"
location    = "westeurope"
app_name    = "contoso-shop" # <-- your app slug (lowercase, hyphenated)

# Cheapest viable plan for dev. (Note: Always On is unavailable on B1.)
service_plan_sku = "B1"
zone_redundant   = false

# PostgreSQL Flexible Server -- cheap burstable SKU for dev.
postgres_sku_name   = "B_Standard_B1ms"
postgres_storage_mb = 32768
postgres_version    = "16"

enable_postgres    = true
log_retention_days = 30

# Entra ID principal that administers PostgreSQL (a group is recommended).
postgres_admin_login     = "<POSTGRES_ADMIN_GROUP_DISPLAY_NAME>"
postgres_admin_object_id = "<POSTGRES_ADMIN_GROUP_OBJECT_ID>"

tags = {
  cost-center = "engineering"
  owner       = "platform-team"
}
