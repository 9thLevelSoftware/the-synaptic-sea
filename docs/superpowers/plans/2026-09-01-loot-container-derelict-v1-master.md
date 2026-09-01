# Loot Container Derelict v1 Master Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild selected Meshy Candidate 1 as one clean, functional Blender master with closed/open/looted states, deterministic preview evidence, and a validated task-local `cleaned.glb` only after visual approval.

**Architecture:** Add one asset-specific deterministic Blender recipe with a host-safe CLI and testable manifest contract. The recipe edits the canonical external master, preserves `SOURCE_RAW`, builds one low-poly hierarchy, renders three state previews into external evidence, and exports a scratch GLB. After human visual approval, the same recipe publishes the canonical task-local `cleaned.glb`; the existing independent validator publishes `blender-validation.json`.

**Tech Stack:** Python 3.9.6, Blender 5.2 LTS Python/`bpy`, repository Meshy governance helpers, pytest, Pillow for decoded-RGBA evidence checks.

## Global Constraints

- Requirements: REQ-AIAP-005, REQ-AIAP-006, REQ-AIAP-007, REQ-AIAP-009.
- Selected task: `01a05dcb-fc3b-7418-b105-2170af354088`.
- Dimensions: `(X, Y, Z) = (0.90, 0.55, 0.65)` metres within `0.01 m` per axis.
- Pivot: bottom center; X/Y centered on zero and minimum Z at zero.
- Forward axis: canonical local `+Z`; transforms finite and positive-orientation.
- Maximum triangles: `3,000`; design target: at most `1,500`.
- Maximum materials: `2`; every exported primitive requires UV0 within `[0, 1]`.
- Required states: `closed`, `open`, `looted`, all from one hierarchy and one Blender master.
- Default exported pose: `closed`; no duplicated whole-state meshes.
- No generic auto-decimation; use deliberate primitive topology and bevels.
- Preserve hidden immutable `SOURCE_RAW` and Meshy `paid-private` provenance.
- Godot remains owner of collision, interaction, inventory truth, navigation, and gameplay bindings.
- Never write runtime/import/catalog/index/wrapper paths during this plan.
- Do not modify, stage, or commit `.hermes/plans/2026-08-30_201614-meshy-blender-asset-production-system.md`.
- Visual approval is mandatory before publishing task-local `cleaned.glb`.

## File Structure

Repository files:

- Create `tools/meshy_loot_container_recipe.py` — host CLI, path/governance checks, Blender authoring runtime, previews, manifest, scratch export, and approved publication mode.
- Create `tests/test_meshy_loot_container_recipe.py` — host contract tests, manifest tests, path rejection, command construction, and focused Blender integration probe.
- Existing, read-only `tools/meshy_blender_master.py` — supplies the governed external master skeleton.
- Existing, read-only `tools/meshy_blender_validate.py` — independently validates/publishes final GLB evidence.

External outputs:

- Update `/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend`.
- Create `/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/build_recipe_manifest.json`.
- Create evidence under `/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/loot_container_derelict_v1/selected_01a05dcb_master_0244e568/`.
- Publish `assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088/cleaned.glb` only after visual approval.
- Publish the adjacent `blender-validation.json` only through the existing validator.

---

### Task 1: Host-safe recipe contract and governed paths

**Files:**
- Create: `tools/meshy_loot_container_recipe.py`
- Create: `tests/test_meshy_loot_container_recipe.py`

