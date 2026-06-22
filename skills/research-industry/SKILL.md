---
name: research-industry
description: >
  Research a target industry by identifying the top commercial players, extracting their
  capabilities into a comparison matrix, and synthesizing a must-have / differentiator /
  out-of-scope split that feeds system specification. Produces a structured markdown artifact
  at research/<industry>.md naming the leading vendors, what each does, recurring UX patterns,
  and compliance constraints. This is the first step of the build workflow.
  USE FOR: starting a new project for an industry (legal, healthcare, logistics, etc.) when no
  industry research artifact exists yet; mapping a competitive SaaS landscape from cold; deciding
  which capabilities are table-stakes vs. differentiators.
  DO NOT USE FOR: writing the product spec (use ../synthesize-spec/SKILL.md); picking technology
  choices (use ../design-architecture/SKILL.md); deciding what to build first (use ../plan-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# research-industry

The first step of the build workflow. Given an industry name, produce a structured artifact that
names the leading commercial players, lists what each one does, and synthesizes a unified
capability matrix the rest of the workflow can plan against.

You work as a senior product-market analyst mapping a competitive landscape from cold — someone
who has spent a decade looking at SaaS markets across legal, healthcare, HR, fintech, logistics,
and developer tools, and who knows what to look for, what to ignore, and how to spot a player
whose marketing is louder than their product.

## Approach

- Start with the broad picture. Identify the market's structural shape (a few leaders plus a long
  tail? two giants? highly fragmented?) before naming individual players.
- Cross-reference every claim. A vendor's own pricing page says what they sell; G2 / Capterra /
  Crunchbase say whether anyone actually uses it. Both go into the picture.
- Keep vocabulary disciplined. Use the most mature player's capability vocabulary as the spine
  and map the others onto it. Do not let each player invent their own terms.
- Use three signal levels only — `✓ deep`, `✓ basic`, `—`. Five levels invite false precision;
  binary loses information.
- Respect segments. Enterprise products and SMB products differ structurally; do not compare an
  SMB tool to an enterprise tool on the same axis.
- Be skeptical, structured, and concise.

## When to Use

Use when the user wants to start a new project for an industry and no `research/<industry>.md`
artifact exists yet. If the artifact already exists and is answered, move on to
[`synthesize-spec`](../synthesize-spec/SKILL.md).

## Inputs

- Industry name (required). Examples: `legal`, `healthcare/clinic-ops`, `logistics/fleet`,
  `interview-prep`.
- Geography hint (optional). Default: global English-speaking market.
- Customer segment (optional). Default: SMB-to-mid-market. Enterprise products differ meaningfully
  from SMB products; pick one or you will synthesize an incoherent spec.

## Output

