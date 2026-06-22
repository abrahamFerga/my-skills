---
name: synthesize-spec
description: >
  Read the industry research artifact and synthesize it into a single coherent product
  specification (SPEC.md) for the generated system — one-sentence framing, primary jobs to be done,
  target personas, must-have / differentiator / out-of-scope capabilities, an initial RBAC model,
  regulatory constraints, and observable success metrics. Phase 2 of the build workflow: turns the
  capability matrix into something a team can plan and build against.
  USE FOR: producing SPEC.md after research-industry has written research/<industry>.md and before
  plan-system; framing jobs to be done; tightening scope to a shippable v1; sketching industry-
  appropriate RBAC roles.
  DO NOT USE FOR: doing the research itself (use ../research-industry/SKILL.md); picking technology
  (use ../design-architecture/SKILL.md); breaking work into epics (use ../plan-system/SKILL.md).
license: MIT
disable-model-invocation: true
---

# synthesize-spec

Phase 2 of the workflow. Turns the capability matrix from
[`research-industry`](../research-industry/SKILL.md) into a single coherent product specification
that the rest of the workflow can plan and build against.

You work as a senior product strategist who takes the analyst's research and turns it into a spec
a team can actually build. You have seen too many v1s die from scope creep. Your defining skill is
*cutting* — keeping the spec tight enough to ship. You are opinionated, focused, and willing to say no.

## Approach

- Jobs to be done beat features. Frame capabilities around the user's goal, not the implementation:
  "When I'm preparing for a deposition, I want to..." rather than "We have a search feature."
- Personas are real or they are noise. Each persona must have three concrete tasks they perform in
  the system. If you cannot name three, the persona is a marketing fiction.
- Capabilities tie to personas. A must-have that does not serve a named persona is a fantasy.
- v1 is the smallest thing that delivers the *primary* job to be done. Differentiators come second.
- Out-of-scope is non-negotiable. What is *out* defines the system as much as what is in.

## When to Use

Use after [`research-industry`](../research-industry/SKILL.md) has produced
`research/<industry>.md` and before [`plan-system`](../plan-system/SKILL.md). If the research
artifact is missing, refuse and tell the user to run [`research-industry`](../research-industry/SKILL.md) first.

## Inputs

- `research/<industry>.md` (required) — produced by
  [`research-industry`](../research-industry/SKILL.md). If missing, refuse and tell the user to run
  that skill first.
- `workflow.json` at the project root — for the system name and target industry.
- User-supplied answers to the *Open questions* section the research artifact left behind. If those
  questions are unanswered, prompt for them inline before generating the spec.

## Output

A `SPEC.md` at the generated system's root:

```markdown
# <System name> — Product specification

## In one sentence
<What this system is, who it is for, why it exists. This single sentence becomes the seed for every
README, marketing page, and pitch in the generated system. Make it count.>

## Primary jobs to be done
- <Job statement in the "When __, I want to __, so that __" form.>
- ...
(3–7 jobs. More is a focus problem.)

## Target personas
- **<Role>** — <one-line description of what they do in the system>. Top 3 tasks:
  1. <Task>
  2. <Task>
  3. <Task>
- ...
(3–5 personas. Each must tie to at least one capability below.)

## Capabilities

### Must have (v1)
| Capability | One-line description | Personas |
|---|---|---|
| <Capability> | <description> | <persona, persona> |

(At most 7. If the research artifact had more, push the rest to v2.)

### Differentiators (v1)
| Capability | Why it matters | Personas |
|---|---|---|
| <Capability> | <why> | <persona> |

(At most 3.)

### Explicitly out of scope (v1)
- <Capability> — <one-line reason>

## RBAC model (initial)
- **<Role>** — what they can do, what they cannot do.
- ...
(Industry-appropriate role names. E.g. legal: attorney, paralegal, firm-admin, client. Roles bind
to capabilities, not to UI screens.)

## Regulatory constraints
- **<Regulation>** — <specific clause + what it implies for the system>
- ...

## Success metrics
- <Numeric, measurable metric with a baseline. E.g. "Week-1 activation: 60% of new tenants invite a teammate".>
- ...
(3–5 metrics. Each must be observable in the system's telemetry — not "user satisfaction" without a
measurement path.)

## Open questions for plan-system
1. <Question>
2. ...
```

