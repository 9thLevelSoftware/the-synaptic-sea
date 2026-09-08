# Blender artist workflow for structural sources

This workflow covers editable structural `.blend` sources for the Synaptic Sea salvage-industrial kit. The canonical visual policy is [`modular_structural_fit.md`](modular_structural_fit.md). JSON placement contracts remain authoritative for module IDs, bounds, sockets, footprint, collision intent, navigation intent, and placement origin. A `.blend` is the editable visual source; runtime GLBs are produced only through staged export and validation.

## Authority boundary

Use each authority only for the question it owns:

- `data/art/structural_visual_dimensions.v1.json` and the canonical runbook own the shared visual shell and fit policy.
- `data/kits/ship_structural_v0.json`, `data/placement/contracts/structural/ship_structural_v0/*.json`, matching `.tres` files, and Godot wrappers own placement, sockets, collision, and navigation intent.
- `tools/structural_source_contract.py` and `tools/validate_structural_sources.py` validate source/helper structure. They do **not** prove visual fit, readability, transformed imported geometry, or assembly seams.
- `tools/structural_visual_contract.py` plus `tools/validate_structural_visual_fit.py` validate visual/interface geometry. They do **not** prove whole-kit assembly, renderer quality, collision/nav correctness, or human art approval.
- `scripts/procgen/walkability_contract.gd` and its compiler/placement consumers are root-code authority for runtime behavior.

The visual policy is art-only. Do not migrate source attestation, edit placement JSON, enlarge collision, rewrite navigation, change socket coordinates, or replace wrapper helpers while modeling. A legacy local bounds record with zero thickness is not visual geometry-dimensions authority. Widen or scale the visual shell to preserve the existing helper/placement contract; do not shrink or rewrite the contract to fit decoration.

## Opening and preserving a source

Structural sources live outside the checkout:

```text
/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.blend
/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.source.json
```

1. Open Blender 4.x and open the existing module `.blend`; do not start a replacement scene.
2. Keep the matching `.source.json` beside the source and update metadata only through approved source-authoring tools.
3. Never edit `assets/imported/structural/` directly.
4. Preserve `ModuleRoot_<module_id>`, `Geometry`, `AuthoringHelpers`, `Origin`, `Anchor_FloorCenter`, every `Anchor_SOCK_<socket_id>`, and the source-only `CollisionProxy`.
5. Keep helper transforms and socket positions unchanged while editing visual collections.

Required source collections and helpers:

- `Geometry`: visual meshes only.
- `AuthoringHelpers`: source-only helpers.
- `Origin` and `Anchor_FloorCenter`: unchanged placement anchors.
- `Anchor_SOCK_<socket_id>`: one empty per contract socket.
- `CollisionProxy`: non-rendering wireframe helper derived from the contract, never from decorative geometry.

## Shared fit policy

All values are metres in runtime/Godot Y-up coordinates:

- Use a 4 m lattice. The finished walking datum is `Y=0`; floor underside is `Y=-0.25`.
- Positive relief above the shared walkable shell is `0`. Recesses are at most `0.02` m and only outside protected walking/clearance guards.
- Shared wall/top height is `3.2` m.
- The complete edge visual envelope is `0.20` m deep, normal `[-0.10,+0.10]`. There is no additional outward decoration allowance: recess detail or use materials inside that same envelope.
- `terminal_mating_band_m` = `0.20` m along the edge tangent at each terminal. Preserve its full `3.2` m height and `0.20` m depth, including planar end faces and continuous band surfaces. No bevel, trim, greeble or damage may consume it.
- `doorway_frame_open_1x1` has a `1.2 × 2.2` m clear opening: X `[-0.6,+0.6]`, Y `[0,2.2]`, Z `[-0.1,+0.1]`. It has no raised threshold.
- The pillar `footprint_cells` is `[1,1]` on the `4.0` m lattice, with centered X/Z contacts and Y contacts at `0` and `3.2`. The policy reserves that cell footprint; it does not prescribe a separate cosmetic body width or a filled-cell cube.
- These seven profiles are auto-supported: `floor_1x1`, `floor_2x1`, `corridor_floor_1x1`, `corridor_floor_1x2`, `wall_straight_1x1`, `doorway_frame_open_1x1`, and `pillar_support_1x1`. Every other ID requires a reviewed profile and fails closed as `hold`; `ramp_up_1x2` remains HOLD.