**Interfaces:**
- Consumes: repository root, contract path, selected task directory, canonical external master path, and external evidence directory.
- Produces:
  - `RecipePaths(project_root: Path, task_dir: Path, master_path: Path, evidence_dir: Path, scratch_glb: Path, manifest_path: Path)`
  - `PublishedArtifact(path: Path, sha256: str, byte_size: int)`
  - `derive_recipe_paths(project_root: Path, task_dir: Path, evidence_dir: Path) -> RecipePaths`
  - `resolve_recipe_paths(project_root: Path, contract_path: Path, task_dir: Path, evidence_dir: Path) -> tuple[AssetContract, RecipePaths]`
  - `build_blender_command(paths: RecipePaths, contract_path: Path, mode: str) -> list[str]`
  - `validate_manifest_document(document: Mapping[str, Any]) -> list[str]`
  - `publish_cleaned(source_glb: Path, destination: Path, allowed_root: Path) -> PublishedArtifact`
  - CLI modes `preview` and `publish-cleaned`.

- [ ] **Step 1: Write host-import and exact-path RED tests**

```python
from __future__ import annotations

import copy
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[1]
RECIPE = ROOT / "tools/meshy_loot_container_recipe.py"


def test_host_import_does_not_load_bpy() -> None:
    sys.modules.pop("bpy", None)
    from tools import meshy_loot_container_recipe as recipe
    assert recipe.ASSET_ID == "loot_container_derelict_v1"
    assert recipe.SELECTED_TASK_ID == "01a05dcb-fc3b-7418-b105-2170af354088"
    assert "bpy" not in sys.modules


def test_paths_are_exact_and_runtime_paths_are_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from tools import meshy_loot_container_recipe as recipe

    project = tmp_path / "project"
    task_dir = project / "assets/_staging/meshy" / recipe.ASSET_ID / recipe.SELECTED_TASK_ID
    evidence = tmp_path / "live-pilot" / recipe.ASSET_ID / "evidence"
    trusted_master = tmp_path / "source"
    master_dir = trusted_master / recipe.ASSET_ID
    master_dir.mkdir(parents=True)
    (master_dir / f"{recipe.ASSET_ID}_master.blend").write_bytes(b"BLENDER-v305")
    task_dir.mkdir(parents=True)
    evidence.mkdir(parents=True)
    monkeypatch.setattr(recipe, "TRUSTED_MASTER_ROOT", trusted_master)
    monkeypatch.setattr(recipe, "TRUSTED_EVIDENCE_ROOT", tmp_path / "live-pilot" / recipe.ASSET_ID)

    paths = recipe.derive_recipe_paths(project, task_dir, evidence)
    assert paths.master_path.name == "loot_container_derelict_v1_master.blend"
    assert paths.scratch_glb == evidence / "cleaned.preview.glb"
    with pytest.raises(ValueError, match="protected|runtime"):
        recipe.validate_external_evidence_dir(project / "assets/imported")
```

- [ ] **Step 2: Run RED tests**

Run:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /usr/bin/python3 -m pytest -q tests/test_meshy_loot_container_recipe.py -k 'host_import or paths_are_exact'`

Expected: FAIL because `tools.meshy_loot_container_recipe` does not exist.

- [ ] **Step 3: Implement the minimal host layer**

Use this structure:

```python
ASSET_ID = "loot_container_derelict_v1"
SELECTED_TASK_ID = "01a05dcb-fc3b-7418-b105-2170af354088"
BLENDER = Path("/opt/homebrew/bin/blender")
TRUSTED_MASTER_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source")
TRUSTED_EVIDENCE_ROOT = Path("/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot") / ASSET_ID
MASTER = TRUSTED_MASTER_ROOT / ASSET_ID / f"{ASSET_ID}_master.blend"
PROTECTED = (Path("assets/imported"), Path("data/combat"), Path("data/props"), Path("scenes/wrappers"))

@dataclass(frozen=True)
class RecipePaths:
    project_root: Path
    task_dir: Path
    master_path: Path
    evidence_dir: Path
    scratch_glb: Path
    manifest_path: Path
