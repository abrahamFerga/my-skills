---
name: build-system
description: >
  Generate code for a system from ARCH.md plus the stack and pattern skills — solution, projects,
  code, tests, IaC, and frontend, all consistent with the enterprise guardrails. The code-generation
  engine Stage 3 runs: a first invocation does the Foundations bootstrap (the whole backbone), and
  each later invocation implements the scope of one feature issue. Guardrail-checked at every
  checkpoint via build, test, and validate-system. It generates code for the scope it's handed;
  selecting the issue, branching, opening the PR, and moving the board are ../work-next-issue/SKILL.md's job.
  USE FOR: generating a system after design-architecture has produced ARCH.md and a clean validate
  pass; scaffolding the Aspire solution and per-context projects; wiring cross-cutting concerns
  (RBAC, multi-tenancy, OTel, idempotency, rate limiting) into endpoints; generating domain/
  application/API/EF/UI code and tests per epic; copying installed connectors into Infrastructure
  projects; producing README/OPERATIONS/SECURITY for the generated system.
  DO NOT USE FOR: planning the work or build order (use /system-definition:plan-system); making architecture
  or technology decisions (use /architecture:design-architecture); validating an already-built system
  (use /workflow-core:validate-system); installing the runtime verification surface (use
  ../verify-runtime/SKILL.md).
license: MIT
disable-model-invocation: true
---

# build-system

Stage 3's synthesis engine. Reads `ARCH.md` and produces working code — solution + projects +
code + tests + IaC + frontend, all consistent with the enterprise guardrails. Composes the stack
and pattern skills; does not invent new technology choices.

