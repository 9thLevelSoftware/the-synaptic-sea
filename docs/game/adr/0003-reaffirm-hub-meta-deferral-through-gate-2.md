# ADR-0003: Re-affirm Hub/Meta Deferral Through Gate 2

## Status

Accepted

## Context

ADR-0002 deferred hub/meta progression past Gate 1 and required a Gate 2 entry re-decision. Gate 1 is now **Go** based on the 2026-06-19 automated playtest and regression evidence recorded in `08_milestone_gates.md`.

The Gate 2 backlog already has unresolved derelict-exploration depth work:

- Inventory/tool loop remains Proposed as REQ-007 and has no feature spec yet.
- Hazard variety is still limited to one oxygen-breach pressure loop.
- Objective and procedural variation remain minimal beyond the validated four-objective slice.
- Save/load work is needed at least for current-run or current-ship-slice persistence.

Escalating hub/meta into Gate 2 would force early decisions on hub ship scene structure, derelict selection, persistent unlocks, meta-currency/economy, and hub save state before the derelict exploration loop has enough production-depth evidence. That conflicts with Pillar 4 (small vertical slices before broad systems) and repeats the scope-creep risk documented in ADR-0002.

## Decision

Choose **Option A: re-affirm deferral**.

Hub/meta progression remains **deferred through Gate 2**. Gate 2 production focuses on deepening the derelict exploration loop: inventory/tools, expanded hazards, objective/procedural variation, and current-run persistence. Gate 2 implementation cards must not include hub ship scene/UI, derelict selection or queueing, persistent meta-currency, persistent unlocks, faction/narrative progression, or hub save state.

The next anchor is **Gate 3 entry planning**. Before Gate 3 Alpha work is accepted as scoped, `sargasso-stage-gate` must schedule a hub/meta feature-spec decision that either:

1. authors `docs/game/features/hub_progression.md` and implementation/review cards for the hub/meta loop, or
2. records a Gate 3/4 cut/hold decision explaining why Alpha can proceed without hub/meta implementation.

Gate 2 save/load scope is limited to run/ship-slice persistence unless the Gate 3 hub/meta decision explicitly expands it to hub-level persistent state.

This is still a **defer**, not a **kill**. The vision-level hub ship remains part of the premise, but it is not a Gate 2 implementation surface.

## Consequences

Positive:

- Keeps Gate 2 focused on validated runtime gameplay depth instead of broad meta architecture.
- Preserves source-backed sequencing: feature specs and requirements come before hub/meta implementation.
- Lets current-run save/load and inventory/tool state emerge from actual derelict-loop needs before hub aggregation is designed.
- Gives the Gate 2 planning card a clear branch: choose derelict exploration depth, not hub/meta implementation.

Negative / tradeoffs:

- The full session loop remains incomplete through Gate 2; the player will still not choose derelicts from a hub or apply persistent gains/losses to a hub ship.
- Gate 3 planning must reserve explicit time for hub/meta design or record another gate decision before Alpha scope can be accepted.
- Some current-run persistence work may need migration once hub-level save state is designed.

Mitigations:

- Gate 2 persistence work should avoid hub/economy assumptions and expose clean current-run state that can later be aggregated by a hub layer.
- Gate 2 cards must cite ADR-0003 when excluding hub/meta scope.
- The Gate 3 entry planning anchor prevents the deferral from becoming implicit abandonment.

## Affected documents

- `docs/game/00_vision.md` — open question now points to ADR-0003 and the Gate 3 anchor.
- `docs/game/02_core_loop.md` — re-decision trigger updated from Gate 2 entry to the Gate 3 anchor.
- `docs/game/03_gdd.md` — feature-spec list and gate note updated for deferral through Gate 2.
- `docs/game/05_requirements.md` — REQ-009 records Option A resolution.
- `docs/game/08_milestone_gates.md` — Gate 2 cites ADR-0003 and scopes its loop to derelict exploration depth.

## Verification

- `docs/game/adr/0003-reaffirm-hub-meta-deferral-through-gate-2.md` exists.
- `docs/game/08_milestone_gates.md` Gate 2 section cites ADR-0003.
- `docs/game/features/hub_progression.md` remains absent for Gate 2.
- Board audit confirms `t_3dc29a93` resolves before dependent Gate 2 planning / implementation dispatches.
