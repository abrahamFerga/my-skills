---
name: plan-system
description: >
  Read SPEC.md and produce an actionable PLAN.md — epics in build order, a module
  list mapped to .NET projects, the refined RBAC policy model, the integration
  surface, a conceptual data-model sketch, background-work inventory, and open
  questions for the architecture phase. Phase 3 of the workflow: turns the *what*
  into a *how, in what order* that design-architecture and build-system execute against.
  USE FOR: planning a generated system after the spec is written; grouping capabilities
  into epics; defining build order; refining roles into action-noun policies; mapping
  declared connectors to webhook routes and per-tenant config; inventorying background jobs.
  DO NOT USE FOR: writing the spec itself (use ../synthesize-spec/SKILL.md); making concrete
  technology choices, C4 diagrams, or solution layout (use ../design-architecture/SKILL.md);
  generating code (use ../build-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# plan-system

Phase 3 of the workflow. Translates the *what* (from `SPEC.md`) into a *how, in what
order*. Produces a `PLAN.md` that [`design-architecture`](../design-architecture/SKILL.md) turns into concrete architectural
decisions and that [`build-system`](../build-system/SKILL.md) executes against.

You operate here as a **staff-level system architect**: pragmatic, decisive, and willing
to write things down. You think in bounded contexts before .NET projects, you make
Foundations epic 1 every time, and you design for the smallest scale that meets v1's
success metrics — not 10x, not 100x. Boring technology is a feature when reliability
matters; the interesting decisions get deferred to [`design-architecture`](../design-architecture/SKILL.md).

## When to Use

- The spec (`SPEC.md`) is written and you need a build sequence before designing the architecture.
- You need to group capabilities into epics and order them so each builds on the previous.
- You need to refine the spec's roles into a concrete RBAC policy model.
- You need to map declared connectors to an integration surface (direction, routes, per-tenant config).
- You need to inventory background jobs and flag which require the outbox pattern.

## Stop Signals

- **Writing the spec itself** → use [`synthesize-spec`](../synthesize-spec/SKILL.md).
- **Choosing concrete technologies, drawing C4 diagrams, or laying out projects** → use [`design-architecture`](../design-architecture/SKILL.md).
- **Generating source code** → use [`build-system`](../build-system/SKILL.md).

## Inputs

| Input | Required | Description |
|---|---|---|
| `SPEC.md` | Yes | Produced by [`synthesize-spec`](../synthesize-spec/SKILL.md). The capabilities, personas, and success metrics being planned. |
| `workflow.json` | When present | Cloud target, declared connectors, capabilities, and skill marketplaces. |
| Enterprise guardrails (below) | Yes | The cross-cutting requirements every generated system must include. The plan is consulted against them as a constraint set. |

## Output

A single `PLAN.md` at the generated system's root. This is the authoritative structure —
follow it exactly.

```markdown
# <System name> — Plan

## Epics (in build order)

1. **Foundations** — auth, multi-tenancy, observability, RBAC scaffold, dashboard shell,
   chatbot panel, connector registry. Always epic 1; pulled from the enterprise guardrails.
2. **<Epic name>** — what it delivers. Capabilities (from SPEC): <list of capabilities from SPEC>.
   Depends on: <other epics>.
3. ...

## Module list

| Module (.NET project name) | Bounded context | Capabilities served | Skills used to build it |
|---|---|---|---|
| `The<Domain>.Application.Foundations` | foundations | (cross-cutting) | dotnet-aspire-base, rbac, multi-tenant |
| `The<Domain>.Application.<Context>` | <context> | <capability, capability> | <stack/pattern skills> |
| ... | | | |

## Data model sketch

Entities and key relationships at the conceptual level. Schemas come from
[`design-architecture`](../design-architecture/SKILL.md) — don't write them here.

- **<Entity>** — fields, key relationships, multi-tenancy boundary, audit/PII flags.
- ...

## RBAC model (refined)

| Role | Policies | Notes |
|---|---|---|
| <Role> | `<Module>.<Action>`, ... | <constraints> |

Policy names use `<Module>.<Action>` form (e.g. `Matters.View`, `Billing.Charge`).
Code references the policy name, not the role.

## Integration surface

| Connector | Direction | Purpose | Webhook routes | Per-tenant config |
|---|---|---|---|---|
| <name> | inbound \| outbound | <one-line> | `/api/connectors/<name>/webhook/...` | <fields> |

## Background work

| Job | Trigger | Cadence | Outbox required? |
|---|---|---|---|
| <name> | reactive \| scheduled \| long-running | <interval or event> | yes \| no |

## Open questions for design-architecture

1. <Question>
2. ...
```

## Workflow

1. **Group capabilities into epics.** An epic delivers one or more capabilities end-to-end.
   Order them so each builds on the previous. Always include "Foundations" as epic 1 (auth,
   multi-tenancy, observability — these are global from the guardrails). Differentiators go
   last so they slip without blocking v1.
2. **Sketch the module list.** For each capability cluster, identify the .NET project it'll
   live in (e.g. `The<Domain>.Application.Matters`, `The<Domain>.Application.Billing`). One
   module per bounded context — group capabilities into bounded contexts first, then map.
3. **Draft the data model.** List entities, key relationships, where multi-tenancy fits.
   Don't write schemas yet — that's [`design-architecture`](../design-architecture/SKILL.md)'s job. Do mark which fields are PII.
4. **Refine the RBAC model** from SPEC into policy names. Use action-noun policies
   (`Matters.View`, `Matters.Edit`, `Billing.Charge`). Roles bind to policies; code
   references policies, not roles.
5. **Map declared connectors to the integration surface.** For each connector in
   `workflow.json`, identify direction (inbound webhook vs outbound), purpose (notify-only
   vs action), and routes consumed.
6. **Identify background jobs.** Anything reactive (notify on event), scheduled (nightly
   export), or long-running (data sync). Mark which require the outbox pattern.
7. **Surface open questions** that [`design-architecture`](../design-architecture/SKILL.md) needs answered — usually scale
   numbers (tenants/day, requests/second), regional needs, or specific external-system protocols.
8. **Refine, then attack.** Make at most three refinement passes (stop earlier once the plan
   passes every check below), then run the adversarial review under [Validation](#validation)
   before declaring the phase complete.

## How to reason

- **Bounded contexts first.** Group capabilities into bounded contexts before mapping to
  .NET projects. Each bounded context owns its data and its language.
- **Pin the build order, not the tech.** This phase decides *what gets built and in what
  order*. Specific provider/library choices are [`design-architecture`](../design-architecture/SKILL.md)'s job; don't pre-empt them.
- **Design for v1's metrics.** Not 10x v1, not 100x. The smallest scale that meets the
  success metrics in `SPEC.md`. Resist anticipating problems the system doesn't have yet.
- **Refuse premature abstraction.** Three similar things is not a pattern. Five is.
- **No "TBD" without a date.** If a choice is genuinely deferred, say so explicitly as an
  open question for [`design-architecture`](../design-architecture/SKILL.md), not as a silent gap.

## Traceability

Every downstream artifact cites its source by name, so a reviewer can walk the chain
SPEC ↔ PLAN ↔ ARCH ↔ code in either direction:

- **Every epic** lists the SPEC capabilities it delivers (the *Capabilities (from SPEC)*
  clause in the Epics list).
- **Every module** lists the bounded context and the capabilities it serves (columns in the
  Module list table).
- **Every must-have / differentiator capability from SPEC** appears in exactly one epic.
  None silently dropped, none invented.

If any link in the chain is missing, traceability is broken and a piece of scope may have
drifted in or out unnoticed.

## Guardrails

The plan is checked against the enterprise guardrails below before it's declared done. These
are the cross-cutting requirements every generated system must include from day one — the
contract for "enterprise-ready." The Foundations epic exists to deliver all of them.

- **Identity & access** — AuthN via OIDC (Entra ID on Azure, Cognito on AWS); RBAC with
  industry-appropriate roles in config (not hardcoded), bound to ASP.NET Core authorization
  policies referenced by policy name; multi-tenancy at the data layer (tenant id on every
  domain table, enforced via EF Core query filters; every request carries a resolved tenant context).
- **Observability** — OpenTelemetry via Aspire `ServiceDefaults` (traces, metrics, logs);
  health checks on every service; append-only audit logging for every domain mutation
  (who/what/when/tenantId/before-after), stored outside the operational DB.
- **API surface** — versioning via URL segment (`/api/v1/...`); Problem Details (RFC 7807)
  for errors; idempotency keys on all non-GET writes (24h replay window); rate limiting per
  tenant + per endpoint; explicit CORS (no production wildcards).
- **Resilience & runtime** — Polly resilience handlers on outbound calls; distributed cache
  (Redis) for session, idempotency replay, and rate-limit windows; a single in-process
  background scheduler; outbox pattern for any external side effect (no fire-and-forget from handlers).
- **Configuration & secrets** — `IOptions<T>` validated at startup; secrets via the cloud
  secret store, never `appsettings.json`.
- **Compliance posture** — GDPR data-export endpoint and per-tenant deletion procedure;
  PII fields tagged with a `[Pii]` attribute that flows through audit logging and export.

Process rules that follow from the above:

- Build order matters: Foundations epic first, then capabilities, then differentiators.
- One epic at a time in [`build-system`](../build-system/SKILL.md) — never start epic N+1 before epic N's tests pass.
- Modules map to .NET projects, not to UI screens. UI organization is [`design-architecture`](../design-architecture/SKILL.md)'s concern.
- The plan must not contradict the guardrails. If it must deviate, surface the conflict and
  record it as an ADR in `DECISIONS.md` (written during [`design-architecture`](../design-architecture/SKILL.md)) — never deviate silently.

## Validation

Before declaring the phase complete, switch from "produce" to "attack" mode and re-read the
plan as a hostile reviewer. Find and fix (or surface as an open question) every instance of:

- **Missing pieces** — an epic without a build-order rationale; a capability that maps to no module.
- **Internal inconsistencies** — SPEC says the system serves attorneys but the RBAC model has
  no `attorney`-shaped role; a connector declared in `workflow.json` with no row in the
  integration surface.
- **Hidden assumptions** — the plan assumes a single region but SPEC says nothing about data
  residency. Confirm it or move it to *Open questions*.
- **Optimistic counts** — "5 must-haves" when a careful read of the differentiators says 7.
- **Out-of-date references** — a connector or skill that's been renamed or removed.

One structured pass. Then confirm: Foundations is epic 1, and every must-have capability from
SPEC appears in at least one epic. Stop iterating after three refinement passes total — if it
still doesn't pass, the input (SPEC) is likely bad; surface that to the user rather than polishing.

## Common Pitfalls

- **Writing schemas in the data-model sketch.** Stay conceptual — entities and relationships,
  not column types or migrations. Schemas are [`design-architecture`](../design-architecture/SKILL.md)'s output.
- **Mapping modules to UI screens.** Modules are .NET projects per bounded context; the SPA's
  organization is decided later.
- **Pre-choosing technologies.** "Use Hangfire" is an architecture decision with an ADR, not a
  plan entry. The plan says *there is background work*; the architecture says *what runs it*.
- **Dropping a differentiator quietly.** Every SPEC capability lands in exactly one epic, even
  if it's last.

## Related skills

- [`synthesize-spec`](../synthesize-spec/SKILL.md) — produces the `SPEC.md` this skill consumes (the previous phase).
- [`design-architecture`](../design-architecture/SKILL.md) — reads `PLAN.md` and produces `ARCH.md` plus C4 diagrams (the next phase).
- [`build-system`](../build-system/SKILL.md) — walks the *Epics (in build order)* table during code generation.
