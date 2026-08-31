from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

import pytest

from tools import meshy_governance as governance


STAGING = Path("assets/_staging/meshy")


def make_project(tmp_path: Path) -> Path:
    root = tmp_path / "project"
    (root / STAGING).mkdir(parents=True)
    return root


def test_project_root_alias_is_resolved_once_and_protected_paths_are_exact(tmp_path: Path) -> None:
    root = make_project(tmp_path)
    alias = tmp_path / "project-alias"
    alias.symlink_to(root, target_is_directory=True)

    physical = governance.physical_project_root(alias)

    assert physical == root.resolve()
    assert governance.protected_runtime_paths(alias) == tuple(
        physical / relative
        for relative in governance.PROTECTED_RUNTIME_RELATIVE_PATHS
    )
    assert governance.PROTECTED_RUNTIME_RELATIVE_PATHS == (
        Path("assets/imported"),
        Path("data/combat"),
        Path("data/props"),
        Path("scenes/wrappers"),
    )


def test_governed_task_path_requires_physical_meshy_staging_and_rejects_symlink_escape(
    tmp_path: Path,
) -> None:
    root = make_project(tmp_path)
    outside = tmp_path / "outside"
    outside.mkdir()
    stage = root / STAGING
    (stage / "escape").symlink_to(outside, target_is_directory=True)

    assert governance.governed_task_path(root, stage / "task.json", "task") == stage / "task.json"
    with pytest.raises(ValueError, match="staging"):
        governance.governed_task_path(root, root / "assets/imported/task.json", "task")
    with pytest.raises(ValueError, match="symlink"):
        governance.governed_task_path(root, stage / "escape/task.json", "task")
    with pytest.raises(ValueError, match="missing"):
        governance.governed_task_path(root, stage / "missing.json", "task", allow_missing=False)


def test_reject_protected_output_catches_direct_and_alias_paths(tmp_path: Path) -> None:
    root = make_project(tmp_path)
    protected = root / "assets/imported"
    protected.mkdir(parents=True)
    alias = root / "runtime-alias"
    alias.symlink_to(protected, target_is_directory=True)

    with pytest.raises(ValueError, match="protected"):
        governance.reject_protected_output(root, protected / "candidate.json", "output")
    with pytest.raises(ValueError, match="protected"):
        governance.reject_protected_output(root, alias / "candidate.json", "output")

    safe = root / STAGING / "candidate.json"
    assert governance.reject_protected_output(root, safe, "output") == safe


def test_strict_json_rejects_duplicates_nonfinite_deep_nonregular_symlink_and_oversize(
    tmp_path: Path,
) -> None:
    valid = tmp_path / "valid.json"
    valid.write_text('{"ok":true}', encoding="utf-8")
    assert governance.strict_load_json(valid, "json", 100) == {"ok": True}

    duplicate = tmp_path / "duplicate.json"
    duplicate.write_text('{"key":1,"key":2}', encoding="utf-8")
    with pytest.raises(ValueError, match="duplicate"):
        governance.strict_load_json(duplicate, "json", 100)

    nonfinite = tmp_path / "nonfinite.json"
    nonfinite.write_text('{"value":NaN}', encoding="utf-8")
    with pytest.raises(ValueError, match="non-standard|non-finite"):
        governance.strict_load_json(nonfinite, "json", 100)

    overflow = tmp_path / "overflow.json"
    overflow.write_text('{"value":1e999}', encoding="utf-8")
    with pytest.raises(ValueError, match="non-finite"):
        governance.strict_load_json(overflow, "json", 100)

    deep = tmp_path / "deep.json"
    deep.write_text("[" * 3000 + "]" * 3000, encoding="utf-8")
    with pytest.raises(ValueError, match="nesting|JSON"):
        governance.strict_load_json(deep, "json", 100_000)

    directory = tmp_path / "directory.json"
    directory.mkdir()
    with pytest.raises(ValueError, match="regular"):
        governance.strict_load_json(directory, "json", 100)

    oversized = tmp_path / "oversized.json"
    oversized.write_text('{"payload":"0123456789"}', encoding="utf-8")
    with pytest.raises(ValueError, match="size|large"):
        governance.strict_load_json(oversized, "json", 10)

    target = tmp_path / "target.json"
    target.write_text('{"safe":true}', encoding="utf-8")
    link = tmp_path / "link.json"
    link.symlink_to(target)
    with pytest.raises(ValueError, match="symlink"):
        governance.strict_load_json(link, "json", 100)


