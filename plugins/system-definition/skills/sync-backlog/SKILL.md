---
name: sync-backlog
description: >
  Publish the feature backlog to GitHub: read PLAN.md (epics + the capabilities each
  delivers) and SPEC.md (for acceptance criteria), then idempotently create/update epic
  and feature issues, link features under their epic as sub-issues, and place every item
  on the project's Projects v2 board in the Backlog column with its Build order. The
  bridge from local planning docs to GitHub as the system-of-record. Re-runnable: matches
  existing issues by a hidden marker and updates instead of duplicating.
  USE FOR: turning a finished PLAN.md into GitHub issues + a populated backlog board;
  re-syncing the backlog after the plan changes.
  DO NOT USE FOR: writing the plan (use ../plan-system/SKILL.md); creating the repo/board/labels
  (use /workflow-core:init-system); architecting features (use /architecture:design-architecture);
  implementing issues (use /development:work-next-issue).
license: MIT
disable-model-invocation: true
---

# sync-backlog

The last step of Stage 1. Everything before it (research → spec → plan) produces local
markdown; this skill projects the plan into GitHub, where the rest of the workflow manages
work. After it runs, the project's repo has an **epic + feature issue tree** and a **Projects v2
board** with every feature in the **Backlog** column — the queue Stage 2 architects and Stage 3
implements.

It is an action/ops skill: idempotent, adversarial about not duplicating, and it never invents
scope — every issue traces back to an epic and capability already written in `PLAN.md`/`SPEC.md`.

## When to Use

- `PLAN.md` is finished and validated, and you want the backlog live in GitHub.
- The plan changed and you need to re-sync (add new features, update bodies) without creating duplicates.

## Stop Signals

- **No `workflow.json.github` (repo/board not created yet)** → follow `/workflow-core:init-system` first (it provisions the repo, labels, and board).
- **Writing or revising the plan itself** → use [`plan-system`](../plan-system/SKILL.md).
- **`gh` not authenticated / missing `project` scope** → stop and tell the user to run `gh auth login` and `gh auth refresh -s project`; do not partially publish.

## Inputs

| Input | Required | Description |
|---|---|---|
| `PLAN.md` | Yes | Source of the epic list and, per epic, the *Capabilities (from SPEC)* that become features. |
| `SPEC.md` | Yes | Source of acceptance criteria — persona tasks, capability definitions, success metrics — folded into each feature's body. |
| `workflow.json` | Yes | Must contain a `github` block with `repo` and a `project` board number. The owner/name and board come from here. |

## Backlog model (what gets created)

| PLAN/SPEC element | GitHub object | Labels | Board |
|---|---|---|---|
| Each epic in *Epics (in build order)* | `type:epic` issue (+ optional milestone) | `type:epic`; `stage:foundations` on epic 1 | not boarded (epics are containers) |
| Each *Capability (from SPEC)* under an epic | `type:feature` issue, **sub-issue** of its epic | `type:feature`; `priority:p0/p1/p2`; `stage:foundations` if under Foundations | added to **Backlog**, `Build order` set |
| Epic order × capability order | — | — | `Build order` = epic index × 100 + capability index (Foundations first) |

Differentiators (last epic) get `priority:p2`; must-haves in the Foundations epic get `priority:p0`; other must-haves `priority:p1`. The exact label table and all `gh` commands are defined by `/workflow-core:init-system`'s `github-ops` reference; the essentials are inlined below so this skill is self-contained.

## Workflow

