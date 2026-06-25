# Ops safety reference

Shared rules for the workflow-core ops skills ([`init-system`](../SKILL.md), [`manage-workflow`](../../manage-workflow/SKILL.md), [`manage-skills`](../../manage-skills/SKILL.md), [`validate-system`](../../validate-system/SKILL.md)). This is the single source of truth for the `workflow.json` shape, the secret-pattern table, and the path-safety / atomic-write / `.claude/settings.json` merge rules. If any of these rules need to change, change them here — do not re-inline them in a skill.

## `workflow.json` structure (authoritative)

`workflow.json` lives at the project root. The shape is intentionally small — keep it that way. Indent with 2 spaces; end with a trailing newline. No top-level keys beyond those listed below are permitted — unknown keys are an error (forward-incompatibility should be loud, not silent).

Top-level fields:

| Field | Required | Type | Rule |
|---|---|---|---|
| `name` | yes | string | Kebab-case, must start with `the-`. Pattern: `^the-[a-z][a-z0-9-]{0,38}$`. Permanent — renaming a system is a separate, painful operation. |
| `industry` | yes | string | Lowercase short phrase, 2–64 chars. |
| `stage` | no (default `system-definition`) | string | One of `system-definition`, `architecture`, `development`. Anything else: refuse. Drives the `.claude/settings.json` enabledPlugins map (see stage -> enabledPlugins below). |
| `cloud` | no (default `none`) | string | One of `azure`, `aws`, `none`. Anything else: refuse. |
| `connectors` | no (default `[]`) | string[] | Each entry kebab-case, pattern `^[a-z][a-z0-9-]{0,38}$`, unique within the array. |
| `capabilities` | no (default `[]`) | object[] | Each `{ "name": <kebab>, "provider"?: <2–64 chars> }`; `name` pattern `^[a-z][a-z0-9-]{0,38}$`. |
| `github` | no (default absent) | object \| null | The system-of-record on GitHub: repo + backlog board. Absent/`null` means the project is local-only (GitHub not yet wired). Shape below. |
| `goal` | no (default absent) | object | The autonomous-run policy: objective + how much latitude the agents have + when to stop. Read by the orchestrator and the loop-continuation hook. Shape below. |
| `skills` | yes | object | `{ "self": Marketplace, "external": ExternalMarketplace[] }`. |

`skills.self` is an invariant — never mutated by any ops skill. It is always:

```json
{
  "marketplace": "my-skills",
  "repo": "abrahamFerga/my-skills",
  "plugins": ["workflow-core", "system-definition", "architecture", "development"]
}
```

That is: `marketplace` = `my-skills`, `repo` = `abrahamFerga/my-skills`, and `plugins` = the four stage plugins `workflow-core`, `system-definition`, `architecture`, `development` (in that order).

`skills.external[]` entries are `{ "marketplace": <ref>, "plugins": [<plugin>...], "reason"?: <8–280 chars> }`:

| Field | Required | Rule |
|---|---|---|
| `marketplace` | yes | One of the three allowed ref forms (see Marketplace ref format below). |
| `plugins` | yes | At least one; each matches `^[a-z][a-z0-9-]{0,63}$`; unique within the array. |
| `reason` | no, strongly recommended | 8–280 chars. Free-text justification; read by humans, ignored by tooling. |

### `github` block

When the project is wired to GitHub (the normal case once [`init-system`](../SKILL.md) has run with `gh` available), `workflow.json.github` is:

```json
{
  "repo": "abrahamFerga/the-lawyer",
  "project": 7,
  "visibility": "public"
}
```

| Field | Required | Rule |
|---|---|---|
| `repo` | yes (when block present) | `<owner>/<name>`, pattern `^[a-z0-9][a-z0-9-]{0,38}/the-[a-z][a-z0-9-]{0,38}$`. `name` segment equals the top-level `name`. |
| `project` | no | Projects v2 board **number** (positive integer), or `null` until the board exists. |
| `visibility` | no (default `public`) | One of `public`, `private`. |

No keys beyond these three. The full repo/label/board/issue taxonomy and the `gh` command playbook live in [`github-ops.md`](github-ops.md) — `ops-safety.md` owns only the **shape** of this block; `github-ops.md` owns the **operations**.

### `goal` block

The autonomous-run policy. Absent by default — a project with no `goal` runs in the conservative default posture (the agents pause for every human decision). [`goal`](../../goal/SKILL.md) is the only skill that writes it; the orchestrator (`build-generated-system`) and the loop-continuation hook read it. Shape:

```json
{
  "objective": "Build the legal practice-management system end to end.",
  "autonomy": "confirm",
  "stop_when": "backlog-drained"
}
```

| Field | Required | Rule |
|---|---|---|
| `objective` | yes (when block present) | 8–280 chars. Free-text statement of what the run is for. Lets a brand-new build start from the goal alone (no `industry` arg). Secret-scanned like every other string. |
| `autonomy` | no (default `confirm`) | One of `manual`, `confirm`, `auto`. `manual` = advise only, take no outward action; `confirm` = act but pause before each outward/irreversible action (first push, PR, board move); `auto` = proceed through outward actions without pausing, stopping only at a genuine blocker or `stop_when`. Anything else: refuse. |
| `stop_when` | no (default `backlog-drained`) | One of `backlog-drained` (stop when every feature is Done), `stage-complete` (stop at the end of the current stage), `never` (run until externally stopped). Anything else: refuse. Bounds the loop-continuation hook so `auto` can't run unbounded. |

No keys beyond these three. `autonomy: auto` is the only setting that lets the loop-continuation hook keep a session going past a natural stop — it is opt-in for exactly that reason, and `stop_when` is its hard ceiling.

