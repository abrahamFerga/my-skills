---
name: aspire
description: >
  Aspire (formerly ".NET Aspire") is the code-first orchestrator for
  cloud-native distributed apps: a C# AppHost declares resources (databases,
  caches, queues, projects, containers) and the `aspire` CLI runs them locally
  with a telemetry dashboard and deploys to Docker Compose, Kubernetes, or
  Azure. Use for multi-service apps (api + db + cache + worker), adding a
  Postgres/Redis/RabbitMQ/Azure resource, ServiceDefaults, `aspire run`/`deploy`,
  and `DistributedApplicationTestingBuilder` tests. DO NOT USE FOR EF Core
  entity/migration/query modeling (use ../entity-framework-core/SKILL.md — Aspire
  only wires the connection) or solution layering/architecture (use
  ../dotnet-architecture/SKILL.md).
license: MIT
---

# Aspire (cloud-native dev/deploy orchestrator)

Aspire is the tool for **code-first, observable dev and deploy** of distributed apps. You describe your whole system — APIs, databases, caches, message brokers, frontends, containers, even Python/JS apps — in one **AppHost** program. `aspire run` launches everything locally (containers + projects), injects connection strings and service-discovery endpoints, and opens a **dashboard** showing live logs, traces, metrics, and resource state. The same app model then drives `aspire publish`/`aspire deploy` to Docker Compose, Kubernetes, or Azure.

As of **Aspire 13** the product dropped the ".NET" prefix and became a **multi-language platform** (first-class Python and JavaScript), but the AppHost and richest integration set are still C#/.NET 10. Two halves matter: **hosting integrations** (`Aspire.Hosting.*`, used in the AppHost to declare resources) and **client integrations** (`Aspire.*`, used inside each service to consume them). Don't confuse them — see [references/integrations.md](references/integrations.md).

## Scope

This skill covers the CLI, the C# app model, hosting-vs-client integrations, Azure provisioning, deployment, and integration testing for Aspire 13.x on .NET 10.

USE FOR: scaffolding or orchestrating a multi-service app (api + db + cache + worker); adding a Postgres/Redis/SQL Server/RabbitMQ/Azure resource to an AppHost; wiring service discovery, OpenTelemetry, health checks, and resilience via ServiceDefaults; passing connection strings/secrets between services; running `aspire run`/`aspire deploy`; provisioning Azure resources with Bicep/azd; writing `DistributedApplicationTestingBuilder` integration tests.

DO NOT USE FOR: a single standalone web API with no other services (just use ASP.NET Core); EF Core entity/migration/query modeling (use [../entity-framework-core/SKILL.md](../entity-framework-core/SKILL.md) — Aspire only wires the connection); broad solution/layering/architecture decisions (use [../dotnet-architecture/SKILL.md](../dotnet-architecture/SKILL.md)); building AI agents (use [../agent-framework-csharp/SKILL.md](../agent-framework-csharp/SKILL.md)); non-.NET-host orchestration tools like raw Docker Compose or Helm authored by hand.

## When to Use

- Orchestrating 2+ services locally (e.g. web API + Postgres + Redis + a worker) without hand-writing Docker Compose
- Adding a backing resource (Postgres, Redis, SQL Server, RabbitMQ, Azure Service Bus/Storage/Key Vault/Cosmos) to an existing app
- Getting OpenTelemetry, health checks, service discovery, and HTTP resilience "for free" via ServiceDefaults
- Passing connection strings and secrets between services without hardcoding URLs or credentials
- Standing up the telemetry dashboard for local debugging of distributed traces
- Publishing/deploying the same model to Docker Compose, Kubernetes, Azure Container Apps, or Azure App Service
- Writing integration tests that spin up the real resource graph (`DistributedApplicationTestingBuilder`)

## Stop Signals

