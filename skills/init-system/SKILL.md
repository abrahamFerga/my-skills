---
name: init-system
description: >
  Bootstrap a brand-new generated system: create the project directory, write a
  valid `workflow.json`, and write the matching `.claude/settings.json` so Claude
  Code picks up the my-skills stage plugins on next open. These are the only two
  files a fresh system needs; later skills add cloud, connectors, capabilities,
  and code.
  USE FOR: starting a new `the-*` system from scratch; scaffolding the initial
  workflow.json + .claude/settings.json pair.
  DO NOT USE FOR: modifying an existing workflow.json (use ../manage-workflow/SKILL.md);
  declaring external plugin marketplaces (use ../manage-skills/SKILL.md); checking
  whether an existing project is valid (use ../validate-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# init-system

The very first step inside a brand-new generated-system repo. Creates the two files every system needs — `workflow.json` and `.claude/settings.json` — and nothing else. Subsequent skills add cloud, connectors, capabilities, and the actual code.

## Approach

This is an ops skill that mutates a developer's filesystem, so treat every operation as a security surface:

- Validate before writing. Schema-shape check first, secret scan second, write third. Never write a file that doesn't conform.
- Refuse, don't fudge. If an input is invalid, refuse and explain — don't "best-effort" through it.
- Idempotent, atomic, dry-run-able by default. Re-running with the same inputs (and `--force`) yields byte-identical output.

## When to Use

- The user wants to start a new `the-*` system from scratch.
- There is no `workflow.json` yet in the target location.

## Inputs

- **Project name** (required) — kebab-case, must start with `the-` (e.g. `the-lawyer`, `the-doctor`). If the user proposes a name without that prefix, refuse and explain.
- **Industry** (required) — short lowercase phrase (e.g. `legal`, `healthcare`, `logistics`), 2–64 chars.
- **Target path** (optional, defaults to the current working directory) — where the project directory should live.

Validate every input before writing anything.

## Output

Two files at `<target-path>/<project-name>/`:

```text
<project-name>/
├── workflow.json          # Validated against the workflow.json structure below
└── .claude/
    └── settings.json      # extraKnownMarketplaces + enabledPlugins for the my-skills stage plugins
```

### Initial `workflow.json` template

```json
{
  "name": "<project-name>",
  "industry": "<industry>",
  "stage": "system-definition",
  "cloud": "none",
  "connectors": [],
  "capabilities": [],
  "skills": {
    "self": {
      "marketplace": "my-skills",
      "repo": "abrahamFerga/my-skills",
      "plugins": ["workflow-core", "system-definition", "architecture", "development"]
    },
    "external": []
  }
}
```

### Initial `.claude/settings.json` template

A fresh init starts in the `system-definition` stage, so only `workflow-core` and `system-definition` are enabled:

```json
{
  "extraKnownMarketplaces": {
    "my-skills": { "source": { "source": "github", "repo": "abrahamFerga/my-skills" } }
  },
  "enabledPlugins": {
    "workflow-core@my-skills": true,
    "system-definition@my-skills": true,
    "architecture@my-skills": false,
    "development@my-skills": false
  }
}
```

### `workflow.json` structure

The authoritative `workflow.json` shape (field-by-field rules, the `stage` enum, the `skills.self` invariant, the stage -> enabledPlugins mapping, and the `skills.external[]` / marketplace-ref format) lives in [`references/ops-safety.md`](references/ops-safety.md). Validate the built object against it before writing.

The `stage` field is an enum — one of `system-definition`, `architecture`, or `development` — and defaults to `system-definition` for a fresh init. It drives which stage plugins `.claude/settings.json` enables (see the stage -> enabledPlugins mapping in [`references/ops-safety.md`](references/ops-safety.md)).

## Workflow

1. **Validate the project name** against `^the-[a-z][a-z0-9-]{0,38}$`. If invalid, refuse and explain.
2. **Validate the industry** is 2–64 chars, no surrounding whitespace.
3. **Resolve the target path** to an absolute path. Reject any `..` segments, null bytes, or characters invalid for the host filesystem before resolving.
4. **Check whether `<target>/<name>/workflow.json` already exists.** If yes and the user did not pass `--force` (an explicit "overwrite" intent), refuse — surface the conflict.
5. **Create the project directory** if it doesn't exist. Create `.claude/` inside it.
6. **Build the `workflow.json` object** from the template above with the user's name + industry substituted in.
7. **Validate it against the structure** in [`references/ops-safety.md`](references/ops-safety.md). If validation fails, refuse — never write an invalid `workflow.json`.
8. **Scan every string value** in the object for the secret patterns in [`references/ops-safety.md`](references/ops-safety.md). On any match, refuse — the user must use a secret-store reference instead of an embedded value.
9. **Write `workflow.json`** with stable 2-space indentation and a trailing newline, as a single complete operation.
10. **Build and write `.claude/settings.json`** using the second template. If a `.claude/settings.json` already exists (rare in a fresh init), merge into it — preserve any unrelated keys, replacing only `extraKnownMarketplaces` and `enabledPlugins`.
11. **Print next steps** for the user:
    - `cd <project-name>`
    - `claude` (open Claude Code in the new project)
    - Invoke `/system-definition:research-industry "<industry>"` to start the workflow, or run the `/workflow-core:build-generated-system` orchestrator to drive the full chain.

## Guardrails

Path safety, the secret-pattern table, atomic-write rules, and the `.claude/settings.json` merge rules are shared across the ops skills — see [`references/ops-safety.md`](references/ops-safety.md). Init-specific guardrails:

- **Schema conformance.** `workflow.json` MUST validate against the structure in [`references/ops-safety.md`](references/ops-safety.md) before being written. The structure is authoritative — if a desired field isn't in it, the structure is wrong and must be updated first (separate change), not bypassed here.
- **Dry-run.** If `--dry-run` was requested, run every step *except* the write (validation and secret scan still run) and print the files that would be written and their contents. Exit 0 with no filesystem side effects. A refused input under `--dry-run` still exits non-zero.
- **Idempotency.** Running this skill twice with the same arguments and `--force` produces byte-identical output. A no-op run does not mutate further.

## Common Pitfalls

- Accepting a name without the `the-` prefix — refuse; the prefix is an invariant of the `The<Domain>` family.
- Full-replacing an existing `.claude/settings.json` instead of merging — clobbers the user's theme and other unrelated keys.
- Embedding a token "just this once" in `workflow.json` — refuse and point the user at a secret-store reference.

## Related skills

- [`research-industry`](../research-industry/SKILL.md) — the next skill in the chain; produces the industry research artifact the rest of the workflow plans against.
- [`manage-workflow`](../manage-workflow/SKILL.md) — composes cloud, connectors, and capabilities into the workflow.json this skill created.
- [`manage-skills`](../manage-skills/SKILL.md) — declares external plugin marketplaces.
- [`validate-system`](../validate-system/SKILL.md) — confirms the system is in a good state.
