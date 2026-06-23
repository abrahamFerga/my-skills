# Solution Structure & Conventions

The layer responsibilities, dependency rule, and repo-wide build conventions for the
modular-monolith + Clean Architecture default.

> **The concrete .NET 10 + Aspire backbone is owned by
> [`dotnet-aspire-base`](..//development:dotnet-aspire-base).** Defer to it for the
> `dotnet new`/`dotnet sln` steps, the project references, the `ServiceDefaults`
> wiring, and the AppHost composition. This page adds only the *rationale* (layer
> responsibilities, CPM, composition root) plus the root build files in
> [../assets/solution/](../assets/solution/) for standalone use. The two layouts use
> the **same names** — the deployable host is `Api`.

## Project layout

This is the same backbone dotnet-aspire-base generates (`The<Domain>.*` prefix there;
unprefixed here for the standalone scaffold):

```
src/
  Domain/            classlib  — entities, value objects, domain events; no deps
  Application/       classlib  — use cases, CQRS handlers, port interfaces; → Domain
  Infrastructure/    classlib  — EF Core DbContext + adapters; → Application, Domain
  Api/               web       — ASP.NET Core host + composition root; → Application, Infrastructure, ServiceDefaults
  AppHost/           aspire    — local orchestration (NOT deployed); → Api
  ServiceDefaults/   aspire    — shared OTel/health/resilience; referenced by Api
tests/
  Domain.Tests/            unit tests for the domain
  Application.Tests/       use-case tests with port test-doubles
  Api.IntegrationTests/    end-to-end host tests
```

Reference direction (inward only) — the canonical graph owned by
[`dotnet-aspire-base`](..//development:dotnet-aspire-base):

- `Api → Application, Infrastructure` (plus `Api → ServiceDefaults`)
- `Infrastructure → Application, Domain`
- `Application → Domain`
- `Domain → (nothing)`
- `AppHost → Api`

(`Api` references both `Application` and `Infrastructure` directly — the
composition root needs the use-case entry points from `Application` and the
concrete adapters from `Infrastructure` for DI registration.) The generation
commands live with the backbone owner —
[`dotnet-aspire-base`](..//development:dotnet-aspire-base) — or, for the standalone
scaffold, in [../assets/solution/README.md](../assets/solution/README.md).

## The four root files

| File | Role |
|------|------|
| [`global.json`](../assets/solution/global.json) | Pins the **.NET 10 SDK** (`10.0.100`, `rollForward: latestFeature`). CI's `setup-dotnet@v4` reads this via `global-json-file`, so local and CI use the same SDK band. |
| [`Directory.Build.props`](../assets/solution/Directory.Build.props) | Auto-imported into every project. Sets `net10.0`, `Nullable`, `ImplicitUsings`, analyzers, and **warnings-as-errors**. Change the TFM in one place. |
| [`Directory.Packages.props`](../assets/solution/Directory.Packages.props) | **Central Package Management.** `ManagePackageVersionsCentrally=true`; every version is a `<PackageVersion>` here, and `.csproj` files reference packages with no `Version`. |
| [`.editorconfig`](../assets/solution/.editorconfig) | Style rules `dotnet format` enforces; the CI `--verify-no-changes` step fails on drift. |

### Central Package Management in practice

```xml
<!-- Directory.Packages.props (one source of truth) -->
<PackageVersion Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.0.2" />

<!-- Infrastructure.csproj (NO Version attribute) -->
<PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" />
```

Benefits: no version drift across projects, one place to bump, and
`CentralPackageTransitivePinningEnabled` lets you pin transitive versions for
supply-chain control. When you scaffold with `dotnet new`, strip the `Version`
attributes the templates add and move them here.

## Where each layer's responsibilities live

| Layer | Owns | Does NOT contain |
|-------|------|------------------|
| **Domain** | Entities, value objects, aggregates, domain events, domain services, invariants. | EF Core attributes, DTOs, HTTP, DI. |
| **Application** | Use-case handlers (commands/queries), port interfaces (`IOrderRepository`, `IClock`), validation, app-level orchestration. | Concrete EF/HTTP/Azure SDK types. |
| **Infrastructure** | `DbContext`, entity configurations, migrations, repository implementations, external service clients, Key Vault config provider. | Business rules. |
| **Api** | Minimal-API endpoints, request/response models, DI composition, auth, middleware, `AddServiceDefaults()`. | Business rules; direct EF queries (go through Application). |

## Composition root (Api)

`Api/Program.cs` is the only place that wires everything:

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();                 // from ServiceDefaults (Aspire skill)
builder.Services.AddApplication();            // registers use-case handlers
builder.Services.AddInfrastructure(builder.Configuration); // DbContext, adapters

// Pull secrets from Key Vault via the app's Managed Identity (no secrets in config).
var kvUri = builder.Configuration["KeyVault:Uri"];
if (!string.IsNullOrEmpty(kvUri))
{
    builder.Configuration.AddAzureKeyVault(
        new Uri(kvUri),
        new DefaultAzureCredential());        // resolves the UAMI via AZURE_CLIENT_ID
}

var app = builder.Build();
app.MapDefaultEndpoints();                     // health checks from ServiceDefaults
// ... map your endpoints ...
app.Run();
```

`AddApplication` / `AddInfrastructure` are extension methods you write in their
respective projects, keeping the wiring close to what it configures while leaving
the actual `Build()` in Api.

## How this pairs with the sibling skills

### Aspire — AppHost + ServiceDefaults

See [`/development:aspire`](..//development:aspire). The two Aspire projects are part
of this skeleton but owned by the Aspire skill:

- **AppHost** is the local app model — it declares the SQL/cache/etc. resources
  and references `Api`, giving you the dashboard and service discovery in dev. It
  is **not** deployed to App Service; in production the wiring comes from Terraform
  app settings + Managed Identity.
- **ServiceDefaults** centralizes OpenTelemetry, health checks, and resilience.
  `Api` calls `builder.AddServiceDefaults()` and `app.MapDefaultEndpoints()`. Reuse
  it for any service you extract later.

### EF Core — Infrastructure persistence

See [`/development:entity-framework-core`](..//development:entity-framework-core).
The `DbContext`, entity configurations, migrations, and query patterns live in
**Infrastructure** (EF Core via the **Npgsql** provider), implementing repository
ports defined in **Application**. In production the connection string uses
**Managed Identity** — Npgsql obtains an Entra access token via the UAMI, not a
password — see [azure-targets.md](azure-targets.md) and the Terraform
`app_settings` in [../assets/terraform/main.tf](../assets/terraform/main.tf).

## Tests

- **Domain.Tests** — pure, fast, no I/O.
- **Application.Tests** — exercise handlers with in-memory test doubles for ports.
- **Api.IntegrationTests** — `WebApplicationFactory<Program>`; back the data layer
  with the EF in-memory provider for speed or Testcontainers for fidelity (prefer
  Testcontainers where query translation matters). dotnet-aspire-base's variant boots
  the whole AppHost via `Aspire.Hosting.Testing` against real Postgres/Redis.

`dotnet test` in [../assets/github-workflows/ci.yml](../assets/github-workflows/ci.yml)
runs all three with coverage collection.
