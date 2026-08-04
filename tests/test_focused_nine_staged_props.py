from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

from tools import focused_nine_staged_props as staged_props
from tools.focused_nine_contract import runtime_mutation_paths
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


def test_trusted_workspace_boundary_documents_pre_pin_scope_and_fd_publication() -> None:
    expected = (
        "trusted_workspace: before initial filesystem observation and descriptor-chain pinning, "
        "the caller must ensure that the project root, staging paths, and output parent paths "
        "are not concurrently renamed or rebound by a same-permission actor; that pre-pinning "
        "namespace threat is intentionally outside this boundary, and this tool makes no claim "
        "of total arbitrary local namespace immunity. After descriptor acquisition, all sidecar "
        "publication is FD-relative and no-follow; protected runtime output paths remain denied, "
        "including symlink aliases."
    )

    assert staged_props.SECURITY_BOUNDARY == "trusted_workspace"
    assert staged_props.TRUST_BOUNDARY_DOCUMENTATION == expected
    assert "trusted_workspace" in (staged_props.__doc__ or "")
    assert "descriptor-chain pinning" in staged_props.TRUST_BOUNDARY_DOCUMENTATION
    assert "FD-relative" in staged_props.TRUST_BOUNDARY_DOCUMENTATION
    assert "protected runtime output paths remain denied" in staged_props.TRUST_BOUNDARY_DOCUMENTATION


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


