from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from tools import focused_nine_contract

PROJECT_ROOT = Path(__file__).resolve().parents[1]
BLENDER = Path("/opt/homebrew/bin/blender")
SOURCE_FIXTURE = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/ship_structural_v0/floor_1x1/floor_1x1.blend"
)
MATERIAL_FIXTURE = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/salvage_industrial.blend"
)


def test_registry_is_reused_without_a_second_asset_allowlist() -> None:
    from tools.focused_nine_blender_recipes import (
        PROP_ASSET_IDS,
        STRUCTURAL_ASSET_IDS,
    )

    assert STRUCTURAL_ASSET_IDS == focused_nine_contract.STRUCTURAL_IDS
    assert PROP_ASSET_IDS == focused_nine_contract.PROP_IDS


def test_unknown_asset_is_rejected_before_blender_import() -> None:
    sys.modules.pop("bpy", None)
    from tools.focused_nine_blender_recipes import parse_args, select_asset

    with pytest.raises(ValueError, match="unknown focused-nine asset"):
        select_asset("not_a_focused_nine_asset")
    with pytest.raises(SystemExit):
        parse_args(
            [
                "--project-root",
                ".",
                "--structural-source-root",
                "/tmp/structural",
                "--props-source-root",
                "/tmp/props",
                "--asset-id",
                "unknown",
            ]
        )
    assert "bpy" not in sys.modules


def test_source_paths_are_exact_and_kind_specific(tmp_path: Path) -> None:
    from tools.focused_nine_blender_recipes import source_blend_path, source_path

    structural_root = tmp_path / "structural"
    props_root = tmp_path / "props"
    assert source_blend_path(structural_root, props_root, "floor_1x1") == (
        structural_root / "floor_1x1/floor_1x1.blend"
    )
    assert source_path(structural_root, props_root, "wall_straight_1x1") == (
        structural_root / "wall_straight_1x1/wall_straight_1x1.blend"
    )
    assert source_blend_path(structural_root, props_root, "hull_breach_seal_point") == (
        props_root / "hull_breach_seal_point.blend"
    )
    with pytest.raises(ValueError, match="unknown focused-nine asset"):
        source_blend_path(structural_root, props_root, "../escape")


def test_cli_parser_exposes_the_required_blender_interface() -> None:
    from tools.focused_nine_blender_recipes import parse_args

    args = parse_args(
        [
            "--project-root",
            "/project",
            "--structural-source-root",
            "/structural",
            "--props-source-root",
            "/props",
            "--asset-id",
            "floor_1x1",
            "--overwrite-generated-only",
        ]
    )
    assert args.project_root == Path("/project")
    assert args.structural_source_root == Path("/structural")
    assert args.props_source_root == Path("/props")
    assert args.asset_id == "floor_1x1"
    assert args.overwrite_generated_only is True


def test_compatibility_wrapper_delegates_without_scene_wide_or_boolean_operations() -> None:
    wrapper = (PROJECT_ROOT / "tools/improve_floor_geometry.py").read_text(encoding="utf-8")
    assert "focused_nine_blender_recipes" in wrapper
    assert "select_all" not in wrapper
    assert "BOOLEAN" not in wrapper
    assert "bpy.ops.object.delete" not in wrapper


def _report_from_stdout(stdout: str) -> tuple[dict, str]:
    reports = []
    for line in stdout.splitlines():
        if line.startswith("FOCUSED_NINE_REPORT "):
            reports.append(json.loads(line.removeprefix("FOCUSED_NINE_REPORT ")))
    assert len(reports) == 1, stdout
    report_line = next(
        line for line in stdout.splitlines() if line.startswith("FOCUSED_NINE_REPORT ")
    )
    return reports[0], report_line


def test_blender_floor_recipe_is_idempotent_and_source_scoped(tmp_path: Path) -> None:
    if not BLENDER.is_file():
        pytest.fail(f"Blender 5.2 executable missing: {BLENDER}")
    if not SOURCE_FIXTURE.is_file():
        pytest.fail(f"source fixture missing: {SOURCE_FIXTURE}")
    if not MATERIAL_FIXTURE.is_file():
        pytest.fail(f"material fixture missing: {MATERIAL_FIXTURE}")
    source_fixture_bytes = SOURCE_FIXTURE.read_bytes()

    structural_root = tmp_path / "structural"
    source_dir = structural_root / "floor_1x1"
    source_dir.mkdir(parents=True)
    source_blend = source_dir / "floor_1x1.blend"
    shutil.copy2(SOURCE_FIXTURE, source_blend)
    material_dir = structural_root.parent / "materials"
    material_dir.mkdir(parents=True)
    shutil.copy2(MATERIAL_FIXTURE, material_dir / "salvage_industrial.blend")
    props_root = tmp_path / "props"
    props_root.mkdir()

    command = [
        str(BLENDER),
        "--background",
        "--factory-startup",
        "--python",
        str(PROJECT_ROOT / "tools/focused_nine_blender_recipes.py"),
        "--",
        "--project-root",
        str(PROJECT_ROOT),
        "--structural-source-root",
        str(structural_root),
        "--props-source-root",
        str(props_root),
        "--asset-id",
        "floor_1x1",
        "--overwrite-generated-only",
    ]
    first = subprocess.run(command, capture_output=True, text=True, check=False)
    assert first.returncode == 0, first.stdout + first.stderr
    first_report, first_report_line = _report_from_stdout(first.stdout)

    second = subprocess.run(command, capture_output=True, text=True, check=False)
    assert second.returncode == 0, second.stdout + second.stderr
    second_report, second_report_line = _report_from_stdout(second.stdout)

    assert first_report == second_report
    assert first_report_line == second_report_line

    assert first_report["asset_id"] == "floor_1x1"
    assert first_report["helper_names"] == [
        "Export_intact",
    ]
    assert first_report["generated_object_names"]
    assert all(
        name.startswith("FocusedNine_floor_1x1_")
        for name in first_report["generated_object_names"]
    )
    assert first_report["generated_count"] == len(first_report["generated_object_names"])
    assert first_report["triangle_count"] > 0
    assert first_report["boolean_modifiers"] == []
    assert "BOOLEAN" not in first_report["modifier_types"]
    assert SOURCE_FIXTURE.read_bytes() == source_fixture_bytes