def test_file_sha256_is_bounded_regular_and_no_follow(tmp_path: Path) -> None:
    path = tmp_path / "payload.bin"
    payload = b"payload"
    path.write_bytes(payload)
    assert governance.file_sha256(path, max_bytes=len(payload)) == hashlib.sha256(payload).hexdigest()
    with pytest.raises(ValueError, match="size|large"):
        governance.file_sha256(path, max_bytes=len(payload) - 1)
    with pytest.raises(ValueError, match="regular"):
        governance.file_sha256(path.parent)
    alias = tmp_path / "payload-alias.bin"
    alias.symlink_to(path)
    with pytest.raises(ValueError, match="symlink"):
        governance.file_sha256(alias)


def test_protected_surface_snapshot_is_immutable_deterministic_and_content_sensitive(
    tmp_path: Path,
) -> None:
    root = make_project(tmp_path)
    (root / "assets/imported").mkdir(parents=True)
    (root / "assets/imported/runtime.bin").write_bytes(b"before")
    (root / "data/props").mkdir(parents=True)
    (root / "data/props/index.json").write_bytes(b"{}")

    first = governance.snapshot_protected_surfaces(root)
    second = governance.snapshot_protected_surfaces(root)

    assert isinstance(first, tuple)
    assert first == second
    assert len(first) == 4
    assert all(isinstance(record, tuple) for record in first)
    assert {record.type for record in first} == {"directory", "missing"}
    assert all(
        (record.type, record.path, record.sha256, record.size) == tuple(record)
        for record in first
    )
    imported = next(record for record in first if record.path == "assets/imported")
    assert imported.sha256
    assert imported.size > 0

    (root / "assets/imported/runtime.bin").write_bytes(b"after")
    changed = governance.snapshot_protected_surfaces(root)
    assert changed != first


def test_atomic_write_json_is_canonical_durable_and_rejects_existing_leaf_symlink(
    tmp_path: Path,
) -> None:
    root = make_project(tmp_path)
    target = root / STAGING / "tasks" / "record.json"
    governance.atomic_write_json(
        target,
        {"z": "café", "a": [True, 1]},
        project_root=root,
        allowed_root=root / STAGING,
    )
    assert target.read_bytes() == b'{"a":[true,1],"z":"caf\xc3\xa9"}\n'

    victim = tmp_path / "victim.json"
    victim.write_bytes(b"unchanged")
    linked_target = root / STAGING / "linked.json"
    linked_target.symlink_to(victim)
    with pytest.raises(ValueError, match="symlink"):
        governance.atomic_write_json(
            linked_target,
            {"changed": True},
            project_root=root,
            allowed_root=root / STAGING,
        )
    assert victim.read_bytes() == b"unchanged"


def test_atomic_write_rejects_protected_output_and_validation_to_open_rebind(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = make_project(tmp_path)
    protected = root / "assets/imported"
    protected.mkdir(parents=True)
    protected_file = protected / "keep.bin"
    protected_file.write_bytes(b"protected")
    with pytest.raises(ValueError, match="protected"):
        governance.atomic_write_json(
            protected / "record.json",
            {"changed": True},
            project_root=root,
            allowed_root=root / STAGING,
        )

    safe_parent = root / STAGING / "safe"
    safe_parent.mkdir()
    target = safe_parent / "record.json"
    moved_parent = root / STAGING / "safe-moved"

    def swap_after_validation(_target: Path) -> None:
        safe_parent.rename(moved_parent)
        safe_parent.mkdir()

    monkeypatch.setattr(governance, "_ATOMIC_VALIDATION_HOOK", swap_after_validation)
    with pytest.raises(OSError, match="identity changed"):
        governance.atomic_write_json(
            target,
            {"changed": True},
            project_root=root,
            allowed_root=root / STAGING,
        )
    assert not target.exists()
    assert not list(safe_parent.glob(".*.tmp"))
    assert protected_file.read_bytes() == b"protected"


def test_atomic_write_preserves_primary_error_when_cleanup_unlink_fails(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = make_project(tmp_path)
    target = root / STAGING / "record.json"
    real_replace = governance.os.replace
    real_unlink = governance.os.unlink
    governance._pinned_directory_flags()

    def fail_replace(*_args: object, **_kwargs: object) -> None:
        raise OSError("primary replacement failure")

    def fail_unlink(path: object, *args: object, **kwargs: object) -> None:
        if isinstance(path, str) and path.endswith(".tmp"):
            raise OSError("cleanup unlink failure")
        real_unlink(path, *args, **kwargs)

    monkeypatch.setattr(governance.os, "replace", fail_replace)
    monkeypatch.setattr(governance.os, "unlink", fail_unlink)
    with pytest.raises(OSError, match="primary replacement failure"):
        governance.atomic_write_json(
            target,
            {"changed": True},
            project_root=root,
            allowed_root=root / STAGING,
        )
    assert not target.exists()
    monkeypatch.setattr(governance.os, "replace", real_replace)
    assert list(target.parent.glob(".*.tmp"))
