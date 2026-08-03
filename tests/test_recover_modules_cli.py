from __future__ import annotations

import builtins
import importlib
from pathlib import Path
import subprocess
import sys

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT_ROOT / "tools" / "recover_modules.py"


def _load_recovery_cli():
    return importlib.import_module("tools.recover_modules")


def test_recovery_cli_requires_explicit_project_and_source_roots() -> None:
    recovery_cli = _load_recovery_cli()

    with pytest.raises(SystemExit):
        recovery_cli.parse_args(["--module", "floor_1x1"])


def test_recovery_cli_rejects_unapproved_module_before_blender_import(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    recovery_cli = _load_recovery_cli()
    real_import = builtins.__import__

    def reject_blender_import(name: str, *args: object, **kwargs: object):
        if name == "bpy":
            raise AssertionError("CLI imported Blender before validating module id")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", reject_blender_import)

    with pytest.raises(SystemExit):
        recovery_cli.main(
            [
                "--project-root",
                str(PROJECT_ROOT),
                "--source-root",
                str(tmp_path),
                "--module",
                "not_a_structural_module",
            ]
        )


def test_recovery_cli_expected_error_returns_nonzero_without_traceback(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    """Expected recovery failures should be concise and nonzero."""
    recovery_cli = _load_recovery_cli()

    monkeypatch.setattr(recovery_cli, "_require_bpy", lambda: object())

    def fail_recovery(args: object, module_id: str) -> dict[str, object]:
        raise FileExistsError("output already exists")

    monkeypatch.setattr(recovery_cli, "recover_one", fail_recovery)

    result = recovery_cli.main(
        [
            "--project-root",
            str(PROJECT_ROOT),
            "--source-root",
            str(tmp_path),
            "--module",
            "floor_1x1",
        ]
    )

    assert result == 1
    captured = capsys.readouterr()
    assert captured.err == "ERROR: output already exists\n"
    assert "Traceback" not in captured.err


def test_recovery_cli_dry_run_prints_paths_without_blender(tmp_path: Path) -> None:
    """--dry-run should work without importing bpy."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--",
         "--project-root", str(PROJECT_ROOT),
         "--source-root", str(tmp_path),
         "--module", "floor_1x1",
         "--dry-run"],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0
    assert "floor_1x1" in result.stdout
    assert ".blend" in result.stdout
    assert ".source.json" in result.stdout


def test_recovery_cli_rejects_existing_output_without_overwrite(tmp_path: Path) -> None:
    """Should fail if output already exists and --overwrite is not set."""
    module_dir = tmp_path / "floor_1x1"
    module_dir.mkdir()
    (module_dir / "floor_1x1.blend").touch()
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--",
         "--project-root", str(PROJECT_ROOT),
         "--source-root", str(tmp_path),
         "--module", "floor_1x1",
         "--dry-run"],
        capture_output=True, text=True, check=False,
    )
    result2 = subprocess.run(
        [sys.executable, str(SCRIPT), "--",
         "--project-root", str(PROJECT_ROOT),
         "--source-root", str(tmp_path),
         "--module", "floor_1x1"],
        capture_output=True, text=True, check=False,
    )
    assert result2.returncode != 0


def test_recovery_cli_all_flag_selects_eight_modules(tmp_path: Path) -> None:
    """--all should mention all 8 module IDs in dry-run output."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--",
         "--project-root", str(PROJECT_ROOT),
         "--source-root", str(tmp_path),
         "--all",
         "--dry-run"],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0
    for module_id in ["floor_1x1", "floor_2x1", "corridor_floor_1x1",
                       "corridor_floor_1x2", "wall_straight_1x1",
                       "doorway_frame_open_1x1", "pillar_support_1x1",
                       "ramp_up_1x2"]:
        assert module_id in result.stdout


def test_recovery_cli_rejects_combined_all_and_module(tmp_path: Path) -> None:
    """--all and --module are mutually exclusive."""
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--",
         "--project-root", str(PROJECT_ROOT),
         "--source-root", str(tmp_path),
         "--all",
         "--module", "floor_1x1"],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode != 0
