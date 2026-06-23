---
name: research-only
description: >
  Orchestrator for exploring an industry without committing to a build — runs
  research-industry and (optionally) synthesize-spec, then stops, producing
  portable artifacts. Run this for portfolio/competitive research or to decide
  whether an industry is worth building. DO NOT USE FOR a full build (use
  ../build-generated-system/SKILL.md) or for bootstrapping a real project
  (use ../init-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# research-only

A fast, no-commitment path: produce one or two artifacts, decide whether an
industry is interesting, and move on without leaving a half-configured project
behind. It runs the research phase (and optionally the spec phase) in isolation.

## Inputs

- **industry** (required) — short lowercase phrase.
- **target_path** (optional) — where to write output. Default: `./research-<industry>/`.
- **include_spec** (optional) — `yes` / `no`. Default: `no`.

## Stage plugin

Enable `system-definition@my-skills` (plus the always-on `workflow-core`) for
this run:

```json
{ "enabledPlugins": { "workflow-core@my-skills": true, "system-definition@my-skills": true } }
```

Then `/reload-plugins`.

## Pipeline

### Phase 1 — Bootstrap (light)

Create `<target_path>/` if missing. Do **not** run `init-system` — this is an
exploration directory, not a full project, so there is no `workflow.json` or
`.claude/settings.json`.

### Phase 2 — Research

Run `/system-definition:research-industry`
(`/system-definition:research-industry`) for the industry, writing
`<target_path>/research/<industry>.md`. If the artifact's *Open questions* are
non-empty, surface them — the user may answer now or later; this variant does not
require it.

### Phase 3 — Spec (optional)

If `include_spec` is `yes`, run `/system-definition:synthesize-spec`
(`/system-definition:synthesize-spec`), writing `<target_path>/SPEC.md`.
Otherwise stop.

## Then what

- The artifacts are portable markdown — share, evaluate, archive, or delete them
  freely; nothing else depends on them.
- To commit to building the industry's system, run
  [`../build-generated-system/SKILL.md`](../build-generated-system/SKILL.md); its
  own research phase can re-validate or redo from scratch.

## Related skills

- [`../build-generated-system/SKILL.md`](../build-generated-system/SKILL.md) — the full end-to-end build.
- `/system-definition:research-industry`, `/system-definition:synthesize-spec` — the phases this runs.
