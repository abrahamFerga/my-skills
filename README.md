# my-skills

A single Claude Code marketplace of **stage-scoped plugins** for agentic .NET
development, managed end-to-end through **GitHub**. Instead of one big plugin whose
20 skill descriptions all load into every session, the skills are split into four
plugins you enable per phase — so each stage carries only the context it needs.

## GitHub is the system of record

Each generated system is its own **public GitHub repo**. The workflow doesn't just
write local docs — it manages the build on GitHub:

- **Stage 1** creates the repo, a label taxonomy, and a **Projects v2 backlog board**,
  then publishes the plan as **issues**: `type:epic` issues (Foundations first) with
  `type:feature` **sub-issues**, all landing on the board in **Backlog**.
- **Stage 2** reads those feature issues, writes the architecture (committed markdown),
  and moves each architected feature **Backlog → Ready** with a note attached.
- **Stage 3** drains the board one feature at a time: branch → implement → PR that
  `Closes #N` → card to **In Review** → merge to **Done**.

Spec/architecture live as committed markdown in the repo (`SPEC.md`, `PLAN.md`,
`ARCH.md`, `DECISIONS.md`); the backlog and its status live as issues + the board.
The `gh`/board/label/issue playbook is
[`init-system/references/github-ops.md`](plugins/workflow-core/skills/init-system/references/github-ops.md).
GitHub is optional-degradable: if `gh` is unavailable, the file artifacts are still
produced and `workflow.json.github` is `null`.

## Pick tooling by stage

| Stage | Plugin | Enable | What it gives you |
|-------|--------|--------|-------------------|
| **System definition** — decide *what* to build | `system-definition@my-skills` | stage 1 (kickoff) | research an industry → spec → plan/RBAC → publish the issue backlog |
| **Architecture** — decide the *shape*, once | `architecture@my-skills` | stage 2 (once) | ARCH.md + C4 + ADRs from the backlog, .NET/Azure skeleton, Terraform, GitHub Actions |
| **Development** — continuous coding | `development@my-skills` | stage 3 (most work) | Aspire / EF Core / Agent Framework references + backbone, connectors, issue-driven build/verify |
| *(all stages)* — ops/meta | `workflow-core@my-skills` | always | bootstrap & manage `workflow.json` + the GitHub repo/board, marketplaces, validation |

