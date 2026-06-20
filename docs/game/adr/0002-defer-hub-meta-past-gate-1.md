# ADR-0002: Defer Hub/Meta Progression Past Gate 1 (with Cut Line)

## Status

Accepted

## Context

The vision (`00_vision.md`) describes a player hub ship trapped in a Sargasso, exploring derelict interiors. The core loop doc (`02_core_loop.md`) lists a session loop whose final step is "Apply gains/losses to the hub ship. Unlock next decisions." This implies a hub/meta progression layer on top of the per-ship loop.

Gate 1 (`08_milestone_gates.md`) is defined as "Pre-production / playable systems slice" with a representative 60–120 second slice, coherent navigation, route/system state, one risk/pressure loop, and clean validation. At the time of this ADR, "Hub/meta progression definition" was listed as missing Gate 1 evidence, but the doc did not specify whether it was a Gate 1 deliverable or a deferred concern.

This ambiguity creates real risk for future workers:

- **Scope creep risk.** A worker could read the session loop as in-scope and start building a hub scene, derelict selection, persistent unlocks, or meta-currency mid-Gate-1.
- **Architecture pressure.** Implementing hub/meta would force early decisions on save data, content scoping, and economy modeling before the per-ship loop is validated — directly violating Pillar 4 (small vertical slices before broad systems).
- **Contradictory evidence.** The current single-ship slice has no hub scene, no derelict selection, and no persistent state across runs; reactor-stabilization completion is the only "return progress" signal. Treating hub/meta as a Gate 1 requirement would invalidate the existing validated slice.
- **Untestable criterion.** Without a cut line, "Hub/meta progression definition" is not a verifiable acceptance criterion.

## Decision

Hub/meta progression is **deferred past Gate 1** with the following cut line:

- **In scope for Gate 1:** one generated derelict ship slice, the four-objective sequence, system/route state, extraction as a completion signal. The reactor-stabilization completion state satisfies the "return progress to hub" step of the session loop for Gate 1 purposes.
- **Out of scope for Gate 1:** hub ship scene/UI, derelict selection or queueing, persistent unlocks across runs, meta-currency/economy, faction/narrative progression, save/load of hub state, narrative arcs that span derelicts.
- **Feature spec `features/hub_progression.md` is NOT authored during Gate 1.** Doing so would imply in-scope work and is treated as a scope violation by `sargassoreview`.
- **Re-decision trigger:** before Gate 2 begins, a hub/meta re-decision card on board `sargasso-stage-gate` must select exactly one of:
  - (a) Re-affirm deferral with a Gate 3 or Gate 4 anchor (recorded as a patched ADR), OR
  - (b) Escalate into an early Gate 2 implementation card with `features/hub_progression.md` authored before any implementation work.
- **Gate 2 entry criteria updated** to require resolution of the hub/meta re-decision card.

This is a **defer**, not a **kill**. The vision-level meta-loop question is reopened at Gate 2 entry review.

## Consequences

Positive:
- Removes a major ambiguity that could derail Gate 1 workers.
- Anchors the largest undecided design surface to a specific re-decision point (Gate 2 entry).
- Preserves the option to re-scope if validation results or vision changes warrant it.
- Aligns with Pillar 4 (small vertical slices first) and Pillar 5 (source-backed decisions).

Negative / tradeoffs:
- The full session loop remains the target loop but is not yet playable end-to-end; Gate 1 demo will look like a single-derelict experience.
- A future Gate 2 card will need to either rebuild or retroactively design the hub/meta layer against validated per-ship data — some rework is possible if the per-ship state schema is not designed with hub aggregation in mind.
- Without a visible hub, external playtesters at Gate 1 may form opinions on the meta-loop that need to be deferred to Gate 2 review.

Mitigations:
- REQ-004 (new gameplay systems require model and scene validation) already requires per-ship state models to be inspectable, which keeps the schema honest for later hub aggregation.
- The Gate 2 entry review provides a natural checkpoint to validate the deferral decision against accumulated evidence.

## Affected documents

- `docs/game/00_vision.md` — open question marked resolved for Gate 1.
- `docs/game/02_core_loop.md` — explicit Gate 1 hub/meta stance section added.
- `docs/game/03_gdd.md` — scope cuts and gate status reflect deferral.
- `docs/game/05_requirements.md` — REQ-008 (stance) and REQ-009 (Gate 2 re-decision trigger) added.
- `docs/game/08_milestone_gates.md` — Gate 1 missing-evidence item closed, Gate 2 entry criteria updated.

## Verification

- Documentation review by `sargassoreview` confirms:
  - All five docs above reflect consistent deferral language.
  - No Gate 1 acceptance criterion requires hub/meta state.
  - REQ-008 and REQ-009 are present and approved.
  - `features/hub_progression.md` is not authored.
- A future Gate 2 entry review invokes REQ-009 and produces either a patched ADR or a new ADR plus a `features/hub_progression.md` spec.