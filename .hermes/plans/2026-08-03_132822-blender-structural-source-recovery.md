# Blender Structural Source Recovery and Connector Authoring Implementation Plan

> **For Hermes:** Use `subagent-driven-development` to implement this plan task-by-task. Every implementation task requires a fresh implementer, then spec-compliance review, then code-quality review.

**Goal:** Build a deterministic Blender-first, source-only recovery pipeline for the eight integrity-variant `ship_structural_v0` modules so that editable `.blend` files contain contract-derived connector sockets, collision-proxy authoring data, and portable provenance without modifying any currently validated GLB, wrapper, manifest, contract, or Godot cache.

**Architecture:** The existing Godot placement contracts remain the sole authority for module identity, grid footprint, bounds, sockets, and collision intent. A pure-Python contract layer supplies both Blender and test code; Blender imports the existing intact GLB only as editable visual geometry, adds source-only helpers, writes `.blend` and canonical `.source.json` records to the external asset volume, and never exports a GLB. A separate inspector validates Blender output against the same contract and emits deterministic JSON reports.

**Tech Stack:** Python 3.11 standard library, Blender 4.x Python API via `/opt/homebrew/bin/blender`, Godot 4.7.1, existing JSON placement contracts, and the repository's `pytest` test runner.

## Global Constraints

- Recover exactly these eight modules in this phase: `floor_1x1`, `floor_2x1`, `corridor_floor_1x1`, `corridor_floor_1x2`, `wall_straight_1x1`, `doorway_frame_open_1x1`, `pillar_support_1x1`, and `ramp_up_1x2`.
- The source destination is external and is not Git content: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/`.
- The authoritative contract for a module is `data/placement/contracts/structural/ship_structural_v0/<module_id>_contract.json`; do not consume the stale `source_workspace_root` paths in `data/kits/ship_structural_v0.json`.
- The runtime input GLB is read-only: `assets/imported/structural/ship_structural_v0/<module_id>/<module_id>.glb`.
- **No GLB export, re-export, copy, replacement, hash change, wrapper edit, contract edit, manifest edit, `.import` artifact, or `.godot` mutation is permitted.** This plan restores source authoring only; runtime-asset promotion requires a separately approved future plan.
- Blender uses Z-up. Placement contracts use Y-up. Convert every point exactly as `(x, y, z) contract -> (x, z, y) Blender`.
- The root placement policy is `cell-center-floor`; source root location and rotation must be identity.
- Prop `.sidecar.json` semantics do not apply to structural sources. Use the unambiguous external source record name `<module_id>.source.json`.
- Source metadata must be deterministic: lexicographically sorted, compact UTF-8 JSON with exactly one trailing newline and no timestamp field.
- The external output root is a required explicit CLI argument in automated tests. The production command may pass `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0`, but never hardcode the old `/Users/christopherwilloughby/off-the-rails-ai-infra/...` root.
- Use TDD: every pure-Python behavior must have a targeted test that was observed failing before implementation. Blender integration is validated separately after unit tests are green.

---

## Source Object Contract

Every recovered `<module_id>.blend` must contain this layout. It is source-authoring metadata only; it must not be inferred as a Godot wrapper replacement.

```text
ModuleRoot_<module_id>                Empty, identity transform, contract custom properties
├── Geometry                           Collection containing imported visual meshes
└── AuthoringHelpers                  Collection containing source-only helpers
    ├── Origin                         Empty at (0, 0, 0)
    ├── Anchor_FloorCenter             Empty at (0, 0, 0)
    ├── Anchor_SOCK_<socket_id>        One Empty per contract socket
    └── CollisionProxy                 Non-rendering wireframe mesh from contract bounds
```

Required custom properties:

```python
root["module_id"] = spec.module_id
root["kit_id"] = "ship_structural_v0"
root["module_family"] = spec.module_family
root["grid_step_m"] = spec.grid_step_m
root["footprint_cells"] = json.dumps(list(spec.footprint_cells))
root["placement_origin"] = spec.placement_origin
root["contract_sha256"] = spec.contract_sha256
root["source_glb_sha256"] = spec.source_glb_sha256