**Scope is one unit at a time.** The backlog is the worklist (GitHub `type:feature` issues marked
*Ready* by `/architecture:design-architecture`). The first time this runs against an empty repo it
performs the **Foundations bootstrap** below (the whole backbone, satisfying the Foundations
epic's issues). Every later invocation implements **one feature issue's scope** — the entities,
handlers, endpoints, migrations, tests, and UI for that one feature — then stops green. The loop
that picks the next Ready issue, creates the branch, opens the `Closes #N` PR, and moves the card
is [`work-next-issue`](../work-next-issue/SKILL.md); this skill just generates the code it's handed.

You operate here as a **senior implementation engineer**: methodical, test-first, and allergic
to clever code. Architecture is law — if `ARCH.md` says EF Core, you use EF Core; if it says
shadcn `Form`, you use shadcn `Form`. You wire cross-cutting concerns from day one, write tests
alongside the code, stop on red, and refuse to generate anything you can't justify against the
guardrails or an ADR. You generate files; you do not commit or push — the user reviews and commits.

## When to Use

- `ARCH.md` exists, `DECISIONS.md` is in place, and `/workflow-core:validate-system` passed cleanly.
- You need to scaffold the Aspire solution + ServiceDefaults + per-context projects.
- You need to generate an epic's domain entities, application handlers, API endpoints, EF
  migrations, tests, and UI screens — with cross-cutting concerns wired in.
- You need to copy installed connectors into `Infrastructure.<Connector>` projects.
- You need the system's `README.md`, `OPERATIONS.md`, and `SECURITY.md`.

## Stop Signals

- **Planning the work / build order** → use `/system-definition:plan-system`.
- **Making architecture or technology decisions** → use `/architecture:design-architecture`.
- **Validating an already-built system** → use `/workflow-core:validate-system`.
- **Installing the runtime test/verify surface** → use [`verify-runtime`](../verify-runtime/SKILL.md).
- **You can't justify a line against the guardrails or an ADR** → stop and surface the conflict; don't improvise.

## Inputs

| Input | Required | Description |
|---|---|---|
| `ARCH.md` | Yes | Produced by `/architecture:design-architecture`. The solution layout and cross-cutting wiring this skill executes. |
| Current feature issue | When driven by `work-next-issue` | The single `type:feature` issue being implemented — its title, body, acceptance criteria, and the Stage-2 architecture comment. Defines this invocation's scope. Absent only for the Foundations bootstrap. |
| `PLAN.md` | Yes | The epic/module narrative behind the issues; used to locate the feature's bounded context and build order. |
| `DECISIONS.md` | Always consulted | The ADRs that justify any non-default choice in `ARCH.md`. |
| `SPEC.md` | Always consulted | Capabilities and personas behind the architecture; source for `README.md`. |
| `workflow.json` | When present | Cloud target, declared connectors, capabilities, marketplaces. |
| Enterprise guardrails (below) | Yes | The cross-cutting contract every generated file is checked against. |

## Output

A buildable repo at the generated system's root. Concretely:

- `<System>.sln` + every `src/*.csproj` and `tests/*.csproj` listed in `ARCH.md`
- `src/<System>.AppHost/Program.cs` composing every Aspire resource
- `src/<System>.ServiceDefaults/` with OTel + health checks + resilience wired
- `src/<System>.Api/` with minimal-APIs grouped by bounded context, versioned, Problem-Details
  enabled, idempotency middleware in place
- `src/<System>.Application/` + `Application.<BoundedContext>/` per the plan
- `src/<System>.Domain/` with entities + value objects, `[Pii]` attribute applied
- `src/<System>.Infrastructure/` with EF Core + multi-tenancy query filters + outbox
- `src/<System>.Infrastructure.<Cloud>/` per the cloud target
- `src/<System>.Infrastructure.<Connector>/` per installed connector
- `src/<System>.Web/` — Vite + React + TypeScript + shadcn/ui + Tailwind, dashboard shell + chatbot panel
- `infra/<cloud>/` with Terraform modules
- `.github/workflows/` with build, test, deploy-staging, deploy-prod
- `tests/` with one test project per source project; integration tests use Testcontainers
- `README.md`, `OPERATIONS.md`, `SECURITY.md` for the generated system

## Workflow

Generation runs **one unit at a time** and after each unit the system must pass
`/workflow-core:validate-system` plus `dotnet build` + `dotnet test`. The Foundations bootstrap is
always first (it's what the Foundations epic's issues collectively require); after that, each
invocation implements a single *Ready* feature issue handed in by `work-next-issue`.

### Foundations bootstrap (first run, once)

The concrete skills this phase orchestrates are [`dotnet-aspire-base`](../dotnet-aspire-base/SKILL.md),
`/architecture:dotnet-architecture`,
[`pluggable-connectors`](../pluggable-connectors/SKILL.md), and
[`verify-runtime`](../verify-runtime/SKILL.md) — invoke each to install its surface. The remaining
foundational concerns (RBAC, multi-tenancy, the MAF agent host, the dashboard shell, the industry
chatbot, and cloud Terraform) are **patterns you apply inline** here, synthesized from the
enterprise guardrails; some are expected to graduate into dedicated sibling skills later, but until
they do, generate them directly rather than calling a skill that does not yet exist.

1. Invoke [`dotnet-aspire-base`](../dotnet-aspire-base/SKILL.md) to create the solution + base
   projects + ServiceDefaults wiring.
2. Follow `/architecture:dotnet-architecture` to lay out the domain /
   application / infrastructure layering the rest of the epic fills in.
3. Apply the **RBAC pattern** to install the role/policy/claim infrastructure (a future `rbac`
   skill; generate it inline for now from the guardrails).
4. Apply the **multi-tenancy pattern** to install the tenant context, EF query filters, and request
   middleware (a future `multi-tenant` skill; generate it inline for now).
5. Apply the **MAF agents pattern** to set up the MAF host + memory store + agent registration
   scaffold (generated inline from the MAF guardrails).
6. Invoke [`pluggable-connectors`](../pluggable-connectors/SKILL.md) to install the connector
   registry + `IChannel` / `IIntegration` contracts.
7. Apply the **dashboard-portal pattern** to scaffold the SPA shell with sidebar/topbar/tenant
   switch (a future `dashboard-portal` skill; generate it inline for now).
8. Apply the **industry-chatbot pattern** to add the chatbot panel + the MAF agent for the industry
   (a future `industry-chatbot` skill; generate it inline for now).
9. For the chosen cloud, apply the **cloud Terraform pattern** to scaffold IaC + the
   `Infrastructure.<Cloud>` project (a future `<cloud>-terraform` skill; generate it inline for now).
10. For each installed connector, copy `connectors/<name>/dotnet/` into
    `src/<System>.Infrastructure.<Name>/` and merge `connectors/<name>/infra/` into IaC.
11. Install the runtime verification surface via [`verify-runtime`](../verify-runtime/SKILL.md)
    (Aspire integration-test host, HTTP request catalog, agent-readable telemetry, Playwright E2E
    when there's a SPA).
12. Run `dotnet build` and `dotnet test`, then follow `/workflow-core:validate-system`.
    Fix any failures before moving on.

### Per feature issue (every subsequent run)

Given one *Ready* `type:feature` issue (title, body, acceptance criteria, Stage-2 architecture comment):

1. Read the issue and its architecture comment to fix the scope: the bounded context/module it
   belongs to (from `ARCH.md`/`PLAN.md`) and the acceptance criteria that define "done."
2. Choose the right stack/pattern skills for that scope (e.g. capability skills like `ocr`,
   `vector-db` if relevant).
3. Generate **only this feature's** domain entities + application handlers + API endpoints + EF
   migrations + tests + UI screens — with every cross-cutting concern wired in. Don't pull in
   scope from other issues.
4. Wire the feature into the dashboard navigation.
5. Run `dotnet build` + `dotnet test`, then follow `/workflow-core:validate-system`. Stop on red — the unit
   isn't done until green. (Confirm every acceptance criterion in the issue is met.)

`work-next-issue` then opens the PR (`Closes #N`) and advances the board. The system should be
landable as one PR per feature.

### Final pass (once the backlog is drained)

1. Generate `README.md` for the system from `SPEC.md` (one-sentence summary, jobs to be done,
   getting started, license).
2. Generate `OPERATIONS.md` documenting deployment, GDPR procedures (export + per-tenant
   deletion), incident playbook.
3. Generate `SECURITY.md` for the system with its own threat model + responsible disclosure.
4. Final `/workflow-core:validate-system`. Final `dotnet build --configuration
   Release` + `dotnet test`. Final `dotnet publish` smoke check.

## How to reason

- **Architecture is law.** `ARCH.md` says EF Core? Use EF Core. `ARCH.md` says shadcn `Form`?
  Use shadcn `Form`. Don't substitute. If you genuinely cannot follow the architecture, stop and
  open an ADR — don't improvise.
- **Compose, don't reinvent.** Stack skills that exist —
  [`dotnet-aspire-base`](../dotnet-aspire-base/SKILL.md) and
  `/architecture:dotnet-architecture` — encode the *how* per technology, and
  [`pluggable-connectors`](../pluggable-connectors/SKILL.md) encodes the connector pattern; invoke
  them rather than hand-rolling. The other cross-cutting concerns (RBAC, the MAF agent host,
  `dashboard-portal`, `industry-chatbot`) are patterns you synthesize inline from the guardrails
  today and that may become dedicated skills later — apply them consistently rather than improvising
  a new shape each time.
- **Allergic to clever code.** Boring, obvious code wins. If a junior engineer can't read it in
  two minutes, simplify. Don't add error handling for cases the framework guarantees won't happen.
- **Stop on red.** If `dotnet build` fails or a test fails, stop and fix it before the next module.
- **Generate, don't push.** Produce files; the user reviews and commits. This skill does not push or merge.

## Traceability

Every generated artifact cites its source so a reviewer can walk SPEC ↔ PLAN ↔ ARCH ↔ code:

- **Every generated source file** that implements a domain concept carries a single-line comment
  header naming the bounded context and the module from `ARCH.md`. (No multi-paragraph docstrings.)
- Test files trace via the file they test; infrastructure code (Terraform, CI) traces at the
  project level via `ARCH.md`; UI components in a feature folder inherit the parent module's traceability.

A reviewer who finds a suspicious line reads the file header → the module in `ARCH.md` → the epic
in `PLAN.md` → the capability in `SPEC.md`. If any link is missing, the line may be silent scope creep.

## Guardrails

Every generated file is checked against the enterprise guardrails below before the step is
declared done. A system that lacks any of these is not "enterprise-ready" and `/workflow-core:validate-system`
must fail. Refuse to generate code you cannot tie to a guardrail or an ADR.

- **Identity & access** — AuthN via OIDC (Entra ID on Azure, Cognito on AWS); RBAC roles in
  config bound to authorization policies referenced by policy name; multi-tenancy at the data
  layer (tenant id on every domain table, EF Core query filters, a resolved tenant context per request).
- **Observability** — OpenTelemetry via Aspire `ServiceDefaults` (no `Console.WriteLine` in
  service code — use `ILogger<T>`); `/health` + `/health/ready` on every service; append-only
  audit logging for every domain mutation (who/what/when/tenantId/before-after), stored outside
  the operational DB.
- **Verifiability** — an Aspire integration-test host (`Aspire.Hosting.Testing`) that boots the
  whole AppHost with real dependencies; a committed `http/*.http` request catalog carrying real
  cross-cutting headers (auth, tenant, `Idempotency-Key`) with secrets from env/user-secrets;
  agent-queryable OpenTelemetry; a Playwright E2E project when there's a SPA. Installed by
  [`verify-runtime`](../verify-runtime/SKILL.md).
- **API surface** — URL-segment versioning (`/api/v1/...`); Problem Details (RFC 7807) for all
  errors; idempotency keys on every non-GET write (24h replay window); per-tenant + per-endpoint
  rate limiting; explicit CORS (no production wildcards).
- **Resilience & runtime** — Polly resilience handlers on every outbound HTTP/SDK call; Redis
  distributed cache for session, idempotency replay, and rate-limit windows; a single in-process
  background scheduler, jobs tenant-aware and observable; outbox pattern for every external side
  effect (no fire-and-forget from request handlers).
- **Configuration & secrets** — `IOptions<T>` validated at startup (`ValidateOnStart` +
  data-annotation validators), no `IConfiguration["key"]` in business code; secrets via the cloud
  secret store, never `appsettings.json` or committed env files.
- **Compliance posture** — a `/api/v1/tenants/{tenantId}/export` endpoint (GDPR Article 20); a
  documented per-tenant deletion procedure in `OPERATIONS.md` (GDPR Article 17, hard delete
  preferred); `[Pii]` attribute on PII fields, flowing through audit logging and export.

Process rules:

- **One epic at a time.** Never start epic N+1 until epic N is green. The user should be able to
  land a PR per epic.
- **No technology improvisation.** If `ARCH.md` says EF Core, do not use Dapper. If it says
  shadcn `Form`, do not switch to react-final-form. Deviations require an ADR update.
- **No skipping cross-cutting requirements.** Every endpoint has its idempotency key, rate limit,
  problem-details handling, audit-log hook, and tenant filter. If you can't fit them in, the
  architecture is wrong, not the rule.
- **Tests live alongside the code that needs them.** Domain → unit tests; Application → use-case
  tests with in-memory infrastructure; API → integration tests with Testcontainers (real Postgres,
  real Redis, real OTel collector).
- **No commits from this skill.** Generate the files; the user reviews and commits.
- **Refuse code you cannot justify** against the guardrails. If something looks reasonable but you
  can't tie it to a guardrail or an ADR, stop and ask.

Forbidden moves (the guardrails' "must NOT" list): inventing a template folder to copy from
(synthesize from skills + guardrails); introducing a stack not listed without a recorded
`DECISIONS.md` entry; writing to `appsettings.json` what belongs in the secret store; vendoring
external skills by copying them in (declare via marketplaces); generating code you cannot explain.

## Validation — when to stop

Stop and consider the system green only when all of the following hold:

- The unit just built (the Foundations bootstrap, or this feature issue's scope) is generated and green, with every acceptance criterion in the issue met.
- `/workflow-core:validate-system` exits 0.
- `dotnet build --configuration Release` is clean.
- `dotnet test` all passing.
- `npm run build` in `src/<System>.Web/` succeeds.

If any of those fail and you cannot resolve them in two attempts, stop and surface the failure to
the user with a concrete description of the conflict — often a guardrail rule the architecture
didn't account for, an ADR that should be written, or a missing skill that needs to be authored
first. Do not iterate blindly past two attempts.

## Common Pitfalls

- **Starting epic N+1 with epic N red.** The whole point is a landable PR per epic; never move on
  with the build or tests failing.
- **Substituting a library "because it's easier."** That's a decision needing an ADR, not an
  implementation detail.
- **Wiring cross-cutting concerns "later."** Idempotency, rate limit, problem-details, audit hook,
  tenant filter go in with the endpoint, not in a follow-up pass.
- **Committing or pushing.** This skill stops at generated files. The user reviews and commits.
- **Writing secrets into `appsettings.json`** or committing env files. Secrets come from the cloud secret store.
- **`Console.WriteLine` in service code.** Use `ILogger<T>` so telemetry stays agent-queryable.

## Related skills

This is the code-generation engine of Stage 3, driven per issue by
[`work-next-issue`](../work-next-issue/SKILL.md). The loop continues until the backlog is drained;
new scope re-enters upstream (update `SPEC.md` → `/system-definition:plan-system` →
`/system-definition:sync-backlog` → `/architecture:design-architecture`).

- [`work-next-issue`](../work-next-issue/SKILL.md) — the Stage-3 loop that selects the Ready issue, branches, calls this engine, opens the PR, and moves the board. **Load when:** driving development off the backlog.
- `/architecture:design-architecture` — produces the `ARCH.md` this skill consumes and the Ready issues it implements (the previous phase).
- `/workflow-core:validate-system` — the guardrail check run at every epic checkpoint and the final pass.
- [`verify-runtime`](../verify-runtime/SKILL.md) — installs the integration/E2E/telemetry surface this skill relies on for "the AI ran it and proved it works."
- [`dotnet-aspire-base`](../dotnet-aspire-base/SKILL.md) — the stack skill that creates the solution base and ServiceDefaults wiring.
- `/architecture:dotnet-architecture` — the stack skill that lays out the domain / application / infrastructure layering this skill fills in.
- [`pluggable-connectors`](../pluggable-connectors/SKILL.md) — the connector registry and `IChannel` / `IIntegration` contracts installed in Foundations.
