import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).parents[1]
MODULE_PATH = ROOT / "tools" / "build_dock_collision_projection.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("dock_collision_projection", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _write_fixture(root: Path, *, shape_type: str = "BoxShape3D", duplicate: bool = False,
                   unsupported_transform: bool = False,
                   transform_value: str | None = None) -> Path:
    wrapper = root / "scenes/wrappers/fixture.tscn"
    wrapper.parent.mkdir(parents=True)
    extra = "\n[node name=\"Shape\" type=\"CollisionShape3D\" parent=\"CollisionRoot/Carrier\"]\nshape = SubResource(\"Shape\")\n" if duplicate else ""
    transform = transform_value or (
        "scale = Vector3(2, 1, 1)" if unsupported_transform else
        "transform = Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, 2, 1.5, 0)")
    wrapper.write_text(
        "[gd_scene load_steps=2 format=3]\n\n"
        f"[sub_resource type=\"{shape_type}\" id=\"Shape\"]\n"
        "size = Vector3(4, 3, 0.2)\n\n"
        "[node name=\"Root\" type=\"Node3D\"]\n\n"
        "[node name=\"CollisionRoot\" type=\"StaticBody3D\" parent=\".\"]\n\n"
        "[node name=\"Carrier\" type=\"Node3D\" parent=\"CollisionRoot\"]\n"
        "position = Vector3(1, 0, 0)\n\n"
        "[node name=\"Shape\" type=\"CollisionShape3D\" parent=\"CollisionRoot/Carrier\"]\n"
        f"{transform}\n"
        "shape = SubResource(\"Shape\")\n"
        f"{extra}",
        encoding="utf-8",
    )
    contract = root / "data/contracts/fixture.tres"
    contract.parent.mkdir(parents=True)
    contract.write_text(
        '[gd_resource type="Resource" format=3]\n'
        'wrapper_scene = "res://scenes/wrappers/fixture.tscn"\n',
        encoding="utf-8",
    )
    kit = root / "data/kits/fixture.json"
    kit.parent.mkdir(parents=True)
    kit.write_text(json.dumps({
        "schema_version": "1.0.0",
        "document_kind": "ship_structural_catalog",
        "kit_id": "fixture",
        "modules": [{
            "module_id": "fixture_box",
            "godot_wrapper_scene": "res://scenes/wrappers/fixture.tscn",
            "godot_contract": "res://data/contracts/fixture.tres",
        }],
    }, indent=2) + "\n", encoding="utf-8")
    return kit


def test_real_selected_wrappers_have_exact_projected_boxes():
    projection = _load_module().build_projection(ROOT, ROOT / "data/kits/ship_structural_v0.json")

    assert projection["schema_version"] == "dock-collision-projection-v1"
    assert projection["numeric_encoding"] == "ieee754-binary32-bits-v1"
    assert list(projection["modules"]) == sorted(projection["modules"])
    assert len(projection["modules"]) == 15
    doorway = projection["modules"]["doorway_frame_open_1x1"]
    assert [box["shape_path"] for box in doorway["boxes"]] == [
        "CollisionRoot/CollisionShape3D_Header",
        "CollisionRoot/CollisionShape3D_PostEast",
        "CollisionRoot/CollisionShape3D_PostWest",
    ]
    assert doorway["boxes"][0]["dimensions"] == [4.0, 1.0, 0.20000000298023224]
    assert doorway["boxes"][0]["dimensions_f32_bits"] == [
        "40800000", "3f800000", "3e4ccccd"]
    assert doorway["boxes"][0]["origin"] == [0.0, 2.700000047683716, 0.0]
    corner = projection["modules"]["wall_inner_corner"]
    assert corner["boxes"][0]["basis"] == [0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0]
    assert corner["boxes"][0]["origin"] == [2.0, 1.5, 0.0]
    ceiling = projection["modules"]["ceiling_cap_1x1"]["boxes"]
    assert ceiling == [{
        "shape_path": "CollisionRoot/CollisionShape3D",
        "basis": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0],
        "basis_f32_bits": [
            "3f800000", "00000000", "00000000",
            "00000000", "3f800000", "00000000",
            "00000000", "00000000", "3f800000",
        ],
        "origin": [0.0, 3.9000000953674316, 0.0],
        "origin_f32_bits": ["00000000", "4079999a", "00000000"],
        "dimensions": [4.0, 0.20000000298023224, 4.0],
        "dimensions_f32_bits": ["40800000", "3e4ccccd", "40800000"],
    }]
    for module in projection["modules"].values():
        for box in module["boxes"]:
            assert all(value in (-1.0, 0.0, 1.0) for value in box["basis"])