def test_staged_validator_accepts_a_symlinked_project_root_ancestor(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project
    lexical_var = Path("/var")
    resolved_var = lexical_var.resolve()
    resolved_project = project_root.resolve()
    if resolved_var == lexical_var:
        pytest.skip("/var is not a symlink on this platform")
    try:
        relative_project = resolved_project.relative_to(resolved_var)
    except ValueError:
        pytest.skip("temporary project is not below the platform /var alias")
        return

    lexical_root = lexical_var / relative_project
    lexical_glb = lexical_root / STAGING_RELATIVE / "hull_breach_seal_point.glb"
    sidecar = build_staged_sidecar(project_root, staged["hull_breach_seal_point"], "hull_breach_seal_point")

    assert lexical_root != resolved_project
    assert validate_staged_sidecar(lexical_root, lexical_glb, sidecar) == []
    assert build_staged_sidecar(lexical_root, lexical_glb, "hull_breach_seal_point") == sidecar


def test_staged_validator_is_total_for_unhashable_asset_id(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project
    sidecar = build_staged_sidecar(project_root, staged["hull_breach_seal_point"], "hull_breach_seal_point")
    sidecar["asset_id"] = []

    errors = validate_staged_sidecar(
        project_root, staged["hull_breach_seal_point"], sidecar
    )

    assert errors == sorted(errors)
    assert any("asset_id" in error for error in errors)


def _make_symlink_loop(project_root: Path) -> Path:
    loop_root = project_root / "loop"
    try:
        loop_root.symlink_to(loop_root, target_is_directory=True)
    except (NotImplementedError, OSError) as exc:
        pytest.skip(f"platform cannot create a symlink loop: {exc}")
    return loop_root / "hull_breach_seal_point.glb"


def test_staged_validator_returns_sorted_diagnostics_for_a_symlink_loop(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project
    sidecar = build_staged_sidecar(project_root, staged["hull_breach_seal_point"], "hull_breach_seal_point")
    loop_glb = _make_symlink_loop(project_root)

    errors = validate_staged_sidecar(project_root, loop_glb, sidecar)

    assert errors == sorted(errors)
    assert any("could not be resolved" in error for error in errors)


def test_staged_validator_returns_sorted_diagnostics_for_a_looping_project_root(
    staged_project: tuple[Path, dict[str, Path]], tmp_path: Path
) -> None:
    project_root, staged = staged_project
    sidecar = build_staged_sidecar(project_root, staged["hull_breach_seal_point"], "hull_breach_seal_point")
    loop_root = tmp_path / "project_loop"
    try:
        loop_root.symlink_to(loop_root, target_is_directory=True)
    except (NotImplementedError, OSError) as exc:
        pytest.skip(f"platform cannot create a symlink loop: {exc}")
    loop_glb = loop_root / STAGING_RELATIVE / "hull_breach_seal_point.glb"

    errors = validate_staged_sidecar(loop_root, loop_glb, sidecar)

    assert errors == sorted(errors)
    assert any("could not be resolved" in error for error in errors)


def test_cli_returns_one_and_preserves_target_when_loop_validation_raises(
    staged_project: tuple[Path, dict[str, Path]], tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, staged = staged_project
    sidecar = build_staged_sidecar(project_root, staged["hull_breach_seal_point"], "hull_breach_seal_point")
    loop_glb = _make_symlink_loop(project_root)
    output = tmp_path / "existing.sidecar.json"
    original = b"existing target must remain unchanged\n"
    output.write_bytes(original)

    monkeypatch.setattr(staged_props, "build_staged_sidecar", lambda *_args: sidecar)
    result = staged_props.main(
        [
            "--project-root",
            str(project_root),
            "--glb",
            str(loop_glb),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(output),
        ]
    )

    assert result == 1
    assert output.read_bytes() == original
    assert not list(output.parent.glob(f".{output.name}.*.tmp"))


def _snapshot_path(path: Path) -> tuple[object, ...]:
    if path.is_dir():
        entries: list[tuple[object, ...]] = []
        for item in sorted(path.rglob("*"), key=lambda candidate: candidate.relative_to(path).as_posix()):
            relative = item.relative_to(path).as_posix()
            if item.is_symlink():
                entries.append(("symlink", relative, os.readlink(item)))
            elif item.is_dir():
                entries.append(("directory", relative))
            elif item.is_file():
                contents = item.read_bytes()
                entries.append(
                    (
                        "file",
                        relative,
                        hashlib.sha256(contents).hexdigest(),
                        contents,
                    )
                )
            else:
                entries.append(("other", relative))
        return ("directory", tuple(entries))
    return ("file", path.read_bytes())


def test_cli_rejects_every_runtime_mutation_surface_and_symlink_alias(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project
    surfaces = runtime_mutation_paths(project_root)
    snapshots: dict[Path, tuple[object, ...]] = {}
    for index, surface in enumerate(surfaces):
        if surface.name in {"imported", "ship_structural_v0"}:
            surface.mkdir(parents=True, exist_ok=True)
        else:
            surface.parent.mkdir(parents=True, exist_ok=True)
            surface.write_bytes(f"live surface {index}\n".encode())
        snapshots[surface] = _snapshot_path(surface)

    for index, surface in enumerate(surfaces):
        for output in (
            surface,
            project_root / f"runtime_surface_alias_{index}",
        ):
            if output != surface:
                output.symlink_to(surface, target_is_directory=surface.is_dir())

            result = staged_props.main(
                [
                    "--project-root",
                    str(project_root),
                    "--glb",
                    str(staged["hull_breach_seal_point"]),
                    "--asset-id",
                    "hull_breach_seal_point",
                    "--sidecar-out",
                    str(output),
                ]
            )

            assert result == 1
            assert _snapshot_path(surface) == snapshots[surface]
            if output != surface:
                assert output.is_symlink()
            assert not list(output.parent.glob(f".{output.name}.*.tmp"))


def test_cli_rejects_symlink_then_dotdot_protected_output(
    staged_project: tuple[Path, dict[str, Path]],
) -> None:
    project_root, staged = staged_project
    protected = runtime_mutation_paths(project_root)[1]
    protected.parent.mkdir(parents=True, exist_ok=True)
    protected.write_bytes(b"live generated props index must remain exact\n")
    alias_target = protected.parent / "child"
    alias_target.mkdir()
    alias = project_root / "runtime_alias"
    alias.symlink_to(alias_target, target_is_directory=True)
    output = alias / ".." / protected.name

    result = staged_props.main(
        [
            "--project-root",
            str(project_root),
            "--glb",
            str(staged["hull_breach_seal_point"]),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(output),
        ]
    )

    assert result == 1
    assert protected.read_bytes() == b"live generated props index must remain exact\n"
    assert not list(protected.parent.glob(f".{protected.name}.*.tmp"))


def test_cli_rejects_ancestor_swap_to_protected_runtime_after_validation(
    staged_project: tuple[Path, dict[str, Path]],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    project_root, staged = staged_project
    output_root = project_root / "safe-output"
    output_parent = output_root / "nested"
    output_parent.mkdir(parents=True)
    output = output_parent / "hull_breach_seal_point.sidecar.json"

    protected_root = project_root / "assets/imported"
    protected_parent = protected_root / "nested"
    protected_parent.mkdir(parents=True)
    protected_file = protected_parent / "existing.bin"
    protected_file.write_bytes(b"protected runtime bytes\n")
    protected_snapshot = _snapshot_path(protected_root)

    real_protection_check = staged_props._protected_output_error
    moved_output_root = project_root / "safe-output-before-race"

    def validate_then_swap(
        root: Path, output_path: Path
    ) -> tuple[Path, str | None]:
        result = real_protection_check(root, output_path)
        output_root.rename(moved_output_root)
        output_root.symlink_to(protected_root, target_is_directory=True)
        return result

    monkeypatch.setattr(staged_props, "_protected_output_error", validate_then_swap)
    result = staged_props.main(
        [
            "--project-root",
            str(project_root),
            "--glb",
            str(staged["hull_breach_seal_point"]),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(output),
        ]
    )

    assert result != 0
    assert _snapshot_path(protected_root) == protected_snapshot
    assert not (protected_parent / output.name).exists()
    assert not list(protected_parent.glob(f".{output.name}.*.tmp"))


def test_cli_preserves_replace_failure_and_closes_fds_when_unlink_fails(
    staged_project: tuple[Path, dict[str, Path]],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    project_root, staged = staged_project
    output = tmp_path / "out" / "failed-replace.sidecar.json"
    opened_fds: list[int] = []
    closed_fds: list[int] = []
    real_open = staged_props.os.open
    real_close = staged_props.os.close
    real_flags = staged_props._pinned_directory_open_flags
    verified_flags = real_flags()

    def tracking_open(*args: Any, **kwargs: Any) -> int:
        descriptor = real_open(*args, **kwargs)
        opened_fds.append(descriptor)
        return descriptor

    def tracking_close(descriptor: int) -> None:
        closed_fds.append(descriptor)
        real_close(descriptor)

    def fail_replace(*_args: object, **_kwargs: object) -> None:
        raise OSError("injected sidecar replace failure")

    def fail_unlink(*_args: object, **_kwargs: object) -> None:
        raise PermissionError("injected sidecar cleanup denial")

    def flags_then_deny_unlink() -> int:
        monkeypatch.setattr(staged_props.os, "unlink", fail_unlink)
        return verified_flags

    monkeypatch.setattr(staged_props.os, "open", tracking_open)
    monkeypatch.setattr(staged_props.os, "close", tracking_close)
    monkeypatch.setattr(staged_props.os, "replace", fail_replace)
    monkeypatch.setattr(staged_props, "_pinned_directory_open_flags", flags_then_deny_unlink)

    result = staged_props.main(
        [
            "--project-root",
            str(project_root),
            "--glb",
            str(staged["hull_breach_seal_point"]),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(output),
        ]
    )

    assert result != 0
    assert "injected sidecar replace failure" in capsys.readouterr().err
    assert opened_fds
    assert closed_fds
    for descriptor in opened_fds:
        with pytest.raises(OSError):
            os.fstat(descriptor)
    assert not output.exists()


def test_cli_rejects_protected_output_before_atomic_writer(
    staged_project: tuple[Path, dict[str, Path]], monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, staged = staged_project
    protected = runtime_mutation_paths(project_root)[1]
    protected.parent.mkdir(parents=True, exist_ok=True)
    protected.write_bytes(b"live generated props index\n")
    writes: list[Path] = []

    def unexpected_write(path: Path, _sidecar: dict) -> None:
        writes.append(path)

    monkeypatch.setattr(staged_props, "_write_sidecar_atomically", unexpected_write)
    result = staged_props.main(
        [
            "--project-root",
            str(project_root),
            "--glb",
            str(staged["hull_breach_seal_point"]),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(protected),
        ]
    )

    assert result == 1
    assert writes == []
    assert protected.read_bytes() == b"live generated props index\n"


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


def test_cli_passes_canonical_external_target_to_writer(
    staged_project: tuple[Path, dict[str, Path]],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    project_root, staged = staged_project
    external_root = tmp_path / "external"
    external_child = external_root / "child"
    external_child.mkdir(parents=True)
    alias = project_root / "external_alias"
    alias.symlink_to(external_child, target_is_directory=True)
    output = alias / ".." / "external.sidecar.json"
    canonical_output = (external_root / "external.sidecar.json").resolve()
    written_paths: list[Path] = []

    monkeypatch.setattr(
        staged_props,
        "_write_sidecar_atomically",
        lambda path, _sidecar: written_paths.append(path),
    )
    result = staged_props.main(
        [
            "--project-root",
            str(project_root),
            "--glb",
            str(staged["hull_breach_seal_point"]),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(output),
        ]
    )

    assert result == 0
    assert written_paths == [canonical_output]


def test_cli_cleans_temporary_after_atomic_writer_failure(
    staged_project: tuple[Path, dict[str, Path]],
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    project_root, staged = staged_project
    output = tmp_path / "out" / "failed.sidecar.json"
    real_fsync = staged_props.os.fsync
    fsync_calls = 0

    def fail_during_temp_fsync(descriptor: int) -> None:
        nonlocal fsync_calls
        fsync_calls += 1
        if fsync_calls == 2:
            raise OSError("injected sidecar fsync failure")
        real_fsync(descriptor)

    monkeypatch.setattr(staged_props.os, "fsync", fail_during_temp_fsync)
    result = staged_props.main(
        [
            "--project-root",
            str(project_root),
            "--glb",
            str(staged["hull_breach_seal_point"]),
            "--asset-id",
            "hull_breach_seal_point",
            "--sidecar-out",
            str(output),
        ]
    )

    assert result == 1
    assert fsync_calls == 2
    assert not output.exists()
    assert not list(output.parent.glob(f".{output.name}.*.tmp"))


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
