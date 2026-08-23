from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from tools import validate_promoted_sources as validator


MODULE_ID = "floor_1x1"


def test_glb_magic_rejects_non_glb_file(tmp_path: Path) -> None:
    path = tmp_path / "not-a-glb.glb"
    path.write_bytes(b"not-a-glb")

    errors = validator.validate_glb_magic(path)

    assert errors
    assert "invalid GLB magic" in errors[0]


def test_glb_magic_accepts_valid_glb(tmp_path: Path) -> None:
    path = tmp_path / "valid.glb"
    path.write_bytes(b"glTF")

    assert validator.validate_glb_magic(path) == []


def test_missing_staging_dir_returns_error(tmp_path: Path) -> None:
    errors = validator.validate_staged_module(
        project_root=tmp_path,
        staging_root=tmp_path / "staging",
        module_id=MODULE_ID,
        skip_godot=True,
    )

    assert any("missing staged GLB" in error for error in errors)


def test_skip_godot_validates_staged_glb_without_subprocess(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staged = tmp_path / "staging" / MODULE_ID
    staged.mkdir(parents=True)
    (staged / f"{MODULE_ID}.glb").write_bytes(b"glTF" + b"payload")

    def fail_if_called(*_args: object, **_kwargs: object) -> None:
        raise AssertionError("Godot should not run when --skip-godot is set")

    monkeypatch.setattr(validator.subprocess, "run", fail_if_called)

    assert (
        validator.validate_staged_module(
            project_root=tmp_path,
            staging_root=tmp_path / "staging",
            module_id=MODULE_ID,
            skip_godot=True,
        )
        == []
    )


def test_godot_diagnostics_are_returned_from_import_and_wrapper_smoke(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root = tmp_path / "project"
    project_root.mkdir()
    (project_root / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    staged = tmp_path / "staging" / MODULE_ID
    staged.mkdir(parents=True)
    staged_glb = staged / f"{MODULE_ID}.glb"
    staged_glb.write_bytes(b"glTF" + b"payload")
    calls: list[list[str]] = []

    def fake_godot(command: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(command)
        if len(calls) == 1:
            return SimpleNamespace(returncode=0, stdout="WARNING: import warning\n", stderr="")
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(validator.subprocess, "run", fake_godot)

    errors = validator.validate_staged_module(
        project_root=project_root,
        staging_root=tmp_path / "staging",
        module_id=MODULE_ID,
    )

    assert any("WARNING: import warning" in error for error in errors)
    assert len(calls) == 1
    assert calls[0][1:4] == ["--headless", "--import", "--path"]


def test_godot_script_error_is_returned_from_structural_smoke(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root = tmp_path / "project"
    project_root.mkdir()
    (project_root / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    staged = tmp_path / "staging" / MODULE_ID
    staged.mkdir(parents=True)
    (staged / f"{MODULE_ID}.glb").write_bytes(b"glTF" + b"payload")
    calls: list[list[str]] = []

    def fake_godot(command: list[str], **_kwargs: object) -> SimpleNamespace:
        calls.append(command)
        if len(calls) == 2:
            return SimpleNamespace(
                returncode=0,
                stdout="SCRIPT ERROR: structural smoke failed\n",
                stderr="",
            )
        return SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(validator.subprocess, "run", fake_godot)

    errors = validator.validate_staged_module(
        project_root=project_root,
        staging_root=tmp_path / "staging",
        module_id=MODULE_ID,
    )

    assert any("SCRIPT ERROR: structural smoke failed" in error for error in errors)
    assert len(calls) == 2
    assert "--script" in calls[1]
