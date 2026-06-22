---
name: design-architecture
description: >
  Read PLAN.md and produce ARCH.md plus C4 diagrams and a DECISIONS.md of ADRs —
  the architecture artifacts build-system executes against. Locks in concrete technology
  choices, the solution layout, cross-cutting wiring (auth, RBAC, multi-tenancy, OTel,
  resilience, caching, background work), cloud topology, the concrete data model and API
  surface, MAF agent design, and SPA architecture. Phase 4 of the workflow: turns the plan
  into buildable decisions, each compliant with the enterprise guardrails or justified by an ADR.
  USE FOR: choosing concrete technologies that comply with the guardrails; drawing C4 context/
  container/component diagrams; defining the .NET solution layout and project naming; pinning a
  single provider per cross-cutting concern; designing the EF Core data model and versioned API
  surface; specifying MAF agents and the SPA architecture; recording non-default choices as ADRs.
  DO NOT USE FOR: deciding what the system does (use ../synthesize-spec/SKILL.md); breaking work
  into epics and build order (use ../plan-system/SKILL.md); generating source code (use
  ../build-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# design-architecture

Phase 4 of the workflow. Turns the plan into concrete architectural decisions and visual
artifacts. Every choice here is constrained by the enterprise guardrails — when a guardrail
conflicts with the plan, the architecture must reconcile that conflict (usually with an ADR)
before generation can start.

You operate here as a **staff-level system architect**: pragmatic, decisive, and willing to
write things down. You pin a single provider per concern, partition cloud-specific code behind
interfaces so a second cloud target is a finite project rather than a rewrite, and reach for
boring technology (Postgres, EF Core, Redis, Polly, OTel) when reliability matters. You write
the ADR when you deviate, not "sometime later" — and you don't over-architect: design for v1's
success metrics, choose patterns that fit the *current* bounded context, and refuse premature abstractions.

This skill produces **cloud-agnostic architecture documents** — `ARCH.md`, C4 diagrams, and
`DECISIONS.md` — that `build-system` executes against. It does **not** generate the .NET solution
skeleton, Terraform, or CI/CD: that .NET/Azure realization is [`dotnet-architecture`](../dotnet-architecture/SKILL.md)
(which scaffolds the layered solution, IaC, and GitHub Actions) standing on the concrete backbone
from [`dotnet-aspire-base`](../dotnet-aspire-base/SKILL.md). For the architecture-style decision guide
(modular monolith, Clean Architecture layering, vertical slice, microservices, DDD blocks, and the
split-to-service criteria), defer to [`dotnet-architecture`'s patterns reference](../dotnet-architecture/references/patterns.md)
rather than re-deriving it here.

## When to Use

- `PLAN.md` exists and you need concrete technology choices and a buildable architecture.
- You need C4 context / container / component diagrams for the system.
- You need the .NET solution layout, project naming, and per-context project list.
- You need to pin one provider per cross-cutting concern (OTel, MAF, RBAC, multi-tenancy, caching, scheduling).
- You need the concrete EF Core data model, the versioned API surface, MAF agent specs, and the SPA architecture.
- You need to record non-default decisions as ADRs.

## Stop Signals

- **Deciding what the system does** → use [`synthesize-spec`](../synthesize-spec/SKILL.md).
- **Breaking work into epics / build order** → use [`plan-system`](../plan-system/SKILL.md).
- **Generating source code** → use [`build-system`](../build-system/SKILL.md).

## Inputs

| Input | Required | Description |
|---|---|---|
| `PLAN.md` | Yes | Produced by [`plan-system`](../plan-system/SKILL.md). Epics, modules, RBAC, integration surface, background work. |
| `SPEC.md` | Always consulted | Capabilities, personas, success metrics — the *why* behind the plan. |
| `workflow.json` | When present | Cloud target, declared connectors, capabilities, skill marketplaces. |
| Enterprise guardrails (below) | Yes | The cross-cutting requirements and technology constraints every choice must comply with. |

## Output

Three artifacts at the generated system's root.

1. **`ARCH.md`** — the architecture document (structure below).
2. **`docs/diagrams/`** — C4 context, container, and component diagrams (PlantUML or Mermaid).
3. **`DECISIONS.md`** — ADRs for any non-default choice (structure below).

### `ARCH.md` structure

This is the authoritative structure — follow it exactly. `build-system` walks the *Solution
layout* and *Cross-cutting wiring* sections to know what to create and wire.

```markdown
# <System name> — Architecture

## Context (C4 L1)
External actors and the system as a single box.
Diagram: `docs/diagrams/c1-context.puml`

## Containers (C4 L2)
Backend API, AppHost, SPA, database, vector store, cache, queue, MAF agent
host, connector services. Each is an Aspire resource.
Diagram: `docs/diagrams/c2-containers.puml`

## Components (C4 L3) — key containers only
Inside the API: minimal-API endpoint groups, MediatR-style handlers, MAF
agents, connector adapters.
Diagram: `docs/diagrams/c3-components-api.puml` (and others as needed)

## Solution layout
Document the *shape* (which projects exist and why) — the concrete .NET backbone is
owned by dotnet-aspire-base and scaffolded by dotnet-architecture; do not re-derive
the `dotnet new` steps here.

src/
  The<Domain>.AppHost/                ← Aspire AppHost
  The<Domain>.ServiceDefaults/        ← OTel + health + resilience
  The<Domain>.Api/                    ← minimal APIs grouped by bounded context
  The<Domain>.Application/            ← shared application services
  The<Domain>.Application.<Context>/  ← one per epic from PLAN
  The<Domain>.Domain/                 ← entities + value objects + domain events
  The<Domain>.Infrastructure/         ← EF Core + outbox + multi-tenancy filters
  The<Domain>.Infrastructure.<Cloud>/ ← cloud-specific implementations
  The<Domain>.Infrastructure.<Connector>/  ← one per installed connector
  The<Domain>.Web/                    ← Vite SPA

tests/
  one test project per source project; integration tests use Testcontainers

## Cross-cutting wiring
- **AuthN**: <provider> via OIDC
- **RBAC**: policies from PLAN, mapped to `<PolicyName>` classes; UI gating via the same names
- **Multi-tenancy**: tenant id resolved from <source>, enforced via EF query filters
- **Observability**: OTel exporters → <sink>, dashboards, alert rules
- **Resilience**: Polly handlers on <which outbound calls>
- **Caching**: Redis topology, what's cached, TTLs
- **Background work**: <scheduler> + outbox configuration
- **Idempotency**: <store> for replay records

## Cloud topology
Record the target and the topology decisions cloud-agnostically; the concrete Azure
realization (Terraform, Managed Identity, Key Vault, App Service) is dotnet-architecture's job.
- **Provider**: <azure | aws>
- **Compute**: <Container Apps | ECS/Fargate | ...>
- **Data**: <Postgres flavor>
- **Vector**: <pgvector | Azure AI Search | Pinecone>
- **Secrets**: <Key Vault | Secrets Manager>
- **Identity**: <Entra ID | Cognito>
- **CDN / Edge**: <if applicable>
- **Networking**: VNet/VPC layout, ingress, private endpoints

## Data model (concrete)
EF Core entities + relationships + migrations strategy + PII attribute usage.

## API surface (concrete)
- Endpoint groups by bounded context: `/api/v1/<group>/...`
- Versioning: URL segment
- Errors: Problem Details (RFC 7807)
- Writes: idempotency keys (`Idempotency-Key` header, 24h replay window)
- Rate limits: <defaults + per-endpoint overrides>

## MAF agents
For each agent:
- **<Agent name>** — purpose, tools registered (including channel connectors),
  system prompt outline, memory store, conversation persistence.

## SPA architecture
- Routing: <library + pattern>
- State: <library / approach>
- Components: shadcn primitives + the shared `DataTable` + the shared `Form` + the slide-over chatbot panel
- Feature folders per bounded context

## Diagrams checked into the repo
- `docs/diagrams/c1-context.puml`
- `docs/diagrams/c2-containers.puml`
- `docs/diagrams/c3-components-<container>.puml` (one per significant container)
```

### `DECISIONS.md` — ADR structure

ADRs accumulate append-only inside `DECISIONS.md`. Reverting a decision adds a new ADR that
supersedes the old one (with a back-reference); the old one is never deleted or renumbered.

```markdown
## ADR-<NNNN>: <Short imperative title>

- **Status**: proposed | accepted | superseded by ADR-<NNNN> | deprecated
- **Date**: <YYYY-MM-DD>
- **Deciders**: <names or roles>

### Context

<2–5 sentences describing the situation that forced a decision. The trigger,
the constraints in play, the alternative if we did nothing.>

### Decision

<1–3 sentences stating the decision in imperative form. "We will use X."
If it's not decided, it doesn't go in DECISIONS.md yet.>

### Consequences

- **Positive**: <what gets easier>
- **Negative**: <what gets harder, what costs are accepted>
- **Neutral**: <what changes that isn't strictly better or worse>

### Alternatives considered

- **<Alternative>** — <one-line description>. Rejected because: <reason>.
- ...
```

ADRs are numbered sequentially from `ADR-0001`, never renumbered. Dates in ISO format
(`YYYY-MM-DD`). Alternatives must be real — "do nothing" is not an alternative; list two real
ones or more. Write an ADR for any non-default technology choice, any pattern with more than
one viable answer (e.g. CQRS vs CRUD for a context), a scaling/cost tradeoff, a security
tradeoff, or a vendor lock-in decision. Do **not** write one for a choice already mandated by
the guardrails (that's a constraint, not a decision) or a trivial, single-commit-reversible detail.

## Workflow

1. **Re-read the guardrails.** Every choice must comply. If something in the plan needs to
   deviate, that deviation is an ADR in `DECISIONS.md`.
2. **Draw the C4 L1 context diagram first** — actors and the system as one box. Forces clarity
   on integrations.
3. **Draw the C4 L2 container diagram.** Use Aspire's resource model as the starting point: the
   AppHost composes API, DB, cache, queue, vector store, plus each `Infrastructure.<Connector>`
   container that needs external connectivity.
4. **Name the projects.** One `Application.<BoundedContext>` per epic from the plan, following
   the naming conventions in the guardrails.
5. **Pin cross-cutting wiring.** Choose a single provider/library for each concern (OTel, MAF,
   RBAC, multi-tenancy, caching, background jobs, idempotency). Ambiguity here causes weeks of
   churn at build time. Reuse the stack skills (e.g. [`dotnet-aspire-base`](../dotnet-aspire-base/SKILL.md)
   for the backbone, [`agent-framework-csharp`](../agent-framework-csharp/SKILL.md) for MAF) — they encode the *how*.
6. **Decide cloud topology.** Regional layout, networking, managed identity, secret store, and
   observability sinks. Cloud-specific code stays behind `Infrastructure.<Cloud>` interfaces so
   a second cloud target is finite.
7. **Concretize the data model.** Turn the plan's entity sketch into EF Core entities with
   multi-tenancy applied. Mark PII fields with `[Pii]`.
8. **Concretize the API surface.** Minimal-APIs grouped by bounded context, all versioned
   (`/api/v1/...`), all returning Problem Details on error, idempotency keys on writes.
9. **Design the MAF agents.** At minimum the industry chatbot. Each agent's tools include the
   channels from installed connectors plus domain-specific actions. Persist conversations.
10. **Design the SPA.** Dashboard shell, chatbot slide-over panel, per-bounded-context feature folders.
11. **Write the ADRs** for every non-default decision, then refine and run the adversarial
    review under [Validation](#validation) before declaring the phase complete.

## How to reason

- **Pin a single provider per concern.** One choice each, written down. Ambiguity at this stage
  causes weeks of churn at build time.
- **Cloud-specific code stays partitioned.** `Infrastructure.<Cloud>` projects implement
  interfaces from `Infrastructure`; the rest of the system imports through the interface.
- **Boring technology when it fits.** Postgres, EF Core, Redis, Polly, OTel — boring is a
  feature when reliability matters.
- **Design for v1's metrics, not 10x.** Pick patterns that fit the *current* bounded context
  (CQRS may suit billing and be overkill for matters — choose per context). Refuse premature
  abstractions; three similar things is not a pattern.
- **No "TBD" without a date.** If a choice is genuinely deferred, write an ADR titled
  "TBD: choose X" with a resolution date. Most decisions are just "the default" — say so; ADRs
  are for the interesting ones.

## Traceability

Every downstream artifact cites its source by name so a reviewer can walk SPEC ↔ PLAN ↔ ARCH ↔
code in either direction:

- **Every module in the solution layout** ties back to the epic(s) it serves from `PLAN.md`.
- **Every ADR** cites the section of `ARCH.md` it affects.
- **Every cross-cutting wiring entry** names a concrete implementation for the corresponding
  guardrail requirement — no requirement silently unaddressed.

## Guardrails

Every choice complies with the enterprise guardrails below, or carries an ADR justifying the
deviation. The architecture's *Cross-cutting wiring* section must name a concrete implementation
for every item.

- **Identity & access** — AuthN via OIDC (Entra ID on Azure, Cognito on AWS); RBAC policies
  from PLAN mapped to policy classes; multi-tenancy at the data layer via EF Core query filters.
- **Observability** — OpenTelemetry via Aspire `ServiceDefaults`; health checks on every
  service; append-only audit logging for every domain mutation, stored outside the operational DB.
- **API surface** — URL-segment versioning; Problem Details (RFC 7807) on errors; idempotency
  keys on writes (24h replay); per-tenant + per-endpoint rate limiting; explicit CORS.
- **Resilience & runtime** — Polly handlers on outbound calls; Redis distributed cache; a single
  in-process background scheduler; outbox pattern for external side effects.
- **Configuration & secrets** — `IOptions<T>` validated at startup; secrets via the cloud secret store.
- **Compliance posture** — GDPR export endpoint and per-tenant deletion procedure; `[Pii]` tagging.

Technology constraints (not negotiable without an ADR):

- **Backend is .NET 10 + Aspire**; **frontend is Vite + React + TypeScript + shadcn/ui +
  Tailwind** (shadcn components are owned/copied, not imported); **agentic features use MAF** —
  no custom orchestration loops where MAF covers the case.
- **Default relational store is Postgres**; **default vector store is Postgres + pgvector**
  unless the connector list already brings something else (e.g. Azure AI Search).
- **Terraform is the IaC tool** (no Bicep, even on Azure); **GitHub Actions** for CI/CD.
- **One cloud per deployment, architecture stays cloud-agnostic.** Cloud-specific code lives
  behind interfaces in `Infrastructure.<Cloud>`.
- **Forms use shadcn `Form` + `react-hook-form` + `zod`; tables use TanStack Table** wrapped in
  a shared `DataTable`. The dashboard chrome (sidebar nav, top bar with tenant switch + user
  menu) is consistent across the family; the chatbot is always present as a slide-over panel.

Process rules:

- Never introduce a technology not listed above without an ADR.
- The architecture must be buildable in the recorded order — fix any circular dependency now.
- Diagrams are PlantUML or Mermaid, checked into `docs/diagrams/` so CI can render them.
- If the guardrails require something the plan didn't allow for (audit logging, idempotency
  keys), the architecture must add it. Plan and guardrails together define the surface — neither
  is optional.

## Validation

Before declaring the phase complete, switch from "produce" to "attack" mode and re-read the
architecture as a hostile reviewer. Find and fix (or surface) every instance of:

- **Missing pieces** — a cross-cutting requirement with no concrete wiring; a non-default choice
  with no ADR; an ADR with no real alternatives.
- **Internal inconsistencies** — a module in the layout that serves no epic; a connector with a
  container but no agent tool registration.
- **Hidden assumptions** — the topology assumes a single region but SPEC implies data residency
  needs. Confirm or document it.
- **Circular dependencies** — a build order that can't actually be built. Fix it now, not at build time.
- **Out-of-date references** — a renamed skill, a removed connector, a stale technology.

One structured pass, at most three refinement passes total. If it still doesn't pass, the input
(PLAN/SPEC) is likely the problem — surface that rather than polishing.

## Common Pitfalls

- **Introducing a technology the guardrails don't list, without an ADR.** Substituting a library
  is a decision, not an implementation detail.
- **Leaving cloud-specific code outside `Infrastructure.<Cloud>`.** It leaks the cloud into the
  rest of the system and turns a second target into a rewrite.
- **Skipping the ADR "for now."** "We'll document this decision sometime" is how undocumented
  decisions happen. Write it when you deviate.
- **Over-architecting.** Designing for 100x v1 or adding CQRS everywhere. Design for v1's metrics
  and choose patterns per bounded context.
- **Generating code.** That's `build-system`. This phase produces documents and diagrams only.

## Related skills

- [`plan-system`](../plan-system/SKILL.md) — produces the `PLAN.md` this skill consumes (the previous phase).
- [`build-system`](../build-system/SKILL.md) — reads `ARCH.md` (and the supporting docs) and generates the code (the next phase).
- [`dotnet-architecture`](../dotnet-architecture/SKILL.md) — the .NET/Azure realization of these docs: the architecture-style decision guide, layered solution skeleton, Terraform, and GitHub Actions. Owns the Clean Architecture / vertical-slice / microservices prose this skill links to instead of re-teaching.
- [`dotnet-aspire-base`](../dotnet-aspire-base/SKILL.md) — the stack skill that encodes the *how* for the concrete .NET 10 + Aspire solution backbone.
- [`pluggable-connectors`](../pluggable-connectors/SKILL.md) — the pattern for the connector registry and `IChannel` / `IIntegration` contracts referenced in the container diagram.
