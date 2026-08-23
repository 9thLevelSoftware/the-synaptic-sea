# Isometric Asset Pack Feasibility & Procgen Review

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

## 0. TL;DR

The ithappy Studios Sci-Fi Props pack (1080+ low-poly modular 3D assets, $35.70 on sale) explicitly supports isometric games and ships in GLTF/FBX/OBJ — directly importable into Godot 4.x. The existing procgen system (15 structural modules, StructuralEdgeCompiler, 627-command regression) is projection-agnostic: it compiles room graphs into placement plans, not visual meshes. This plan audits the procgen boundary, maps ithappy categories to the existing module/role system, and produces a feasibility verdict with a concrete integration path — before any asset purchase or import work begins.

**Goal:** Determine whether the ithappy Sci-Fi Props pack can replace or augment the current placeholder structural modules for an isometric (or top-down) presentation, without breaking the mature procgen pipeline.

**Architecture:** The procgen system has a clean separation: `ShipLayoutGenerator` produces a layout dictionary → `StructuralEdgeCompiler` compiles boundary plans → `GeneratedShipLoader` instantiates wrapper scenes from a kit catalog. The visual meshes live behind `.tscn` wrapper scenes in `scenes/wrappers/structural/ship_structural_v0/`. Swapping visuals means swapping the GLB referenced inside each wrapper — the procgen compiler never touches mesh data.

**Tech Stack:** Godot 4.7.1, GDScript, Blender 4.x (for GLB conversion), glTF Transform (optimization), Python 3.11 (validation scripts).

---

## 1. Why revisit (decision record)

| Driver | Detail |
|--------|--------|
| Asset quality | User rejected AI-generated 3D assets as "terrible" for final game art. Previous pipeline (Meshy/TripoSR/Hunyuan3D) produces draft-quality meshes unsuitable for shipping. |
| Asset availability | ithappy Sci-Fi Props pack: 1080+ modular assets, low-poly (~493 tris/model), explicitly designed for isometric/top-down games, Godot-compatible formats. |
| Cost | $35.70 (70% off $119) — orders of magnitude cheaper than commissioning equivalent art. |
| Existing pipeline maturity | 18 simulation loops closed, 627-command regression bundle, structural compiler with parity proofs. The simulation is projection-agnostic. |
| Frustration pivot | User previously pivoted to top-down due to asset frustration. Better assets may restore isometric viability. |

**Non-drivers:** The simulation code, procgen compiler, and gameplay systems are NOT being rewritten. This is a visual-layer evaluation only.

---

## 2. Architectural split — what changes, what doesn't

| Layer | Path | Action |
|-------|------|--------|
| **Procgen compiler** | `scripts/procgen/structural_edge_compiler.gd`, `structural_edge_plan.gd`, `structural_plan_validator.gd` | STAYS — untouched. Projection-agnostic. |
| **Layout generator** | `scripts/procgen/ship_layout_generator.gd`, `ship_generator.gd` | STAYS — produces layout dictionaries, not meshes. |
| **Kit catalog** | `data/kits/ship_structural_v0.json`, `scripts/procgen/kit_catalog.gd` | STAYS — role→module mapping is data-driven. New modules can be added without code changes. |
| **Wrapper scenes** | `scenes/wrappers/structural/ship_structural_v0/*.tscn` | POTENTIAL CHANGE — swap GLB references to ithappy meshes. |
| **Structural modules (GLB)** | `assets/imported/structural/*.glb` | POTENTIAL CHANGE — replace with ithappy-sourced GLBs. |
| **Camera rig** | `scripts/camera/iso_camera_rig.gd` | STAYS for isometric; may need parameter tuning for new asset scale. |
| **Prop/decor layer** | Currently placeholder/missing | NEW — ithappy props (turrets, drones, containers, terminals, furniture) fill this gap. |
| **Room dressing** | `scripts/procgen/gameplay_slice_builder.gd` | STAYS — places gameplay objects, not visuals. |

---

## 3. Decisions owned by the architect (do not let workers re-decide)

