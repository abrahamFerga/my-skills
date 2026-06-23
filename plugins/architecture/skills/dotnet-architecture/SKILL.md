---
name: dotnet-architecture
description: >
  Designs a .NET system end to end — architecture style, solution structure, and
  Azure service selection — then generates the infrastructure-as-code and CI/CD to
  ship it. Leads with a modular monolith built in Clean Architecture, deployed to
  Azure App Service (Linux), with ready-to-use Terraform (azurerm) and GitHub
  Actions (OIDC) scaffolding plus an architecture decision document. Acts as a
  decision guide across vertical slice / microservices / DDD and App Service vs
  ACA / AKS / Functions.
  USE FOR: greenfield .NET architecture; choosing an architecture style; laying
  out a solution (Clean Architecture, Central Package Management, ServiceDefaults);
  picking Azure services (compute, data, messaging, cache, secrets, identity,
  observability); generating Terraform + GitHub Actions to deploy to Azure App
  Service; wiring Managed Identity, Key Vault, and OIDC.
  DO NOT USE FOR: deep Aspire app-model work (orchestration, resources, the
  dashboard) → ../aspire; EF Core data modeling, migrations, query tuning →
  ../entity-framework-core; building agent/LLM apps → agent-framework-csharp;
  deploying to AWS/GCP or non-Azure clouds.
license: MIT
disable-model-invocation: true
---

# .NET System Architecture (Azure / Terraform / GitHub Actions)

Design a .NET 10 system and produce everything needed to run it on Azure. This
skill does two jobs: **(1) decide the shape** — architecture style, project
layout, and which Azure services to use — and **(2) scaffold the delivery** —
copy-ready Terraform and GitHub Actions, recording the choices as ADRs in the
canonical `DECISIONS.md`.

This is the **.NET/Azure realization** of the cloud-agnostic architecture docs from
[`design-architecture`](../design-architecture/SKILL.md): that skill produces `ARCH.md`,
the C4 diagrams, and `DECISIONS.md`; this skill turns those decisions into a layered
solution skeleton, Terraform, and CI/CD. When this skill is used inside that workflow,
its decisions are appended to the **same `DECISIONS.md`** — it does not introduce a
competing ADR file.

The opinionated default — chosen so the scaffold is concrete, not because it's the
only answer — is a **modular monolith** layered with **Clean Architecture**,
deployed to **Azure App Service (Linux)**, backed by **Azure Database for
PostgreSQL Flexible Server** (which matches the local Aspire Postgres and the
[`design-architecture`](../design-architecture/SKILL.md) Postgres guardrail),
secured with a **User-Assigned Managed Identity** + **Key Vault**, and shipped via
**OIDC** (no stored credentials). The skill still guides you to vertical slice,
microservices, ACA/AKS/Functions, or Azure SQL when the requirements call for it.

## When to Use

- Starting a new .NET service/app and deciding how to structure it
- Choosing an architecture style (monolith vs. services; layered vs. vertical slice)
- Laying out a multi-project solution with shared conventions (CPM, analyzers)
- Selecting Azure services for compute, data, messaging, cache, secrets, identity, observability
- Generating Terraform to provision Azure and GitHub Actions to build/deploy
- Wiring Managed Identity, Key Vault, and OIDC so nothing stores a secret
- Producing an Architecture Decision record for the choices made

## Stop Signals

- **Deep Aspire app-model work** (declaring resources, service discovery, the
  dashboard, `AddProject`/`AddContainer`) → use `/development:aspire`.
  This skill only consumes `AppHost` + `ServiceDefaults`.
- **EF Core data modeling** (entities, configurations, migrations, query tuning;
  the **Npgsql** provider for PostgreSQL) → use
  `/development:entity-framework-core`.
- **Agent / LLM apps** (tools, multi-agent, MCP) → use `agent-framework-csharp`.
- **Non-Azure clouds** (AWS/GCP) → the Terraform/CI here is Azure-specific.
- **An existing, working architecture that just needs a feature** → don't
  re-architect; make the change in place.

