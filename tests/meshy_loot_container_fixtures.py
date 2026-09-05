from __future__ import annotations

import hashlib
import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tools.meshy_blender_master import _run_bounded_process

ASSET_ID = "loot_container_derelict_v1"
TASK_ID = "01a05dcb-fc3b-7418-b105-2170af354088"


@dataclass(frozen=True)
class LootFixtureCase:
    master: Path
    raw: Path
    task: Path
    evidence: Path


def create_synthetic_blender_fixture(
    root: Path, blender: Path, project_root: Path
) -> LootFixtureCase:
    """Build disposable Blender master/raw inputs for generic integration tests.

    This deliberately creates a small real-Blender fixture rather than standing in
    for paid-private Meshy provenance.  The recipe behavior under test is still
    exercised by the actual Blender subprocess and by the actual recipe runner.
    """

    fixture_root = root / "synthetic-blender-input"
    master = fixture_root / "source" / ASSET_ID / f"{ASSET_ID}_master.blend"
    task = fixture_root / "task"
    evidence = fixture_root / "evidence"
    master.parent.mkdir(parents=True)
    task.mkdir()
    evidence.mkdir()
    raw = task / "raw.glb"

    expression = "\n".join(
        (
            "import bpy",
            "from pathlib import Path",
            f"master = Path({str(master)!r})",
            f"raw = Path({str(raw)!r})",
            "scene = bpy.context.scene",
            "for obj in list(bpy.data.objects):",
            "    bpy.data.objects.remove(obj, do_unlink=True)",
            "for datablocks in (bpy.data.meshes, bpy.data.cameras, bpy.data.lights):",
            "    for datablock in list(datablocks):",
            "        if datablock.users == 0:",
            "            datablocks.remove(datablock)",
            "def ensure_collection(name):",
            "    collection = bpy.data.collections.get(name)",
            "    if collection is None:",
            "        collection = bpy.data.collections.new(name)",
            "    if scene.collection.children.get(name) is None:",
            "        scene.collection.children.link(collection)",
            "    return collection",
            "source = ensure_collection('SOURCE_RAW')",
            "ensure_collection('WORKING')",
            "markers = ensure_collection('SOCKETS_MARKERS')",
            "bpy.ops.mesh.primitive_cube_add(size=0.1, location=(0.0, 0.0, 0.05))",
            "mesh_node = bpy.context.object",
            "mesh_node.name = 'mesh_node'",
            "mesh_node.data.name = 'SyntheticRawMesh'",
            "mesh_node.hide_render = True",
            "for owner in list(mesh_node.users_collection):",
            "    owner.objects.unlink(mesh_node)",
            "source.objects.link(mesh_node)",
            "for name, location in (('ORIGIN_MARKER', (0.0, 0.0, 0.0)), ('FORWARD_Z_MARKER', (0.0, 0.0, 0.1))):",
            "    marker = bpy.data.objects.new(name, None)",
            "    marker.location = location",
            "    markers.objects.link(marker)",
            "for selected in list(bpy.context.selected_objects):",
            "    selected.select_set(False)",
            "mesh_node.select_set(True)",
            "bpy.context.view_layer.objects.active = mesh_node",
            "requested = {",
            "    'filepath': str(raw), 'export_format': 'GLB', 'use_selection': True,",
            "    'export_apply': True, 'export_extras': True, 'export_materials': 'EXPORT',",
            "    'export_texcoords': True, 'export_animations': False, 'export_yup': False,",
            "}",
            "supported = {item.identifier for item in bpy.ops.export_scene.gltf.get_rna_type().properties}",
            "kwargs = {key: value for key, value in requested.items() if key in supported}",
            "if 'filepath' not in kwargs or 'export_format' not in kwargs or 'use_selection' not in kwargs:",
            "    raise RuntimeError('Blender GLB exporter lacks required synthetic-fixture options')",
            "result = bpy.ops.export_scene.gltf(**kwargs)",
            "if 'FINISHED' not in result:",
            "    raise RuntimeError('synthetic raw GLB export did not finish: ' + repr(result))",
            "if not raw.is_file() or raw.stat().st_size <= 20 or raw.read_bytes()[:4] != b'glTF':",
            "    raise RuntimeError('synthetic raw GLB is missing or invalid')",
            "result = bpy.ops.wm.save_as_mainfile(filepath=str(master))",
            "if 'FINISHED' not in result or not master.is_file() or master.stat().st_size <= 0:",
            "    raise RuntimeError('synthetic Blender master was not saved')",
        )
    )
    result = _run_bounded_process(
        [str(blender), "--background", "--factory-startup", "--python-expr", expression],
        cwd=project_root,
        timeout=120.0,
    )
    stdout = result.stdout.decode("utf-8", "replace") if isinstance(result.stdout, bytes) else str(result.stdout or "")
    stderr = result.stderr.decode("utf-8", "replace") if isinstance(result.stderr, bytes) else str(result.stderr or "")
    if result.returncode != 0:
        raise AssertionError(f"synthetic Blender fixture failed:\n{stdout}\n{stderr}")
    if not master.is_file() or not raw.is_file():
        raise AssertionError("synthetic Blender fixture did not produce master and raw GLB")
    return LootFixtureCase(master=master, raw=raw, task=task, evidence=evidence)