| Decision | Current value | Notes |
|----------|---------------|-------|
| Tile/grid size | `CELL_SIZE = 4.0` (4m modules) | ithappy walls are 4m standard height. Floor tiles are modular. Compatible. |
| Coordinate system | Y-up, XZ plane for floor plans | Standard Godot. ithappy uses real-world scale. |
| Camera projection | Orthographic isometric (offset 16,18,16, size 22) | May need tuning for ithappy asset density. |
| Z-axis handling | 3D with ortho camera; Y is vertical | No change needed. |
| Authoritative asset pack | ithappy Sci-Fi Props (if approved) | Secondary: existing hand-authored modules. |
| Module naming convention | `{role}_{variant}_{size}.tscn` | Keep existing convention. ithappy assets get imported under `assets/third_party/ithappy/`. |
| Budget cap | $35.70 for the pack (one-time) | No ongoing costs. License: 5 seats per quantity. |

---

## 4. Asset pack analysis

### ithappy Sci-Fi Props — key specs

- **1080+ modular/interactive assets**
- **Polygon count:** 532K triangles total (~493 per model)
- **Materials:** 11, **Textures:** 7 (1024–2048px)
- **Scale:** Real-world-size
- **Collision:** Yes (included)
- **Formats:** FBX, OBJ, GLTF, STL, Unity, Unreal, Godot
- **Godot compatibility:** 3.4+ (native .tscn available on Unity/Fab stores)
- **License:** 5 seats per purchase, one-time

### Category mapping to Synaptic Sea roles

| ithappy category | Count | Synaptic Sea role | Current module | Fit |
|------------------|-------|-------------------|----------------|-----|
| **Floors** (3 color variants) | 120 | `floor_1x1`, `floor_2x1`, `corridor_floor_*` | Hand-authored GLB | EXCELLENT — modular 4m tiles, direct replacement |
| **Walls** (3 color variants, 4m height) | 221 | `wall_straight_1x1`, `wall_end_cap`, `wall_inner_corner`, `wall_outer_corner`, `wall_t_junction` | Hand-authored GLB | EXCELLENT — 4m standard height matches CELL_SIZE |
| **Doors** (rectangular, round, sliding, hinged) | 27 | `doorway_frame_open_1x1`, `doorway_frame_blocked_1x1`, `bulkhead_portal_2x1` | Hand-authored GLB | EXCELLENT — multiple door types for variety |
| **Ceilings** (3 color variants) | 195 | `ceiling_cap_1x1` | Hand-authored GLB | EXCELLENT — modular ceiling system |
| **Stairs & Fencing** (1.5m height) | 54 | `ramp_up_1x2` | Hand-authored GLB | GOOD — 1.5m stairs may need stacking for 4m modules |
| **Platforms** (4×4m) | 12 | N/A (new) | None | GOOD — could replace or augment floor modules |
| **Construction/Supports** | 26 | `pillar_support_1x1` | Hand-authored GLB | GOOD — structural supports |
| **Hatches** (1/2/3 panel) | 30 | N/A (new) | None | GOOD — interactive hatches for gameplay |
| **Generators** | 28 | Room dressing | Placeholder | EXCELLENT — reactor/engineering props |
| **Terminals** (holographic) | 53 | Room dressing | Placeholder | EXCELLENT — bridge/control room props |
| **Crates** (opening lids) | 16 | Room dressing / loot | Placeholder | EXCELLENT — cargo/scavenge props |
| **Drones** (cargo, flying, wheeled) | 103 | Threat/decor | None | EXCELLENT — enemy/ambient drones |
| **Turrets** (7 types) | 88 | Threat/decor | None | EXCELLENT — defense systems |
| **Containers** (6m, 4m) | 16 | Room dressing | Placeholder | GOOD — cargo bay dressing |
| **Capsules** (with contents) | 26 | Room dressing | None | GOOD — medical/science props |
| **Furniture** (desks, chairs, sofas) | 124 | Room dressing | Placeholder | GOOD — crew quarters/bridge dressing |
| **Pipes/Cables/Vents** | 37 | Decor | None | GOOD — corridor/industrial dressing |
| **Security Cameras** | 13 | Decor | None | GOOD — surveillance props |
| **Barrels/Gas Cans** | 32 | Decor/loot | None | GOOD — industrial props |
| **Farm Elements** | 15 | Room dressing | None | GOOD — life support/hydroponics |
| **Vending Machines** | 7 | Decor | None | OK — crew quarters flavor |
| **Barriers** | 14 | Decor | None | GOOD — defensive positions |