def test_projection_composes_parent_and_shape_transforms(tmp_path: Path):
    kit = _write_fixture(tmp_path)
    box = _load_module().build_projection(tmp_path, kit)["modules"]["fixture_box"]["boxes"][0]

    assert box["shape_path"] == "CollisionRoot/Carrier/Shape"
    assert box["basis"] == [0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0]
    assert box["origin"] == [3.0, 1.5, 0.0]
    assert box["dimensions"] == [4.0, 3.0, 0.20000000298023224]


def test_projection_preserves_finite_non_cardinal_basis(tmp_path: Path):
    kit = _write_fixture(
        tmp_path,
        transform_value=(
            "transform = Transform3D(0.7071067811865476, 0, -0.7071067811865475, "
            "0, 1, 0, 0.7071067811865475, 0, 0.7071067811865476, 2, 1.5, 0)"),
    )
    box = _load_module().build_projection(tmp_path, kit)["modules"]["fixture_box"]["boxes"][0]

    assert box["basis"] == [
        0.7071067690849304, 0.0, 0.7071067690849304,
        0.0, 1.0, 0.0,
        -0.7071067690849304, 0.0, 0.7071067690849304,
    ]
    assert box["basis_f32_bits"] == [
        "3f3504f3", "00000000", "3f3504f3",
        "00000000", "3f800000", "00000000",
        "bf3504f3", "00000000", "3f3504f3",
    ]
    assert box["origin"] == [3.0, 1.5, 0.0]


def test_projection_rejects_finite_value_outside_binary32_range(tmp_path: Path):
    kit = _write_fixture(
        tmp_path,
        transform_value=(
            "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 3.5e38, 0, 0)"),
    )
    module = _load_module()

    with pytest.raises(module.ProjectionError, match="binary32 range"):
        module.build_projection(tmp_path, kit)


def test_existing_projection_rejects_stale_wrapper_hash(tmp_path: Path):
    kit_path = _write_fixture(tmp_path)
    module = _load_module()
    kit = json.loads(kit_path.read_text(encoding="utf-8"))
    kit["dock_collision_projection_v1"] = module.build_projection(tmp_path, kit_path)
    kit_path.write_text(json.dumps(kit, indent=2) + "\n", encoding="utf-8")
    wrapper = tmp_path / "scenes/wrappers/fixture.tscn"
    wrapper.write_text(wrapper.read_text(encoding="utf-8") + "\n# changed\n", encoding="utf-8")

    with pytest.raises(module.ProjectionError, match="stale wrapper hash"):
        module.check_projection(tmp_path, kit_path)


@pytest.mark.parametrize(
    ("fixture_args", "reason"),
    [
        ({"shape_type": "CapsuleShape3D"}, "unsupported shape"),
        ({"duplicate": True}, "duplicate collision shape path"),
        ({"unsupported_transform": True}, "unsupported transform property"),
    ],
)
def test_projection_rejects_unsupported_or_ambiguous_wrapper_data(
        tmp_path: Path, fixture_args: dict, reason: str):
    kit = _write_fixture(tmp_path, **fixture_args)
    module = _load_module()

    with pytest.raises(module.ProjectionError, match=reason):
        module.build_projection(tmp_path, kit)


def test_write_preserves_kit_fields_and_check_is_deterministic(tmp_path: Path):
    kit_path = _write_fixture(tmp_path)
    module = _load_module()
    before = json.loads(kit_path.read_text(encoding="utf-8"))

    module.write_projection(tmp_path, kit_path)
    first = kit_path.read_bytes()
    module.check_projection(tmp_path, kit_path)
    module.write_projection(tmp_path, kit_path)

    after = json.loads(kit_path.read_text(encoding="utf-8"))
    assert kit_path.read_bytes() == first
    assert {key: value for key, value in after.items() if key != "dock_collision_projection_v1"} == before