```

`resolve_recipe_paths` must reuse the governed candidate loader, require `review.state == "selected"`, require the exact task ID, verify `generation.status == "SUCCEEDED"`, validate the task-local raw hash, require the canonical regular master, and reject symlink/path rebinding at every trusted root. Evidence must remain under `/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/loot_container_derelict_v1/` and outside the repository.

- [ ] **Step 4: Write manifest-shape RED tests**

```python
def fixture_manifest() -> dict[str, Any]:
    from tools import meshy_loot_container_recipe as recipe

    return {
        "schema_version": "1.0.0",
        "document_kind": "loot_container_master_recipe",
        "asset_id": recipe.ASSET_ID,
        "task_id": recipe.SELECTED_TASK_ID,
        "contract_sha256": "a" * 64,
        "raw_sha256": "b" * 64,
        "master_path": str(recipe.MASTER),
        "objects": ["ContainerRoot", "ContainerBody", "HingePivot", "ContainerLid",
                    "FrontHandle", "LatchLeft", "LatchRight", "LootVisual"],
        "states": {"closed": 1, "open": 30, "looted": 60},
        "hinge": {"axis": "X", "open_degrees": 105.0},
        "dimensions_m": [0.9, 0.55, 0.65],
        "triangle_count": 900,
        "materials": ["painted_ship_alloy", "warning_accent"],
        "uvs_present": True,
        "source_raw_preserved": True,
        "runtime_promoted": False,
        "renders": {},
    }


def test_manifest_requires_exact_geometry_and_states() -> None:
    valid = fixture_manifest()
    assert recipe.validate_manifest_document(valid) == []
    invalid = copy.deepcopy(valid)
    invalid["states"] = {"closed": 1, "open": 30}
    assert "states must be exactly closed/open/looted" in recipe.validate_manifest_document(invalid)
    invalid = copy.deepcopy(valid)
    invalid["triangle_count"] = 3001
    assert "triangle budget exceeded" in recipe.validate_manifest_document(invalid)
```

The canonical manifest fields are:

```python
{
    "schema_version": "1.0.0",
    "document_kind": "loot_container_master_recipe",
    "asset_id": ASSET_ID,
    "task_id": SELECTED_TASK_ID,
    "contract_sha256": contract.sha256,
    "raw_sha256": governance.file_sha256(paths.task_dir / "raw.glb"),
    "master_path": str(MASTER),
    "objects": ["ContainerRoot", "ContainerBody", "HingePivot", "ContainerLid",
                "FrontHandle", "LatchLeft", "LatchRight", "LootVisual"],
    "states": {"closed": 1, "open": 30, "looted": 60},
    "hinge": {"axis": "X", "open_degrees": 105.0},
    "dimensions_m": [0.9, 0.55, 0.65],
    "triangle_count": 0,
    "materials": ["painted_ship_alloy", "warning_accent"],
    "uvs_present": True,
    "source_raw_preserved": True,
    "runtime_promoted": False,
    "renders": {},
}
```

- [ ] **Step 5: Implement strict manifest validation and command construction**

`validate_manifest_document` must reject missing/extra top-level fields, wrong identity/hash formats, object/state set drift, dimensions outside tolerance, triangles above 3,000, material inventory other than one or two permitted names, missing UV evidence, missing raw preservation, or any promotion flag other than false.

`build_blender_command` must return:

```python
[
    str(BLENDER), "--background", str(paths.master_path),
    "--python", str(paths.project_root / "tools/meshy_loot_container_recipe.py"), "--",
    "--project-root", str(paths.project_root),
    "--contract", str(contract_path),
    "--task-dir", str(paths.task_dir),
    "--evidence-dir", str(paths.evidence_dir),
    "--mode", mode,
]
```

- [ ] **Step 6: Run focused GREEN tests**

Run:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /usr/bin/python3 -m pytest -q tests/test_meshy_loot_container_recipe.py`

Expected: all focused host tests pass.

- [ ] **Step 7: Run adjacent host regression**

