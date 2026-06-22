---
name: manage-skills
description: >
  Declare or remove third-party Claude Code plugin marketplaces in a generated
  system's `workflow.json`, then re-sync `.claude/settings.json` so Claude Code
  installs them on next open. Always touches both files and preserves unrelated
  keys in `settings.json`. External skills are declared, never vendored.
  USE FOR: adding/removing external marketplaces like `dotnet/skills` or
  `anthropics/skills`; re-syncing settings.json from workflow.json.
  DO NOT USE FOR: connectors or capabilities (use ../manage-workflow/SKILL.md);
  creating a fresh project (use ../init-system/SKILL.md); validating without
  mutating (use ../validate-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# manage-skills

The skill for "compose the skill set." Adds or removes external Claude Code plugin marketplaces in a generated system. Always touches both files: `workflow.json` (the source of truth) and `.claude/settings.json` (what Claude Code actually reads).

This is how a generated system gets things like `dotnet/skills`, `anthropics/skills`, or any other plugin marketplace without copying skills locally. External skills are **declared, never vendored** — provenance is preserved by using Claude Code's native marketplace mechanism. Every external marketplace should carry a `reason` so future maintainers know why the dependency exists, and should be pinned by tag where possible (`owner/repo#v1.2.0`).

## Approach

This is an ops skill that mutates both `workflow.json` and the security-sensitive `.claude/settings.json`, so:

- Marketplace refs are allow-listed to three forms. Anything else is a security error — a malicious entry in `settings.json` lets remote code reach the developer's machine on next open.
- `.claude/settings.json` writes are merges, not replaces — never clobber unrelated keys.
- Schema validation gates every `workflow.json` write; secret scan runs before every write.

## When to Use

- The user wants to add or remove an external plugin marketplace, or re-sync `settings.json` from the current `workflow.json`.

## Inputs

- **Project root** (defaults to the current working directory).
- **Operation** — one of:
  - `add <marketplace>@<plugin> [--reason <text>]`
  - `remove <marketplace>@<plugin>`
  - `sync` — regenerate `.claude/settings.json` from the current `workflow.json` without otherwise mutating

## Output

For `add` and `remove`: updates both `workflow.json` (in the `skills.external` array) and `.claude/settings.json`. For `sync`: only updates `.claude/settings.json`.

### Structure reference

The `skills.external[]` entry shape, the `skills.self` invariant, the `stage` enum, the `.claude/settings.json` generated shape, the **stage -> enabledPlugins mapping**, and the three allowed marketplace-ref forms (GitHub `owner/repo[#tag]`, `https://...git`, `./local-path`) all live in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). This skill writes the `skills.external[]` side; `skills.self` is never mutated here.

### How `enabledPlugins` is derived

When this skill regenerates `.claude/settings.json`, the `enabledPlugins` map has two parts:

- **Self stage plugins.** The four self plugins (`workflow-core`, `system-definition`, `architecture`, `development`, all on `my-skills`) get their `true`/`false` values from the `workflow.json` `stage` field, using the canonical stage -> enabledPlugins mapping in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). `workflow-core@my-skills` is **always** `true`; the active stage plugin is `true` and the other two stage plugins are `false`.
- **External plugins.** One `<plugin>@<marketplace>` key per external plugin from `skills.external[]`, value `true`.

The self-marketplace `my-skills` (`{ "source": { "source": "github", "repo": "abrahamFerga/my-skills" } }`) is always declared in `extraKnownMarketplaces`, alongside one entry per external marketplace.

## Workflow

1. **Resolve the project root.** Same path-safety rules as the other ops skills — see [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md) (absolute, no `..`, no invalid characters).
2. **Verify `workflow.json` exists** and is valid against the structure in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). If not, refuse and direct the user to [`init-system`](../init-system/SKILL.md) or [`validate-system`](../validate-system/SKILL.md).
3. **For `add` / `remove`: parse the reference** as `<marketplace>@<plugin>`:
   - The marketplace part must match one of the three ref forms in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md).
   - The plugin part must match `^[a-z][a-z0-9-]{0,63}$`.
   - On parse failure, refuse with a clear example.