## Inputs

Elicit these before recommending anything. Defaults apply when the user is unsure.

| Input | Why it matters | Default if unstated |
|-------|----------------|--------------------|
| Workload type | API / web app / worker / event-driven shapes the compute target | Web API + UI on App Service |
| Expected scale | Drives plan SKU, zone redundancy, monolith vs. services | Moderate; single region |
| Team size & maturity | Small teams → monolith; platform teams can run services/AKS | 1–6 devs → monolith |
| Data needs | Relational vs. document; transactions; reporting | PostgreSQL Flexible Server (relational) |
| Compliance / isolation | Data residency, tenancy, Entra-only auth, private networking | Entra-only auth; public endpoints in dev |
| Budget sensitivity | Serverless/scale-to-zero vs. always-on; SKU tiers | Cost-conscious dev, resilient prod |
| Existing infra | Reuse an RG, vnet, registry, or Entra app | Greenfield |
| Region(s) | Single vs. multi-region; latency | `westeurope`, single region |

## Version / toolchain

| Tool | Version | Notes |
|------|---------|-------|
| .NET SDK | **10.0.x** | Pinned by [`global.json`](assets/solution/global.json); `net10.0` TFM |
| ASP.NET Core | 10.0 | The `Api` host (the deployable) |
| Aspire | **13.x** | Local orchestration; AppHost + ServiceDefaults — see `/development:aspire` |
| EF Core | **10** | Persistence in Infrastructure via the **Npgsql** provider (`Npgsql.EntityFrameworkCore.PostgreSQL` 10.0.x) — see `/development:entity-framework-core` |
| Terraform | ≥ 1.9 | CI installs `1.13.0` via `setup-terraform@v3` |
| azurerm provider | **`~> 4.0`** | Current major; `features {}` required |
| azuread provider | `~> 3.0` | Entra admin on the database, federated creds |
| `azure/login` | `@v2` | OIDC login |
| `actions/setup-dotnet` | `@v4` | Reads `global.json` |
| `azure/webapps-deploy` | `@v3` | App Service deploy |

> Verify exact package/provider patch versions against the registry before a real
> deploy; the values in the assets are tested-baseline placeholders, not gospel.

## Decision framework

**Pick the architecture style:**

```
Small/medium team, evolving domain, one product   ──► Modular monolith + Clean Architecture  ★ default
CRUD-/feature-heavy, little shared domain logic    ──► add Vertical Slice in the Application layer
Measured need: independent scale/deploy/isolation  ──► extract the hottest module to a service
Org maps to services + platform team + ops maturity──► microservices from the start (rare)
```

**Pick the compute target:**

```
A monolith / a few web apps        ──► Azure App Service (Linux)   ★ default (scaffold targets this)
Several containers, scale-to-zero  ──► Azure Container Apps
A fleet + a platform team          ──► AKS
Triggers / schedules / glue        ──► Azure Functions (often alongside the monolith)
```

Lead with **modular monolith on App Service**. It is a single deployable with
clean internal seams, the cheapest to run and operate, and splittable later
*without a rewrite* because the boundaries are already drawn. Recommend something
heavier only when a concrete force (scale profile, deploy independence, isolation,
team autonomy) is present and measured. Full reasoning, with the split criteria
and the Azure selection matrices, is in [references/patterns.md](references/patterns.md)
and [references/azure-targets.md](references/azure-targets.md).

## Core Mental Model

Two views: the **layers inside the deployable**, and the **Azure target** it runs on.

