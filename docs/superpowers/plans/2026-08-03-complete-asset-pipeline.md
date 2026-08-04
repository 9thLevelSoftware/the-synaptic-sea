# Complete Asset Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close all 5 remaining Synaptic Sea structural asset pipeline gaps — export/promotion gate, remaining 7 modules, Blender add-on, artistic workflow, cloud backup — in phased order.

**Architecture:** Linear pipeline where each phase builds on the previous. Phase 1 (staged export/promotion) is the critical blocker. Phase 2 expands module coverage. Phase 3 adds the Blender UI. Phase 4 provides artist tooling. Phase 5 adds backup. Each phase is independently shippable and testable.

**Tech Stack:** Python 3.11 standard library, Blender 4.x Python API via `/opt/homebrew/bin/blender`, Godot 4.7.1 headless, existing JSON placement contracts, pytest, rsync/aws CLI/gsutil for backup.

**Spec:** `docs/superpowers/specs/2026-08-03-complete-asset-pipeline-design.md`

## Global Constraints

- All Python code targets 3.11+ (uses `match`, `zip(strict=True)`, `tomllib`).
- Blender scripts run via `/opt/homebrew/bin/blender --background --factory-startup`.
- Godot runs via `/opt/homebrew/bin/godot --headless`.
- No runtime GLB, wrapper, manifest, contract, `.import`, or `.godot` mutation without explicit promotion through the staged gate.
- Source metadata is deterministic: lexicographically sorted, compact UTF-8 JSON, one trailing newline, no timestamp.
- External source root: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/`.
- Project root: `/Volumes/Untitled/SynapticSeaAssets/worktrees/the-synaptic-sea-asset-metadata-retrofit`.
- All CLI tools require explicit `--project-root` and `--source-root` arguments; no hardcoded paths.

## Files Created or Modified

| Path | Phase | Responsibility |
|------|-------|---------------|
| `tools/export_structural_glb.py` | 1 | Blender-only: open .blend, export tagged collections to staging |
| `tools/promote_structural_sources.py` | 1 | CLI orchestrator: export → hash → validate → promote |
| `tools/validate_promoted_sources.py` | 1 | Standard-Python: Godot import + smoke test against staging |
| `tests/test_export_structural_glb.py` | 1 | Blender-backed tests for collection detection and export |
| `tests/test_promote_structural_sources.py` | 1 | Unit tests for hash comparison, skip logic, report format |
| `tools/structural_source_contract.py` | 2 | Expand `STRUCTURAL_SOURCE_MODULE_IDS` from 8 to 15 |
| `tests/test_structural_source_contract.py` | 2 | Update parameterized tests for 15 modules |
| `tools/blender_addons/structural_module_toolkit/__init__.py` | 3 | Add-on registration |
| `tools/blender_addons/structural_module_toolkit/panels.py` | 3 | UI panel |
| `tools/blender_addons/structural_module_toolkit/operators.py` | 3 | Button operators |
| `tools/blender_addons/structural_module_toolkit/export.py` | 3 | Staged GLB export with variant tagging |
| `tools/blender_addons/structural_module_toolkit/contract_creator.py` | 3 | Draft contract generation from family templates |
| `tools/blender_addons/structural_module_toolkit/preferences.py` | 3 | Add-on preferences |
| `tests/test_contract_creator.py` | 3 | Unit tests for draft contract generation |
| `meshes/source/materials/salvage_industrial.blend` | 4 | Material library |
| `docs/game/features/blender_artist_workflow.md` | 4 | Artist workflow guide |
| `tools/backup_structural_sources.py` | 5 | Backup CLI |
| `tests/test_backup_structural_sources.py` | 5 | Unit tests for dry-run, target validation |

---

## Phase 1: Staged Export/Promotion Gate

### Task 1: Create the Blender GLB Export Script

**Objective:** Create a Blender-only script that opens a `.blend` source file and exports tagged collections as GLB files to a staging directory.

**Files:**
- Create: `tools/export_structural_glb.py`
- Create: `tests/test_export_structural_glb.py`

**Interfaces:**

```text
/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/export_structural_glb.py -- \
  --blend-path <absolute-blend-path> \
  --staging-dir <absolute-staging-dir> \
  [--module <id>]