socket["socket_id"] = record.socket_id
socket["kind"] = record.kind
socket["compatible_kinds"] = json.dumps(list(record.compatible_kinds))
socket["position_contract_y_up"] = json.dumps(list(record.position_y_up))
socket["position_blender_z_up"] = json.dumps(list(record.position_z_up))
socket["orientation_source"] = "socket-id-cardinal-convention"
collision["proxy_shape"] = spec.collision_proxy_shape
collision["nav_blocker"] = spec.nav_blocker
```

`Anchor_SOCK_*` rotations are a Blender authoring aid only: map `north/up -> +Y`, `south/down -> -Y`, `east/right -> +X`, `west/left -> -X`; set a `+Z` local up axis. The JSON contract does not currently own socket orientation, so connector compatibility continues to use the existing socket ID, kind, position, and `compatible_kinds` fields.

## Files Created or Modified

| Path | Responsibility |
|---|---|
| `tools/structural_source_contract.py` | Pure, Blender-independent loading, normalization, validation, canonical source-record serialization, and source-root containment. |
| `tools/recover_modules.py` | Refactor existing unsafe exporter into a Blender-only, source-recovery CLI. It imports existing GLBs and writes `.blend`/`.source.json` only. |
| `tools/inspect_structural_sources.py` | Blender-only inspector that reads `.blend` files and prints one deterministic JSON report. |
| `tools/validate_structural_sources.py` | Standard-Python CLI that invokes the inspector, compares reports to authoritative contracts, and reports deterministic errors. |
| `tests/test_structural_source_contract.py` | Unit tests for contract parsing, coordinate conversion, containment, and canonical source records. |
| `tests/test_validate_structural_sources.py` | Unit tests for inspector-report validation and command construction; no Blender mock is allowed in production code. |
| `tests/fixtures/structural_source_contracts/` | Small JSON-only contract fixtures for malformed/mismatched source tests. |
| `docs/game/features/blender_structural_source_pipeline.md` | Source layout, operator workflow, ownership boundary, and recovery status documentation. |
| `docs/game/06_validation_plan.md` | Reproducible Blender source recovery and verification commands; preserve the existing Godot state-runner rules. |
| `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.blend` | Eight generated external editable Blender source files; never added to Git. |
| `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.source.json` | Eight canonical external provenance and connector records; never added to Git. |

## Task 1: Establish the Pure Structural-Source Contract API

**Objective:** Create one standard-Python module that safely loads the eight authoritative structural contracts and exposes the exact source-recovery values required by Blender and validation.

**Files:**
- Create: `tools/structural_source_contract.py`
- Create: `tests/test_structural_source_contract.py`
- Create: `tests/fixtures/structural_source_contracts/floor_1x1_contract.json`
- Create: `tests/fixtures/structural_source_contracts/mismatched_module_contract.json`

**Public interface signatures:**

```python
# tools/structural_source_contract.py
from dataclasses import dataclass
from pathlib import Path
from typing import Any

STRUCTURAL_SOURCE_MODULE_IDS: tuple[str, ...] = (
    "floor_1x1", "floor_2x1", "corridor_floor_1x1", "corridor_floor_1x2",
    "wall_straight_1x1", "doorway_frame_open_1x1", "pillar_support_1x1",
    "ramp_up_1x2",
)

@dataclass(frozen=True)
class SocketSpec:
    socket_id: str
    kind: str
    compatible_kinds: tuple[str, ...]
    position_y_up: tuple[float, float, float]

    @property
    def anchor_name(self) -> str: ...

    @property
    def position_z_up(self) -> tuple[float, float, float]: ...

@dataclass(frozen=True)
class StructuralSourceSpec:
    module_id: str
    kit_id: str
    module_family: str
    grid_step_m: float
    footprint_cells: tuple[int, int]
    placement_origin: str
    bounds_min_y_up: tuple[float, float, float]
    bounds_max_y_up: tuple[float, float, float]
    collision_proxy_shape: str
    nav_blocker: bool
    sockets: tuple[SocketSpec, ...]
    contract_path: Path
    contract_sha256: str
    source_glb_path: Path
    source_glb_sha256: str

def y_up_to_z_up(value: tuple[float, float, float]) -> tuple[float, float, float]: ...
def load_source_spec(project_root: Path, module_id: str) -> StructuralSourceSpec: ...
def source_output_paths(source_root: Path, module_id: str) -> tuple[Path, Path]: ...
def build_source_record(spec: StructuralSourceSpec, blend_path: Path) -> dict[str, Any]: ...
def canonical_json(document: dict[str, Any]) -> bytes: ...
```

- [ ] **Step 1: Write failing conversion and allowlist tests**

```python
# tests/test_structural_source_contract.py
from pathlib import Path
import json
import pytest
from tools.structural_source_contract import (
    STRUCTURAL_SOURCE_MODULE_IDS,
    build_source_record,
    canonical_json,
    load_source_spec,
    source_output_paths,
    y_up_to_z_up,
)

PROJECT_ROOT = Path(__file__).resolve().parents[1]

def test_contract_coordinates_convert_y_up_to_blender_z_up() -> None:
    assert y_up_to_z_up((2.0, 3.0, -4.0)) == (2.0, -4.0, 3.0)