```
  In-process layering (Clean Architecture) — one App Service deployable
  ┌──────────────────────────────────────────────────────────────┐
  │  Api (ASP.NET Core host, endpoints, DI composition root)       │
  │    └─ AddServiceDefaults()  ◄── ServiceDefaults (Aspire skill) │
  │  ┌────────────────────────────────────────────────────────┐   │
  │  │ Infrastructure (EF Core DbContext, adapters, KV config) │   │  → ../entity-framework-core
  │  │  ┌──────────────────────────────────────────────────┐  │   │
  │  │  │ Application (use cases, ports, CQRS handlers)     │  │   │
  │  │  │  ┌────────────────────────────────────────────┐  │  │   │
  │  │  │  │ Domain (entities, value objects, events)   │  │  │   │
  │  │  │  └────────────────────────────────────────────┘  │  │   │
  │  │  └──────────────────────────────────────────────────┘  │   │
  │  └────────────────────────────────────────────────────────┘   │
  └──────────────────────────────────────────────────────────────┘
        AppHost (Aspire) orchestrates this + Postgres + cache LOCALLY only.

  Azure target (what Terraform builds)
  ┌──────────────── Resource Group (rg-<app>-<env>) ────────────────┐
  │  User-Assigned Managed Identity ──┬─► Key Vault (RBAC; Secrets User) │
  │                                   ├─► PostgreSQL Flex (Entra-only)   │
  │  App Service Plan (Linux)         └─► reads secrets / DB, no password │
  │     └─ Linux Web App (.NET 10) ── identity ▶ UAMI                     │
  │            app_settings ► App Insights conn str, KV refs, DB conn     │
  │  Log Analytics ◄── Application Insights (workspace-based)             │
  └──────────────────────────────────────────────────────────────────────┘
        GitHub Actions ──OIDC──► Azure   (no stored credentials)
```

## Workflow

### Step 1: Elicit requirements

