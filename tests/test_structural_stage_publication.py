from __future__ import annotations

import json
from pathlib import Path
import re

import pytest

import tools.structural_stage_publication as publication
from tools.structural_stage_publication import StagePublicationError, publish_staged_files


def _paths(tmp_path: Path) -> tuple[list[tuple[Path, Path]], list[Path]]:
    destination = tmp_path / "staging"
    destination.mkdir()
    old_intact = destination / "module.glb"
    old_damaged = destination / "module_damaged.glb"
    old_intact.write_bytes(b"old-intact")
    old_damaged.write_bytes(b"old-damaged")
    new_intact = tmp_path / "new-intact.glb"
    new_damaged = tmp_path / "new-damaged.glb"
    new_intact.write_bytes(b"new-intact")
    new_damaged.write_bytes(b"new-damaged")
    return [(new_intact, old_intact), (new_damaged, old_damaged)], []


def test_second_replacement_failure_restores_complete_previous_variant_set(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    replacements, obsolete = _paths(tmp_path)
    targets = {target for _source, target in replacements}
    real_replace = publication.os.replace
    replacement_count = 0

    def fail_second_replacement(source, target, *args, **kwargs):
        nonlocal replacement_count
        if Path(target) in targets:
            replacement_count += 1
            if replacement_count == 2:
                raise OSError("injected second replacement failure")
        return real_replace(source, target, *args, **kwargs)

    monkeypatch.setattr(publication.os, "replace", fail_second_replacement)

    with pytest.raises(StagePublicationError, match="second replacement"):
        publish_staged_files(replacements, obsolete)

    assert replacements[0][1].read_bytes() == b"old-intact"
    assert replacements[1][1].read_bytes() == b"old-damaged"
    assert not list(tmp_path.glob("staging/.structural-stage-recovery-*"))


def test_partial_recovery_cleanup_failure_preserves_new_complete_variant_set(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    replacements, obsolete = _paths(tmp_path)

    def fail_after_partial_cleanup(recovery: Path) -> None:
        backup = next(recovery.glob("backup-*"), None)
        assert backup is not None
        backup.unlink()
        raise OSError("injected partial recovery cleanup failure")

    monkeypatch.setattr(publication, "_remove_recovery_directory", fail_after_partial_cleanup)

    with pytest.raises(StagePublicationError, match="cleanup failed") as caught:
        publish_staged_files(replacements, obsolete)

    assert replacements[0][1].read_bytes() == b"new-intact"
    assert replacements[1][1].read_bytes() == b"new-damaged"
    match = re.search(r"recovery directory: (.+)", str(caught.value))
    assert match is not None
    assert Path(match.group(1)).is_dir()


def test_backup_failure_after_rename_restores_the_old_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    replacements, obsolete = _paths(tmp_path)
    real_replace = publication.os.replace
    old_target = replacements[0][1]

    def fail_after_backup_rename(source, target, *args, **kwargs):
        if Path(source) == old_target:
            real_replace(source, target, *args, **kwargs)
            raise OSError("injected failure after backup rename")
        return real_replace(source, target, *args, **kwargs)

    monkeypatch.setattr(publication.os, "replace", fail_after_backup_rename)

    with pytest.raises(StagePublicationError, match="after backup rename"):
        publish_staged_files(replacements, obsolete)

    assert old_target.read_bytes() == b"old-intact"
    assert replacements[1][1].read_bytes() == b"old-damaged"
    assert replacements[0][0].read_bytes() == b"new-intact"
    assert replacements[1][0].read_bytes() == b"new-damaged"
    assert not list(tmp_path.glob("staging/.structural-stage-recovery-*"))


def test_missing_original_and_backup_retains_recovery_for_manual_repair(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    replacements, obsolete = _paths(tmp_path)
    real_replace = publication.os.replace
    old_target = replacements[0][1]

    def lose_backup_after_rename(source, target, *args, **kwargs):
        if Path(source) == old_target:
            real_replace(source, target, *args, **kwargs)
            Path(target).unlink()
            raise OSError("injected loss after backup rename")
        return real_replace(source, target, *args, **kwargs)

    monkeypatch.setattr(publication.os, "replace", lose_backup_after_rename)

    with pytest.raises(StagePublicationError, match="recovery directory") as caught:
        publish_staged_files(replacements, obsolete)

    match = re.search(r"recovery directory: (.+)", str(caught.value))
    assert match is not None
    recovery = Path(match.group(1))
    assert recovery.is_dir()
    manifest = json.loads((recovery / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["phase"] == "rollback_failed"


def test_successful_publication_removes_stale_variant_safely(tmp_path: Path) -> None:
    replacements, _obsolete = _paths(tmp_path)
    stale = replacements[1][1]
    publish_staged_files((replacements[0],), obsolete=(stale,))

    assert replacements[0][1].read_bytes() == b"new-intact"
    assert not stale.exists()
    assert not list(tmp_path.glob("staging/.structural-stage-recovery-*"))


def test_first_backup_failure_leaves_old_outputs_and_sources_untouched(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    replacements, obsolete = _paths(tmp_path)
    real_replace = publication.os.replace
    old_target = replacements[0][1]

    def fail_first_backup(source, target, *args, **kwargs):
        if Path(source) == old_target:
            raise OSError("injected first backup failure")
        return real_replace(source, target, *args, **kwargs)

    monkeypatch.setattr(publication.os, "replace", fail_first_backup)

    with pytest.raises(StagePublicationError, match="first backup"):
        publish_staged_files(replacements, obsolete)

    assert old_target.read_bytes() == b"old-intact"
    assert replacements[1][1].read_bytes() == b"old-damaged"
    assert replacements[0][0].read_bytes() == b"new-intact"
    assert replacements[1][0].read_bytes() == b"new-damaged"
    assert not list(tmp_path.glob("staging/.structural-stage-recovery-*"))


def test_rollback_failure_retains_backups_and_recovery_manifest(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    replacements, obsolete = _paths(tmp_path)
    targets = {target for _source, target in replacements}
    real_replace = publication.os.replace
    replacement_count = 0
    restore_attempted = False

    def fail_rollback_restore(source, target, *args, **kwargs):
        nonlocal replacement_count, restore_attempted
        if Path(target) in targets:
            replacement_count += 1
            if replacement_count == 2:
                raise OSError("injected publication failure")
        if Path(source).parent.name.startswith(".structural-stage-recovery-"):
            restore_attempted = True
            raise OSError("injected rollback failure")
        return real_replace(source, target, *args, **kwargs)

    monkeypatch.setattr(publication.os, "replace", fail_rollback_restore)

    with pytest.raises(StagePublicationError, match="recovery directory") as caught:
        publish_staged_files(replacements, obsolete)

    match = re.search(r"recovery directory: (.+)", str(caught.value))
    assert match is not None
    recovery = Path(match.group(1))
    assert restore_attempted
    assert recovery.is_dir()
    manifest = recovery / "manifest.json"
    assert json.loads(manifest.read_text(encoding="utf-8"))["backups"]
    assert list(recovery.glob("backup-*"))