- **One self-contained web API, no other services** → Just use ASP.NET Core. Aspire adds orchestration overhead with nothing to orchestrate.
- **Modeling entities, relationships, migrations, or LINQ queries** → Use [../entity-framework-core/SKILL.md](../entity-framework-core/SKILL.md). Aspire only registers the `DbContext` and supplies its connection string.
- **Solution layout, layering, DDD, project boundaries** → Use [../dotnet-architecture/SKILL.md](../dotnet-architecture/SKILL.md).
- **Building an LLM agent / tool-calling workflow** → Use [../agent-framework-csharp/SKILL.md](../agent-framework-csharp/SKILL.md).
- **You already deploy with hand-authored Helm/Compose and don't want a .NET-driven model** → Aspire generates these; if you must hand-tune everything, stay with your existing pipeline.
- **Production secret store is the question, not orchestration** → Use Azure Key Vault / user-secrets directly; Aspire `AddParameter` references them, it isn't a vault.

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| Services to orchestrate | Yes | The set of projects + backing resources (db/cache/queue/etc.) to model in the AppHost. |
| Backing resource types | Yes | Postgres, Redis, SQL Server, RabbitMQ, Azure Service Bus/Storage/Key Vault/Cosmos, raw containers, Python/JS apps. Drives which `Aspire.Hosting.*` packages to add. |
| Deployment target | For deploy | Docker Compose, Kubernetes/AKS, Azure Container Apps, or Azure App Service. Picks the compute-environment API and publisher. |
| Secrets/parameters | If any | External values (passwords, API keys, existing connection strings). Supplied via `AddParameter` + user-secrets/env, never hardcoded. |
| Test scope | If testing | Which resources a `DistributedApplicationTestingBuilder` test must start and wait for. |

## Version / package status (as of Aspire 13.x)

| Piece | Version / package | Status |
|-------|-------------------|--------|
| Aspire CLI | `Aspire.Cli` 13.4.x (NuGet `Aspire.Cli`) | Stable. Requires **.NET SDK 10.0.100+**. |
| AppHost SDK | `Aspire.AppHost.Sdk` 13.x (MSBuild SDK) | Stable. `Aspire.Hosting.AppHost` is implicitly referenced. |
| Hosting integrations | `Aspire.Hosting.PostgreSQL`/`.Redis`/`.SqlServer`/`.RabbitMQ`/`.Azure.*` 13.4.x | Stable. |
| Client integrations | `Aspire.Npgsql.EntityFrameworkCore.PostgreSQL`, `Aspire.StackExchange.Redis`, `Aspire.Microsoft.Data.SqlClient`, `Aspire.RabbitMQ.Client`, `Aspire.Azure.Messaging.ServiceBus`, … 13.4.x | Stable. |
| ServiceDefaults deps | `Microsoft.Extensions.Http.Resilience` 10.x, `Microsoft.Extensions.ServiceDiscovery` 10.x, `OpenTelemetry.*` 1.12.x | Stable. |
| Testing | `Aspire.Hosting.Testing` 13.4.x | Stable. |
| Compute environments | `AddDockerComposeEnvironment`, `AddKubernetesEnvironment`, `AddAzureContainerAppEnvironment`, `AddAzureAppServiceEnvironment` | Generally available in 13.x (matured from 9.3 preview); Helm/AKS deploy hardened in 13.3. |
| **TypeScript AppHost** | define the app model in TS instead of C# | **Preview** (introduced 13.2) — flag it as preview; C# AppHost is the supported default. |
| EF Core migrations in AppHost | `Aspire.Hosting.EntityFrameworkCore` | Newer (13.3): adds Update/Add/Remove-Migration commands to dashboard + CLI. |
| Python / JavaScript hosting | `Aspire.Hosting.Python`, `Aspire.Hosting.JavaScript` | GA in 13.x (`AddPythonApp`/`AddUvicornApp`, `AddJavaScriptApp`). |

> Pin versions to the 13.4.x line and let `aspire add`/`aspire update` resolve exact patches. The whole family ships in lockstep, so keep all `Aspire.*` packages on the same minor.

## Core Mental Model

