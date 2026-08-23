# Focused 9 Gameplay-Grade Comparison Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `subagent-driven-development` (recommended) or `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create six gameplay-grade structural representatives, a staged pressure-door candidate, two staged visual-only gameplay props, and a deterministic locked-isometric baseline-versus-improved comparison artifact without changing current runtime bindings or assets.

**Architecture:** A focused-nine registry owns the comparison batch, its asset IDs, budgets, and staging paths. Blender recipes edit only namespaced generated visuals while preserving structural source helpers. All candidate GLBs, pressure-door wrapper resources, sidecars, evidence, and preview files stage under `assets/_staging/focused_nine/`; Godot validation copies those candidates into a temporary project overlay so current runtime files and catalogs remain unchanged.

**Tech Stack:** Python 3.11.15, Blender 5.2 LTS Python API, Godot 4.7.1, pytest, existing GLB metadata parser, existing structural contract/export/promotion utilities.

## Global Constraints

- Run all Python commands with `/opt/homebrew/bin/python3.11`; the host `python3` is 3.9.6 and cannot run `zip(..., strict=True)` code.
- Run project Python tests from repository root with `PYTHONPATH=.`.
- Blender executable: `/opt/homebrew/bin/blender`; Godot executable: `/opt/homebrew/bin/godot`.
- Use additive, deterministic Blender geometry only; do not use boolean subtraction in floor/ramp recipes.
- Preserve every existing structural `ModuleRoot_*`, `Geometry`, `AuthoringHelpers`, `Origin`, socket marker, collision proxy, and unrelated object. Delete/recreate only `FocusedNine_*` generated visual objects.
- Use `/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/salvage_industrial.blend` and only the approved Salvage Industrial material names.
- Current runtime paths under `assets/imported/`, generated live prop indexes, current wrapper scenes, current manifests, and current Godot bindings must remain byte-identical through the comparison batch.
- Candidate artifacts live under `assets/_staging/focused_nine/` inside the repository so `res://` containment and temporary Godot overlays work, but no runtime binder or catalog may scan that path.
- Godot script success requires its explicit pass marker and no unexpected `ERROR:`, `WARNING:`, or `SCRIPT ERROR:` diagnostics. Delete any generated `.godot/` and untracked `.import` state after Godot commands.
- Promotion and source backup are explicitly out of scope. Do not invoke `promote_structural_sources.py` without a later user approval.

---

## File Structure

| Path | Responsibility |
|---|---|
| `tools/focused_nine_contract.py` | Pure-Python registry, IDs, variant policy, output paths, triangle budgets, and report schema helpers. |
| `tools/structural_source_contract.py` | Adds isolated candidate-source loading for `pressure_door_1x1` without changing default runtime-source behavior. |
| `tools/focused_nine_blender_recipes.py` | Blender-only idempotent source recipes and atomic GLB export for all nine assets. |
| `tools/focused_nine_evidence.py` | Validates staged GLBs with GLB magic, metadata, clean Blender re-import, triangle/material metrics, and budgets. |
| `tools/focused_nine_staged_props.py` | Creates/validates staged, unbound prop sidecars without the live inventory/index. |
| `tools/focused_nine_staged_structural.py` | Builds pressure-door overlay resources and validates them in a temporary Godot project overlay. |
| `tools/focused_nine_batch.py` | Orchestrates generation, staging, validation, report creation, and capture without promotion. |
| `scenes/validation/focused_nine_comparison_harness.tscn` | Fixed baseline-versus-staged comparison scene. |
| `scripts/validation/focused_nine_comparison_capture.gd` | Windowed locked-isometric capture and explicit result marker. |
| `tests/test_focused_nine_*.py` | Unit/CLI contract, evidence, staging, and no-runtime-mutation tests. |
| `docs/superpowers/proofs/focused-nine-comparison.md` | Checked-in review evidence produced only after all gates pass. |

### Task 1: Focused-nine registry, report contract, and no-runtime mutation test

