from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys

import pytest

from tools.room_kit_contract import glb_document, validate_static


ROOT = Path(__file__).resolve().parents[1]
BLENDER = Path(os.environ.get("BLENDER", "/opt/homebrew/bin/blender"))
EXPORTER = ROOT / "tools/export_static_room_prop.py"
EVIDENCE = ROOT / "artifacts/room_kit_v2/contracts"



def run_blender(script: Path, *args: str, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    assert BLENDER.is_file(), f"Blender not found: {BLENDER}"
    return subprocess.run(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python-exit-code",
            "1",
            "--python",
            str(script),
            "--",
            *args,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        timeout=timeout,
    )



def save_log(name: str, result: subprocess.CompletedProcess[str]) -> None:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / name).write_text(
        result.stdout + ("\n--- STDERR ---\n" + result.stderr if result.stderr else ""),
        encoding="utf-8",
    )



def create_master(tmp_path: Path, case: str = "valid") -> Path:
    source = tmp_path / f"{case}.blend"
    script = tmp_path / f"create_{case}.py"
    script.write_text(
        """
import bpy
import sys
from mathutils import Vector

source = sys.argv[sys.argv.index('--') + 1]
case = sys.argv[sys.argv.index('--') + 2]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
export = bpy.data.collections.new('Export_Static')
scene.collection.children.link(export)
helpers = bpy.data.collections.new('AuthoringHelpers')
scene.collection.children.link(helpers)
material = bpy.data.materials.new('MAT_PaintedAlloyGray')


def move_to(obj, collection):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)


def cube(name, location=(-1.0, 0.0, 0.5)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(island_margin=0.03)
    bpy.ops.object.mode_set(mode='OBJECT')
    move_to(obj, export)
    obj.select_set(False)
    return obj

if case == 'valid':
    cube('Part_Left', (-1.0, 0.0, 0.5))
    cube('Part_Right', (1.0, 0.0, 0.5))
elif case == 'empty':
    pass
elif case == 'nonmesh':
    obj = bpy.data.objects.new('NotMesh', None)
    export.objects.link(obj)
elif case == 'helper':
    cube('HelperVisual')
elif case == 'armature':
    bpy.ops.object.armature_add(location=(0.0, 0.0, 0.5))
    move_to(bpy.context.object, export)
elif case == 'armature_modifier':
    obj = cube('ArmatureModifiedMesh')
    bpy.ops.object.armature_add(location=(0.0, 0.0, 0.5))
    armature = bpy.context.object
    move_to(armature, helpers)
    modifier = obj.modifiers.new(name='Rig', type='ARMATURE')
    modifier.object = armature
elif case == 'animated_parent':
    obj = cube('AnimatedParentChild')
    parent = bpy.data.objects.new('AnimatedParent', None)
    helpers.objects.link(parent)
    obj.parent = parent
    parent.location.x = -0.5
    parent.keyframe_insert(data_path='location', frame=1)
    parent.location.x = 0.5
    parent.keyframe_insert(data_path='location', frame=10)
elif case == 'morph':
    obj = cube('MorphMesh')
    obj.shape_key_add(name='Basis')
    obj.shape_key_add(name='Morph')
elif case == 'animation':
    obj = cube('AnimatedMesh')
    obj.location.x = -0.5
    obj.keyframe_insert(data_path='location', frame=1)
    obj.location.x = 0.5
    obj.keyframe_insert(data_path='location', frame=10)
elif case == 'nonpositive':
    obj = cube('ZeroScale')
    obj.scale = (0.0, 1.0, 1.0)
elif case == 'no_uv':
    obj = cube('NoUV')
    while obj.data.uv_layers:
        obj.data.uv_layers.remove(obj.data.uv_layers[0])
else:
    raise RuntimeError(case)

front = bpy.data.objects.new('AuthoringFront', None)
helpers.objects.link(front)
front.location = (0.0, -1.0, 0.0)
bpy.ops.wm.save_as_mainfile(filepath=source)
print('ROOM_KIT_TEST_MASTER_PASS', case, source)
""",
        encoding="utf-8",
    )
    result = run_blender(script, str(source), case)
    save_log(f"create-{case}.log", result)
    assert result.returncode == 0, result.stdout + result.stderr
    assert source.is_file()
    return source



