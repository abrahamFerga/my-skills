---
name: dotnet-aspire-base
description: >
  Set up the opinionated .NET 10 + Aspire backbone that every generated system in this
  family shares — solution layout, AppHost orchestration, ServiceDefaults (OpenTelemetry,
  health checks, resilience), and the Api + Application + Domain + Infrastructure project
  split, plus a tests project per layer. Produces a solution that boots end-to-end via
  `dotnet run --project src/The<Domain>.AppHost` with the Aspire dashboard green.
  USE FOR: starting a new generated system after the architecture is decided; adding the
  backend to a project where the frontend was scaffolded first; refactoring an existing
  project onto the current backbone layout; wiring ServiceDefaults / OTel / health checks.
  DO NOT USE FOR: front-end setup (a react-vite-shadcn skill covers that); MAF agent
  registration (use ../agent-framework-csharp/SKILL.md); the pluggable-connector pattern (use
  ../pluggable-connectors/SKILL.md); proving the system actually behaves at runtime
  (use ../verify-runtime/SKILL.md). For deeper Aspire app-model / deployment detail see
  ../aspire/SKILL.md; for EF Core entity/migration modeling see ../entity-framework-core/SKILL.md.
license: MIT
disable-model-invocation: true
---

# dotnet-aspire-base

Establishes the .NET backbone every system in this family shares. The output is a solution that boots end-to-end via `dotnet run --project src/The<Domain>.AppHost` (or `aspire run`), with the Aspire dashboard showing every service, OpenTelemetry traces flowing, and health checks green.

This is a stack skill: it encodes the *how* for the .NET 10 + Aspire layer so the rest of the workflow can compose against it. Deeper Aspire mechanics (CLI, app model, publish/deploy, integration-testing builder) live in [../aspire/SKILL.md](../aspire/SKILL.md); EF Core entity/migration/query modeling lives in [../entity-framework-core/SKILL.md](../entity-framework-core/SKILL.md). This skill creates the backbone those skills then fill in.

## Approach

Work as a senior implementation engineer: methodical, test-first, allergic to clever code. The architecture is law — if the architecture doc names EF Core, Postgres, Quartz, you use exactly those; substituting a library is a decision that needs an ADR, not a quiet implementation detail. Boring, obvious code wins; if a junior can't read it in two minutes, simplify. Wire the cross-cutting concerns from day one rather than "later." Generate files; don't commit or push — the user reviews.

## When to use

- Starting a new generated system, once the architecture is decided
- Adding the backend to a project where the frontend was scaffolded first
- Refactoring an existing project onto the current backbone layout

## When NOT to use

- Frontend-only work (use a react-vite-shadcn skill)
- Agentic features (use [../agent-framework-csharp/SKILL.md](../agent-framework-csharp/SKILL.md) — this skill sets up the host, not the agents)
- The pluggable-connector pattern (use [../pluggable-connectors/SKILL.md](../pluggable-connectors/SKILL.md))
- Proving the system behaves at runtime (use [../verify-runtime/SKILL.md](../verify-runtime/SKILL.md))

## Version / toolchain

| Concern | Choice | Notes |
|---|---|---|
| SDK | .NET 10 | Pinned in `Directory.Build.props` / `global.json` |
| Orchestration | Aspire (AppHost + ServiceDefaults) | Local dev/run orchestration only — no cloud resources here |
| API style | Minimal APIs | No MVC controllers |
| Persistence | EF Core + Postgres | Registered via Aspire `AddPostgres("db")`; entity modeling in ../entity-framework-core/SKILL.md |
| Cache | Redis | Registered through Aspire; used for session, idempotency replay, rate-limit windows |
| Telemetry | OpenTelemetry via ServiceDefaults | Traces, metrics, logs — on by default |
| Resilience | `StandardResilienceHandler` (Polly) | On outbound HTTP via ServiceDefaults |
| Config | `IOptions<T>` with `ValidateOnStart` | No string-key `IConfiguration` reads in business code |
| Background jobs | Quartz.NET or Hangfire | One choice, locked in here; tenant-aware and dashboard-observable |
| Namespaces | File-scoped | Enforced via `.editorconfig` |

## Solution layout this skill produces

```text
The<Domain>/
├── The<Domain>.sln
├── src/
│   ├── The<Domain>.AppHost/              # Aspire orchestration entry point
│   ├── The<Domain>.ServiceDefaults/      # OTel, health checks, resilience, DI conventions
│   ├── The<Domain>.Api/                  # Minimal APIs
│   ├── The<Domain>.Application/          # Use cases, MediatR-style handlers, validators
│   ├── The<Domain>.Domain/               # Entities, value objects, domain events
│   └── The<Domain>.Infrastructure/       # EF Core, external services, persistence
└── tests/
    ├── The<Domain>.Domain.Tests/
    ├── The<Domain>.Application.Tests/
    └── The<Domain>.IntegrationTests/      # Aspire.Hosting.Testing — boots the whole AppHost
```

The [../verify-runtime/SKILL.md](../verify-runtime/SKILL.md) pattern adds `tests/The<Domain>.E2E/` (Playwright) when the system has a SPA, plus a committed `http/` request catalog and the Aspire MCP wiring this layout anticipates.

Cloud-specific infrastructure goes in its own project added later by the cloud skill — `The<Domain>.Infrastructure.Azure/` or `The<Domain>.Infrastructure.Aws/`. It is NOT created here: Aspire is local orchestration only.

## Steps

