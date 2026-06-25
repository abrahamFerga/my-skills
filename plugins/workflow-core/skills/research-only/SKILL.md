---
name: research-only
description: >
  Orchestrator for exploring an industry without committing to a build — delegates the research to
  the industry-researcher agent and (optionally) runs the spec phase, then stops, producing portable
  artifacts. Run this for portfolio/competitive research or to decide whether an industry is worth
  building. DO NOT USE FOR a full build (use ../build-generated-system/SKILL.md) or for bootstrapping
  a real project (use ../init-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# research-only

A fast, no-commitment path: produce one or two artifacts, decide whether an industry is interesting,
and move on without leaving a half-configured project behind. It runs the research phase (and
optionally the spec phase) in isolation — **no `workflow.json`, no repo, no build**.

## Inputs

- **industry** (required) — short lowercase phrase. Unlike a full build there is no `workflow.json`
  to read it from, so it must be given here (or in the invocation).
- **target_path** (optional) — where to write output. Default: `./research-<industry>/`.
- **include_spec** (optional) — `yes` / `no`. Default: `no`.

## Stage plugin

Enable `system-definition@my-skills` (plus the always-on `workflow-core`) for this run, then
`/reload-plugins` — that is what makes the **industry-researcher** agent available:

```json
{ "enabledPlugins": { "workflow-core@my-skills": true, "system-definition@my-skills": true } }
```

## Pipeline

### Phase 1 — Bootstrap (light)

Create `<target_path>/` if missing. Do **not** run `/workflow-core:init-system` — this is an
exploration directory, not a full project, so there is no `workflow.json` or `.claude/settings.json`.

### Phase 2 — Research (agent)

Delegate to the **industry-researcher** subagent (Agent tool, `subagent_type: industry-researcher`)
with a brief that **names the industry explicitly** (there is no `workflow.json` for it to read) and
the target path: "You are exploring `<industry>`. Write `<target_path>/research/<industry>.md` per
your method; surface any open questions." The agent works autonomously and returns the artifact
path and open-questions status. This variant does **not** require the questions to be answered —
surface them; the user may answer now or later.

### Phase 3 — Spec (optional, inline)

If `include_spec` is `yes`, follow the **synthesize-spec** skill (`/system-definition:synthesize-spec`)
— read its `SKILL.md` and follow it inline (it is `disable-model-invocation`, so the Skill tool
can't fire it) — writing `<target_path>/SPEC.md`. Otherwise stop.

## Then what

- The artifacts are portable markdown — share, evaluate, archive, or delete them freely; nothing
  else depends on them.
- To commit to building the industry's system, run
  [`build-generated-system`](../build-generated-system/SKILL.md); its own research phase can
  re-validate or redo from scratch.

## Related skills

- [`build-generated-system`](../build-generated-system/SKILL.md) — the full end-to-end build. **Load when:** you decide the industry is worth building.
- **industry-researcher** (system-definition agent) — the autonomous worker this delegates Phase 2 to.
- `/system-definition:synthesize-spec` — the optional Phase 3 spec step.
