# my-skills

Claude Code plugins that build a complete, enterprise-grade **.NET 10** system for you
— from an industry name to a working repo — and manage the whole thing on **GitHub**
(issues, a backlog board, and one pull request per feature).

You mostly type **one command**. Here's how.

---

## Quick start

**1. One-time setup** (in any Claude Code session):

```text
/plugin marketplace add abrahamFerga/my-skills
/plugin install workflow-core@my-skills
/plugin install system-definition@my-skills
/plugin install architecture@my-skills
/plugin install development@my-skills
```

You also need the [GitHub CLI](https://cli.github.com/) signed in, with the project scope:

```bash
gh auth login
gh auth refresh -s project    # lets the workflow create the backlog board
```

**2. Build a whole system — one command:**

```text
/workflow-core:build-generated-system the-lawyer legal
```

That's it. `the-lawyer` is the project name (must start with `the-`); `legal` is the
industry. Claude then walks the entire pipeline, pausing only when it needs a decision
from you:

1. Creates a **public GitHub repo** + a **backlog board**.
2. Researches the industry → writes a product **spec** and **plan**.
3. Publishes the plan as **GitHub issues** (epics + features) on the board.
4. Designs the **architecture** (committed as `ARCH.md` + diagrams + ADRs).
5. **Builds the system feature by feature**, opening one **pull request per feature**.

Everything lives in the new repo: the docs are committed files, the work is tracked as
issues, and each feature lands as a reviewable PR that closes its issue.

---

## Hands-off mode (`/loop`)

Want Claude to keep going on its own? Use `/loop`.

**Drive the whole build, self-paced:**

```text
/loop /workflow-core:build-generated-system the-lawyer legal
```

Claude advances through the phases on its own, re-checking what's done and continuing —
it only stops to ask you the unavoidable decisions (e.g. answering the research
questions, picking a cloud).

**Just grind through the development backlog** (after the architecture stage), one
feature per pass until the board is empty:

```text
/loop /development:work-next-issue
```

Each pass takes the next *Ready* feature, branches, implements it, runs the tests, and
opens a `Closes #N` PR. For a truly continuous loop, **turn on auto-merge** on the repo
(or merge PRs as they arrive) so each merged feature frees the next one:

```bash
gh repo edit abrahamFerga/the-lawyer --enable-auto-merge
```

Stop the loop any time with `Esc` (or `/loop stop`).

---

## Prefer to go step by step?

Run the stages yourself, in order. Each command is one phase:

```text
# Stage 1 — decide WHAT to build (enable system-definition)
/workflow-core:init-system the-lawyer legal      # repo + board + config
/system-definition:research-industry legal        # market + capabilities
/system-definition:synthesize-spec                 # -> SPEC.md
/system-definition:plan-system                     # -> PLAN.md (epics + features)
/system-definition:sync-backlog                    # -> GitHub issues on the board

# Stage 2 — decide the SHAPE once (enable architecture)
/architecture:design-architecture                  # -> ARCH.md, moves features to "Ready"

# Stage 3 — build it (enable development)
/development:work-next-issue                        # implement the next feature -> PR
#   ...repeat (or /loop) until the board is empty
```

`/workflow-core:research-only legal` is a no-commitment variant: just research (+ optional
spec), no repo, no build.

---

## How the stages work

The plugins are **stage-scoped** so each phase loads only the context it needs. The active
stage is recorded in your project's `workflow.json` and reflected in
`.claude/settings.json` → `enabledPlugins`. The orchestrator flips stages for you; to do it
by hand, edit `enabledPlugins` and run `/reload-plugins`, or let
`/workflow-core:manage-skills sync` derive it from the `stage` field.

| Stage | Enable this plugin | What it's for |
|-------|--------------------|---------------|
| **1 — System definition** | `system-definition@my-skills` | research → spec → plan → publish issue backlog |
| **2 — Architecture** | `architecture@my-skills` | architecture docs from the backlog; mark features Ready |
| **3 — Development** | `development@my-skills` | build features off the board, one PR each |
| *(always on)* | `workflow-core@my-skills` | bootstrap, repo/board, validation, the orchestrators |

GitHub is optional: if `gh` isn't available the docs are still written locally and
`workflow.json.github` is `null` — but the issues/board/PR flow is the point, so install `gh`.

---

## All the skills

<details>
<summary>workflow-core — ops/meta (always on)</summary>

| Skill | Command | What it does |
|-------|---------|--------------|
| build-generated-system | `/workflow-core:build-generated-system` | **The one-command orchestrator** for the full pipeline. |
| research-only | `/workflow-core:research-only` | Research (+ optional spec), no repo, no build. |
| init-system | `/workflow-core:init-system` | New system: config + public repo + labels + backlog board. |
| manage-workflow | `/workflow-core:manage-workflow` | Set stage/cloud, add connectors & capabilities. |
| manage-skills | `/workflow-core:manage-skills` | Declare external marketplaces; sync settings. |
| validate-system | `/workflow-core:validate-system` | Schema + secret + sync + GitHub-reachability checks. |
</details>

<details>
<summary>system-definition — Stage 1</summary>

| Skill | Command | What it does |
|-------|---------|--------------|
| research-industry | `/system-definition:research-industry` | Players → capability matrix → must-have / differentiator. |
| synthesize-spec | `/system-definition:synthesize-spec` | Capabilities → product spec (`SPEC.md`). |
| plan-system | `/system-definition:plan-system` | Spec → epics, modules, RBAC (`PLAN.md`). |
| sync-backlog | `/system-definition:sync-backlog` | Publish the plan as epic/feature issues on the board. |
</details>

<details>
<summary>architecture — Stage 2</summary>

| Skill | Command | What it does |
|-------|---------|--------------|
| design-architecture | `/architecture:design-architecture` | Backlog → `ARCH.md` + C4 + ADRs; move features to Ready. |
| dotnet-architecture | `/architecture:dotnet-architecture` | .NET/Azure realization: solution skeleton + Terraform + Actions. |
</details>

<details>
<summary>development — Stage 3</summary>

| Skill | Command | What it does |
|-------|---------|--------------|
| work-next-issue | `/development:work-next-issue` | **The dev loop:** next Ready issue → branch → build → PR. |
| build-system | `/development:build-system` | Code-generation engine (Foundations, then one feature). |
| verify-runtime | `/development:verify-runtime` | Run → observe → debug → fix loop with real telemetry. |
| dotnet-aspire-base | `/development:dotnet-aspire-base` | Scaffold the .NET 10 + Aspire backbone. |
| pluggable-connectors | `/development:pluggable-connectors` | Channel/integration connector pattern. |
| aspire / entity-framework-core / agent-framework-csharp | auto + `/development:…` | Reference skills Claude uses automatically while coding. |
</details>

---

## Repository layout

Each plugin is a self-contained directory (its own `.claude-plugin/plugin.json` + `skills/`),
so a plugin only ever exposes its own skills.

```text
my-skills/
├── .claude-plugin/marketplace.json     # one entry per plugin -> ./plugins/<name>
├── plugins/
│   ├── workflow-core/skills/   …       # always on
│   ├── system-definition/skills/  …    # stage 1
│   ├── architecture/skills/  …         # stage 2
│   └── development/skills/  …          # stage 3
├── AUTHORING.md   LICENSE   NOTICES.md   README.md
```

The shared GitHub playbook (`gh` commands, board/label taxonomy) and the `workflow.json`
schema live under
[`plugins/workflow-core/skills/init-system/references/`](plugins/workflow-core/skills/init-system/references/).
To add a skill, follow [AUTHORING.md](AUTHORING.md).

## License

MIT — see [LICENSE](LICENSE). Attribution in [NOTICES.md](NOTICES.md).
