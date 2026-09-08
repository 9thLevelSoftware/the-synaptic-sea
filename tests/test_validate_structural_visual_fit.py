from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT_ROOT / "tools" / "validate_structural_visual_fit.py"
BLENDER = Path(os.environ.get("BLENDER", "/opt/homebrew/bin/blender"))


def _load_validator_module():
    spec = importlib.util.spec_from_file_location("validate_structural_visual_fit", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _run_blender_python(script: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python-exit-code",
            "1",
            "--python-expr",
            script,
            "--",
            *args,
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def test_validator_cli_requires_project_module_and_glb(tmp_path: Path) -> None:
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "--project-root" in result.stderr
    assert "--module" in result.stderr
    assert "--glb" in result.stderr


def test_validator_uses_full_world_vertices_and_native_gltf_axis_conversion(
    tmp_path: Path,
) -> None:
    if not BLENDER.is_file():
        pytest.skip(f"Blender not found: {BLENDER}")

    glb = tmp_path / "asymmetric.glb"
    captured = tmp_path / "captured.json"
    create = r'''
import bpy
import sys
from mathutils import Vector

output = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
mesh = bpy.data.meshes.new("Asymmetric")
# Blender Z-up points corresponding to native glTF Y-up points:
# (1, 2, 3), (2, 2, 3), (1, 4, 4).
mesh.from_pydata([(1.0, -3.0, 2.0), (2.0, -3.0, 2.0), (1.0, -4.0, 4.0)], [], [(0, 1, 2)])
obj = bpy.data.objects.new("Part_Asymmetric", mesh)
bpy.context.scene.collection.objects.link(obj)
obj.location = (0.0, 0.0, 0.0)
# The validator must use evaluated world vertices, so compensate in the
# source mesh and leave the imported node transform at identity.
bpy.context.view_layer.objects.active = obj
obj.select_set(True)
result = bpy.ops.export_scene.gltf(filepath=output, export_format="GLB", export_apply=True, use_selection=True)
if "FINISHED" not in result:
    raise RuntimeError(result)
'''
    created = _run_blender_python(create, str(glb))
    assert created.returncode == 0, created.stdout + created.stderr

    inspect = r'''
import importlib.util
import json
import sys
from pathlib import Path

import bpy

script = Path(sys.argv[sys.argv.index("--") + 1])
glb = Path(sys.argv[sys.argv.index("--") + 2])
out = Path(sys.argv[sys.argv.index("--") + 3])
spec = importlib.util.spec_from_file_location("validator_under_test", script)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def fake_load_dimensions(path):
    return {"test": True}

def fake_validate_geometry(module_id, triangles, dimensions):
    out.write_text(json.dumps({"module": module_id, "triangles": triangles, "dimensions": dimensions}), encoding="utf-8")
    return {"status": "pass", "errors": [], "measurements": {"triangle_count": len(triangles)}}

module.load_dimensions = fake_load_dimensions
module.validate_geometry = fake_validate_geometry
result = module.validate_glb(glb, "wall_straight_1x1", None, bpy)
if result.get("status") != "pass":
    raise RuntimeError(result)
'''
    inspected = _run_blender_python(inspect, str(SCRIPT), str(glb), str(captured))
    assert inspected.returncode == 0, inspected.stdout + inspected.stderr

    document = json.loads(captured.read_text(encoding="utf-8"))
    points = [point for triangle in document["triangles"] for point in triangle]
    assert any(
        all(abs(actual - expected) <= 1e-5 for actual, expected in zip(point, (1.0, 2.0, 3.0)))
        for point in points
    )
    assert any(
        all(abs(actual - expected) <= 1e-5 for actual, expected in zip(point, (2.0, 2.0, 3.0)))
        for point in points
    )
    assert any(
        all(abs(actual - expected) <= 1e-5 for actual, expected in zip(point, (1.0, 4.0, 4.0)))
        for point in points
    )


def test_validator_rejects_mesh_node_translation_and_non_identity_import_root(
    tmp_path: Path,
) -> None:
    validator = _load_validator_module()

    class Matrix:
        def __init__(self, translation=(0.0, 0.0, 0.0)):
            self.translation = translation

        def __matmul__(self, point):
            return SimpleNamespace(
                x=point.x + self.translation[0],
                y=point.y + self.translation[1],
                z=point.z + self.translation[2],
            )

    class Vertex:
        def __init__(self, x, y, z):
            self.co = SimpleNamespace(x=x, y=y, z=z)

    class Polygon:
        vertices = (0, 1, 2)

    class Mesh:
        polygons = (Polygon(),)
        # These local vertices compensate for the node translation, keeping
        # the evaluated world bounds unchanged while violating the GLB node contract.
        vertices = (Vertex(-2, 0, 0), Vertex(-1, 0, 0), Vertex(-2, 0, 1))

    root = SimpleNamespace(
        name="ModuleRoot_wall_straight_1x1",
        type="EMPTY",
        parent=None,
        children=[],
        matrix_world=Matrix((0.0, 0.0, 0.0)),
        location=SimpleNamespace(x=0.0, y=0.0, z=0.0),
        rotation_euler=SimpleNamespace(x=0.0, y=0.0, z=0.0),
        scale=SimpleNamespace(x=1.0, y=1.0, z=1.0),
    )
    child = SimpleNamespace(
        name="Part_wall",
        type="MESH",
        parent=root,
        data=Mesh(),
        matrix_world=Matrix((2.0, 0.0, 0.0)),
        location=SimpleNamespace(x=2.0, y=0.0, z=0.0),
        rotation_euler=SimpleNamespace(x=0.0, y=0.0, z=0.0),
        scale=SimpleNamespace(x=1.0, y=1.0, z=1.0),
        evaluated_get=lambda _depsgraph: child,
        to_mesh=lambda: Mesh(),
        to_mesh_clear=lambda: None,
    )
    root.children = [child]

    class Ops:
        class Wm:
            @staticmethod
            def read_factory_settings(use_empty=True):
                return {"FINISHED"}

        class Import:
            @staticmethod
            def gltf(filepath):
                return {"FINISHED"}

        wm = Wm()
        import_scene = Import()

    fake_bpy = SimpleNamespace(
        ops=Ops(),
        context=SimpleNamespace(
            scene=SimpleNamespace(objects=[root, child]),
            evaluated_depsgraph_get=lambda: object(),
        ),
    )
    validator.load_dimensions = lambda _path: {}
    validator.validate_geometry = lambda *_args: {
        "status": "pass",
        "errors": [],
        "measurements": {},
    }
    (tmp_path / "fixture.glb").write_bytes(b"glTF" + b"\0" * 32)

    result = validator.validate_glb(tmp_path / "fixture.glb", "wall_straight_1x1", None, fake_bpy)
    assert result["status"] == "fail"
    assert any("translation" in error.lower() for error in result["errors"])
    assert result["measurements"]["mesh_object_count"] == 1

    root.matrix_world = Matrix((1.0, 0.0, 0.0))
    rejected = validator.validate_glb(tmp_path / "fixture.glb", "wall_straight_1x1", None, fake_bpy)
    assert rejected["status"] == "fail"
    assert any("root" in error.lower() for error in rejected["errors"])


def test_validator_rejects_imported_helpers_without_calling_geometry_contract(
    tmp_path: Path,
) -> None:
    validator = _load_validator_module()
    calls: list[object] = []
    validator.validate_geometry = lambda *_args: calls.append(True)
    validator.load_dimensions = lambda _path: {}

    helper = SimpleNamespace(
        name="AuthoringHelpers",
        type="LIGHT",
        parent=None,
        children=[],
        matrix_world=SimpleNamespace(is_identity=True),
    )

    class Wm:
        @staticmethod
        def read_factory_settings(use_empty=True):
            return {"FINISHED"}

    class Import:
        @staticmethod
        def gltf(filepath):
            return {"FINISHED"}

    fake_bpy = SimpleNamespace(
        ops=SimpleNamespace(wm=Wm(), import_scene=Import()),
        context=SimpleNamespace(scene=SimpleNamespace(objects=[helper])),
    )
    (tmp_path / "fixture.glb").write_bytes(b"glTF" + b"\0" * 32)

    result = validator.validate_glb(tmp_path / "fixture.glb", "wall_straight_1x1", None, fake_bpy)
    assert result["status"] == "fail"
    assert any("helper" in error.lower() or "light" in error.lower() for error in result["errors"])
    assert calls == []
