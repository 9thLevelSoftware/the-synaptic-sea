# Feature: Route Control

## Status

Validated

## Design pillar alignment

- Spatial coherence first: blocked routes are represented by actual route gates.
- Runtime systems over proof artifacts: gates affect collision/passability.
- Every action has visible consequence: restoring systems opens routes and updates HUD/status.

## Player fantasy

The player restores ship systems and physically opens access through a previously blocked derelict route.

## Gameplay problem

Blocked routes previously risked being only visual affordances. The feature turns route access into real runtime state.

## Core behavior

- Build route gates from blocked-route loader data.
- Gate starts closed with collision enabled.
- Restoring systems opens powered route gates.
- Opening disables gate collision and updates inspectable metadata.
- Reactor stabilization unlocks extraction.

## Inputs

- Generated ship blocked-route data.
- Ship-system summary from objective progression.
- Objective sequence completion.

## Outputs

- Route-control summary.
- Gate collision enabled/disabled state.
- Gate metadata.
- HUD route/extraction status lines.

## Rules

- Power alone does not open gates unless blocked routes are cleared.
- Opening a gate disables collision; it does not delete the gate node.
- Extraction unlock is separate from route opening.

## Non-goals

- No inventory keys/tools.
- No animation/audio polish.
- No generalized procedural door system.
- No map UI.

## Technical design

- Pure model: `scripts/systems/route_control_state.gd`.
- Scene integration: `scripts/procgen/playable_generated_ship.gd`.
- Direct smoke: `scripts/validation/route_control_state_smoke.gd`.
- Main-scene smoke: `scripts/validation/main_playable_slice_route_control_smoke.gd`.

## Acceptance criteria

- Route gate count is at least 1 in the main playable slice.
- Active blocker count starts at least 1.
- Collision enabled count starts at least 1.
- Objective 1 leaves route closed.
- Objective 2 opens route and collision enabled count becomes 0.
- Gate metadata `route_gate_open` and `system_cleared` become true.
- Objective 4 unlocks extraction and run completion remains true.

## Validation

See `docs/game/06_validation_plan.md`.

## ADRs

- `docs/game/adr/0001-adopt-stage-gate-kanban-godot-validation.md`