### Coverage assessment

- **Structural modules (floors, walls, doors, ceilings, stairs):** ~637 assets — DIRECT REPLACEMENT for all 15 existing wrapper modules
- **Room dressing (generators, terminals, crates, furniture, containers):** ~300+ assets — FILLS the placeholder gap
- **Threat/decor (drones, turrets, cameras):** ~200+ assets — NEW category, enables visual variety
- **Total coverage:** ~95% of the visual layer needs

### Format conversion path

ithappy provides GLTF natively. Godot 4.x imports GLTF/GLB directly. Conversion pipeline:
1. Download pack (GLTF format)
2. Run `gltf-transform optimize` to compress textures/merge meshes
3. Import into Godot project under `assets/third_party/ithappy/`
4. Create wrapper `.tscn` scenes that reference the optimized GLBs
5. Update `data/kits/ship_structural_v0.json` to map roles to new wrappers

---

## 5. Procgen compatibility analysis

### What the procgen system actually does (and doesn't do)

The procgen pipeline is a **boundary compiler**, not a visual renderer:

```
ShipLayoutGenerator → layout.json (rooms, connections, footprints)
    ↓
StructuralEdgeCompiler → structural_plan (placement_id, edge_key, kind, state, module_id, position, yaw)
    ↓
StructuralPlanValidator → validates plan against layout
    ↓
GeneratedShipLoader → instantiates wrapper .tscn scenes from kit catalog
```

**Critical insight:** The compiler never touches mesh data. It produces placement records with `module_id` strings. The loader looks up `module_id` in the kit catalog, finds the wrapper `.tscn`, and instantiates it. Swapping the GLB inside a wrapper is invisible to the compiler.

### Compatibility matrix

| Procgen component | ithappy impact | Change needed |
|-------------------|----------------|---------------|
| `ShipLayoutGenerator` | None | No change |
| `StructuralEdgeCompiler` | None | No change |
| `StructuralPlanValidator` | None | No change |
| `GeneratedShipLoader` | None (loads wrappers by module_id) | No change |
| `KitCatalog` | New module_ids possible | Data-only change in `ship_structural_v0.json` |
| Wrapper `.tscn` scenes | GLB reference swap | Per-module edit |
| `IsoCameraRig` | May need size/offset tuning | Parameter change |
| `GameplaySliceBuilder` | None (places gameplay objects) | No change |
| Smoke tests | Should still pass if wrapper names unchanged | Verify |

### Risk: module_id stability

The 627-command regression bundle references module_ids by name. If we keep the same module_id strings (e.g., `floor_1x1`) and only swap the GLB inside the wrapper, all tests pass unchanged. If we add new module_ids (e.g., `floor_1x1_variant_b`), the kit catalog handles routing without code changes.

---

## 6. Gate plan

### Gate 1: Procgen boundary audit (1 day)

**Owner:** Architect (this plan)
**Dependencies:** None
**Deliverables:**
- Verified list of all 15 structural module_ids and their wrapper paths
- Confirmed that `StructuralEdgeCompiler` never references mesh data
- Confirmed that `GeneratedShipLoader` loads wrappers by module_id string only
- Camera rig parameters documented (offset, size, projection)

**Exit criteria:**
- `godot --headless --path . --script res://scripts/validation/procgen_structural_compiler_smoke.gd -- 17 23 41 73 101` passes
- `PYTHONPATH=. python3.11 -m pytest -q tests/test_procgen_structural_compiler.py` passes
- Document: `docs/superpowers/proofs/procgen-boundary-audit-for-asset-swap.md`

**Regression invariant:** All 627 regression commands pass unchanged.

### Gate 2: Asset pack evaluation (1 day)

