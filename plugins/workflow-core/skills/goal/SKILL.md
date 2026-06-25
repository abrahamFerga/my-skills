---
name: goal
description: >
  Set or show the autonomous-run policy for a generated system — the objective, how much latitude
  the agents have (manual / confirm / auto), and when the loop should stop (backlog-drained /
  stage-complete / never) — by writing the optional `goal` block in workflow.json. This is the
  knob the orchestrator and the loop-continuation hook read to run hands-off. USE FOR: declaring
  what an autonomous build is for and how unattended it may run; reading the current policy.
  DO NOT USE FOR: changing stage/cloud/connectors/capabilities (use ../manage-workflow/SKILL.md);
  creating the project (use ../init-system/SKILL.md); starting the run (that's `/loop` +
  ../build-generated-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# goal

The front door for hands-off operation. `/goal` records **what** an autonomous run is trying to
achieve and **how much rope** the agents have, into the optional `goal` block of `workflow.json`.
The orchestrator reads it to know the objective (so a build can start from the goal alone, with no
`industry` argument) and the loop-continuation hook reads it to decide whether to keep a session
going. Nothing else writes this block.

It is an ops skill: it validates against the `workflow.json` structure, secret-scans, and merges —
it never rewrites unrelated fields. Same safety contract as the other workflow-core ops skills.

## When to Use

- You want a build to run unattended and need to state the objective + autonomy level once.
- You want to read the current policy (`/goal show`).
- You want to dial autonomy up (`auto`) or down (`manual`) between runs.

## Stop Signals

- **No `workflow.json` yet** → run [`init-system`](../init-system/SKILL.md) first; there's nothing to write the block into.
- **Changing stage / cloud / connectors / capabilities** → use [`manage-workflow`](../manage-workflow/SKILL.md).
- **Embedding a token or customer name in the objective** → refuse; the block is secret-scanned and may live in a public repo.

## Inputs

| Input | Required | Description |
|---|---|---|
| `objective` | For a `set` | 8–280 chars: what the run is for (e.g. "Build the legal practice-management system end to end"). |
| `autonomy` | No (default `confirm`) | `manual` \| `confirm` \| `auto`. See the table below. |
| `stop_when` | No (default `backlog-drained`) | `backlog-drained` \| `stage-complete` \| `never`. Hard ceiling for the loop. |
| `show` | — | `/goal show` prints the current block and exits without writing. |

### Autonomy levels

| Level | The agents… | Outward actions (first push, PRs, board moves, merges) |
|---|---|---|
| `manual` | advise and produce local artifacts only | never taken — reported as "ready to do" for the human |
| `confirm` *(default)* | do the work | paused before each outward/irreversible action for a yes |
| `auto` | proceed continuously | taken without pausing; the run stops only at a genuine blocker or `stop_when` |

`auto` is the only level the loop-continuation hook will use to re-drive a session past a natural
stop. `stop_when` bounds it: `backlog-drained` stops once every feature is Done, `stage-complete`
stops at the end of the current stage, `never` runs until the human stops it (`Esc` / `/loop stop`).

While `auto` is set, only a session **actively running the build** self-continues on each stop (the
hook re-drives it). A session doing unrelated work in the same project is left alone — the hook
re-drives only when the build pipeline is present in the transcript. Set autonomy back to `confirm`
(`/goal … --autonomy confirm`) to take the project off unattended mode.

## Workflow

1. **Read `workflow.json`** at the cwd. If absent, stop with the init-system pointer.
2. **`/goal show`**: print the current `goal` block (or "none — running in the default `confirm`
   posture") and exit. No write.
3. **Validate inputs.** `objective` 8–280 chars; `autonomy` ∈ {manual, confirm, auto}; `stop_when`
   ∈ {backlog-drained, stage-complete, never}. Refuse on anything else — don't coerce.
4. **Secret-scan** the objective against the shared secret-pattern table
   ([`init-system/references/ops-safety.md`](../init-system/references/ops-safety.md)). On a match,
   refuse and name the pattern only.
5. **Merge** the `goal` block into the in-memory `workflow.json` (preserve every other field
   byte-for-byte), then **validate the whole object** against the structure in
   [`ops-safety.md`](../init-system/references/ops-safety.md). Never write an invalid file.
6. **Write** `workflow.json` atomically (2-space indent, trailing newline).
7. **Report** the new policy and the one command to start the run:
   `/loop /workflow-core:build-generated-system` (self-paced), noting that `auto` will also
   self-continue via the loop hook until `stop_when`.

## Guardrails

- **Only the `goal` block.** This skill touches nothing else in `workflow.json`, and never
  `.claude/settings.json`. Unrelated keys survive untouched.
- **Validate before write, secret-scan before write.** Same non-negotiable order as every ops skill.
- **`auto` is a loaded gun — make it explicit.** Never infer `auto`; the human must ask for it. When
  setting `auto`, restate in the report exactly what will now happen without a prompt and how to stop it.
- **Idempotent.** Setting the same policy twice yields byte-identical output.

## Common Pitfalls

- Treating `/goal` as the thing that *starts* the run — it only records policy; `/loop` +
  `build-generated-system` is the engine.
- Writing `auto` when the user said "go ahead" about one action — that's a one-time `confirm`
  approval, not a standing `auto` policy.
- Putting build details (stage, cloud, connectors) in the objective text — those belong in
  `manage-workflow`, not the goal string.

## Related skills

- [`build-generated-system`](../build-generated-system/SKILL.md) — reads this block to run the pipeline hands-off. **Load when:** starting the run.
- [`manage-workflow`](../manage-workflow/SKILL.md) — the sibling that owns stage/cloud/connectors/capabilities. **Load when:** composing what's in the system.
- [`init-system`](../init-system/SKILL.md) — creates the `workflow.json` this writes into. **Load when:** there is no project yet.