def materialize_fixture_case(fixture: LootFixtureCase, case_root: Path) -> LootFixtureCase:
    """Copy a synthetic fixture into an isolated disposable recipe case."""

    master = case_root / "source" / ASSET_ID / f"{ASSET_ID}_master.blend"
    task = case_root / "task"
    evidence = case_root / "evidence"
    master.parent.mkdir(parents=True)
    task.mkdir()
    evidence.mkdir()
    shutil.copy2(fixture.master, master)
    shutil.copy2(fixture.raw, task / "raw.glb")
    return LootFixtureCase(master=master, raw=task / "raw.glb", task=task, evidence=evidence)


def recover_verified_private_raw(
    project_root: Path, destination: Path, contract_sha256: str
) -> Path:
    """Recover private raw bytes only from a matching generation record.

    The neighboring worktree archive is read-only evidence.  A missing or
    mismatched record is a hard test failure, never a skip or synthetic fallback.
    """

    relative = Path("assets/_staging/meshy") / ASSET_ID / TASK_ID
    candidates = (
        project_root / relative,
        project_root.parent / "meshy-blender-asset-system" / relative,
    )
    checked: list[str] = []
    for task_root in candidates:
        raw = task_root / "raw.glb"
        generation_path = task_root / "generation.json"
        checked.append(str(task_root))
        if not raw.is_file() or not generation_path.is_file():
            continue
        try:
            generation: Any = json.loads(generation_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            continue
        output = generation.get("outputs", {}).get("raw.glb") if isinstance(generation, dict) else None
        provenance = generation.get("provenance") if isinstance(generation, dict) else None
        if not isinstance(output, dict) or not isinstance(provenance, dict):
            continue
        if (
            generation.get("asset_id") != ASSET_ID
            or generation.get("task_id") != TASK_ID
            or generation.get("status") != "SUCCEEDED"
            or generation.get("contract_sha256") != contract_sha256
            or generation.get("output_license") != "paid-private"
            or provenance.get("provider") != "meshy"
            or provenance.get("license_state") != "paid-private"
        ):
            continue
        payload = raw.read_bytes()
        digest = hashlib.sha256(payload).hexdigest()
        if (
            payload[:4] != b"glTF"
            or output.get("sha256") != digest
            or output.get("byte_size") != len(payload)
        ):
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(raw, destination)
        return destination
    raise AssertionError(
        "verified paid-private raw.glb unavailable; checked generation-bound sources: "
        + ", ".join(checked)
    )