### Marketplace ref format

The `marketplace` field accepts exactly three forms — anything else is a security error (a malicious entry can reach the developer's machine on next open of Claude Code):

1. **GitHub `owner/repo[#tag]`** — pattern `^[a-z0-9][a-z0-9-]{0,38}/[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}(#[a-zA-Z0-9._/-]{1,128})?$`. Tag pinning recommended (warn when absent). Classified as `github`.
2. **Explicit https git URL** — pattern `^https://[a-z0-9.-]+(/[A-Za-z0-9._~%/-]*)?(\.git)?(#[A-Za-z0-9._/-]+)?$`. Classified as `url`.
3. **Local relative path** — pattern `^\./[A-Za-z0-9._/-]+$`. Development use only. Classified as `local`.

Rejected: SSH (`git@…`), `file://`, FTP, implicit-protocol URLs.

### `.claude/settings.json` generated shape

```json
{
  "extraKnownMarketplaces": {
    "<marketplace-ref>": {
      "source": { "source": "github" | "url" | "local", "repo" | "url": "<value>" }
    }
  },
  "enabledPlugins": {
    "<plugin>@<marketplace-ref>": true | false
  }
}
```

Classify each marketplace by ref prefix: `https://` → `url`, `./` → `local`, otherwise `github`. One `extraKnownMarketplaces` key per marketplace. The self-marketplace `my-skills` is always declared in `extraKnownMarketplaces` (`{ "source": { "source": "github", "repo": "abrahamFerga/my-skills" } }`).

`enabledPlugins` keys come from two sources:

- The four self stage plugins (`workflow-core`, `system-definition`, `architecture`, `development`), all on `my-skills`, whose `true`/`false` value is derived from the `stage` field per the stage -> enabledPlugins mapping below.
- One key per external plugin, formatted `<plugin>@<marketplace-ref>`, value `true`.

### stage -> enabledPlugins mapping

This is the shared spec the ops skills follow when deriving `.claude/settings.json` from `workflow.json`. `workflow-core@my-skills` is **always** `true`; the active stage plugin is `true` and the other two stage plugins are `false`:

| stage | `workflow-core` | `system-definition` | `architecture` | `development` |
|---|---|---|---|---|
| `system-definition` | true | true | false | false |
| `architecture` | true | false | true | false |
| `development` | true | false | false | true |

All four keys use the `@my-skills` suffix (e.g. `system-definition@my-skills`). `manage-skills` always **generates** exactly this set when it syncs (the active stage's plugins `true`, the others `false`); changing the `stage` field and re-syncing produces this exact map.

**Build-mode superset (validator tolerance).** A reader/validator ([`validate-system`](../../validate-system/SKILL.md)) requires only that the *active stage's* plugins are enabled — `workflow-core` **and** the stage's plugin must be `true`. **Extra** stage plugins being `true` is **allowed** (a non-fatal note), because an orchestrated full build ([`build-generated-system`](../../build-generated-system/SKILL.md)) keeps all four enabled so every phase's agent stays reachable without a mid-loop `/reload-plugins`. So: a *missing* required plugin (or `workflow-core` disabled) is a failure; an *extra* enabled stage plugin is not. The generator stays exact; only the check tolerates the superset.

## Secret-pattern detection table

Before writing any file, scan every string value (nested too) against the patterns below. On any match, refuse and print only the *name* of the matched pattern — never the matched value (echoing the value defeats the purpose). The user must use a secret-store reference instead of an embedded value.

| Pattern | Regex |
|---|---|
| AWS Access Key ID | `AKIA[0-9A-Z]{16}` |
| GitHub personal access token | `gh[ps]_[A-Za-z0-9]{36}` |
| GitHub fine-grained PAT | `github_pat_[A-Za-z0-9_]{82}` |
| Slack token | `xox[baprs]-[A-Za-z0-9-]{10,}` |
| Stripe secret key | `sk_(test\|live)_[0-9a-zA-Z]{24,}` |
| OpenAI API key | `sk-[A-Za-z0-9]{32,}` |
| Anthropic API key | `sk-ant-[A-Za-z0-9_-]{20,}` |
| Google API key | `AIza[0-9A-Za-z_-]{35}` |
| JWT | `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` |
| Private key block | `-----BEGIN [A-Z ]*PRIVATE KEY-----` |
| Azure storage connection string | `DefaultEndpointsProtocol=https?;AccountName=[^;]+;AccountKey=[^;]+` |
| High-entropy blob (heuristic) | Any `[A-Za-z0-9+/=_-]{32,}` substring with Shannon entropy ≥ 4.5 bits/char |

## Path safety

- Resolve every user-supplied path to an absolute path.
- Reject `..` segments, null bytes, and characters invalid for the host filesystem before resolving.
- Never write outside the resolved target path — a `..` traversal in any input is an immediate stop.
- Follow symlinks for containment checks.

## Atomic writes

- Build the complete file contents in memory, then write in a single operation. Never stream partial updates.
- Create parent directories first.
- End every file with a trailing newline.
- A torn `workflow.json` or `.claude/settings.json` can brick a developer's Claude Code session — atomicity is not optional.

## `.claude/settings.json` merge rules

- Writes to `.claude/settings.json` are **merges, not replaces**. Only `extraKnownMarketplaces` and `enabledPlugins` are owned by these skills — preserve every other key (theme, etc.).
- Read the existing `.claude/settings.json` if it exists; create the directory + file if not.
- Replace only the two owned keys with freshly derived values; leave unrelated keys byte-for-byte intact.
- Full-replacing the file clobbers the user's theme and other settings — always merge.
