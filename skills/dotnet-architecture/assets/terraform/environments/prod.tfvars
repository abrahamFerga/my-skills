###############################################################################
# environments/prod.tfvars
#
# Apply with:
#   terraform init -backend-config="key=prod.tfstate"
#   terraform plan  -var-file="environments/prod.tfvars"
#   terraform apply -var-file="environments/prod.tfvars"
#
# No secrets here. Replace the <PLACEHOLDER> values.
###############################################################################

environment = "prod"
location    = "westeurope"
app_name    = "contoso-shop"

# Premium v3 supports Always On, autoscale, and zone redundancy.
service_plan_sku = "P1v3"
zone_redundant   = true # places the Flexible Server in zone "1"

# PostgreSQL Flexible Server -- General Purpose SKU; size to your load.
postgres_sku_name   = "GP_Standard_D2s_v3"
postgres_storage_mb = 131072
postgres_version    = "16"

enable_postgres    = true
log_retention_days = 90

postgres_admin_login     = "<POSTGRES_ADMIN_GROUP_DISPLAY_NAME>"
postgres_admin_object_id = "<POSTGRES_ADMIN_GROUP_OBJECT_ID>"

tags = {
  cost-center = "engineering"
  owner       = "platform-team"
  criticality = "tier-1"
}
