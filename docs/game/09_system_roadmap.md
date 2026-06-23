# 09 System Roadmap — Consolidated Build State

Date: 2026-06-22
Status: Living document. Supersedes the scattered phase/gate/sub-project tracking as the single answer to "what is built, what remains."

## Why this document exists

Progress had been tracked in three overlapping places that no longer told one
story:

1. **The stage-gate pipeline** (`08_milestone_gates.md`, Gate 0–5) — a
   *process* ladder (concept → release candidate). **All gates are closed.**
   Gate 5 exited 2026-06-20 with a v0.1.0 release candidate. The stage-gate
   pipeline has nothing left to advance; it is historical.
2. **The system-first build phases** (`specs/2026-06-20-sargasso-core-systems-design.md`
   §"Build Phases", Phases 1–7) — the *engineering* roadmap.
3. **The brainstorm→spec→plan sub-projects** (loot, repair, …) — the *cadence*
   we actually execute in, which has run slightly out of phase order.

This document reconciles all three into the build state that matters: the
**system-isolation roadmap**. The founding principle is unchanged — *isolate
each system the game needs, build each one completely in isolation behind a
clean interface, then wire them together at the end.* The numbered phases are
just a suggested order through those systems; the sub-project cadence is how we
deliver them. They do not conflict.

## The core architecture: 8 isolated systems

From the core-systems design. Each is meant to stand alone behind an interface
and be validated independently before integration.

