# ADR-0011: ShipInstance abstraction and live travel integration

Date: 2026-06-21
Status: Accepted
Supersedes: none
Related: Phase 4 scanner/travel design; System 4/5 in the core-systems master spec

## Context

Phases 1–3 are integrated into the live coordinator `PlayableGeneratedShip`, but
Phase 4 (scanner/travel/Synaptic Sea) was built as pure logic with no in-game wiring,
and there was no first-class "ship" object: `TravelController.attempt_travel()`
returned a `Node3D` nobody held, and the coordinator owned exactly one hardcoded
ship with a single `ShipSystemsManager`. Phase 5 docking ("attach ship B to ship
A") cannot be designed without a ship identity to attach ports/hierarchy to.

## Decision

Introduce `ShipInstance` (RefCounted): a per-ship handle bundling `ship_id`,
`marker_id`, `blueprint`, its own `ShipSystemsManager`, the generated `scene_root`,
and declared-but-unused Phase-5 docking stubs (`parent_ship`, `docked_ships`,
`docking_ports`). The coordinator wraps its starting ship as `current_ship`, owns a
`Synaptic SeaWorld`/`ScannerState`/`TravelController`/`ShipGenerator`, and exposes
`scan()` / `travel_to()` that swap `current_ship` and re-home the player on success.

Boundary (Approach A): only state that MUST be per-ship for travel to be real moves
into `ShipInstance`. The rich hazard/objective/oxygen sim stays on the coordinator,
attached to the starting ship; it is paused (`away_from_start`) while the player is
aboard a traveled derelict. `ShipInstance` never frees its own `scene_root` — the
coordinator owns scene-tree lifecycle (single ownership).

## Consequences

- Travel is gated by the CURRENT ship's systems. On the STARTING ship this is the
  intended emergent mechanic: board a wrecked derelict with dead propulsion → stranded
  until repaired. On a BOARDED DERELICT, however, Phase 4.5 ships no derelict
  repair/objective flow, so condition-gating would softlock the player with no in-game
  way to leave or repair. Therefore boarded derelicts report FULL scanner/travel
  capability (`_current_systems_ops()` short-circuits to `{navigation:true,
  scanners:true, propulsion:true}` when `away_from_start == true`). Stranding-by-
  condition on derelicts is deferred to the future derelict repair loop.
- While aboard a derelict, starting-ship interactions are gated off:
  `_on_player_interact_requested` early-returns when `away_from_start == true`, so
  pressing interact on a derelict cannot complete stale starting-ship objectives.
  Derelicts have no interactables of their own yet, so nothing legitimate is lost.
- Traveled derelicts are STATELESS: freed on leave, regenerated deterministically
  from seed on return. Loot/repairs on traveled ships do not persist yet. True world
  persistence is deferred to the meta-save phase (the current `RunSnapshot` is the
  single-ship-slice save; the world that wraps it does not exist yet). The starting
  ship keeps its full persistent sim (detached-not-freed on travel).
- Full per-ship state extraction (hazards/objectives into `ShipInstance`, coordinator
  as a thin multi-ship manager) is the eventual target (Approach B) but deliberately
  deferred; the `ShipInstance` seam introduced here is exactly what B would grow.
- Phase 5 docking attaches to the stable `parent_ship`/`docked_ships`/`docking_ports`
  shape declared here.
