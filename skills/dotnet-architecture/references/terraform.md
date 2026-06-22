# Terraform Scaffold

Explains [../assets/terraform/](../assets/terraform/): what each file does, the
state/auth model, naming/tagging, and the Managed Identity + Key Vault + OIDC
wiring. Provider is **hashicorp/azurerm `~> 4.0`** (the current major).

## File map

| File | Purpose |
|------|---------|
| [`providers.tf`](../assets/terraform/providers.tf) | Pins Terraform + `azurerm ~> 4.0` (and `azuread ~> 3.0`); the required `provider "azurerm" { features {} }` block; `use_oidc = true` so CI reuses the federated login. |
| [`backend.tf`](../assets/terraform/backend.tf) | `azurerm` remote state in an Azure Storage container. Per-env `key` is passed at `init` time. Uses `use_azuread_auth` + `use_oidc` (no storage keys). |
| [`variables.tf`](../assets/terraform/variables.tf) | Every env-specific input, with validation. No secrets. |
| [`main.tf`](../assets/terraform/main.tf) | All resources: RG, UAMI, Log Analytics + App Insights, Key Vault (+ role assignments), PostgreSQL Flexible Server (Entra-only), App Service Plan + Linux Web App. |
| [`outputs.tf`](../assets/terraform/outputs.tf) | Values the pipeline/operators need (`web_app_name`, identity ids, KV uri, `postgres_fqdn`); App Insights connection string marked `sensitive`. |
| [`environments/dev.tfvars`](../assets/terraform/environments/dev.tfvars) / [`prod.tfvars`](../assets/terraform/environments/prod.tfvars) | Per-env values (SKUs, retention, region, Postgres admin). Replace the `<PLACEHOLDER>`s. |

## Layout model: single root, per-env state + tfvars

This scaffold uses **one root configuration** with **per-environment state files
and `.tfvars`** — the simplest layout that still isolates environments:

```
infra/                      (this is assets/terraform/, copied into your repo)
├─ providers.tf  backend.tf  variables.tf  main.tf  outputs.tf
└─ environments/
   ├─ dev.tfvars            terraform … -var-file=environments/dev.tfvars  + key=dev.tfstate
   └─ prod.tfvars           terraform … -var-file=environments/prod.tfvars + key=prod.tfstate
```

Each environment gets its own state blob via `-backend-config="key=<env>.tfstate"`,
so a `dev` apply can never touch `prod` state. When the estate grows, refactor the
resource groupings in `main.tf` into reusable **modules** (e.g. `modules/web-app`,
`modules/data`) and have thin per-env roots call them — but don't start there.

## Remote state (bootstrap once, by hand)

Terraform can't create the storage that holds its own state, so the state
**resource group + storage account + container** must exist before the first
`init`. Create them once (CLI or a tiny separate root), then grant the CI identity
**Storage Blob Data Contributor** on the container. The backend authenticates with
Entra ID (`use_azuread_auth = true`) and OIDC in CI — no account keys.

```bash
terraform init -backend-config="key=dev.tfstate"
terraform plan  -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

## Naming & tagging

- Names follow `<type>-<app>-<env>` (e.g. `rg-contoso-shop-dev`,
  `plan-contoso-shop-dev`). Globally-unique resources (Key Vault, the PostgreSQL
  Flexible Server, the web app) append a deterministic 6-char suffix derived from
  `sha1(app + env + subscription)` so re-applies are stable and names don't clash.
- **Every resource is tagged** from a single `local.tags` map:
  `environment`, `app`, `managed-by = "terraform"`, merged with any caller `tags`.
  Centralizing tags means one edit re-tags the estate.

## Managed Identity + Key Vault wiring (the security spine)

```
azurerm_user_assigned_identity.app
        │  principal_id
        ▼
azurerm_role_assignment.app_kv_secrets_user   → role "Key Vault Secrets User"
        │                                         scope = the Key Vault
        ▼
azurerm_linux_web_app.main
   identity { type = "UserAssigned", identity_ids = [uami.id] }
   key_vault_reference_identity_id = uami.id      ← resolves @Microsoft.KeyVault refs
   app_settings = {
     AZURE_CLIENT_ID = uami.client_id             ← DefaultAzureCredential picks this UAMI
     APPLICATIONINSIGHTS_CONNECTION_STRING = appi.connection_string
     KeyVault__Uri = kv.vault_uri
     ConnectionStrings__Default = "Host=<server fqdn>;Database=appdb;Username=<uami client id>;SSL Mode=Require;..."
   }
```

Key points verified against the azurerm v4 docs:

- Key Vault uses **`rbac_authorization_enabled = true`** (the correct argument name;
  *not* `enable_rbac_authorization`). Data-plane access is granted with
  `azurerm_role_assignment`, not legacy `access_policy` blocks.
- The web app's `identity` block is `type = "UserAssigned"` with `identity_ids`.
- `key_vault_reference_identity_id` tells App Service which identity resolves Key
  Vault references — **required** when using a *user-assigned* identity (the
  default is the system-assigned one).
- The deployer principal (the CI identity / `data.azurerm_client_config.current`)
  is granted **Key Vault Secrets Officer** so `apply` can write secrets.
- PostgreSQL Flexible Server uses `authentication { active_directory_auth_enabled =
  true, password_auth_enabled = false }` plus an
  `azurerm_postgresql_flexible_server_active_directory_administrator` (the Entra
  admin group) — no password is ever created. The app connects with its Managed
  Identity: Npgsql obtains an Entra access token via the UAMI and uses it as the
  password. Post-provision, grant the UAMI a Postgres role mapped to its Entra
  identity. (Swap in `azurerm_mssql_server` with `azuread_authentication_only =
  true` if you choose Azure SQL instead.)

## Adding a secret to Key Vault

```hcl
resource "azurerm_key_vault_secret" "example" {
  name         = "ExternalApiKey"
  value        = var.external_api_key # pass via TF_VAR_, never commit it
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv_secrets_officer]
}
```

Then reference it from `app_settings`:

```hcl
"ExternalApi__Key" = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.example.id})"
```

App Service resolves the reference at runtime using the UAMI — the app reads
`ExternalApi:Key` as a normal config value with no code changes.

## GitHub OIDC for Terraform

The pipeline exports `ARM_CLIENT_ID` / `ARM_TENANT_ID` / `ARM_SUBSCRIPTION_ID` /
`ARM_USE_OIDC=true` and runs `azure/login@v2` first; the azurerm provider
(`use_oidc = true`) then reuses that federated token. There is **no
`ARM_CLIENT_SECRET`**. The federated credential on the Entra app (or UAMI) must
trust your repo's `subject` (e.g. `repo:org/repo:ref:refs/heads/main` and the
`environment:prod` subject for the gated apply job). See
[github-actions.md](github-actions.md).

## Validate locally

```bash
terraform fmt -check -recursive
terraform validate
terraform plan -var-file="environments/dev.tfvars"
```

`fmt` and `validate` also run in
[../assets/github-workflows/cd-infra.yml](../assets/github-workflows/cd-infra.yml)
before any plan.
