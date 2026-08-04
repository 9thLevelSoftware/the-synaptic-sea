from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from tools.prop_visual_metadata import validate_sidecar
from tools.focused_nine_staged_props import (
    build_staged_sidecar,
    validate_staged_sidecar,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
FIXTURE_GLB = PROJECT_ROOT / "assets/imported/props/components/reactor_console.glb"
STAGING_RELATIVE = Path("assets/_staging/focused_nine/props")
ASSET_IDS = ("fire_suppression_station", "hull_breach_seal_point")


@pytest.fixture
def staged_project(tmp_path: Path) -> tuple[Path, dict[str, Path]]:
    project_root = tmp_path / "project"
    staged_root = project_root / STAGING_RELATIVE
    staged_root.mkdir(parents=True)
    staged = {}
    for asset_id in ASSET_IDS:
        path = staged_root / f"{asset_id}.glb"
        shutil.copy2(FIXTURE_GLB, path)
        staged[asset_id] = path
    return project_root, staged


def test_build_staged_sidecar_is_visual_only_and_unbound_from_live_catalog(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project

    for asset_id in ASSET_IDS:
        sidecar = build_staged_sidecar(project_root, staged[asset_id], asset_id)

        assert sidecar["prop_kind"] == "dressing"
        assert sidecar["binding"] == {
            "namespace": "visual_prop_id",
            "ids": [asset_id],
        }
        assert sidecar["collision_policy"] == "none_visual_only"
        assert sidecar["extensions"] == {
            "comparison_role": "objective_prop",
            "staged_visual_only": True,
        }
        assert sidecar["visual_scene_path"] == (
            f"res://assets/_staging/focused_nine/props/{asset_id}.glb"
        )
        assert validate_sidecar(sidecar, staged[asset_id], project_root) == []
        assert validate_staged_sidecar(project_root, staged[asset_id], sidecar) == []


def test_build_staged_sidecar_rejects_runtime_imported_path(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, _staged = staged_project
    runtime_glb = PROJECT_ROOT / "assets/imported/props/objectives/repair_junction.glb"

    with pytest.raises(ValueError, match="focused-nine staging"):
        build_staged_sidecar(project_root, runtime_glb, "hull_breach_seal_point")


def test_validator_reports_non_staged_runtime_path_without_throwing(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project
    sidecar = build_staged_sidecar(project_root, staged["hull_breach_seal_point"], "hull_breach_seal_point")
    runtime_glb = PROJECT_ROOT / "assets/imported/props/objectives/repair_junction.glb"

    errors = validate_staged_sidecar(project_root, runtime_glb, sidecar)

    assert errors == sorted(errors)
    assert any("focused-nine staging" in error for error in errors)


def test_staged_validator_reports_sorted_metadata_and_contract_mutations(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project
    glb_path = staged["hull_breach_seal_point"]
    sidecar = build_staged_sidecar(project_root, glb_path, "hull_breach_seal_point")
    sidecar["binding"] = {"namespace": "component_id", "ids": ["wrong"]}
    sidecar["bounds"]["local_min_m"] = [999.0, 999.0, 999.0]
    sidecar["extensions"] = {
        "comparison_role": "wrong",
        "staged_visual_only": False,
        "unexpected": True,
    }
    sidecar["source"]["sha256"] = "0" * 64

    errors = validate_staged_sidecar(project_root, glb_path, sidecar)

    assert errors == sorted(errors)
    assert "binding must be exactly {'namespace': 'visual_prop_id', 'ids': ['hull_breach_seal_point']}" in errors
    assert "bounds mismatch" in errors
    assert "extensions must be exactly {'comparison_role': 'objective_prop', 'staged_visual_only': True}" in errors
    assert "sha256 mismatch" in errors


def test_staged_validator_rejects_invalid_asset_id_filename_and_missing_file(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project
    valid_path = staged["hull_breach_seal_point"]
    sidecar = build_staged_sidecar(project_root, valid_path, "hull_breach_seal_point")

    wrong_name = project_root / STAGING_RELATIVE / "wrong_name.glb"
    shutil.copy2(FIXTURE_GLB, wrong_name)
    errors = validate_staged_sidecar(project_root, wrong_name, sidecar)
    assert errors == sorted(errors)
    assert any("filename must match asset_id" in error for error in errors)

    missing = project_root / STAGING_RELATIVE / "fire_suppression_station.glb"
    missing.unlink()
    errors = validate_staged_sidecar(project_root, missing, sidecar)
    assert errors == sorted(errors)
    assert any("does not exist" in error for error in errors)

    with pytest.raises(ValueError, match="asset_id must be one of"):
        build_staged_sidecar(project_root, valid_path, "not_a_focused_nine_prop")


def test_staged_validator_rejects_symlink_escape(
    staged_project: tuple[Path, dict[str, Path]], tmp_path: Path
) -> None:
    project_root, staged = staged_project
    sidecar = build_staged_sidecar(project_root, staged["hull_breach_seal_point"], "hull_breach_seal_point")
    escaped = project_root / STAGING_RELATIVE / "fire_suppression_station.glb"
    escaped.unlink()
    outside = tmp_path / "fire_suppression_station.glb"
    shutil.copy2(FIXTURE_GLB, outside)
    escaped.symlink_to(outside)

    errors = validate_staged_sidecar(project_root, escaped, sidecar)

    assert errors == sorted(errors)
    assert any("symlink" in error for error in errors)
    with pytest.raises(ValueError, match="symlink"):
        build_staged_sidecar(project_root, escaped, "fire_suppression_station")


def test_cli_writes_valid_sidecar_atomically(
    staged_project: tuple[Path, dict[str, Path]], tmp_path: Path
) -> None:
    project_root, staged = staged_project
    output = tmp_path / "out" / "hull_breach_seal_point.sidecar.json"

    result = subprocess.run(
        [
            sys.executable,
            str(PROJECT_ROOT / "tools/focused_nine_staged_props.py"),
            "--project-root",
            str(project_root),
            "--glb",
            str(staged["hull_breach_seal_point"]),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(output),
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    sidecar = json.loads(output.read_text(encoding="utf-8"))
    assert validate_staged_sidecar(
        project_root, staged["hull_breach_seal_point"], sidecar
    ) == []
    assert output.read_text(encoding="utf-8").endswith("\n")


def test_cli_preserves_existing_output_when_validation_fails(
    staged_project: tuple[Path, dict[str, Path]], tmp_path: Path
) -> None:
    project_root, _staged = staged_project
    output = tmp_path / "existing.sidecar.json"
    original = b"existing target must remain unchanged\n"
    output.write_bytes(original)
    runtime_glb = PROJECT_ROOT / "assets/imported/props/objectives/repair_junction.glb"

    result = subprocess.run(
        [
            sys.executable,
            str(PROJECT_ROOT / "tools/focused_nine_staged_props.py"),
            "--project-root",
            str(project_root),
            "--glb",
            str(runtime_glb),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(output),
        ],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode != 0
    assert "focused-nine staging" in result.stderr
    assert output.read_bytes() == original
    assert not list(output.parent.glob(f".{output.name}.*.tmp"))