```
                    aspire CLI (new / run / add / publish / deploy)
                                  │
            ┌─────────────────────┴──────────────────────┐
            ▼                                             ▼
   ┌──────────────────┐                          ┌────────────────┐
   │     AppHost      │  DistributedApplication  │   Dashboard    │
   │  (single .cs /   │  .CreateBuilder(args)    │ logs · traces  │
   │   .csproj w/     │                          │ metrics · state│
   │ Aspire.AppHost.  │   builder.Add…()         └────────────────┘
   │      Sdk)        │   .WithReference(...)            ▲
   └──────────────────┘   .WaitFor(...)                  │ OTLP
            │              .Build().Run();               │
            ▼                                             │
   ┌─────────────────── app model (resources) ───────────┴───────┐
   │  AddPostgres  AddRedis  AddSqlServer  AddRabbitMQ            │
   │  AddProject<T>  AddContainer  AddPythonApp  AddJavaScriptApp │
   │  AddAzureServiceBus / Storage / KeyVault / CosmosDB         │
   └──────────────┬──────────────────────────┬──────────────────┘
                  │ injects conn strings      │ injects service-discovery URLs
                  ▼                            ▼
        ┌───────────────────┐       each Project calls (in Program.cs):
        │  service Program  │  ──►  builder.AddServiceDefaults();   // OTel+health+
        │  AddNpgsqlDbContext│       …AddRedisClient/AddNpgsql…      // discovery+resilience
        │  AddRedisClient    │  ──►  app.MapDefaultEndpoints();      // /health /alive
        └───────────────────┘
```

| Key type / API | Where | Role |
|----------------|-------|------|
| `DistributedApplication.CreateBuilder(args)` | AppHost | Entry point; returns `IDistributedApplicationBuilder`. |
| `builder.AddPostgres / AddRedis / AddSqlServer / AddRabbitMQ` | AppHost | Declare a backing resource (runs as a container locally). |
| `builder.AddProject<Projects.X>("name")` | AppHost | Add one of your .NET services to the model. |
| `.WithReference(dep).WaitFor(dep)` | AppHost | Inject the dependency's connection/URL and gate startup until it's healthy. |
| `builder.AddParameter("p", secret: true)` | AppHost | Externalize a value (password/key) to user-secrets/env. |
| `builder.AddServiceDefaults()` | each service | OpenTelemetry + health checks + service discovery + HTTP resilience. |
| `app.MapDefaultEndpoints()` | each service | Expose `/health` (ready) and `/alive` (live). |
| `builder.AddNpgsqlDbContext<T>("db")` / `AddRedisClient("cache")` | each service | Client integration that consumes a referenced resource by name. |
| `aspire run` / `aspire deploy` | CLI | Run locally with dashboard / push to a compute environment. |

## Workflow

### Step 1: Install the CLI and verify prerequisites

```bash
# Install (pick one). Script installer is the documented default:
curl -sSL https://aspire.dev/install.sh | bash        # macOS / Linux
# Windows PowerShell:
#   irm https://aspire.dev/install.ps1 | iex
# Or as a .NET global tool:
dotnet tool install -g Aspire.Cli

aspire --version          # expect 13.4.x
dotnet --version          # expect 10.0.100 or later
aspire doctor             # verify environment (SDK, container runtime, certs)
```

A container runtime (Docker Desktop or Podman) is required to run containerized resources locally.

### Step 2: Scaffold a new solution

```bash
aspire new                # interactive: pick a starter template
# Templates include an AppHost project, a ServiceDefaults project,
# and one or more sample services already wired together.
```

To add Aspire to an existing repo instead: `aspire init`.

### Step 3: Author the AppHost (single source of truth)

See the full sample in [assets/AppHost.cs](assets/AppHost.cs). The essentials:

```csharp
var builder = DistributedApplication.CreateBuilder(args);

// Externalized secret -> user-secrets / env, never hardcoded.
var dbPassword = builder.AddParameter("db-password", secret: true);

// Backing resources (run as containers locally).
var postgres = builder.AddPostgres("postgres", password: dbPassword)
    .WithLifetime(ContainerLifetime.Persistent);   // reuse container across runs
var appDb = postgres.AddDatabase("appdb");

var cache = builder.AddRedis("cache");

// Your services. WithReference injects conn strings/URLs; WaitFor gates startup.
var api = builder.AddProject<Projects.Api>("api")
    .WithReference(appDb).WaitFor(appDb)
    .WithReference(cache).WaitFor(cache);

builder.AddProject<Projects.Web>("web")
    .WithReference(api)            // service discovery: "https://api" resolves
    .WithExternalHttpEndpoints()
    .WithReplicas(2);

builder.Build().Run();
```