```

Output: one line per exported variant:
`STRUCTURAL_GLB_EXPORTED module=<id> variant=<intact|damaged|breached> glb=<path> bytes=<n>`

Collections are identified by name prefix `Export_` and custom property `variant_role`.

- [ ] **Step 1: Write failing CLI and export tests**

```python
# tests/test_export_structural_glb.py
from pathlib import Path
import subprocess
import sys

SCRIPT = Path("tools/export_structural_glb.py")

def test_export_cli_requires_blend_path_and_staging_dir() -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPT)], capture_output=True, text=True, check=False
    )
    assert result.returncode != 0
    assert "--blend-path" in result.stderr
    assert "--staging-dir" in result.stderr

def test_export_cli_rejects_nonexistent_blend_file(tmp_path: Path) -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--",
         "--blend-path", str(tmp_path / "missing.blend"),
         "--staging-dir", str(tmp_path / "staging")],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode != 0
```

- [ ] **Step 2: Run and verify red**

Run: `/opt/homebrew/bin/python3.11 -m pytest -q tests/test_export_structural_glb.py`
Expected: collection failure because `tools/export_structural_glb.py` does not exist.

- [ ] **Step 3: Implement the Blender export script**

```python
# tools/export_structural_glb.py (structure)
#!/usr/bin/env python3
"""Export tagged collections from a .blend source file to GLB staging."""

import argparse
import json
import os
import sys
from pathlib import Path

def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export structural source GLBs to staging")
    parser.add_argument("--blend-path", type=Path, required=True)
    parser.add_argument("--staging-dir", type=Path, required=True)
    parser.add_argument("--module", type=str, default=None)
    return parser.parse_args(argv)

if __name__ == "__main__":
    raw_argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    args = parse_args(raw_argv)

    if not args.blend_path.is_file():
        print(f"ERROR: blend file not found: {args.blend_path}", file=sys.stderr)
        sys.exit(1)

    import bpy
    bpy.ops.wm.open_mainfile(filepath=str(args.blend_path))

    # Find export collections
    export_collections = [
        col for col in bpy.data.collections
        if col.name.startswith("Export_")
    ]

    if not export_collections:
        # Fall back: export the Geometry collection as intact
        geometry = bpy.data.collections.get("Geometry")
        if geometry:
            export_collections = [geometry]

    os.makedirs(args.staging_dir, exist_ok=True)

    for col in export_collections:
        variant_role = col.get("variant_role", "intact")
        module_id = args.module or _detect_module_id(bpy)
        suffix = "" if variant_role == "intact" else f"_{variant_role}"
        glb_name = f"{module_id}{suffix}.glb"
        glb_path = args.staging_dir / glb_name

        # Select only objects in this collection
        bpy.ops.object.select_all(action="DESELECT")
        for obj in col.objects:
            obj.select_set(True)

        bpy.ops.export_scene.gltf(
            filepath=str(glb_path),
            export_format="GLB",
            export_apply=True,
            use_selection=True,
        )

        print(f"STRUCTURAL_GLB_EXPORTED module={module_id} variant={variant_role} "
              f"glb={glb_path} bytes={glb_path.stat().st_size}")

    bpy.ops.wm.quit_blender()
```

`_detect_module_id(bpy)` reads the `ModuleRoot_*` object name or `module_id` custom property from the scene.

- [ ] **Step 4: Run parser tests and Blender smoke**

Run parser tests:
```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_export_structural_glb.py
```

Run single-module export smoke:
```bash
TMP_STAGING=$(mktemp -d /private/tmp/synaptic-export.XXXXXX)
SOURCE_ROOT=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0
/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/export_structural_glb.py -- \
  --blend-path "$SOURCE_ROOT/floor_1x1/floor_1x1.blend" \
  --staging-dir "$TMP_STAGING" \
  --module floor_1x1
ls -la "$TMP_STAGING"
rm -rf "$TMP_STAGING"
```

Expected: `STRUCTURAL_GLB_EXPORTED module=floor_1x1 variant=intact glb=... bytes=...`

- [ ] **Step 5: Commit**

```bash
git add tools/export_structural_glb.py tests/test_export_structural_glb.py
git commit -m "feat: export structural source GLBs to staging"
```

---

### Task 2: Create the Promotion Orchestrator

**Objective:** Build the CLI that orchestrates export → hash → validate → promote for structural sources.

**Files:**
- Create: `tools/promote_structural_sources.py`
- Create: `tests/test_promote_structural_sources.py`

**Interfaces:**

```text
/opt/homebrew/bin/python3.11 tools/promote_structural_sources.py \
  --project-root <path> --source-root <path> --staging-root <path> \
  --module <id> | --all [--dry-run] [--force] [--backup]