Use textures, normals, and trim sheets for paint wear, labels, hazard stripes, small grooves, fasteners, and shallow seams. Use actual geometry for readable large features, silhouette changes, deep recesses, braces, service pipes, and broken forms. Use cool salvaged steel, dark service cavities, and safety amber for practical maintenance cues. Static derelict dressing is not permanently emissive.

Godot Compatibility does not provide the Forward+ Decal path. Prefer baked material detail. If an overlay is unavoidable, use a tightly bound non-colliding `Sprite3D` or overlay mesh with deliberate depth sorting and a documented depth decision. Do not apply a blanket offset to every overlay.

## Coordinates and export axes

Preserve the legacy helper mapping exactly:

```text
contract/helper [x, y, z] -> Blender [x, z, y]
```

This mapping applies to contract-derived helpers, sockets, bounds, and source inspection. Physical Blender geometry is Z-up and uses native glTF/runtime conversion `[x, z, -y]`; do not remap imported geometry through the helper mapping or convert it twice.

For export collections, put runtime visual geometry in `Export_*` collections and set `variant_role` to `intact`, `damaged`, or `breached`. If no tagged collection exists, the exporter uses `Geometry` as the intact fallback. Helpers, cameras, lights, rigs, and authoring meshes must not enter a runtime GLB.

## Validation and publication

The source/helper validator and visual-fit gate are different checks:

1. Run source inspection/validation to prove required helpers, sockets, origin, collision proxy, source record, and variant inventory.
2. Export each requested variant to a private temporary GLB.
3. Fresh-import each actual temporary GLB in Blender, evaluate transformed triangles, reject helper/light/camera/rig leakage and unbaked transforms, then run the pure visual contract.
4. Preserve previous staging if any variant fails, is empty, or is cancelled.
5. Run the Godot import smoke and record diagnostics.
6. Keep runtime promotion closed while source authority is unresolved, even when visual geometry returns PASS.

The implemented CLI is:

```bash
blender --background --factory-startup --python-exit-code 1 \
  --python tools/validate_structural_visual_fit.py -- \
  --project-root ROOT --module ID --glb PATH --report PATH
```

The exporter does fresh validation for each temporary variant before replacing staged output. The promoter checks source-authority HOLD before backup/copy, including force and skip-Godot paths; this gate does not approve an asset.

Full assembly review is still required: four rotations; floor/wall joins, door corners, inner/outer corners, and T-junctions; a mixed-length 2×2 floor patch; closed loopback; mixed-length stack with gap/overlap negatives; and clay/material evidence from the actual production camera. These are not automatic coverage of the core preflight.

## Research basis and review record

The policy adapts, rather than overclaims, the local research brief:

`artifacts/room_kit_v2/research/2026-09-08_154121-modular-fit/research-brief.txt`

That ledger cites:

- https://book.leveldesignbook.com/process/blockout/metrics/modular
- https://docs.godotengine.org/en/stable/classes/class_gridmap.html
- https://docs.godotengine.org/en/stable/classes/class_camera3d.html
- https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html
- https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html
- https://dev.epicgames.com/documentation/en-us/unreal-engine/fbx-static-mesh-pipeline-in-unreal-engine
- http://blog.joelburgess.com/2013/04/skyrims-modular-level-design-gdc-2013.html
- https://wiki.frozenbyte.com/index.php/3D_Asset_Workflow:_Tile_Textures_and_Trimsheets
- https://www.exp-points.com/vuk-single-material-modular-kit-environment-ue4

Record module ID, source path, policy hash, transformed measurements, protected-strip/doorway checks, variant, validator reports, camera evidence, and whether the result is source-validated, visual-fit-passed, assembly-reviewed, or merely staged. This documentation update authored no assets, approved no assets, and does not claim old baselines all pass.
