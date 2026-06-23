---
name: build-generated-system
description: >
  Orchestrator that drives the full GitHub-native system-building pipeline end to end —
  bootstrap+repo → research → spec → plan → publish backlog → compose → architect →
  develop (issue by issue) → validate — invoking the right stage skill at each phase
  and gating on each phase's exit condition. GitHub is the system-of-record: the repo,
  the issue backlog, and the project board are created and driven along the way. Run this
  when the user wants a complete new system built from an industry name. DO NOT USE FOR a
  single phase (invoke that phase's skill directly) or for exploration without committing
  to a build (use ../research-only/SKILL.md).
license: MIT
disable-model-invocation: true
---

# build-generated-system

The conductor for a full build. It does not generate anything itself — it runs
each phase's skill in the right order, enforces the handoff artifact at every
step, and stops when a phase needs a human decision. This is the answer to "how
does the agent know what to run, and in what order."

## Inputs

- **project_name** (required) — kebab-case, must start with `the-` (e.g. `the-lawyer`).
- **industry** (required) — short lowercase phrase (e.g. `legal`, `healthcare`).
- **target_path** (optional) — parent dir for the project. Default: cwd.
- **cloud** (optional) — `azure` / `aws` / `none`. Asked at compose if unset.
- **connectors** (optional) — comma-separated kebab names.
- **external_marketplaces** (optional) — e.g. `dotnet/skills@dotnet`.

## Stage plugins for a full run

This pipeline spans all three stages, so for a full build enable every stage
plugin up front, then narrow to `development` once the system exists:

```json
// .claude/settings.json  → then run /reload-plugins
{
  "enabledPlugins": {
    "workflow-core@my-skills": true,
    "system-definition@my-skills": true,
    "architecture@my-skills": true,
    "development@my-skills": true
  }
}
```

`workflow-core` (this skill's home) is always on. The pipeline flips the active
stage plugin as it advances (Phase 5 → `architecture`, Phase 7 → `development`) via
`/workflow-core:manage-workflow set stage …` + `/workflow-core:manage-skills sync`,
so each stage runs with only its tooling loaded — [`../manage-skills/SKILL.md`](../manage-skills/SKILL.md)
derives the `enabledPlugins` map from the `workflow.json` `stage` field. Enabling all
four up front (above) is only to bootstrap the very first run.

## Pipeline

Run phases in order. Do not skip or reorder. Each phase is idempotent: if the
expected artifact (or GitHub object) already exists and is valid, short-circuit and
move on. After a successful Phase 1, all later skills operate under
`<target_path>/<project_name>`, and GitHub is the system-of-record from then on.

### Phase 1 — Bootstrap + repo (Stage 1)

Run `/workflow-core:init-system` ([skill](../init-system/SKILL.md)) with the
project name, industry, and `target_path`. Besides the two config files, this
creates the **public GitHub repo, the label taxonomy, and the Projects v2 backlog
board**, and records them in `workflow.json.github`.
**Exit:** `workflow.json` + `.claude/settings.json` exist and validate; the repo +
board exist (or `github: null` with a clear warning if the user chose `--no-github`
or `gh` is unavailable).

### Phase 2 — Research (Stage 1)

Run `/system-definition:research-industry` for the industry.
If the artifact's *Open questions* are non-empty, **stop** and have the user
answer them in-place before continuing.
**Exit:** `research/<industry>.md` exists, conforms, no unanswered questions.

### Phase 3 — Spec (Stage 1)

Run `/system-definition:synthesize-spec`.
**Exit:** `SPEC.md` exists, conforms, no unanswered open questions.

### Phase 4 — Plan (Stage 1)

Run `/system-definition:plan-system`.
**Exit:** `PLAN.md` exists, Foundations is epic 1, every must-have capability
maps to an epic.

### Phase 5 — Publish backlog (closes Stage 1)

Run `/system-definition:sync-backlog`. Projects `PLAN.md` into GitHub: epics →
`type:epic` issues, the capabilities each delivers → `type:feature` sub-issues, all
placed on the board in **Backlog** with their `Build order`.
**Exit:** every epic + feature from `PLAN.md` exists as an issue (no duplicates), sub-issues
linked, features on the board in Backlog. Then advance the stage:
`/workflow-core:manage-workflow set stage architecture` + `/workflow-core:manage-skills sync`.

### Phase 6 — Compose

Apply composition to `workflow.json` + `.claude/settings.json` with
`/workflow-core:manage-workflow` ([skill](../manage-workflow/SKILL.md)) and
`/workflow-core:manage-skills` ([skill](../manage-skills/SKILL.md)):

1. Set cloud (`{{cloud}}`, or ask: azure/aws/none).
2. Add each connector in `{{connectors}}`.
3. Add capabilities the user wants now.
4. Declare each external marketplace in `{{external_marketplaces}}`.

**Exit:** `workflow.json` reflects the choices; `.claude/settings.json` synced; both validate.

### Phase 7 — Architect (Stage 2)

Run `/architecture:design-architecture`. It **reads the feature issues** from the
board, produces `ARCH.md` + C4 diagrams + `DECISIONS.md`, and moves each architected
feature **Backlog → Ready** with an architecture note as an issue comment. For the
concrete .NET/Azure realization (solution skeleton + Terraform + GitHub Actions) it
hands off to `/architecture:dotnet-architecture`.
**Exit:** `ARCH.md` complete, C4 diagrams checked in, an ADR for every non-default
choice, and every open `type:feature` issue is **Ready** (or has a recorded reason it
isn't). Then advance: `set stage development` + `manage-skills sync`.

### Phase 8 — Develop, issue by issue (Stage 3)

Drive `/development:work-next-issue` in a loop until the board's `Ready` column is
empty. Each pass takes the next Ready feature (Foundations first by `Build order`),
branches, implements it via `/development:build-system`, runs build/test/validate +
`/development:verify-runtime`, opens a PR (`Closes #N`), and moves the card to
**In Review**. One feature in flight at a time; merge advances it to Done.
**Exit:** every feature issue closed via a merged PR; board drained to Done;
`dotnet build -c Release` clean, `dotnet test` passing, validate exits 0.

### Phase 9 — Validate & verify

Run `/workflow-core:validate-system` ([skill](../validate-system/SKILL.md)) for the
static checks (including the `github` reachability check), then a final
`/development:verify-runtime` pass to prove the whole system works at runtime.
**Exit:** all checks `OK`; runtime behavior verified.

## When to stop early

- Phase 2 can't find ~5 credible players → the industry may be too narrow; discuss.
- Phase 5 finds a capability in `SPEC.md` with no home in `PLAN.md` → fix the plan before publishing.
- Phase 7 hits a fundamental conflict with the architecture guardrails → write the ADR before continuing.
- Phase 8 fails the same feature the same way twice → architecture or a skill is wrong; surface it, don't loop.

## Guardrails

This is a workflow, not a magic box. The user keeps every decision; the
orchestrator only enforces order and handoff artifacts. Pausing is fine —
re-invoke to resume (completed phases short-circuit). GitHub is now part of the
pipeline: Phase 1 creates and first-pushes the repo, and Phase 8 pushes a branch +
opens a PR per feature. These are visible, outward actions on a public repo —
confirm with the user before the first push of a new project, and never force-push
the default branch or merge a PR without review.

## Related skills

- [`../research-only/SKILL.md`](../research-only/SKILL.md) — the no-build exploration variant.
- Every phase skill linked above.
