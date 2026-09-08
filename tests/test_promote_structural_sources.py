from __future__ import annotations

from pathlib import Path
import subprocess
from types import SimpleNamespace
import sys

import pytest

import tools.promote_structural_sources as promoter
from tools.promote_structural_sources import (
    PromotionError,
    should_skip_promotion,
)


def test_identical_hash_skips_promotion(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    runtime = tmp_path / "runtime.glb"
    staged.write_bytes(b"same GLB bytes")
    runtime.write_bytes(b"same GLB bytes")

    assert should_skip_promotion(staged, runtime, force=False) is True


def test_different_hash_does_not_skip(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    runtime = tmp_path / "runtime.glb"
    staged.write_bytes(b"new GLB bytes")
    runtime.write_bytes(b"old GLB bytes")

    assert should_skip_promotion(staged, runtime, force=False) is False


def test_force_overrides_hash_skip(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    runtime = tmp_path / "runtime.glb"
    staged.write_bytes(b"same GLB bytes")
    runtime.write_bytes(b"same GLB bytes")

    assert should_skip_promotion(staged, runtime, force=True) is False


def test_missing_runtime_does_not_skip(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    runtime = tmp_path / "runtime.glb"
    staged.write_bytes(b"staged GLB bytes")

    assert should_skip_promotion(staged, runtime, force=False) is False


def test_dry_run_skips_export_and_does_not_touch_staging(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    project_root = tmp_path / "project"
    source_root = tmp_path / "sources"
    staging_root = tmp_path / "staging"
    blend_path = source_root / "floor_1x1" / "floor_1x1.blend"
    blend_path.parent.mkdir(parents=True)
    blend_path.write_bytes(b"blend")

    monkeypatch.setattr(promoter, "load_source_spec", lambda *_args: object())

    def fail_if_exported(*_args, **_kwargs):
        raise AssertionError("dry-run invoked Blender export")

    monkeypatch.setattr(promoter, "export_module_to_staging", fail_if_exported)

    assert promoter.promote_all(
        project_root,
        source_root,
        staging_root,
        ("floor_1x1",),
        dry_run=True,
    ) == []

    assert not staging_root.exists()
    assert "STRUCTURAL_PROMOTION_PLAN module=floor_1x1" in capsys.readouterr().out


def test_godot_smoke_rejects_invalid_glb_magic_before_subprocess(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staged = tmp_path / "floor_1x1.glb"
    staged.write_bytes(b"nope" + b"\0" * 20)
    subprocess_calls: list[object] = []
    monkeypatch.setattr(
        promoter.subprocess,
        "run",
        lambda *args, **kwargs: subprocess_calls.append((args, kwargs)),
    )

    with pytest.raises(PromotionError, match="invalid GLB magic"):
        promoter._run_godot_import_smoke(
            tmp_path,
            "floor_1x1",
            {"intact": staged},
        )

    assert subprocess_calls == []


def test_failed_export_preserves_previous_staging_contents(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source_root = tmp_path / "sources"
    blend_path = source_root / "floor_1x1" / "floor_1x1.blend"
    blend_path.parent.mkdir(parents=True)
    blend_path.write_bytes(b"blend")
    staging_module = tmp_path / "staging" / "floor_1x1"
    staging_module.mkdir(parents=True)
    previous_glb = staging_module / "floor_1x1.glb"
    previous_glb.write_bytes(b"previous staged output")
    metadata = staging_module / "README.txt"
    metadata.write_text("keep me", encoding="utf-8")

    monkeypatch.setattr(
        promoter.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(
            returncode=1,
            stderr="Blender failed",
            stdout="",
        ),
    )

    with pytest.raises(PromotionError, match="Blender export failed"):
        promoter.export_module_to_staging(
            tmp_path / "project",
            source_root,
            tmp_path / "staging",
            "floor_1x1",
        )

    assert previous_glb.read_bytes() == b"previous staged output"
    assert metadata.read_text(encoding="utf-8") == "keep me"
    assert not list(staging_module.glob(".tmp_export-*"))


def test_successful_export_commits_validated_outputs_to_final_staging(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source_root = tmp_path / "sources"
    blend_path = source_root / "floor_1x1" / "floor_1x1.blend"
    blend_path.parent.mkdir(parents=True)
    blend_path.write_bytes(b"blend")
    staging_module = tmp_path / "staging" / "floor_1x1"
    staging_module.mkdir(parents=True)
    old_glb = staging_module / "floor_1x1.glb"
    old_glb.write_bytes(b"old")
    metadata = staging_module / "README.txt"
    metadata.write_text("keep me", encoding="utf-8")

    def fake_blender(command, **_kwargs):
        export_dir = Path(command[command.index("--staging-dir") + 1])
        (export_dir / "floor_1x1.glb").write_bytes(b"glTF" + b"new")
        return SimpleNamespace(returncode=0, stderr="", stdout="")

    monkeypatch.setattr(promoter.subprocess, "run", fake_blender)

    exported = promoter.export_module_to_staging(
        tmp_path / "project",
        source_root,
        tmp_path / "staging",
        "floor_1x1",
    )

    final_glb = staging_module / "floor_1x1.glb"
    assert exported == {"intact": final_glb}
    assert final_glb.read_bytes() == b"glTFnew"
    assert metadata.read_text(encoding="utf-8") == "keep me"
    assert not list(staging_module.glob(".tmp_export-*"))


def test_direct_promote_refuses_source_authority_hold_before_any_runtime_copy(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    staging_module = tmp_path / "staging" / "floor_1x1"
    staging_module.mkdir(parents=True)
    staged = staging_module / "floor_1x1.glb"
    staged.write_bytes(b"staged")
    copy_calls: list[object] = []

    monkeypatch.setattr(
        promoter,
        "_source_authority_hold_reason",
        lambda _project_root: "source authority status is unresolved",
    )
    monkeypatch.setattr(
        promoter,
        "_copy_atomic",
        lambda *args, **kwargs: copy_calls.append((args, kwargs)),
    )

    with pytest.raises(PromotionError, match="source authority"):
        promoter.promote_module(
            tmp_path / "project",
            tmp_path / "staging",
            "floor_1x1",
            {"intact": staged},
        )

    assert copy_calls == []
    assert not (tmp_path / "project" / promoter._RUNTIME_ROOT).exists()


def test_force_and_skip_godot_cannot_bypass_source_authority_hold(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        promoter,
        "_source_authority_hold_reason",
        lambda _project_root: "source authority status is unresolved",
    )

    def fail_if_exported(*_args, **_kwargs):
        raise AssertionError("source authority hold was bypassed")

    monkeypatch.setattr(promoter, "export_module_to_staging", fail_if_exported)

    with pytest.raises(PromotionError, match="source authority"):
        promoter.promote_all(
            tmp_path / "project",
            tmp_path / "sources",
            tmp_path / "staging",
            ("floor_1x1",),
            force=True,
            skip_godot=True,
        )

    assert not (tmp_path / "project" / promoter._RUNTIME_ROOT).exists()


def test_dry_run_reports_source_authority_hold_without_side_effects(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    source_root = tmp_path / "sources"
    blend_path = source_root / "floor_1x1" / "floor_1x1.blend"
    blend_path.parent.mkdir(parents=True)
    blend_path.write_bytes(b"blend")
    monkeypatch.setattr(promoter, "load_source_spec", lambda *_args: object())
    monkeypatch.setattr(
        promoter,
        "_source_authority_hold_reason",
        lambda _project_root: "source authority status is unresolved",
    )

    assert promoter.promote_all(
        tmp_path / "project",
        source_root,
        tmp_path / "staging",
        ("floor_1x1",),
        dry_run=True,
    ) == []

    output = capsys.readouterr().out
    assert "STRUCTURAL_PROMOTION_HOLD module=floor_1x1" in output
    assert not (tmp_path / "staging").exists()


def test_cli_reports_source_authority_hold_reason_and_writes_nothing(
    tmp_path: Path,
) -> None:
    project_root = tmp_path / "project"
    source_root = tmp_path / "sources"
    staging_root = tmp_path / "staging"
    backup_target = tmp_path / "backup"
    script = Path(__file__).resolve().parents[1] / "tools" / "promote_structural_sources.py"

    result = subprocess.run(
        [
            sys.executable,
            str(script),
            "--project-root",
            str(project_root),
            "--source-root",
            str(source_root),
            "--staging-root",
            str(staging_root),
            "--module",
            "floor_1x1",
            "--force",
            "--skip-godot",
            "--backup",
            "--backup-target",
            str(backup_target),
        ],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    output = result.stdout + result.stderr
    assert "STRUCTURAL_PROMOTION_HOLD" in output
    assert "source authority" in output.lower()
    assert not project_root.exists()
    assert not staging_root.exists()
    assert not backup_target.exists()
