# Feature: Component slots & interior machinery

## Status

Approved (pre-implementation)

## Design pillar alignment

- Pillar: Salvage / Craft / Repair + Procgen dressing (pre-polish plan Parts 2.3, 5.2)
- Why: Mid-grain salvage between loot containers and structural modules; physically embodies ship-system subcomponents

## Player fantasy

Rooms are full of machines you can repair in place or rip out and haul home. The derelict's failing recycler is a real object in a real room.

## Gameplay problem

`WallDoorResolver` already computes `wall_slots` and `center_slots`; nothing populates them. Ship systems exist as pure data with repair points as the only physical presence.

## Core behavior

- Component catalog: per room role/variant weighted sets (biome/dressing bias).
- Deterministic placement stage after structure load fills wall/center slots.
- Link pass maps `systems.json` subcomponents onto placed components per ship.
- Mount/dismount as WorkActions; dismounted form is a heavy inventory item (cart economics).
- Linked components light up `ShipSystemsManager` damage/repair.

## Inputs

- Layout slots from WallDoorResolver
- Component catalog JSON
- Seed + room role/variant/dressing
- Ship systems subcomponent list

## Outputs

- Placed interactive components; inventory items on dismount; system capacity/state coupling

## Rules

1. Placement is seeded and deterministic (same contract as the rest of the pipeline).
2. Slot collision and reachability are validated in smoke.
3. Every ship-system subcomponent that can be damaged must exist somewhere physical after link pass (or be explicitly marked non-physical in data).
4. Components strip, carry, and reinstall without bespoke code paths.

## Non-goals

- Full ship-modification install UI / power budget tradeoffs (ship_modification feature)
- Final machine art (placeholder meshes OK)
- Loot container redesign

## Technical design

- New placement stage script in procgen/loader chain
- Component catalog under `data/`
- WorkAction verbs for mount/dismount
- Requirements: REQ-CMP-001..006
- Depends: ADR-0051, work_actions, preferred after dressing consumption

## Acceptance criteria

- Given a seed and layout with non-empty slots, when placement runs, then components occupy slots without overlap and are interactable.
- Given a linked damaged subcomponent, when the player repairs or rips it, then ship system state reflects the change.
- Given a dismounted component, when carried to home slots (ship_modification), then reinstall is a WorkAction (may land in later package).

## Validation

- Slot population + collision/reachability pure/scene smoke
- Link pass smoke against systems.json
- Mount/dismount yield/encumbrance smoke

## Risks

- Loader ownership serialization with module integrity scene work
- Catalog authoring volume — start thin, schema-final
