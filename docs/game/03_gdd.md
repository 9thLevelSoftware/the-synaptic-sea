# 03 Living Game Design Document

## Purpose

This is the master GDD. It should stay concise and link to feature specs rather than duplicate every detail.

## Vision

See `00_vision.md`.

## Design pillars

See `01_design_pillars.md`.

## Core loop

See `02_core_loop.md`.

## Camera and perspective

- Locked-isometric 3D.
- Orthographic readability is a core requirement.
- Spatial coherence and traversal clarity outrank visual spectacle.

## Player verbs, current and planned

Current:
- Move through generated ship spaces.
- Interact with objective affordances.
- Complete objective sequence.
- Restore systems and unlock routes.

Planned candidates:
- Avoid or mitigate hazards.
- Use inventory/tools to bypass or repair obstacles.
- Salvage resources.
- Make route/return/extraction decisions.

## World and level structure

The current unit of play is a generated derelict ship interior. Rooms, corridors, blocked routes, objectives, and extraction should be represented as runtime data plus scene consequences.

## Feature specs

- `features/route_control.md`
- `features/hazards.md` (validated for the Gate 1 runtime slice)
- Future: `features/inventory_tools.md`
- Future (deferred through Gate 2 per ADR-0003): `features/hub_progression.md`

## Scope cuts for current gate

- No enemies unless a feature spec is approved.
- No content-scale work until the systems slice is stable.
- No production art pipeline beyond what supports gameplay validation.
- No multiplayer.
- **No hub/meta progression in Gate 1 or Gate 2.** The derelict exploration loop is the unit of Gate 2 production work; hub ship, derelict selection, persistent unlocks, and meta-currency are deferred through Gate 2 per ADR-0002 and ADR-0003. The reactor-stabilization completion state remains the Gate 1 stand-in for "return progress to hub," while Gate 2 deepens the derelict loop with inventory/tools, hazards, objective/procedural variation, and current-run persistence.

## Gate status

Current gate: Gate 1 — Pre-production / playable systems slice.

Gate 1 exit requires a representative 60–120 second playable slice with coherent navigation, route/system state, one risk/pressure loop, and clean validation.

Hub/meta progression is NOT a Gate 1 or Gate 2 implementation requirement (see ADR-0002 and ADR-0003). It is anchored to Gate 3 entry planning before Alpha scope is accepted.