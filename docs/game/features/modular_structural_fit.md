# Shared Modular Structural Fit v1

Status: canonical art-authoring and validation runbook. The dimensions policy is approved as an art policy, but its source-authority metadata remains `approved_dimensions_pending_source_authority` / `operator_approval_required`. This update authored no assets and approved no assets for promotion.

This document is the canonical runbook for the shared modular-fit policy. It supersedes conflicting visual guidance in the older room-kit plan and its mirrored feature text. It does not supersede runtime placement, wrapper, collision, navigation, socket, or provenance authority.

## 1. Authority and scope

Use the authorities in this order for the question each one owns:

| Question | Authority | What it does not prove |
|---|---|---|
| Shared visual dimensions and fit policy | `data/art/structural_visual_dimensions.v1.json` | Source provenance, runtime collision, or whole-kit assembly acceptance |
| Module IDs, placement, sockets, wrapper physics, and navigation intent | `data/kits/ship_structural_v0.json`, `data/placement/contracts/structural/ship_structural_v0/*.json`, matching `.tres` and `scenes/wrappers/structural/ship_structural_v0/*.tscn` | That legacy visual meshes fit the new visual shell |
| Source/helper structure | `tools/structural_source_contract.py`, `tools/validate_structural_sources.py`, Blender source helpers and `.source.json` records | Visual readability, transformed imported geometry, or assembly seams |
| Visual geometry fit | `tools/structural_visual_contract.py` and the Blender adapter `tools/validate_structural_visual_fit.py` | Whole-kit procedural assembly, renderer presentation, collision/nav correctness, or human art approval |
| Runtime behavior | Godot compiler, placement, wrapper, collision, and navigation consumers | That a GLB passed a pure geometry check |

The root-code authority for runtime behavior includes `scripts/procgen/walkability_contract.gd`, the structural compiler/placement consumers, the per-module placement contracts, and the matching Godot wrappers. The visual policy never silently replaces those owners.

The visual policy is art-only. Do not migrate source attestation, change wrappers, enlarge collision, rewrite navigation, change socket coordinates, or alter placement JSON as part of this runbook. Preserve the existing placement `.json`/`.tres` wrappers, collision/nav ownership, and socket helpers.

A legacy local bounds record with zero thickness is not visual geometry-dimensions authority. It remains evidence for the source/helper and runtime-contract lanes until the source-authority decision is resolved. Do not claim that old baselines all pass; the known source/variant baseline remains a HOLD.

## 2. Grounding and design rationale

The policy adapts the local research brief rather than presenting research as an asset acceptance result:

