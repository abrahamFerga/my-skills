# my-skills

A single Claude Code marketplace of **stage-scoped plugins** for agentic .NET
development. Instead of one big plugin whose 18 skill descriptions all load into
every session, the skills are split into four plugins you enable per phase — so
each stage carries only the context it needs.

## Pick tooling by stage

| Stage | Plugin | Enable | What it gives you |
|-------|--------|--------|-------------------|
| **System definition** — decide *what* to build | `system-definition@my-skills` | stage 1 (kickoff) | research an industry → spec → plan/RBAC |
| **Architecture** — decide the *shape*, once | `architecture@my-skills` | stage 2 (once) | ARCH.md + C4 + ADRs, .NET/Azure solution skeleton, Terraform, GitHub Actions |
| **Development** — continuous coding | `development@my-skills` | stage 3 (most work) | Aspire / EF Core / Agent Framework references + backbone, connectors, build, verify |
| *(all stages)* — ops/meta | `workflow-core@my-skills` | always | bootstrap & manage `workflow.json`, marketplaces, validation |

Switching stage is one declarative edit (see [Enable plugins per stage](#enable-plugins-per-stage)). Disabling a stage plugin removes all of its skills' descriptions from context — the core noise-control lever.

## Skills by plugin

### `workflow-core` — ops/meta (always on)

| Skill | Slash command | What it does |
|-------|---------------|--------------|
| [build-generated-system](skills/build-generated-system/SKILL.md) | `/workflow-core:build-generated-system` | **Orchestrator** — drives the full pipeline bootstrap → research → spec → plan → design → compose → build → validate. |
| [research-only](skills/research-only/SKILL.md) | `/workflow-core:research-only` | **Orchestrator** — industry research (+ optional spec), no build. |
| [init-system](skills/init-system/SKILL.md) | `/workflow-core:init-system` | Bootstrap a new system (`workflow.json` + `.claude/settings.json`). |
| [manage-workflow](skills/manage-workflow/SKILL.md) | `/workflow-core:manage-workflow` | Set cloud target, add/remove connectors & capabilities. |
| [manage-skills](skills/manage-skills/SKILL.md) | `/workflow-core:manage-skills` | Declare/remove external marketplaces; sync `.claude/settings.json`. |
| [validate-system](skills/validate-system/SKILL.md) | `/workflow-core:validate-system` | Schema + secret + sync-state check. |

### `system-definition` — stage 1 (enable at kickoff)

| Skill | Slash command | What it does |
|-------|---------------|--------------|
| [research-industry](skills/research-industry/SKILL.md) | `/system-definition:research-industry` | Top players → capability matrix → must-have / differentiator / skip. |
| [synthesize-spec](skills/synthesize-spec/SKILL.md) | `/system-definition:synthesize-spec` | Capability matrix → product spec (SPEC.md). |
| [plan-system](skills/plan-system/SKILL.md) | `/system-definition:plan-system` | Spec → epics, modules, RBAC (PLAN.md). |

### `architecture` — stage 2 (enable once)

| Skill | Slash command | What it does |
|-------|---------------|--------------|
| [design-architecture](skills/design-architecture/SKILL.md) | `/architecture:design-architecture` | Plan → ARCH.md + C4 diagrams + ADRs (cloud-agnostic). |
| [dotnet-architecture](skills/dotnet-architecture/SKILL.md) | `/architecture:dotnet-architecture` | .NET/Azure realization: solution skeleton + Terraform + GitHub Actions. |

### `development` — stage 3 (default on)

| Skill | Invocation | What it does |
|-------|------------|--------------|
| [agent-framework-csharp](skills/agent-framework-csharp/SKILL.md) | auto + `/development:agent-framework-csharp` | Microsoft Agent Framework reference. |
| [aspire](skills/aspire/SKILL.md) | auto + `/development:aspire` | Aspire 13.x orchestration reference. |
| [entity-framework-core](skills/entity-framework-core/SKILL.md) | auto + `/development:entity-framework-core` | EF Core 10 data-layer reference. |
| [dotnet-aspire-base](skills/dotnet-aspire-base/SKILL.md) | `/development:dotnet-aspire-base` | Scaffold the .NET 10 + Aspire solution backbone. |
| [pluggable-connectors](skills/pluggable-connectors/SKILL.md) | `/development:pluggable-connectors` | On-demand channel/integration pattern. |
| [build-system](skills/build-system/SKILL.md) | `/development:build-system` | Generate the system epic by epic. |
| [verify-runtime](skills/verify-runtime/SKILL.md) | `/development:verify-runtime` | Install testability infra + run → observe → debug → fix loop. |

> **Noise control:** the three reference skills (Agent Framework, Aspire, EF Core) are model-invokable so Claude reaches for them automatically while coding. Every other skill sets `disable-model-invocation: true` — it's a deliberate `/plugin:skill` action and its description is **not** loaded into context, so it costs nothing until you run it.

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

> On Claude Code ≥ 2.1.154 you can add `"defaultEnabled": false` to the
> `system-definition` and `architecture` marketplace entries so they install
> disabled until opted in. This repo omits it for compatibility with older
> versions — control enablement via `enabledPlugins` instead (below).

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
`stage` field — see [manage-skills](skills/manage-skills/SKILL.md).

## Install — Cursor / Copilot / Codex

These skills follow the [agentskills.io](https://agentskills.io) standard, so the
`SKILL.md` files work in any compatible tool:

- **Cursor:** the same `marketplace.json` works as a Cursor plugin marketplace; symlink the repo into `~/.cursor/plugins/local/my-skills`.
- **GitHub Copilot:** Copilot reads the same `SKILL.md` files from `.claude/skills/`. It has no per-project `enabledPlugins`, so stage-scope there by which plugin a team vendors. Skill bodies are kept tool-agnostic; only the `workflow-core` skills assume Claude Code mechanics.
- **Codex CLI:** install a single skill directly with `skill-installer`:

  ```bash
  skill-installer install https://github.com/abrahamFerga/my-skills/tree/main/skills/aspire
  ```

## Repository layout

```text
my-skills/
├── .claude-plugin/
│   └── marketplace.json   # one marketplace, FOUR plugin entries (source "./", strict false, skills subset)
├── skills/                # all 18 skills, one folder each (SKILL.md [+ references/ + assets/])
│   ├── build-generated-system/  research-only/                              # workflow-core (orchestrators)
│   ├── init-system/  manage-workflow/  manage-skills/  validate-system/      # workflow-core (ops)
│   ├── research-industry/  synthesize-spec/  plan-system/                    # system-definition
│   ├── design-architecture/  dotnet-architecture/                           # architecture
│   ├── agent-framework-csharp/  aspire/  entity-framework-core/             # development (references)
│   └── dotnet-aspire-base/  pluggable-connectors/  build-system/  verify-runtime/  # development
├── AUTHORING.md           # how to add a new skill (the reusable template)
├── LICENSE                # MIT
├── NOTICES.md             # upstream attribution
└── README.md              # this file
```

A single plugin entry loads only its listed skills (`"source": "./"` +
`"strict": false` + a `"skills"` subset), so all 18 skills share one tree with no
duplication and no per-plugin manifests.

## Adding more skills

Follow [AUTHORING.md](AUTHORING.md) — the canonical `SKILL.md` template and
checklist. After writing the skill, add its folder to the appropriate plugin's
`skills` array in `.claude-plugin/marketplace.json` (or create a new stage plugin).

## Provenance

The `system-definition`, `architecture`, `workflow-core`, and several
`development` skills originate from the author's `TheWorkflow` plugin and were
consolidated here (their persona / protocol / format layers inlined). See
[NOTICES.md](NOTICES.md).

## License

MIT — see [LICENSE](LICENSE). Upstream attribution is in [NOTICES.md](NOTICES.md).