**Files:**
- Create: `tools/focused_nine_contract.py`
- Create: `tests/test_focused_nine_contract.py`

**Interfaces:**
- Produces `STRUCTURAL_IDS = ("floor_1x1", "wall_straight_1x1", "doorway_frame_open_1x1", "pillar_support_1x1", "ramp_up_1x2", "ceiling_cap_1x1", "pressure_door_1x1")`.
- Produces `PROP_IDS = ("hull_breach_seal_point", "fire_suppression_station")`.
- Produces `VARIANT_ROLES = {"pressure_door_1x1": ("intact", "damaged", "breached")}`; all other structural IDs are `("intact",)` for this comparison batch.
- Produces `asset_stage_dir(project_root: Path, asset_id: str) -> Path`, `asset_stage_glb(project_root: Path, asset_id: str, role: str = "intact") -> Path`, `comparison_report_path(project_root: Path) -> Path`, `validate_report(document: dict) -> list[str]`, and `runtime_mutation_paths(project_root: Path) -> tuple[Path, ...]`.

- [ ] **Step 1: Write failing registry tests.**

```python
def test_focused_nine_ids_are_exact_and_disjoint() -> None:
    assert contract.STRUCTURAL_IDS == (
        "floor_1x1", "wall_straight_1x1", "doorway_frame_open_1x1",
        "pillar_support_1x1", "ramp_up_1x2", "ceiling_cap_1x1", "pressure_door_1x1",
    )
    assert contract.PROP_IDS == ("hull_breach_seal_point", "fire_suppression_station")
    assert set(contract.STRUCTURAL_IDS).isdisjoint(contract.PROP_IDS)


def test_candidate_paths_stay_inside_focused_nine_staging(tmp_path: Path) -> None:
    path = contract.asset_stage_glb(tmp_path, "pressure_door_1x1", "damaged")
    assert path == tmp_path / "assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1_damaged.glb"
```

- [ ] **Step 2: Run the test to verify it fails.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_contract.py
```
Expected: import failure for `tools.focused_nine_contract`.

- [ ] **Step 3: Implement registry and strict report schema.**

Use exactly these report root fields: `schema_version`, `document_kind`, `assets`, `baseline`, `improved`, `preview`, `overall_pass`. Each asset record must require `asset_id`, `kind`, `source_path`, `staged_glbs`, `metrics`, `validation`, `pass`, and `first_error`. `metrics` must contain `sha256`, `byte_size`, `mesh_count`, `triangle_count`, `material_names`, and `bounds`.

- [ ] **Step 4: Add no-runtime-mutation digest coverage.**

```python
def test_runtime_mutation_paths_are_only_live_surfaces(project_root: Path) -> None:
    paths = contract.runtime_mutation_paths(project_root)
    assert project_root / "assets/imported" in paths
    assert project_root / "data/props/visual_bindings.generated.json" in paths
    assert project_root / "data/kits/ship_structural_v0.json" in paths
```

- [ ] **Step 5: Run focused tests.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_contract.py
```
Expected: PASS.

- [ ] **Step 6: Commit.**

```bash
git add tools/focused_nine_contract.py tests/test_focused_nine_contract.py
git commit -m "feat: define focused nine comparison contract"
```

### Task 2: Isolated pressure-door candidate contract and source validation

**Files:**
- Modify: `tools/structural_source_contract.py`
- Modify: `tools/validate_structural_sources.py`
- Modify: `tests/test_structural_source_contract.py`
- Modify: `tests/test_validate_structural_sources.py`
- Create: `data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json`

**Interfaces:**
- Produces `FOCUSED_NINE_CANDIDATE_MODULE_IDS = ("pressure_door_1x1",)`.
- Produces `load_candidate_source_spec(project_root: Path, module_id: str, source_glb_path: Path) -> StructuralSourceSpec`.
- Extends `validate_structural_sources.py` with `--candidate-source-glb module_id=relative/path.glb`; default `--all` remains the existing 15 runtime-backed modules.

- [ ] **Step 1: Write failing tests for candidate-only loading.**

