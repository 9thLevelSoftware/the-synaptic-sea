from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT_ROOT / "tools" / "export_structural_glb.py"
BLENDER = Path(os.environ.get("BLENDER", "/opt/homebrew/bin/blender"))


def _load_exporter_module():
    spec = importlib.util.spec_from_file_location("export_structural_glb", SCRIPT)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _run_export_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--", *args],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def test_export_cli_requires_blend_path_and_staging_dir() -> None:
    result = _run_export_cli()

    assert result.returncode != 0
    assert "--blend-path" in result.stderr
    assert "--staging-dir" in result.stderr


def test_export_cli_rejects_nonexistent_blend_file(tmp_path: Path) -> None:
    result = _run_export_cli(
        "--blend-path",
        str(tmp_path / "missing.blend"),
        "--staging-dir",
        str(tmp_path / "staging"),
    )

    assert result.returncode != 0
    assert "blend" in result.stderr.lower()
    assert "exist" in result.stderr.lower()


class _FakeCollection(dict):
    def __init__(self, name: str, variant_role: str) -> None:
        super().__init__(variant_role=variant_role)
        self.name = name
        self.objects: list[object] = []


class _FakeCollections(list[_FakeCollection]):
    def get(self, name: str):
        return next((collection for collection in self if collection.name == name), None)


def _fake_bpy(*collections: _FakeCollection):
    return SimpleNamespace(
        context=SimpleNamespace(scene={}),
        data=SimpleNamespace(collections=_FakeCollections(collections), objects=[]),
        ops=SimpleNamespace(
            wm=SimpleNamespace(open_mainfile=lambda filepath: {"FINISHED"}),
            object=SimpleNamespace(),
            export_scene=SimpleNamespace(),
        ),
    )


def test_export_rejects_duplicate_variant_roles_before_export(tmp_path: Path) -> None:
    exporter = _load_exporter_module()
    args = SimpleNamespace(
        blend_path=tmp_path / "source.blend",
        staging_dir=tmp_path / "staging",
        module="module_a",
    )
    bpy = _fake_bpy(
        _FakeCollection("Export_Damaged_A", "damaged"),
        _FakeCollection("Export_Damaged_B", "damaged"),
    )

    with pytest.raises(ValueError, match="duplicate variant_role 'damaged'"):
        exporter.export_blend(args, bpy)


def test_export_rejects_cancelled_source_open_before_using_current_scene(
    tmp_path: Path,
) -> None:
    exporter = _load_exporter_module()
    args = SimpleNamespace(
        blend_path=tmp_path / "source.blend",
        staging_dir=tmp_path / "staging",
        module="module_a",
    )

    class ExplodingScene:
        def __getattribute__(self, name: str):
            if name != "__class__":
                raise AssertionError(f"current scene used after cancelled open: {name}")
            return object.__getattribute__(self, name)

    bpy = _fake_bpy()
    bpy.context.scene = ExplodingScene()
    bpy.ops.wm.open_mainfile = lambda filepath: {"CANCELLED"}

    with pytest.raises(RuntimeError, match="source open did not finish"):
        exporter.export_blend(args, bpy)

    assert not (tmp_path / "staging").exists()


def test_export_rejects_module_id_that_escapes_staging(tmp_path: Path) -> None:
    exporter = _load_exporter_module()
    args = SimpleNamespace(
        blend_path=tmp_path / "source.blend",
        staging_dir=tmp_path / "staging",
        module="../../evil",
    )

    with pytest.raises(ValueError, match="invalid module id"):
        exporter.export_blend(args, _fake_bpy())


