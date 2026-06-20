# Route Control System Design

Date: 2026-06-19
Project: The Sargasso of Stars
Milestone: Main Playable Slice — Route Control System

## Summary

The next gameplay milestone turns the current blocked-route affordance into a real route-control system. The game should no longer merely hide a prop or update HUD text after power is restored. It should create runtime route gates/blockers in the main playable scene, keep them closed while ship systems are offline, and open them by disabling collision and updating route state when objectives restore relevant systems.

This milestone continues the move away from proof artifacts. The deliverable is runtime behavior in `res://scenes/main.tscn`, backed by Godot smokes. No HTML, PNGs, contact sheets, or proof documents are part of the deliverable.

## Current Context

The project already has these relevant pieces:

- `ShipSystemState` tracks supplies, main power, logs, reactor stability, extraction unlock, power percentage, and reactor percentage.
- `PlayableGeneratedShip` owns objective progression, player/camera spawning, interactables, readability affordances, HUD, and ship-system updates.
- `restore_systems` currently changes ship-system state and hides `BlockedAffordance_*` props.
- `stabilize_reactor` unlocks extraction in ship-system state.
- `ObjectiveTracker` shows the current objective and compact system status.

The missing piece is passability. A route that is blocked should have actual runtime gate/blocker state and collision while closed, then become passable when the relevant ship system is restored.

## Goals

1. Add a focused route-control runtime model.
2. Create route gate/blocker scene nodes from existing blocked-route information.
3. Make blocked routes physically closed at start through collision.
4. Open powered route gates when `main_power_restored` and `blocked_routes_cleared` become true.
5. Mark extraction route unlocked when `extraction_unlocked` becomes true.
6. Keep route gate nodes inspectable after opening by disabling collision and updating metadata rather than deleting nodes.
7. Keep existing objective sequencing, ship-system updates, HUD behavior, and playable smokes working.

## Non-Goals

This milestone does not include:

- full procedural door generation for every doorway;
- door animations;
- sounds;
- inventory or keycards;
- hazards, enemies, or survival pressure;
- map UI;
- topology or loader rewrites;
- new visual proof artifacts.

## Architecture

The architecture adds one new state model and one new runtime scene root.

```text
Objective completed
  -> ShipSystemState.apply_objective(...)
  -> RouteControlState.apply_ship_systems_summary(ship_systems.get_summary())
  -> PlayableGeneratedShip applies route-control scene consequences
  -> route gate collision, visibility, and metadata update
  -> ObjectiveTracker receives concise status lines
```

`ShipSystemState` remains responsible for ship-level facts: power, logs, reactor, extraction. `RouteControlState` is responsible for route access facts: gates, active blockers, opened gates, and extraction route lock state. `PlayableGeneratedShip` coordinates both models and owns scene-tree mutation.

## Components

### `RouteControlState`

New file:

`/Users/christopherwilloughby/the-sargasso-of-stars/scripts/systems/route_control_state.gd`

Responsibilities:

- store route gate records by id;
- track whether each gate is open;
- track active blocker count;
- track opened gate count;
- track extraction route lock state;
- apply ship-system summaries idempotently;
- provide summary and HUD/status lines for consumers.

Expected public methods:

- `configure_from_blocked_routes(route_gate_ids: Array) -> void`
- `apply_ship_systems_summary(summary: Dictionary) -> bool`
- `get_summary() -> Dictionary`
- `get_status_lines() -> PackedStringArray`
- `is_gate_open(gate_id: String) -> bool`
- `is_extraction_unlocked() -> bool`

Initial state:

- powered route gates are closed;
- active blocker count equals the number of configured blocked routes;
- opened gate count is zero;
- extraction route is locked.

State transitions:

- if `main_power_restored=true` and `blocked_routes_cleared=true`, powered gates open and active blocker count becomes zero;
- if `extraction_unlocked=true`, extraction route becomes unlocked;
- repeated application of the same summary is a no-op from the caller's perspective.

### Runtime route gate/blocker nodes

`PlayableGeneratedShip` creates a `route_control_root` under the main scene. For each node returned by `loader.get_blocked_route_nodes()`, it creates a simple runtime gate/blocker near that world position.

The first gate implementation can be a simple `StaticBody3D` with a `CollisionShape3D`. It does not need final art. Its purpose is to make passability real.

Required metadata on each gate node:

- `route_gate_id`
- `route_gate_kind`
- `required_system`
- `route_gate_open`

Closed gate behavior:

- visible or otherwise inspectable;
- collision enabled;
- `route_gate_open=false`.

Open gate behavior:

- collision disabled;
- optionally hidden or visually softened;
- `route_gate_open=true`;
- `system_cleared=true`.

Gate nodes should remain in the scene after opening. This keeps state inspectable and preserves a seam for future animation or visuals.