```python
def test_candidate_pressure_door_loads_from_contained_staged_glb(tmp_path: Path) -> None:
    staged = tmp_path / "assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb"
    staged.parent.mkdir(parents=True)
    staged.write_bytes((PROJECT_ROOT / "assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb").read_bytes())
    _copy_pressure_contract(tmp_path)
    spec = load_candidate_source_spec(tmp_path, "pressure_door_1x1", staged)
    assert spec.module_id == "pressure_door_1x1"
    assert spec.source_glb_path == staged


def test_default_runtime_loader_rejects_unpromoted_pressure_door() -> None:
    with pytest.raises(ValueError, match="missing source GLB"):
        load_source_spec(PROJECT_ROOT, "pressure_door_1x1")
```

- [ ] **Step 2: Run contract tests and verify the new tests fail.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_structural_source_contract.py tests/test_validate_structural_sources.py
```
Expected: missing `load_candidate_source_spec` and pressure-door contract fixture.

- [ ] **Step 3: Implement candidate-path validation without changing the default allowlist behavior.**

`load_candidate_source_spec()` must reuse all existing JSON, containment, finite-bounds, socket, and SHA-256 validation; it must reject a path outside `project_root` and must never fall back to `assets/imported/`. Keep `STRUCTURAL_SOURCE_MODULE_IDS` as the live 15-ID runtime-backed set and keep candidate IDs in the new isolated tuple, avoiding a broken `--all` path before promotion.

- [ ] **Step 4: Add the pressure-door portal contract.**

Copy the doorway portal dimensions and three portal sockets from `doorway_frame_open_1x1_contract.json`, changing only `asset_id`, `module_id`, provenance ID, source asset path, and wrapper scene to `pressure_door_1x1`. Keep `grid_step_m: 4.0`, `footprint_cells: [1, 0]`, `nav_blocker: true`, and the portal edge/center socket IDs and compatibility lists unchanged.

- [ ] **Step 5: Add candidate CLI tests.**

Verify `--candidate-source-glb pressure_door_1x1=assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb` validates a matching source record; verify traversal and a missing staged GLB return deterministic nonzero diagnostics.

- [ ] **Step 6: Run focused structural tests.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_structural_source_contract.py tests/test_validate_structural_sources.py tests/test_recover_modules_cli.py
```
Expected: PASS; existing `--all` tests still cover exactly the 15 live source modules.

- [ ] **Step 7: Commit.**

```bash
git add tools/structural_source_contract.py tools/validate_structural_sources.py tests/test_structural_source_contract.py tests/test_validate_structural_sources.py data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json
git commit -m "feat: add staged pressure door contract"
```

### Task 3: Idempotent Blender source recipes for all nine assets

**Files:**
- Create: `tools/focused_nine_blender_recipes.py`
- Create: `tests/test_focused_nine_blender_recipes.py`
- Modify: `tools/improve_floor_geometry.py`

**Interfaces:**
- Produces Blender CLI: `--project-root PATH --structural-source-root PATH --props-source-root PATH --asset-id ID --overwrite-generated-only`.
- Produces `replace_generated_visuals(root, geometry, asset_id) -> None`, `ensure_structural_helpers(spec, root, helpers) -> None`, `build_structural_recipe(asset_id, spec, geometry) -> list[Any]`, and `build_prop_recipe(asset_id, collection) -> list[Any]`.
- `improve_floor_geometry.py` becomes a compatibility entry point that delegates `floor_1x1` to the new recipe driver; it must not clear scenes or perform boolean operations.

- [ ] **Step 1: Write pure-Python parser/selection tests.**

```python
def test_recipe_cli_rejects_unknown_asset_before_importing_bpy() -> None:
    with pytest.raises(SystemExit):
        recipes.parse_args(["--project-root", ".", "--structural-source-root", "/tmp/s", "--props-source-root", "/tmp/p", "--asset-id", "unknown"])


def test_structural_and_prop_source_paths_are_distinct(tmp_path: Path) -> None:
    assert recipes.source_path(tmp_path / "struct", tmp_path / "props", "wall_straight_1x1") == tmp_path / "struct/wall_straight_1x1/wall_straight_1x1.blend"
    assert recipes.source_path(tmp_path / "struct", tmp_path / "props", "hull_breach_seal_point") == tmp_path / "props/hull_breach_seal_point.blend"
```

