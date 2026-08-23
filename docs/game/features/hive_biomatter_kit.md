# Feature: Hive Template and Biomatter Kit Remap

## Status

In implementation (REQ-HIVE-001). First milestone is a kit-id stamp using
existing v0 wrapper scenes, not a visual remap.

## Requirement cross-reference

- REQ-HIVE-001 in `docs/game/05_requirements.md`
- ADR-0053 catalog fallback (when present, `ModularSocketCatalog.load_kit`
  falls back to `ship_structural_v0` contracts when a kit directory is missing)
- Related: `docs/game/features/remaining_procgen_play_stack.md`,
  `docs/game/features/socketed_enclosed_interiors.md`

## Design pillar alignment

- Pillar: derelict exploration of enclosed, readable ship volumes.
- Why this feature supports it: a hive cluster is the same occupancy
  rooms as a wreck, overgrown by a biomatter kit on the same sockets —
  not a second generator.

## Player fantasy

The player boards a short-core hive: clustered compartments around a
corridor, one lateral overgrown pocket, destination on the bow. It
should feel like the same ship architecture eaten by growth, not a
unique mesh set.

## Gameplay problem

There is no `hive` topology template. `ShipGenerator` always passed
`ship_structural_v0.json` into the loader, so layout `kit_id` never
changed instantiated wrappers. Hazard/industrial kits have no
`modules[].godot_wrapper_scene` array. Hive flavour lived only in
encounter/dressing (`biomatter_crusted`).

## Core behavior

1. `data/procgen/templates/hive.json` is occupancy-in: clustered
   compartments around a short **linear** corridor core (`count: [2, 3]`,
   same pattern as `compact.json` spine), one lateral overgrown pocket,
   destination on the bow. Integer cells, shared cardinal edges. Same
   schema as `derelict_a.json`.
2. `"hive"` is appended to `TemplateSelector.EXTENDED_TEMPLATES` only.
   It is not a derelict guaranteed template and is not forced into the
   16-seed quality-gate pool.
3. `ShipLayoutGenerator._generate_once` stamps `layout.template_id`
   after serialize (not in `LayoutSerializer`). When
   `template_id == "hive"`, `kit_id = ship_structural_biomatter`,
   independent of biome. `_kit_id_for_biome` is unchanged.
4. `data/kits/ship_structural_biomatter.json` copies v0 `modules[]`
   with the same `module_id`s and `godot_wrapper_scene` paths.
5. `ShipGenerator` resolves `res://data/kits/%s.json` from
   `layout.kit_id`. Missing file or no `modules[].godot_wrapper_scene`
   array falls back to v0. Hazard/industrial keep falling back until
   they gain that array.

## Inputs

- Archetype `template: "hive"` (explicit) or extended-pool RNG.
- Layout pipeline seed / blueprint. Biome id does not override hive kit.

## Outputs

- Generated layout with `template_id=hive` and
  `kit_id=ship_structural_biomatter`.
- Loader instances v0 wrapper scenes via the biomatter kit map.
- Compiler sockets fall back to v0 contracts (no biomatter contract dir).

## Rules

- Occupancy stays 4-connected integer cells with shared cardinal edges.
- Hive kit binds on `template_id`, not biome.
- First milestone wrappers are v0 paths (stamp, not visual remap).
- Do not add hive to `AVAILABLE_TEMPLATES`, `DERELICT_TEMPLATES`, or
  the derelict archetype `template` key.

## Non-goals

- Unique hive GLBs or skinned biomatter wrappers.
- A fourth biome.
- WFC or voxel interiors.
- Forcing hive into derelict guaranteed templates or the quality-gate
  seed pool.

## Technical design

- `data/procgen/templates/hive.json`
- `scripts/procgen/template_selector.gd`
- `data/kits/ship_structural_biomatter.json`
- `scripts/procgen/ship_layout_generator.gd`
- `scripts/procgen/ship_generator.gd`
- `scripts/validation/hive_biomatter_kit_smoke.gd`

## Acceptance criteria

- Given `hive.json` and extended template selection, when the layout
  pipeline runs with `template: "hive"`, then occupancy rooms share
  cardinal edges and `template_id` is `hive`.
- Given a hive layout, when biome is `breach_field`, then `kit_id` is
  still `ship_structural_biomatter`.
- Given the biomatter kit JSON, when the catalog loads sockets, then
  contracts fall back to v0 and every `godot_wrapper_scene` is a v0 path.
- Given `ShipGenerator`, when `layout.kit_id` names a kit without a
  wrapper map, then the loader receives `ship_structural_v0.json`.

## Validation

```bash
ROOT="${ROOT:-.}"
GODOT="${GODOT:-/opt/homebrew/bin/godot}"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hive_biomatter_kit_smoke.gd
```

Expected: `HIVE BIOMATTER KIT PASS template=true kit=true sockets_fallback=true occupancy=true v0_paths=true`

Also remains green: `template_selector_smoke.gd` (legacy three),
`kit_catalog_smoke.gd`.

## Risks

- Adding a kit JSON increments `KitCatalog.configure()` load count;
  update the `kit_catalog_smoke` bundle pin if the printed `loaded=`
  changes.
- A crowded hive occupancy can fail shared-edge placement; keep the
  core short and clustered rooms modest.

## ADRs

- ADR-0053 (socketed enclosed interiors; catalog fallback)
- No new ADR for hive (occupancy + kit stamp, not architecture)