Run:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /usr/bin/python3 -m pytest -q tests/test_meshy_blender_tools.py tests/test_meshy_candidate_review.py`

Expected: all tests pass.

- [ ] **Step 8: Commit Task 1**

```bash
git add tools/meshy_loot_container_recipe.py tests/test_meshy_loot_container_recipe.py
git commit -m "feat: add deterministic loot container recipe"
```

---

### Task 2: Functional hierarchy, state animation, previews, and scratch export

**Files:**
- Modify: `tools/meshy_loot_container_recipe.py`
- Modify: `tests/test_meshy_loot_container_recipe.py`
- External outputs only under the canonical source/evidence roots.

**Interfaces:**
- Consumes: Task 1 `RecipePaths`, selected raw evidence, and the canonical master skeleton.
- Produces:
  - `run_blender_recipe(paths: RecipePaths, contract: AssetContract, mode: str) -> dict[str, Any]`
  - one updated canonical master;
  - `cleaned.preview.glb` outside the repository;
  - `closed.png`, `open.png`, `looted.png`, `states_contact_sheet.png`, and canonical manifest.

- [ ] **Step 1: Write Blender source-policy RED tests**

The tests inspect the recipe source without importing `bpy` and require the exact authoring helpers:

```python
def test_recipe_declares_functional_hierarchy_and_no_decimator() -> None:
    source = RECIPE.read_text(encoding="utf-8")
    for name in ("ContainerBody", "HingePivot", "ContainerLid", "FrontHandle",
                 "LatchLeft", "LatchRight", "LootVisual"):
        assert name in source
    assert "DECIMATE" not in source
    assert "collision" not in recipe.EXPORT_OBJECT_NAMES
```

Add a manifest fixture test that rejects duplicate state meshes and requires one `lid_open` action.

- [ ] **Step 2: Run RED tests**

Run:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /usr/bin/python3 -m pytest -q tests/test_meshy_loot_container_recipe.py -k 'functional_hierarchy or lid_open'`

Expected: FAIL because Blender authoring helpers are absent.

- [ ] **Step 3: Implement deterministic geometry helpers**

Inside Blender runtime only, implement:

```python
def _link_only(obj: Any, collection: Any) -> None:
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)


def _add_box(name: str, center: tuple[float, float, float], size: tuple[float, float, float],
             collection: Any, material: Any, bevel: float = 0.0) -> Any:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    _link_only(obj, collection)
    obj.data.materials.append(material)
    if bevel > 0.0:
        modifier = obj.modifiers.new(name="PurposefulEdgeBevel", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj

def _join_as(name: str, objects: list[Any]) -> Any:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]

def _add_u_handle(collection: Any, material: Any) -> Any:
    parts = [
        _add_box("HandleLeft", (-0.19, -0.266, 0.29), (0.035, 0.018, 0.13), collection, material, 0.004),
        _add_box("HandleRight", (0.19, -0.266, 0.29), (0.035, 0.018, 0.13), collection, material, 0.004),
        _add_box("HandleGrip", (0.0, -0.266, 0.235), (0.38, 0.018, 0.035), collection, material, 0.004),
    ]
    return _join_as("FrontHandle", parts)

def _build_body(collection: Any, alloy: Any) -> Any:
    parts = [
        _add_box("BodyFloor", (0.0, 0.0, 0.035), (0.90, 0.55, 0.07), collection, alloy, 0.006),
        _add_box("BodyFront", (0.0, -0.2625, 0.25), (0.90, 0.025, 0.36), collection, alloy, 0.006),
        _add_box("BodyRear", (0.0, 0.2625, 0.25), (0.90, 0.025, 0.36), collection, alloy, 0.006),
        _add_box("BodyLeft", (-0.4375, 0.0, 0.25), (0.025, 0.50, 0.36), collection, alloy, 0.006),
        _add_box("BodyRight", (0.4375, 0.0, 0.25), (0.025, 0.50, 0.36), collection, alloy, 0.006),
    ]
    return _join_as("ContainerBody", parts)

def _build_lid(collection: Any, hinge: Any, alloy: Any) -> Any:
    parts = [
        _add_box("LidTop", (0.0, 0.0, 0.60), (0.90, 0.55, 0.10), collection, alloy, 0.006),
        _add_box("LidFront", (0.0, -0.2625, 0.49), (0.90, 0.025, 0.12), collection, alloy, 0.006),
        _add_box("LidRear", (0.0, 0.2625, 0.49), (0.90, 0.025, 0.12), collection, alloy, 0.006),
    ]
    lid = _join_as("ContainerLid", parts)
    lid.parent = hinge
    lid.matrix_parent_inverse = hinge.matrix_world.inverted()
    return lid

def _build_latches_and_accents(collection: Any, accent: Any) -> list[Any]:
    return [
        _add_box("LatchLeft", (-0.23, -0.272, 0.43), (0.07, 0.006, 0.14), collection, accent, 0.003),
        _add_box("LatchRight", (0.23, -0.272, 0.43), (0.07, 0.006, 0.14), collection, accent, 0.003),
        _add_box("LootVisual", (0.0, 0.0, 0.12), (0.28, 0.18, 0.08), collection, accent, 0.004),
    ]

def _unwrap_object(obj: Any) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
```