1. **Load and verify inputs.** Read `workflow.json`; require `github.repo` and an integer `github.project`. If `github` is `null`, stop with the init-system pointer. Read `PLAN.md` and `SPEC.md`; if either is missing, stop. Set `OWNER/NAME` and `PROJECT` from the github block.
2. **Verify `gh`.** `gh auth status` must succeed with the `project` scope (Stage 1 stop-signal otherwise). Confirm the repo and board resolve: `gh repo view OWNER/NAME` and `gh project view PROJECT --owner @me`.
3. **Parse the epics.** From `## Epics (in build order)`, extract each epic's name, the one-line "what it delivers", its *Capabilities (from SPEC)* list, and *Depends on*. Preserve order (index 1..N; Foundations is 1).
4. **Derive features.** Each capability under an epic is a feature. Pull its acceptance criteria from `SPEC.md` (the persona task(s) it serves + the capability's must-have/differentiator framing + any success metric it moves). Assign a stable slug `feature/<kebab-capability>` and the epic slug `epic/<kebab-epic>`.
5. **Secret-scan every issue body** against the secret-pattern table (same table `init-system` uses). On any match, refuse to create that issue — a backlog is public.
6. **Upsert epic issues.** For each epic, match an existing issue by its `mskey` marker; create if absent, else edit the body. Apply labels (`type:epic`, plus `stage:foundations` for epic 1).
7. **Upsert feature issues.** For each feature, match by `mskey`; create or edit. Apply `type:feature`, the derived `priority:*`, and `stage:foundations` when under Foundations.
8. **Link sub-issues.** Attach each feature under its epic via the sub-issues API (skip if already linked).
9. **Board the features.** Add each feature issue to project `PROJECT`, set `Pipeline = Backlog` and `Build order` per the model above. Epics are not boarded. Skip items already present (match by issue url).
10. **Report.** Print a tree: each epic → its features, with issue numbers, priority, and build order. State counts created vs updated vs skipped, and the board url.

## gh commands (inlined; idempotent)

```bash
OWNER=abrahamFerga; NAME=<name>; REPO=$OWNER/$NAME; PROJECT=<n>

# --- match-before-create: pull existing issues with their bodies (for mskey matching)
gh issue list -R "$REPO" --state all --limit 300 --json number,title,body,labels

# --- epic issue (body ends with the marker)
gh issue create -R "$REPO" --title "<Epic name>" \
  --body $'<goal>\n\nDelivers: <capabilities>\nDepends on: <epics>\n\n<!-- mskey: epic/<slug> -->' \
  --label type:epic            # add --label stage:foundations for epic 1
# update instead of create when matched:
gh issue edit <n> -R "$REPO" --body '<new body with same mskey>'

# --- feature issue
gh issue create -R "$REPO" --title "<Capability>" \
  --body $'<one-line>\n\n## Acceptance criteria\n- ...\n\nServes persona(s): ...\nMoves metric: ...\n\n<!-- mskey: feature/<slug> -->' \
  --label type:feature --label priority:p1

# --- sub-issue link (child id is the node id, NOT the number)
child_id=$(gh api repos/$REPO/issues/<child#> --jq '.id')
gh api --method POST repos/$REPO/issues/<epic#>/sub_issues -F sub_issue_id="$child_id"

# --- board: discover ids once, then add + set fields
PID=$(gh project view "$PROJECT" --owner @me --format json --jq '.id')
gh project field-list "$PROJECT" --owner @me --format json   # -> Pipeline field id + option ids, Build order field id
ITEM=$(gh project item-add "$PROJECT" --owner @me --url <issue-url> --format json --jq '.id')
gh project item-edit --id "$ITEM" --project-id "$PID" --field-id <pipeline-fid> --single-select-option-id <backlog-oid>
gh project item-edit --id "$ITEM" --project-id "$PID" --field-id <buildorder-fid> --number <N>
```

## Guardrails

- **Idempotent or nothing.** Every object is matched before creation (issues by `mskey`, sub-issues by existing-children list, board items by issue url). A second run with an unchanged plan creates zero new objects.
- **No invented scope.** Every epic and feature must trace to a line in `PLAN.md`; every acceptance criterion to `SPEC.md`. If the plan is missing a capability that SPEC requires, stop and send the user back to `plan-system` — do not paper over it with a guessed issue.
- **Public-repo hygiene.** Issue bodies are world-readable: secret-scan them, and never paste tenant data, tokens, or customer names.
- **All-or-clean.** If `gh`/auth/scope checks fail, publish nothing and report what's needed — never leave a half-built backlog.
- **Stage gate.** This is the terminal Stage-1 step. After it succeeds, advancing to `architecture` (`/workflow-core:manage-workflow set stage architecture` then `manage-skills sync`) is the next move.

## Common Pitfalls

- **Duplicating issues** because the `mskey` marker was dropped from a body — always re-emit the exact marker on edits.
- **Using the issue number as `sub_issue_id`** — the sub-issues API wants the node `.id` from `gh api .../issues/<n>`.
- **Boarding epics** — only features go on the board; epics are containers tracked via sub-issues.
- **Forgetting Build order** — without it the board has no stable Foundations-first ordering for Stage 3 to follow.

## Related skills

- [`plan-system`](../plan-system/SKILL.md) — produces the `PLAN.md` this skill publishes. **Load when:** the plan isn't written yet.
- `/workflow-core:init-system` — creates the repo, labels, and board this skill populates. **Load when:** `workflow.json.github` is missing.
- `/architecture:design-architecture` — reads the feature issues this skill creates and moves them Backlog → Ready. **Load when:** the backlog is published and you're starting Stage 2.
- `/development:work-next-issue` — pulls Ready features off the board and implements them. **Load when:** architecture is done.
