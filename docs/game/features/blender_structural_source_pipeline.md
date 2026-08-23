## Authority
- Structural JSON contracts own sockets, bounds, footprint, collision intent, and placement origin.
- `.blend` sources are editable representations of current visuals plus contract-derived helpers.
- Existing imported GLBs and Godot wrappers remain runtime authority for this phase.

## External source layout
```
/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/
  <module_id>.blend
  <module_id>.source.json
```

## Required Blender objects
- ModuleRoot_<module_id> — Empty, identity transform, contract custom properties
- Geometry — Collection containing imported visual meshes
- AuthoringHelpers — Collection containing source-only helpers
  - Origin — Empty at (0, 0, 0)
  - Anchor_FloorCenter — Empty at (0, 0, 0)
  - Anchor_SOCK_<socket_id> — One Empty per contract socket
  - CollisionProxy — Non-rendering wireframe mesh from contract bounds

## Coordinate mapping
contract [x, y, z] maps to Blender [x, z, y].

## Prohibited actions
No GLB export/re-export, no replacement of `assets/imported`, no wrapper/manifest/contract edits, and no direct manual edits to `.source.json`.

## Recovered structural modules
The source-recovery allowlist contains these 15 modules:
- `floor_1x1`
- `floor_2x1`
- `corridor_floor_1x1`
- `corridor_floor_1x2`
- `wall_straight_1x1`
- `doorway_frame_open_1x1`
- `pillar_support_1x1`
- `ramp_up_1x2`
- `bulkhead_portal_2x1`
- `ceiling_cap_1x1`
- `doorway_frame_blocked_1x1`
- `wall_end_cap`
- `wall_inner_corner`
- `wall_outer_corner`
- `wall_t_junction`

## Future promotion gate
A later, separately approved plan must define staged export paths, GLB byte-change review, structural variant treatment, wrapper/contract compatibility, Godot import, and the full state-safe regression bundle before any source can affect runtime assets.

## Tools
- `tools/structural_source_contract.py` — Pure-Python contract loading and source-record serialization
- `tools/recover_modules.py` — Blender CLI that imports GLBs and writes .blend/.source.json
- `tools/inspect_structural_sources.py` — Blender inspector that reads .blend and prints JSON report
- `tools/validate_structural_sources.py` — Standard-Python validator comparing inspector reports to contracts

## Reproducible recovery commands
```bash
ROOT=/Volumes/Untitled/SynapticSeaAssets/worktrees/the-synaptic-sea-asset-metadata-retrofit
SOURCE_ROOT=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0

# Recover all 15 modules
/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/recover_modules.py -- \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" --all

# Validate all sources
/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" --all
```
