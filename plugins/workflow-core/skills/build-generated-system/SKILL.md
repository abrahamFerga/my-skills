---
name: build-generated-system
description: >
  Parameterless conductor for the full GitHub-native build pipeline — bootstrap+repo → research →
  spec → plan → publish backlog → compose → architect → develop (issue by issue) → validate. Takes
  no required arguments: it infers the current phase from the project folder (workflow.json,
  research/, SPEC.md, PLAN.md, ARCH.md) and the GitHub board, then advances the first unmet phase by
  delegating it to a focused subagent and gating on that phase's exit condition. Built to run under
  `/loop` and `/goal`. Run this from inside a project to drive or resume a complete build. DO NOT
  USE FOR a single phase (invoke that phase's skill/agent directly) or exploration without a build
  (use ../research-only/SKILL.md).
license: MIT
disable-model-invocation: true
---

# build-generated-system

The conductor for a full build. It generates nothing itself — it **reads where the project is**,
advances the **one** phase that isn't done yet, delegates the real work to a specialized subagent,
enforces that phase's exit condition, and yields. The project folder and GitHub **are** the state;
there is nothing to pass in.

## Parameterless by design

There are **no required inputs**. Run it from inside the project (or its parent) and it figures out
the rest:

- **Resuming an existing project** (the normal case — the folder already has `workflow.json` and
  some of `research/`, `SPEC.md`, `PLAN.md`, `ARCH.md`): it reads `name`, `industry`, `stage`, and
  `github` straight from `workflow.json`. **Pass nothing.**
- **Bootstrapping a brand-new project** (no `workflow.json` anywhere up the tree): it needs one
  seed — an industry word or a goal. It takes that, in order, from: an argument if you typed one →
  `goal.objective` (set via [`/workflow-core:goal`](../goal/SKILL.md)) → a single question. The
  project name defaults to `the-<industry>`.

Optional overrides still work when you want them: `cloud` (azure/aws/none), `connectors`,
`external_marketplaces`, an explicit `project_name`/`target_path`. Everything else is inferred. The
old required `industry` + `target_path` arguments are gone.

## How it advances (one phase per pass)

Each pass: **re-read the state** (which artifacts/issues exist), find the **first phase whose exit
condition isn't met**, advance **that one phase** (in Phase 8, one *feature*), enforce its exit
condition, then **yield** so a loop can continue. Completed phases short-circuit, so re-entry is
cheap and idempotent. This shape is what makes it safe under:

- **`/loop /workflow-core:build-generated-system`** — self-paced; you stay in the driver's seat (Esc to stop).
- **`/goal … auto` + the loop hook** — the workflow-core Stop hook re-drives it automatically until `stop_when`.

It **stops and reports** (never spins) for a genuine human decision: unanswered research questions,
a guardrail conflict, or — under `autonomy: confirm` — an outward action awaiting a yes.

## Autonomy

Read `goal.autonomy` from `workflow.json` (default `confirm` when no `goal` block):

| `autonomy` | Outward/irreversible actions (first push, PRs, board moves, merges) |
|---|---|
| `manual` | not taken — produce local artifacts and report what's ready to do |
| `confirm` *(default)* | taken, but pause for a yes before each one |
| `auto` | taken without pausing; only a real blocker or `stop_when` ends the run |

The git-safety guard (workflow-core hook) still blocks force-pushing the default branch and merging
PRs under `manual`/`confirm` regardless — autonomy raises latitude, it does not remove the rails.

## Delegation model

Heavy and specialized phases run in their **own subagent** (a fresh context that reads the project
state itself and returns only a summary — this is what keeps the conductor's context clean and the
agents autonomous). Light one-time glue (init, spec, plan, publish, compose, validate) the conductor
runs **inline** by reading that skill's `SKILL.md` and following it — those skills are
`disable-model-invocation`, so the Skill tool can't fire them; the conductor composes them by
reference. Spawn each agent with the **Agent tool** (`subagent_type: <name>`); build mode keeps every stage
plugin enabled for the whole run, so every phase's agent is reachable throughout (see *Stage plugins*).

| Phase | Runs as | Exit condition (what "done" looks like) |
|---|---|---|
| 1 Bootstrap + repo | inline `init-system` | `workflow.json` + `.claude/settings.json` valid; repo + board exist (or `github:null` with a clear reason) |
| 2 Research | agent **industry-researcher** | `research/<industry>.md` conforms; no unanswered questions |
| 3 Spec | inline `synthesize-spec` | `SPEC.md` conforms; no unanswered questions |
| 4 Plan | inline `plan-system` | `PLAN.md`: Foundations is epic 1; every must-have maps to an epic |
| 5 Publish backlog | inline `sync-backlog` | every epic+feature is an issue (no dupes), sub-issues linked, features in **Backlog** with Build order; then advance the `stage` marker to `architecture` |
| 6 Compose | inline `manage-workflow` / `manage-skills` | cloud/connectors/capabilities/marketplaces applied; both files valid |
| 7 Architect | agent **system-architect** | `ARCH.md` + C4 + an ADR per non-default choice; every feature **Ready** (or a recorded reason) |
| 8 Develop (loop) | `/development:work-next-issue` → agents **feature-builder** → **runtime-verifier** → **backlog-manager** | every feature implemented, verified, and landed as an open `Closes #N` PR in **In Review**, build/test/validate green (merge → Done needs repo auto-merge or a human) |
| 9 Validate & verify | inline `validate-system` + agent **runtime-verifier** | all static checks OK; runtime behavior verified |

## Stage plugins for a full run

The pipeline spans all three stages. A full run uses **build mode** — enable every stage plugin up
front (below) so every phase's agent is reachable, and keep them enabled for the whole run:

```json
// .claude/settings.json  → then /reload-plugins
{ "enabledPlugins": {
  "workflow-core@my-skills": true, "system-definition@my-skills": true,
  "architecture@my-skills": true, "development@my-skills": true } }
```

`workflow-core` is always on. The `/reload-plugins` above loads every phase's agent once; **keep all
four enabled for the whole run**. The conductor does **not** narrow stages mid-run: a re-enabled
plugin's agents don't load without another `/reload-plugins`, which nothing can type in a hands-off
loop — so narrowing-then-re-enabling would strand the next phase's agent (this is the trap that
breaks `autonomy: auto`). Instead it advances only the `stage` **marker** for orientation
(`/workflow-core:manage-workflow set stage …`, with **no** `manage-skills sync`); `validate-system`
tolerates this build-mode superset (all four enabled while `stage` reads a single phase). The **one**
narrowing happens at the end (Phase 9), as the handoff to ongoing development.