4. **For `add`:**
   - If the marketplace is already in `skills.external[]`, add the plugin to its `plugins[]` (if not already present) and update `reason` if the new one is non-empty.
   - Otherwise, append a new entry `{ marketplace, plugins: [plugin], reason }`.
   - Recommend `--reason` strongly — the field exists so future maintainers know why the dependency exists.
5. **For `remove`:**
   - Remove the plugin from the matching marketplace's `plugins[]`.
   - If that `plugins[]` becomes empty, remove the marketplace entry entirely.
   - If the marketplace isn't present, report and exit cleanly.
6. **Validate the modified `workflow.json` against the structure** in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md) and scan for the secret patterns listed there. Refuse on either failure.
7. **Write `workflow.json`** (skip for `sync`).
8. **Regenerate `.claude/settings.json`** from the (possibly modified) `workflow.json`:
   - Read the existing `.claude/settings.json` if it exists; create the directory + file if not.
   - Build the `extraKnownMarketplaces` object: always declare the self-marketplace `my-skills` (`{ "source": { "source": "github", "repo": "abrahamFerga/my-skills" } }`), plus one key per external marketplace, value `{ "source": { "source": "github"|"url"|"local", "repo"|"url": <value> } }` (classify external refs by prefix: `https://` → url, `./` → local, otherwise github).
   - Build the `enabledPlugins` object in two parts:
     - **Self stage plugins** — the four `<plugin>@my-skills` keys (`workflow-core`, `system-definition`, `architecture`, `development`), with `true`/`false` derived from the `workflow.json` `stage` field per the stage -> enabledPlugins mapping in [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). Keep `workflow-core@my-skills` `true` always.
     - **External plugins** — one `<plugin>@<marketplace>` key per external plugin, value `true`.
   - Merge into the existing settings object — **preserve unrelated keys** (theme, etc.). Replace only `extraKnownMarketplaces` and `enabledPlugins`.
   - Write the file as a single complete operation with stable 2-space indentation.
9. **Print a summary** of what changed in each file, and whether `.claude/settings.json` was already in sync (no-op).
10. **Remind the user** that on next open of Claude Code in this project, the new marketplaces will prompt for trust the first time, then auto-install the declared plugins.

## Guardrails

Path safety, the secret-pattern table, atomic-write rules, the allow-listed marketplace-ref forms, and the `.claude/settings.json` merge rules are all shared across the ops skills — see [`../init-system/references/ops-safety.md`](../init-system/references/ops-safety.md). These two are load-bearing for this skill specifically:

- **Merge, don't replace.** `.claude/settings.json` writes are merges. Never clobber unrelated keys — only `extraKnownMarketplaces` and `enabledPlugins` are owned. (Full rules in the reference.)
- **Allow-listed refs.** Marketplace refs are restricted to the three forms in the reference (`owner/repo`, `https://...git`, `./local`). No SSH (`git@`), no `file://`, no implicit-protocol URLs — anything else is a security error.

Manage-skills-specific guardrails:

- **Invariant.** The `skills.self` block is never mutated by this skill.
- **Schema conformance.** Validation gates every `workflow.json` write.
- **Dry-run.** For `--dry-run`, print the diff for both files and exit 0 without writing.
- **Idempotency.** Running `sync` twice in a row produces the same file the second time (and reports "already in sync").

## Common Pitfalls

- Full-replacing `.claude/settings.json` and losing the user's theme or other settings — always merge.
- Accepting a `git@github.com:...` SSH ref — refuse; require the `owner/repo` form.
- Adding a marketplace with no `reason` — allowed but discouraged; nudge the user to supply one.

## Related skills

- [`init-system`](../init-system/SKILL.md) — must run first.
- [`manage-workflow`](../manage-workflow/SKILL.md) — for cloud / connectors / capabilities (the other half of composition).
- [`validate-system`](../validate-system/SKILL.md) — to check both files are consistent.