The AppHost `.csproj` uses `Sdk="Aspire.AppHost.Sdk/13.x"` and references each service project via `IsAspireProjectResource` so the strongly-typed `Projects.*` class generates. See [references/app-model.md](references/app-model.md).

### Step 4: Add an integration

```bash
# From the AppHost directory — adds the hosting package and registers it:
aspire add postgres        # or: aspire add redis / rabbitmq / azure-service-bus ...
```

Then add the matching **client** package to each consuming service and register it:

```csharp
// In the API's Program.cs — Aspire.Npgsql.EntityFrameworkCore.PostgreSQL
builder.AddServiceDefaults();
builder.AddNpgsqlDbContext<AppDbContext>("appdb");   // name matches AddDatabase("appdb")
// Aspire.StackExchange.Redis
builder.AddRedisClient("cache");                     // name matches AddRedis("cache")
```

Hosting-vs-client mapping for every common resource is in [references/integrations.md](references/integrations.md).

### Step 5: Wire ServiceDefaults in every service

Each service references the **ServiceDefaults** project and calls two methods. See [assets/ServiceDefaults.cs](assets/ServiceDefaults.cs).

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.AddServiceDefaults();      // OTel + health + service discovery + resilience
// ... register your services ...
var app = builder.Build();
app.MapDefaultEndpoints();          // /health and /alive
app.Run();
```

### Step 6: Run locally with the dashboard

```bash
aspire run            # builds AppHost + resources, starts everything, opens the dashboard
# Detached / scriptable variants:
aspire start          # run AppHost in the background
aspire ps             # list running AppHosts (supports --format json)
aspire logs           # stream logs
aspire stop           # terminate
```

The dashboard shows resource state, structured logs, distributed traces, and metrics (fed by OTLP from ServiceDefaults).

### Step 7: Publish / deploy

Declare a compute environment in the AppHost, then publish artifacts or deploy directly:

```csharp
// Docker Compose target:
builder.AddDockerComposeEnvironment("compose");
// or Azure Container Apps:        builder.AddAzureContainerAppEnvironment("aca");
// or Azure App Service:           builder.AddAzureAppServiceEnvironment("appsvc");
// or Kubernetes/AKS:              builder.AddKubernetesEnvironment("k8s");
```

```bash
aspire publish        # serialize the model into deployable assets (compose/bicep/manifests)
aspire deploy         # build images, push, and deploy to the target environment
aspire destroy        # tear a deployed environment back down
```

For Azure, `aspire deploy` integrates with `azd` and emits Bicep. Details and target-specific notes (App Service is the default in the sibling architecture skill) are in [references/deployment.md](references/deployment.md) and [references/azure.md](references/azure.md).

### Step 8: Add an integration test

```csharp
var appHost = await DistributedApplicationTestingBuilder
    .CreateAsync<Projects.AppHost>();
await using var app = await appHost.BuildAsync();
await app.StartAsync();

await app.ResourceNotificationService
    .WaitForResourceAsync("api", KnownResourceStates.Running);

