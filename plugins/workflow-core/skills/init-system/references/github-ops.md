# GitHub ops reference

Shared GitHub playbook for the my-skills workflow. GitHub is the **system of record** for a generated system: the project's code, its design docs (committed markdown), and its **feature backlog** (issues + a Projects v2 board) all live in one public repo. This file is the single source of truth for the repo/label/board taxonomy and the exact `gh` commands the skills use. If a command or taxonomy needs to change, change it here — do not re-inline it in a skill.

Skills that depend on this: [`init-system`](../SKILL.md) (creates the repo + board + labels), `/system-definition:sync-backlog` (publishes the backlog), `/architecture:design-architecture` (reads features, moves them to Ready), and `/development:work-next-issue` (drives issues to Done).

## Prerequisites (check once, up front)

1. **`gh` is installed and authenticated.** `gh auth status` must show a logged-in account. If not, stop and tell the user to run `gh auth login` — never attempt to authenticate for them.
2. **Token has the `project` scope.** Projects v2 commands fail without it. Check with `gh auth status` (look for `project` in *Token scopes*). If missing, instruct the user to run:

   ```bash
   gh auth refresh -s project
   ```

   The base `repo` scope (already present in a normal `gh auth login`) covers repo + issues + labels + milestones.
3. **Degrade gracefully.** If `gh` is absent or unauthenticated, a skill that would touch GitHub must **skip the GitHub steps, warn the user, and continue locally** (write `workflow.json` / docs as usual). GitHub is the management layer, not a hard dependency for producing artifacts. Record `github: null` (or omit it) in `workflow.json` so later skills know the backlog is not yet live.

The owner is the authenticated user (`abrahamFerga`); repos are created **public** (the user builds these as portfolio work). `@me` resolves to the owner for project commands.

## Repo

Repo name = `workflow.json.name` (e.g. `the-lawyer`). Full ref = `<owner>/<name>`.

```bash
# create (idempotent: if `gh repo view <owner>/<name>` succeeds, skip creation)
gh repo create <owner>/<name> --public --description "<one-line from SPEC, or the industry>"

# the generated system's working tree is its own git repo; wire the remote and push
git -C <project-path> init -b main          # if not already a repo
git -C <project-path> remote add origin https://github.com/<owner>/<name>.git
git -C <project-path> add -A && git -C <project-path> commit -m "<message>"
git -C <project-path> push -u origin main
```

Always check existence first (`gh repo view <owner>/<name> >/dev/null 2>&1`) so re-runs don't error.

## Labels (taxonomy)

Create with `gh label create <name> --color <hex> --description <text> --force` (`--force` makes it idempotent — updates if it exists). Run against the project repo (`-R <owner>/<name>`).

| Label | Color | Meaning |
|---|---|---|
| `type:epic` | `5319E7` | A capability area / build-order epic (parent of features). |
| `type:feature` | `1D76DB` | A shippable feature (the unit Stage 3 implements). |
| `type:story` | `0E8A16` | A smaller slice of a feature (optional finer grain). |
| `stage:foundations` | `B60205` | Belongs to the always-first Foundations epic (auth, multi-tenancy, OTel, RBAC, dashboard shell, connector registry). |
| `priority:p0` | `D93F0B` | Must-have, build first within its epic. |
| `priority:p1` | `FBCA04` | Should-have. |
| `priority:p2` | `C2E0C6` | Nice-to-have / deferrable. |

Status is **not** a label — it lives on the board's `Pipeline` field (below).

## Milestones (optional, per epic)

`gh` has no native milestone create; use the REST API. One milestone per epic gives a per-epic progress bar.

```bash
gh api repos/<owner>/<name>/milestones -f title="<epic title>" -f state=open -f description="<epic goal>"
# idempotent: GET repos/<owner>/<name>/milestones first; match by title; reuse its `number`
```

## Project board (Projects v2)

