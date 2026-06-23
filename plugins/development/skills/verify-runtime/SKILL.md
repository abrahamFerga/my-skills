---
name: verify-runtime
description: >
  Make a generated .NET 10 + Aspire system testable by an AI at runtime, and drive the
  run -> exercise -> observe -> debug -> fix -> lock-in loop. Installs the verification
  infrastructure (Aspire integration-test host, committed `.http` request catalog,
  agent-readable OpenTelemetry via the Aspire MCP/CLI, and a Playwright E2E project when
  there's a SPA), then uses it to reproduce behaviour, debug from telemetry, and guard the
  fix with a regression test that fails without it.
  USE FOR: asking the AI to run/debug/exercise a generated system, call its API, or drive its
  UI — proving an implementation actually works, not just that it compiles; standing up the
  verification harness for a new system; producing a deterministic reproduction plus a
  regression test before a bug is considered fixed.
  DO NOT USE FOR: static config checks of workflow/settings files (use /workflow-core:validate-system);
  generating feature code (use ../build-system/SKILL.md); setting up the .NET + Aspire backbone
  itself (use ../dotnet-aspire-base/SKILL.md — this skill drives that backbone, it doesn't create it).
license: MIT
disable-model-invocation: true
---

# verify-runtime

The **runtime, behavioural** counterpart to static validation. Static validation answers "is this system *described* consistently?" (config and settings checks). `verify-runtime` answers "does this system *actually work* when it runs?" — and it makes the system AI-verifiable in the first place.

The stack is .NET 10 + Aspire + MAF, mostly APIs and sometimes a Vite/React SPA. Two things make such a system AI-verifiable: it already emits **OpenTelemetry** through `ServiceDefaults` (a backbone requirement — see [../dotnet-aspire-base/SKILL.md](../dotnet-aspire-base/SKILL.md)), and **Aspire ships an MCP server + CLI built for AI coding agents** that exposes that telemetry as structured, queryable data. This skill installs the rest of the harness and defines the loop that uses it.

## Approach

Work as a senior verification engineer: telemetry-first, reproduce-before-fix, skeptical of "it should work." A green build and a plausible diff are not proof — you run the system, drive it the way a client would, and read the telemetry to confirm what actually happened. If you can't observe it, you don't believe it. Reproduce a bug deterministically *before* investigating it. Read OTel (`aspire otel traces/logs`, the Aspire MCP tools, the dashboard) instead of adding print statements — the observability you need is already flowing. Form one hypothesis, make the smallest change, re-run the *exact same* reproduction. Keep the cross-cutting contract on while testing. Stop on red. Produce verified behaviour and tests; the user reviews and commits.

## When to use

- The user asks the AI to **run, debug, or exercise** a generated system ("call the API and check X", "the endpoint returns 500 — find out why", "drive the dashboard and confirm the flow works").
- A new system needs its **verification infrastructure** stood up (after each epic — "prove the epic works", not just "it builds").
- A bug needs a **deterministic reproduction + a regression test** before it's considered fixed.

## When NOT to use

- Static validation of workflow/settings config → use `/workflow-core:validate-system`. A system that isn't statically valid isn't worth running.
- Generating feature code → use [`build-system`](../build-system/SKILL.md).
- Standing up the .NET + Aspire backbone (solution, projects, ServiceDefaults) → use [../dotnet-aspire-base/SKILL.md](../dotnet-aspire-base/SKILL.md). This skill *drives* that backbone, it doesn't create it.

---

## Part A — The infrastructure this pattern installs

A generated system is "AI-testable" when an agent can, without human help: boot it to a known-good state, exercise every endpoint and screen deterministically, and read what happened. Install these.

### 1. Aspire integration-test host — `tests/The<Domain>.IntegrationTests`

The canonical way to test a distributed .NET app. Add the `Aspire.Hosting.Testing` package and boot the whole AppHost — real Postgres, real Redis, real service discovery, real connection strings (Aspire injects them; never hand-roll). This supersedes a bare `WebApplicationFactory` for anything that crosses a service or touches persistence.

```csharp
// Start the AppHost once per test collection (xUnit collection fixture).
public sealed class AppHostFixture : IAsyncLifetime
{
    public DistributedApplication App { get; private set; } = null!;

    public async Task InitializeAsync()
    {
        var builder = await DistributedApplicationTestingBuilder
            .CreateAsync<Projects.The<Domain>_AppHost>();
        builder.Services.ConfigureHttpClientDefaults(http => http.AddStandardResilienceHandler());

        App = await builder.BuildAsync();
        await App.StartAsync();

        // StartAsync does NOT wait for readiness — wait explicitly.
        await App.ResourceNotifications
            .WaitForResourceAsync("api", KnownResourceStates.Running)
            .WaitAsync(TimeSpan.FromSeconds(60));
    }

    public async Task DisposeAsync() => await App.DisposeAsync();
}

// In a test: drive the API through the Aspire-named resource.
var client = App.CreateHttpClient("api");
var res = await client.GetAsync("/health");
```

Guidance baked in: start the AppHost **once per collection** (not per test); configure log filters so infrastructure chatter doesn't drown the output; inject the `StandardResilienceHandler` on the test client; assert cross-service wiring (e.g. the web resource's env vars resolve to the API URL — the thing `WebApplicationFactory` can't see).

### 2. HTTP request catalog — committed `http/*.http`

One `.http` file per bounded context, one request per endpoint, checked into the repo. Each request carries the cross-cutting headers a real call needs so the AI exercises the system honestly:

```http
@host = https://localhost:7443
@token = {{$dotenv TOKEN}}        # test OIDC token, from env — never inline a real one

### Create order (idempotent, authed)
POST {{host}}/api/v1/orders
Authorization: Bearer {{token}}
Idempotency-Key: {{$guid}}
Content-Type: application/json

{ "sku": "ABC-123", "qty": 2 }
```

This is the deterministic, reviewable way to hit the API; it complements the OpenAPI/Scalar surface the API already exposes. Secrets live in env / user-secrets, never in the file.

### 3. Agent-readable telemetry — wire the Aspire MCP/CLI

The system already exports OTel via `ServiceDefaults`. Make it queryable by the agent:

- `aspire agent init` — configures MCP integration for the AppHost (one-time, in the generated repo).
- `aspire agent mcp --dashboard-url "http://localhost:18888"` — starts the MCP server for a standalone dashboard.

Then the agent reads runtime state with (all support `--format Json` for parseable output):

| Need | CLI | MCP tool |
|---|---|---|
| Resource status / health | `aspire describe` | `list_resources` |
| Wait for healthy | `aspire wait` | — |
| Structured logs (filter by resource) | `aspire otel logs` | `list_structured_logs` |
| Distributed traces | `aspire otel traces` | `list_traces` |
| Individual spans | `aspire otel spans` | — |
| Console output | `aspire logs` | `list_console_logs` |

Fallback when the CLI isn't wired: the dashboard exposes `GET /api/telemetry/resources` and `/api/telemetry/logs` (OTLP JSON).

### 4. UI E2E — `tests/The<Domain>.E2E` (only when the system has a SPA)

Use `Microsoft.Playwright` for repeatable, committed E2E. Optionally generate Playwright Agents (`npx playwright init-agents --loop=claude`) which produce `specs/` (Markdown test plans), `tests/` (generated specs), and `tests/seed.spec.ts` (a ready `page` fixture) — driven by a Planner, Generator, and Healer. **Handle the OIDC login wall with `storageState`:** authenticate once in a setup project against a test identity, persist the session, and reuse it so tests don't re-auth (and don't burn tokens) on every run. During an interactive session the agent can also drive the SPA live via the browser MCP / Playwright MCP for exploration — but anything worth keeping becomes a committed E2E test.

### 5. CI wiring

A `test` job in `.github/workflows/` runs `dotnet test` (integration tests spin up their containers via Aspire) and the Playwright E2E headless. This is what turns "verified once locally" into "stays verified."

### 6. One-command-to-running helper — `scripts/run-and-wait.{ps1,sh}`

A thin wrapper: `aspire run` (or `dotnet run --project src/The<Domain>.AppHost`) → `aspire wait` → print the dashboard URL and the API base URL. Gives the agent a single command to reach a known-good running state instead of guessing ports and readiness.

---

## Part B — The debug / test loop

The loop is **bounded** (a few iterations, not infinite polishing) and **closed out adversarially** (you attack your own result before declaring done).

1. **Baseline green.** Boot the system (`scripts/run-and-wait` or `aspire run`), `aspire wait` until resources are healthy. Confirm `dotnet build` and the existing `dotnet test` are green *before* you change anything — otherwise you can't attribute what you observe.
2. **Reproduce deterministically.** Trigger the target behaviour through the right surface: a `.http` request (API), an integration test (cross-service), or a Playwright step (UI). **Capture the trace ID** from the response (or the failing test's logs).
3. **Observe via telemetry, not guesswork.** Follow the trace ID: `aspire otel traces --format Json`, then `aspire otel logs --format Json` filtered to the failing resource. Check `aspire describe` for any unhealthy dependency. Tie the symptom back to the span/log/line and, where relevant, to the architecture behaviour it violates — every observation should trace to evidence, not a hunch.
4. **One hypothesis, smallest change.** Form a single evidence-backed explanation; make the minimal fix.
5. **Confirm against the same reproduction.** Re-run the *exact* step from (2). Confirm via telemetry the symptom is gone — a green status code is the headline, the trace is the proof.
6. **Lock it in.** Add a regression test at the right layer (Domain unit / Application use-case / API integration via the Aspire host / UI E2E). The test must respect the cross-cutting contract (auth on, tenant context set, idempotency key present).
7. **Adversarial close-out.** Verify the new test **fails without the fix** (revert, watch it go red, re-apply). Check you didn't regress a sibling endpoint or tenant — the same latent bug often lives in a neighbour. Only then declare it done. One structured close-out pass; don't invent problems on a second.

### Worked example (a real 500)

A compact walk-through of the loop on a concrete defect — the point is that *telemetry, not guesswork, drives the fix*.

**Symptom:** "Creating an order sometimes returns 500."

1. **Baseline green** — `scripts/run-and-wait.ps1` prints the dashboard + API URLs; `aspire describe --format Json` shows all resources Running/Healthy; `dotnet test` is green, so new observations are attributable.
2. **Reproduce** — send the committed `.http` `POST /api/v1/orders` (auth header, `X-Tenant-Id`, `Idempotency-Key`). It returns `500`, and the response `traceparent` yields a trace id, e.g. `3a5f9c1d…`.
3. **Observe** — `aspire otel traces --format Json | jq 'select(.traceId=="3a5f9c1d…")'` shows the span chain `POST /api/v1/orders` → `outbox.enqueue` → `db.exec status=ERROR`. `aspire otel logs --format Json --resource api` filtered to that trace shows `23502: null value in column "tenant_id" violates not-null constraint`. `aspire describe` shows the DB healthy — so it's not infrastructure. The failure localises to the **outbox enqueue**: the request's `ITenantContext` resolves, but the outbox writer isn't stamping the tenant id.
4. **Hypothesis + smallest change** — `OutboxWriter` doesn't set `TenantId` from `ITenantContext`. Fix: stamp `TenantId` on the outbox message in the writer (one line), where every other domain write already does.
5. **Confirm** — re-send the **identical** request → `201 Created`; the new trace's `outbox.enqueue` span is OK and the row carries the tenant id. Green status is the headline; the clean trace is the proof.
6. **Lock it in** — add an API integration test (boots the AppHost, contract on) that creates an order and asserts the outbox row carries the tenant id — the layer where the bug actually lived.
7. **Adversarial close-out** — revert the one-line fix → the new test goes red (it guards *this* bug) → re-apply → green. Check siblings: do the other writers stamp the tenant id? If a neighbour had the same latent bug, fix and cover it in the same pass.

**Evidence note handed back:** trace `3a5f9…` → outbox enqueue wrote a null `tenant_id`; `OutboxWriter` now stamps `ITenantContext.TenantId`; guarded by `OrdersApiTests.Create_order_stamps_tenant_on_outbox`; same latent bug checked in sibling writers.

## Choosing the right tool

| Symptom | Verify with | Why |
|---|---|---|
| Pure logic / calculation bug | Domain or Application **unit test**, no host | Fastest; no I/O involved |
| Cross-service, persistence, DI, config-binding bug | **Aspire integration test** (real containers) | These only surface when the real app boots |
| "Is the running system behaving right now?" | `aspire run` + `.http` catalog + `aspire otel …` | Exploratory, interactive |
| UI / interaction / auth-flow bug | **Playwright E2E** (repeatable) or **browser MCP** (exploratory) | Real DOM + real session |
| Latency / throughput / N+1 | **traces + metrics** via dashboard / MCP | The trace shows where the time goes |

## Guardrails

- **Telemetry-first debugging.** Read OTel via the Aspire CLI/MCP or dashboard. **Never** add `Console.WriteLine` or leave temporary log spam — use `ILogger<T>` + OTel, and the data you need is already flowing.
- **Never weaken the security contract to test.** Do not disable auth/OIDC, drop the tenant filter, bypass RBAC policies, or turn off rate limiting to make something pass. Use a **test OIDC token** and a **test tenant**. If a behaviour can only be verified with the contract off, the design is wrong — surface it, don't disable it.
- **No secrets in `.http` files or test config.** Tokens and connection strings come from env / user-secrets / the cloud secret store. Secret-detection rules still apply to anything you write.
- **Deterministic and isolated.** Real dependencies via Aspire/Testcontainers, never a shared cloud environment. Each test owns its tenant and data. No `Thread.Sleep` — wait on `WaitForResourceAsync` / Playwright auto-waiting.
- **Never commit `storageState` with a real token.** Generate it in a fixture from a test identity; keep it out of git.
- **Integration tests boot the whole app via the AppHost.** Let Aspire inject connection strings and service-discovery URLs; do not hand-roll them or point tests at a long-lived shared database.
- **Idempotent loop.** Re-running the verification leaves the same final state; clean up resources you create.

## Related skills

- [../dotnet-aspire-base/SKILL.md](../dotnet-aspire-base/SKILL.md) — creates the `ServiceDefaults`/OTel wiring and the test-project layout this skill drives.
- [../pluggable-connectors/SKILL.md](../pluggable-connectors/SKILL.md) — connector webhook endpoints and health are among the surfaces this skill exercises.
- `/workflow-core:validate-system` is the static counterpart (config, secrets, settings sync) — run it before `verify-runtime`. [`build-system`](../build-system/SKILL.md) invokes `verify-runtime` after each epic to prove the epic works at runtime, not just that it compiles. A react-vite-shadcn / dashboard-portal skill produces the SPA the Playwright E2E / browser MCP exercises.