Switching stage is one declarative edit (see [Enable plugins per stage](#enable-plugins-per-stage)). Disabling a stage plugin removes all of its skills' descriptions from context — the core noise-control lever.

## Skills by plugin

### `workflow-core` — ops/meta (always on)

| Skill | Slash command | What it does |
|-------|---------------|--------------|
| [build-generated-system](plugins/workflow-core/skills/build-generated-system/SKILL.md) | `/workflow-core:build-generated-system` | **Orchestrator** — drives the full pipeline: bootstrap+repo → research → spec → plan → publish backlog → compose → architect → develop (issue by issue) → validate. |
| [research-only](plugins/workflow-core/skills/research-only/SKILL.md) | `/workflow-core:research-only` | **Orchestrator** — industry research (+ optional spec), no build, no repo. |
| [init-system](plugins/workflow-core/skills/init-system/SKILL.md) | `/workflow-core:init-system` | Bootstrap a new system: `workflow.json` + `.claude/settings.json` + the public GitHub repo, labels, and backlog board. |
| [manage-workflow](plugins/workflow-core/skills/manage-workflow/SKILL.md) | `/workflow-core:manage-workflow` | Set stage/cloud, add/remove connectors & capabilities. |
| [manage-skills](plugins/workflow-core/skills/manage-skills/SKILL.md) | `/workflow-core:manage-skills` | Declare/remove external marketplaces; sync `.claude/settings.json`. |
| [validate-system](plugins/workflow-core/skills/validate-system/SKILL.md) | `/workflow-core:validate-system` | Schema + secret + sync-state check, plus a non-fatal GitHub reachability check. |

### `system-definition` — stage 1 (enable at kickoff)

| Skill | Slash command | What it does |
|-------|---------------|--------------|
| [research-industry](plugins/system-definition/skills/research-industry/SKILL.md) | `/system-definition:research-industry` | Top players → capability matrix → must-have / differentiator / skip. |
| [synthesize-spec](plugins/system-definition/skills/synthesize-spec/SKILL.md) | `/system-definition:synthesize-spec` | Capability matrix → product spec (SPEC.md). |
| [plan-system](plugins/system-definition/skills/plan-system/SKILL.md) | `/system-definition:plan-system` | Spec → epics, modules, RBAC (PLAN.md). |
| [sync-backlog](plugins/system-definition/skills/sync-backlog/SKILL.md) | `/system-definition:sync-backlog` | Publish PLAN.md to GitHub: epic + feature issues, sub-issues, board in Backlog. |

### `architecture` — stage 2 (enable once)

| Skill | Slash command | What it does |
|-------|---------------|--------------|
| [design-architecture](plugins/architecture/skills/design-architecture/SKILL.md) | `/architecture:design-architecture` | Read the feature backlog → ARCH.md + C4 + ADRs; move features Backlog → Ready. |
| [dotnet-architecture](plugins/architecture/skills/dotnet-architecture/SKILL.md) | `/architecture:dotnet-architecture` | .NET/Azure realization: solution skeleton + Terraform + GitHub Actions. |

### `development` — stage 3 (default on)

| Skill | Invocation | What it does |
|-------|------------|--------------|
| [agent-framework-csharp](plugins/development/skills/agent-framework-csharp/SKILL.md) | auto + `/development:agent-framework-csharp` | Microsoft Agent Framework reference. |
| [aspire](plugins/development/skills/aspire/SKILL.md) | auto + `/development:aspire` | Aspire 13.x orchestration reference. |
| [entity-framework-core](plugins/development/skills/entity-framework-core/SKILL.md) | auto + `/development:entity-framework-core` | EF Core 10 data-layer reference. |
| [dotnet-aspire-base](plugins/development/skills/dotnet-aspire-base/SKILL.md) | `/development:dotnet-aspire-base` | Scaffold the .NET 10 + Aspire solution backbone. |
| [pluggable-connectors](plugins/development/skills/pluggable-connectors/SKILL.md) | `/development:pluggable-connectors` | On-demand channel/integration pattern. |
| [build-system](plugins/development/skills/build-system/SKILL.md) | `/development:build-system` | Code-generation engine: Foundations bootstrap, then one feature's scope. |
| [work-next-issue](plugins/development/skills/work-next-issue/SKILL.md) | `/development:work-next-issue` | The Stage-3 loop: next Ready issue → branch → build-system → PR (`Closes #N`) → board. |
| [verify-runtime](plugins/development/skills/verify-runtime/SKILL.md) | `/development:verify-runtime` | Install testability infra + run → observe → debug → fix loop. |

> **Noise control:** the three reference skills (Agent Framework, Aspire, EF Core) are model-invokable so Claude reaches for them automatically while coding. Every other skill sets `disable-model-invocation: true` — it's a deliberate `/plugin:skill` action and its description is **not** loaded into context, so it costs nothing until you run it.

## Prerequisites

- The [GitHub CLI](https://cli.github.com/) `gh`, authenticated (`gh auth login`).
- For the backlog board, the token needs the `project` scope: `gh auth refresh -s project`.

## Install

Add the marketplace once:

```text
/plugin marketplace add abrahamFerga/my-skills
```

Then install the plugins for your current stage:

```text
/plugin install workflow-core@my-skills
/plugin install development@my-skills
/plugin install system-definition@my-skills   # opt in for the definition phase
/plugin install architecture@my-skills         # opt in for the design phase
```

### Enable plugins per stage

The real switch is `enabledPlugins` in your project's `.claude/settings.json`. A
project in the **development** stage:

```json
{
  "enabledPlugins": {
    "workflow-core@my-skills": true,
    "development@my-skills": true,
    "system-definition@my-skills": false,
    "architecture@my-skills": false
  }
}
```

To move to a new stage, flip the booleans and run `/reload-plugins`. The
`workflow-core` skills can generate this map for you from a `workflow.json`
`stage` field — see [manage-skills](plugins/workflow-core/skills/manage-skills/SKILL.md).

## Install — Cursor / Copilot / Codex

These skills follow the [agentskills.io](https://agentskills.io) standard, so the
`SKILL.md` files work in any compatible tool:

- **Cursor:** the same `marketplace.json` works as a Cursor plugin marketplace; symlink the repo into `~/.cursor/plugins/local/my-skills`.
- **GitHub Copilot:** Copilot reads the same `SKILL.md` files. It has no per-project `enabledPlugins`, so stage-scope there by which plugin a team vendors. Skill bodies are kept tool-agnostic; only the `workflow-core` skills assume Claude Code + `gh` mechanics.
- **Codex CLI:** install a single skill directly with `skill-installer`:

  ```bash
  skill-installer install https://github.com/abrahamFerga/my-skills/tree/main/plugins/development/skills/aspire
  ```

## Repository layout

Each plugin is a **self-contained directory** with its own `.claude-plugin/plugin.json`
and `skills/` tree, so a plugin only ever exposes its own skills (no cross-plugin
contamination), and the marketplace just points at each plugin's folder.

```text
my-skills/
├── .claude-plugin/
│   └── marketplace.json        # one marketplace; each entry's source → ./plugins/<name>
├── plugins/
│   ├── workflow-core/          # ops/meta + orchestrators (always on)
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/
│   │       ├── build-generated-system/  research-only/                   # orchestrators
│   │       └── init-system/  manage-workflow/  manage-skills/  validate-system/
│   ├── system-definition/      # stage 1
│   │   └── skills/ research-industry/  synthesize-spec/  plan-system/  sync-backlog/
│   ├── architecture/           # stage 2
│   │   └── skills/ design-architecture/  dotnet-architecture/
│   └── development/            # stage 3
│       └── skills/ agent-framework-csharp/  aspire/  entity-framework-core/
│                   dotnet-aspire-base/  pluggable-connectors/  build-system/
│                   work-next-issue/  verify-runtime/
├── AUTHORING.md                # how to add a new skill (the reusable template)
├── LICENSE                     # MIT
├── NOTICES.md                  # upstream attribution
└── README.md                   # this file
```

The shared GitHub playbook lives at
[`plugins/workflow-core/skills/init-system/references/github-ops.md`](plugins/workflow-core/skills/init-system/references/github-ops.md);
the `workflow.json` schema (including the `github` block) lives at
[`plugins/workflow-core/skills/init-system/references/ops-safety.md`](plugins/workflow-core/skills/init-system/references/ops-safety.md).
Because plugins install in isolation, skills reference siblings in the **same** plugin
by relative path and skills in **other** plugins by slash command (`/plugin:skill`).

## Adding more skills

Follow [AUTHORING.md](AUTHORING.md) — the canonical `SKILL.md` template and
checklist. A skill lives under its owning plugin (`plugins/<plugin>/skills/<name>/`);
it is auto-discovered, so there's no `skills` array to maintain.

## Provenance

The `system-definition`, `architecture`, `workflow-core`, and several
`development` skills originate from the author's `TheWorkflow` plugin and were
consolidated here (their persona / protocol / format layers inlined). See
[NOTICES.md](NOTICES.md).

## License

MIT — see [LICENSE](LICENSE). Upstream attribution is in [NOTICES.md](NOTICES.md).
