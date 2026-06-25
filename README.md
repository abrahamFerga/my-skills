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
industry. (Resuming later? Just `cd` into the project and run
`/workflow-core:build-generated-system` with **no arguments** — it reads `workflow.json`
and the board, figures out which phase is next, and continues.) Claude then walks the
entire pipeline, pausing only when it needs a decision from you:

1. Creates a **public GitHub repo** + a **backlog board**.
2. Researches the industry → writes a product **spec** and **plan**.
3. Publishes the plan as **GitHub issues** (epics + features) on the board.
4. Designs the **architecture** (committed as `ARCH.md` + diagrams + ADRs).
5. **Builds the system feature by feature**, opening one **pull request per feature**.

Everything lives in the new repo: the docs are committed files, the work is tracked as
issues, and each feature lands as a reviewable PR that closes its issue.

---

## Hands-off mode

Want Claude to keep going on its own? There are two knobs — a **loop** (you drive the
cadence) and a **goal** (the project drives itself).

### Specialized agents do the work

The orchestrator no longer does everything in one context. It **delegates the heavy phases
to focused subagents** that work in their own window and report back — so the main thread
stays clean and each agent is autonomous (it reads the project state and figures out the
answers itself), while light one-time glue (init, spec, plan, publish, validate) runs inline:

| Agent | Plugin | Does |
|-------|--------|------|
| `industry-researcher` | system-definition | Research the market → `research/<industry>.md`. |
| `system-architect` | architecture | Backlog → `ARCH.md` + C4 + ADRs; mark features Ready. |
| `feature-builder` | development | Implement one Ready issue's scope, green (build + test). |
| `runtime-verifier` | development | Boot it, exercise it, read telemetry — prove it actually works. |
| `backlog-manager` | workflow-core | Select the next issue, branch, commit, open the `Closes #N` PR, move the board. |

The development loop is exactly the cycle you'd run by hand:
**backlog-manager picks → feature-builder builds → runtime-verifier proves → backlog-manager lands the PR.**

### `/loop` — you set the cadence

```text
/loop /workflow-core:build-generated-system        # drive the whole build, self-paced (no args — it resumes)
/loop /development:work-next-issue                  # just grind the dev backlog, one feature/PR per pass
```

Claude advances one phase (or one feature) per pass, re-checking what's done. Stop any time
with `Esc` (or `/loop stop`). For a continuous dev loop, **turn on auto-merge** so each
merged feature frees the next:

```bash
gh repo edit abrahamFerga/the-lawyer --enable-auto-merge
```

### `/goal` — the project sets its own latitude

Record the objective and **how unattended** the run may be, once, into `workflow.json`:

```text
/workflow-core:goal "Build the legal practice-management system" --autonomy auto
```

| Autonomy | What the agents do with outward actions (first push, PRs, board moves, merges) |
|----------|------------------------------------------------------------------------------|
| `manual` | produce local artifacts only; report what's ready to do |
| `confirm` *(default)* | do the work, but pause for a yes before each outward action |
| `auto` | proceed continuously; stop only at a real blocker or when the backlog is drained |

