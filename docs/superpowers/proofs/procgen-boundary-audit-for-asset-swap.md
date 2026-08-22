# Gate 1: Procgen Boundary Audit for Asset Swap

**Date:** 2026-08-22
**Status:** PASS

## Scope

Verify that the procgen pipeline's boundary compiler, plan, and validator never reference mesh/GLB data, and that the loader resolves modules by `module_id` string lookup only — confirming that swapping GLB files inside wrapper `.tscn` scenes is invisible to the compiler.

## Findings

### 1. StructuralEdgeCompiler — NO mesh references

`scripts/procgen/structural_edge_compiler.gd`:
- Only `preload` reference: `structural_edge_plan.gd` (data structure)
- Zero matches for: mesh, GLB, glb, .tscn, ResourceLoader, load()
- **Verdict: Pure data compiler. Never touches visual assets.**

### 2. StructuralEdgePlan — NO mesh references

`scripts/procgen/structural_edge_plan.gd`:
- Zero matches for: mesh, GLB, glb, .tscn, ResourceLoader, load()
- **Verdict: Pure data structure.**

### 3. StructuralPlanValidator — NO mesh references

`scripts/procgen/structural_plan_validator.gd`:
- Only `preload` reference: `structural_edge_plan.gd`
- One comment mentioning "visual mesh" (line 722) — documentation only, no code
- **Verdict: Validates plan data against layout data. Never loads meshes.**

### 4. GeneratedShipLoader — module_id lookup only

`scripts/procgen/generated_ship_loader.gd`:
- Line 267-271: Reads `module_id` and `godot_wrapper_scene` from kit JSON
- Line 551-554: Validates `module_id` is non-empty String
- Line 565-566: `module_to_scene.has(module_id)` — looks up wrapper by module_id
- Line 573-574: `ResourceLoader.exists(scene_path)` + `load(scene_path)` — loads wrapper .tscn
- Line 579: Validates loaded resource is `PackedScene`
- **Verdict: Resolves modules by module_id string → wrapper .tscn path. The GLB is referenced INSIDE the .tscn, not by the loader.**

### 5. Kit catalog — 15 module_id → wrapper mappings

`data/kits/ship_structural_v0.json`:
```
floor_1x1              -> scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn
floor_2x1              -> scenes/wrappers/structural/ship_structural_v0/floor_2x1.tscn
corridor_floor_1x1     -> scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1.tscn
corridor_floor_1x2     -> scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x2.tscn
wall_straight_1x1      -> scenes/wrappers/structural/ship_structural_v0/wall_straight_1x1.tscn
wall_end_cap           -> scenes/wrappers/structural/ship_structural_v0/wall_end_cap.tscn
wall_inner_corner      -> scenes/wrappers/structural/ship_structural_v0/wall_inner_corner.tscn
wall_outer_corner      -> scenes/wrappers/structural/ship_structural_v0/wall_outer_corner.tscn
wall_t_junction        -> scenes/wrappers/structural/ship_structural_v0/wall_t_junction.tscn
doorway_frame_open_1x1 -> scenes/wrappers/structural/ship_structural_v0/doorway_frame_open_1x1.tscn
bulkhead_portal_2x1    -> scenes/wrappers/structural/ship_structural_v0/bulkhead_portal_2x1.tscn
doorway_frame_blocked_1x1 -> scenes/wrappers/structural/ship_structural_v0/doorway_frame_blocked_1x1.tscn
ramp_up_1x2            -> scenes/wrappers/structural/ship_structural_v0/ramp_up_1x2.tscn
pillar_support_1x1     -> scenes/wrappers/structural/ship_structural_v0/pillar_support_1x1.tscn
ceiling_cap_1x1        -> scenes/wrappers/structural/ship_structural_v0/ceiling_cap_1x1.tscn
```

### 6. Wrapper scene structure (example: floor_1x1.tscn)

```
ext_resource path="res://assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb"     (intact)
ext_resource path="res://assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1_damaged.glb"  (damaged)
ext_resource path="res://assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1_breached.glb" (breached)
+ BoxShape3D collision (4×0.25×4m)
+ Socket anchors (Marker3D) for module connections
+ StaticBody3D collision layer
+ Visual node with 3 variants (intact/damaged/breached, one visible at a time)
```

**To swap visuals: change only the 3 ext_resource GLB paths. Keep collision, sockets, anchors unchanged.**

### 7. Camera rig parameters

`scripts/camera/iso_camera_rig.gd`:
```
DEFAULT_OFFSET = Vector3(16.0, 18.0, 16.0)
DEFAULT_SIZE = 22.0
Projection: Camera3D.PROJECTION_ORTHOGONAL
Follow: tracks target position + offset
```

## Regression evidence

### Python tests
```
58 passed in 7.75s
```

### Godot multi-seed compiler smoke
```
PROCGEN_STRUCTURAL_COMPILER_PASS seeds=5 placements=248 portals=46
```

No ERROR, WARNING, or SCRIPT ERROR diagnostics.

## Conclusion

The procgen pipeline has a clean architectural boundary:
- **Compiler layer** (StructuralEdgeCompiler, StructuralEdgePlan, StructuralPlanValidator): Pure data. Never references meshes, GLBs, or wrapper scenes.
- **Loader layer** (GeneratedShipLoader): Resolves `module_id` → wrapper `.tscn` path via kit catalog. Loads the `.tscn`; the GLB is referenced inside it.
- **Wrapper layer** (`.tscn` scenes): References GLB files as `ext_resource`. This is the ONLY place where visual meshes are referenced.

**Swapping GLB files inside wrapper scenes is invisible to the compiler. All 627 regression commands should pass unchanged.**
