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
| 5 | Ship Docking & Ship-in-Ship | ✅ **Complete (5a + 5b + 5c + 5d)** | `docking_manager.gd`, `dock_ports.gd` (typed ports + compat + `for_hangar`/asymmetric compat), `ship_occupancy.gd`, `dock_port_barrier.gd` (welding-speeded breach); `ship_instance.gd` parent/child + real `interior_aabb`. Runtime port-aligned docking at boot+travel in `playable_generated_ship.gd` — travel is a real undock→dock loop (the piloted ship is the player's ride), NOT a menu teleport. Occupancy-gated boarding; dock-edge persistence. `ship_access_state.gd` (login-based ownership), `bridge_terminal.gd` (working-vessel gate), `set_piloted_ship` pilot-switch. `hangar_bay.gd` (fixed-slot bay), `hangar_bay_control.gd` (physical walk-up dock/launch), weighted `hangar` derelict role (+ home bay via cargo fallback), arbitrary-depth DFS rigid-pair travel (`_capture_subtree`/`_reposition_subtree`), `world-4` persistence (`port_type`/`slot_index`). Multiplayer access UI and the screen-space hangar/fleet UI are post-Phase-7 seams. ADR-0016, ADR-0017, ADR-0018, ADR-0019. |
| 6 | Inventory & Equipment | 🟡 **~85% — player inventory + loot + ship cargo holds + worn equipment/encumbrance + carts + inventory/transfer UI (Phase 7 slice A) done** | PlayerInventory (`inventory_state.gd`, PZ soft-cap, categorized) ✅; loot (`loot_roller.gd`, `loot_container.gd`, `item_definitions.json`, `loot_tables.json`) ✅; ship cargo holds (`ship_inventory.gd`, weight-capped 500, lazy on `ShipInstance.get_inventory()`), `CargoTransfer`, `CargoHoldControl`, additive persistence (ADR-0020) ✅; worn equipment (`equipment_state.gd`: suit/back/waist/hand slots, worn-container capacity bonus, suit oxygen-effect modeled), PZ soft-cap encumbrance + Heavy Load move penalty (`encumbrance.gd`), auto-equip-on-pickup, `WorldSnapshot.player_equipment` persistence ✅; pushable carts (`cart_state.gd` zero-encumbrance mobile container, `cart_control.gd` walk-up grab/load/unload, both-hands + push penalty, `ShipInstance.carts` + `WorldSnapshot.home_ship_carts` persistence) — ADR-0021 ✅; inventory/transfer UI (`InventorySelectionModel`, `InventoryPanel`, `cargo_move_item`, coordinator wiring, live O2-pump oxygen effect on transfer) — ADR-0022 ✅. *Remaining:* item-icon generation, partial-stack split UX polish, nested per-container weight-reduction, strength-skill capacity scaling, endurance/health Heavy Load (Phase 7 sub-slices B/C/D). |
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
| Phase 5 — Ship Docking & Ship-in-Ship | System 5 | ✅ done — 5a + 5b + 5c + 5d all built |
| Phase 6 — Inventory & Equipment | System 6 | 🟡 partial |
| Phase 7 — Integration & Polish | all (wire-together) | 🟡 in progress (slice A: inventory/transfer UI built) |

The recent sub-project cadence ran out of the suggested order, which is fine
under the isolate-then-integrate model: **#3 loot** delivered System 6's
player-inventory half ahead of Phase 6; **#4 repair** completed System 2's
repair flow. Out-of-order isolated delivery is the method working as intended.

## What remains

Two bodies of work, in the recommended order:

### A. Finish System 6 — Inventory & Equipment (Phase 6 remainder)
Player inventory + loot + ship cargo holds (player↔ship physical transfer, ADR-0020) are
done. The hold is a weight-capped `ShipInventory` on every `ShipInstance`, accessible via a
physical `CargoHoldControl` walk-up node; `CargoTransfer` deposits parts/supplies and
withdraws by category (tools excluded). Cross-ship transfer is emergent and physical (carry
into personal inventory, walk to the next ship, deposit). Remaining: carry containers
(bags/trolleys/carts raising per-trip haul capacity), EquipmentSlots (worn items that modify
actions), and the rich item-transfer UI (Phase 7). Unblocks "store salvage on your ship"
and equipment-gated actions.

### ✅ System 5 — Ship Docking & Ship-in-Ship (Phase 5) — COMPLETE
**5a (foundation), 5b (physical docking + typed ports), 5c (claim + pilot-switch
+ rigid-pair travel), and 5d (hangar nesting) are all built and merged.** The
player's lifeboat physically docks to a target derelict and stays docked as a
guaranteed ride; travel is a real undock→dock loop (the menu-teleport abstraction
is retired); typed dock ports gate boarding with a welding-speeded forced-entry
breach; occupancy and the dock-edge graph persist. Repairing a derelict's
propulsion lets the player **claim it** by logging in at its bridge terminal and
pilot it as their new vessel. Pilot-switch is physical: walk to any ship's bridge
and log in. 5d adds the **hangar bay**: a ship (a hangar-rolled derelict, or the
home ship via cargo fallback) stores other ships in fixed slots and carries a
**nested fleet of arbitrary depth** — physical walk-up dock/launch control,
`world-4` persistence of `port_type`/`slot_index`. `DockingManager`, `DockPorts`
(+ `for_hangar`), `DockPortBarrier`, `ShipAccessState`, `BridgeTerminal`,
`HangarBay`, `HangarBayControl`, and the parent/child `ShipInstance` forest exist
(ADR-0016, ADR-0017, ADR-0018, ADR-0019). Multiplayer access UI and the
screen-space hangar/fleet UI are post-Phase-7 seams.

### C. Phase 7 — Integration & Polish (the "wire it all together" step)
The endgame the whole isolation strategy was building toward: connect all
systems end-to-end, add the full UI/HUD layer (including the deferred live
repair-progress line — `RepairPoint.progress`/`repair_blocked` → HUD status —
and an inventory/weight panel), and balance (repair difficulty, loot
distribution, scanner upgrades). This is where isolated systems stop being
independently validated slices and become one game.

**Net: two phases remain (6, 7); System 5 is complete, and 6 is ~60% done (player inventory + loot + ship cargo holds built; carry containers + EquipmentSlots + transfer UI remain).**

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
