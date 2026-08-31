from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from tools.meshy_asset_contract import load_contract
from tools.meshy_blender_master import (
    BLENDER_PATH,
    build_blender_command,
    derive_master_path,
    reject_protected_output_path,
)
from tools.meshy_blender_validate import (
    build_parser as build_validate_parser,
    check_dimensions,
    check_triangle_budget,
    validate_cleaned_glb,
    write_validation_report,
)
from tools.meshy_blender_master import build_parser as build_master_parser

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures/meshy_blender"
CONTRACT_PATH = FIXTURES / "fixture_contract.json"
GLB_PATH = FIXTURES / "fixture_triangle.glb"
MASTER_SCRIPT = ROOT / "tools/meshy_blender_master.py"
ASSET_ID = "fixture_triangle"


@pytest.fixture()
def contract():
    return load_contract(CONTRACT_PATH)


def test_master_derives_correct_blend_path() -> None:
    assert derive_master_path(ASSET_ID) == Path(
        "/Volumes/Untitled/SynapticSeaAssets/meshy/source/"
        "fixture_triangle/fixture_triangle_master.blend"
    )


def test_master_rejects_protected_output_path(tmp_path: Path) -> None:
    protected = tmp_path / "assets/imported" / "fixture_triangle_master.blend"

    with pytest.raises(ValueError, match="protected"):
        reject_protected_output_path(protected, project_root=tmp_path)


def test_master_constructs_blender_command(tmp_path: Path) -> None:
    contract_path = tmp_path / "contract.json"
    task_dir = tmp_path / "task"
    command = build_blender_command(
        project_root=tmp_path,
        contract=contract_path,
        task_dir=task_dir,
        reviewer="operator",
    )

    assert command == [
        BLENDER_PATH,
        "--background",
        "--factory-startup",
        "--python",
        str(MASTER_SCRIPT),
        "--",
        "--project-root",
        str(tmp_path),
        "--contract",
        str(contract_path),
        "--task-dir",
        str(task_dir),
        "--reviewer",
        "operator",
    ]


def test_validate_rejects_missing_glb(contract, tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="does not exist"):
        validate_cleaned_glb(tmp_path / "missing.glb", contract)


def test_validate_rejects_non_glb_file(contract, tmp_path: Path) -> None:
    path = tmp_path / "not-a-glb.glb"
    path.write_bytes(b"not a glb")

    with pytest.raises(ValueError, match="GLB"):
        validate_cleaned_glb(path, contract)


def test_validate_report_has_required_fields(contract, tmp_path: Path) -> None:
    report = validate_cleaned_glb(GLB_PATH, contract)
    report_path = tmp_path / "blender-validation.json"
    write_validation_report(report_path, report)

    persisted = json.loads(report_path.read_text(encoding="utf-8"))
    assert {
        "sha256",
        "byte_size",
        "mesh_count",
        "material_names",
        "triangle_count",
        "bounds",
    } <= set(persisted)
    assert persisted["sha256"] == hashlib.sha256(GLB_PATH.read_bytes()).hexdigest()
    assert persisted["byte_size"] == GLB_PATH.stat().st_size
    assert persisted["mesh_count"] == 1
    assert persisted["triangle_count"] == 1
    assert persisted["material_names"] == []
    assert persisted["bounds"]["min"] == [0.0, 0.0, 0.0]
    assert persisted["bounds"]["max"] == [1.0, 1.0, 0.0]
    assert report_path.read_bytes().endswith(b"\n")


def test_validate_dimensions_within_tolerance() -> None:
    assert check_dimensions([1.0, 2.0, 3.0], [1.01, 2.0, 3.0], 0.01)
    assert not check_dimensions([1.0, 2.02, 3.0], [1.01, 2.0, 3.0], 0.01)


def test_validate_triangle_budget() -> None:
    assert check_triangle_budget(3, 3)
    assert check_triangle_budget(3, {"min": 1, "max": 3, "scope": "whole_asset"})
    assert not check_triangle_budget(4, 3)


def test_cli_master_requires_all_args() -> None:
    with pytest.raises(SystemExit):
        build_master_parser().parse_args([])


def test_cli_validate_requires_all_args() -> None:
    with pytest.raises(SystemExit):
        build_validate_parser().parse_args([])