def test_floor_contract_exposes_exact_socket_anchor_names() -> None:
    spec = load_source_spec(PROJECT_ROOT, "floor_1x1")
    assert [socket.anchor_name for socket in spec.sockets] == [
        "Anchor_SOCK_floor_edge_north_01",
        "Anchor_SOCK_floor_edge_south_01",
        "Anchor_SOCK_floor_edge_east_01",
        "Anchor_SOCK_floor_edge_west_01",
    ]

def test_unknown_or_path_traversal_module_is_rejected() -> None:
    with pytest.raises(ValueError, match="unsupported structural source module"):
        load_source_spec(PROJECT_ROOT, "../../floor_1x1")

def test_source_recovery_allowlist_is_exactly_the_eight_integrity_families() -> None:
    assert STRUCTURAL_SOURCE_MODULE_IDS == (
        "floor_1x1", "floor_2x1", "corridor_floor_1x1", "corridor_floor_1x2",
        "wall_straight_1x1", "doorway_frame_open_1x1", "pillar_support_1x1",
        "ramp_up_1x2",
    )
```

- [ ] **Step 2: Run the tests and verify red**

Run:

```bash
cd /Volumes/Untitled/SynapticSeaAssets/worktrees/the-synaptic-sea-asset-metadata-retrofit
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_structural_source_contract.py
```

Expected: collection failure because `tools.structural_source_contract` does not exist.

- [ ] **Step 3: Implement strict contract loading**

```python
# tools/structural_source_contract.py (core validation)
def y_up_to_z_up(value: tuple[float, float, float]) -> tuple[float, float, float]:
    return (float(value[0]), float(value[2]), float(value[1]))

def load_source_spec(project_root: Path, module_id: str) -> StructuralSourceSpec:
    if module_id not in STRUCTURAL_SOURCE_MODULE_IDS:
        raise ValueError(f"unsupported structural source module: {module_id!r}")
    contract_path = (
        project_root / "data/placement/contracts/structural/ship_structural_v0"
        / f"{module_id}_contract.json"
    )
    source_glb_path = (
        project_root / "assets/imported/structural/ship_structural_v0"
        / module_id / f"{module_id}.glb"
    )
    document = json.loads(contract_path.read_text(encoding="utf-8"))
    if document.get("document_kind") != "modular_asset_spec":
        raise ValueError(f"invalid structural contract kind: {module_id}")
    if document.get("module_id") != module_id:
        raise ValueError(f"contract module_id mismatch: {module_id}")
    if not source_glb_path.is_file():
        raise ValueError(f"missing source GLB: {module_id}")
    # Require exactly three finite coordinates, two positive integer footprint cells,
    # `cell-center-floor`, `box`, and nonempty socket id/kind/compatible-kinds fields.
    # Return immutable tuples and SHA-256 digests of the exact input files.
```

Implement `source_output_paths()` with `Path.resolve(strict=False)` containment: the resolved `<source_root>/<module_id>` must remain under `source_root.resolve()`, and the module name must still be in `STRUCTURAL_SOURCE_MODULE_IDS`.

- [ ] **Step 4: Add deterministic source-record tests**

```python
def test_source_record_is_canonical_and_has_no_clock_field(tmp_path: Path) -> None:
    spec = load_source_spec(PROJECT_ROOT, "floor_1x1")
    blend_path, _ = source_output_paths(tmp_path, spec.module_id)
    raw = canonical_json(build_source_record(spec, blend_path))
    assert raw.endswith(b"\n")
    assert raw == canonical_json(json.loads(raw))
    document = json.loads(raw)
    assert document["document_kind"] == "structural_blender_source"
    assert "generated_at" not in document
    assert document["sockets"][0]["anchor_name"] == "Anchor_SOCK_floor_edge_north_01"
```

- [ ] **Step 5: Implement canonical source records and run green**

Source-record shape:

```python
{
    "document_kind": "structural_blender_source",
    "schema_version": "1.0.0",
    "module_id": spec.module_id,
    "kit_id": spec.kit_id,
    "contract": {
        "path": spec.contract_path.relative_to(project_root).as_posix(),
        "sha256": spec.contract_sha256,
    },
    "source_glb": {
        "path": spec.source_glb_path.relative_to(project_root).as_posix(),
        "sha256": spec.source_glb_sha256,
    },
    "blend_path": str(blend_path),
    "coordinate_conversion": "contract[x,y,z]->blender[x,z,y]",
    "placement_origin": spec.placement_origin,
    "sockets": [
        {
            "id": socket.socket_id,
            "anchor_name": socket.anchor_name,
            "kind": socket.kind,
            "compatible_kinds": list(socket.compatible_kinds),
            "position_contract_y_up": list(socket.position_y_up),
            "position_blender_z_up": list(socket.position_z_up),
            "orientation_source": "socket-id-cardinal-convention",
        }
        for socket in spec.sockets
    ],
}
```

Run:

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_structural_source_contract.py
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add tools/structural_source_contract.py tests/test_structural_source_contract.py tests/fixtures/structural_source_contracts
git commit -m "feat: define structural Blender source contract"
```

