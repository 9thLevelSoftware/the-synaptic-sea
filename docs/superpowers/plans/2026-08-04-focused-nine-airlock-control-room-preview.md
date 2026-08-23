# Focused-Nine Airlock/Control Room Preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a deterministic, staged-only Godot render of a coherent 3x3 focused-nine airlock/control room without promoting any asset.

**Architecture:** A new GDScript capture scene directly imports only focused-nine staged GLBs and composes the approved 3x3 layout. A separate Python runner validates the staged pressure-door/prop packages, runs the non-headless Godot capture in a private overlay, atomically publishes a preview and proof only after every gate succeeds, and verifies live runtime surfaces have not changed.

**Tech Stack:** Godot 4.7 GDScript, Python 3.11, staged GLB/JSON assets, pytest, Ruff.

## Global Constraints

- Source every visual from `assets/_staging/focused_nine`; never use `assets/imported` or live wrapper scenes.
- Do not change imported assets, generated prop bindings, kit data, or live structural wrappers.
- Use the established 4.0 m grid, locked orthographic isometric camera, and a 1600x900 non-headless capture.
- Reject staged dependencies with symlinked existing components before loading/copying.
- Treat `WARNING:`, `ERROR:`, and `SCRIPT ERROR:` in Godot output as capture failure even if a pass marker exists.
- Use same-directory temporary files plus replace for preview/proof publication; preserve old published artifacts on failure.
- All process launches have explicit timeout, fresh process group/session, bounded output, and group cleanup on timeout.
- State the established trusted-workspace limitation honestly: same-user concurrent rebind after initial checks is out of scope.

---

### Task 1: Staged-only room scene and deterministic Godot capture

**Files:**
- Create: `scenes/validation/focused_nine_airlock_control_room_harness.tscn`
- Create: `scripts/validation/focused_nine_airlock_control_room_capture.gd`
- Create: `tests/test_focused_nine_airlock_control_room_capture.py`

**Interfaces:**
- Consumes: staged GLBs under `res://assets/_staging/focused_nine/`.
- Produces: `FOCUSED_NINE_AIRLOCK_ROOM_CAPTURE PASS output=<path>` after atomically publishing `focused-nine-airlock-control-room.png`.
- CLI: `godot --path <project> --scene res://scenes/validation/focused_nine_airlock_control_room_harness.tscn -- --output-dir <approved-dir>`.

- [ ] **Step 1: Write failing static contract tests**

```python
def test_room_capture_is_staged_only_and_declares_every_required_asset() -> None:
    source = CAPTURE_SCRIPT.read_text(encoding="utf-8")
    assert 'const STAGED_ROOT := "res://assets/_staging/focused_nine/"' in source
    assert "assets/imported" not in source
    for path in (
        "structural/floor_1x1/floor_1x1.glb",
        "structural/wall_straight_1x1/wall_straight_1x1.glb",
        "structural/doorway_frame_open_1x1/doorway_frame_open_1x1.glb",
        "structural/pillar_support_1x1/pillar_support_1x1.glb",
        "structural/ramp_up_1x2/ramp_up_1x2.glb",
        "structural/ceiling_cap_1x1/ceiling_cap_1x1.glb",
        "structural/pressure_door_1x1/pressure_door_1x1.glb",
        "props/hull_breach_seal_point.glb",
        "props/fire_suppression_station.glb",
    ):
        assert path in source


def test_room_scene_has_one_locked_iso_camera_and_no_baseline_root() -> None:
    scene = HARNESS_SCENE.read_text(encoding="utf-8")
    assert 'name="RoomCamera" type="Camera3D"' in scene
    assert "projection = 1" in scene and "size = 18.0" in scene
    assert 'name="Baseline"' not in scene
    assert 'name="Room" type="Node3D"' in scene
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_airlock_control_room_capture.py`

Expected: FAIL because the scene, capture script, and test contract do not exist.

- [ ] **Step 3: Create the harness scene**

Create an isolated `Node3D` root containing `RoomCamera`, `RoomKeyLight`, `RoomFillLight`, `RoomEnvironment`, and `Room`. Use the already accepted orthographic orientation and a dark-navy environment; do not add external-resource references to live runtime assets.

```ini
[node name="RoomCamera" type="Camera3D" parent="."]
projection = 1
size = 18.0
current = true

[node name="Room" type="Node3D" parent="."]
```

- [ ] **Step 4: Implement deterministic layout and safe capture**

Implement constants for the nine staged resource paths and use `GLTFDocument.append_from_file` followed by `generate_scene`. The capture must reject a non-staged path, missing file, or symlinked existing component before loading. Populate these exact floor coordinates:

```gdscript
const FLOOR_LAYOUT: Array[Vector3] = [
    Vector3(-4.0, 0.0, -4.0), Vector3(0.0, 0.0, -4.0), Vector3(4.0, 0.0, -4.0),
    Vector3(-4.0, 0.0, 0.0),  Vector3(0.0, 0.0, 0.0),  Vector3(4.0, 0.0, 0.0),
    Vector3(-4.0, 0.0, 4.0),  Vector3(0.0, 0.0, 4.0),  Vector3(4.0, 0.0, 4.0),
]
```

