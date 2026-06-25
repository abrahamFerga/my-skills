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

Each plugin is a **self-contained directory** with its own `.claude-plugin/plugin.json`
and any of these component dirs at its **root** (never inside `.claude-plugin/`):

```text
plugins/<plugin>/
├── .claude-plugin/plugin.json   # manifest (only this lives in .claude-plugin/)
├── skills/<kebab-name>/SKILL.md  # skills (auto-discovered)
├── agents/<kebab-name>.md        # subagents (auto-discovered)
├── hooks/hooks.json              # lifecycle hooks
└── scripts/<name>.js             # hook/utility scripts (node — no jq dependency)
```

The `.claude-plugin/marketplace.json` catalog has one entry per plugin whose `source`
points at `./plugins/<plugin>`. A plugin auto-discovers every skill under `skills/` and
every agent under `agents/` — there is **no array to maintain** — and because each plugin
has a distinct source root, plugins never expose each other's skills. Stage plugins:

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

## Authoring an agent (subagent)

An agent is a **worker that runs in its own context window** and returns a summary —
use one when a phase is heavy (would flood the main thread with logs/searches/file
dumps) or specialized enough to deserve its own restricted toolset and model tier. A
*skill* is shared procedure/knowledge loaded into the current context; an *agent* is a
delegate. In this repo the orchestrator delegates the heavy/repeated phases (research,
architecture, per-feature build/verify, GitHub ops) to agents and runs the light
one-time glue (init, spec, plan, publish, validate) inline.

An agent is a single markdown file at `plugins/<plugin>/agents/<kebab-name>.md`:

```yaml
---
name: feature-builder          # required — kebab; how it's spawned (subagent_type)
description: >                  # required — "when to delegate"; ALWAYS-ON context when the
  Implements one Ready issue's scope … (sharp, like a model-invokable skill description)
tools: Read, Edit, Bash        # optional allowlist (drops MCP unless listed); OR…
disallowedTools: Edit, Write   # …optional denylist (keeps MCP/browser; great for read/run-only)
model: sonnet                  # optional — omit to inherit; set a cheaper tier for mechanical work
skills: [aspire]               # optional — preload a MODEL-INVOKABLE skill's content (NOT a disable-model-invocation engine)
---

You are <role>. When invoked: 1)… 2)… Guardrails (hard): … Return value: your final
message IS the result — return structured data, not a chat reply.
```

Rules specific to **plugin** agents:

- **`hooks`, `mcpServers`, and `permissionMode` are ignored** for plugin-shipped agents
  (they work only for user/project agents). Don't rely on them here.
- **A subagent cannot reach this repo's engine skills — make it self-contained.** A subagent
  has no "active skill base dir", so it can't `Read` another skill's file by relative path; and
  `skills:` preload **only works for model-invokable skills** — you *cannot* preload a
  `disable-model-invocation` skill (Claude Code skips it and logs a warning), nor can a subagent
  invoke one via the Skill tool. Since every orchestration engine here (`build-system`,
  `verify-runtime`, `design-architecture`, …) is `disable-model-invocation`, an agent must **carry
  its own procedure + the essential guardrails in its body** and lean on (a) the project's own
  artifacts (`ARCH.md`/`PLAN.md`/`SPEC.md`, the committed `.http` catalog) and (b) the
  **model-invokable** reference skills (`aspire`, `entity-framework-core`, `agent-framework-csharp`,
  `dotnet-architecture`) via the Skill tool. Use `skills:` preload only to inject a *model-invokable*
  helper. Name the canonical `/plugin:skill` in the body so a human can run the full-fidelity version.
- **Tool scope tightly.** Use `disallowedTools: Edit, Write, NotebookEdit` when the agent
  must keep MCP/browser tools but not mutate code (`runtime-verifier`); use a `tools` allowlist
  when it needs only a few named tools (`industry-researcher`'s web+write set, `backlog-manager`'s
  `Bash, Read, Grep, Glob`). A denylist keeps inherited MCP; an allowlist drops it.
- **Model-tier for cost.** Omit `model` (inherit) for heavy reasoning; set `sonnet`/`haiku`
  for mechanical work (gh/git, board moves). Tune further with `effort` (low/medium/high/xhigh/max)
  and `maxTurns`.
- **Other supported plugin-agent fields** (none needed by the shipped agents): `memory`
  (`user`/`project`/`local` — cross-session learning), `background: true` (always run as a
  background task), `isolation: worktree` (run in a throwaway git worktree — use when parallel
  agents would otherwise clash on the same files), `color`, and `initialPrompt`.
- **Same cross-plugin rule as skills.** Reference another plugin's skill by `/plugin:skill`
  or by `skills:` name — never by file path.
- The `description` is always-on context whenever the plugin is enabled (it's how the model
  decides to delegate). Keep it as tight as a model-invokable skill description.

## Authoring a hook

Hooks live in `plugins/<plugin>/hooks/hooks.json` and react to lifecycle events. This repo
ships three on the always-on `workflow-core` plugin: a **PreToolUse** git-safety guard, a
**Stop** auto-loop continuation (opt-in), and a **SessionStart** orienter.

- **Gate with `if` so always-on hooks stay cheap.** A PreToolUse hook with
  `"if": "Bash(git push *)"` only spawns its script for matching commands — zero cost on
  every other Bash call.
- **Scripts are node, in `scripts/`, invoked via exec form** so paths with spaces and
  cross-platform shells just work:
  `{"type":"command","command":"node","args":["${CLAUDE_PLUGIN_ROOT}/scripts/guard.js"]}`.
  Node (not `jq`/`sh`) because every generated system already has it and it parses JSON
  natively. Use `${CLAUDE_PLUGIN_ROOT}` for plugin files, `${CLAUDE_PROJECT_DIR}` for project files.
- **A script reads JSON on stdin and writes a decision on stdout, exit 0.** PreToolUse
  deny → `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`;
  Stop re-drive → top-level `{"decision":"block","reason":"…"}`; SessionStart inject →
  `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"…"}}`.
- **Fail open and no-op off-target.** Every script here exits 0 silently when there's no
  `workflow.json` (so it's invisible in this repo and any non-generated project) and on any
  internal error — a buggy guard must never brick a session.
- **Make anything aggressive opt-in and bounded.** The auto-loop only fires under
  `goal.autonomy === "auto"` and trips a git-HEAD circuit breaker after N stalled iterations.
- **Test by piping sample input:** `echo '{"cwd":"…","tool_input":{"command":"git push --force"}}' | node scripts/guard.js`.
- Editing a `SKILL.md` is live; editing `hooks/`, `agents/`, `.mcp.json`, or scripts needs
  `/reload-plugins` (or a restart) to take effect.

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

## Checklist — adding an agent or hook

1. **Agent:** create `plugins/<plugin>/agents/<name>.md` with `name` + `description` (required)
   and a focused system-prompt body (When invoked / Guardrails / Return value). Scope `tools`/
   `disallowedTools`, pick a `model` tier, and `skills:`-preload the engine it runs.
2. **Hook:** add the event to `plugins/<plugin>/hooks/hooks.json`, gate it with `if`, and put the
   script in `plugins/<plugin>/scripts/<name>.js` (node, fail-open, no-op without `workflow.json`).
3. **Bump the plugin `version`** in `.claude-plugin/plugin.json` — agents/hooks/scripts are cached;
   a version bump forces the install to pick them up (and `/reload-plugins` in a live session).
4. **Test the script** by piping sample stdin JSON (see *Authoring a hook*). Add a README row.
5. Validate: `claude plugin validate .` (checks agent frontmatter + `hooks.json`), then markdownlint.
