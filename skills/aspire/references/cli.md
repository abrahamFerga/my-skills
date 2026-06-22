# Aspire CLI reference

Scope: the full `aspire` command surface in 13.x, how to install it, and the flags that make it usable from scripts, CI, and coding agents.

## Install

The `aspire` CLI is distributed independently of the integration packages. Pick one method.

```bash
# Script installer (documented default) — installs the latest stable build:
curl -sSL https://aspire.dev/install.sh | bash             # macOS / Linux

# Windows PowerShell:
irm https://aspire.dev/install.ps1 | iex

# As a .NET global tool (cross-platform; good for CI images):
dotnet tool install -g Aspire.Cli
# update later with: dotnet tool update -g Aspire.Cli

# Package managers also publish it: npm, WinGet, Homebrew, NuGet.
```

Quality channels are selectable with the script installer:

```bash
curl -sSL https://aspire.dev/install.sh | bash -s -- -q staging   # or: -q dev
# PowerShell: iex "& { $(irm https://aspire.dev/install.ps1) } -Quality staging"
```

Requirements: **.NET SDK 10.0.100 or later** (enforced since 13.0) and a container runtime (Docker Desktop or Podman) for running containerized resources.

```bash
aspire --version          # expect 13.4.x
aspire doctor             # checks SDK version, container runtime, dev certs, etc.
```

## Command surface (13.x)

| Command | What it does |
|---------|--------------|
| `aspire new` | Interactive-first scaffolding. Creates one or more Aspire projects from curated starter templates; installs/updates the templates first. |
| `aspire init` | Adds Aspire support (AppHost + ServiceDefaults) to an existing repo or workspace. |
| `aspire run` | Finds the AppHost (searches cwd, then subdirs), ensures dev HTTPS certs, builds the AppHost and its resources, starts everything, and opens the dashboard. |
| `aspire add <name\|id>` | Adds an official integration package to the AppHost. Omit the argument for an interactive picker. |
| `aspire update` | Updates outdated Aspire packages and templates to the current line. |
| `aspire publish` | Serializes the app model into deployable assets (Docker Compose files, Bicep, Kubernetes manifests) for downstream tooling. |
| `aspire deploy` | Runs the deployment pipeline: builds container images, pushes them, and deploys resources to the target compute environment. |
| `aspire destroy` | Tears down a previously deployed environment. Accepts `--yes` to skip the confirmation prompt. |
| `aspire do` | Executes specific pipeline steps with dependency ordering and parallelism (the `aspire do` pipeline system introduced in 13.0). |
| `aspire restore` | Restores dependencies and regenerates SDK/codegen artifacts. |
| `aspire start` | Starts the AppHost in the background (detached) — useful in CI before running tests. |
| `aspire stop` | Terminates running AppHost process(es). |
| `aspire ps` | Lists running AppHost instances. Supports `--format json` for machine-readable output. |
| `aspire wait` | Blocks until a resource reaches a target status. |
| `aspire resource` | Invokes commands a resource exposes (e.g. EF Core migration commands surfaced by `Aspire.Hosting.EntityFrameworkCore`). |
| `aspire exec` | Runs a command in the context of a resource/the running app (e.g. one-off tasks against a resource). |
| `aspire describe` | Inspects resources of a running AppHost. |
| `aspire logs` | Streams logs from a running AppHost. Supports `--search` filtering. |
| `aspire export` | Packages telemetry and resource data for export. |
| `aspire otel` | Views OpenTelemetry traces/spans from the CLI. |
| `aspire doctor` | Verifies environment readiness. |
| `aspire certs` | Manages the HTTPS development certificates Aspire uses locally. |
| `aspire secret` | Manages user secrets for the AppHost. |
| `aspire config` | Reads/writes CLI configuration settings. |
| `aspire cache` | Manages the CLI's on-disk cache. |
| `aspire mcp` | Lists and calls MCP tools (Aspire ships an MCP surface for AI tooling). |
| `aspire agent` | Initializes and manages coding-agent integration. |
| `aspire docs` | Browses/searches the Aspire documentation. |

> Exact subcommands and flags evolve fast across 13.x patches. When in doubt run `aspire <command> --help`; treat the table above as the stable backbone, not an exhaustive flag list.

## Agent / CI-friendly usage

Aspire's CLI is "interactive-first", but every interactive flow can be automated:

- **Detached run for tests** — use `aspire start` (background) instead of `aspire run` (foreground/blocking), then `aspire ps` / `aspire wait` to gate on readiness, and `aspire stop` to clean up. In a test *project*, prefer `DistributedApplicationTestingBuilder` (see [testing.md](testing.md)) over driving the CLI.
- **Machine-readable output** — `aspire ps --format json` for parsing running instances; `aspire logs --search <term>` and `aspire otel --search <term>` for filtered diagnostics.
- **Non-interactive destroy/deploy** — pass `--yes` to `aspire destroy` (and where supported) to skip confirmations in pipelines.
- **Deterministic project creation** — `aspire new` accepts template/name/output arguments so you can scaffold without the interactive picker (`aspire new --help` for the current flag names).
- **Coding-agent detection** — 13.4 adds coding-agent detection to CLI telemetry; the `aspire agent` and `aspire mcp` commands exist specifically so agents can discover and invoke Aspire capabilities.

## Typical sessions

```bash
# Greenfield:
aspire new                      # scaffold
cd MyApp.AppHost
aspire add postgres             # add a backing resource
aspire run                      # run + dashboard

# Existing repo:
aspire init                     # add AppHost + ServiceDefaults
aspire add redis

# CI smoke test:
aspire start                    # background
aspire wait --resource api      # gate on readiness (or use aspire ps --format json)
# ... run tests ...
aspire stop

# Ship it:
aspire publish                  # produce assets
aspire deploy                   # build/push/deploy to the declared compute environment
```
