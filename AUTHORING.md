# Authoring skills for this repo

The canonical template and checklist for adding a skill to `my-skills`. Follows
the [Claude Code skills](https://code.claude.com/docs/en/skills) and
[Agent Skills](https://agentskills.io) standards and the conventions of the
existing skills.

## Where a skill lives

A skill lives **under its owning plugin**:

```text
plugins/<plugin>/skills/<kebab-name>/
├── SKILL.md          # required — the entry point (body < ~450 lines)
├── references/       # optional — progressive-disclosure deep dives (one level deep)
│   └── <topic>.md
└── assets/           # optional — copy-ready template files (Terraform, YAML, project skeletons)
```

Each plugin is a **self-contained directory** with its own
`.claude-plugin/plugin.json` and `skills/` tree. The `.claude-plugin/marketplace.json`
catalog has one entry per plugin whose `source` points at `./plugins/<plugin>`. A
plugin auto-discovers every skill under its own `skills/` — there is **no `skills`
array to maintain**, and because each plugin has a distinct source root, plugins never
expose each other's skills. Stage plugins:

| Plugin | Stage | Default |
|--------|-------|---------|
| `workflow-core` | ops/meta, all stages | on |
| `system-definition` | stage 1 | off |
| `architecture` | stage 2 | off |
| `development` | stage 3 | on |

**Cross-plugin links break on install.** Plugins are installed in isolation, so a
relative path from one plugin to another (`../../<other-plugin>/...`) won't resolve at
runtime. Reference a sibling in the **same** plugin by relative path
(`../<name>/SKILL.md`); reference a skill in **another** plugin by slash command
(`/<plugin>:<skill>`), never by file path.

## Naming

- **Skill folder & `name`:** short, kebab-case, technology/domain-named
  (`aspire`, `entity-framework-core`, `research-industry`). `name` ≤ 64 chars,
  lowercase/digits/hyphens, must not contain `claude` or `anthropic`.
- **Reference files:** kebab-case topic names (`migrations.md`, `app-model.md`).

## Frontmatter (required)

```yaml
---
name: <kebab-name>            # must equal the folder name
description: >
  <2–4 dense sentences: what the skill does + when to use it + the 1–2 sharpest
  exclusions>. USE FOR: ... DO NOT USE FOR: ...
license: MIT
disable-model-invocation: true   # OPTIONAL — see "Invocation" below
---
```

- The `description` is the only thing loaded for auto-invocation. Keep it tight:
  put the key use case first; the combined `description` (+ optional `when_to_use`)
  is truncated at ~1,536 chars in the skill listing, and long descriptions eat the
  shared listing budget. Move exhaustive `USE FOR` / `DO NOT USE FOR` enumerations
  into the body or a `references/scope.md` if they get long.

## Invocation: auto vs manual (noise control)

- **Knowledge/reference skills** Claude should reach for automatically while
  working → leave model-invokable (omit `disable-model-invocation`). Keep their
  descriptions sharp; they are the always-on cost when their plugin is enabled.
- **Action / phase / ops skills** a human fires deliberately (scaffolders,
  generators, `init`/`deploy`-style mutations, pipeline phases) → set
  `disable-model-invocation: true`. The skill is then invoked only as
  `/<plugin>:<skill>`, and its description is **not** loaded into context (zero
  always-on cost). In this repo only the three .NET references
  (`agent-framework-csharp`, `aspire`, `entity-framework-core`) are
  model-invokable; everything else is manual.

## SKILL.md body — section order

1. `# Title` + 1–2 paragraph intro.
2. `## When to Use` — concrete scenarios.
3. `## Stop Signals` — `**<situation>** → <use this instead>`.
4. `## Inputs` — table.
5. *(tech skills)* `## Version / package status` — pinned, date-stamped.
6. *(tech skills)* `## Core Mental Model` — diagram and/or key-types table.
7. `## Workflow` — numbered, copy-pasteable steps. *(process skills may use
   `## How to do it`, `## Output`, `## Approach`, `## How to reason` instead —
   match the job; don't bolt a package table onto a process skill.)*
8. `## Validation` / `## Guardrails` — checklists.
9. `## Common Pitfalls` — table.
10. `## Reference Files` / `## Related skills` — each with a **`Load when:`** hint;
    cross-link siblings as `../<name>/SKILL.md`.
11. `## More Info` — external links.

## Writing rules

- Body **under ~450 lines**; push depth into `references/` (one level deep; a
  reference >100 lines should open with a table of contents).
- Numbered steps for workflows, checklists for requirements, tables for matrices.
- Cross-platform `dotnet` CLI; no hardcoded secrets in examples.
- Pin current versions/package IDs (verify on the web — these ecosystems move fast).
- Clickable relative links for same-plugin siblings (`references/x.md`,
  `../other-skill/SKILL.md`, `assets/...`); slash commands (`/plugin:skill`) for
  other-plugin skills. Keep skill bodies tool-agnostic so they also work under Copilot.
- Don't copy upstream docs verbatim; record attribution in `NOTICES.md`.

## `assets/` (copy-ready templates)

When a skill produces files (IaC, CI/CD, project skeletons), ship valid,
parameterized template files under `assets/` and explain them in a `references/*.md`.

## Checklist — adding a new skill

1. `mkdir plugins/<plugin>/skills/<name>/` (+ `references/`, `assets/` as needed),
   under the plugin that owns the stage it belongs to.
2. Write `SKILL.md` with valid frontmatter and the section order above. Decide
   auto vs manual invocation and set `disable-model-invocation` accordingly.
3. Web-verify all versions/package IDs/API names before committing them to prose.
4. No marketplace edit needed — the plugin auto-discovers the new `skills/<name>/`
   folder. (Only adding a whole new *plugin* requires a `marketplace.json` entry
   plus a `plugins/<plugin>/.claude-plugin/plugin.json`.)
5. Add a row to the matching table in `README.md`.
6. Add upstream attribution to `NOTICES.md` if you adapted anything.
7. Lint: `npx markdownlint-cli2 "plugins/<plugin>/skills/<name>/**/*.md"`. Validate
   the marketplace with `claude plugin validate .` if available.
