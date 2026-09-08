from __future__ import annotations

from pathlib import Path

import pytest

from tools.blender_addons.structural_module_toolkit import export as export_module


class _Scene(dict):
    pass


class _Object:
    type = "MESH"

    def __init__(self, name: str):
        self.name = name
        self.selected = False

    def select_set(self, value: bool) -> None:
        self.selected = value


class _Collection(dict):
    def __init__(self, name: str, objects: list[_Object], role: str):
        super().__init__(variant_role=role)
        self.name = name
        self.objects = objects


class _CollectionMap(list):
    def get(self, name: str):
        return next((collection for collection in self if collection.name == name), None)


class _ObjectMap(list):
    def get(self, name: str):
        return next((obj for obj in self if obj.name == name), None)


class _Bpy:
    def __init__(self, collections: list[_Collection], *, cancelled: bool = False):
        self.context = type("Context", (), {})()
        self.context.scene = _Scene(module_id="floor_1x1")
        self.context.view_layer = type("ViewLayer", (), {})()
        self.context.view_layer.objects = type("Objects", (), {"active": None})()
        objects = [obj for collection in collections for obj in collection.objects]
        self.data = type("Data", (), {})()
        self.data.collections = _CollectionMap(collections)
        self.data.objects = _ObjectMap(objects)
        self.ops = type("Ops", (), {})()
        self.ops.object = type("ObjectOps", (), {})()
        self.ops.object.select_all = lambda action: [
            obj.select_set(False) for obj in objects
        ]
        self.ops.export_scene = type("ExportOps", (), {})()
        self.ops.export_scene.gltf = self._export
        self.cancelled = cancelled

    def _export(self, *, filepath: str, **_kwargs):
        if self.cancelled:
            return {"CANCELLED"}
        path = Path(filepath)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"glTF" + path.name.encode("ascii"))
        return {"FINISHED"}


def _collections() -> list[_Collection]:
    return [
        _Collection("Export_intact", [_Object("intact")], "intact"),
        _Collection("Export_damaged", [_Object("damaged")], "damaged"),
    ]


def test_export_validates_every_variant_before_publishing(tmp_path, monkeypatch):
    bpy = _Bpy(_collections())
    calls: list[tuple[Path, Path, Path]] = []
    project_root = tmp_path / "project"
    dimensions = project_root / "data" / "art" / "structural_visual_dimensions.v1.json"

    def validate(path, module_id, root, policy, **_kwargs):
        calls.append((Path(path), Path(root), Path(policy)))
        assert module_id == "floor_1x1"
        return {"status": "pass", "errors": []}

    monkeypatch.setattr(export_module, "_validate_with_fresh_blender", validate)

    exported = export_module.export_scene_to_staging(
        bpy,
        tmp_path / "stage",
        "floor_1x1",
        project_root=project_root,
        dimensions=dimensions,
    )

    assert sorted(path.name for path in exported) == ["floor_1x1.glb", "floor_1x1_damaged.glb"]
    assert len(calls) == 2
    assert {path.name for path, _root, _policy in calls} == {
        ".floor_1x1.tmp.glb",
        ".floor_1x1_damaged.tmp.glb",
    }
    assert all(root == project_root.resolve() for _path, root, _policy in calls)
    assert all(policy == dimensions for _path, _root, policy in calls)
    assert all(path.is_file() for path in exported)
    assert not list(exported[0].parent.glob(".*.tmp.glb"))


def test_failed_variant_preserves_all_previous_staged_bytes(tmp_path, monkeypatch):
    bpy = _Bpy(_collections())
    stage = tmp_path / "stage"
    final_paths = [
        stage / "floor_1x1" / "floor_1x1.glb",
        stage / "floor_1x1" / "floor_1x1_damaged.glb",
    ]
    for path, contents in zip(final_paths, (b"old-intact", b"old-damaged")):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)
    before = {path: path.read_bytes() for path in final_paths}
    calls: list[Path] = []

    def validate(path, *_args, **_kwargs):
        calls.append(Path(path))
        if Path(path).name == ".floor_1x1_damaged.tmp.glb":
            raise ValueError("fresh Blender GLB validation failed: geometry mismatch")
        return {"status": "pass"}

    monkeypatch.setattr(export_module, "_validate_with_fresh_blender", validate)

    with pytest.raises(ValueError, match="geometry mismatch"):
        export_module.export_scene_to_staging(bpy, stage, "floor_1x1")

    assert len(calls) == 2
    assert {path.read_bytes() for path in final_paths} == set(before.values())
    assert all(path.read_bytes() == contents for path, contents in before.items())
    assert not list(final_paths[0].parent.glob(".*.tmp.glb"))


def test_cancelled_export_never_replaces_previous_staging(tmp_path):
    bpy = _Bpy(_collections(), cancelled=True)
    final = tmp_path / "stage" / "floor_1x1" / "floor_1x1.glb"
    final.parent.mkdir(parents=True, exist_ok=True)
    final.write_bytes(b"old")

    with pytest.raises(RuntimeError, match="cancelled"):
        export_module.export_scene_to_staging(bpy, final.parents[1], "floor_1x1")

    assert final.read_bytes() == b"old"
    assert not list(final.parent.glob(".*.tmp.glb"))


def test_non_pass_validation_status_is_rejected_before_publish(tmp_path, monkeypatch):
    bpy = _Bpy(_collections())
    final = tmp_path / "stage" / "floor_1x1" / "floor_1x1.glb"
    final.parent.mkdir(parents=True, exist_ok=True)
    final.write_bytes(b"old")

    def validate(*_args, **_kwargs):
        return {
            "status": "hold",
            "errors": ["unsupported geometry profile: ramp_up_1x2"],
        }

    monkeypatch.setattr(export_module, "_validate_with_fresh_blender", validate)

    with pytest.raises(ValueError, match="unsupported geometry profile"):
        export_module.export_scene_to_staging(bpy, final.parents[1], "floor_1x1")

    assert final.read_bytes() == b"old"
    assert not list(final.parent.glob(".*.tmp.glb"))