Under `auto`, a workflow-core **Stop hook** re-drives the build after each pass, so a single
`/loop /workflow-core:build-generated-system` runs the whole thing end to end and stops itself
when `stop_when` is reached. Only sessions actively running the build self-continue — ad-hoc work
you do in the same project is left alone; set autonomy back to `confirm` to take it off unattended
mode. A **git-safety hook** still blocks force-pushing `main` and merging PRs under
`manual`/`confirm` — autonomy raises latitude, it never removes the rails.

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
`.claude/settings.json` → `enabledPlugins`. During a full build the orchestrator keeps all four
enabled (so every phase's agent is reachable) and narrows to the active stage once the build is
done; to switch stages by hand, edit `enabledPlugins` and run `/reload-plugins`, or let
`/workflow-core:manage-skills sync` derive the set from the `stage` field.

| Stage | Enable this plugin | What it's for |
|-------|--------------------|---------------|
| **1 — System definition** | `system-definition@my-skills` | research → spec → plan → publish issue backlog |
| **2 — Architecture** | `architecture@my-skills` | architecture docs from the backlog; mark features Ready |
| **3 — Development** | `development@my-skills` | build features off the board, one PR each |
| *(always on)* | `workflow-core@my-skills` | bootstrap, repo/board, validation, the orchestrators |

GitHub is optional: if `gh` isn't available the docs are still written locally and
`workflow.json.github` is `null` — but the issues/board/PR flow is the point, so install `gh`.

---

## All the skills & agents

<details>
<summary>workflow-core — ops/meta (always on)</summary>

| Skill | Command | What it does |
|-------|---------|--------------|
| build-generated-system | `/workflow-core:build-generated-system` | **The parameterless conductor** for the full pipeline — infers the phase and delegates to agents. |
| goal | `/workflow-core:goal` | Set the run's objective + autonomy (`manual`/`confirm`/`auto`) + stop condition. |
| research-only | `/workflow-core:research-only` | Research (+ optional spec), no repo, no build. |
| init-system | `/workflow-core:init-system` | New system: config + public repo + labels + backlog board. |
| manage-workflow | `/workflow-core:manage-workflow` | Set stage/cloud, add connectors & capabilities. |
| manage-skills | `/workflow-core:manage-skills` | Declare external marketplaces; sync settings. |
| validate-system | `/workflow-core:validate-system` | Schema + secret + sync + GitHub-reachability checks. |

Plus the **backlog-manager** agent (GitHub board/PR ops) and the workflow-core **hooks** (git-safety guard, `auto` loop continuation, session orientation).
</details>

<details>
<summary>system-definition — Stage 1</summary>

| Skill | Command | What it does |
|-------|---------|--------------|
| research-industry | `/system-definition:research-industry` | Players → capability matrix → must-have / differentiator. |
| synthesize-spec | `/system-definition:synthesize-spec` | Capabilities → product spec (`SPEC.md`). |
| plan-system | `/system-definition:plan-system` | Spec → epics, modules, RBAC (`PLAN.md`). |
| sync-backlog | `/system-definition:sync-backlog` | Publish the plan as epic/feature issues on the board. |

Plus the **industry-researcher** agent — autonomous market research → `research/<industry>.md`.
</details>

<details>
<summary>architecture — Stage 2</summary>

| Skill | Command | What it does |
|-------|---------|--------------|
| design-architecture | `/architecture:design-architecture` | Backlog → `ARCH.md` + C4 + ADRs; move features to Ready. |
| dotnet-architecture | `/architecture:dotnet-architecture` | .NET/Azure realization: solution skeleton + Terraform + Actions. |

Plus the **system-architect** agent — autonomously turns the backlog into `ARCH.md` + C4 + ADRs and marks features Ready.
</details>

<details>
<summary>development — Stage 3</summary>

| Skill | Command | What it does |
|-------|---------|--------------|
| work-next-issue | `/development:work-next-issue` | **The dev loop:** sequences the agents — select → build → prove → PR, one feature in flight. |
| build-system | `/development:build-system` | Code-generation engine (Foundations, then one feature). |
| verify-runtime | `/development:verify-runtime` | Run → observe → debug → fix loop with real telemetry. |
| dotnet-aspire-base | `/development:dotnet-aspire-base` | Scaffold the .NET 10 + Aspire backbone. |
| pluggable-connectors | `/development:pluggable-connectors` | Channel/integration connector pattern. |
| aspire / entity-framework-core / agent-framework-csharp | auto + `/development:…` | Reference skills Claude uses automatically while coding. |

Plus the **feature-builder** (implements a Ready issue, green) and **runtime-verifier** (boots it and proves it works) agents — the build → prove half of the loop.
</details>

---

## Repository layout

Each plugin is a self-contained directory (its own `.claude-plugin/plugin.json` + `skills/`,
plus `agents/`, and — for workflow-core — `hooks/` + `scripts/`), so a plugin only ever
exposes its own components.

```text
my-skills/
├── .claude-plugin/marketplace.json     # one entry per plugin -> ./plugins/<name>
├── plugins/
│   ├── workflow-core/                  # always on
│   │   ├── skills/  …                  #   build-generated-system, goal, init/manage/validate
│   │   ├── agents/backlog-manager.md   #   the GitHub board/PR worker
│   │   ├── hooks/hooks.json            #   git-safety + auto-loop + session-state
│   │   └── scripts/  …                 #   node hook scripts (no jq dependency)
│   ├── system-definition/{skills,agents}/  …   # stage 1 (+ industry-researcher)
│   ├── architecture/{skills,agents}/  …        # stage 2 (+ system-architect)
│   └── development/{skills,agents}/  …          # stage 3 (+ feature-builder, runtime-verifier)
├── AUTHORING.md   LICENSE   NOTICES.md   README.md
```

The shared GitHub playbook (`gh` commands, board/label taxonomy) and the `workflow.json`
schema live under
[`plugins/workflow-core/skills/init-system/references/`](plugins/workflow-core/skills/init-system/references/).
To add a skill, follow [AUTHORING.md](AUTHORING.md).

## License

MIT — see [LICENSE](LICENSE). Attribution in [NOTICES.md](NOTICES.md).