- [ ] **Step 2: Run tests to verify failure.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_blender_recipes.py
```
Expected: import failure.

- [ ] **Step 3: Implement generated-object namespace and material library append.**

Every generated object name must begin `FocusedNine_<asset_id>_`. `replace_generated_visuals()` deletes only objects with that exact prefix from `Geometry` or the prop collection. Link or append `MAT_PaintedAlloyGray`, `MAT_WarningStripe`, `MAT_ReactorGlow`, and `MAT_Conduit` from `salvage_industrial.blend`; fail if a requested material does not exist.

- [ ] **Step 4: Implement structural recipes.**

Use additive applied-transform boxes, cylinders, and bevel modifiers for the six representatives:
- floor: panel seams, access plate, bolts, cable channels, drain cover;
- wall: perimeter frame, two inset panels, conduit, service cover;
- doorway: segmented jamb caps, lintel housing, two indicator bays;
- pillar: base, cap, four reinforcing ribs, conduit collar;
- ramp: stepped tread strips, low curbs, cable raceway;
- ceiling: recessed light trough, vent bars, cable tray.

Create `Export_intact`, `Export_damaged`, and `Export_breached` only for `pressure_door_1x1`; damaged removes one cosmetic panel and breached omits the central door leaf. Existing five variant-capable live families export only `intact` during this non-promotion batch; `ceiling_cap_1x1` also exports only `intact`.

- [ ] **Step 5: Implement pressure door and prop recipes.**

Pressure door: portal-sized outer frame, split central leaves, overhead motor housing, warning strip threshold, cyan indicators. Hull seal point: wall clamp frame, four clamp arms, orange service face, short conduit. Fire station: red cabinet, hose reel cylinder, emergency light, labeled-shape panel with no text mesh.

- [ ] **Step 6: Add Blender integration test.**

Execute Blender twice against a temporary copied `floor_1x1.blend`; inspect its JSON report after each pass. Assert the helper object list is byte-for-byte unchanged, all generated names have the prefix, no boolean modifiers exist, and generated object count is stable on rerun.

- [ ] **Step 7: Run recipe tests.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_blender_recipes.py
```
Expected: PASS.

- [ ] **Step 8: Commit.**

```bash
git add tools/focused_nine_blender_recipes.py tools/improve_floor_geometry.py tests/test_focused_nine_blender_recipes.py
git commit -m "feat: add idempotent focused nine blender recipes"
```

### Task 4: Atomic staged export plus GLB evidence and budget validator

**Files:**
- Create: `tools/focused_nine_evidence.py`
- Create: `tests/test_focused_nine_evidence.py`

**Interfaces:**
- Produces `inspect_staged_glb(glb_path: Path, blender: Path) -> dict`, `validate_evidence(record: dict, minimum: int, maximum: int) -> list[str]`, and CLI `--glb PATH --kind structural|prop --min-triangles N --max-triangles N --blender PATH --json-out PATH`.
- Record fields: existing `read_glb_metadata()` output plus `triangle_count`, `material_names`, `material_count`, `blender_reimport_passed`.

- [ ] **Step 1: Write failing validation tests using fixture GLBs.**

```python
def test_budget_validator_rejects_triangle_count_above_maximum() -> None:
    record = {"triangle_count": 1501, "mesh_count": 1, "material_names": ["MAT_PaintedAlloyGray"], "blender_reimport_passed": True}
    assert validate_evidence(record, 350, 1500) == ["triangle budget exceeded: 1501 > 1500"]


def test_atomic_json_publish_preserves_previous_evidence_on_failure(tmp_path: Path) -> None:
    target = tmp_path / "evidence.json"
    target.write_text('{"old":true}\n')
    with pytest.raises(ValueError):
        publish_json_atomically(target, {"triangle_count": float("nan")})
    assert target.read_text() == '{"old":true}\n'
```