Place the doorway/ramp at the south entrance, intact pressure door at north center, wall perimeter with front/roof cutaway, pillars at rear corners, ceiling caps across the rear row, fire station beside the entry, and breach seal point on the east wall. Wait ten process frames, capture exactly 1600x900, and atomically publish a first-frame leaf plus stable `focused-nine-airlock-control-room.png` leaf using hidden temporary siblings and `rename_absolute`.

- [ ] **Step 5: Add behavioral GDScript probe tests**

Adapt the existing comparison-capture probe pattern. The probe must assert valid parser behavior, reject external/traversal/symlink output paths, reject symlinked capture leaves without writing through them, and confirm both stable image leaves have equal non-empty bytes after normal publication.

- [ ] **Step 6: Run tests and Godot parse smoke**

Run:

```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_airlock_control_room_capture.py
godot --headless --path . --editor --quit
```

Expected: tests PASS and Godot exits 0 with no parser errors.

- [ ] **Step 7: Commit**

```bash
git add scenes/validation/focused_nine_airlock_control_room_harness.tscn \
  scripts/validation/focused_nine_airlock_control_room_capture.gd \
  tests/test_focused_nine_airlock_control_room_capture.py
git commit -m "feat: add staged airlock room capture"
```

### Task 2: No-promotion room-preview runner and validation gates

**Files:**
- Create: `tools/focused_nine_airlock_control_room_preview.py`
- Create: `tests/test_focused_nine_airlock_control_room_preview.py`

**Interfaces:**
- Consumes: `--project-root PATH --staging-root PATH --preview-dir PATH --proof PATH [--dry-run]`.
- Produces: `FOCUSED_NINE_AIRLOCK_ROOM_PREVIEW PASS path=<logical-path>` only after staged package validation, capture validation, atomic preview/proof publication, and runtime no-diff.
- Uses: `snapshot_runtime_surfaces()` and bounded-process helpers from `tools/focused_nine_batch.py`; `tools/validate_prop_visual_bindings.py`; staged pressure-door validation contract.

- [ ] **Step 1: Write failing runner tests**

```python
def test_parse_args_rejects_runtime_or_symlinked_staging_roots(tmp_path: Path) -> None:
    project = _project(tmp_path)
    runtime_root = project / "assets/imported"
    with pytest.raises(SystemExit):
        preview.parse_args([
            "--project-root", str(project), "--staging-root", str(runtime_root),
            "--preview-dir", str(project / "artifacts/validation-previews/focused-nine"),
            "--proof", str(project / "docs/superpowers/proofs/focused-nine-airlock-control-room.md"),
        ])


def test_capture_diagnostics_block_publication_and_preserve_existing_preview(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    preview_path = _existing_preview(tmp_path, b"previous")
    monkeypatch.setattr(preview, "_run_room_capture", lambda *_: (False, "ERROR: injected", "ERROR: injected"))
    result = preview.run(_args(tmp_path))
    assert result.exit_code == 1
    assert preview_path.read_bytes() == b"previous"
```

- [ ] **Step 2: Run failing tests**

Run: `PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q tests/test_focused_nine_airlock_control_room_preview.py`

Expected: FAIL because the runner module does not exist.

- [ ] **Step 3: Implement path and dependency gates**

Implement `parse_args(argv) -> argparse.Namespace`, `_reject_static_symlink_components(path, label)`, and `validate_inputs(args)`. Require staging root to be inside `project_root/assets/_staging/focused_nine`, reject runtime aliases and symlink components, and require exactly the nine staged GLBs, both prop sidecars, and pressure-door package metadata. Use the existing staged prop validator and staged pressure-door validator; do not duplicate or weaken their contracts.

- [ ] **Step 4: Implement private-overlay capture and transactional publication**

Implement `run(args) -> RunResult`. Snapshot runtime surfaces immediately before validation and after every capture attempt. Build an isolated overlay containing staged inputs only, invoke the room scene with `--path <overlay> --scene ... -- --output-dir artifacts/validation-previews/focused-nine`, and enforce a 120-second timeout through a process group. Require the exact GDScript marker and reject diagnostics.

On success, validate a non-empty PNG with `sips -g pixelWidth -g pixelHeight` or Pillow-compatible Python inspection and require `(1600, 900)`. Write preview and proof to temporary siblings, verify bytes, then replace both; on failure restore prior preview/proof bytes or absence exactly.

- [ ] **Step 5: Add runner regression coverage**

Add tests for: missing staged GLB; missing pressure-door package member; sidecar validation failure; symlinked `props` or structural child; timeout cleanup; pass marker plus diagnostic rejection; wrong PNG dimensions; runtime snapshot mismatch; dry run makes no output; and failure after temporary preview creation restores old preview/proof.

