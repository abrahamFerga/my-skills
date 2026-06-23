# Aspire — Azure resources in the app model

Scope: declaring Azure resources in the AppHost with `Aspire.Hosting.Azure.*`, the
provision-vs-connect-vs-emulate choice, Bicep generation, and how it feeds `azd`
and the deployment flow. For non-Azure backing resources see
[integrations.md](integrations.md); for the deploy mechanics see
[deployment.md](deployment.md).

## The core idea

An Azure hosting integration models a real Azure service in the same app model as
your containers and projects. The same `Add…` call behaves differently per mode:

- **Run mode** (`aspire run`) — runs a **local emulator or container** so you never
  touch Azure during inner-loop dev.
- **Publish/deploy mode** (`aspire publish` / `aspire deploy`) — emits **Bicep** and
  **provisions** the real resource (or connects to an existing one).

You opt into the local behavior explicitly with `RunAsEmulator()` /
`RunAsContainer()`, and into connecting (vs creating) with `AsExisting(...)`.

## Packages

| Resource | Hosting package | AppHost call |
|----------|-----------------|--------------|
| Service Bus | `Aspire.Hosting.Azure.ServiceBus` | `AddAzureServiceBus("sb")` |
| Storage (blob/queue/table) | `Aspire.Hosting.Azure.Storage` | `AddAzureStorage("st")` |
| Key Vault | `Aspire.Hosting.Azure.KeyVault` | `AddAzureKeyVault("kv")` |
| Cosmos DB | `Aspire.Hosting.Azure.CosmosDB` | `AddAzureCosmosDB("cosmos")` |
| Azure SQL | `Aspire.Hosting.Azure.Sql` | `AddAzureSqlServer("sql")` |
| Postgres Flexible Server | `Aspire.Hosting.Azure.PostgreSQL` | `AddAzurePostgresFlexibleServer("pg")` |
| Azure Cache for Redis | `Aspire.Hosting.Azure.Redis` | `AddAzureRedis("cache")` |
| App Configuration | `Aspire.Hosting.Azure.AppConfiguration` | `AddAzureAppConfiguration("cfg")` |
| OpenAI / Foundry | `Aspire.Hosting.Azure.CognitiveServices` | `AddAzureOpenAI("openai")` |
| Application Insights | `Aspire.Hosting.Azure.ApplicationInsights` | `AddAzureApplicationInsights("ai")` |

Add them from the AppHost directory with `aspire add azure-service-bus` (etc.) or
`dotnet add package`. All ship in lockstep on the 13.4.x line.

## Provision vs connect vs emulate

```csharp
// 1) Provision a NEW resource (created on `aspire deploy`):
var sb = builder.AddAzureServiceBus("messaging");
var orders = sb.AddServiceBusQueue("orders");

// 2) Run an EMULATOR locally, provision the real thing on deploy:
var sbLocal = builder.AddAzureServiceBus("messaging").RunAsEmulator();

// 3) CONNECT to an EXISTING resource instead of creating one:
var existingName = builder.AddParameter("sb-name");
var rg = builder.AddParameter("sb-resource-group");
var sbExisting = builder.AddAzureServiceBus("messaging")
    .AsExisting(existingName, rg);

// 4) Azure-flavored databases can also run as a plain container locally:
var sql = builder.AddAzureSqlServer("sql").RunAsContainer();        // local SQL container
var pg = builder.AddAzurePostgresFlexibleServer("pg").RunAsContainer();
```

Emulator support exists for Storage (Azurite), Cosmos, Service Bus, Event Hubs,
and SQL/Postgres (as containers). Resources without an emulator must be
provisioned to develop against them — scope a cheap dev resource group for that.

## Storage sub-resources

```csharp
var storage = builder.AddAzureStorage("storage").RunAsEmulator();   // Azurite
var blobs = storage.AddBlobs("blobs");
var queues = storage.AddQueues("queues");
var tables = storage.AddTables("tables");

builder.AddProject<Projects.Api>("api")
    .WithReference(blobs).WaitFor(blobs);
```

Client side (in the service): `Aspire.Azure.Storage.Blobs` →
`builder.AddAzureBlobClient("blobs")`. See [integrations.md](integrations.md).

## Identity, not connection strings

Aspire's Azure integrations default to **token credential / Managed Identity**, not
account keys. Locally they use your `DefaultAzureCredential` (so `az login` first);
in Azure the deployed app uses its managed identity with role assignments that
Aspire generates into the Bicep. Prefer this over `PublishAsConnectionString()`,
which falls back to a secret and should be reserved for services that can't use
Entra auth.

```csharp
// Force a key-based connection string only when the consumer can't use Entra:
var sbKeyed = builder.AddAzureServiceBus("legacy").PublishAsConnectionString();
```

## Provisioning during `aspire run` (optional)

You can let Aspire provision real Azure resources even in run mode by supplying
provisioning config (subscription, location, resource-group) via user-secrets:

```jsonc
// dotnet user-secrets (AppHost project)
{
  "Azure": {
    "SubscriptionId": "<sub-guid>",
    "Location": "westeurope",
    "ResourceGroup": "rg-myapp-dev"
  }
}
```

Add `builder.AddAzureProvisioning()` (pulled in transitively by the Azure hosting
packages) and Aspire provisions on first run and reuses the resources afterward.

## Bicep and azd

`aspire publish` serializes every Azure resource into **Bicep modules**, and the
deploy path integrates with **Azure Developer CLI (`azd`)**:

```bash
azd init          # one-time: detect the AppHost, create azure.yaml
azd provision     # create the Azure resources from generated Bicep
azd deploy        # build + push images and deploy the services
azd up            # provision + deploy in one step
azd down          # tear everything down
```

You can also drop in your own `*.bicep` and reference it with
`builder.AddBicepTemplate("name", "infra/my.bicep")` when an integration doesn't
cover a service you need.

## When the target is Azure App Service

The sibling [dotnet-architecture](..//architecture:dotnet-architecture) skill defaults
to **Azure App Service** with **Terraform** for the surrounding infrastructure. Two
clean ways to combine them:

- **Aspire-owned infra:** `builder.AddAzureAppServiceEnvironment("appsvc")` +
  `aspire deploy` — Aspire generates and provisions everything (good for
  Aspire-first teams).
- **Terraform-owned infra (recommended when you already standardize on Terraform):**
  provision App Service, Azure SQL, Key Vault, App Insights, and the managed
  identity with the Terraform assets in the architecture skill, and use Aspire only
  for local orchestration + connection-string/service-discovery wiring. The app
  reads its Azure connection info from App Service app settings / Key Vault
  references rather than from Aspire-generated Bicep.

Pick one owner for production infra; don't let both Terraform and `azd` race to
manage the same resources.