- [ ] **Step 2: Run tests to verify failure.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_evidence.py
```
Expected: import failure.

- [ ] **Step 3: Implement static GLB checks and Blender clean-process inspection.**

Use `validate_glb_magic()` and `read_glb_metadata()` before launching Blender. Launch Blender with `--background --factory-startup --python` against a small inspector mode in the same tool. Count mesh loop triangles with `sum(len(mesh.loop_triangles) for mesh in bpy.data.meshes)` after `mesh.calc_loop_triangles()` and report sorted unique material names from imported mesh slots. Treat no mesh, zero triangles, or empty material list as a failure.

- [ ] **Step 4: Implement atomic evidence publication and strict budgets.**

Write evidence JSON to a sibling temporary file, flush it, then `os.replace`. Enforce 350–1,500 triangles for structural and 300–1,200 for props. Return sorted deterministic diagnostics.

- [ ] **Step 5: Add real Blender fixture coverage.**

Export a known small fixture GLB to a temporary directory; assert clean Blender re-import, positive triangles, a GLB hash matching `read_glb_metadata`, and deterministic sorted material names.

- [ ] **Step 6: Run focused tests.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_evidence.py tests/test_prop_visual_metadata.py tests/test_validate_promoted_sources.py
```
Expected: PASS.

- [ ] **Step 7: Commit.**

```bash
git add tools/focused_nine_evidence.py tests/test_focused_nine_evidence.py
git commit -m "feat: validate staged focused nine GLB evidence"
```

### Task 5: Staged visual-only prop exporter and sidecars

**Files:**
- Create: `tools/focused_nine_staged_props.py`
- Create: `tests/test_focused_nine_staged_props.py`

**Interfaces:**
- Produces `build_staged_sidecar(project_root: Path, glb_path: Path, asset_id: str) -> dict`, `validate_staged_sidecar(project_root: Path, glb_path: Path, sidecar: dict) -> list[str]`, and CLI `--project-root PATH --glb PATH --asset-id ID --sidecar-out PATH`.
- Both props have `prop_kind: "dressing"`, `binding.namespace: "visual_prop_id"`, `binding.ids: [asset_id]`, `collision_policy: "none_visual_only"`, and `extensions: {"comparison_role": "objective_prop", "staged_visual_only": true}`.

- [ ] **Step 1: Write failing sidecar tests.**

```python
def test_staged_sidecar_is_unbound_from_runtime_catalog(project_root: Path, staged_glb: Path) -> None:
    sidecar = build_staged_sidecar(project_root, staged_glb, "hull_breach_seal_point")
    assert sidecar["prop_kind"] == "dressing"
    assert sidecar["binding"] == {"namespace": "visual_prop_id", "ids": ["hull_breach_seal_point"]}
    assert sidecar["extensions"]["staged_visual_only"] is True


def test_staged_sidecar_rejects_runtime_imported_path(project_root: Path) -> None:
    with pytest.raises(ValueError, match="focused-nine staging"):
        build_staged_sidecar(project_root, project_root / "assets/imported/props/objectives/repair_junction.glb", "hull_breach_seal_point")
```

- [ ] **Step 2: Run tests to verify failure.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_staged_props.py
```
Expected: import failure.

- [ ] **Step 3: Implement contained staging-only sidecar generation.**

Require GLBs under `assets/_staging/focused_nine/props/`. Reuse `read_glb_metadata`, `validate_sidecar`, and `write_canonical_json`; do not call `generate_prop_sidecars.py`, do not touch `OBJECTIVE_IDS`, and do not write `data/props/visual_bindings.generated.json`.

- [ ] **Step 4: Implement staged validation.**

Validate actual `res://assets/_staging/focused_nine/props/<asset>.glb` path, hash, bytes, mesh count, bounds, finite transforms, no forbidden gameplay fields, visual-only collision, exact extension values, and no files under `assets/imported/props` changed.