**Owner:** Architect
**Dependencies:** Gate 1 complete
**Deliverables:**
- Downloaded ithappy pack (GLTF format)
- Blender import test: open 5 representative models (floor, wall, door, generator, turret)
- Scale verification: confirm real-world scale matches 4m module grid
- Material count: verify ≤11 materials, ≤7 textures per the spec
- Collision mesh verification: confirm collision shapes are included and reasonable
- Poly count spot-check: verify ~493 tris/model average

**Exit criteria:**
- 5 representative models import into Blender without errors
- Scale matches 4m grid (within 10% tolerance)
- Collision meshes present and usable
- Document: `docs/superpowers/proofs/ithappy-pack-evaluation.md`

**Regression invariant:** No project files modified yet.

### Gate 3: Integration prototype — dual camera (2-3 days)

**Owner:** Implementation worker
**Dependencies:** Gate 2 approved
**Deliverables:**
- GLTF import pipeline script (`tools/ithappy_import_pipeline.py`) — direct import, no pre-optimization
- 3 wrapper scene conversions: `floor_1x1`, `wall_straight_1x1`, `doorway_frame_open_1x1`
- Updated kit catalog entries for the 3 converted modules
- **Dual camera prototype:** screenshot comparison in BOTH isometric and top-down
  - Isometric: existing `IsoCameraRig` parameters
  - Top-down: new `TopDownCameraRig` variant (ortho, straight-down angle)
- Screenshot comparison: before (placeholder) vs after (ithappy) in both angles

**Exit criteria:**
- `godot --headless --path . --script res://scripts/validation/procgen_structural_compiler_smoke.gd -- 17` passes with ithappy wrappers
- Visual inspection: 3 converted modules render correctly in BOTH camera angles
- Screenshot artifacts saved for operator review and final camera decision
- No new Godot errors or warnings
- Document: `docs/superpowers/proofs/ithappy-integration-prototype.md`

**Regression invariant:** 627-command regression bundle passes.

### Gate 4: Full asset import (3-5 days)

**Owner:** Implementation worker
**Dependencies:** Gate 3 approved + operator camera decision
**Deliverables:**
- All 1080+ ithappy assets imported under `assets/third_party/ithappy/`
- All 15 structural wrapper scenes converted to ithappy meshes
- Kit catalog fully updated
- Room dressing props imported and cataloged (generators, terminals, crates, furniture, containers, capsules, farm elements)
- Threat/decor props imported (drones, turrets, cameras, barriers)
- Material library: ithappy's 11 materials mapped to Godot shaders
- Camera rig finalized based on Gate 3 dual-prototype decision
- Existing hand-authored modules archived as reference (not deleted until validation complete)

**Exit criteria:**
- Full procgen smoke suite passes with all 15 ithappy modules
- Golden parity smoke passes (live/staged structural agreement)
- Visual inspection: full ship generation with ithappy assets
- Document: `docs/superpowers/proofs/ithappy-full-conversion.md`

**Regression invariant:** 627-command regression bundle passes.

### Gate 5: Polish and content pass (ongoing)

**Owner:** Content/artist
**Dependencies:** Gate 4 approved
**Deliverables:**
- Room dressing placement rules (which props go in which room roles)
- Biome-specific variant selection (e.g., damaged vs intact props)
- Threat visual variety (turret types, drone types)
- Audio asset integration with ithappy prop interactions

**Exit criteria:**
- Each room role has at least 3 dressing variants
- Biome difficulty affects prop selection
- Document: `docs/superpowers/proofs/ithappy-content-pass.md`

**Regression invariant:** 627-command regression bundle passes.

---

## 7. Risk register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| ithappy scale doesn't match 4m grid | Low (real-world scale stated) | High — requires rescaling all assets | Gate 2 scale verification; Blender import test before purchase |
| Collision meshes are too detailed/missing | Medium | Medium — affects gameplay | Gate 2 collision check; can generate simplified collisions in Blender |
| Material count exceeds Godot mobile budget | Low (11 materials stated) | Medium — performance impact | Gate 2 material audit; can merge atlases |
| ithappy GLTF has naming inconsistencies | Medium | Low — requires renaming | Gate 3 import pipeline handles renaming |
| Camera angle doesn't work with ithappy art style | Low (explicitly supports isometric) | High — visual quality | Gate 3 camera tuning; screenshot comparison |
| ithappy pack doesn't include enough wall/door variants | Low (221 walls, 27 doors) | Medium — limits variety | Gate 2 count verification; supplement with custom models if needed |
| License restrictions (5 seats) | Low | Low — solo/small team | Verify license terms before purchase |
| Godot import issues with ithappy GLTF | Low (Godot 3.4+ stated) | Medium — requires conversion work | Gate 3 import test; Blender intermediate if needed |

