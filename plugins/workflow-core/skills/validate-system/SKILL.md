---
name: validate-system
description: >
  Check a generated system's `workflow.json` against the format, scan for secret
  patterns, and verify `.claude/settings.json` matches what manage-skills would
  generate from the current `workflow.json`. Produces a pass/fail report that
  exits non-zero on any failure. Read-only — it reports problems, it does not fix
  them.
  USE FOR: confirming a system is in a good state before commit, before build, or
  in CI; auditing schema/secret/sync consistency.
  DO NOT USE FOR: fixing problems it finds (use ../manage-workflow/SKILL.md or
  ../manage-skills/SKILL.md); creating a new project (use ../init-system/SKILL.md);
  generating code (use /development:build-system).
license: MIT
disable-model-invocation: true
---

# validate-system

The "is this system in a good state?" skill. Reads both `workflow.json` and `.claude/settings.json`, runs every check the ops skills would normally run before writing, and produces a pass/fail report. Used:

- Before committing changes to a generated system
- Before invoking `/development:build-system` (which assumes a valid project)
- In a generated system's CI pipeline (invoked through Claude Code)

## Approach

This is an audit skill, so the stance is adversarial: start by asking "what would make this fail?", not "does this look fine?" Give no benefit of the doubt — if something can't be proven, it's flagged.

- **Schema is law, settings sync is law.** Drift between `workflow.json` and its format is a failure. For settings sync, a *missing* required stage plugin (or a wrong marketplace/external entry) is a failure; an *extra* stage plugin enabled is the tolerated build-mode superset (a note), not a failure.
- **Secrets in writing is a critical failure.** Any pattern match in `workflow.json` blocks, no exceptions.
- **Read-only by default.** This skill validates; it never modifies `workflow.json` or `.claude/settings.json`.
- **Concrete remediation, not vague advice.** Don't say "fix the schema errors"; say exactly which field has which disallowed value and what the allowed set is.
- **No "minor" findings.** If it's not worth reporting, don't. The report is short or it's uselessly long.

## When to Use

- Before commit, before build, or in CI, to confirm `workflow.json` and `.claude/settings.json` are valid and in sync.

## Inputs

- **Project root** (defaults to the current working directory).

## Output

A structured report printed to the user. Each section is `OK` or `FAIL <reason>`. The overall result is `OK` iff every section is `OK`; on any failure, the report exits non-zero and the user has a concrete list of fixes.

```text
/workflow-core:validate-system

  found    workflow.json
  valid    workflow.json against schema
  clean    no secret patterns in workflow.json
  synced   .claude/settings.json matches workflow.json
  github   abrahamFerga/the-lawyer (board #7) reachable

OK
```

Status words: `found` / `valid` / `clean` / `synced` / `github` for OK; `missing` / `invalid` / `secrets` / `stale` for fail. The `github` line also reports `local-only` (no GitHub configured) or `warn <reason>` (config present but remote unreachable / `gh` unavailable) — neither fails the overall result.

### `workflow.json` structure (what "valid" means)

The authoritative `workflow.json` shape this skill validates against — field-by-field rules, the `stage` enum, the `skills.self` invariant (drift is a failure), the stage -> enabledPlugins mapping, the `skills.external[]` / marketplace-ref forms, and the no-unknown-keys rule — lives in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). The structure there is law; this skill reports any deviation rather than fixing it. In particular:

- The `stage` field must be a valid enum — one of `system-definition`, `architecture`, `development`.
- `skills.self` must match the invariant exactly: `marketplace` = `my-skills`, `repo` = `abrahamFerga/my-skills`, `plugins` = the four stage plugins `workflow-core`, `system-definition`, `architecture`, `development`. Any drift is a failure.
- `.claude/settings.json` `enabledPlugins` must enable the `stage`'s **required** plugins (`workflow-core` + the active stage's plugin); **extra** stage plugins enabled is tolerated (the build-mode superset), a **missing** required one is a finding — see the stage -> enabledPlugins mapping.

## Checks (run in order, stop on the first that fails)

1. **`found workflow.json`** — file exists at `<project-root>/workflow.json`. On miss: refuse, direct the user to [`init-system`](../init-system/SKILL.md).
2. **`valid workflow.json against schema`** — parse the file, validate against the structure in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). On miss: print each error with the JSON path it occurred at, as `<path>: <keyword>: <message>`. This includes two specific invariants:
   - **`stage` is a valid enum** — `system-definition`, `architecture`, or `development`. Any other value (or a non-string) is a finding.
   - **`skills.self` matches the invariant** — `marketplace` = `my-skills`, `repo` = `abrahamFerga/my-skills`, `plugins` = `["workflow-core", "system-definition", "architecture", "development"]`. Any drift is a finding.