- [ ] **Step 5: Run focused tests plus current catalog guard.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_staged_props.py tests/test_prop_visual_metadata.py tests/test_validate_prop_visual_bindings.py
```
Expected: PASS; current prop inventory/index remains valid.

- [ ] **Step 6: Commit.**

```bash
git add tools/focused_nine_staged_props.py tests/test_focused_nine_staged_props.py
git commit -m "feat: stage focused nine visual-only props"
```

### Task 6: Pressure-door staged wrapper package and overlay smoke

**Files:**
- Create: `tools/focused_nine_staged_structural.py`
- Create: `tests/test_focused_nine_staged_structural.py`
- Create: `assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.manifest.json`
- Create: `assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.input.json`
- Create: `assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.tscn`
- Create: `scripts/validation/focused_nine_staged_structural_smoke.gd`

**Interfaces:**
- Produces `build_overlay(project_root: Path, staging_root: Path, destination: Path) -> None` and `validate_pressure_door_overlay(project_root: Path, staging_root: Path, godot: Path) -> list[str]`.
- Smoke output: `FOCUSED_NINE_PRESSURE_DOOR_PASS variants=3 anchors=4 collision=true`.

- [ ] **Step 1: Write failing overlay-copy tests.**

```python
def test_overlay_receives_pressure_door_glbs_wrapper_and_contract(tmp_path: Path) -> None:
    build_overlay(PROJECT_ROOT, staged_root, tmp_path / "overlay")
    assert (tmp_path / "overlay/assets/imported/structural/ship_structural_v0/pressure_door_1x1/pressure_door_1x1.glb").is_file()
    assert (tmp_path / "overlay/scenes/wrappers/structural/ship_structural_v0/pressure_door_1x1.tscn").is_file()


def test_live_project_has_no_pressure_door_wrapper_before_promotion() -> None:
    assert not (PROJECT_ROOT / "scenes/wrappers/structural/ship_structural_v0/pressure_door_1x1.tscn").exists()
```

- [ ] **Step 2: Run tests to verify failure.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_staged_structural.py
```
Expected: import failure.

- [ ] **Step 3: Implement staged wrapper resources.**

The staged wrapper must mirror the portal wrapper hierarchy: root `Pressure_Door_1x1`; `Anchor_FloorCenter`; three contract socket `Marker3D` nodes; `CollisionRoot/CollisionShape3D`; `Visual/VisualInstance_Intact`, `VisualInstance_Damaged`, `VisualInstance_Breached`. Use only overlay canonical paths in its `ExtResource` entries.

- [ ] **Step 4: Implement isolated overlay and smoke.**

Copy the project excluding `.git`, `.godot`, caches, and `.superpowers`; overlay the three pressure GLBs, contract, wrapper `.tscn`, manifest, and input files only in the temporary project. The smoke loads the wrapper and asserts exactly three variant children, all four anchors, and one collision shape. It must print the exact pass marker.

- [ ] **Step 5: Add failure isolation tests.**

Delete the breached GLB in a copied staging tree and assert validation fails with `missing staged variant breached`; assert the original project wrapper directory remains unchanged after any failed overlay validation.