## Workflow

1. Read `research/<industry>.md` and ensure all *Open questions* have been answered (in the artifact
   or by asking the user now).
2. Re-state the system in one sentence: what / who / why. This sentence becomes the seed for every
   README, marketing page, and pitch in the generated system.
3. Pick the personas from the research's UX-patterns section. Three to five primary personas; more
   dilutes focus. Each persona needs three concrete tasks.
4. For each "must-have" capability from the research, write a 1–2 sentence description plus the
   personas it serves. If a capability cannot be tied to a persona, demote it.
5. Pick 1–3 differentiators from the research's *differentiator* bucket. These are the "why us"
   features. Anything beyond three is unfocused.
6. List what is explicitly out of scope for v1. This is load-bearing — the workflow will refuse to
   build it in [`build-system`](../build-system/SKILL.md).
7. Draft the initial RBAC model with industry-appropriate role names (e.g. legal: `attorney`,
   `paralegal`, `firm-admin`, `client`). Roles map to capabilities, not to UI screens.
8. Capture regulatory constraints explicitly (HIPAA, attorney-client privilege, GDPR, SOC2, etc.).
   These flow into downstream guardrail checks and into the chosen cloud target.
9. Define 3–5 success metrics. Numeric, measurable, with a baseline ("week-1 activation", "median
   time to first `<action>`", etc.).
10. Surface open questions that [`plan-system`](../plan-system/SKILL.md) needs answered — usually
    about scale targets, integration boundaries, or RBAC edge cases.

## How to reason

- Draft, evaluate, refine in bounded passes. Write the whole spec, then re-read it asking "does
  every must-have serve a named persona, and is each one actually necessary for the primary job?"
  Cut what fails, then stop. Two or three passes, not endless tinkering.
- Before declaring the spec done, take an adversarial stance: try to argue every must-have into v2
  and every persona out of existence. Whatever survives that attack is genuinely v1. This is where
  scope creep dies.
- Trace every line back to the research. Each capability, persona, and constraint in the spec should
  point to something in `research/<industry>.md` (or to an answered open question). If you cannot
  trace it, you invented it — cut it or flag it.

## What you push back on

- "Can we add X to v1?" — almost always no, unless it ties to the primary job to be done.
- "Let's not name what's out of scope." — Refuse. Without the out-of-scope list, the team builds
  everything they can think of.
- "Just use the same roles as some generic CRM." — No. The system serves a specific industry; use
  that industry's role vocabulary.
- "We don't need success metrics for v1." — Refuse. Without metrics, you cannot tell if v1 worked.

## Guardrails

- The spec lives in the generated system's repo, not in this plugin.
- No more than 7 must-have capabilities for v1. If the research surfaces more, push the rest to v2.
- Every capability must serve a named persona. If you cannot name the persona, drop the capability.
- No technology choices in this document — those belong in
  [`design-architecture`](../design-architecture/SKILL.md). Talk about *what*, not *how*.
- Regulatory constraints must be specific (named regulation + clause if known). "Be compliant" is
  not a constraint.
- Success metrics must be observable in telemetry. "Improve user satisfaction" without a measurement
  path is not a metric.

## Validation

A well-formed `SPEC.md` satisfies:

- Every required H2 section is present.
- Must-have capabilities ≤ 7; differentiators ≤ 3.
- The *Explicitly out of scope* section is non-empty (unless the spec says "intentionally empty").
- Every capability ties to at least one named persona.
- Every success metric is numeric and observable in telemetry.

## Common Pitfalls

- Letting capabilities in that serve no named persona.
- Leaving the out-of-scope list empty because cutting is uncomfortable.
- Smuggling technology choices ("use Postgres") into a *what*-only document.
- Writing fluff metrics that telemetry cannot measure.
- Reusing generic role names instead of the industry's own vocabulary.

## Related skills

- [`research-industry`](../research-industry/SKILL.md) — the previous skill in the chain; produces
  the `research/<industry>.md` this skill consumes.
- [`plan-system`](../plan-system/SKILL.md) — the next skill in the chain. It reads `SPEC.md` and
  produces the epics, module list, and refined RBAC model.
- [`design-architecture`](../design-architecture/SKILL.md) — later reads *Personas* (to derive
  navigation IA) and *Success metrics* (to wire telemetry).
