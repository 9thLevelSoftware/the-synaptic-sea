from __future__ import annotations

import hashlib
import json
import os
import typing
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


def test_reject_protected_output_rejects_outside_and_safe_symlink_paths(tmp_path: Path) -> None:
    root = make_project(tmp_path)
    outside = tmp_path / "outside"
    outside.mkdir()
    with pytest.raises(ValueError, match="root|escape"):
        governance.reject_protected_output(root, outside / "candidate.json", "output")

    outside_link = root / "outside-link"
    outside_link.symlink_to(outside, target_is_directory=True)
    with pytest.raises(ValueError, match="root|escape|symlink"):
        governance.reject_protected_output(root, outside_link / "candidate.json", "output")

    real = root / STAGING / "real.json"
    real.write_text("{}", encoding="utf-8")
    safe_link = root / STAGING / "safe-link.json"
    safe_link.symlink_to(real)
    with pytest.raises(ValueError, match="symlink"):
        governance.reject_protected_output(root, safe_link, "output")


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


def test_descriptor_reader_rejects_deterministic_ancestor_rebind(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    safe = tmp_path / "safe"
    safe.mkdir()
    target = safe / "record.json"
    target.write_text('{"safe":true}', encoding="utf-8")
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "record.json").write_text('{"outside":true}', encoding="utf-8")

    def rebind_after_validation(_path: Path) -> None:
        moved = tmp_path / "safe-moved"
        safe.rename(moved)
        safe.symlink_to(outside, target_is_directory=True)

    monkeypatch.setattr(governance, "_FILE_VALIDATION_HOOK", rebind_after_validation)
    with pytest.raises(ValueError, match="identity|changed|symlink"):
        governance.strict_load_json(target, "json", 100)


