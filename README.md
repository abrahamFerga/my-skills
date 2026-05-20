# my-skills

Personal collection of Claude Code skills.

## Skills

| Skill | What it does |
|-------|--------------|
| [agent-framework-csharp](plugins/my-skills/skills/agent-framework-csharp/SKILL.md) | Build .NET applications with Microsoft Agent Framework — agents, tools, sessions, agent skills, memory, middleware, workflows (HITL / checkpoints / conditional edges / shared state), declarative YAML workflows, A2A and AGUI protocols, DI hosting, durable agents, and OpenTelemetry. |

## Install — Claude Code

Add this repository as a plugin marketplace:

```text
/plugin marketplace add abrahamFerga/my-skills
```

Then install the plugin:

```text
/plugin install my-skills@my-skills
```

After restarting Claude Code, view available skills:

```text
/skills
```

## Install — Cursor

The same `marketplace.json` works as a Cursor plugin marketplace. From a local
checkout you can symlink the folder into Cursor's local plugin path:

```text
~/.cursor/plugins/local/my-skills  →  this repo
```

Then restart Cursor (or run **Developer: Reload Window**).

## Install — Codex CLI

Individual skills follow the [agentskills.io](https://agentskills.io) standard
and can be installed directly with `skill-installer`:

```bash
skill-installer install https://github.com/abrahamFerga/my-skills/tree/main/plugins/my-skills/skills/agent-framework-csharp
```

## Repository layout

```text
my-skills/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace manifest (one plugin: my-skills)
├── plugins/
│   └── my-skills/
│       ├── plugin.json           # Plugin manifest
│       └── skills/
│           └── agent-framework-csharp/
│               ├── SKILL.md      # Main skill (~350 lines)
│               └── references/   # Progressive-disclosure references
│                   ├── providers.md
│                   ├── tools.md
│                   ├── agent-skills.md
│                   ├── memory.md
│                   ├── middleware.md
│                   ├── workflows.md
│                   ├── declarative.md
│                   ├── remote-agents.md
│                   └── hosting-and-observability.md
├── LICENSE                       # MIT
├── NOTICES.md                    # Upstream attribution
└── README.md                     # This file
```

## Adding more skills later

The current marketplace contains one plugin (`my-skills`) which can hold
multiple skills. To add a new skill:

1. Create `plugins/my-skills/skills/<new-skill-name>/SKILL.md` with valid frontmatter.
2. (Optional) Add reference files under `plugins/my-skills/skills/<new-skill-name>/references/`.
3. No marketplace manifest changes needed — `plugin.json` already points to the
   whole `./skills/` directory.

To split a future skill into its own plugin, add another `plugins/<plugin-name>/`
directory with its own `plugin.json`, then register it in
`.claude-plugin/marketplace.json`.

## License

MIT — see [LICENSE](LICENSE). Attribution for upstream MIT-licensed material is
in [NOTICES.md](NOTICES.md).