| # | System | Status | Primary evidence |
|---|--------|--------|------------------|
| 1 | Ship Generation Framework | ✅ **Complete** | `scripts/procgen/*` (template_selector → room_assigner → cell_layout_engine → wall_door_resolver → layout_serializer → generated_ship_loader), `ship_generator.gd`, `ship_layout_generator.gd`, `gameplay_slice_builder.gd`, `life_boat.gd`, `start_scene_builder.gd`, `playable_generated_ship.gd`. Procgen + golden ships share one load path. Design: `specs/2026-06-20-procgen-layout-pipeline-design.md`. |
| 2 | Ship Systems (6 systems + repair) | ✅ **Complete** | `ship_systems_manager.gd`, `ship_system.gd`, `ship_subcomponent.gd`, `life_support_system.gd`; dependency cascades (ADR-0008, ADR-0009); hazards (oxygen/fire/electrical_arc/route_control/junction_calibrator, ADR-0005); timed parts-gated repair (`repair_point.gd`, `repair_with_inventory`, ADR-0015). |
| 3 | Player Progression (class + skills) | 🟢 **Slice built** | `class_definition.gd`, `player_progression_state.gd`; XP + repair-skill integration (ADR-0010). Repair skill speeds the repair channel. *Remaining:* full 8-class roster, full five-category skill tree, cross-training XP costs, training-by-item. |
| 4 | Scanner & Travel | 🟢 **Slice built** | `scanner_state.gd`, `travel_controller.gd`, `marker_generator.gd`, `ship_marker.gd` (ADR-0011, phase4 + phase4.5 specs). Menu-based travel works; propulsion gates onward travel (repair loop). *Remaining:* multi-level scanner detail/upgrades (currently basic). |
| 5 | Ship Docking & Ship-in-Ship | 🟢 **Foundation (5a) + physical docking & ports (5b) built** | `docking_manager.gd`, `dock_ports.gd` (typed ports + compat), `ship_occupancy.gd`, `dock_port_barrier.gd` (welding-speeded breach); `ship_instance.gd` parent/child + real `interior_aabb`. Runtime port-aligned docking at boot+travel in `playable_generated_ship.gd` — travel is now a real undock→dock loop (the piloted ship is the player's ride), NOT a menu teleport. Occupancy-gated boarding; dock-edge persistence. ADR-0016, ADR-0017. *Remaining (5c):* claim/pilot a repaired derelict, ship-in-ship hangar nesting. |
| 6 | Inventory & Equipment | 🟡 **~40% — player half done** | PlayerInventory (`inventory_state.gd`, weight-capped, categorized) ✅; loot (`loot_roller.gd`, `loot_container.gd`, `item_definitions.json`, `loot_tables.json`) ✅. *Remaining:* ShipInventory (per-ship storage), EquipmentSlots (suit/tool-belt/etc.), item transfer player↔ship↔ship, equipment & data item categories. |
| 7 | Procedural Generation Details | ✅ **Complete** | Folded into System 1 — room roles, graph rules, structural placement, deterministic-per-seed all delivered in the procgen pipeline. |
| 8 | Sargasso World & Scanner Display | ✅ **Complete** | `sargasso_world.gd` (registry + spatial grid), `scanner_panel.gd`, `marker_generator.gd`. Folded into System 4's delivery. |

### Cross-cutting layers built beyond the original 8

These were not in the original system list but emerged as necessary integration
glue and are done:

- **World persistence** — `world_snapshot.gd`, `save_load_service.gd`, `run_snapshot.gd` (ADR-0012). Disk save/load of world + per-ship slices; geometry regenerates from seed.
- **Ship identity & travel integration** — `ship_instance.gd` (ADR-0011): ships are durable identities with persisted mutable state.
- **Derelict gameplay parity** — `derelict_objective_controller.gd` (ADR-0013): boarded derelicts run the same objective/hazard/loot loop as the home ship.

## Build-phase crosswalk

| Build phase (core design) | Maps to system(s) | Status |
|---------------------------|-------------------|--------|
| Phase 1 — Ship Generation Framework | System 1 (+7) | ✅ done |
| Phase 2 — Ship Systems | System 2 | ✅ done |
| Phase 3 — Player Progression | System 3 | 🟢 slice |
| Phase 4 — Scanner & Travel | Systems 4, 8 | 🟢 slice |
| Phase 5 — Ship Docking & Ship-in-Ship | System 5 | 🟢 5a foundation + 5b physical docking & ports built; 5c (claim/pilot 2nd ship, hangar nesting) remains |
| Phase 6 — Inventory & Equipment | System 6 | 🟡 partial |
| Phase 7 — Integration & Polish | all (wire-together) | ⛔ not started |

The recent sub-project cadence ran out of the suggested order, which is fine
under the isolate-then-integrate model: **#3 loot** delivered System 6's
player-inventory half ahead of Phase 6; **#4 repair** completed System 2's
repair flow. Out-of-order isolated delivery is the method working as intended.

## What remains

Three bodies of work, in the recommended order:

### A. Finish System 6 — Inventory & Equipment (Phase 6 remainder)
Smallest, builds directly on shipped loot/inventory. Add ShipInventory
(per-ship storage containers), EquipmentSlots (worn items that modify actions),
and item transfer (player↔ship, ship↔ship when co-located). Unblocks "store
salvage on your ship" and equipment-gated actions.

### B. Build System 5 — Ship Docking & Ship-in-Ship (Phase 5)
The system that makes the world physical. **5a (foundation) and 5b (physical
docking + typed ports) are built and merged:** the player's lifeboat is a
functional ship that **physically docks** to a target derelict and stays docked
as a guaranteed ride; travel is a real undock→dock loop (the menu-teleport
abstraction is retired); typed dock ports gate boarding with a welding-speeded
forced-entry breach; occupancy and the dock-edge graph persist. `DockingManager`,
`DockPorts`, `DockPortBarrier`, and the parent/child `ShipInstance` hierarchy
exist (ADR-0016, ADR-0017). **Remaining — 5c:** repairing a derelict's
propulsion lets the player **claim a second functional ship**; ships nest in
hangars (ship-in-ship) and travel together; piloting/switching the active ship.
Depends on nothing from A, but sharing inventory across docked ships is cleaner
once A exists.

### C. Phase 7 — Integration & Polish (the "wire it all together" step)
The endgame the whole isolation strategy was building toward: connect all
systems end-to-end, add the full UI/HUD layer (including the deferred live
repair-progress line — `RepairPoint.progress`/`repair_blocked` → HUD status —
and an inventory/weight panel), and balance (repair difficulty, loot
distribution, scanner upgrades). This is where isolated systems stop being
independently validated slices and become one game.

**Net: three phases remain (5, 6, 7); one of them (6) is already partly done.**

## Explicitly out of scope (future expansions)

Per the core-systems design, deferred beyond the core build — not part of the
3 remaining phases:

- Fortify/defend mechanics and monster/creature encounters (combat).
- Alien ship types; ultra-rare jump-drive escape win condition.
- NPC encounters (survivors, traders); crafting-system expansion.
- Multiplayer; narrative/story; music and audio.

These are real ambitions for the game but are sequenced *after* the core
loop is wired together in Phase 7, and each will get its own spec when it
comes up.