def test_descriptor_reader_rejects_same_size_in_place_mutation(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = tmp_path / "payload.bin"
    path.write_bytes(b"AAAA")
    real_read = governance.os.read
    mutated = False

    def read_and_mutate(descriptor: int, size: int) -> bytes:
        nonlocal mutated
        result = real_read(descriptor, size)
        if not mutated:
            path.write_bytes(b"BBBB")
            mutated = True
        return result

    monkeypatch.setattr(governance.os, "read", read_and_mutate)
    with pytest.raises(ValueError, match="changed|mutat"):
        governance.file_sha256(path, max_bytes=4)


def test_streaming_file_hash_does_not_materialize_file_bytes(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    path = tmp_path / "payload.bin"
    payload = b"payload"
    path.write_bytes(payload)

    def fail_materialization(*_args: object, **_kwargs: object) -> bytes:
        raise AssertionError("file_sha256 must stream from its descriptor")

    monkeypatch.setattr(governance, "_read_bounded_regular_file", fail_materialization)
    assert governance.file_sha256(path, max_bytes=len(payload)) == hashlib.sha256(payload).hexdigest()


def test_descriptor_reader_closes_fds_on_rebind_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    safe = tmp_path / "safe"
    safe.mkdir()
    target = safe / "record.json"
    target.write_text('{"safe":true}', encoding="utf-8")
    outside = tmp_path / "outside"
    outside.mkdir()

    def rebind_after_validation(_path: Path) -> None:
        moved = tmp_path / "safe-moved"
        safe.rename(moved)
        safe.symlink_to(outside, target_is_directory=True)

    close_calls: list[int] = []
    real_close = governance.os.close

    def record_close(descriptor: int) -> None:
        close_calls.append(descriptor)
        real_close(descriptor)

    monkeypatch.setattr(governance, "_FILE_VALIDATION_HOOK", rebind_after_validation)
    monkeypatch.setattr(governance.os, "close", record_close)
    with pytest.raises(ValueError):
        governance.file_sha256(target, max_bytes=100)
    assert close_calls


def test_descriptor_reader_annotation_resolves_without_private_hashlib_types() -> None:
    hints = typing.get_type_hints(governance._read_descriptor)

    assert hints["hasher"] == typing.Optional[typing.Any]


def test_protected_surface_snapshot_rejects_pre_enumeration_directory_swap(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = make_project(tmp_path)
    protected = root / "assets/imported"
    protected.mkdir(parents=True)
    (protected / "inside.bin").write_bytes(b"inside")
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "outside.bin").write_bytes(b"outside")

    def swap_before_enumeration(path: Path) -> None:
        if path == protected:
            moved = tmp_path / "protected-moved"
            protected.rename(moved)
            outside.rename(protected)

    monkeypatch.setattr(governance, "_SNAPSHOT_VALIDATION_HOOK", swap_before_enumeration)
    with pytest.raises(ValueError, match="identity|changed"):
        governance.snapshot_protected_surfaces(root)
    assert (protected / "outside.bin").read_bytes() == b"outside"
    assert (tmp_path / "protected-moved/inside.bin").read_bytes() == b"inside"


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


@pytest.mark.parametrize(
    ("name", "value"),
    [
        ("max_file_bytes", 0),
        ("max_file_bytes", -1),
        ("max_file_bytes", True),
        ("max_total_bytes", 0),
        ("max_total_bytes", False),
        ("max_entries", 0),
        ("max_entries", 1.5),
        ("max_depth", 0),
        ("max_depth", None),
    ],
)
def test_snapshot_limits_are_positive_non_bool_integers(
    tmp_path: Path, name: str, value: object
) -> None:
    root = make_project(tmp_path)
    kwargs = {name: value}
    with pytest.raises(ValueError, match="positive integer"):
        governance.snapshot_protected_surfaces(root, **kwargs)


def test_snapshot_enforces_aggregate_bytes_entries_and_depth(tmp_path: Path) -> None:
    root = make_project(tmp_path)
    imported = root / "assets/imported"
    imported.mkdir(parents=True)
    (imported / "level1").mkdir()
    (imported / "level1/level2").mkdir()
    (imported / "level1/level2/payload.bin").write_bytes(b"1234")

    with pytest.raises(ValueError, match="total|aggregate|bytes"):
        governance.snapshot_protected_surfaces(root, max_total_bytes=3)
    with pytest.raises(ValueError, match="entr"):
        governance.snapshot_protected_surfaces(root, max_entries=4)
    with pytest.raises(ValueError, match="depth"):
        governance.snapshot_protected_surfaces(root, max_depth=1)


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


def test_atomic_write_bytes_publishes_exact_bytes_with_private_mode(tmp_path: Path) -> None:
    root = make_project(tmp_path)
    target = root / STAGING / "tasks" / "payload.bin"
    payload = b"not-json\x00exact"

    governance.atomic_write_bytes(
        target,
        payload,
        project_root=root,
        allowed_root=root / STAGING,
    )

    assert target.read_bytes() == payload
    assert target.stat().st_mode & 0o777 == 0o600
    assert not list(target.parent.glob(".*.tmp"))


def test_atomic_publish_directory_renames_complete_private_tree(tmp_path: Path) -> None:
    root = make_project(tmp_path)
    parent = root / STAGING / "asset"
    parent.mkdir()
    source = parent / ".task-id-random.tmp"
    final = parent / "task-id"
    source.mkdir(mode=0o700)
    governance.atomic_write_bytes(source / "raw.glb", b"complete", root, parent)

    governance.atomic_publish_directory(source, final, root, parent)

    assert final.is_dir()
    assert (final / "raw.glb").read_bytes() == b"complete"
    assert not source.exists()


def test_atomic_publish_directory_rejects_existing_final_and_symlink_source(tmp_path: Path) -> None:
    root = make_project(tmp_path)
    parent = root / STAGING / "asset"
    parent.mkdir()
    source = parent / ".task-id-random.tmp"
    final = parent / "task-id"
    source.mkdir(mode=0o700)
    final.mkdir()
    with pytest.raises(ValueError, match="existing|final"):
        governance.atomic_publish_directory(source, final, root, parent)

    final.rmdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    source.rmdir()
    source.symlink_to(outside, target_is_directory=True)
    with pytest.raises(ValueError, match="symlink|regular|directory"):
        governance.atomic_publish_directory(source, final, root, parent)


def test_atomic_publish_directory_rejects_parent_rebind_and_leaves_source(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    root = make_project(tmp_path)
    parent = root / STAGING / "asset"
    parent.mkdir()
    source = parent / ".task-id-random.tmp"
    final = parent / "task-id"
    source.mkdir(mode=0o700)
    moved = root / STAGING / "asset-moved"

    def rebind(_path: Path) -> None:
        parent.rename(moved)
        parent.mkdir()

    monkeypatch.setattr(governance, "_ATOMIC_VALIDATION_HOOK", rebind)
    with pytest.raises(OSError, match="identity|changed|validation"):
        governance.atomic_publish_directory(source, final, root, parent)
    assert not final.exists()
    assert (moved / source.name).is_dir()


def test_atomic_write_bytes_uses_pinned_parent_and_preserves_primary_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = make_project(tmp_path)
    parent = root / STAGING / "safe"
    parent.mkdir()
    target = parent / "payload.bin"
    moved = root / STAGING / "safe-moved"

    def swap_after_validation(_target: Path) -> None:
        parent.rename(moved)
        parent.mkdir()

    monkeypatch.setattr(governance, "_ATOMIC_VALIDATION_HOOK", swap_after_validation)
    with pytest.raises(OSError, match="identity changed"):
        governance.atomic_write_bytes(
            target,
            b"protected exact bytes",
            project_root=root,
            allowed_root=root / STAGING,
        )
    assert not target.exists()
    assert not list(parent.glob(".*.tmp"))
    assert not list(moved.glob(".*.tmp"))


def test_atomic_write_rejects_unexpected_descendant_created_after_parent(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = make_project(tmp_path)
    stage = root / STAGING
    target = stage / "new1" / "new2" / "record.json"
    real_mkdir = governance.os.mkdir

    def mkdir_and_precreate_descendant(path: object, *args: object, **kwargs: object) -> object:
        result = real_mkdir(path, *args, **kwargs)
        if path == "new1":
            (stage / "new1" / "new2").mkdir()
        return result

    monkeypatch.setattr(governance.os, "mkdir", mkdir_and_precreate_descendant)
    with pytest.raises(OSError, match="appeared|validation"):
        governance.atomic_write_json(
            target,
            {"changed": True},
            project_root=root,
            allowed_root=stage,
        )


def test_atomic_write_fsyncs_each_created_parent_before_descending(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = make_project(tmp_path)
    stage = root / STAGING
    target = stage / "new1" / "new2" / "record.json"
    mkdir_parent_fds: list[int] = []
    fsync_fds: list[int] = []
    real_mkdir = governance.os.mkdir
    real_fsync = governance.os.fsync

    def record_mkdir(path: object, *args: object, **kwargs: object) -> object:
        parent_fd = kwargs.get("dir_fd")
        if isinstance(parent_fd, int):
            mkdir_parent_fds.append(parent_fd)
        return real_mkdir(path, *args, **kwargs)

    def record_fsync(descriptor: int) -> None:
        fsync_fds.append(descriptor)
        real_fsync(descriptor)

    monkeypatch.setattr(governance.os, "mkdir", record_mkdir)
    monkeypatch.setattr(governance.os, "fsync", record_fsync)
    governance.atomic_write_json(
        target,
        {"changed": True},
        project_root=root,
        allowed_root=stage,
    )
    assert mkdir_parent_fds
    assert all(parent_fd in fsync_fds for parent_fd in mkdir_parent_fds)


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