## Task 2: Make the Existing Blender Recovery Script Source-Only and Safe

**Objective:** Refactor `tools/recover_modules.py` into a deterministic Blender CLI that imports existing visual geometry and writes editable `.blend`/`.source.json` files, without exporting or changing any GLB.

**Files:**
- Modify: `tools/recover_modules.py`
- Modify: `tests/test_structural_source_contract.py`
- Create: `tests/test_recover_modules_cli.py`

**Interfaces:**

```text
/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/recover_modules.py -- \
  --project-root <absolute-project-root> \
  --source-root <absolute-external-or-temp-source-root> \
  --module floor_1x1 [--module ...] [--overwrite] [--dry-run]
```

- `--project-root` and `--source-root` are required.
- One or more `--module` flags are required; `--all` selects the exact eight-module allowlist and may not be combined with `--module`.
- Existing `.blend` or `.source.json` outputs cause a failure unless `--overwrite` is supplied.
- `--dry-run` prints planned source paths and writes nothing.
- Successful recovery prints one line per module: `STRUCTURAL_SOURCE_RECOVERED module=<id> sockets=<n> blend=<path> source_record=<path>`.

- [ ] **Step 1: Write failing CLI and source-layout tests**

```python
# tests/test_recover_modules_cli.py
from pathlib import Path
import subprocess
import sys

SCRIPT = Path("tools/recover_modules.py")
PROJECT_ROOT = Path(__file__).resolve().parents[1]

def test_recovery_cli_requires_explicit_project_and_source_roots() -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPT)], capture_output=True, text=True, check=False
    )
    assert result.returncode != 0
    assert "--project-root" in result.stderr
    assert "--source-root" in result.stderr

def test_recovery_cli_rejects_unapproved_module_before_blender_import(tmp_path: Path) -> None:
    result = subprocess.run(
        [
            sys.executable, str(SCRIPT), "--",
            "--project-root", str(PROJECT_ROOT),
            "--source-root", str(tmp_path),
            "--module", "wall_t_junction",
        ],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode != 0
    assert "unsupported structural source module" in result.stderr
```

The script must keep Blender imports behind `if __name__ == "__main__"` or a `bpy`-availability branch so parser and argument tests run under Python 3.11 without Blender.

- [ ] **Step 2: Run and verify red**

Run:

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_recover_modules_cli.py
```

Expected: tests fail because the current script imports `bpy` at module import and has no required CLI parser.

- [ ] **Step 3: Replace obsolete hardcoded/export behavior**

Delete these existing behaviors from `tools/recover_modules.py`:

```python
ASSET_ROOT = "/Volumes/Untitled/SynapticSeaAssets"
REPO = os.path.join(ASSET_ROOT, "projects", "the-synaptic-sea")
PROCESSED_ROOT = os.path.join(ASSET_ROOT, "meshes", "processed", "ship_structural_v0")
export_visual_glb(glb_path, visual_objects)
"generated_at_utc": datetime.now(timezone.utc).isoformat(),
"glb": glb_path,
"glb_bytes": os.path.getsize(glb_path),
"validation_status": "authored_and_exported",
```

Replace with this entrypoint boundary:

```python
def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Recover source-only structural Blender files")
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--all", action="store_true")
    group.add_argument("--module", action="append", default=[])
    parser.add_argument("--overwrite", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)

if __name__ == "__main__":
    raw_argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    args = parse_args(raw_argv)
    if args.dry_run:
        print_recovery_plan(args)
    else:
        import bpy
        recover_sources(bpy, args)
```

`load_source_spec(args.project_root, module_id)` replaces the old `meta.json` dependency. Do not use `data/kits/ship_structural_v0.json["source_workspace_root"]`.

- [ ] **Step 4: Implement the Blender source assembly**

For each approved module:

```python
def recover_one(bpy: Any, spec: StructuralSourceSpec, source_root: Path, overwrite: bool) -> dict[str, Any]:
    blend_path, record_path = source_output_paths(source_root, spec.module_id)
    if not overwrite and (blend_path.exists() or record_path.exists()):
        raise FileExistsError(f"source output already exists: {spec.module_id}")

    clear_factory_scene(bpy)
    root = add_empty(bpy, f"ModuleRoot_{spec.module_id}")
    root.location = (0.0, 0.0, 0.0)
    root.rotation_euler = (0.0, 0.0, 0.0)
    set_root_properties(root, spec)

    geometry = new_collection(bpy, "Geometry")
    helpers = new_collection(bpy, "AuthoringHelpers")
    import_glb_into_collection(bpy, spec.source_glb_path, geometry, root)
    add_empty(bpy, "Origin", helpers, root, (0.0, 0.0, 0.0))
    add_empty(bpy, "Anchor_FloorCenter", helpers, root, (0.0, 0.0, 0.0))
    for socket in spec.sockets:
        add_socket_empty(bpy, socket, helpers, root)
    add_contract_collision_proxy(bpy, spec, helpers, root)

    atomic_save_blend(bpy, blend_path)
    atomic_write(record_path, canonical_json(build_source_record(spec, blend_path)))
    return {"module_id": spec.module_id, "blend": str(blend_path), "source_record": str(record_path)}