## Pipeline

Run phases in order; never skip or reorder. Each is idempotent — if its exit artifact already
exists and is valid, short-circuit and move on. After Phase 1, everything operates under the project
root and GitHub is the system-of-record.

### Phase 1 — Bootstrap + repo (inline)

If a valid `workflow.json` already exists, skip. Otherwise follow [`init-system`](../init-system/SKILL.md)
with the resolved name + industry (see *Parameterless by design*). It writes the two config files
and stands up the **public repo, label taxonomy, and Projects v2 board**, recording them in
`workflow.json.github`.

### Phase 2 — Research (agent)

Delegate to **industry-researcher**: "You are in `<project>`. Produce/validate `research/<industry>.md`
per your skill; surface any open questions." If it returns unanswered questions, **stop** and have
the user answer them in place before continuing.

### Phase 3 — Spec (inline)

Follow the **synthesize-spec** skill (`/system-definition:synthesize-spec`). Stop on unanswered open questions.

### Phase 4 — Plan (inline)

Follow the **plan-system** skill (`/system-definition:plan-system`).

### Phase 5 — Publish backlog (inline; closes Stage 1)

Follow the **sync-backlog** skill (`/system-definition:sync-backlog`) to project `PLAN.md`
into epic/feature issues on the board. Then advance the `stage` marker (`set stage architecture`, **no** `manage-skills sync` — build mode keeps all four enabled).

### Phase 6 — Compose (inline)

Apply composition via [`manage-workflow`](../manage-workflow/SKILL.md) + [`manage-skills`](../manage-skills/SKILL.md):
set cloud (or ask under `confirm`), add connectors, add capabilities, declare external marketplaces.

### Phase 7 — Architect (agent)

Delegate to **system-architect**: "You are in `<project>`. Produce `ARCH.md` + C4 + `DECISIONS.md`
from the backlog and mark each feature Ready per your skill." Then advance the `stage` marker
(`set stage development`, **no** `manage-skills sync`).

### Phase 8 — Develop, issue by issue (loop)

Drive the **work-next-issue** skill (`/development:work-next-issue`) until the board's
`Ready` column is empty. Each pass it delegates the implementation to **feature-builder**, the E2E
proof to **runtime-verifier**, and the branch/commit/PR/board moves to **backlog-manager** —
Foundations first, one feature in flight, each landing as an open `Closes #N` PR in **In Review** —
the agent-reachable terminal state (reaching merged/Done needs repo auto-merge or a human). Under
`confirm`, pause before the first push of the project and before each PR; under `auto`, proceed.

### Phase 9 — Validate & verify

Follow [`validate-system`](../validate-system/SKILL.md) for the static checks (it tolerates the
build-mode superset — all four plugins enabled while `stage` reads one phase), then a final
**runtime-verifier** pass to prove the whole system works at runtime.

When the build is done and the user turns to ongoing feature work, **narrow to the development
stage**: `/workflow-core:manage-skills sync` (with `stage: development`) drops the stage-1/2 plugins
and `/reload-plugins` applies it. This is the single, end-of-build narrowing — safe because it
happens once, between sessions, not mid-loop.

## When to stop early

- Phase 2 can't find ~5 credible players → the industry may be too narrow; discuss.
- Phase 5 finds a SPEC capability with no home in PLAN → fix the plan before publishing.
- Phase 7 hits a fundamental guardrail conflict → the architect writes the ADR before continuing.
- Phase 8 fails the same feature the same way twice → architecture or a skill is wrong; surface it, don't loop.

## Guardrails

This is a workflow, not a magic box. The human keeps every decision; the conductor enforces order,
handoff artifacts, and the autonomy policy. Pausing is fine — re-invoke to resume (completed phases
short-circuit). GitHub is part of the pipeline: Phase 1 first-pushes the repo and Phase 8 pushes a
branch + opens a PR per feature. Under `confirm`, confirm the first push of a new project; never
force-push the default branch or merge a PR without review (the workflow-core hook enforces both).

## Related skills

- [`goal`](../goal/SKILL.md) — sets the objective + autonomy this conductor reads. **Load when:** configuring a hands-off run.
- [`research-only`](../research-only/SKILL.md) — the no-build exploration variant.
- Each phase's agent (`industry-researcher`, `system-architect`, `feature-builder`, `runtime-verifier`, `backlog-manager`) and inline skill linked in the table above.
