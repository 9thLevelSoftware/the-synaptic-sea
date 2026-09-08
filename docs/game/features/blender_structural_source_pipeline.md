# Blender structural source pipeline

Shared art measurements: `data/art/structural_visual_dimensions.v1.json`. This art-only policy does not replace source-attestation or runtime collision/navigation authority.

This document is the source/helper runbook. The shared visual policy is [`modular_structural_fit.md`](modular_structural_fit.md); this pipeline does not replace runtime placement or physics authority.

## Authority and scope

- Structural JSON contracts own IDs, sockets, bounds, footprint, collision intent, navigation intent, and placement origin.
- `.blend` files are editable visual sources plus contract-derived helpers.
- Existing imported GLBs and Godot wrappers remain runtime authority until a separately approved promotion clears all gates.
- `tools/structural_source_contract.py`, Blender inspection, and `tools/validate_structural_sources.py` are source/helper validators. They prove source structure and contract-derived helper mapping; they do not prove visual fit or whole-assembly quality.
- `tools/structural_visual_contract.py` and `tools/validate_structural_visual_fit.py` are visual/interface validators. They consume actual transformed triangles from a fresh GLB import; they do not own sockets, collision, navigation, wrappers, or procgen topology.
- Root-code runtime authority remains `scripts/procgen/walkability_contract.gd`, the structural compiler/placement consumers, per-module contracts, and matching wrappers.

This is an art-only update. Do not migrate source attestation, alter placement JSON or `.tres` wrappers, enlarge collision, rewrite navigation, or move sockets. A legacy local bounds record with zero thickness is not visual geometry-dimensions authority. Preserve the helper contract and widen/scale the visual shell when necessary.

## Source layout and required objects

Sources remain external so editable Blender files can be backed up independently:

```text
/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/
  <module_id>.blend
  <module_id>.source.json
```

Each source must contain:

- `ModuleRoot_<module_id>` with identity transform and contract metadata;
- `Geometry` for visual meshes;
- `AuthoringHelpers` for source-only helpers;
- `Origin` and `Anchor_FloorCenter` at the contract origin;
- `Anchor_SOCK_<socket_id>` for every contract socket;
- `CollisionProxy` as a non-rendering wireframe helper generated from contract bounds.

Put exportable visual states in `Export_*` collections with `variant_role` `intact`, `damaged`, or `breached`. Do not export helpers, cameras, lights, rigs, or collision meshes.

## Shared modular-fit policy for source authors

All values are metres in runtime/Godot Y-up coordinates:

- 4 m lattice; finished floor datum `Y=0`; slab underside `Y=-0.25`.
- Positive walkable relief `0`; recesses at most `0.02` m and only outside protected walking guards.
- Wall/top height `3.2` m.
- The complete edge visual envelope is `0.20` m deep, normal `[-0.10,+0.10]`. There is no additional outward decoration allowance: recess detail or use materials inside that same envelope.
- `terminal_mating_band_m` = `0.20` m along the edge tangent at each terminal. Preserve its full `3.2` m height and `0.20` m depth, including planar end faces and continuous band surfaces. No bevel, trim, greeble or damage may consume it.
- Open doorway clear opening is `1.2 × 2.2` m, X `[-0.6,+0.6]`, Y `[0,2.2]`, Z `[-0.1,+0.1]`; no raised threshold.
- The pillar `footprint_cells` is `[1,1]` on the `4.0` m lattice, with centered X/Z contacts and Y contacts at `0` and `3.2`. The policy reserves that cell footprint; it does not prescribe a separate cosmetic body width or a filled-cell cube.

- These seven profiles are auto-supported: `floor_1x1`, `floor_2x1`, `corridor_floor_1x1`, `corridor_floor_1x2`, `wall_straight_1x1`, `doorway_frame_open_1x1`, and `pillar_support_1x1`. All other module IDs require reviewed profiles and fail closed as `hold`, not as bad geometry. `ramp_up_1x2` remains HOLD because its endpoint transform is not authorized.

Use flat/color textures, normals, and trim sheets for microdetail. Reserve actual geometry for readable large features, silhouette changes, deep recesses, braces, and service pipes. Use salvage steel and safety amber for practical cues. Godot Compatibility has no equivalent Decal path to rely on: prefer baked materials, or a tightly bound non-colliding `Sprite3D`/overlay mesh with deliberate depth sorting. Do not apply a blanket overlay offset.