```

Rules for `import_glb_into_collection()`:
- Call `bpy.ops.import_scene.gltf(filepath=str(spec.source_glb_path))`.
- Re-link every imported object to `Geometry`, parent it to `ModuleRoot_<id>`, and do not apply, bake, decimate, rename, or export its mesh data.
- Imported visual geometry may have transforms that came from the GLB. Preserve them; only the source root and helpers must be identity/contract-derived.
- `CollisionProxy` is a helper-only wireframe cube using the exact converted contract bounds. Set `hide_render=True`; it is not an exported collision mesh.

- [ ] **Step 5: Run parser tests and a single-module Blender recovery smoke**

Run parser tests:

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_recover_modules_cli.py tests/test_structural_source_contract.py
```

Expected: all pass.

Run source recovery only into a disposable external-safe test directory:

```bash
TMP_SOURCE=$(mktemp -d /private/tmp/synaptic-blender-source.XXXXXX)
/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/recover_modules.py -- \
  --project-root "$PWD" \
  --source-root "$TMP_SOURCE" \
  --module floor_1x1
```

Expected: `STRUCTURAL_SOURCE_RECOVERED module=floor_1x1 sockets=4` and exactly two output files under `$TMP_SOURCE/floor_1x1/`: `floor_1x1.blend` and `floor_1x1.source.json`. Confirm `git status --porcelain` remains empty, then remove only `$TMP_SOURCE`.

- [ ] **Step 6: Commit**

```bash
git add tools/recover_modules.py tests/test_recover_modules_cli.py tests/test_structural_source_contract.py
git commit -m "feat: recover structural Blender sources safely"
```

## Task 3: Add an Independent Blender Source Inspector

**Objective:** Validate recovered `.blend` files against authoritative contracts without loading Godot or writing into the project repository.

**Files:**
- Create: `tools/inspect_structural_sources.py`
- Create: `tools/validate_structural_sources.py`
- Create: `tests/test_validate_structural_sources.py`

**Interfaces:**

```text
/opt/homebrew/bin/blender --background --factory-startup <blend-path> \
  --python tools/inspect_structural_sources.py -- \
  --project-root <absolute-project-root> --module <id>

/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root <absolute-project-root> \
  --source-root <absolute-source-root> [--module <id> | --all]
```

The inspector prints exactly one line beginning `STRUCTURAL_SOURCE_REPORT ` followed by compact, sorted JSON. The standard-Python validator parses that line, compares it to `StructuralSourceSpec`, emits sorted errors to stderr, and returns zero only when every selected source is compliant.

- [ ] **Step 1: Write failing report-validation tests**

```python
# tests/test_validate_structural_sources.py
from pathlib import Path
import pytest
from tools.structural_source_contract import load_source_spec
from tools.validate_structural_sources import validate_report

PROJECT_ROOT = Path(__file__).resolve().parents[1]

@pytest.fixture
def spec():
    return load_source_spec(PROJECT_ROOT, "floor_1x1")

BASE_REPORT = {
    "module_id": "floor_1x1",
    "root_name": "ModuleRoot_floor_1x1",
    "root_identity": True,
    "helper_names": [
        "Anchor_FloorCenter",
        "Anchor_SOCK_floor_edge_east_01",
        "Anchor_SOCK_floor_edge_north_01",
        "Anchor_SOCK_floor_edge_south_01",
        "Anchor_SOCK_floor_edge_west_01",
        "CollisionProxy",
        "Origin",
    ],
    "collision": {"proxy_shape": "box", "nav_blocker": False},
    "socket_records": [],
}

def test_missing_contract_socket_is_reported_deterministically(spec) -> None:
    report = BASE_REPORT | {"helper_names": ["Anchor_FloorCenter", "Origin", "CollisionProxy"]}
    errors = validate_report(spec, report)
    assert errors[:4] == [
        "missing source socket Anchor_SOCK_floor_edge_east_01: floor_1x1",
        "missing source socket Anchor_SOCK_floor_edge_north_01: floor_1x1",
        "missing source socket Anchor_SOCK_floor_edge_south_01: floor_1x1",
        "missing source socket Anchor_SOCK_floor_edge_west_01: floor_1x1",
    ]

def test_non_identity_source_root_is_rejected(spec) -> None:
    report = BASE_REPORT | {"root_identity": False}
    assert "source root transform is not identity: floor_1x1" in validate_report(spec, report)
```