Use deliberate low-poly boxes/rails with these fixed envelopes:

- base/body exterior: width `0.90`, depth `0.55`, body top at `Z=0.43`;
- lid exterior: closed top at `Z=0.65`, hinge center near `(0, 0.245, 0.43)`;
- wall thickness: `0.025` m; interior floor above `Z=0.05`;
- handle and latches remain inside the overall Y bound `[-0.275, 0.275]`;
- all bevels are applied, bounded to `0.008` m or less, and use one segment;
- geometry is built directly inside final dimensions rather than scaled afterward.

Construct the body as floor plus four walls so the open state has a real cavity. Construct the lid as top plus four shallow walls parented through `HingePivot`. Add small reinforcement rails/corners only while remaining below the 1,500-triangle design target.

- [ ] **Step 4: Implement materials, UVs, hierarchy, and metadata**

Create only:

```python
painted_ship_alloy = make_material("painted_ship_alloy", (0.23, 0.29, 0.34, 1.0), metallic=0.65, roughness=0.48)
warning_accent = make_material("warning_accent", (0.65, 0.18, 0.06, 1.0), metallic=0.4, roughness=0.42)
```

UV unwrap every exported mesh with deterministic cube/smart projection and pack into `[0, 1]`. Create `ContainerRoot` custom properties:

```python
root["required_states"] = "closed,open,looted"
root["default_state"] = "closed"
root["hinge_axis"] = "X"
root["hinge_open_degrees"] = 105.0
root["state_frames"] = "closed:1,open:30,looted:60"
root["collision_owner"] = "godot_wrapper"
root["source_provider"] = "meshy"
root["source_task_id"] = SELECTED_TASK_ID
```

- [ ] **Step 5: Implement one hinge action and state presentations**

At frame 1, keyframe `HingePivot.rotation_euler.x = 0`. At frames 30 and 60, keyframe the same pivot at `math.radians(-105.0)`. Name the action `lid_open`. Keep one set of lid/body meshes.

Use `LootVisual` only as a lightweight non-gameplay visual insert. Keyframe its Blender `hide_render` presentation so it is hidden at frame 1, visible at frame 30, and hidden at frame 60. Store `LootVisual["wrapper_visibility"] = "open_unlooted_only"`; runtime state remains wrapper-owned.

- [ ] **Step 6: Implement closed/open/looted rendering**

Use deterministic `BLENDER_WORKBENCH` rendering at `640x640`, transparent background disabled, fixed studio light, fixed orthographic locked-isometric camera, fixed color management, and no temporal effects. Render frames 1, 30, and 60 to the evidence directory.

Create `states_contact_sheet.png` with labels and 3 columns using Pillow from host mode. Hash decoded RGBA pixels rather than PNG container bytes.

