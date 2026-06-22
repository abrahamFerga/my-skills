# Architecture Styles — Decision Guide

This is the "which shape" reference. The skill's lead recommendation is a
**modular monolith built with Clean Architecture layering**. Everything below
helps you confirm that, or justify deviating from it.

## TL;DR decision

```
Start here ──► Modular monolith + Clean Architecture (single App Service deployable)
   │
   ├─ Need independent scaling / independent deploy cadence per capability,
   │  and you have the platform maturity (observability, CI/CD, on-call)?
   │      └─► Split the noisiest module into its own service. Keep the rest a monolith.
   │
   ├─ Team is small (1–6 devs) / product is pre-PMF / domain still churning?
   │      └─► Stay a monolith. Microservices now is premature distribution.
   │
   └─ Hard regulatory/tenancy isolation, or org boundaries map to services?
          └─► Service-per-bounded-context may be justified from day one.
```

> Distribution is a cost you pay in network failure modes, eventual consistency,
> and operational overhead. Buy it only when a concrete force (scale, deploy
> independence, team autonomy, isolation) requires it.

## The styles

### Modular monolith (default)

One process, one deployable, partitioned into **modules** that map to bounded
contexts. Modules talk through in-process interfaces, not HTTP. Each module owns
its data (logically — separate schemas, no cross-module table joins).

- **Pros:** simple deploy, in-process calls (no network), one transaction
  boundary available when you need it, trivial local debugging, cheap to run.
- **Cons:** one scaling unit; a runaway module can starve others; discipline is
  required to keep module boundaries from eroding.
- **Keep boundaries honest:** no project reference from module A's internals to
  module B's internals; communicate via published contracts or domain events.

### Clean Architecture (the layering *inside* the monolith)

Concentric layers with an **inward-only dependency rule**:

```
        ┌─────────────────────────────────────┐
        │  Api (host, endpoints, DI root)      │  ← frameworks, I/O
        │   ┌─────────────────────────────┐    │
        │   │ Infrastructure (EF, clients)│    │  ← adapters implement ports
        │   │   ┌─────────────────────┐   │    │
        │   │   │ Application (use    │   │    │  ← orchestration, ports
        │   │   │ cases, ports/CQRS)  │   │    │
        │   │   │   ┌─────────────┐   │   │    │
        │   │   │   │  Domain     │   │   │    │  ← entities, rules; ZERO deps
        │   │   │   └─────────────┘   │   │    │
        │   │   └─────────────────────┘   │    │
        │   └─────────────────────────────┘    │
        └─────────────────────────────────────┘
```

- **Domain** depends on nothing. Pure business model.
- **Application** depends on Domain; defines **ports** (interfaces) it needs.
- **Infrastructure** depends on Application; provides **adapters** (EF Core
  repositories, message bus, HTTP clients) implementing those ports.
- **Api** depends on Infrastructure + Application; it is the **composition root**
  that wires DI and exposes the API. The only project that touches the outside.

This is the layout the [solution skeleton](solution-structure.md) generates.

### Vertical slice architecture

Organize by **feature** (a folder per use case containing its request, handler,
validation, and data access) rather than by technical layer. Often combined with
a thin mediator. Great when the app is a collection of mostly-independent
endpoints and the per-layer ceremony of Clean Architecture feels heavy.

- **Use when:** CRUD-heavy or feature-additive apps; you want each change
  localized to one folder; minimal shared domain logic.
- **Tradeoff:** less enforced central domain model; cross-cutting rules can get
  duplicated across slices. The two combine well — Clean layering for the core
  domain, vertical slices for the application/use-case layer.

### Microservices

Independently deployable services, each owning its data and exposed over the
network. Choose **per service** whether it warrants its own database, pipeline,
and scaling policy.

- **Use when:** distinct scaling profiles, independent deploy cadence, team-per-
  service autonomy, or strong isolation requirements — AND you already have the
  platform (centralized logging/tracing, automated CD, contract testing, on-call).
- **Don't use when:** you're adopting it to "do it right" without a forcing
  function. The default path is *modular monolith first, extract later*.

### Domain-Driven Design (DDD) building blocks

DDD is orthogonal to the styles above — it informs how you model, at any scale.

| Block | What it is |
|-------|-----------|
| **Entity** | Identity-bearing object; equality by id, not value. |
| **Value object** | Immutable, equality by value (e.g. `Money`, `Address`). |
| **Aggregate** | Consistency boundary; an **aggregate root** is the only entry point; invariants hold within it. |
| **Domain event** | A fact that happened ("OrderPlaced"); decouples side effects. |
| **Repository** | Collection-like abstraction over aggregate persistence (a *port*). |
| **Domain service** | Stateless domain operation that doesn't belong to one entity. |
| **Bounded context** | A boundary within which a model and its language are consistent. Maps to a *module* (monolith) or a *service* (distributed). |

Use **strategic DDD** (context mapping, ubiquitous language) to find module/service
seams; use **tactical DDD** (the blocks above) to model inside a context. You do
not need full DDD for CRUD; reach for aggregates where invariants are real.

## When to split a module into a service

Split when a **specific, measured** force appears — not on a hunch:

- The module needs a **different scaling profile** (e.g. a CPU-bound report
  generator vs. a chatty CRUD API).
- It needs an **independent deploy cadence** and the shared release train blocks it.
- A **separate team** owns it and coordination cost is high.
- **Isolation** (security, tenancy, compliance) requires a process/data boundary.

Pre-work before extracting: the module already has a clean public contract, owns
its own schema, and has no in-process transactions spanning the boundary. If those
aren't true, fix them *inside the monolith first* — that work is the actual hard
part, and it's reversible while still in-process.

## Mapping styles to Azure compute

| Style | Default Azure target | Notes |
|-------|---------------------|-------|
| Modular monolith | **App Service (Linux)** | This skill's scaffold. |
| A few services | Azure Container Apps | Managed Kubernetes-less containers, scale-to-zero, Dapr optional. |
| Many services / platform team | AKS | Only with the ops maturity to run it. |
| Event/HTTP-triggered functions | Azure Functions | Glue, scheduled jobs, lightweight APIs. |

See [azure-targets.md](azure-targets.md) for the full compute + data + supporting-
services selection matrix.