Work through the [Inputs](#inputs) table. Capture answers verbatim — they become
the "Context" section of the Architecture Decision document in Step 8. Don't
recommend before you have workload type, scale, team size, and data needs.

### Step 2: Choose the architecture style

Apply the [Decision framework](#decision-framework). Default to a **modular
monolith + Clean Architecture** unless a measured force says otherwise. Record the choice
and the force that drove it. Detail: [references/patterns.md](references/patterns.md).

### Step 3: Lay out the solution

The concrete .NET 10 + Aspire backbone — the `dotnet new`/`dotnet sln` generation
steps, project references, `ServiceDefaults` wiring, and AppHost composition — is
owned by `/development:dotnet-aspire-base`. **Defer to it for
the backbone**; do not re-run a competing skeleton here. The shared backbone projects
are `Domain` / `Application` / `Infrastructure` / `Api` (the deployable host) /
`AppHost` / `ServiceDefaults` + `tests/*`, with the inward-only dependency rule and
Central Package Management.

This skill adds only the **layering decision rationale** (which style, why) on top of
that backbone, plus the root build conventions captured in
[assets/solution/](assets/solution/) (`Directory.Build.props`, `Directory.Packages.props`,
`global.json`, `.editorconfig`) for standalone use. Detail and how it pairs with
dotnet-aspire-base: [references/solution-structure.md](references/solution-structure.md).

### Step 4: Pick Azure services

Use the matrices in [references/azure-targets.md](references/azure-targets.md):
compute (App Service default), data (PostgreSQL Flexible Server default, Azure SQL
alternative), plus messaging/cache/storage/secrets/identity/observability as the
requirements demand. Default to **App Service + PostgreSQL Flexible Server
(Entra-only) + Key Vault + App Insights/Log Analytics + UAMI**.

### Step 5: Generate Terraform

Copy [assets/terraform/](assets/terraform/) into `infra/` and set the per-env
values in `environments/<env>.tfvars` (`app_name`, region, SKUs, Postgres admin
Entra principal). Toggle/replace resources to match Step 4 (e.g. disable the data
tier with `enable_postgres = false`, or swap in Azure SQL). Then:

```bash
cd infra
terraform fmt -recursive
terraform init -backend-config="key=dev.tfstate"   # state RG/SA/container must pre-exist
terraform validate
terraform plan -var-file="environments/dev.tfvars"
```

How it's structured (state, naming, MI/KV/OIDC wiring):
[references/terraform.md](references/terraform.md).

### Step 6: Generate GitHub Actions

Copy [assets/github-workflows/](assets/github-workflows/) into
`.github/workflows/`. Three workflows: `ci.yml` (build/test/format),
`cd-infra.yml` (plan on PR, apply on main behind a prod gate), `cd-app.yml`
(publish + deploy to App Service). All authenticate via **OIDC** with
`permissions: id-token: write` — no stored passwords. Set the repo/environment
variables (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
`TFSTATE_*`, `AZURE_WEBAPP_NAME`) and configure federated credentials. Detail:
[references/github-actions.md](references/github-actions.md).

### Step 7: Wire observability, security & Managed Identity

Confirm the spine is intact end to end:

- App reads config/secrets via Key Vault + `DefaultAzureCredential` (resolves the
  UAMI through `AZURE_CLIENT_ID`); **no secrets in source or app settings**.
- Key Vault uses **RBAC** (`rbac_authorization_enabled = true`); the UAMI has
  **Key Vault Secrets User**.
- PostgreSQL Flexible Server is **Entra-only** (`password_auth_enabled = false`,
  `active_directory_auth_enabled = true`); the app connects with its identity —
  Npgsql obtains an Entra access token via the UAMI (`Azure.Identity`). Remember the
  post-provision step: grant the UAMI a Postgres role mapped to its Entra identity.
  (Azure SQL alternative: `azuread_authentication_only = true`.)
- `https_only = true`, `minimum_tls_version = "1.2"`.
- OpenTelemetry/App Insights enabled (via `AddServiceDefaults()` from the Aspire
  skill or `Azure.Monitor.OpenTelemetry.AspNetCore`).

### Step 8: Record the decisions as ADRs in `DECISIONS.md`

Append one or more ADRs to the canonical **`DECISIONS.md`** at the system root —
the same file [`design-architecture`](../design-architecture/SKILL.md) owns; do **not**
create a separate `docs/architecture-decision.md`. Capture: the **context**
(requirements from Step 1), the **decision** (style, compute target, data store,
key services), the **alternatives considered** and why rejected, and the
**consequences** (what gets easier, what gets harder, the explicit split-later
path). Follow the ADR structure in
[`design-architecture`](../design-architecture/SKILL.md) — sequential `ADR-NNNN`
numbering, ISO dates, append-only. If you are running this skill standalone (outside
the workflow) and no `DECISIONS.md` exists yet, create it. This is the durable artifact
the rest of the team reads.

## Validation

- [ ] Architecture style chosen with an explicit driving force recorded
- [ ] Solution generated with the inward-only dependency rule; `dotnet build -c Release` clean (warnings = errors)
- [ ] Central Package Management on; no `Version` on individual `<PackageReference>`s
- [ ] `terraform fmt -check -recursive` clean
- [ ] `terraform validate` passes; `plan` runs against a `*.tfvars`
- [ ] Variables defined in `variables.tf`, referenced in `main.tf`, surfaced in `outputs.tf`; tfvars set env values
- [ ] Every resource tagged (`environment`, `app`, `managed-by = terraform`)
- [ ] **User-Assigned Managed Identity** wired into the web app + granted Key Vault Secrets User via RBAC
- [ ] App Insights connection string reaches the app via app settings; KV used for secrets
- [ ] All three workflows parse; CD jobs use `permissions: id-token: write` and `azure/login@v2` (OIDC)
- [ ] **No secrets in code, tfvars, or app settings**; no `ARM_CLIENT_SECRET`, no publish profile
- [ ] Prod `apply`/deploy gated by a GitHub `environment` with required reviewers
- [ ] Decisions recorded as ADRs in the canonical `DECISIONS.md` (no competing `docs/architecture-decision.md`)

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Jumping to microservices with no forcing function | Start modular monolith; extract on a measured need. See [patterns.md](references/patterns.md). |
| Letting module/layer boundaries leak (Api querying EF directly) | Enforce inward-only refs: Api → Application + Infrastructure; Infrastructure → Application + Domain; Application → Domain. Queries go through Application. |
| Per-project package versions drifting | Central Package Management — versions only in `Directory.Packages.props`. |
| `enable_rbac_authorization` on Key Vault | Wrong name. It's **`rbac_authorization_enabled = true`** in azurerm v4. |
| Key Vault references fail with a user-assigned identity | Set `key_vault_reference_identity_id` on the web app to the UAMI. |
| Storing a database password (in tfvars/app settings) | Use Entra-only auth + Managed Identity (Postgres `password_auth_enabled = false`); if a password is unavoidable, put it in Key Vault and reference it. |
| Forgetting the Postgres UAMI role grant | Entra auth on the server is not enough — post-provision, create a Postgres role mapped to the UAMI's Entra identity and grant it on the database, or the app can't connect. |
| `ARM_CLIENT_SECRET` / publish profile in CI | Use OIDC: `id-token: write` + `azure/login@v2` with federated credentials. No long-lived creds. |
| OIDC works on push but fails in a gated job | The federated credential subject must include the `environment:<name>` form, not just the branch ref. |
| `terraform init` fails: backend storage missing | Bootstrap the state RG/SA/container once before the first init. |
| Always On error on a `B1` plan | Always On needs Standard/Premium; the scaffold disables it on `B1`. |
| Missing `features {}` in the provider block | Required by azurerm even when empty. |
| Treating AppHost as the deployable | AppHost is local-only orchestration; the `Api` host is what deploys. See `/development:aspire`. |

## Reference Files

- [references/patterns.md](references/patterns.md) — Architecture styles: modular
  monolith, Clean Architecture layers, vertical slice, microservices, DDD building
  blocks, and the criteria for splitting a module into a service. **Load when:**
  choosing or justifying an architecture style.
- [references/solution-structure.md](references/solution-structure.md) — The layer
  responsibilities, the inward-only dependency rule, Central Package Management, the
  root build files (`Directory.Build.props`/`global.json`/`.editorconfig`), and the
  composition root — the *rationale* on top of the backbone. The concrete `dotnet new`
  generation is deferred to `/development:dotnet-aspire-base`.
  **Load when:** justifying the layering or wiring the build conventions.
- [references/azure-targets.md](references/azure-targets.md) — Service-selection
  matrices: compute (App Service default vs. ACA/AKS/Functions), data (PostgreSQL
  Flexible Server default vs. Azure SQL alternative), and Service Bus / Redis /
  Storage / Key Vault / App Insights+Log Analytics / Entra ID + Managed Identity,
  with the security baseline. **Load when:** picking Azure services.
- [references/terraform.md](references/terraform.md) — The Terraform scaffold:
  single-root + per-env state/tfvars layout, remote-state bootstrap, azurerm v4
  provider, naming/tagging, the Managed Identity + Key Vault (RBAC) wiring, and
  GitHub OIDC. **Load when:** generating or editing infrastructure.
- [references/github-actions.md](references/github-actions.md) — The three
  workflows, pinned action versions, the OIDC token-exchange flow, the one-time
  Azure federated-credential setup, and environment gates/approvals. **Load when:**
  generating or editing CI/CD.

## More Info

- [Azure Architecture Center](https://learn.microsoft.com/azure/architecture/) — reference architectures and the well-architected framework
- [azurerm provider docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs) — exact resource schemas (verify before deploying)
- [Authenticate to Azure from GitHub Actions with OIDC](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect) — federated credentials setup
- [App Service Key Vault references](https://learn.microsoft.com/azure/app-service/app-service-key-vault-references) — `@Microsoft.KeyVault(...)` and identity selection
- [.NET application architecture guides](https://learn.microsoft.com/dotnet/architecture/) — Clean Architecture, modular monolith, and microservices e-books
