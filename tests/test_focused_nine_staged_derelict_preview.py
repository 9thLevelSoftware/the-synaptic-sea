from __future__ import annotations

import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

from tools import focused_nine_staged_derelict_preview as preview

PROJECT_ROOT = Path(__file__).resolve().parents[1]
STAGING_RELATIVE = Path("assets/_staging/focused_nine")
PREVIEW_RELATIVE = Path("artifacts/validation-previews/focused-nine")
PROOF_RELATIVE = Path("docs/superpowers/proofs/focused-nine-staged-derelict.md")
IMAGE_NAME = "focused-nine-staged-derelict.png"


def _args(project: Path, *, dry_run: bool = False) -> list[str]:
    values = [
        "--project-root",
        str(project),
        "--staging-root",
        str(project / STAGING_RELATIVE),
        "--preview-dir",
        str(project / PREVIEW_RELATIVE),
        "--proof",
        str(project / PROOF_RELATIVE),
    ]
    if dry_run:
        values.append("--dry-run")
    return values


def _project_fixture(tmp_path: Path) -> Path:
    project = tmp_path / "project"
    project.mkdir()
    shutil.copytree(
        PROJECT_ROOT / STAGING_RELATIVE,
        project / STAGING_RELATIVE,
        copy_function=shutil.copy2,
    )
    contract_path = project / "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
    contract_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        PROJECT_ROOT / "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json",
        contract_path,
    )
    wrapper = project / "scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn"
    wrapper.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        PROJECT_ROOT / "scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn",
        wrapper,
    )
    return project


def _namespace_args(project: Path, *, dry_run: bool = False):
    return preview.parse_args(_args(project, dry_run=dry_run))


def test_parse_args_rejects_runtime_staging_alias_and_traversal(tmp_path: Path) -> None:
    project = tmp_path / "project"
    project.mkdir()
    with pytest.raises(SystemExit):
        preview.parse_args(
            [
                "--project-root",
                str(project),
                "--staging-root",
                str(project / "assets/imported"),
                "--preview-dir",
                str(project / PREVIEW_RELATIVE),
                "--proof",
                str(project / PROOF_RELATIVE),
            ]
        )
    with pytest.raises(SystemExit):
        preview.parse_args(_args(project / ".." / "project"))


def test_preflight_requires_all_staged_focused_nine_inputs(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    (project / STAGING_RELATIVE / "structural/pressure_door_1x1/pressure_door_1x1_breached.glb").unlink()
    with pytest.raises(ValueError, match="pressure-door|staged input"):
        preview.validate_inputs(_namespace_args(project))


def test_overlay_uses_regular_staged_glbs_at_canonical_import_paths(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    inputs = preview.validate_inputs(_namespace_args(project))
    overlay = tmp_path / "overlay"
    preview._build_overlay(project, inputs, overlay)
    try:
        imported_floor = overlay / "assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb"
        staged_floor = project / STAGING_RELATIVE / "structural/floor_1x1/floor_1x1.glb"
        assert imported_floor.is_file()
        assert not imported_floor.is_symlink()
        assert imported_floor.read_bytes() == staged_floor.read_bytes()
        wrapper = overlay / "scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn"
        assert "res://assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb" in wrapper.read_text()
        assert "assets/_staging/focused_nine" not in wrapper.read_text()
    finally:
        shutil.rmtree(overlay)


def test_capture_output_rejects_diagnostics_even_with_pass_marker(tmp_path: Path) -> None:
    wrapper = tmp_path / "capture.py"
    wrapper.write_text(
        "print('FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS seed=17 rooms=5 wrappers=5')\n"
        "print('WARNING: injected')\n",
        encoding="utf-8",
    )
    ok, detail, metadata = preview._run_capture_process(
        [sys.executable, str(wrapper)], cwd=tmp_path, timeout=3
    )
    assert not ok
    assert "WARNING:" in detail
    assert metadata is None


def test_bounded_process_timeout_kills_process_group(tmp_path: Path) -> None:
    wrapper = tmp_path / "sleep.py"
    wrapper.write_text("import time\ntime.sleep(30)\n", encoding="utf-8")
    started = time.monotonic()
    with pytest.raises(preview.CaptureTimeout):
        preview._run_bounded_process([sys.executable, str(wrapper)], timeout=0.1, label="test")
    assert time.monotonic() - started < 3


def test_proof_contains_seed_room_and_staged_wrapper_evidence(tmp_path: Path) -> None:
    proof = preview.build_proof(
        output_path=tmp_path / IMAGE_NAME,
        dimensions=(1600, 900),
        seed=17,
        room_count=5,
        staged_wrapper_count=12,
        staged_input_count=17,
        marker="FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS seed=17 rooms=5 wrappers=12 staged=17",
    )
    assert "seed=17" in proof
    assert "room_count=5" in proof
    assert "staged_wrapper_count=12" in proof
    assert "staged_input_count=17" in proof
    assert "No runtime promotion occurred" in proof


def test_capture_scene_source_uses_direct_viewport_texture_and_staged_generator_contract() -> None:
    script = PROJECT_ROOT / "scripts/validation/focused_nine_staged_derelict_capture.gd"
    scene = PROJECT_ROOT / "scenes/validation/focused_nine_staged_derelict_harness.tscn"
    assert script.is_file()
    assert scene.is_file()
    text = script.read_text(encoding="utf-8")
    assert "get_viewport().get_root()" not in text
    assert "get_viewport()" in text
    assert "get_texture()" in text
    assert "ShipGenerator" in text
    assert "StagedFocusedNine" in text
    assert "FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS" in text


def test_dry_run_does_not_build_overlay_or_write_outputs(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = _project_fixture(tmp_path)
    args = _namespace_args(project, dry_run=True)
    monkeypatch.setattr(
        preview,
        "_build_overlay",
        lambda *_args: (_ for _ in ()).throw(AssertionError("dry-run built overlay")),
    )
    result = preview.run(args)
    assert result.exit_code == 0
    assert result.dry_run
    assert not (project / PREVIEW_RELATIVE).exists()
    assert not (project / PROOF_RELATIVE).exists()


def test_runtime_snapshot_mismatch_blocks_publication(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = _project_fixture(tmp_path)
    args = _namespace_args(project)
    monkeypatch.setattr(preview, "validate_inputs", lambda _args: preview.ValidatedInputs(()))
    monkeypatch.setattr(preview, "_run_capture_process", lambda *_args, **_kwargs: (False, "synthetic stop", None))
    snapshots = iter([("before",), ("after",)])
    monkeypatch.setattr(preview, "snapshot_runtime_surfaces", lambda _root: next(snapshots))
    result = preview.run(args)
    assert result.exit_code == 1
    assert "runtime surface mismatch" in result.reason


def test_png_dimension_validation_requires_real_1600x900_png(tmp_path: Path) -> None:
    image = tmp_path / IMAGE_NAME
    image.write_bytes(b"\x89PNG\r\n\x1a\ninvalid")
    with pytest.raises(ValueError, match="PNG|1600x900"):
        preview._validate_capture_image(image)