```

- [ ] **Step 1: Write failing hash-comparison and skip-logic tests**

```python
# tests/test_promote_structural_sources.py
from pathlib import Path
import hashlib
import pytest
from tools.promote_structural_sources import (
    compute_glb_hash,
    should_skip_promotion,
)

def test_identical_hash_skips_promotion(tmp_path: Path) -> None:
    content = b"fake glb bytes"
    staged = tmp_path / "staged.glb"
    staged.write_bytes(content)
    runtime = tmp_path / "runtime.glb"
    runtime.write_bytes(content)
    assert should_skip_promotion(staged, runtime, force=False) is True

def test_different_hash_does_not_skip(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    staged.write_bytes(b"new bytes")
    runtime = tmp_path / "runtime.glb"
    runtime.write_bytes(b"old bytes")
    assert should_skip_promotion(staged, runtime, force=False) is False

def test_force_overrides_hash_skip(tmp_path: Path) -> None:
    content = b"same bytes"
    staged = tmp_path / "staged.glb"
    staged.write_bytes(content)
    runtime = tmp_path / "runtime.glb"
    runtime.write_bytes(content)
    assert should_skip_promotion(staged, runtime, force=True) is False

def test_missing_runtime_does_not_skip(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    staged.write_bytes(b"new bytes")
    runtime = tmp_path / "nonexistent.glb"
    assert should_skip_promotion(staged, runtime, force=False) is False
```

- [ ] **Step 2: Run and verify red**

Run: `/opt/homebrew/bin/python3.11 -m pytest -q tests/test_promote_structural_sources.py`
Expected: collection failure.

- [ ] **Step 3: Implement the promotion orchestrator**

The orchestrator:
1. Loads source spec via `load_source_spec()`
2. Calls `export_structural_glb.py` via Blender subprocess for each module
3. Computes SHA-256 of staged GLBs
4. Compares to runtime GLB hashes — skips if identical (unless `--force`)
5. Validates via Godot import smoke test (unless `--skip-godot`)
6. Copies staged GLBs to `assets/imported/structural/`
7. Prints `STRUCTURAL_PROMOTED module=<id> glbs=<n>` per module

- [ ] **Step 4: Run tests and commit**

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_promote_structural_sources.py
git add tools/promote_structural_sources.py tests/test_promote_structural_sources.py
git commit -m "feat: staged promotion orchestrator for structural sources"
```

---

### Task 3: Create the Godot Validation Gate

**Objective:** Build a standard-Python tool that validates staged GLBs by running Godot import and structural smoke tests against a temporary overlay.

**Files:**
- Create: `tools/validate_promoted_sources.py`

**Interfaces:**

```text
/opt/homebrew/bin/python3.11 tools/validate_promoted_sources.py \
  --project-root <path> --staging-root <path> \
  --module <id> | --all [--skip-godot]
```

- [ ] **Step 1: Write failing validation tests**

```python
# In tests/test_promote_structural_sources.py
from tools.validate_promoted_sources import validate_staged_module

def test_validation_finds_missing_glb(tmp_path: Path) -> None:
    errors = validate_staged_module(
        project_root=tmp_path,
        staging_root=tmp_path / "staging",
        module_id="floor_1x1",
        skip_godot=True,
    )
    assert any("missing staged GLB" in e for e in errors)
```

- [ ] **Step 2: Run and verify red**

Run: `/opt/homebrew/bin/python3.11 -m pytest -q tests/test_promote_structural_sources.py`
Expected: collection failure for `validate_promoted_sources`.

- [ ] **Step 3: Implement the validator**

The validator:
1. Checks staged GLBs exist and are nonempty
2. Copies staged GLBs to a temporary `assets/imported/` overlay (symlink or copy)
3. Runs `godot --headless --import` against the overlay
4. Runs `structural_variant_wrapper_smoke.gd` against the overlay
5. Parses output for `ERROR:`, `WARNING:`, `SCRIPT ERROR:`
6. Returns list of errors (empty = pass)

- [ ] **Step 4: Run tests and commit**

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_promote_structural_sources.py
git add tools/validate_promoted_sources.py tests/test_promote_structural_sources.py
git commit -m "feat: Godot validation gate for staged structural sources"
```

---

### Task 4: End-to-End Promotion Smoke Test

**Objective:** Run the full promotion pipeline for one module end-to-end, proving export → hash → validate → promote → verify works.

**Files:** No new files. Uses tools from Tasks 1-3.

- [ ] **Step 1: Run promotion for floor_1x1 with --dry-run**

```bash
ROOT=/Volumes/Untitled/SynapticSeaAssets/worktrees/the-synaptic-sea-asset-metadata-retrofit
SOURCE_ROOT=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0
STAGING=/private/tmp/synaptic-promote-smoke

/opt/homebrew/bin/python3.11 tools/promote_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" \
  --staging-root "$STAGING" --module floor_1x1 --dry-run
```

Expected: shows what would change, no files modified.

- [ ] **Step 2: Run promotion for floor_1x1 (real)**

```bash
/opt/homebrew/bin/python3.11 tools/promote_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" \
  --staging-root "$STAGING" --module floor_1x1
```

Expected: `STRUCTURAL_PROMOTED module=floor_1x1 glbs=1`

- [ ] **Step 3: Verify runtime GLB changed and Godot still works**

```bash
git -C "$ROOT" status --porcelain
# Should show modified GLB
/opt/homebrew/bin/godot --headless --path "$ROOT" --import 2>&1 | grep -ciE "(error|fail)"
```

Expected: 0 errors.

- [ ] **Step 4: Commit (no code changes, just verification)**

No commit needed — this is a verification task.

---

## Phase 2: Remaining 7 Catalog Modules

### Task 5: Expand Module Allowlist to 15

**Objective:** Expand `STRUCTURAL_SOURCE_MODULE_IDS` to include all 15 structural modules.

**Files:**
- Modify: `tools/structural_source_contract.py`
- Modify: `tests/test_structural_source_contract.py`

- [ ] **Step 1: Update the allowlist**

Add to `STRUCTURAL_SOURCE_MODULE_IDS`:
```python
"bulkhead_portal_2x1",
"ceiling_cap_1x1",
"doorway_frame_blocked_1x1",
"wall_end_cap",
"wall_inner_corner",
"wall_outer_corner",
"wall_t_junction",
```

- [ ] **Step 2: Update parameterized tests**

Update `test_all_eight_modules_load_from_live_contracts` to
`test_all_fifteen_modules_load_from_live_contracts` with all 15 module IDs.

- [ ] **Step 3: Run tests**

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_structural_source_contract.py
```

Expected: all pass (including 15-module parameterized test).

- [ ] **Step 4: Commit**

```bash
git add tools/structural_source_contract.py tests/test_structural_source_contract.py
git commit -m "feat: expand structural source recovery to all 15 modules"
```

---

### Task 6: Recover and Validate the 7 New Modules

**Objective:** Run the recovery pipeline for the 7 new modules and validate all 15.

**Files:** No new files. External outputs only.

- [ ] **Step 1: Recover the 7 new modules**

```bash
ROOT=/Volumes/Untitled/SynapticSeaAssets/worktrees/the-synaptic-sea-asset-metadata-retrofit
SOURCE_ROOT=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0

/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/recover_modules.py -- \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" \
  --module bulkhead_portal_2x1 \
  --module ceiling_cap_1x1 \
  --module doorway_frame_blocked_1x1 \
  --module wall_end_cap \
  --module wall_inner_corner \
  --module wall_outer_corner \
  --module wall_t_junction
```

Expected: 7 `STRUCTURAL_SOURCE_RECOVERED` lines.

- [ ] **Step 2: Validate all 15**

```bash
/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" --all
```

Expected: `STRUCTURAL_SOURCE_VALIDATION PASS modules=15`

- [ ] **Step 3: Verify no runtime changes**

```bash
git -C "$ROOT" diff --check
git -C "$ROOT" status --porcelain
```

Expected: clean.

- [ ] **Step 4: Update documentation**

Update `docs/game/features/blender_structural_source_pipeline.md` module list to 15.

```bash
git add docs/game/features/blender_structural_source_pipeline.md
git commit -m "docs: update structural source pipeline for 15 modules"
```

---

## Phase 3: Blender Add-on for One-Button Module Generation

### Task 7: Create the Blender Add-on Skeleton

**Objective:** Create the add-on package structure with registration, panel, and basic operators.

**Files:**
- Create: `tools/blender_addons/structural_module_toolkit/__init__.py`
- Create: `tools/blender_addons/structural_module_toolkit/panels.py`
- Create: `tools/blender_addons/structural_module_toolkit/operators.py`
- Create: `tools/blender_addons/structural_module_toolkit/preferences.py`

- [ ] **Step 1: Create add-on registration**

```python
# tools/blender_addons/structural_module_toolkit/__init__.py
bl_info = {
    "name": "Structural Module Toolkit",
    "author": "Synaptic Sea",
    "version": (1, 0, 0),
    "blender": (4, 0, 0),
    "location": "View3D > Sidebar > Structural",
    "description": "Create and edit structural modules with contract-derived helpers",
    "category": "Object",
}
```

- [ ] **Step 2: Create the UI panel**

Panel in N-panel sidebar with: Module ID, Family dropdown, Grid Size, buttons.

- [ ] **Step 3: Create operator stubs**

Load Contract, Import GLB, Generate Helpers, Export GLB, Validate — each as a Blender operator.

- [ ] **Step 4: Test add-on loads in Blender**

```bash
/opt/homebrew/bin/blender --background --factory-startup \
  --python-expr "
import bpy
bpy.ops.preferences.addon_enable(module='structural_module_toolkit')
print('ADDON LOAD PASS')
" 2>&1 | grep "ADDON LOAD"
```

- [ ] **Step 5: Commit**

```bash
git add tools/blender_addons/structural_module_toolkit/
git commit -m "feat: Blender structural module toolkit add-on skeleton"
```

---

### Task 8: Implement Contract Creator

**Objective:** Build the module that generates draft contracts from family templates.

**Files:**
- Create: `tools/blender_addons/structural_module_toolkit/contract_creator.py`
- Create: `tests/test_contract_creator.py`

- [ ] **Step 1: Write failing tests for contract generation**

```python
# tests/test_contract_creator.py
def test_floor_template_generates_edge_sockets() -> None:
    contract = create_draft_contract("test_floor", "floor", (2, 1))
    assert len(contract["sockets"]) == 4  # N, S, E, W edges
    assert contract["bounds"]["placement_origin"] == "cell-center-floor"

def test_wall_template_generates_three_sockets() -> None:
    contract = create_draft_contract("test_wall", "wall", (1, 0))
    assert len(contract["sockets"]) == 3  # N, S edges + face
```

- [ ] **Step 2: Run and verify red**

Run: `/opt/homebrew/bin/python3.11 -m pytest -q tests/test_contract_creator.py`

- [ ] **Step 3: Implement contract creator**

Family templates define socket patterns:
- `floor`: 4 edge sockets (N, S, E, W)
- `corridor_floor`: 4 edge sockets + wall constraints
- `wall`: 3 sockets (N, S edges + face)
- `portal`: 4 sockets (N, S edges + left/right jambs)
- `support`: 4 sockets (N, S, E, W edges)
- `ceiling`: 4 edge sockets (N, S, E, W)
- `vertical_transition`: 4 edge sockets

- [ ] **Step 4: Run tests and commit**

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_contract_creator.py
git add tools/blender_addons/structural_module_toolkit/contract_creator.py tests/test_contract_creator.py
git commit -m "feat: draft contract generation from family templates"
```

---

### Task 9: Implement Generate Helpers and Export Operators

**Objective:** Wire up the "Generate Helpers" and "Export GLB" buttons in the add-on.

**Files:**
- Modify: `tools/blender_addons/structural_module_toolkit/operators.py`
- Modify: `tools/blender_addons/structural_module_toolkit/export.py`

- [ ] **Step 1: Implement Generate Helpers operator**

Uses `load_source_spec()` (or draft contract) to create ModuleRoot, Geometry, AuthoringHelpers collections with socket empties and collision proxy. Same logic as `recover_modules.py` but as an in-process operator.

- [ ] **Step 2: Implement Export GLB operator**

Exports tagged `Export_*` collections to staging directory. Reuses logic from `export_structural_glb.py` but runs in-process.

- [ ] **Step 3: Test in Blender**

```bash
/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/blender_addons/structural_module_toolkit/test_smoke.py
```

- [ ] **Step 4: Commit**

```bash
git add tools/blender_addons/structural_module_toolkit/
git commit -m "feat: generate helpers and export operators for structural add-on"
```

---

## Phase 4: Artistic Iteration Workflow

### Task 10: Create Material Library and Artist Documentation

**Objective:** Provide artists with materials and documentation for working with structural sources.

**Files:**
- Create: `meshes/source/materials/salvage_industrial.blend`
- Create: `docs/game/features/blender_artist_workflow.md`

- [ ] **Step 1: Create material library .blend**

```bash
/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/create_material_library.py
```

Script creates 5 materials (PaintedAlloyGray, WarningStripe, ReactorGlow, Biomatter, Conduit) and saves to `meshes/source/materials/salvage_industrial.blend`.

- [ ] **Step 2: Write artist workflow documentation**

Cover: opening sources, material library, export process, validation, coordinate reference.

- [ ] **Step 3: Commit**

```bash
git add tools/create_material_library.py docs/game/features/blender_artist_workflow.md
git commit -m "feat: material library and artist workflow documentation"
```

---

## Phase 5: Cloud Backup Integration

### Task 11: Create Backup Script and Integrate with Promote Pipeline

**Objective:** Add cloud backup for external source files, integrated with the promote pipeline.

**Files:**
- Create: `tools/backup_structural_sources.py`
- Create: `tests/test_backup_structural_sources.py`
- Modify: `tools/promote_structural_sources.py` (add `--backup` flag)

- [ ] **Step 1: Write failing backup tests**

```python
# tests/test_backup_structural_sources.py
def test_dry_run_shows_files_without_uploading(tmp_path: Path) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "test.blend").write_bytes(b"fake")
    result = backup_sources(source, target="local:///tmp/backup", dry_run=True)
    assert result.would_sync == 1
    assert result.uploaded == 0
```

- [ ] **Step 2: Run and verify red**

Run: `/opt/homebrew/bin/python3.11 -m pytest -q tests/test_backup_structural_sources.py`

- [ ] **Step 3: Implement backup script**

Supports S3, GCS, and local paths. Uses `subprocess.run` for rsync/aws/gsutil.

- [ ] **Step 4: Integrate with promote pipeline**

Add `--backup` flag to `promote_structural_sources.py` that calls backup before promotion.

- [ ] **Step 5: Run tests and commit**

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_backup_structural_sources.py
git add tools/backup_structural_sources.py tools/promote_structural_sources.py tests/test_backup_structural_sources.py
git commit -m "feat: cloud backup integration for structural sources"
```

---

### Task 12: Final Integration Acceptance Gate

**Objective:** Run the complete pipeline end-to-end — all 15 modules from source through promotion with backup.

**Files:** No new files.

- [ ] **Step 1: Run full test suite**

```bash
/opt/homebrew/bin/python3.11 -m pytest -q
```

Expected: 150+ tests pass.

- [ ] **Step 2: Promote all 15 modules with dry-run**

```bash
/opt/homebrew/bin/python3.11 tools/promote_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" \
  --staging-root "/private/tmp/synaptic-final" --all --dry-run
```

- [ ] **Step 3: Verify all 15 external sources exist**

```bash
for module in floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 \
  wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2 \
  bulkhead_portal_2x1 ceiling_cap_1x1 doorway_frame_blocked_1x1 \
  wall_end_cap wall_inner_corner wall_outer_corner wall_t_junction; do
  test -s "$SOURCE_ROOT/$module/$module.blend" && echo "OK $module"
done
```

Expected: 15 OK lines.

- [ ] **Step 4: Verify repo is clean**

```bash
git -C "$ROOT" diff --check
git -C "$ROOT" status --porcelain
```

Expected: clean.

---

## Risks and Tradeoffs

- **Godot smoke tests require working Godot install.** `--skip-godot` flag available for CI.
- **Blender add-on targets 4.x.** Version check in `__init__.py` with clear error.
- **Cloud backup requires credentials.** Falls back to local rsync if not configured.
- **Draft contracts need human review.** Validation catches errors at promote time.
- **External files not in Git.** Cloud backup addresses this.