3. **`clean no secret patterns in workflow.json`** — scan every string value for the secret patterns in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). On miss: print the *names* of the pattern types that matched (NEVER the matched values themselves — that defeats the purpose).
4. **`synced .claude/settings.json matches workflow.json`** — verify `extraKnownMarketplaces` + the external plugins derived from `workflow.json.skills`, and that the `stage`'s **required** self plugins are enabled: `workflow-core@my-skills` **and** the active stage's plugin must be `true`. Per the stage -> enabledPlugins mapping in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md), a **missing** required plugin (or a wrong `extraKnownMarketplaces`/external entry) is a finding; **extra** stage plugins enabled is the tolerated build-mode superset (`build-generated-system` keeps all four on during a run) — note it, don't fail it. On miss: print which required keys are out of sync and suggest invoking [`manage-skills`](../manage-skills/SKILL.md) with `sync` to fix.
5. *(Optional, when supported)* **`connectors present`** — for each connector in `workflow.json.connectors`, verify the corresponding `Infrastructure.<Connector>/` project exists in the solution. Skip if `build-system` hasn't run yet.
6. **`github`** — *non-fatal*. If `github` is absent or `null`, report `local-only` and move on (a project can be deliberately local). If present, validate its shape against the `github` block in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md) (a shape violation — e.g. `repo` whose `name` segment ≠ top-level `name`, or a non-integer `project` — **is** a failure). Then, only when `gh` is authenticated, confirm the repo resolves (`gh repo view <repo>`) and the board exists (`gh project view <project> --owner @me`); a missing remote is a **warning** (the config points at something that isn't there), not a hard failure — `gh` may be offline or run in a context without the `project` scope. Never block a local validation on network/auth state.

## Workflow

1. **Resolve the project root** safely (absolute path; no `..` traversal, no null bytes, no invalid characters).
2. **Run each check in order.** If a check fails, print the failure with detail and stop — do not run subsequent checks. This keeps the output focused on the first thing to fix.
3. **Format output consistently** — two columns: status word + check description.
4. **For the schema check**, walk every error and print as `<path>: <keyword>: <message>` so the user can pinpoint where the file is wrong. Give concrete remediation (e.g. "the `cloud` field is `gcp`, which is not in the allowed set [`azure`, `aws`, `none`] — set it to one of those or remove the field").
5. **For the secret check**, print pattern names only — never matched substrings.
6. **For the sync check**, verify `extraKnownMarketplaces` + the external plugins match `workflow.json.skills`, and that the `stage`'s required self plugins (`workflow-core` + the stage plugin) are enabled. Treat extra stage plugins enabled as the build-mode superset (a note, not a failure); a missing required plugin or a wrong marketplace/external entry is a finding. Suggest `manage-skills sync` to fix.
7. **Run an adversarial pass before declaring OK.** Re-read the system as if seeing it for the first time and look for: internal inconsistencies (e.g. `skills.external` references a marketplace that `settings.json` doesn't enable), optimistic counts, and out-of-date references. Fix nothing — surface every finding in the report.
8. **Exit cleanly with `OK`** only if every check (and the adversarial pass) passed.

## Guardrails

The secret-pattern table (this skill scans against it but never modifies anything) and path-safety rules are shared across the ops skills — see [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). Validate-specific guardrails:

- **Read-only.** This skill must never modify `workflow.json` or `.claude/settings.json`. If a `--fix` option is ever added, it must be opt-in, dry-run by default, and document each change.
- **Never echo secrets.** Emit pattern *names* only — never the matched values.
- **The structure is authoritative.** Don't second-guess it here — if the [structure](../init-system/references/ops-safety.md) accepts something you dislike, fix the structure (separate change) rather than adding a "soft" check.
- **Severities matter, no quiet passes.** A schema mismatch is an error; a missing `reason` on an external marketplace is a warning. Don't downgrade an error to make the build pass, and don't silently skip a known issue.

## Validation

The skill's own output IS the validation report. Every check labeled `OK` or `FAIL <reason>`; overall `OK` only when all pass; any failure exits non-zero with concrete remediation and stops at the first failure.

## Common Pitfalls

- Continuing to later checks after the first failure — stop at the first to keep the output focused.
- Printing matched secret substrings in the report — emit pattern names only.
- Treating a *missing required* settings-sync plugin as a warning — that's a failure; suggest `manage-skills sync`. (Failing on an *extra* enabled stage plugin is the opposite error — that's the tolerated build-mode superset.)

## Related skills

- [`init-system`](../init-system/SKILL.md), [`manage-workflow`](../manage-workflow/SKILL.md), [`manage-skills`](../manage-skills/SKILL.md) — the writers; this skill is the corresponding reader.
- `/development:build-system` — should be preceded by a clean validate.
