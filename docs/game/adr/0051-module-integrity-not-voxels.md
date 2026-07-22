# ADR-0051: Module integrity is the unit of destruction (not voxels)

- **Status:** Accepted
- **Date:** 2026-07-22
- **Supersedes / amends:** none (locks grain for salvage/craft/repair pillar)
- **Related:** cell layout pipeline, WallDoorResolver slots, ShipNavGraph, regenerate-from-seed persistence

## Context

The pre-polish plan raises the question of whether structural destruction should be voxel-grained (continuous or sub-cell volume editing) or module-grained (discrete kit modules already placed by the layout pipeline).

The live pipeline is already discrete at 4 m cell grain:

1. `CellLayoutEngine` places rooms as cell sets.
2. `WallDoorResolver` emits one structural module per cell-edge (`wall_straight_1x1`, `bulkhead_portal_2x1`, …) and already computes empty `wall_slots` / `center_slots`.
3. `GeneratedShipLoader` instantiates wrapper scenes per module.
4. `ShipNavGraph` pathfinds over discrete links.
5. Persistence regenerates geometry from seed and applies sparse deltas.

A voxel destruction model would invalidate the kit catalog, resolver, nav graph, wrapper scenes, and the regenerate-from-seed save model simultaneously. Locked-isometric camera also reads coarse module damage poorly at sub-cell resolution. The player fantasy (cut a bulkhead, strip a panel, weld a plate) is module- and component-grained, not 1/64-wall-grained.

## Decision

**Do not adopt a voxel destruction system.** The unit of destruction, salvage, and repair is the **structural module** (kit module instance), with mid-grain **mounted components** in wall/center slots.

### Integrity state machine

Every placed structural module owns integrity state:

```
intact → damaged → breached → destroyed
```

- **intact** — default pristine geometry/collision.
- **damaged** — cosmetic mesh swap + slower interactions through the module.
- **breached** (walls/hull) — atmosphere link to vacuum (feeds existing hull/field atmosphere); crawl-passable gap; collision adjusted.
- **destroyed** — module removed; collision gone; nav graph edge opened.

Material composition per kit module is data (`*.materials.json`); yields and tool classes derive from that table.

### Persistence

`ModuleIntegrityMap` lives in ship runtime context and serializes as **sparse deltas from pristine** (only touched modules persist). This matches regenerate-from-seed + apply-deltas exactly.

### What agents must not do

- Introduce voxel grids, chunk meshing, or continuous CSG destruction as the structural model.
- Re-litigate this ADR during pillar implementation without a new ADR that supersedes 0051.

### What agents must build instead (pillar contracts)

- `ModuleIntegrityState` / `ModuleIntegrityMap` pure models.
- WorkAction framework (cut / unbolt / weld / patch / pry / splice) against modules and components.
- Slot population for interior machinery (consumes existing empty slots).
- Scene consequences: mesh swap, collision toggle, nav link updates — not voxel remeshing.

## Alternatives considered

| Option | Why rejected |
| --- | --- |
| Full voxel hull | Invalidates kit, resolver, nav, save model; poor locked-iso readability; huge cost |
| Sub-cell fracture (hybrid) | Same pipeline breakage at smaller scale; still not the fantasy grain |
| Abstract HP only (no physical holes) | Fails "strip the derelict" and breach-as-route fantasy |

## Consequences

- Pillar packages (module integrity, work actions, components, ship modification) cite this ADR.
- Fire, decompression, threat structure damage, and player tools all route through module integrity; `breach_count` becomes derived where applicable.
- Placeholder damaged/breached mesh variants are acceptable pre-polish; schemas and verbs must be final.
- Validation must cover integrity transitions, sparse snapshot round-trip, and determinism under fixed seeds.

## Validation (when implemented)

- Pure-model: integrity FSM + sparse delta serdes.
- Scene: fire/tool breach opens traversable gap and vents atmosphere.
- Save/load: revisit restores stripped/damaged modules.
