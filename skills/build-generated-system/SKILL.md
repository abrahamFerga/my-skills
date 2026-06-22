---
name: build-generated-system
description: >
  Orchestrator that drives the full system-building pipeline end to end —
  bootstrap → research → spec → plan → design → compose → build → validate —
  invoking the right stage skill at each phase and gating on each phase's exit
  condition. Run this when the user wants a complete new system built from an
  industry name. DO NOT USE FOR a single phase (invoke that phase's skill
  directly) or for exploration without committing to a build (use
  ../research-only/SKILL.md).
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

`workflow-core` (this skill's home) is always on. After Phase 8, flip
`system-definition` and `architecture` to `false` for the long development phase
— [`../manage-skills/SKILL.md`](../manage-skills/SKILL.md) can generate this map
from the `workflow.json` `stage` field.

## Pipeline

Run phases in order. Do not skip or reorder. Each phase is idempotent: if the
expected artifact already exists and is valid, short-circuit and move on. After a
successful Phase 1, all later skills operate under `<target_path>/<project_name>`.

### Phase 1 — Bootstrap

Run `/workflow-core:init-system` ([skill](../init-system/SKILL.md)) with the
project name, industry, and `target_path`.
**Exit:** `workflow.json` + `.claude/settings.json` exist and validate.

### Phase 2 — Research

Run `/system-definition:research-industry`
([skill](../research-industry/SKILL.md)) for the industry.
If the artifact's *Open questions* are non-empty, **stop** and have the user
answer them in-place before continuing.
**Exit:** `research/<industry>.md` exists, conforms, no unanswered questions.

### Phase 3 — Spec

Run `/system-definition:synthesize-spec`
([skill](../synthesize-spec/SKILL.md)).
**Exit:** `SPEC.md` exists, conforms, no unanswered open questions.

### Phase 4 — Plan

Run `/system-definition:plan-system` ([skill](../plan-system/SKILL.md)).
**Exit:** `PLAN.md` exists, Foundations is epic 1, every must-have capability
maps to an epic.

### Phase 5 — Design

Run `/architecture:design-architecture`
([skill](../design-architecture/SKILL.md)) to produce `ARCH.md` + C4 diagrams +
`DECISIONS.md`. For the concrete .NET/Azure realization (solution skeleton +
Terraform + GitHub Actions), it hands off to
[`../dotnet-architecture/SKILL.md`](../dotnet-architecture/SKILL.md).
**Exit:** `ARCH.md` complete, C4 diagrams checked in, an ADR in `DECISIONS.md`
for every non-default choice.

### Phase 6 — Compose

Apply composition to `workflow.json` + `.claude/settings.json` with
`/workflow-core:manage-workflow` ([skill](../manage-workflow/SKILL.md)) and
`/workflow-core:manage-skills` ([skill](../manage-skills/SKILL.md)):

1. Set cloud (`{{cloud}}`, or ask: azure/aws/none).
2. Add each connector in `{{connectors}}`.
3. Add capabilities the user wants now.
4. Declare each external marketplace in `{{external_marketplaces}}`.

**Exit:** `workflow.json` reflects the choices; `.claude/settings.json` synced; both validate.

### Phase 7 — Build

Run `/development:build-system` ([skill](../build-system/SKILL.md)). It generates
the repo epic by epic in `PLAN.md` order — Foundations first — composing
[`../dotnet-architecture/SKILL.md`](../dotnet-architecture/SKILL.md),
[`../dotnet-aspire-base/SKILL.md`](../dotnet-aspire-base/SKILL.md),
[`../pluggable-connectors/SKILL.md`](../pluggable-connectors/SKILL.md), and the
.NET reference skills, and running `/workflow-core:validate-system` between
epics. Never start epic N+1 until epic N is green.
**Exit:** every epic generated and green (`dotnet build -c Release` clean,
`dotnet test` passing, validate exits 0).

### Phase 8 — Validate & verify

Run `/workflow-core:validate-system` ([skill](../validate-system/SKILL.md)) for
the static checks, then `/development:verify-runtime`
([skill](../verify-runtime/SKILL.md)) to prove the system works at runtime.
**Exit:** all checks `OK`; runtime behavior verified.

## When to stop early

- Phase 2 can't find ~5 credible players → the industry may be too narrow; discuss.
- Phase 5 hits a fundamental conflict with the architecture guardrails → write the ADR before continuing.
- Phase 7 fails the same module the same way twice → architecture or a skill is wrong; surface it, don't loop.

## Guardrails

This is a workflow, not a magic box. The user keeps every decision; the
orchestrator only enforces order and handoff artifacts. Pausing is fine —
re-invoke to resume (completed phases short-circuit). Committing and pushing are
user actions; this skill does not push.

## Related skills

- [`../research-only/SKILL.md`](../research-only/SKILL.md) — the no-build exploration variant.
- Every phase skill linked above.
