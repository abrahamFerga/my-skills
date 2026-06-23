---
name: work-next-issue
description: >
  Drive Stage 3 off the GitHub backlog, one issue at a time. Pick the highest-priority Ready
  feature from the project board (Foundations first by Build order), move it to In Progress,
  branch, implement it with build-system, run build/test/validate, then open a PR that closes
  the issue and move the card to In Review. The development loop that turns the architected
  backlog into merged PRs without ever holding more than one feature in flight.
  USE FOR: implementing the next feature off the board; running the per-issue branch -> code ->
  PR loop; resuming development after a PR merges.
  DO NOT USE FOR: generating the code itself (that engine is ../build-system/SKILL.md, which this
  calls); designing architecture or moving Backlog -> Ready (use /architecture:design-architecture);
  publishing the backlog (use /system-definition:sync-backlog).
license: MIT
disable-model-invocation: true
---

# work-next-issue

The Stage-3 loop. The backlog board is the worklist; this skill takes the next **Ready** feature,
implements it on its own branch via [`build-system`](../build-system/SKILL.md), and lands it as a
PR that closes the issue — then stops, one feature in flight at a time. Re-invoke (or run on a
loop) to take the next one. It owns *selection, branching, the PR, and the board*; it delegates
*code generation* to `build-system` and *runtime proof* to [`verify-runtime`](../verify-runtime/SKILL.md).

## When to Use

- Architecture is done (features are *Ready* on the board) and you want to implement the next one.
- A PR just merged and you want to pull the next feature.
- You want a tight, reviewable cadence: one issue → one branch → one PR.

## Stop Signals

- **No `workflow.json.github` / empty board** → the backlog isn't published; use `/system-definition:sync-backlog`.
- **Nothing in Ready** → architecture hasn't marked features Ready; use `/architecture:design-architecture`.
- **Generating code or scaffolding** → that's [`build-system`](../build-system/SKILL.md); this skill calls it.
- **Working tree dirty / mid-merge** → stop; never start a new feature on top of uncommitted work.

## Inputs

| Input | Required | Description |
|---|---|---|
| `workflow.json` | Yes | The `github` block (`repo`, `project`) — the repo and board to drive. |
| Project board | Yes | Source of the next item: the `Ready` column, ordered by `Build order` then `priority`. |
| `ARCH.md` / `PLAN.md` / `SPEC.md` | Yes | Passed through to `build-system` as the design context for the selected feature. |

## Workflow (one issue per run)

1. **Preflight.** Confirm `gh auth status` (with `project` scope) and a **clean working tree** on
   the default branch (`git status --porcelain` empty; not mid-merge/rebase). Read `workflow.json.github`
   for `REPO` and `PROJECT`. If the repo has no solution yet, the selected work is the **Foundations
   bootstrap** (see step 3).
2. **Select the next issue.** From the board, take the `Ready` feature with the lowest `Build order`
   (ties broken by `priority` p0>p1>p2). Foundations features sort first because `sync-backlog` gave
   them the lowest build orders. If `Ready` is empty, stop with the design-architecture pointer.
3. **Claim it.** Move the card `Ready → In Progress`. Create a branch `feat/<issue#>-<slug>` off the
   default branch. (First run with no solution: do the Foundations bootstrap via `build-system`,
   which satisfies the whole Foundations epic; close/advance those Foundations issues together.)
4. **Implement.** Invoke [`build-system`](../build-system/SKILL.md) with the selected issue as scope
   (title, body, acceptance criteria, and the Stage-2 architecture comment). It generates only this
   feature's entities/handlers/endpoints/migrations/tests/UI with cross-cutting concerns wired in.
5. **Prove it.** Run `dotnet build` + `dotnet test` + `/workflow-core:validate-system`; use
   [`verify-runtime`](../verify-runtime/SKILL.md) to exercise it at runtime when the feature has a
   reachable surface. Every acceptance criterion in the issue must hold. Stop on red — fix before the PR.
6. **Land it.** Commit (message referencing the issue), push the branch, and open a PR with
   `Closes #<issue#>` in the body. Move the card `In Progress → In Review`.
7. **Report and stop.** Print the issue, branch, PR url, and checks status. Do **not** start the next
   issue — one feature in flight. (When run under `/loop`, the next invocation picks up after this
   PR merges and the board auto-archives the card.)

## gh / git commands (inlined; self-contained)

```bash
OWNER=abrahamFerga; REPO=$OWNER/<name>; PROJECT=<n>
PID=$(gh project view "$PROJECT" --owner @me --format json --jq '.id')
gh project field-list "$PROJECT" --owner @me --format json   # -> Pipeline field id + option ids

# next Ready feature, lowest Build order (inspect item-list JSON; fields carry Pipeline + Build order)
gh project item-list "$PROJECT" --owner @me --format json

# claim: Ready -> In Progress
gh project item-edit --id <item-id> --project-id "$PID" --field-id <pipeline-fid> --single-select-option-id <in-progress-oid>

# branch, implement (build-system), verify, then:
git switch -c feat/<issue#>-<slug>
git add -A && git commit -m "feat: <title> (#<issue#>)"
git push -u origin feat/<issue#>-<slug>
gh pr create -R "$REPO" --fill --body "Closes #<issue#>"

# In Progress -> In Review
gh project item-edit --id <item-id> --project-id "$PID" --field-id <pipeline-fid> --single-select-option-id <in-review-oid>
```

On merge, `Closes #<n>` closes the issue and the board's built-in *closed → Done* workflow archives
the card. If that automation is off, move it explicitly to the `Done` option.

## Guardrails

- **One feature in flight.** Never branch a second feature before the current PR is open. Keeps every
  change reviewable and the board honest.
- **Clean base only.** Refuse to start on a dirty tree or detached/mid-merge state — surface it instead.
- **Green before PR.** No PR until `build` + `test` + `validate-system` pass and the issue's acceptance
  criteria are met. A red branch is not "In Review."
- **Scope discipline.** Implement only the selected issue. If the work reveals missing scope, file/adjust
  an issue (or send it back to `sync-backlog`) rather than silently widening the PR.
- **Outward actions are visible.** Pushing a branch and opening a PR are public on a public repo —
  proceed when the user is driving the loop, but never force-push the default branch or merge without review.
- **No secrets in commits/PRs.** The secret scan applies to committed files and PR bodies alike.

## Common Pitfalls

- **Starting the next issue automatically** — stop after each PR; the loop resumes on the next invocation.
- **Forgetting `Closes #N`** — without it the issue stays open and the card never reaches Done.
- **Leaving the card in In Progress** after opening the PR — always advance to In Review.
- **Selecting by creation order instead of `Build order`** — Foundations and priority ordering live in the board field, not the issue number.

## Related skills

- [`build-system`](../build-system/SKILL.md) — the code-generation engine this loop calls per issue. **Load when:** implementing the selected feature.
- [`verify-runtime`](../verify-runtime/SKILL.md) — runtime exercise/debug loop used to prove a feature before the PR. **Load when:** the feature has a reachable surface.
- `/workflow-core:validate-system` — the guardrail check run before every PR.
- `/architecture:design-architecture` — fills the `Ready` column this loop drains. **Load when:** Ready is empty.
- `/system-definition:sync-backlog` — publishes the backlog this loop consumes. **Load when:** the board is empty.
