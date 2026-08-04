from __future__ import annotations

import math
from pathlib import Path

import pytest

from tools import focused_nine_contract as contract


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _valid_asset(*, asset_id: str = "floor_1x1", kind: str = "structural") -> dict:
    return {
        "asset_id": asset_id,
        "kind": kind,
        "source_path": f"res://assets/imported/{kind}/{asset_id}.glb",
        "staged_glbs": [
            f"res://assets/_staging/focused_nine/{kind}/{asset_id}/{asset_id}.glb"
        ],
        "metrics": {
            "sha256": "a" * 64,
            "byte_size": 128,
            "mesh_count": 1,
            "triangle_count": 12,
            "material_names": ["MAT_PaintedAlloyGray"],
            "bounds": {
                "local_min_m": [0.0, 0.0, 0.0],
                "local_max_m": [1.0, 1.0, 1.0],
            },
        },
        "validation": [],
        "pass": True,
        "first_error": None,
    }


def _valid_report() -> dict:
    return {
        "schema_version": "1.0.0",
        "document_kind": "focused_nine_comparison",
        "assets": [_valid_asset()],
        "baseline": {"asset_count": 1},
        "improved": {"asset_count": 1},
        "preview": {"path": "res://assets/_staging/focused_nine/preview.png"},
        "overall_pass": True,
    }


def test_focused_nine_ids_are_exact_and_disjoint() -> None:
    assert contract.STRUCTURAL_IDS == (
        "floor_1x1",
        "wall_straight_1x1",
        "doorway_frame_open_1x1",
        "pillar_support_1x1",
        "ramp_up_1x2",
        "ceiling_cap_1x1",
        "pressure_door_1x1",
    )
    assert contract.PROP_IDS == (
        "hull_breach_seal_point",
        "fire_suppression_station",
    )
    assert set(contract.STRUCTURAL_IDS).isdisjoint(contract.PROP_IDS)


def test_variant_roles_are_exact_for_pressure_door_and_default_intact_elsewhere() -> None:
    assert contract.VARIANT_ROLES == {
        "pressure_door_1x1": ("intact", "damaged", "breached")
    }
    assert contract.VARIANT_ROLES.get("floor_1x1", ("intact",)) == ("intact",)
    assert contract.VARIANT_ROLES["pressure_door_1x1"] == (
        "intact",
        "damaged",
        "breached",
    )


def test_candidate_paths_stay_inside_focused_nine_staging(tmp_path: Path) -> None:
    assert contract.asset_stage_dir(tmp_path, "pressure_door_1x1") == (
        tmp_path / "assets/_staging/focused_nine/structural/pressure_door_1x1"
    )
    assert contract.asset_stage_glb(tmp_path, "pressure_door_1x1", "damaged") == (
        tmp_path
        / "assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1_damaged.glb"
    )
    assert contract.asset_stage_glb(tmp_path, "hull_breach_seal_point") == (
        tmp_path
        / "assets/_staging/focused_nine/props/hull_breach_seal_point.glb"
    )
    assert contract.comparison_report_path(tmp_path) == (
        tmp_path / "assets/_staging/focused_nine/focused-nine-comparison.json"
    )


@pytest.mark.parametrize(
    "asset_id,role",
    [
        ("unknown", "intact"),
        ("../floor_1x1", "intact"),
        ("pressure_door_1x1", "unknown"),
        ("floor_1x1", "damaged"),
        ("hull_breach_seal_point", "damaged"),
    ],
)
def test_unknown_asset_ids_invalid_roles_and_traversal_are_rejected(
    tmp_path: Path, asset_id: str, role: str
) -> None:
    with pytest.raises(ValueError):
        contract.asset_stage_glb(tmp_path, asset_id, role)


def test_stage_paths_reject_a_symlink_that_escapes_project_root(tmp_path: Path) -> None:
    outside = tmp_path.parent / f"{tmp_path.name}-outside"
    outside.mkdir()
    (tmp_path / "assets").symlink_to(outside, target_is_directory=True)

    with pytest.raises(ValueError, match="escapes project root"):
        contract.asset_stage_dir(tmp_path, "floor_1x1")


def test_runtime_mutation_paths_are_exactly_the_live_surfaces(tmp_path: Path) -> None:
    assert contract.runtime_mutation_paths(tmp_path) == (
        tmp_path / "assets/imported",
        tmp_path / "data/props/visual_bindings.generated.json",
        tmp_path / "data/kits/ship_structural_v0.json",
        tmp_path / "scenes/wrappers/structural/ship_structural_v0",
    )


def test_valid_report_has_no_schema_errors() -> None:
    assert contract.validate_report(_valid_report()) == []


def test_report_root_fields_are_exact_and_required() -> None:
    document = _valid_report()
    document["unexpected"] = True
    del document["preview"]

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert any("root missing field: preview" in error for error in errors)
    assert any("unknown root field: unexpected" in error for error in errors)


def test_report_asset_and_metric_fields_are_required() -> None:
    document = _valid_report()
    del document["assets"][0]["first_error"]
    del document["assets"][0]["metrics"]["bounds"]

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert any("asset[0] missing field: first_error" in error for error in errors)
    assert any("asset[0].metrics missing field: bounds" in error for error in errors)


def test_report_rejects_unknown_ids_bad_kinds_and_nonfinite_values() -> None:
    document = _valid_report()
    document["assets"][0]["asset_id"] = "floor_1x1"
    document["assets"][0]["kind"] = "prop"
    document["assets"].append(_valid_asset(asset_id="not_registered"))
    document["assets"][0]["metrics"]["triangle_count"] = math.nan
    document["assets"][0]["metrics"]["bounds"]["local_max_m"][1] = math.inf

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert any("unknown asset_id" in error for error in errors)
    assert any("kind does not match registered asset" in error for error in errors)
    assert any("non-finite value" in error for error in errors)


def test_report_rejects_invalid_metric_shapes_and_types() -> None:
    document = _valid_report()
    metrics = document["assets"][0]["metrics"]
    metrics["sha256"] = "not-a-sha"
    metrics["byte_size"] = -1
    metrics["mesh_count"] = True
    metrics["triangle_count"] = 1.5
    metrics["material_names"] = ["MAT_OK", 3]
    metrics["bounds"] = {"local_min_m": [0.0], "local_max_m": [1.0, 1.0, 1.0]}

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert any("sha256" in error for error in errors)
    assert any("byte_size" in error for error in errors)
    assert any("mesh_count" in error for error in errors)
    assert any("triangle_count" in error for error in errors)
    assert any("material_names" in error for error in errors)
    assert any("bounds" in error for error in errors)


def test_report_rejects_nonfinite_values_anywhere() -> None:
    document = _valid_report()
    document["preview"]["camera_yaw"] = float("-inf")

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert any("preview.camera_yaw contains non-finite value" in error for error in errors)