- [ ] **Step 6: Run focused wrapper tests.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_staged_structural.py tests/test_validate_promoted_sources.py tests/test_validate_structural_variant_bindings.py
```
Expected: PASS; current eight-family validator remains unchanged.

- [ ] **Step 7: Commit.**

```bash
git add tools/focused_nine_staged_structural.py tests/test_focused_nine_staged_structural.py assets/_staging/focused_nine/structural/pressure_door_1x1 scripts/validation/focused_nine_staged_structural_smoke.gd
git commit -m "feat: validate staged pressure door wrapper"
```

### Task 7: Deterministic comparison harness and capture

**Files:**
- Create: `scenes/validation/focused_nine_comparison_harness.tscn`
- Create: `scripts/validation/focused_nine_comparison_capture.gd`
- Create: `tests/test_focused_nine_comparison_capture.py`

**Interfaces:**
- CLI args: `--output-dir DIR --baseline-label Baseline --improved-label Improved`.
- Produces `FOCUSED_NINE_COMPARISON_CAPTURE PASS output=<png>`.
- Produces stable image path `artifacts/validation-previews/focused-nine/focused-nine-comparison.png`.

- [ ] **Step 1: Write static-scene and script tests.**

```python
def test_capture_script_uses_locked_iso_camera_and_staged_glb_loading() -> None:
    source = CAPTURE_SCRIPT.read_text()
    assert "CAMERA_SIZE := 18.0" in source
    assert "GLTFDocument" in source
    assert "FOCUSED_NINE_COMPARISON_CAPTURE PASS" in source


def test_harness_has_baseline_and_improved_roots() -> None:
    scene = HARNESS_SCENE.read_text()
    assert 'name="Baseline"' in scene
    assert 'name="Improved"' in scene
```

- [ ] **Step 2: Run tests to verify failure.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_comparison_capture.py
```
Expected: missing scene/script files.

- [ ] **Step 3: Implement the comparison scene.**

Use the orthographic camera transform and `size = 18.0` from `locked_iso_readability_harness`. Keep baseline and improved roots 10 m apart, use identical lighting, and ensure no UI labels are visible in the saved image. Baseline uses current live GLBs and `readability_prop_factory.gd` stand-ins; improved loads staged GLBs with `GLTFDocument.append_from_file()`.

- [ ] **Step 4: Implement windowed capture.**

Wait ten process frames before calling `get_root().get_texture().get_image().save_png(output)`. Require a 1600×900 PNG, ensure nonzero byte size, copy the first stable frame to `focused-nine-comparison.png`, and print the exact pass marker.

- [ ] **Step 5: Run static tests and real windowed capture.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_comparison_capture.py
/opt/homebrew/bin/godot --path . --editor --scene res://scenes/validation/focused_nine_comparison_harness.tscn -- --output-dir artifacts/validation-previews/focused-nine
```
Expected: test PASS and `FOCUSED_NINE_COMPARISON_CAPTURE PASS`; inspect diagnostics and remove generated Godot state afterward.

- [ ] **Step 6: Commit.**

```bash
git add scenes/validation/focused_nine_comparison_harness.tscn scripts/validation/focused_nine_comparison_capture.gd tests/test_focused_nine_comparison_capture.py
git commit -m "feat: capture focused nine comparison"
```

### Task 8: Batch orchestration, report, and final no-promotion acceptance gate

**Files:**
- Create: `tools/focused_nine_batch.py`
- Create: `tests/test_focused_nine_batch.py`
- Create: `docs/superpowers/proofs/focused-nine-comparison.md`

**Interfaces:**
- CLI: `--project-root PATH --structural-source-root PATH --props-source-root PATH --report PATH --preview-dir PATH [--asset ID ...] [--dry-run]`.
- Success markers: `FOCUSED_NINE_STAGED asset=<id>`, `FOCUSED_NINE_REPORT path=<path>`, `FOCUSED_NINE_BATCH PASS assets=9`.

- [ ] **Step 1: Write failing orchestration tests.**

```python
def test_dry_run_is_side_effect_free(tmp_path: Path) -> None:
    before = snapshot_runtime_surfaces(PROJECT_ROOT)
    result = run_batch("--dry-run", "--asset", "floor_1x1")
    assert result.returncode == 0
    assert snapshot_runtime_surfaces(PROJECT_ROOT) == before
    assert not (PROJECT_ROOT / "assets/_staging/focused_nine").exists()


def test_failed_asset_preserves_previous_staging_and_reports_first_error(tmp_path: Path) -> None:
    existing = tmp_path / "assets/_staging/focused_nine/props/hull_breach_seal_point.glb"
    existing.parent.mkdir(parents=True)
    existing.write_bytes(b"previous")
    result = run_batch("--asset", "hull_breach_seal_point", env={"FOCUSED_NINE_FORCE_EXPORT_FAILURE": "1"})
    assert result.returncode == 1
    assert existing.read_bytes() == b"previous"
    assert report_for(result)["assets"][0]["first_error"] == "forced export failure: hull_breach_seal_point"