1. **Create the solution and projects** using `dotnet new`:
   ```bash
   dotnet new sln -n The<Domain>
   dotnet new aspire-apphost -o src/The<Domain>.AppHost
   dotnet new aspire-servicedefaults -o src/The<Domain>.ServiceDefaults
   dotnet new webapi -o src/The<Domain>.Api --use-minimal-apis
   dotnet new classlib -o src/The<Domain>.Application
   dotnet new classlib -o src/The<Domain>.Domain
   dotnet new classlib -o src/The<Domain>.Infrastructure
   # ... plus the tests projects
   ```
2. **Add references**:
   - `Api` → `Application`, `Infrastructure`, `ServiceDefaults`
   - `Application` → `Domain`
   - `Infrastructure` → `Application`, `Domain`
   - `AppHost` → `Api` (and any other services)
3. **Wire `ServiceDefaults`** with OpenTelemetry (traces, metrics, logs), `AddServiceDiscovery`, `AddDefaultHealthChecks`, and the resilience handler. The API project calls `builder.AddServiceDefaults()` and `app.MapDefaultEndpoints()`.
4. **AppHost composition**: register the API, Postgres (`AddPostgres("db")`), Redis, and any other Aspire resources the architecture specifies. Do not register cloud-specific resources here — Aspire is local orchestration only.
5. **Add `Directory.Build.props`** at solution root pinning the SDK to .NET 10, enabling nullable, implicit usings, and treating warnings as errors in `Release`. Add **`Directory.Packages.props`** with `ManagePackageVersionsCentrally=true` (Central Package Management): every version is a `<PackageVersion>` here and `.csproj` files reference packages with no `Version`. Strip the `Version` attributes the `dotnet new` templates add.
6. **Add `.editorconfig`** with the standard Microsoft .NET C# rules plus a few opinions: `csharp_style_namespace_declarations = file_scoped`, `dotnet_style_qualification_for_* = false:warning`.
7. **Validate** with `dotnet build`, then bring the system up with `aspire run` (or `dotnet run --project src/The<Domain>.AppHost`) and `aspire wait` until every resource is healthy. The Aspire dashboard should open and all resources should turn green. Proving the system actually *behaves* — and debugging it when it doesn't — is the job of [../verify-runtime/SKILL.md](../verify-runtime/SKILL.md).

## Guardrails

This skill is the place where the family's cross-cutting contract gets its foundation. Wire it in from day one; surface any conflict with the user before downgrading, and record an intentional deviation as an ADR rather than silently dropping a requirement.

- **Minimal APIs only** — no MVC controllers.
- **`IOptions<T>` for all config** with `ValidateOnStart` — no string-key `IConfiguration` reads in business code.
- **OpenTelemetry on by default** through ServiceDefaults — never `Console.WriteLine`; use `ILogger<T>` + OTel.
- **File-scoped namespaces, nullable enabled**, treat warnings as errors in `Release`.
- **A tests project per source project.** Integration tests boot the whole app via `Aspire.Hosting.Testing` (real Postgres/Redis, real service discovery, real connection strings injected by Aspire) — not in-memory fakes. See [../verify-runtime/SKILL.md](../verify-runtime/SKILL.md).
- **Cross-cutting requirements from day one.** Every generated system in this family must wire, from the first epic: OIDC auth; configurable RBAC bound to authorization policies; multi-tenancy at the data layer (tenant id on every domain table, EF query filters, a resolved `ITenantContext` per request); audit logging for domain mutations; health checks per service; API versioning via URL segment (`/api/v1/...`); Problem Details (RFC 7807) error responses; idempotency keys on writes; per-tenant + per-endpoint rate limiting; explicit CORS; Polly resilience on outbound calls; Redis distributed cache; a background-job scheduler; the outbox pattern for external side effects; GDPR export/delete; and `[Pii]` tagging. This skill stands up the host and the wiring points; the feature skills fill in the per-endpoint specifics. A backbone that can't accommodate these means the architecture is wrong — surface it.
- **Stop on red.** If `dotnet build` fails or a test fails, fix it before moving on. Do not advance with the build red.
- **Generate, don't push.** Produce files; the user reviews and commits.

## Related skills

- [../aspire/SKILL.md](../aspire/SKILL.md) — deeper Aspire CLI, app model, publish/deploy, and `DistributedApplicationTestingBuilder` detail this backbone builds on.
- `/architecture:dotnet-architecture` — the architecture-style decision (modular monolith / Clean Architecture / vertical slice), plus Terraform + GitHub Actions to ship this backbone to Azure. It defers to this skill for the concrete backbone and uses the same `Api` host name.
- [../entity-framework-core/SKILL.md](../entity-framework-core/SKILL.md) — EF Core entity/migration/query modeling inside the `Infrastructure` project.
- [../pluggable-connectors/SKILL.md](../pluggable-connectors/SKILL.md) — the after-the-fact integration pattern that mounts onto this backbone.
- [../verify-runtime/SKILL.md](../verify-runtime/SKILL.md) — installs the integration-test host, `.http` catalog, Playwright E2E, and Aspire MCP wiring this layout anticipates, and drives the run/debug/test loop.
- [../agent-framework-csharp/SKILL.md](../agent-framework-csharp/SKILL.md) — adds Microsoft Agent Framework to the Application layer. An rbac skill adds role/policy infrastructure; an azure-terraform / aws-terraform skill adds the `Infrastructure.<Cloud>` project + IaC (those skills are not yet ported here).