- [ ] **Step 7: Implement scratch GLB export and manifest**

Export only the functional visual hierarchy to `cleaned.preview.glb` with `export_format='GLB'`, selection-only, applied mesh transforms, extras, materials, UVs, and animations enabled. Do not export `SOURCE_RAW`, cameras, lights, authoring markers, collision, or helper meshes.

Compute the manifest from the saved master and exported scratch GLB. Validate it before atomically writing `build_recipe_manifest.json` and the evidence copy.

- [ ] **Step 8: Add a real Blender integration probe**

The test creates a disposable copy of the canonical master and evidence root, runs `preview`, and asserts:

```python
assert result.returncode == 0
assert "LOOT CONTAINER RECIPE PASS mode=preview" in result.stdout
assert manifest["objects"] == EXPECTED_OBJECTS
assert manifest["states"] == {"closed": 1, "open": 30, "looted": 60}
assert manifest["triangle_count"] <= 1500
assert manifest["materials"] == ["painted_ship_alloy", "warning_accent"]
assert all((evidence / name).is_file() for name in
           ("closed.png", "open.png", "looted.png", "states_contact_sheet.png", "cleaned.preview.glb"))
```

The disposable probe must never point at the live task-local `cleaned.glb`.

- [ ] **Step 9: Run RED/GREEN and adjacent tests**

Run:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /usr/bin/python3 -m pytest -q tests/test_meshy_loot_container_recipe.py`

Then:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /usr/bin/python3 -m pytest -q tests/test_meshy_blender_tools.py tests/test_meshy_candidate_review.py tests/test_meshy_governance.py`

Expected: all focused and adjacent tests pass.

- [ ] **Step 10: Commit Task 2**

```bash
git add tools/meshy_loot_container_recipe.py tests/test_meshy_loot_container_recipe.py
git commit -m "feat: author functional loot container states"
```

- [ ] **Step 11: Build live external preview evidence twice**

Run `preview` twice in fresh disposable evidence roots and once in the canonical evidence root. Compare:

- exact object inventory;
- dimensions and triangle/material counts;
- state frame/hinge metadata;
- decoded RGBA hashes for all three renders;
- scratch GLB semantic validation;
- unchanged protected repository/runtime paths.

Expected marker:

`LOOT CONTAINER RECIPE PASS mode=preview asset=loot_container_derelict_v1 states=closed,open,looted`

- [ ] **Step 12: Open the contact sheet for human visual approval**

On macOS:

`open -a Preview /Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/loot_container_derelict_v1/selected_01a05dcb_master_0244e568/states_contact_sheet.png`

Stop here until Christopher explicitly approves the closed/open/looted visual result.

---

### Task 3: Publish and independently validate `cleaned.glb`

**Files:**
- Modify: `tools/meshy_loot_container_recipe.py` only if Task 2 review finds a publication defect.
- Modify: `tests/test_meshy_loot_container_recipe.py` only with a RED test for that defect.
- Create external/task evidence: task-local `cleaned.glb` and `blender-validation.json`.

**Interfaces:**
- Consumes: visually approved canonical master and Task 2 manifest.
- Produces: governed `cleaned.glb` and independent `blender-validation.json`.

- [ ] **Step 1: Write/confirm publication idempotency test**

```python
def test_publish_cleaned_is_exclusive_and_idempotent(tmp_path: Path) -> None:
    from tools import meshy_loot_container_recipe as recipe

    source_glb = tmp_path / "source.glb"
    destination = tmp_path / "task" / "cleaned.glb"
    destination.parent.mkdir()
    source_glb.write_bytes((ROOT / "tests/fixtures/meshy_blender/fixture_triangle.glb").read_bytes())
    first = recipe.publish_cleaned(source_glb, destination, allowed_root=tmp_path)
    second = recipe.publish_cleaned(source_glb, destination, allowed_root=tmp_path)
    assert first.sha256 == second.sha256
    destination.write_bytes(b"attacker")
    with pytest.raises(ValueError, match="already exists|mismatch"):
        recipe.publish_cleaned(source_glb, destination, allowed_root=tmp_path)
    assert destination.read_bytes() == b"attacker"
```