- Local ledger: `artifacts/room_kit_v2/research/2026-09-08_154121-modular-fit/research-brief.txt`.
- [1] [Level Design Book — modular metrics](https://book.leveldesignbook.com/process/blockout/metrics/modular)
- [2] [Godot GridMap](https://docs.godotengine.org/en/stable/classes/class_gridmap.html)
- [3] [Godot Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)
- [4] [Godot StandardMaterial3D and normal mapping](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html)
- [5] [Godot decals and renderer support](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html)
- [6] [Epic Games FBX Static Mesh Pipeline](https://dev.epicgames.com/documentation/en-us/unreal-engine/fbx-static-mesh-pipeline-in-unreal-engine)
- [7] [Bethesda/Joel Burgess — Skyrim modular level design](http://blog.joelburgess.com/2013/04/skyrims-modular-level-design-gdc-2013.html)
- [8] [Frozenbyte — tile textures and trimsheets](https://wiki.frozenbyte.com/index.php/3D_Asset_Workflow:_Tile_Textures_and_Trimsheets)
- [9] [Vuk Banovic — modular-kit workflow](https://www.exp-points.com/vuk-single-material-modular-kit-environment-ue4)

The transferable result is simple: predetermine thickness, reserve joining space, keep the walking datum shared, and test rotations, corners, loops, stacks, and final-camera readability in the target renderer. Orthographic projection does not repair a real floor step or an incorrect pivot.

## 3. Shared fit policy

All values below are metres in runtime/Godot Y-up coordinates unless stated otherwise.

### Lattice and floor

- Use a 4 m lattice. A floor module's walking datum is `Y=0`.
- Floor underside is `Y=-0.25`; floor slab thickness is `0.25`.
- Positive relief above the walking datum is prohibited for the shared walkable shell.
- Recesses are at most `0.02` m and only outside protected walking/clearance guards. A recessed service detail must not remove the mating edge or create a step in the player path.
- The doorway has no raised threshold. The threshold limit is `Y=0`; the opening must remain traversable without a decorative speed bump.

### Wall and structural edge

- Shared wall/top height is `3.2` m.
- The complete edge visual envelope is `0.20` m deep, normal `[-0.10,+0.10]`. There is no additional outward decoration allowance: recess detail or use materials inside that same envelope.
- `terminal_mating_band_m` = `0.20` m along the edge tangent at each terminal. Preserve its full `3.2` m height and `0.20` m depth, including planar end faces and continuous band surfaces. No bevel, trim, greeble or damage may consume it.
- Detail must recess away from mating faces. Keep joining faces flat and deliberately owned; do not round away a shared edge to conceal a seam.
- The visual shell may be widened or scaled in the authoring source to preserve this policy and the existing helper/placement contract. Do not silently edit the helper or runtime contract to fit decoration.

### Doorway and pillar

- `doorway_frame_open_1x1` clear prism: X `[-0.6,+0.6]`, Y `[0,2.2]`, Z `[-0.1,+0.1]`.
- Actual triangles, not only vertex extrema, must stay out of the clear prism. This catches a triangle that crosses the opening while all vertices appear outside it.
- The pillar `footprint_cells` is `[1,1]` on the `4.0` m lattice, with centered X/Z contacts and Y contacts at `0` and `3.2`. The policy reserves that cell footprint; it does not prescribe a separate cosmetic body width or a filled-cell cube.

### Detail and material allocation

- Use flat/color textures, normals, and trim sheets for paint wear, labels, hazard stripes, small grooves, fasteners, and shallow seams.
- Use actual geometry only for readable large features, silhouette changes, deep recesses, structural braces, service pipes, and broken forms. Do not turn microdetail into repeated runtime meshes.
- Use the existing salvage-industrial language: cool salvaged steel, dark service cavities, and safety amber where it communicates a practical maintenance cue. Cyan/red emission is reserved for an actual powered/fault state; derelict static dressing is not permanently emissive.
- Textures, normals, and trim sheets are not permission to fake a silhouette-changing feature. Conversely, geometry is not permission to occupy a protected interface.

### Godot Compatibility renderer

Godot Compatibility does not provide the same Decal rendering path as Forward+. Prefer baked material detail. If a flat overlay is unavoidable, use a tightly bound non-colliding `Sprite3D` or overlay mesh with deliberate depth sorting and ownership. Do not apply a blanket offset to every overlay; document the specific depth decision and verify the final camera.

## 4. Coordinate and contract rules

The legacy helper mapping is preserved exactly:

```text
placement/helper contract [x, y, z] -> Blender [x, z, y]
```

This mapping is for contract-derived helpers, sockets, bounds, and source inspection. It is not a license to remap the runtime geometry twice. Physical Blender geometry is authored Z-up and exports through the native glTF axis convention `[x, z, -y]`. Keep the helper mapping and physical geometry conversion distinct and tested.

Keep floor-center or edge-center origins, identity placement transforms, required helper names, socket empties, `.tres` companions, wrapper visibility/state switching, collision proxies, and nav ownership unchanged. Decorative GLB geometry never becomes a second physics authority.

## 5. Implemented gate coverage

The current code and tests support the following claims only when the corresponding files are present and the fresh command passes:

### Pure policy/geometry checks

`tools/structural_visual_contract.py` currently provides:

- strict loading of `data/art/structural_visual_dimensions.v1.json`;
- rejection of missing, malformed, non-finite, boolean, unknown-field, and per-asset-override policy data;
- actual-triangle validation rather than local accessor bounds alone;
- empty, degenerate, and non-finite geometry rejection;
- floor datum/underside, recess, projected coverage, and full mating-boundary checks;
- wall/door terminal profile coverage;
- actual triangle intersection testing for the doorway clear prism;
- pillar contact and envelope checks;
- explicit `hold` results for unsupported profiles.

These are per-module visual/interface checks. They are not whole-kit acceptance.

### Seven core profiles for this policy

The implementation brief and canonical policy declare these seven profiles as automatically supported for this update:

- `floor_1x1`
- `floor_2x1`
- `corridor_floor_1x1`
- `corridor_floor_1x2`
- `wall_straight_1x1`
- `doorway_frame_open_1x1`
- `pillar_support_1x1`

Every other module ID, including corners, junctions, portals, ceilings, blocked doors, and ramps, needs a reviewed profile before it can be called automatically supported. Unsupported or not-yet-reviewed IDs must fail closed as `hold`; they are not “bad geometry” failures. `ramp_up_1x2` remains HOLD because its endpoint transform is not authorized.

### Not implemented by this core preflight

The following are required full-assembly review gates, not claims of automatic coverage:

1. all four quarter-turn rotations;
2. straight floor/wall joins, door corners, inner/outer corners, and T-junctions;
3. a mixed-length 2×2 floor patch with no accumulated height;
4. a closed room-to-corridor loopback returning to its socket;
5. a mixed-length vertical stack and intentional gap/overlap negatives;
6. clay and material renders from the actual production camera at gameplay size;
7. intact/damaged/breached interface parity;
8. separate visual floor, collision support, nav, and doorway-clearance checks.

The minimum evidence packet is the actual assembled geometry, transformed imported vertices, all required rotations, deliberate wrong-height/wrong-pivot/raised-threshold/bevel/gap negatives, and final-camera clay/material evidence. A pure validator pass is not a visual-review approval.

### Checked-in implementation status

At the time of this update, `tools/validate_structural_visual_fit.py` exists and exposes a fresh-Blender adapter. The legacy focused-nine diagnostic recipe behavior is preserved; it does not claim automatic migration or policy preflight. New authoring must load the shared policy, and legacy outputs must revalidate through the guarded export path before publication. The core tests exercise policy and adapter seams, but their presence is not whole-kit acceptance.

The checked-in exporter calls fresh validation for every temporary variant before `os.replace`, and the promoter checks source-authority HOLD before backup/copy; those are implemented code paths, not evidence that any asset passes. A source-authority HOLD still closes runtime promotion. The parent real-Blender fixture log records 13/13 expected cases; that evidence is still separate from whole-kit assembly review and promotion approval.

## 6. Pipeline commands and publication boundary

The actual per-module Blender adapter invocation is:

```bash
blender --background --factory-startup --python-exit-code 1 \
  --python tools/validate_structural_visual_fit.py -- \
  --project-root ROOT --module ID --glb PATH --report PATH
```

The adapter imports the actual GLB in a fresh Blender process, evaluates full transforms, rejects helper/light/camera/rig leakage and invalid root transforms, converts native glTF coordinates correctly, and delegates mesh triangles to the pure contract. It validates the actual temporary GLB, not a pre-export source approximation.

This is the implemented CLI shape; `--help` confirms the required `--project-root`, `--module`, `--glb`, and optional `--report` arguments.

The exporter must validate every actual temporary variant GLB before replacing staged output. Any cancelled export, empty output, invalid GLB, or failed visual fit preserves the previous staging contents. The promoter must enforce the current source-authority HOLD before backup, copy, or runtime writes, including direct `promote_module`, `--force`, and `--skip-godot` paths. Staging fixtures may be prepared for validation; runtime release remains closed until source authority, Godot import, wrapper/variant, and review gates clear.

## 7. Artist acceptance checklist

Before requesting review, record:

- source path, module ID, policy hash, helper/source record, and intended state;
- actual transformed bounds and the shared datum/interface measurements;
- protected joining strips and doorway prism checks;
- four rotation checks or an explicit profile HOLD;
- clay and material camera evidence, plus negative cases;
- wrapper/collision/nav/socket preservation evidence;
- whether the result is source-validated, visual-fit-passed, assembly-reviewed, or merely staged.

No asset is authored, approved, promoted, or released by this documentation update. Keep A/B source authority and ramp decisions HOLD, and keep geometric PASS separate from promotion approval.
