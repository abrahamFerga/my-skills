---
name: work-next-issue
description: >
  Drive Stage 3 off the GitHub backlog, one issue at a time, by orchestrating three subagents:
  backlog-manager selects the highest-priority Ready feature and branches, feature-builder
  implements its scope, runtime-verifier proves it works end to end, and backlog-manager lands it as
  a Closes #N PR and moves the board. Never holds more than one feature in flight. USE FOR:
  implementing the next feature off the board; running the per-issue select → build → verify → PR
  loop; resuming development after a PR merges. DO NOT USE FOR: generating the code yourself (the
  feature-builder agent does that); designing architecture or moving Backlog → Ready (use
  /architecture:design-architecture); publishing the backlog (use /system-definition:sync-backlog).
license: MIT
disable-model-invocation: true
---

# work-next-issue

The Stage-3 loop body. It is a **conductor**, not a worker: it takes the next **Ready** feature and
moves it through four hand-offs to three specialized subagents, landing it as a PR that closes the
issue — then stops, one feature in flight. Re-invoke (or run under `/loop`, or let
`build-generated-system` drive it) to take the next one.

```
backlog-manager(select+claim) → feature-builder(implement) → runtime-verifier(prove) → backlog-manager(land)
        pick + branch                generate code               run + observe              commit + PR + board
```

Each subagent works in its **own context** and reads the project state itself; the conductor just
sequences them, gates on each result, and enforces the autonomy policy. The agents share the one
working tree on the feature branch, so the builder's code is what the verifier runs and the
backlog-manager commits.

## When to Use

- Architecture is done (features are *Ready* on the board) and you want to implement the next one.
- A PR just merged and you want to pull the next feature.
- You want a tight, reviewable cadence: one issue → one branch → one PR.

## Stop Signals

- **No `workflow.json.github` / empty board** → the backlog isn't published; use `/system-definition:sync-backlog`.
- **Nothing in Ready** → architecture hasn't marked features Ready; use `/architecture:design-architecture`.
- **Working tree dirty / mid-merge** → stop; never start a new feature on top of uncommitted work.
- **You're about to write code or run gh yourself** → don't; that's the agents' job. This skill only sequences them.

## Inputs

| Input | Required | Description |
|---|---|---|
| `workflow.json` | Yes | The `github` block (repo, board) and `goal.autonomy` (latitude for the land step). |
| Project board | Yes | Source of the next item: the `Ready` column, ordered by `Build order` then `priority`. |
| `ARCH.md` / `PLAN.md` / `SPEC.md` | Yes | The design context each agent reads for the selected feature. |

## Autonomy

Read `goal.autonomy` (default `confirm`). It governs the **land** step's outward actions (first push,
PR, board move): `manual` → stop after verify and report the branch as ready-to-land; `confirm` →
pause for a yes before the first push of the project and before the PR; `auto` → land without
pausing. The workflow-core git-safety hook still blocks force-pushing the default branch and merging
under `manual`/`confirm`.

## Workflow (one issue per run)

1. **Preflight.** Confirm a **clean working tree** on the default branch (`git status --porcelain`
   empty; not mid-merge/rebase) and `gh auth status` with the `project` scope. On a dirty tree, stop
   and surface it — never start on top of uncommitted work.
2. **Select + claim.** Spawn the **backlog-manager** subagent (Agent tool, `subagent_type:
   backlog-manager`) with job `select` then `claim`: pick the lowest-`Build order` Ready feature
   (Foundations first; ties by priority p0>p1>p2), move it `Ready → In Progress`, and branch
   `feat/<issue#>-<slug>` off a clean default branch. It returns the issue (number, title, slug,
   acceptance criteria, architecture note) and the branch. If it reports `drained`, stop with the
   design-architecture pointer. **First run on an empty repo:** the unit is the *Foundations
   bootstrap* on branch `feat/foundations`.
3. **Implement.** Spawn the **feature-builder** subagent with the selected issue as scope (title,
   body, acceptance criteria, architecture comment — or "Foundations bootstrap"). It generates only
   that unit's code with cross-cutting concerns wired in and stops green (build + test + validate).
   It returns the green/red status and which acceptance criteria it believes are met.
4. **Prove.** Spawn the **runtime-verifier** subagent with the issue's acceptance criteria. It boots
   the system, exercises the real surface, reads telemetry, and returns `verified` or `failed` with
   evidence. **If the builder was red or the verifier failed:** hand the concrete failure back to a
   fresh **feature-builder** to fix, then re-verify. After **two** failed build→verify cycles on the
   same issue, stop and surface the conflict (architecture or a skill is wrong) — do not loop.
5. **Land.** Per the autonomy policy, spawn the **backlog-manager** subagent with job `land`: commit
   the working tree, push the branch, open a PR with `Closes #<issue#>`, and move the card
   `In Progress → In Review`. It secret-scans the diff and PR body first.
6. **Report and stop.** Print the issue, branch, PR url, the verifier's verdict, and checks status.
   Do **not** start the next issue — one feature in flight. (Under `/loop` or `auto`, the next pass
   picks up after this PR merges and the board auto-archives the card.)

## Guardrails

- **Conductor, not worker.** You spawn agents and gate on results; you do not write code, run the
  build, or call `gh`/`git` yourself. If you're reaching for Edit or a `gh` command, delegate instead.
- **One feature in flight.** Never let backlog-manager claim a second feature before the current PR
  is open. Keeps every change reviewable and the board honest.
- **Green before land.** No PR until feature-builder is green **and** runtime-verifier returns
  `verified` against the issue's acceptance criteria. A red branch is not "In Review."
- **Two-cycle cap.** Two failed build→verify cycles on one issue → stop and surface. Don't grind.
- **Scope discipline.** Implement only the selected issue. Missing scope → file/adjust an issue (or
  send it back to `sync-backlog`), don't silently widen the PR.
- **Outward actions respect autonomy.** The land step obeys `goal.autonomy`; force-pushing the
  default branch and merging without review are blocked by the workflow-core hook regardless.

## Common Pitfalls

- **Doing the agents' work inline** — the point is context isolation; sequence the agents, don't
  inline build/verify/gh into the conductor's context.
- **Starting the next issue automatically** — stop after each PR; the loop resumes on the next pass.
- **Landing on a builder-green-but-verifier-failed branch** — runtime proof gates the PR, not just compilation.
- **Selecting by issue number instead of `Build order`** — Foundations and priority ordering live in the board field.

## Related skills

- **feature-builder** / **runtime-verifier** (development agents) and **backlog-manager** (workflow-core agent) — the three workers this skill sequences. Spawn via the Agent tool.
- [`build-system`](../build-system/SKILL.md) — the code-generation engine the feature-builder agent runs. **Load when:** you need to understand or change what the builder generates.
- [`verify-runtime`](../verify-runtime/SKILL.md) — the run/observe loop the runtime-verifier agent runs. **Load when:** changing how features are proven.
- `/architecture:design-architecture` — fills the `Ready` column this loop drains. **Load when:** Ready is empty.
- `/system-definition:sync-backlog` — publishes the backlog this loop consumes. **Load when:** the board is empty.