### `PlayableGeneratedShip` integration

`PlayableGeneratedShip` will:

- preload and own `RouteControlState`;
- create `route_control_root` during runtime node setup;
- build route gates from `loader.get_blocked_route_nodes()` after the ship loads;
- configure `RouteControlState` with created gate ids;
- after each objective completion, pass the latest ship-system summary to `RouteControlState`;
- apply route scene consequences by enabling/disabling collision and updating gate metadata;
- expose validation helpers:
  - `get_route_control_summary() -> Dictionary`
  - `get_route_gate_nodes() -> Array`
  - `get_route_gate_collision_enabled_count() -> int`

This keeps route-control state testable without requiring consumers to inspect node internals, while still proving that scene collision changes.

### HUD integration

The HUD remains compact. It should not grow into a noisy debug panel.

`ObjectiveTracker` can continue receiving already-composed system status lines. `PlayableGeneratedShip` should combine ship-system and route-control status into the existing status-line flow.

Example status after power restore:

```text
Systems:
  Power: 72%
  Reactor: 22%
  Routes: POWERED OPEN
  Extraction: LOCKED
```

Example status after reactor stabilization:

```text
Systems:
  Power: 72%
  Reactor: 100%
  Routes: POWERED OPEN
  Extraction: UNLOCKED
```

Existing HUD strings must remain intact for regression smokes:

- `Sargasso First Playable`
- `Controls: WASD move / E interact`
- `Progress:`
- `Current:`
- `Prompt:`

## Testing Strategy

Testing is Godot-headless and runtime-focused. The milestone does not depend on screenshots.

### New smoke

New file:

`/Users/christopherwilloughby/the-sargasso-of-stars/scripts/validation/main_playable_slice_route_control_smoke.gd`

The smoke should instantiate `res://scenes/main.tscn`, wait for `PlayableGeneratedShip`, and assert the route-control lifecycle.

Initial assertions:

- route-control model exists;
- at least one powered route gate/blocker exists;
- active blocker count is at least one;
- opened gate count is zero;
- extraction route is locked;
- route blocker collision is enabled;
- route blocker metadata says `route_gate_open=false`.

After objective 1, `recover_supplies`:

- route gate remains closed;
- extraction remains locked.

After objective 2, `restore_systems`:

- `main_power_restored=true`;
- route-control state says powered gates are open;
- active blocker count becomes zero;
- opened gate count is at least one;
- route blocker collision is disabled;
- route blocker metadata says `route_gate_open=true`.

After objective 3, `download_logs`:

- route remains open;
- extraction remains locked.

After objective 4, `stabilize_reactor`:

- `extraction_unlocked=true`;
- route-control state says extraction is unlocked;
- slice completion still works.

Required pass marker:

```text
MAIN PLAYABLE ROUTE CONTROL PASS gates=1 opened=1 blockers=0 extraction=true
```

If the gate count is greater than one, the marker may report the actual count, but it must still prove at least one gate opened and zero blockers remain active.

### Regression smokes

Run these after the new route-control smoke:

```bash
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_route_control_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_ship_systems_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_completion_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_input_smoke.gd
/Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-sargasso-of-stars --script res://scripts/validation/main_playable_slice_readability_smoke.gd
```

Output should be clean of unexpected `ERROR:` or `WARNING:` lines.

## Success Criteria

The milestone is successful when:

- route-control state exists and is separate from ship-system state;
- at least one runtime gate/blocker is created in the main playable scene;
- closed gates have active collision;
- restored power opens powered gates;
- opened gates have disabled collision and updated metadata;
- extraction remains locked until reactor stabilization;
- HUD route status updates without breaking existing HUD strings;
- existing objective progression and smokes continue to pass;
- no proof artifacts are created as the milestone deliverable.

## Failure Criteria

The milestone fails if it:

- only hides a prop again;
- only adds HUD text;
- only asserts counters without scene-side collision changes;
- deletes gate nodes instead of preserving inspectable state;
- breaks existing playable smokes;
- creates HTML, PNG, contact sheets, or proof documents as the primary output.

## Scope for the Implementation Plan

The implementation plan should be TDD-first:

1. Write the route-control smoke and watch it fail because the API or model is missing.
2. Add `RouteControlState`.
3. Add route-control root and gate construction to `PlayableGeneratedShip`.
4. Wire ship-system summaries into route-control state after objective completion.
5. Apply collision/metadata consequences to route gate nodes.
6. Update HUD status-line composition as needed.
7. Run the new smoke and regressions cleanly.

## No-Git Tracking

This workspace is not currently a git repository. Instead of a commit, design and implementation changes should be recorded in a no-git ledger. For this design phase, use:

`/tmp/sargasso_route_control_no_git_changes.log`
