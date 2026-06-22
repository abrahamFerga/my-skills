# Modular-Monolith Solution Skeleton (.NET 10 + Aspire 13.x)

A single deployable, internally layered as **Clean Architecture**. One App Service
hosts it today; the seams are drawn so you can carve out services later without a
rewrite. Local orchestration is Aspire; persistence is EF Core 10.

## Folder tree

```
<repo-root>/
├─ global.json                  # pins the .NET 10 SDK
├─ Directory.Build.props        # shared TFM, nullable, analyzers, warnings-as-errors
├─ Directory.Packages.props     # Central Package Management (one version per package)
├─ .editorconfig                # style enforced by `dotnet format` in CI
├─ <App>.sln
├─ src/
│  ├─ Domain/                   # entities, value objects, domain events. ZERO deps.
│  ├─ Application/              # use cases, CQRS handlers, port interfaces. Deps: Domain.
│  ├─ Infrastructure/           # EF Core DbContext, repositories, external clients.
│  │                            #   Deps: Application (+ Domain). See ../entity-framework-core.
│  ├─ Api/                      # ASP.NET Core host: minimal-API endpoints, DI composition root.
│  │                            #   Deps: Application + Infrastructure. The deployable.
│  ├─ AppHost/                  # Aspire app model: wires Api + SQL + cache for local run.
│  │                            #   See ../aspire. NOT deployed to App Service.
│  └─ ServiceDefaults/          # shared OpenTelemetry / health / resilience defaults.
│                               #   Referenced by Api (and any future service). See ../aspire.
└─ tests/
   ├─ Domain.Tests/             # fast, pure unit tests
   ├─ Application.Tests/        # use-case tests with test doubles for ports
   └─ Api.IntegrationTests/     # WebApplicationFactory end-to-end (in-memory or Testcontainers)
```

### The dependency rule

Dependencies point **inward only**: `Api → Infrastructure → Application → Domain`.
Domain references nothing. Application defines interfaces (ports); Infrastructure
implements them (adapters). `Api` is the only project that knows about both
Infrastructure and the outside world, and it is the composition root where DI is
assembled. This is what keeps the monolith splittable.

## Generate the projects

From the repo root, with the SDK pinned by `global.json`:

```bash
# 1) Solution + source projects
dotnet new sln -n App

dotnet new classlib  -n Domain         -o src/Domain
dotnet new classlib  -n Application    -o src/Application
dotnet new classlib  -n Infrastructure -o src/Infrastructure
dotnet new webapi    -n Api            -o src/Api --use-minimal-apis

# 2) Aspire pieces (templates from the Aspire workload; see ../aspire)
dotnet new aspire-apphost        -n AppHost         -o src/AppHost
dotnet new aspire-servicedefaults -n ServiceDefaults -o src/ServiceDefaults

# 3) Tests
dotnet new xunit -n Domain.Tests        -o tests/Domain.Tests
dotnet new xunit -n Application.Tests   -o tests/Application.Tests
dotnet new xunit -n Api.IntegrationTests -o tests/Api.IntegrationTests

# 4) Add everything to the solution
dotnet sln add (Get-ChildItem -Recurse src,tests -Filter *.csproj)   # PowerShell
# bash:  dotnet sln add $(find src tests -name '*.csproj')

# 5) Wire the dependency rule (inward-only references)
dotnet add src/Application    reference src/Domain
dotnet add src/Infrastructure reference src/Application
dotnet add src/Api            reference src/Infrastructure src/ServiceDefaults
dotnet add src/AppHost        reference src/Api
dotnet add tests/Application.Tests    reference src/Application
dotnet add tests/Api.IntegrationTests reference src/Api
```

Then drop the four root files from this folder (`global.json`,
`Directory.Build.props`, `Directory.Packages.props`, `.editorconfig`) into the
repo root. Because Central Package Management is on, remove the `Version="..."`
attributes the templates put on `<PackageReference>` items and add the versions to
`Directory.Packages.props` instead.

## Pairs with the sibling skills

- **AppHost + ServiceDefaults** are owned by the [`aspire`](../../../aspire/SKILL.md)
  skill — local orchestration, service discovery, the dashboard, and the shared
  telemetry/health/resilience defaults `Api` consumes via `AddServiceDefaults()`.
- **Infrastructure persistence** (the `DbContext`, configurations, migrations,
  query patterns) is owned by the
  [`entity-framework-core`](../../../entity-framework-core/SKILL.md) skill.

This skill (`dotnet-architecture`) owns the *shape* — the layering decision, the
project boundaries, the Azure target, and the IaC/CI-CD that ships it.

## Build & run

```bash
dotnet build -c Release          # warnings are errors
dotnet test  -c Release
dotnet run --project src/AppHost # launches the Aspire dashboard + dependencies
```