```

- [ ] **Step 2: Run tests to verify failure.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_batch.py
```
Expected: import failure.

- [ ] **Step 3: Implement atomic per-asset orchestration.**

For every requested asset: snapshot runtime mutation paths; invoke recipe generation; atomic export to its staging directory; run evidence validation; create staged prop sidecar or staged pressure wrapper overlay validation; append one deterministic report record. On any asset failure, preserve prior stage content and store its first causal error; do not claim a batch pass.

- [ ] **Step 4: Implement final report and proof generation.**

Write `assets/_staging/focused_nine/focused-nine-comparison.json` atomically. After a nine-asset pass, run the comparison capture and write `docs/superpowers/proofs/focused-nine-comparison.md` with each asset’s source path, staged paths, hash, bytes, mesh/triangle/material metrics, validator result, preview path, and explicit statement that no runtime promotion occurred.

- [ ] **Step 5: Run focused unit tests.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_contract.py tests/test_focused_nine_blender_recipes.py tests/test_focused_nine_evidence.py tests/test_focused_nine_staged_props.py tests/test_focused_nine_staged_structural.py tests/test_focused_nine_comparison_capture.py tests/test_focused_nine_batch.py
```
Expected: PASS.

- [ ] **Step 6: Run the real batch and acceptance gates.**

Run:
```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 tools/focused_nine_batch.py \
  --project-root . \
  --structural-source-root /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0 \
  --props-source-root /Volumes/Untitled/SynapticSeaAssets/meshes/source/props \
  --report assets/_staging/focused_nine/focused-nine-comparison.json \
  --preview-dir artifacts/validation-previews/focused-nine
PYTHONPATH=. /opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root . \
  --source-root /Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0 \
  --all \
  --blender /opt/homebrew/bin/blender
PYTHONPATH=. /opt/homebrew/bin/python3.11 tools/validate_prop_visual_bindings.py --project-root . --check-index
git diff --exit-code -- assets/imported data/props/visual_bindings.generated.json data/kits/ship_structural_v0.json scenes/wrappers/structural/ship_structural_v0
```
Expected: `FOCUSED_NINE_BATCH PASS assets=9`, current source validator PASS for 15 live modules, current prop binding validator PASS, and no diff in runtime surfaces.

- [ ] **Step 7: Commit review artifacts.**

```bash
git add tools/focused_nine_batch.py tests/test_focused_nine_batch.py docs/superpowers/proofs/focused-nine-comparison.md assets/_staging/focused_nine/focused-nine-comparison.json artifacts/validation-previews/focused-nine/focused-nine-comparison.png
git commit -m "feat: stage focused nine comparison batch"
```

## Plan Self-Review

- **Spec coverage:** Tasks 1–8 cover all nine assets, source-only structural editing, a staged pressure-door candidate, visual-only staged props, evidence/budgets, deterministic visual comparison, error isolation, and the no-promotion gate. Source backup and promotion are intentionally excluded per spec.
- **Critical reconciliation:** The approved no-runtime rule conflicts with globally expanding a 15-ID runtime-backed loader before a pressure-door GLB exists. Task 2 resolves this with an isolated candidate registry and explicit staged GLB loader; default live `--all` remains the valid 15-module check. This preserves the approved safety boundary without inventing a runtime asset.
- **Variant policy:** Existing representative variants remain baseline during comparison; only pressure door demonstrates all three staged roles. This prevents silent half-updating of runtime variant families.
- **Placeholder scan:** No TODO/TBD/open-question steps are present. Every created interface, command, output path, and validation expectation is defined above.
- **Type consistency:** All batch asset IDs, staging paths, report keys, pass markers, candidate-loader names, and CLI arguments use one exact spelling across tasks.
