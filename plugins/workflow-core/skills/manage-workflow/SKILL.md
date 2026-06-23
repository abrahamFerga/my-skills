---
name: manage-workflow
description: >
  Safely compose what's inside an existing generated system by updating
  `workflow.json`: set the cloud target, add or remove connectors, add or remove
  capabilities. Validates against the format on every read and write, scans for
  secrets, and preserves unrelated fields. Does not touch `.claude/settings.json`.
  USE FOR: `set stage system-definition|architecture|development`;
  `set cloud azure|aws|none`; adding/removing connectors; adding/removing
  capabilities (with optional `--provider`) in an existing project.
  DO NOT USE FOR: bootstrapping a brand-new project (use ../init-system/SKILL.md);
  declaring external plugin marketplaces (use ../manage-skills/SKILL.md);
  validating without mutating (use ../validate-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# manage-workflow

The skill for "compose the system." Adds, removes, or updates the cloud target, connectors, and capabilities recorded in `workflow.json`. Does NOT touch `.claude/settings.json` — that's `manage-skills`' job; invoke it separately when needed.

## Approach

This is an ops skill that mutates a developer's `workflow.json`, so it treats every write as a security surface:

- Validate the existing file before mutating, and the mutated object before writing. Never write a file that fails the schema.
- Idempotent by default. Adding what's present, removing what's absent, or setting what's already set is a no-op that reports cleanly and exits 0.
- Refuse, don't fudge. An invalid input or an already-invalid file is surfaced, not silently repaired.

## When to Use

- The project already has a `workflow.json` and the user wants to change cloud, connectors, or capabilities.

## Inputs

- **Project root** (defaults to the current working directory) — must contain a `workflow.json`.
- **Operation** — one of:
  - `set stage <system-definition|architecture|development>`
  - `set cloud <azure|aws|none>`
  - `add connector <kebab-name>` / `remove connector <kebab-name>`
  - `add capability <kebab-name> [--provider <provider>]` / `remove capability <kebab-name>`

## Output

A modified `workflow.json` at the project root. Nothing else. If the change is a no-op (e.g. adding a connector that's already present), report that and exit without writing.

### `workflow.json` structure

The authoritative `workflow.json` shape (field-by-field rules, the `skills.self` invariant, no-unknown-keys) lives in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). Validate against it before AND after every mutation.

## Workflow

1. **Resolve the project root** to an absolute path. Reject `..` traversal, null bytes, and invalid characters.
2. **Verify `workflow.json` exists** at the project root. If missing, refuse — direct the user to [`init-system`](../init-system/SKILL.md) first.
3. **Read and parse** `workflow.json`. If it fails to parse, refuse with the parse error.
4. **Validate the current file against the structure** in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md) — if the file is already invalid, surface that and stop. We do not silently "fix" an invalid file.
5. **Apply the operation** to an in-memory copy of the object:
   - `set stage <value>` → set the `stage` field. Reject any value not in `{ system-definition, architecture, development }`. Changing the stage changes which stage plugins must be enabled, so it requires a follow-up `.claude/settings.json` re-sync (see step 10).
   - `set cloud <value>` → set the `cloud` field. Reject any value not in `{ azure, aws, none }`.
   - `add connector <name>` → append to `connectors[]` if not present. Validate name against `^[a-z][a-z0-9-]{0,38}$`.
   - `remove connector <name>` → remove from `connectors[]`. If absent, report and exit cleanly.
   - `add capability <name> [--provider <p>]` → add to `capabilities[]` if not present, or update `provider` on the existing entry.
   - `remove capability <name>` → remove the entry.
6. **Validate the modified object against the structure** in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). If invalid, refuse and surface the errors — do not write a broken file.
7. **Scan every string value for secret patterns** (see [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md)). Refuse on any match.
8. **Write `workflow.json`** with stable 2-space indentation and a trailing newline. One complete write — don't stream partial updates.
9. **Print a one-line summary** of what changed (or "no change — already present").
10. **If `stage` changed, prompt to re-sync `.claude/settings.json`.** This skill does not touch `.claude/settings.json`, but the `stage` field drives the `enabledPlugins` map. After a `set stage`, the user must run [`../manage-skills/SKILL.md`](../manage-skills/SKILL.md) with `sync` to re-derive `enabledPlugins` per the stage -> enabledPlugins mapping in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). Surface this clearly — a stale `settings.json` will load the wrong stage plugins on next open.
11. **Remind the user** that connector code-copy and Terraform scaffolding are NOT performed by this skill — they happen later when `/development:build-system` runs over the project.

## Guardrails

Path safety, the secret-pattern table, and atomic-write rules are shared across the ops skills — see [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). Manage-workflow-specific guardrails:

- **Schema conformance.** Validation is mandatory before AND after the mutation. Never write a file that fails the schema. The structure is the truth — if it and the skill disagree, fix the [structure](../init-system/references/ops-safety.md) (separate change), don't bypass.
- **Scope.** Don't touch `.claude/settings.json`. If the user wants to add a third-party plugin marketplace, that's [`manage-skills`](../manage-skills/SKILL.md).
- **Invariant.** Don't overwrite the `skills.self` block. Its `marketplace` is `my-skills`, its `repo` is `abrahamFerga/my-skills`, and its `plugins` are the four stage plugins `workflow-core`, `system-definition`, `architecture`, `development` — invariants of any generated system. The `stage` field is mutated by `set stage`; `skills.self` is not.
- **Dry-run.** If `--dry-run` was requested, print the would-be-modified `workflow.json` (a diff is preferred over a full dump) and exit 0 without writing. Validation and the secret scan still run.
- **Idempotency.** Running the same operation twice yields the same final file; the second run is a reported no-op.

## Common Pitfalls

- Mutating an already-invalid `workflow.json` — stop and surface the existing errors first.
- Writing the file even when the operation is a no-op — check membership first and report "no change."
- Accepting a cloud value outside `{ azure, aws, none }` — refuse with the allowed set.

## Related skills

- [`init-system`](../init-system/SKILL.md) — must run first.
- [`manage-skills`](../manage-skills/SKILL.md) — for the external-marketplaces side of composition.
- [`validate-system`](../validate-system/SKILL.md) — to check the file after the mutation.
- `/development:build-system` — when you're ready to turn the composed `workflow.json` into actual code.