One board per repo, owned by the user, linked to the repo. Built-in `Status` field is left unused; we drive a custom single-select `Pipeline` field so the whole flow is gh-scriptable (the built-in Status options can't be edited via `gh`).

```bash
# create -> returns {number, id, url}; persist `number` to workflow.json github.project
gh project create --owner @me --title "<name> backlog" --format json

# show the board on the repo's Projects tab
gh project link <number> --owner @me --repo <name>

# custom fields (idempotent: field-list first, skip if present)
gh project field-create <number> --owner @me --name "Pipeline" --data-type SINGLE_SELECT \
  --single-select-options "Backlog,Ready,In Progress,In Review,Done"
gh project field-create <number> --owner @me --name "Build order" --data-type NUMBER
```

`Pipeline` progression across stages: **Backlog** (Stage 1 publishes here) → **Ready** (Stage 2 has architected it) → **In Progress** (Stage 3 working it) → **In Review** (PR open) → **Done** (PR merged / issue closed).

### Discovering IDs (required before editing item fields)

Project, field, and option IDs are stable per board — fetch once per run and reuse:

```bash
gh project view <number> --owner @me --format json --jq '.id'          # project node id
gh project field-list <number> --owner @me --format json               # fields + single-select option ids
```

From `field-list` JSON, capture: the `Pipeline` field `id` and its options' `id`s (keyed by name), and the `Build order` field `id`.

### Adding an issue to the board and setting fields

```bash
# add -> returns the item {id}
gh project item-add <number> --owner @me --url <issue-url> --format json

# set Pipeline = Backlog
gh project item-edit --id <item-id> --project-id <project-id> \
  --field-id <pipeline-field-id> --single-select-option-id <backlog-option-id>

# set Build order = N
gh project item-edit --id <item-id> --project-id <project-id> \
  --field-id <build-order-field-id> --number <N>
```

To move a card later (e.g. Stage 2 → Ready), re-run `item-edit` with the target option id. Find an existing item's id via `gh project item-list <number> --owner @me --format json` and match on the issue url/number.

## Issues

```bash
# create a feature issue with labels + (optional) milestone, return its number + url
gh issue create -R <owner>/<name> --title "<title>" --body "<body>" \
  --label type:feature --label priority:p1 --milestone "<epic title>"
```

Each issue body ends with a hidden idempotency marker so re-runs match instead of duplicate:

```text
<!-- mskey: <kind>/<slug> -->
```

where `<kind>` is `epic|feature|story` and `<slug>` is a stable kebab id (e.g. `feature/matter-intake`).

### Idempotency (match before create)

Before creating any issue, list existing ones and match on the `mskey` marker (fall back to exact title):

```bash
gh issue list -R <owner>/<name> --state all --label type:feature --limit 200 \
  --json number,title,body
```

If a matching `mskey` is found, **update** that issue (`gh issue edit <n> -R <owner>/<name> --body <new>`) rather than create a new one. Never create a second issue with the same `mskey`.

### Sub-issues (epic → features)

Link features under their epic using the native sub-issues REST API. The child's `sub_issue_id` is the issue's **node database id** (`.id`), *not* its number.

```bash
child_id=$(gh api repos/<owner>/<name>/issues/<child-number> --jq '.id')
gh api --method POST repos/<owner>/<name>/issues/<epic-number>/sub_issues -F sub_issue_id="$child_id"
```

Idempotent: `gh api repos/<owner>/<name>/issues/<epic-number>/sub_issues --jq '.[].number'` lists current children; skip if already linked. If the sub-issues API is unavailable, fall back to a task list in the epic body (`- [ ] #<child-number>`).

## PR flow (Stage 3)

```bash
git -C <project-path> switch -c feat/<issue-number>-<slug>
# ... implement ...
gh pr create -R <owner>/<name> --fill --body "Closes #<issue-number>"
```

`Closes #<n>` auto-closes the issue on merge. The board's built-in "Item closed → Done" workflow (enabled by default on `gh`-created boards) archives the card; if it isn't, move it explicitly with `item-edit` to the `Done` option.

## Guardrails

- **Never commit secrets.** The secret-pattern scan in [`ops-safety.md`](ops-safety.md) applies to issue/PR bodies and committed files alike.
- **Public repos:** assume everything pushed is world-readable and indexed. Do not push tenant data, real tokens, or customer names.
- **Idempotent always:** every create checks existence first (`--force` for labels, `mskey`/title match for issues, `field-list` for fields, `repo view`/`project list` for repo/board). Re-running a stage must converge, not duplicate.
- **Confirm before outward actions:** creating the repo and pushing are visible, hard-to-undo, outward-facing operations — confirm with the user before the first push of a new project unless they've said to proceed.