def test_export_validates_all_variants_before_replacing_any_staged_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    exporter = _load_exporter_module()
    args = SimpleNamespace(
        blend_path=tmp_path / "source.blend",
        staging_dir=tmp_path / "staging",
        module="wall_straight_1x1",
        project_root=tmp_path,
        dimensions=None,
    )
    old_intact = args.staging_dir / "wall_straight_1x1.glb"
    old_damaged = args.staging_dir / "wall_straight_1x1_damaged.glb"
    args.staging_dir.mkdir(parents=True)
    old_intact.write_bytes(b"old-intact")
    old_damaged.write_bytes(b"old-damaged")

    class Object:
        def select_set(self, _selected: bool) -> None:
            pass

    class ObjectOps:
        @staticmethod
        def select_all(action: str):
            assert action == "DESELECT"

    class ExportScene:
        @staticmethod
        def gltf(filepath: str, **_kwargs):
            Path(filepath).write_bytes(
                b"new-damaged" if "damaged" in filepath else b"new-intact"
            )
            return {"FINISHED"}

    class Collection(_FakeCollection):
        def __init__(self, name: str, role: str):
            super().__init__(name, role)
            self.objects = [Object()]

    collections = _FakeCollections(
        [
            Collection("Export_Intact", "intact"),
            Collection("Export_Damaged", "damaged"),
        ]
    )
    bpy = SimpleNamespace(
        context=SimpleNamespace(
            scene={},
            view_layer=SimpleNamespace(objects=SimpleNamespace(active=None)),
        ),
        data=SimpleNamespace(collections=collections, objects=[]),
        ops=SimpleNamespace(
            wm=SimpleNamespace(open_mainfile=lambda filepath: {"FINISHED"}),
            object=ObjectOps(),
            export_scene=ExportScene(),
        ),
    )
    calls: list[str] = []

    def validate(path: Path, module_id: str, project_root: Path, dimensions, fake_bpy) -> None:
        del module_id, project_root, dimensions, fake_bpy
        calls.append(path.name)
        if "damaged" in path.name:
            raise ValueError("visual contract rejected damaged variant")

    monkeypatch.setattr(exporter, "_validate_exported_glb", validate)

    with pytest.raises(ValueError, match="visual contract rejected"):
        exporter.export_blend(args, bpy)

    assert len(calls) == 2
    assert all(call.endswith(".tmp.glb") for call in calls)
    assert any("damaged" in call for call in calls)
    assert old_intact.read_bytes() == b"old-intact"
    assert old_damaged.read_bytes() == b"old-damaged"
    assert not list(args.staging_dir.glob(".*.tmp.glb"))


def test_real_blender_export_reimports_and_preserves_staged_output_on_visual_failure(
    tmp_path: Path,
) -> None:
    if not BLENDER.is_file():
        pytest.skip(f"Blender not found: {BLENDER}")

    def create_source(path: Path, wall_height: float) -> None:
        script = r'''
import bpy
import sys
from pathlib import Path

output = Path(sys.argv[sys.argv.index("--") + 1])
wall_height = float(sys.argv[sys.argv.index("--") + 2])
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene["module_id"] = "wall_straight_1x1"
export = bpy.data.collections.new("Export_Intact")
export["variant_role"] = "intact"
scene.collection.children.link(export)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, wall_height / 2.0))
wall = bpy.context.object
wall.name = "Part_wall"
wall.dimensions = (4.0, 0.2, wall_height)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
for collection in list(wall.users_collection):
    collection.objects.unlink(wall)
export.objects.link(wall)
bpy.ops.wm.save_as_mainfile(filepath=str(output))
'''
        created = subprocess.run(
            [
                str(BLENDER),
                "--background",
                "--factory-startup",
                "--python-expr",
                script,
                "--",
                str(path),
                str(wall_height),
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
            timeout=180,
        )
        assert created.returncode == 0, created.stdout + created.stderr

    source = tmp_path / "wall.blend"
    staging = tmp_path / "staging"
    create_source(source, 3.2)
    valid = subprocess.run(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python-exit-code",
            "1",
            "--python",
            str(SCRIPT),
            "--",
            "--blend-path",
            str(source),
            "--staging-dir",
            str(staging),
            "--project-root",
            str(PROJECT_ROOT),
            "--module",
            "wall_straight_1x1",
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
        timeout=300,
    )
    assert valid.returncode == 0, valid.stdout + valid.stderr
    final_glb = staging / "wall_straight_1x1.glb"
    assert final_glb.is_file()
    assert final_glb.read_bytes()[:4] == b"glTF"

    previous = final_glb.read_bytes()
    invalid_source = tmp_path / "invalid-wall.blend"
    create_source(invalid_source, 3.3)
    invalid = subprocess.run(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python-exit-code",
            "1",
            "--python",
            str(SCRIPT),
            "--",
            "--blend-path",
            str(invalid_source),
            "--staging-dir",
            str(staging),
            "--project-root",
            str(PROJECT_ROOT),
            "--module",
            "wall_straight_1x1",
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
        timeout=300,
    )
    assert invalid.returncode != 0
    assert "validation" in (invalid.stdout + invalid.stderr).lower()
    assert final_glb.read_bytes() == previous
    assert not list(staging.glob(".*.tmp.glb"))
