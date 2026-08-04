from __future__ import annotations

import math
from pathlib import Path

import pytest

from tools import focused_nine_contract as contract


def _valid_asset(*, asset_id: str = "floor_1x1", kind: str = "structural") -> dict:
    staged_root = "res://assets/_staging/focused_nine"
    if asset_id == "pressure_door_1x1":
        staged_glbs = [
            f"{staged_root}/structural/{asset_id}/{asset_id}.glb",
            f"{staged_root}/structural/{asset_id}/{asset_id}_damaged.glb",
            f"{staged_root}/structural/{asset_id}/{asset_id}_breached.glb",
        ]
    elif kind == "prop":
        staged_glbs = [f"{staged_root}/props/{asset_id}.glb"]
    else:
        staged_glbs = [f"{staged_root}/{kind}/{asset_id}/{asset_id}.glb"]
    return {
        "asset_id": asset_id,
        "kind": kind,
        "source_path": f"res://assets/imported/{kind}/{asset_id}.glb",
        "staged_glbs": staged_glbs,
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
    assets = [
        *(_valid_asset(asset_id=asset_id) for asset_id in contract.STRUCTURAL_IDS[:-1]),
        _valid_asset(asset_id="pressure_door_1x1"),
        *(
            _valid_asset(asset_id=asset_id, kind="prop")
            for asset_id in contract.PROP_IDS
        ),
    ]
    return {
        "schema_version": "1.0.0",
        "document_kind": "focused_nine_comparison",
        "assets": assets,
        "baseline": {"asset_count": len(assets)},
        "improved": {"asset_count": len(assets)},
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


def test_report_huge_integer_values_return_deterministic_errors_without_raising() -> None:
    document = _valid_report()
    huge = 10**1000
    bounds = document["assets"][0]["metrics"]["bounds"]
    bounds["local_min_m"][0] = huge
    document["assets"][0]["metrics"]["byte_size"] = huge
    document["baseline"]["huge_metadata_value"] = huge

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "asset[0].metrics.bounds.local_min_m/local_max_m minimum must not exceed maximum" in errors


def test_report_huge_integer_keys_at_root_preview_and_nested_maps_never_raise() -> None:
    document = _valid_report()
    huge_key = 10**5000
    document[huge_key] = math.nan
    document["preview"][huge_key] = math.inf
    document["baseline"]["nested"] = {huge_key: -math.inf}

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "root contains a non-string object key" in errors
    assert "report contains a non-string object key" in errors
    assert "report.<non-string-key> contains non-finite value" in errors
    assert "report.preview contains a non-string object key" in errors
    assert "report.preview.<non-string-key> contains non-finite value" in errors
    assert "report.baseline.nested contains a non-string object key" in errors
    assert "report.baseline.nested.<non-string-key> contains non-finite value" in errors


class _HostileNonStringKey:
    def __hash__(self) -> int:
        return 1

    def __str__(self) -> str:
        raise AssertionError("hostile key was stringified")

    def __repr__(self) -> str:
        raise AssertionError("hostile key was represented")

    def __lt__(self, other: object) -> bool:
        raise AssertionError("hostile key was compared")


def test_report_non_string_keys_are_generic_and_still_traverse_nested_values() -> None:
    document = _valid_report()
    hostile_key = _HostileNonStringKey()
    document["assets"][0][hostile_key] = {"nested": math.inf}
    document["preview"]["nested"] = {hostile_key: {"value": math.nan}}

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "asset[0] contains a non-string object key" in errors
    assert "report.assets[0].<non-string-key>.nested contains non-finite value" in errors
    assert "report.preview.nested contains a non-string object key" in errors
    assert "report.preview.nested.<non-string-key>.value contains non-finite value" in errors


def test_report_bounds_accept_only_canonical_glb_metadata_keys() -> None:
    document = _valid_report()
    document["assets"][0]["metrics"]["bounds"] = {
        "min": [0.0, 0.0, 0.0],
        "max": [1.0, 1.0, 1.0],
    }

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "asset[0].metrics.bounds must contain a min/max 3-vector pair" in errors
    assert "unknown asset[0].metrics.bounds field: min" in errors
    assert "unknown asset[0].metrics.bounds field: max" in errors


def test_report_rejects_unknown_bounds_keys_even_with_canonical_pair() -> None:
    document = _valid_report()
    document["assets"][0]["metrics"]["bounds"]["min"] = [0.0, 0.0, 0.0]

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "unknown asset[0].metrics.bounds field: min" in errors


def test_report_requires_all_nine_registered_assets_exactly_once() -> None:
    document = _valid_report()
    document["assets"] = document["assets"][:-1]
    document["assets"].append(_valid_asset(asset_id="floor_1x1"))

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "assets missing registered asset_id: fire_suppression_station" in errors
    assert "assets duplicate asset_id: floor_1x1" in errors


def test_report_rejects_empty_assets_staged_glbs_and_material_names() -> None:
    document = _valid_report()
    document["assets"] = []
    errors = contract.validate_report(document)
    assert "assets must contain exactly the nine registered assets" in errors

    document = _valid_report()
    document["assets"][0]["staged_glbs"] = []
    document["assets"][0]["metrics"]["material_names"] = []
    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "asset[0].staged_glbs must be a non-empty list of canonical paths" in errors
    assert "asset[0].metrics.material_names must be a non-empty list of non-empty strings" in errors


def test_report_enforces_exact_asset_kinds_and_staged_glb_roles() -> None:
    document = _valid_report()
    pressure_door = document["assets"][6]
    pressure_door["kind"] = "prop"
    pressure_door["staged_glbs"] = [
        "res://assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb"
    ]
    document["assets"][7]["staged_glbs"] = [
        "res://assets/_staging/focused_nine/props/../props/hull_breach_seal_point.glb"
    ]

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "asset[6].kind does not match registered asset" in errors
    assert "asset[6].staged_glbs must exactly match asset_stage_glb roles" in errors
    assert "asset[7].staged_glbs must exactly match asset_stage_glb roles" in errors


def test_report_source_paths_must_be_normalized_project_relative_strings() -> None:
    document = _valid_report()
    document["assets"][0]["source_path"] = "res://assets/imported/structural/../escape.glb"

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "asset[0].source_path must be a normalized project-relative path" in errors


def test_report_nonfinite_scan_is_iterative_cycle_safe_and_deterministic() -> None:
    document = _valid_report()
    nested: dict[str, object] = {}
    cursor = nested
    for _ in range(1100):
        child: dict[str, object] = {}
        cursor["child"] = child
        cursor = child
    cursor["value"] = math.inf
    preview = {"cycle": None, "nested": nested}
    preview["cycle"] = preview
    document["preview"] = preview

    errors = contract.validate_report(document)
    expected = f"report.preview.nested{'.child' * 1100}.value contains non-finite value"

    assert errors == [expected]
    assert errors == contract.validate_report(document)


def test_report_rejects_pass_true_asset_failure_fields() -> None:
    document = _valid_report()
    asset = document["assets"][0]
    asset["validation"] = ["unexpected warning"]
    asset["first_error"] = "unexpected failure"

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "asset[0].validation must be empty when pass is true" in errors
    assert "asset[0].first_error must be null when pass is true" in errors
    assert "overall_pass must be false when any asset has a failure error" in errors


def test_report_rejects_pass_false_asset_without_failure_details() -> None:
    document = _valid_report()
    asset = document["assets"][0]
    asset["validation"] = []
    asset["pass"] = False
    asset["first_error"] = ""
    document["overall_pass"] = False

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "asset[0].validation must be non-empty when pass is false" in errors
    assert "asset[0].first_error must be a non-empty string when pass is false" in errors


def test_report_overall_pass_must_equal_all_asset_pass_values() -> None:
    document = _valid_report()
    document["overall_pass"] = False

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "overall_pass must equal all asset pass values" in errors

    document = _valid_report()
    asset = document["assets"][0]
    asset["validation"] = ["failed validation"]
    asset["pass"] = False
    asset["first_error"] = "failed validation"

    errors = contract.validate_report(document)

    assert errors == sorted(errors)
    assert "overall_pass must equal all asset pass values" in errors