---

## 8. Definition of done

- [ ] Procgen boundary audit complete — compiler never touches mesh data
- [ ] ithappy pack evaluated — scale, collision, materials verified
- [ ] 3-module integration prototype working — visual comparison documented
- [ ] All 15 structural modules converted — full procgen suite passes
- [ ] 627-command regression bundle passes unchanged
- [ ] Room dressing props imported and cataloged
- [ ] Camera rig tuned for ithappy asset density
- [ ] ADR written documenting the asset pack decision
- [ ] Cold-player playthrough: generate ship, walk through rooms, verify visuals

---

## 9. Follow-on work (out of scope)

- **Custom prop commissioning** for ithappy pack gaps (if any)
- **Biome-specific material variants** (e.g., rust, moss, ice)
- **Animated prop integration** (ithappy includes interactive/moving parts)
- **Audio integration** with ithappy prop interactions
- **Performance optimization** for mobile/VR targets
- **Cloud saves / Steamworks** (ADR-0032, unrelated)

---

## 10. Files to read before starting

| File | Why |
|------|-----|
| `scripts/procgen/structural_edge_compiler.gd` | Understand boundary compilation — confirm no mesh references |
| `scripts/procgen/generated_ship_loader.gd` | Understand wrapper instantiation — confirm module_id lookup |
| `data/kits/ship_structural_v0.json` | Current role→module mapping |
| `scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn` | Example wrapper scene — understand GLB reference structure |
| `scripts/camera/iso_camera_rig.gd` | Camera parameters for tuning |
| `scripts/procgen/structural_placer.gd` | Legacy placer — understand CELL_SIZE and module layout |
| `docs/superpowers/proofs/procgen-canonical-structural-compiler.md` | Existing parity proof — baseline for regression |
| `docs/game/06_validation_plan.md` | Regression bundle contract (627 commands) |

---

## 11. Operator decisions (2026-08-22)

| # | Question | Decision |
|---|----------|----------|
| 1 | Purchase timing | **Buy now** while 70% off sale is live ($35.70). |
| 2 | Isometric or top-down | **Prototype both** — convert 3 modules, screenshot in isometric AND top-down, decide after visual comparison. |
| 3 | Import path | **Direct GLTF import first**, optimize only if Godot profiling reveals issues. The pack is already lean (11 materials, 7 textures, ~493 tris/model). Don't pre-optimize. |
| 4 | Scope | **Everything at once** — import all 1080+ assets, not just structural modules. |
| 5 | Existing modules | **Use as scale/alignment reference, then discard.** Keep until ithappy wrappers are validated. |

---

## 12. Glossary

| Term | Definition |
|------|------------|
| **Wrapper scene** | A `.tscn` file that wraps a GLB mesh with collision, metadata, and socket empties. The procgen loader instantiates these by `module_id`. |
| **Kit catalog** | `data/kits/ship_structural_v0.json` — maps room roles (e.g., "cargo", "bridge") to lists of module_ids. Data-driven, no code changes needed. |
| **Structural plan** | The output of `StructuralEdgeCompiler` — a list of placement records with `placement_id`, `edge_key`, `kind`, `state`, `module_id`, `position`, `yaw_degrees`. |
| **Module_id** | A string identifier for a structural module (e.g., `floor_1x1`, `wall_straight_1x1`). Used by the kit catalog and loader. |
| **Regression bundle** | The 627-command validation suite in `docs/game/06_validation_plan.md`. Must pass after any change. |
| **Golden parity** | The contract that live and staged procgen outputs agree on structural placement (kind, state, module_id, position, yaw). Visual-only differences (GLB, material) are allowed. |
