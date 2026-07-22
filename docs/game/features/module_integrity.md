# Feature: Module Integrity Layer

## Status

Approved (pre-implementation)

## Design pillar alignment

- Pillar: Salvage / Craft / Repair (pre-polish plan Part 2.1)
- Why: Physical destruction and repair grain for the entire pillar; replaces any voxel ambition (ADR-0051)

## Player fantasy

Bulkheads burn through, decompress, and get cut open. Holes are real routes. Damage survives revisit.

## Gameplay problem

Structure damage today is abstract (`breach_count`, fire zones) without per-module physical state the player can strip, patch, or path through.

## Core behavior

- Pure `ModuleIntegrityState` per placed structural module: `module_id`, `kind`, `integrity`, `state ∈ {intact, damaged, breached, destroyed}`, `material_composition`, `mounted_components`.
- Ship-level `ModuleIntegrityMap` in ShipRuntime; sparse deltas from pristine for save/load.
- Transitions drive scene consequences: mesh swap, collision, nav edge, atmosphere link when breached.
- Damage sources: fire, threat structure attacks, decompression, player tools (WorkActions).

## Inputs

- Kit materials table (`ship_structural_v0.materials.json` or equivalent)
- Fire zone / decompression / tool damage events
- Snapshot apply on load / revisit

## Outputs

- Module state changes; derived breach count; passability; atmosphere coupling; salvage composition for WorkActions

## Rules

1. Unit of destruction is the kit module (ADR-0051) — not voxels.
2. Only touched modules serialize (sparse deltas).
3. `destroyed` removes collision and opens nav; `breached` vents and allows crawl.
4. Deterministic under fixed seed + same event order.

## Non-goals

- Final damaged/breached art (placeholders OK)
- Player dismantle verbs (WorkActions feature)
- Component slot population (component_slots feature)
- Full ShipRuntime extraction (architecture prerequisite; integrity mounts there when ready)

## Technical design

- Models: `scripts/systems/module_integrity_state.gd`, `module_integrity_map.gd`
- Data: kit materials JSON under `data/kits/` or `data/materials/`
- Scene applier: loader / integrity applier; ShipNavGraph link updates
- ADR: `docs/game/adr/0051-module-integrity-not-voxels.md`
- Requirements: REQ-MI-001..006

## Acceptance criteria

- Given a wall module at full integrity, when fire damage accumulates past thresholds, then state transitions intact→damaged→breached with atmosphere/nav consequences.
- Given a sparse snapshot of touched modules, when geometry regenerates from seed and deltas apply, then states match pre-save.
- Given two identical seeds and event sequences, when integrity advances, then maps are bit-equal.

## Validation

- Pure-model smoke: FSM, deltas, determinism
- Scene smoke: fire breach + vent + crawl gap + save/load restore
- Register in `docs/game/06_validation_plan.md`

## Risks

- Loader/nav coupling conflicts with parallel dressing/component work — serialize loader ownership.
- Coordinator size; prefer ShipRuntime mount once A1 lands.