## Coordinate contracts

Preserve the legacy helper mapping exactly:

```text
contract/helper [x, y, z] -> Blender [x, z, y]
```

This is for contract-derived helpers, sockets, bounds, and source inspection. Physical Blender geometry is Z-up and uses native glTF/runtime axes `[x, z, -y]`; the helper mapping is not the geometry conversion and must not be applied twice.

## Recovery and source validation

The recovery allowlist remains the existing 15 source modules:

`floor_1x1`, `floor_2x1`, `corridor_floor_1x1`, `corridor_floor_1x2`, `wall_straight_1x1`, `doorway_frame_open_1x1`, `pillar_support_1x1`, `ramp_up_1x2`, `bulkhead_portal_2x1`, `ceiling_cap_1x1`, `doorway_frame_blocked_1x1`, `wall_end_cap`, `wall_inner_corner`, `wall_outer_corner`, `wall_t_junction`.

Recovery is not visual approval. Run the source validator with the actual parser:

```bash
ROOT=/Volumes/Untitled/SynapticSeaAssets/worktrees/room-kit-v2
SOURCE_ROOT=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0

python3 tools/validate_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" --module floor_1x1
# Repeat --module, or use --all for the source-recovery allowlist.
```

This gate checks source existence, module/source-record agreement, required helpers and sockets, contract-to-Blender helper positions, collision-proxy bounds, and variant inventory. It does not prove visual dimensions, transformed triangle coverage, final-camera readability, or assembly seams.

## Export, visual fit, and publication

1. Open and edit the recovered source; do not replace helpers to make an art change fit.
2. Export each requested variant to a private temporary GLB.
3. Fresh-import the actual temporary GLB in Blender and evaluate full transforms. Reject helper/light/camera/rig leakage, unsupported transforms, empty geometry, and invalid triangles.
4. Delegate runtime/Godot Y-up triangles to the pure visual contract. The gate checks real triangles and interface coverage, not only accessor extrema or an AABB.
5. Validate every variant before replacing staged output. Cancellation, empty output, or any failed variant preserves previous staging.
6. Run the Godot import smoke and record unexpected diagnostics.
7. Keep promotion closed while source authority is unresolved; geometric PASS is not promotion approval.

The implemented visual-fit CLI is:

```bash
blender --background --factory-startup --python-exit-code 1 \
  --python tools/validate_structural_visual_fit.py -- \
  --project-root ROOT --module ID --glb PATH --report PATH
```

The checked-in exporter calls fresh visual validation for each temporary variant before `os.replace`. The checked-in promoter checks source-authority HOLD before backup/copy, including direct/force/skip-Godot paths, and the unresolved authority status still blocks runtime promotion.

## Full assembly review boundary

The core preflight is per-module. It does not automatically implement or approve:

- all four quarter-turn rotations;
- straight floor/wall joins, door corners, inner/outer corners, or T-junctions;
- a mixed-length 2×2 floor patch without height accumulation;
- a closed room-to-corridor loopback returning to its socket;
- a mixed-length vertical stack and deliberate gap/overlap negatives;
- clay and material renders from the actual production camera at gameplay size;
- intact/damaged/breached interface parity;
- separate visual-floor, collision, navigation, and doorway-clearance evidence.

Record those as full-assembly review gates. Do not turn a pure geometry PASS into a release claim.

## Research basis and status

This policy adapts the local research ledger, not an acceptance result:

`artifacts/room_kit_v2/research/2026-09-08_154121-modular-fit/research-brief.txt`

The ledger URLs are:

- https://book.leveldesignbook.com/process/blockout/metrics/modular
- https://docs.godotengine.org/en/stable/classes/class_gridmap.html
- https://docs.godotengine.org/en/stable/classes/class_camera3d.html
- https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
- https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/fbx-static-mesh-pipeline-in-unreal-engine
- http://blog.joelburgess.com/2013/04/skyrims-modular-level-design-gdc-2013.html
- https://wiki.frozenbyte.com/index.php/3D_Asset_Workflow:_Tile_Textures_and_Trimsheets
- https://www.exp-points.com/vuk-single-material-modular-kit-environment-ue4

A/B source authority remains HOLD, the ramp remains HOLD, and no asset was authored or approved by this update. The dimensions data and pure validator remain subject to the source-authority status and full-assembly review gates before the policy can be treated as release approval.