- [ ] **Step 2: Run and verify red**

Run:

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_validate_structural_sources.py
```

Expected: collection failure because `tools.validate_structural_sources` does not exist.

- [ ] **Step 3: Implement a read-only Blender inspector**

```python
# tools/inspect_structural_sources.py (core report creation)
def inspect_open_blend(bpy, module_id: str) -> dict[str, object]:
    root = bpy.data.objects.get(f"ModuleRoot_{module_id}")
    helpers = bpy.data.collections.get("AuthoringHelpers")
    if root is None or helpers is None:
        raise RuntimeError(f"missing source root or AuthoringHelpers: {module_id}")
    socket_records = []
    for obj in sorted(helpers.objects, key=lambda candidate: candidate.name):
        if obj.name.startswith("Anchor_SOCK_"):
            socket_records.append({
                "name": obj.name,
                "location_z_up": [round(float(value), 6) for value in obj.location],
                "socket_id": str(obj.get("socket_id", "")),
                "kind": str(obj.get("kind", "")),
                "compatible_kinds": json.loads(str(obj.get("compatible_kinds", "[]"))),
                "position_contract_y_up": json.loads(str(obj.get("position_contract_y_up", "[]"))),
            })
    collision = bpy.data.objects.get("CollisionProxy")
    return {
        "module_id": module_id,
        "root_name": root.name,
        "root_identity": tuple(root.location) == (0.0, 0.0, 0.0) and tuple(root.rotation_euler) == (0.0, 0.0, 0.0),
        "helper_names": sorted(obj.name for obj in helpers.objects),
        "collision": {
            "proxy_shape": str(collision.get("proxy_shape", "")) if collision else "",
            "nav_blocker": bool(collision.get("nav_blocker", False)) if collision else None,
        },
        "socket_records": socket_records,
    }
```

The inspector must not save, export, alter selection, or create objects.

- [ ] **Step 4: Implement contract/report comparison and run green**

`validate_report(spec, report)` must require:
- exact `ModuleRoot_<id>` name and identity transform;
- exactly one `Origin`, `Anchor_FloorCenter`, and `CollisionProxy` helper;
- helper socket names equal the contract socket-anchor set;
- every socket custom property and Blender location equals the contract after Y-up -> Z-up conversion at six-decimal precision;
- collision shape and `nav_blocker` equal the contract;
- source record’s contract and GLB SHA-256 values match the current input bytes.

Run:

```bash
/opt/homebrew/bin/python3.11 -m pytest -q tests/test_validate_structural_sources.py tests/test_structural_source_contract.py
```

Expected: all tests pass.

- [ ] **Step 5: Execute the single-source inspector proof**

After Task 2’s disposable `floor_1x1` source is present:

```bash
/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root "$PWD" --source-root "$TMP_SOURCE" --module floor_1x1
```

Expected: `STRUCTURAL_SOURCE_VALIDATION PASS modules=1` and no diagnostics.

- [ ] **Step 6: Commit**

```bash
git add tools/inspect_structural_sources.py tools/validate_structural_sources.py tests/test_validate_structural_sources.py
git commit -m "test: validate Blender structural source contracts"
```

## Task 4: Recover and Validate the Eight External Blender Sources

**Objective:** Use the tested source-only pipeline to create the eight editable Blender source files and companion source records on the external asset volume.

**Files:**
- Create externally: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.blend` (8 files)
- Create externally: `/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/<module_id>.source.json` (8 files)
- No repository runtime asset files may change.

**Interfaces:** The exact CLI from Task 2 using `--all` and no `--overwrite`.

- [ ] **Step 1: Preflight the destination and protect existing runtime assets**

```bash
ROOT=/Volumes/Untitled/SynapticSeaAssets/worktrees/the-synaptic-sea-asset-metadata-retrofit
SOURCE_ROOT=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0
mkdir -p "$SOURCE_ROOT"
git -C "$ROOT" status --porcelain
shasum -a 256 "$ROOT"/assets/imported/structural/ship_structural_v0/*/*.glb \
  | sort > /private/tmp/synaptic-structural-glb-before.sha256
```

Expected: clean repository status and an external baseline hash manifest. This manifest is verification evidence only; do not add it to Git.

- [ ] **Step 2: Run recovery for exactly the eight approved modules**

```bash
cd "$ROOT"
/opt/homebrew/bin/blender --background --factory-startup \
  --python tools/recover_modules.py -- \
  --project-root "$ROOT" \
  --source-root "$SOURCE_ROOT" \
  --all
```

Expected: eight `STRUCTURAL_SOURCE_RECOVERED` lines, with no `GLB` output path printed.