var http = app.CreateHttpClient("api");
var resp = await http.GetAsync("/health");
resp.EnsureSuccessStatusCode();
```

Full patterns in [references/testing.md](references/testing.md).

## Validation

- [ ] `aspire --version` reports 13.4.x and `dotnet --version` is 10.0.100+.
- [ ] AppHost `.csproj` uses `Sdk="Aspire.AppHost.Sdk/13.x"`; every service project is referenced as an Aspire project resource so `Projects.*` resolves.
- [ ] Each backing resource has a matching **hosting** package in the AppHost AND a matching **client** package in every consumer.
- [ ] Connection names line up: `AddDatabase("appdb")` ↔ `AddNpgsqlDbContext<…>("appdb")`; `AddRedis("cache")` ↔ `AddRedisClient("cache")`.
- [ ] Every service calls `AddServiceDefaults()` and `MapDefaultEndpoints()`.
- [ ] Dependencies use both `.WithReference(dep)` and `.WaitFor(dep)` so startup is gated on health.
- [ ] No secrets in source — passwords/keys go through `AddParameter(..., secret: true)` + user-secrets/env.
- [ ] `aspire run` shows all resources reaching **Running** and the dashboard renders traces/metrics.
- [ ] A compute environment is declared before `aspire deploy`; `aspire publish` produces the expected assets.

## Common Pitfalls

| Pitfall | Solution |
|---------|----------|
| Confusing hosting (`AddPostgres`) with client (`AddNpgsqlDbContext`) packages | Hosting `Aspire.Hosting.*` goes in the AppHost; client `Aspire.*` goes in each consuming service. Both are required. |
| `WithReference` but no `WaitFor` | The service may start before the DB is ready and crash on first query. Add `.WaitFor(dep)` for startup-critical deps. |
| Connection name mismatch | The string in `AddDatabase("x")`/`AddRedis("x")` must equal the name in `AddNpgsqlDbContext<…>("x")`/`AddRedisClient("x")`. |
| Hardcoded URLs between services | Use `WithReference(api)` and call the service by its resource name (`https://api`); service discovery resolves it. Hardcoding breaks `WithReplicas`. |
| Containers re-created every run, losing data | `.WithLifetime(ContainerLifetime.Persistent)` and/or `.WithDataVolume(...)` to persist across `aspire run`. |
| Secrets committed to `appsettings.json` | `AddParameter("name", secret: true)` + `dotnet user-secrets` locally / env vars in CI. |
| Forgetting `MapDefaultEndpoints()` | Health probes (`/health`, `/alive`) and readiness gating won't work; deploys may mark the service unhealthy. |
| Mixed Aspire package versions | Keep every `Aspire.*` package on the same 13.4.x minor; run `aspire update`. |
| Expecting TS AppHost to be production-ready | TypeScript AppHost is **preview** (13.2+). Use the C# AppHost for anything you ship. |
| `aspire deploy` with no compute environment | Declare `AddDockerComposeEnvironment`/`AddAzure…Environment`/`AddKubernetesEnvironment` first, or there's nowhere to deploy. |

## Reference Files

- [references/cli.md](references/cli.md) — Full `aspire` command surface (new, init, run, add, update, publish, deploy, destroy, do, start/stop/ps/logs, exec/resource, doctor, certs, config, secret, mcp), install methods, and agent/CI-friendly flags (`--format json`, `--yes`, detached run). **Load when:** driving Aspire from scripts/CI or you need a command you don't remember.
- [references/app-model.md](references/app-model.md) — The C# app model in depth: AppHost project shape, resource types, `WithReference`/`WaitFor`/`WithEnvironment`, endpoints, `WithReplicas`, persistent containers, parameters & secrets, and ServiceDefaults internals. **Load when:** writing or extending the AppHost beyond the basics.
- [references/integrations.md](references/integrations.md) — The hosting-vs-client table for Postgres, Redis, SQL Server, RabbitMQ, Azure Service Bus/Storage/Key Vault/Cosmos, plus the `Aspire.*.EntityFrameworkCore.*` client integrations and registration calls. **Load when:** adding any backing resource.
- [references/azure.md](references/azure.md) — `Aspire.Hosting.Azure.*`, provision-vs-connect (`RunAsEmulator`, `AsExisting`), Bicep generation, and `azd`/App Service publishing context. **Load when:** the target uses real Azure resources.
- [references/deployment.md](references/deployment.md) — `aspire publish`/`aspire deploy`, compute environments, the Docker Compose / Kubernetes publishers, and Azure Container Apps / App Service targets. **Load when:** taking the app to any environment.
- [references/testing.md](references/testing.md) — `Aspire.Hosting.Testing`, `DistributedApplicationTestingBuilder`, waiting on resources, `CreateHttpClient`, and patterns for DB/integration tests. **Load when:** writing integration tests against the resource graph.

## More Info

- [Aspire documentation](https://aspire.dev/) and the legacy redirect at [learn.microsoft.com/dotnet/aspire](https://learn.microsoft.com/dotnet/aspire/) — Official docs.
- [microsoft/aspire](https://github.com/microsoft/aspire) — Source, issues, release notes (samples under the repo).
- [Aspire integrations gallery](https://aspire.dev/integrations/gallery/) — Browse every hosting/client integration and its package IDs.
- [What's new in Aspire 13](https://aspire.dev/whats-new/aspire-13/) — Rename, polyglot support, `aspire do` pipelines, AppHost SDK changes.
