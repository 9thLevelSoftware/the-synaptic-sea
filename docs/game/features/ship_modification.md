# Feature: Ship modification & fleet meaning

## Status

Approved (pre-implementation)

## Design pillar alignment

- Pillar: Salvage / Craft / Repair endgame (pre-polish plan Part 2.6) + World/Fleet (Part 6.3)
- Why: Captured ships become upgrade donors and platforms; hub growth is physical

## Player fantasy

Rip the good recycler out of a prize ship, or keep the whole hull because its engine bay is intact. Power budget forces PZ-style base-building tradeoffs. Your own ship is the explorable hub.

## Gameplay problem

Docking/hangar/ship-in-ship are mechanically complete, but ships are not differentiated and ownership has no mechanical reward beyond cargo space.

## Core behavior

- Ships carry a component manifest (from component_slots).
- Install verbs mount salvaged components into home (and claimed) ship slots.
- Power budget tables (`power_budget_tables.json`) constrain installs.
- Hull work: patch/replace damaged modules with salvaged plating via module integrity.
- Walkable home ship + stations + hydroponics replaces a separate hub scene deferral.

## Inputs

- Component inventory / manifests
- Empty or occupied slots on target ship
- Power budget + ShipSystemsManager capacities
- ModuleIntegrityMap on player ships

## Outputs

- Changed system capacities; visible installed components; power overdraw failure modes; travel/hull resilience

## Rules

1. Capture reason is mechanical (parts or platform), not cosmetic.
2. Better components draw more power; illegal installs are gated, not silently applied.
3. Module integrity applies to player ships (travel damage, docking welds per ADR-0016/17).
4. No separate hub scene required once home interior supports stations/components.

## Non-goals

- Multiplayer fleet AI
- Full 3D exterior ship editor
- Narrative-only ship skins without mechanical effect

## Technical design

- Extends ShipRuntime / ShipInstance snapshots
- WorkAction install/uninstall verbs
- Power budget consumers already data-backed
- Requirements: REQ-SMOD-001..REQ-SMOD-003
- Depends: component_slots, work_actions, module_integrity, ShipRuntime multi-instance

## Acceptance criteria

- Given a scavenged fabricator head and an empty home station slot, when install completes, then station tier/capacity rises and power draw increases.
- Given over-budget power, when player attempts install, then install is rejected or systems degrade per authored rules.
- Given a damaged home hull module and salvaged plating, when patch/replace WorkAction completes, then integrity improves and is visible/persistent.

## Validation

- Install/uninstall pure + scene smokes
- Power budget constraint smoke
- Home-ship station interaction verification (explorable hub)

## Risks

- Snapshot schema growth; coordinate with persistence package
- UI ship-mod screen is consumer work (panel framework reuse only)