- [ ] **Step 3: Validate all recovered sources against live contracts**

```bash
/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" --all
```

Expected: `STRUCTURAL_SOURCE_VALIDATION PASS modules=8` and zero errors.

- [ ] **Step 4: Independently prove each `.blend` opens and is editable**

```bash
for module in floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 \
  wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2; do
  /opt/homebrew/bin/blender --background --factory-startup \
    "$SOURCE_ROOT/$module/$module.blend" \
    --python-expr "import bpy; print('BLEND_OPEN PASS module=$module objects=%d' % len(bpy.data.objects))" \
    --quit
 done
```

Expected: eight `BLEND_OPEN PASS` lines. Each source has at least one imported mesh plus the required helpers.

- [ ] **Step 5: Prove this phase did not change any runtime GLB or repository path**

```bash
shasum -a 256 "$ROOT"/assets/imported/structural/ship_structural_v0/*/*.glb \
  | sort > /private/tmp/synaptic-structural-glb-after.sha256
diff -u /private/tmp/synaptic-structural-glb-before.sha256 /private/tmp/synaptic-structural-glb-after.sha256
git -C "$ROOT" diff --check
git -C "$ROOT" status --porcelain
```

Expected: empty `diff`, zero `git status --porcelain` output, and no `.import` or `.godot` changes. Delete the two `/private/tmp/synaptic-structural-glb-*.sha256` files after the comparison.

- [ ] **Step 6: Do not commit external Blender outputs**

The `.blend` and `.source.json` outputs intentionally live outside the Git worktree. Commit only the implementation code, tests, and documentation from the preceding tasks. Record the verified module IDs and external source root in the documentation, not raw absolute user-home paths embedded in source code.

## Task 5: Document the Authoring Boundary and Future Export Gate

**Objective:** Make the source workflow repeatable and prevent a future worker from accidentally treating source recovery as permission to replace validated runtime assets.

**Files:**
- Create: `docs/game/features/blender_structural_source_pipeline.md`
- Modify: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Write the source-pipeline contract document**

Document these exact sections:

```markdown
## Authority
- Structural JSON contracts own sockets, bounds, footprint, collision intent, and placement origin.
- `.blend` sources are editable representations of current visuals plus contract-derived helpers.
- Existing imported GLBs and Godot wrappers remain runtime authority for this phase.

## External source layout
/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/<module_id>/
  <module_id>.blend
  <module_id>.source.json

## Required Blender objects
ModuleRoot_<module_id>, Origin, Anchor_FloorCenter, Anchor_SOCK_<socket_id>, CollisionProxy.

## Coordinate mapping
contract [x, y, z] maps to Blender [x, z, y].

## Prohibited actions
No GLB export/re-export, no replacement of `assets/imported`, no wrapper/manifest/contract edits, and no direct manual edits to `.source.json`.

## Future promotion gate
A later, separately approved plan must define staged export paths, GLB byte-change review, structural variant treatment, wrapper/contract compatibility, Godot import, and the full state-safe regression bundle before any source can affect runtime assets.
```

- [ ] **Step 2: Add reproducible validation commands**

Add these commands to `docs/game/06_validation_plan.md` exactly under a new Blender-source section:

```bash
ROOT=/Volumes/Untitled/SynapticSeaAssets/worktrees/the-synaptic-sea-asset-metadata-retrofit
SOURCE_ROOT=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0
/opt/homebrew/bin/python3.11 -m pytest -q \
  tests/test_structural_source_contract.py \
  tests/test_recover_modules_cli.py \
  tests/test_validate_structural_sources.py
/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" --all
python3 tools/validate_structural_variant_bindings.py --project-root "$ROOT"
```

State that Godot smoke tests still require the frozen external state runner; Blender recovery itself must not invoke Godot or cause generated-state cleanup.

- [ ] **Step 3: Validate documentation links and repository scope**

Run:

```bash
/opt/homebrew/bin/python3.11 -m pytest -q \
  tests/test_structural_source_contract.py \
  tests/test_recover_modules_cli.py \
  tests/test_validate_structural_sources.py
python3 tools/validate_structural_variant_bindings.py --project-root .
git diff --check
git status --short
```

Expected: tests and structural audit pass; Git changes are limited to the five planned code/test files and the two documentation files.

- [ ] **Step 4: Commit**

```bash
git add docs/game/features/blender_structural_source_pipeline.md docs/game/06_validation_plan.md
git commit -m "docs: define Blender structural source workflow"
```

## Task 6: Final Source-Recovery Acceptance Gate

**Objective:** Run one final, evidence-backed acceptance pass proving the external source library is complete, contract-correct, and has not altered the runtime pipeline.

**Files:**
- No new files.
- Reads external sources and repository contracts/GLBs only.

- [ ] **Step 1: Run all source-pipeline tests**