- [ ] **Step 6: Run focused tests and lint**

Run:

```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q \
  tests/test_focused_nine_airlock_control_room_capture.py \
  tests/test_focused_nine_airlock_control_room_preview.py
ruff check tools/focused_nine_airlock_control_room_preview.py \
  tests/test_focused_nine_airlock_control_room_preview.py
git diff --check
```

Expected: PASS, clean Ruff output, and no whitespace errors.

- [ ] **Step 7: Commit**

```bash
git add tools/focused_nine_airlock_control_room_preview.py \
  tests/test_focused_nine_airlock_control_room_preview.py
git commit -m "feat: validate staged airlock room preview"
```

### Task 3: Real room capture, evidence, and final no-promotion gate

**Files:**
- Create: `docs/superpowers/proofs/focused-nine-airlock-control-room.md`
- Modify: `tests/test_focused_nine_airlock_control_room_preview.py`
- Generated: `artifacts/validation-previews/focused-nine/focused-nine-airlock-control-room.png`

**Interfaces:**
- Consumes: the Task 1 scene/capture script and Task 2 runner.
- Produces: committed preview and proof with `FOCUSED_NINE_AIRLOCK_ROOM_PREVIEW PASS` evidence.

- [ ] **Step 1: Add real-run acceptance test**

```python
def test_real_room_preview_has_room_composition_contract() -> None:
    image = PROJECT_ROOT / "artifacts/validation-previews/focused-nine/focused-nine-airlock-control-room.png"
    proof = PROJECT_ROOT / "docs/superpowers/proofs/focused-nine-airlock-control-room.md"
    assert image.is_file() and image.stat().st_size > 0
    assert proof.is_file()
    text = proof.read_text(encoding="utf-8")
    assert "No runtime promotion occurred." in text
    assert "3x3" in text
    assert "FOCUSED_NINE_AIRLOCK_ROOM_PREVIEW PASS" in text
```

- [ ] **Step 2: Run the complete focused test set before real capture**

Run:

```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 -m pytest -q \
  tests/test_focused_nine_contract.py \
  tests/test_focused_nine_blender_recipes.py \
  tests/test_focused_nine_evidence.py \
  tests/test_focused_nine_staged_props.py \
  tests/test_focused_nine_staged_structural.py \
  tests/test_focused_nine_comparison_capture.py \
  tests/test_focused_nine_batch.py \
  tests/test_focused_nine_airlock_control_room_capture.py \
  tests/test_focused_nine_airlock_control_room_preview.py
```

Expected: all focused tests pass before publication.

- [ ] **Step 3: Execute real staged-only room preview**

Run:

```bash
PYTHONPATH=. /opt/homebrew/bin/python3.11 tools/focused_nine_airlock_control_room_preview.py \
  --project-root . \
  --staging-root assets/_staging/focused_nine \
  --preview-dir artifacts/validation-previews/focused-nine \
  --proof docs/superpowers/proofs/focused-nine-airlock-control-room.md
```

Expected: `FOCUSED_NINE_AIRLOCK_ROOM_PREVIEW PASS` and no Godot diagnostic marker.

- [ ] **Step 4: Independently verify artifact and no-promotion boundary**

Run:

```bash
sips -g pixelWidth -g pixelHeight artifacts/validation-previews/focused-nine/focused-nine-airlock-control-room.png
PYTHONPATH=. /opt/homebrew/bin/python3.11 tools/validate_prop_visual_bindings.py --project-root . --check-index
git diff --exit-code -- assets/imported data/props/visual_bindings.generated.json data/kits/ship_structural_v0 scenes/wrappers/structural/ship_structural_v0
```

Expected: exactly 1600x900; prop index PASS; no protected runtime diff.

- [ ] **Step 5: Review evidence text**

Require the proof to state all of: staged-only source root, 3x3 composition, capture path/dimensions, pressure-door and prop validator results, no runtime promotion, and exact runner pass marker. It must not include absolute external source paths or secret values.

- [ ] **Step 6: Commit generated review evidence**

```bash
git add artifacts/validation-previews/focused-nine/focused-nine-airlock-control-room.png \
  docs/superpowers/proofs/focused-nine-airlock-control-room.md \
  tests/test_focused_nine_airlock_control_room_preview.py
git commit -m "feat: stage focused airlock room preview"
```

## Plan Self-Review

- **Spec coverage:** Task 1 implements the 3x3 composition, camera, staged-only scene, lighting, output contract, and atomic image capture. Task 2 implements staged dependency checks, pressure-door/prop validation, diagnostics rejection, private capture, transactional publication, and no-diff enforcement. Task 3 runs the real artifact gate and records proof.
- **Completeness scan:** No unfinished markers, undefined implementation steps, or ambiguous asset source locations remain.
- **Type consistency:** Task 1 emits the marker consumed by Task 2; Task 2 emits the marker and files verified by Task 3. Paths and output filename are consistent across all tasks.