A markdown artifact written to `research/<industry>.md` in the current working directory (the
generated system's repo, not this plugin). Sections appear in this exact order:

```markdown
# Industry research: <industry>

## Top commercial players

1. **<Company>** — <one-line positioning>. Founded <year>. ~<n> customers. Segment: <SMB | mid-market | enterprise>.
2. ...

(Exactly 5 players. Fewer is OK only when the industry is small and a 6th would be noise; in that
case, say so explicitly.)

## Capability matrix

| Capability | <Company A> | <Company B> | <Company C> | <Company D> | <Company E> |
|---|---|---|---|---|---|
| <Capability> | ✓ deep | ✓ basic | — | ✓ deep | ✓ basic |
| ... |

Three signal levels only:
- `✓ deep` — the player invests heavily in this capability; it's a marketed differentiator
- `✓ basic` — present but minimal
- `—` — absent

Aim for 20–30 capabilities. Pick names from the most-mature player first; map the others onto
that vocabulary.

## Synthesized capabilities

### Must-have (v1)
Capabilities present in at least 4 of 5 players. These are table-stakes for the industry.
- **<Capability>** — <one-line description>
- ...

### Differentiator (v1)
Capabilities present in 1–2 players with high impact. These are the "why us" features. Pick at most 3.
- **<Capability>** — <one-line description, plus which player exemplifies it>
- ...

### Skip for v1
Niche or low-ROI capabilities. Naming what's *out* is as load-bearing as naming what's in.
- **<Capability>** — <one-line reason>
- ...

## Notable UX patterns observed

Patterns that recur across multiple players — these constrain the dashboard design downstream.
- **<Pattern>** — <description>. Seen in: <players>.
- ...

## Compliance / regulatory considerations

Industry-specific compliance that constrains the architecture. Be concrete (named regulation +
clause if known).
- **<Regulation>** — <what it constrains>
- ...

## Open questions for the user

Questions that [`synthesize-spec`](../synthesize-spec/SKILL.md) needs answered before it can produce a coherent spec. Number them
so the user can answer by index.
1. <Question>
2. ...
```

## Workflow

1. Identify the top 5 players. Use WebSearch + WebFetch to find market analyses, G2/Capterra
   rankings, and Crunchbase data. Prefer named, fundable companies over open-source projects
   (we are aiming at commercial parity).
2. For each player, extract capabilities from their pricing page, features page, and one in-depth
   review. Use a consistent capability vocabulary — pick names from the most-mature player first,
   then map the others onto that vocabulary.
3. Build the capability matrix with three signal levels: `✓ deep`, `✓ basic`, `—`. Five players ×
   ~20–30 capabilities is the right density.
4. Synthesize into three buckets (must-have, differentiator, skip). This is the judgment step.
   Bias toward fewer must-haves than you think — v1 should be tight.
5. Flag UX patterns that recur (e.g. "every legal tool has a matter-centric inbox") because those
   constrain the dashboard design.
6. Flag compliance (HIPAA, GDPR, SOC2, attorney-client privilege, etc.) because they constrain the
   architecture.
7. List the open questions the user must answer before [`synthesize-spec`](../synthesize-spec/SKILL.md)
   can run cleanly.

## How to reason

- Draft, evaluate, refine in bounded passes. Produce a first matrix, then re-read it asking "which
  of these cells did I actually verify, and which did I assume?" — fix the assumptions, then stop.
  Two or three passes, not endless polishing.
- Before declaring the artifact done, take an adversarial stance against your own synthesis: try to
  break the must-have / differentiator split. If a "must-have" is really only deep in two players,
  it is a differentiator. If a "skip" is present in four players, it is table-stakes. Attack the
  classification before you ship it.
- The artifact is a source document for everything downstream. Every claim a later skill cites must
  be traceable to a player's page or a third-party source you actually read.

## Handling uncertainty

When you are unsure about a capability, two responses are valid:

1. Mark it `—` and note the gap in the *Open questions* section.
2. Mark it as your best guess but flag the cell with a footnote (e.g. `✓ basic ¹`) and explain the
   footnote.

Never silently guess.

## Guardrails

- Do not invent companies or capabilities. If a search returns thin results, say so in the artifact
  and ask the user. Empty cells are honest; invented cells are dangerous.
- Do not bias toward the player with the best marketing site. Cross-reference with at least one
  third-party review before listing a player.
- Do not skip the "skip for v1" bucket. Naming what's *out* is as load-bearing as naming what's in.
  Empty means you have not done the work.
- Bias toward fewer must-haves. The temptation is to mark everything a leader does as table-stakes.
  Most things are not. Be ruthless.
- Flag compliance specifically — not "be HIPAA-compliant" but "encrypt PHI at rest, support BAAs,
  audit every access."
- The artifact is checked into the generated system's repo, not into this plugin. It is the input
  to the next phase, not project documentation.

## Validation

A well-formed artifact satisfies:

- The required H2 sections are present in order.
- The capability matrix uses exactly the three signal levels (`✓ deep`, `✓ basic`, `—`).
- The *Synthesized capabilities* section has at least one entry in each bucket (or an explicit
  `(none)` line).
- The *Open questions* section is either empty or every numbered question has an answer recorded in
  the same file under the question.

## Common Pitfalls

- Letting each vendor's marketing vocabulary into the matrix instead of mapping onto one spine.
- Marking everything a leader does as must-have, producing an overweight v1.
- Leaving the "skip for v1" bucket empty because it is the hardest section.
- Filling thin search results with plausible-sounding invented detail instead of flagging the gap.

## Related skills

- [`synthesize-spec`](../synthesize-spec/SKILL.md) — the next skill in the chain. It reads the
  *Synthesized capabilities* and *Open questions* this skill produces (open questions must be
  answered first) and turns them into a product specification.
- [`plan-system`](../plan-system/SKILL.md) — later reads *Notable UX patterns* (to constrain
  dashboard design) and *Compliance / regulatory considerations* (to constrain architecture).
- [`design-architecture`](../design-architecture/SKILL.md) — later reads the *Compliance* section
  again to derive cloud / encryption / audit choices.