```bash
/opt/homebrew/bin/python3.11 -m pytest -q \
  tests/test_structural_source_contract.py \
  tests/test_recover_modules_cli.py \
  tests/test_validate_structural_sources.py
```

Expected: all tests pass.

- [ ] **Step 2: Run all eight source checks and runtime structural audit**

```bash
ROOT=$PWD
SOURCE_ROOT=/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0
/opt/homebrew/bin/python3.11 tools/validate_structural_sources.py \
  --project-root "$ROOT" --source-root "$SOURCE_ROOT" --all
/opt/homebrew/bin/python3.11 tools/validate_structural_variant_bindings.py \
  --project-root "$ROOT"
```

Expected:

```text
STRUCTURAL_SOURCE_VALIDATION PASS modules=8
```

and structural variant audit exit `0`.

- [ ] **Step 3: Re-run the relevant Godot structural smoke through the frozen state runner**

```bash
RUNNER=/tmp/synaptic-task6.lndUqM/state_runner.py
"$RUNNER" -- /bin/bash -c \
  '/opt/homebrew/bin/godot --headless --editor --path . --quit && \
   /opt/homebrew/bin/godot --headless --path . --script \
   res://scripts/validation/structural_variant_wrapper_smoke.gd'
```

Expected: `STRUCTURAL VARIANT WRAPPER PASS wrappers=8 intact=true damaged=true breached=true`, generated-state restoration marker, and zero `ERROR:`, `WARNING:`, and `SCRIPT ERROR:` lines. If the frozen runner path differs, recreate it using the already-approved state-runner implementation before running this command; do not use raw Godot or Git cleanup as a substitute.

- [ ] **Step 4: Verify source inventory and no runtime mutation**

```bash
for module in floor_1x1 floor_2x1 corridor_floor_1x1 corridor_floor_1x2 \
  wall_straight_1x1 doorway_frame_open_1x1 pillar_support_1x1 ramp_up_1x2; do
  test -s "$SOURCE_ROOT/$module/$module.blend"
  test -s "$SOURCE_ROOT/$module/$module.source.json"
done

git diff --check
test -z "$(git status --porcelain)"
```

Expected: all 16 external source files exist and are nonempty; the repository worktree is clean after the implementation commits; no GLB path has changed.

- [ ] **Step 5: Final integration review**

Dispatch a read-only reviewer after all checks pass. The review checklist must confirm:
- exactly eight permitted source modules;
- source root and all CLI paths are explicit, with no stale Off The Rails hardcoded path;
- source helpers use the live contract, not duplicated socket data;
- current GLBs, wrappers, manifests, contracts, `.import`, and `.godot` are untouched;
- no generated source record has a timestamp or manually duplicated runtime authority;
- source validation and runtime structural validation both pass.

## Risks, Tradeoffs, and Explicit Non-Goals

- **Imported geometry is preserved, not cosmetically rebuilt.** Recovery produces editable Blender files from current intact visuals, which is safer than introducing visual drift. Industrial art improvement, UV repair, retopology, and material revision remain later artistic tasks.
- **Connector orientation is provisional authoring metadata.** Existing contracts own positions/kinds/compatibility but not rotations. The cardinal socket-ID convention is stored as source aid only; it is not promoted to gameplay authority.
- **Only eight integrity-variant modules are recovered.** The seven other catalog modules (`bulkhead_portal_2x1`, `ceiling_cap_1x1`, `doorway_frame_blocked_1x1`, `wall_end_cap`, `wall_inner_corner`, `wall_outer_corner`, `wall_t_junction`) require a follow-up source-recovery expansion after this foundation is proven.
- **No runtime asset promotion occurs.** A future export/promotion plan must be separately approved and must use a staged output directory, explicit byte-hash review, damaged/breached variant policy, Godot import, wrapper validation, and the full state-safe regression suite. It may not silently copy a new GLB over an existing runtime asset.
- **External source files are not backed up by Git.** The source root must be included in the existing external-drive backup routine before an artistic iteration workflow begins.

## Plan Self-Review

- [x] Covers the missing Blender-source requirement with contract-derived sockets, collision helper, coordinate conversion, and provenance.
- [x] Uses exact current project paths and the eight structural families governed by `validate_structural_variant_bindings.py`.
- [x] Reuses/refactors the existing `tools/recover_modules.py` instead of duplicating a second recovery script.
- [x] Preserves runtime ownership boundaries: no structural connector/collision behavior is transferred to prop sidecars or visual bindings.
- [x] Contains red/green unit-test cycles, real Blender integration checks, deterministic source inspection, and a state-safe Godot regression gate.
- [x] Prohibits GLB re-export and runtime mutation throughout this phase.
- [x] Defines every implementation file, source output, verification command, and acceptance criterion needed for execution.
