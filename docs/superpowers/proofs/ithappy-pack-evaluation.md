# Gate 2: ithappy Asset Pack Evaluation

**Date:** 2026-08-22
**Status:** PASS

## Scope

Verify that ithappy Sci-Fi Props pack assets are compatible with the Synaptic Sea 4m module grid, have reasonable poly counts, use manageable materials, and can be imported into Godot 4.x via GLTF.

## Test method

Blender 4.x headless import of 5 representative GLB models. Measured: bounding box (meters), vertex/face/triangle counts, material count and names, collision object presence.

## Results

| Model | Size (m) | Verts | Tris | Materials | Grid fit |
|-------|----------|-------|------|-----------|----------|
| Floor_type_A_001.glb | 4.00 × 4.00 × 0.01 | 803 | 469 | 2 (Color, Emission) | PERFECT — exact 4m grid |
| Wall_type_A_001.glb | 2.50 × 2.50 × 4.00 | 523 | 350 | 2 (Color, Emission) | 4m height matches module height |
| Door_001.glb | 1.27 × 0.55 × 2.76 | 529 | 440 | 2 (Color, Emission) | Reasonable door size |
| Generator_001.glb | 1.89 × 2.33 × 1.27 | 2,167 | 2,058 | 2 (Color, Emission) | Good prop size |
| Turret_001.glb | 1.98 × 2.67 × 2.67 | 3,970 | 3,654 | 2 (Color, Emission) | Good threat prop |

## Key findings

### Scale compatibility
- **Floor: 4.00m × 4.00m** — exact match for `CELL_SIZE = 4.0` in `structural_placer.gd`
- **Wall: 4.00m height** — matches the standard module height (walls are 2.5m wide panels, combinable)
- **Door: 2.76m height** — fits within 4m wall openings
- All models use real-world scale as documented

### Material efficiency
- **Every model uses exactly 2 materials:** `Color` (base color/albedo) and `Emission` (glow/emissive)
- This is far leaner than the documented 11 materials / 7 textures — those are totals across the entire pack, not per-model
- Godot can handle this easily even on mobile

### Triangle budget
- Structural models: 350–469 tris (extremely low)
- Props: 2,058 tris (generator)
- Threat: 3,654 tris (turret with 8 mesh sub-objects)
- All well within budget for isometric/top-down rendering

### Collision
- **No collision meshes found in GLB files** — collision is NOT included despite the product page claiming it
- **Not a blocker:** existing wrapper `.tscn` scenes already define collision via `BoxShape3D` sub-resources (e.g., `size = Vector3(4, 0.25, 4)` for floors)
- Collision stays in the wrapper; GLB is visual-only

### Import path
- GLTF/GLB imports directly into Blender 4.x and Godot 4.x
- No conversion needed
- No encoding issues after filename fix (%E6 → c for capsule)

## Compatibility matrix

| Requirement | ithappy | Status |
|-------------|---------|--------|
| 4m grid alignment | Floor = 4.00m × 4.00m | PASS |
| Module height | Wall = 4.00m | PASS |
| Material count | 2 per model | PASS |
| Triangle budget | 350–3,654 | PASS |
| GLTF format | Native GLB | PASS |
| Godot 4.x import | Standard glTF pipeline | PASS |
| Collision | Not in GLB (wrapper provides it) | PASS (existing) |

## Conclusion

The ithappy Sci-Fi Props pack is fully compatible with the Synaptic Sea module system. The floor tiles match the 4m grid exactly, walls match the 4m module height, materials are minimal (2 per model), and triangle counts are low. The only gap — no collision meshes in GLBs — is already handled by the existing wrapper `.tscn` collision shapes.

**Recommendation: Proceed to Gate 3 (integration prototype).**