def run_export(source: Path, output: Path, name: str) -> subprocess.CompletedProcess[str]:
    result = run_blender(
        EXPORTER,
        "--source",
        str(source),
        "--output",
        str(output),
    )
    save_log(name, result)
    return result



def test_transformed_master_exports_y_up_identity_and_preserves_source(tmp_path) -> None:
    source = create_master(tmp_path)
    output = tmp_path / "translated-pair.glb"
    before = hashlib.sha256(source.read_bytes()).hexdigest()

    result = run_export(source, output, "export-positive.log")

    assert result.returncode == 0, result.stdout + result.stderr
    assert "ROOM_KIT_STATIC_EXPORT_PASS" in result.stdout
    assert output.is_file() and output.stat().st_size > 32
    record = validate_static(
        output,
        {"max_size_m": [3.0, 1.0, 1.0], "triangles_max": 10000, "material_max": 4},
    )
    assert record["local_min_m"] == [-1.5, 0.0, -0.5]
    assert record["local_max_m"] == [1.5, 1.0, 0.5]
    source_after = hashlib.sha256(source.read_bytes()).hexdigest()
    assert source_after == before
    exported_document = glb_document(output)
    identity_nodes = all(
        all(abs(float(value) - expected) <= 1e-6 for value, expected in zip(node.get("translation", [0, 0, 0]), [0, 0, 0]))
        and all(abs(float(value) - expected) <= 1e-6 for value, expected in zip(node.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1]))
        and all(abs(float(value) - expected) <= 1e-6 for value, expected in zip(node.get("scale", [1, 1, 1]), [1, 1, 1]))
        for node in exported_document["nodes"]
    )
    helpers_excluded = not any(
        node.get("name", "").startswith(("Anchor", "Collision", "Socket", "Helper"))
        for node in exported_document["nodes"]
    )
    (EVIDENCE / "export-proof.json").write_text(
        json.dumps(
            {
                "source_sha256_before": before,
                "source_sha256_after": source_after,
                "source_unchanged": before == source_after,
                "output_sha256": record["sha256"],
                "world_min_y_up": record["local_min_m"],
                "world_max_y_up": record["local_max_m"],
                "identity_nodes": identity_nodes,
                "helpers_excluded": helpers_excluded,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )
    assert identity_nodes
    assert helpers_excluded
    assert all(
        all(abs(float(value) - expected) <= 1e-6 for value, expected in zip(node.get("translation", [0, 0, 0]), [0, 0, 0]))
        and all(abs(float(value) - expected) <= 1e-6 for value, expected in zip(node.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1]))
        and all(abs(float(value) - expected) <= 1e-6 for value, expected in zip(node.get("scale", [1, 1, 1]), [1, 1, 1]))
        for node in glb_document(output)["nodes"]
    )
    assert not any(
        node.get("name", "").startswith(("Anchor", "Collision", "Socket", "Helper"))
        for node in glb_document(output)["nodes"]
    )

    inspect_script = tmp_path / "inspect_reimport.py"
    inspect_script.write_text(
        """
import bpy
import json
import sys
from mathutils import Vector
path = sys.argv[sys.argv.index('--') + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
result = bpy.ops.import_scene.gltf(filepath=path)
if 'FINISHED' not in result:
    raise RuntimeError(result)
meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
if len(meshes) != 2:
    raise RuntimeError('expected two imported meshes')
points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
lo = [min(point[index] for point in points) for index in range(3)]
hi = [max(point[index] for point in points) for index in range(3)]
if any(abs(value) > 1e-6 for obj in meshes for value in obj.location):
    raise RuntimeError('non-identity imported node translation')
if any(abs(value) > 1e-6 for obj in meshes for value in obj.rotation_euler):
    raise RuntimeError('non-identity imported node rotation')
if any(abs(value - 1.0) > 1e-6 for obj in meshes for value in obj.scale):
    raise RuntimeError('non-identity imported node scale')
print('ROOM_KIT_GLTF_REIMPORT_PASS ' + json.dumps({'mesh_count': len(meshes), 'world_min': lo, 'world_max': hi, 'helpers_excluded': True}, sort_keys=True))
""",
        encoding="utf-8",
    )
    inspect = run_blender(inspect_script, str(output))
    save_log("export-reimport.log", inspect)
    assert inspect.returncode == 0, inspect.stdout + inspect.stderr
    assert "ROOM_KIT_GLTF_REIMPORT_PASS" in inspect.stdout
    assert '"helpers_excluded": true' in inspect.stdout


@pytest.mark.parametrize("case", ["empty", "nonmesh", "helper", "armature", "armature_modifier", "animated_parent", "morph", "animation", "nonpositive", "no_uv"])
def test_export_rejects_invalid_static_sources(tmp_path, case) -> None:
    source = create_master(tmp_path, case)
    result = run_export(source, tmp_path / f"{case}.glb", f"export-negative-{case}.log")

    assert result.returncode != 0
    assert "ROOM_KIT_STATIC_EXPORT_PASS" not in result.stdout



def test_export_rejects_missing_source_and_existing_or_symlink_output(tmp_path) -> None:
    source = create_master(tmp_path)
    missing = tmp_path / "missing.blend"
    result = run_export(missing, tmp_path / "missing.glb", "export-negative-missing.log")
    assert result.returncode != 0
    assert "ROOM_KIT_STATIC_EXPORT_PASS" not in result.stdout

    existing = tmp_path / "existing.glb"
    existing.write_bytes(b"sentinel")
    result = run_export(source, existing, "export-negative-existing.log")
    assert result.returncode != 0
    assert existing.read_bytes() == b"sentinel"

    target = tmp_path / "symlink-target.glb"
    link = tmp_path / "symlink.glb"
    link.symlink_to(target)
    result = run_export(source, link, "export-negative-symlink.log")
    assert result.returncode != 0
    assert link.is_symlink()



def test_export_rejects_cancelled_operator(tmp_path) -> None:
    source = create_master(tmp_path)
    output = tmp_path / "cancelled.glb"
    script = tmp_path / "cancel_export.py"
    script.write_text(
        f"""
import runpy
from pathlib import Path
module = runpy.run_path({str(EXPORTER)!r})
def cancelled(**kwargs):
    return {{'CANCELLED'}}
module['export_static'](Path({str(source)!r}), Path({str(output)!r}), export_operator=cancelled)
""",
        encoding="utf-8",
    )
    result = run_blender(script)
    save_log("export-negative-cancelled.log", result)

    assert result.returncode != 0
    assert "ROOM_KIT_STATIC_EXPORT_PASS" not in result.stdout
    assert not output.exists()



def test_export_rejects_invalid_glb_from_finished_operator(tmp_path) -> None:
    source = create_master(tmp_path)
    output = tmp_path / "invalid.glb"
    script = tmp_path / "invalid_export.py"
    script.write_text(
        f"""
import runpy
from pathlib import Path
module = runpy.run_path({str(EXPORTER)!r})
def invalid(**kwargs):
    Path({str(output)!r}).write_bytes(b'not-a-glb')
    return {{'FINISHED'}}
module['export_static'](Path({str(source)!r}), Path({str(output)!r}), export_operator=invalid)
""",
        encoding="utf-8",
    )
    result = run_blender(script)
    save_log("export-negative-invalid-glb.log", result)

    assert result.returncode != 0
    assert "ROOM_KIT_STATIC_EXPORT_PASS" not in result.stdout
    assert not output.exists()



def test_export_rejects_glb_without_binary_payload(tmp_path) -> None:
    source = create_master(tmp_path)
    output = tmp_path / "missing-bin.glb"
    script = tmp_path / "missing_bin_export.py"
    script.write_text(
        f"""
import json
import runpy
import struct
from pathlib import Path
module = runpy.run_path({str(EXPORTER)!r})
def invalid(**kwargs):
    document = {{'asset': {{'version': '2.0'}}, 'nodes': [{{'mesh': 0}}], 'meshes': [{{'primitives': []}}]}}
    payload = json.dumps(document, separators=(',', ':')).encode()
    payload += b' ' * ((-len(payload)) % 4)
    raw = struct.pack('<4sII', b'glTF', 2, 20 + len(payload)) + struct.pack('<I4s', len(payload), b'JSON') + payload
    Path({str(output)!r}).write_bytes(raw)
    return {{'FINISHED'}}
module['export_static'](Path({str(source)!r}), Path({str(output)!r}), export_operator=invalid)
""",
        encoding="utf-8",
    )
    result = run_blender(script)
    save_log("export-negative-missing-bin.log", result)

    assert result.returncode != 0
    assert "ROOM_KIT_STATIC_EXPORT_PASS" not in result.stdout
    assert not output.exists()