Use the existing governed exclusive-create helper; never replace a mismatching leaf.

- [ ] **Step 2: Run the focused publication test**

Run:

`PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 PYTHONPATH=. /usr/bin/python3 -m pytest -q tests/test_meshy_loot_container_recipe.py -k publish_cleaned`

Expected: PASS.

- [ ] **Step 3: Publish the approved GLB**

Run the recipe in `publish-cleaned` mode against the exact selected task. Require the canonical manifest and scratch GLB to match the visually approved hashes before creating the task-local leaf.

Expected marker:

`LOOT CONTAINER RECIPE PASS mode=publish-cleaned task=01a05dcb-fc3b-7418-b105-2170af354088`

- [ ] **Step 4: Run independent Blender validation**

Run:

`/usr/bin/python3 tools/meshy_blender_validate.py --project-root . --contract data/asset_generation/contracts/loot_container_derelict_v1.json --task-dir assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088 --glb assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088/cleaned.glb --report assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088/blender-validation.json`

Expected: validation command exit 0 and canonical report `status=PASS`, exact dimensions within tolerance, triangles ≤3,000, ≤2 materials, UV evidence present, and Blender re-import passed.

- [ ] **Step 5: Verify selected candidate evidence**

Run:

`/usr/bin/python3 tools/meshy_candidate_review.py verify --project-root . --task-dir assets/_staging/meshy/loot_container_derelict_v1/01a05dcb-fc3b-7418-b105-2170af354088`

Expected: candidate review passes at the Blender cleanup state expected by the pipeline; do not bind runtime/promotion readiness yet.

- [ ] **Step 6: Verify protected-path and repository scope**

Confirm no changes under `assets/imported`, `data/combat`, `data/props`, or `scenes/wrappers`. Confirm the protected untracked plan hash remains `3e399f581aaca12e05adc8e3c163e188eb5da3b3b5661e228d12036bb50febf9`.

---

### Task 4: Independent artifact review and handoff

**Files:**
- No repository modifications unless a concrete reviewed defect requires a RED-first correction.
- Review external master, preview evidence, task-local GLB, and validation report.

**Interfaces:**
- Consumes: Task 3 artifacts and all fresh verification logs.
- Produces: independent PASS/FAIL verdict with concrete High/Medium findings only.

- [ ] **Step 1: Dispatch independent specification/security review**

Reviewer verifies selected-task identity, raw preservation, one-master state derivation, no duplicate state meshes, correct dimensions/pivot/axis, triangle/material/UV budgets, exclusive publication, no collision/gameplay ownership drift, no protected-path changes, and no false promotion readiness.

- [ ] **Step 2: Dispatch independent visual/code-quality review**

Reviewer checks silhouette fidelity to Candidate 1, lid/body/handle/latch readability, clean hinge motion, useful open cavity, visible distinction between open and looted, locked-isometric readability, recipe simplicity, deterministic evidence, and absence of over-engineering.

- [ ] **Step 3: Correct only proven findings with RED tests**

For any High/Medium finding, add one failing focused regression, implement the smallest fix, rebuild previews, obtain renewed visual approval if appearance changes, rerun validation, and re-review.

- [ ] **Step 4: Final verification bundle**

Run focused recipe tests, adjacent Blender/candidate/governance tests, real Blender recipe probe, decoded-pixel determinism comparison, independent validator, candidate verification, `git diff --check`, status/protected-plan hash check, and current PR checks.

- [ ] **Step 5: Push only after all reviews pass**

Push the feature branch to the user’s fork and verify PR #543 head, mergeability, checks, and exact commit SHA. Do not merge or promote runtime assets without a separate explicit task.
