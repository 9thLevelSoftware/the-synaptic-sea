from __future__ import annotations

from pathlib import Path

import pytest

from tools.backup_structural_sources import BackupError, backup_sources


def test_dry_run_shows_files_without_uploading(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    source = tmp_path / "source"
    source.mkdir()
    (source / "test.blend").write_bytes(b"fake")

    result = backup_sources(source, target=f"local://{tmp_path / 'backup'}", dry_run=True)

    assert result.would_sync == 1
    assert result.uploaded == 0
    assert not (tmp_path / "backup").exists()
    output = capsys.readouterr().out
    assert "BACKUP_PLAN" in output
    assert "test.blend" in output


def test_local_backup_copies_files(tmp_path: Path) -> None:
    source = tmp_path / "source"
    nested = source / "module" / "nested"
    nested.mkdir(parents=True)
    (source / "module" / "source.blend").write_bytes(b"blend")
    (nested / "record.json").write_text('{"ok": true}\n', encoding="utf-8")

    target = tmp_path / "backup"
    result = backup_sources(source, target)

    assert result.would_sync == 2
    assert result.uploaded == 2
    assert (target / "module" / "source.blend").read_bytes() == b"blend"
    assert (target / "module" / "nested" / "record.json").read_text(
        encoding="utf-8"
    ) == '{"ok": true}\n'


def test_missing_source_root_returns_error(tmp_path: Path) -> None:
    with pytest.raises(BackupError, match="source root does not exist"):
        backup_sources(tmp_path / "missing", tmp_path / "backup")


def test_backup_flag_runs_before_promotion(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    import tools.promote_structural_sources as promoter

    calls: list[tuple[str, bool]] = []
    monkeypatch.setattr(
        promoter,
        "backup_sources",
        lambda source_root, target, dry_run=False: (
            calls.append((str(target), dry_run))
            or type("Result", (), {"would_sync": 1, "uploaded": 1})()
        ),
    )

    monkeypatch.setattr(promoter, "_dry_run_module", lambda *_args: None)
    result = promoter.promote_all(
        tmp_path / "project",
        tmp_path / "source",
        tmp_path / "staging",
        ("floor_1x1",),
        dry_run=True,
        backup=True,
        backup_target="s3://bucket/sources",
    )

    assert result == []
    assert calls == [("s3://bucket/sources", True)]
