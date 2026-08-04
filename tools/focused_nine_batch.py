#!/usr/bin/env python3
"""Atomically stage and validate the focused-nine comparison batch.

The batch is deliberately a no-promotion workflow.  Blender edits only the
approved external source roots, candidate GLBs and staged metadata are built in
an isolated temporary staging workspace, and requested assets are published
only after the batch's recipe, export, evidence, wrapper/sidecar, capture, and
validator gates pass.  Runtime surfaces are never copied to or written by this
module.

Trusted-workspace boundary: Blender and Godot use path-based APIs.  After the
initial path observations, same-user concurrent rename or rebind of the source,
project, and output paths is outside this workflow's boundary; the containment,
no-follow validators, temporary workspaces, and atomic renames are defense in
depth and are not claimed to provide descriptor-level race immunity.

Publication recovery boundary: requested final artifacts are snapshotted before
the first stage rename and restored on any later publication failure.  This is
an all-or-nothing transaction for a trusted workspace, not crash recovery: a
process or power loss during publication can still leave the exact structural
backup marker for the next invocation's local recovery.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
from collections.abc import Iterable, Sequence
from dataclasses import replace
from pathlib import Path
from typing import Any

try:
    from tools import focused_nine_contract as contract
    from tools import focused_nine_evidence as evidence
    from tools import focused_nine_staged_props as staged_props
    from tools import structural_source_contract as source_contract
    from tools import validate_structural_sources as structural_validator
    from tools.focused_nine_blender_recipes import (
        resolve_source_path,
        source_blend_path,
    )
except ModuleNotFoundError:  # pragma: no cover - direct script execution
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools import focused_nine_contract as contract
    from tools import focused_nine_evidence as evidence
    from tools import focused_nine_staged_props as staged_props
    from tools import structural_source_contract as source_contract
    from tools import validate_structural_sources as structural_validator
    from tools.focused_nine_blender_recipes import (
        resolve_source_path,
        source_blend_path,
    )


ORDERED_ASSET_IDS: tuple[str, ...] = contract.STRUCTURAL_IDS + contract.PROP_IDS
BLENDER = Path(os.environ.get("BLENDER", "/opt/homebrew/bin/blender"))
GODOT = Path(os.environ.get("GODOT", "/opt/homebrew/bin/godot"))
RECIPE_SCRIPT = Path(__file__).with_name("focused_nine_blender_recipes.py")
EXPORT_SCRIPT = Path(__file__).with_name("export_structural_glb.py")
PRESSURE_PACKAGE = Path("assets/_staging/focused_nine/structural/pressure_door_1x1")
PROOF_RELATIVE = Path("docs/superpowers/proofs/focused-nine-comparison.md")
_CAPTURE_SCENE = "res://scenes/validation/focused_nine_comparison_harness.tscn"
_CAPTURE_SCRIPT = "res://scripts/validation/focused_nine_comparison_capture.gd"
CAPTURE_TIMEOUT_SECONDS = 120
SOURCE_TIMEOUT_SECONDS = 120
RECIPE_TIMEOUT_SECONDS = 300
STRUCTURAL_EXPORT_TIMEOUT_SECONDS = 180
PROP_EXPORT_TIMEOUT_SECONDS = 180
PRESSURE_OVERLAY_TIMEOUT_SECONDS = 180
STRUCTURAL_VALIDATOR_TIMEOUT_SECONDS = 300
PROP_VALIDATOR_TIMEOUT_SECONDS = 180
MAX_CAPTURED_OUTPUT_BYTES = 64 * 1024
# Evidence copies are intentionally capped at 256 MiB per staged GLB.  This is
# large enough for the focused-nine candidates while bounding private temporary
# storage and Blender re-import exposure before any evidence copy occurs.
MAX_STAGED_GLB_INPUT_BYTES = 256 * 1024 * 1024
_PROCESS_DRAIN_TIMEOUT_SECONDS = 0.25
_PROCESS_REAP_TIMEOUT_SECONDS = 0.25
_CAPTURE_DIAGNOSTIC_MARKERS = ("WARNING:", "ERROR:", "SCRIPT ERROR:")
_CAPTURE_DIAGNOSTIC_BLOCKER = "comparison capture blocker: Godot emitted diagnostics"


# Re-exporting this pure validator keeps the batch's report gate obvious to
# callers and makes the CLI contract easy to test without Blender.
validate_report = contract.validate_report


def _absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(Path(path).expanduser())))


def _contained(root: Path, candidate: Path) -> bool:
    root = root.resolve(strict=False)
    candidate = candidate.resolve(strict=False)
    return candidate == root or root in candidate.parents


def _stage_root(project_root: Path) -> Path:
    return project_root / "assets/_staging/focused_nine"


def _canonical_res_path(project_root: Path, path: Path) -> str:
    root = project_root.resolve(strict=False)
    candidate = path.resolve(strict=False)
    try:
        return f"res://{candidate.relative_to(root).as_posix()}"
    except ValueError:
        # The report contract intentionally permits only project-relative
        # logical source references; external source paths never enter report
        # or proof artifacts.
        return f"res://assets/_staging/focused_nine/source_refs/{path.stem}.blend"


def _source_reference(asset_id: str) -> str:
    return f"res://assets/_staging/focused_nine/source_refs/{asset_id}.blend"


def _iter_surface_entries(root: Path) -> Iterable[tuple[str, str, int | None, str | None]]:
    """Yield a deterministic, no-follow manifest for one runtime surface."""

    if not os.path.lexists(root):
        yield ("", "missing", None, None)
        return
    try:
        mode = root.lstat().st_mode
    except OSError as exc:
        yield ("", "error", None, str(exc))
        return
    if stat.S_ISLNK(mode):
        yield ("", "symlink", None, os.readlink(root))
        return
    if stat.S_ISREG(mode):
        yield ("", "file", root.stat().st_size, hashlib.sha256(root.read_bytes()).hexdigest())
        return
    if not stat.S_ISDIR(mode):
        yield ("", "other", None, stat.filemode(mode))
        return

    for current, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        dirnames[:] = sorted(dirnames)
        filenames[:] = sorted(filenames)
        for name in tuple(dirnames):
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                yield (relative, "symlink", None, os.readlink(path))
                dirnames.remove(name)
            else:
                yield (relative, "directory", None, None)
        for name in filenames:
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            try:
                entry_mode = path.lstat().st_mode
                if stat.S_ISLNK(entry_mode):
                    yield (relative, "symlink", None, os.readlink(path))
                elif stat.S_ISREG(entry_mode):
                    yield (
                        relative,
                        "file",
                        path.stat().st_size,
                        hashlib.sha256(path.read_bytes()).hexdigest(),
                    )
                else:
                    yield (relative, "other", None, stat.filemode(entry_mode))
            except OSError as exc:
                yield (relative, "error", None, str(exc))


def snapshot_runtime_surfaces(project_root: Path) -> tuple[tuple[str, str, int | None, str | None], ...]:
    """Return a stable content snapshot of the protected live runtime paths."""

    root = project_root.resolve(strict=False)
    result: list[tuple[str, str, int | None, str | None]] = []
    for surface in contract.runtime_mutation_paths(root):
        try:
            label = surface.relative_to(root).as_posix()
        except ValueError:
            label = surface.as_posix()
        for relative, kind, size, digest in _iter_surface_entries(surface):
            result.append((f"{label}/{relative}" if relative else label, kind, size, digest))
    return tuple(sorted(result))


def _canonical_json(document: object) -> bytes:
    return (
        json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
        + "\n"
    ).encode("utf-8")


def _atomic_write_bytes(path: Path, payload: bytes) -> None:
    """Publish bytes with a same-directory temporary file and replace."""

    _reject_static_symlink_components(path, f"output path {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def _reject_static_symlink_components(path: Path, label: str) -> None:
    """Reject existing symlink components without resolving caller aliases."""

    absolute = _absolute(path)
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            # A missing component means all later components are missing too.
            break
        except OSError as exc:
            raise ValueError(f"cannot inspect {label}: {path}") from exc
        if stat.S_ISLNK(mode) and current not in (Path("/var"), Path("/tmp")):
            # macOS exposes temporary directories through /var and /tmp;
            # these system aliases are not caller-controlled workspace aliases.
            raise ValueError(f"{label} contains symlink component: {current}")


def _validate_source_root(
    project_root: Path,
    source_root: Path,
    label: str,
    asset_id: str | None = None,
) -> Path:
    """Validate one external source root before any Blender or validator work."""

    root = _absolute(source_root)
    _reject_static_symlink_components(root, label)
    try:
        mode = root.lstat().st_mode
    except FileNotFoundError:
        mode = None
    except OSError as exc:
        raise ValueError(f"cannot inspect {label}: {source_root}") from exc
    if mode is not None and not stat.S_ISDIR(mode):
        raise ValueError(f"{label} must be a directory: {source_root}")

    project = _absolute(project_root)
    project_resolved = project.resolve(strict=False)
    root_resolved = root.resolve(strict=False)
    runtime_lexical = (
        project / "assets/imported",
        project / "assets/_staging",
        *(_absolute(path) for path in contract.runtime_mutation_paths(project)),
    )
    runtime_resolved = (
        project_resolved / "assets/imported",
        project_resolved / "assets/_staging",
        *(Path(path).resolve(strict=False) for path in contract.runtime_mutation_paths(project_resolved)),
    )
    for candidate in (root, root_resolved):
        for runtime_surface in (*runtime_lexical, *runtime_resolved):
            if candidate == runtime_surface or runtime_surface in candidate.parents:
                raise ValueError(f"{label} is on a runtime surface: {source_root}")

    checked_assets = (asset_id,) if asset_id is not None else contract.STRUCTURAL_IDS
    for checked_asset in checked_assets:
        candidate = source_blend_path(root, root, checked_asset)
        _reject_static_symlink_components(candidate, f"{label} source path")
        resolved_candidate = resolve_source_path(
            project_root,
            root,
            root,
            checked_asset,
        )
        try:
            resolved_candidate.relative_to(root_resolved)
        except ValueError as exc:
            raise ValueError(
                f"{label} source path is not physically beneath its root: {candidate}"
            ) from exc
    return root


def _validation_source_root(args: argparse.Namespace) -> Path:
    return getattr(args, "validation_structural_source_root", args.structural_source_root)


def _validate_output_paths(project_root: Path, report: Path, preview_dir: Path) -> tuple[Path, Path, Path]:
    root = project_root.resolve(strict=False)
    report_abs = _absolute(report)
    preview_abs = _absolute(preview_dir)
    stage = _stage_root(root)
    approved_preview = root / "artifacts/validation-previews/focused-nine"
    _reject_static_symlink_components(stage, "stage root")
    _reject_static_symlink_components(report_abs, "report path")
    _reject_static_symlink_components(approved_preview, "preview root")
    _reject_static_symlink_components(preview_abs, "preview path")
    if not _contained(root, report_abs) or not _contained(stage, report_abs):
        raise ValueError("report must be under assets/_staging/focused_nine in the project")
    if not _contained(root, preview_abs) or not _contained(approved_preview, preview_abs):
        raise ValueError("preview-dir must be under artifacts/validation-previews/focused-nine")
    return root, report_abs, preview_abs


def _requested_assets(values: Sequence[str] | None) -> tuple[str, ...]:
    if not values:
        return ORDERED_ASSET_IDS
    unknown = sorted(set(values) - set(ORDERED_ASSET_IDS))
    if unknown:
        raise ValueError(f"unknown focused-nine asset id: {unknown[0]!r}")
    duplicates = sorted({asset_id for asset_id in values if values.count(asset_id) > 1})
    if duplicates:
        raise ValueError(f"duplicate focused-nine asset id: {duplicates[0]!r}")
    requested = set(values)
    return tuple(asset_id for asset_id in ORDERED_ASSET_IDS if asset_id in requested)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--structural-source-root", type=Path, required=True)
    parser.add_argument(
        "--validation-structural-source-root",
        type=Path,
        help="optional source root used only by live 15-module structural validation",
    )
    parser.add_argument("--props-source-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--preview-dir", type=Path, required=True)
    parser.add_argument("--asset", dest="assets", action="append", metavar="ID")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.validation_structural_source_root is None:
        args.validation_structural_source_root = args.structural_source_root
    try:
        args.assets = _requested_assets(args.assets)
        _validate_output_paths(args.project_root, args.report, args.preview_dir)
        _validate_source_root(args.project_root, args.structural_source_root, "structural source root")
        _validate_source_root(
            args.project_root,
            args.validation_structural_source_root,
            "validation structural source root",
        )
    except ValueError as exc:
        parser.error(str(exc))
    return args


def _read_process_output(
    process: subprocess.Popen[bytes], timeout: float | None
) -> tuple[bytes, bytes]:
    selector = selectors.DefaultSelector()
    streams = (process.stdout, process.stderr)
    for index, stream in enumerate(streams):
        if stream is not None:
            selector.register(stream, selectors.EVENT_READ, index)
    buffers = [bytearray(), bytearray()]
    captured = 0
    deadline = time.monotonic() + timeout if timeout is not None else None
    try:
        while selector.get_map():
            remaining = None if deadline is None else deadline - time.monotonic()
            if remaining is not None and remaining <= 0:
                raise subprocess.TimeoutExpired(
                    process.args,
                    timeout if timeout is not None else 0.0,
                    output=bytes(buffers[0]),
                    stderr=bytes(buffers[1]),
                )
            events = selector.select(remaining)
            if not events:
                raise subprocess.TimeoutExpired(
                    process.args,
                    timeout if timeout is not None else 0.0,
                    output=bytes(buffers[0]),
                    stderr=bytes(buffers[1]),
                )
            for key, _mask in events:
                chunk = os.read(key.fd, 8192)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                remaining_budget = max(0, MAX_CAPTURED_OUTPUT_BYTES - captured)
                if remaining_budget:
                    accepted = chunk[:remaining_budget]
                    buffers[key.data].extend(accepted)
                    captured += len(accepted)
    finally:
        selector.close()
    process.wait()
    return bytes(buffers[0]), bytes(buffers[1])


def _close_process_pipes(process: subprocess.Popen[bytes]) -> None:
    for stream in (process.stdout, process.stderr):
        if stream is None:
            continue
        try:
            stream.close()
        except OSError:
            continue


def _reap_process_after_timeout(process: subprocess.Popen[bytes]) -> None:
    try:
        process.wait(timeout=_PROCESS_REAP_TIMEOUT_SECONDS)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        process.kill()
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=_PROCESS_REAP_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        # The parent process has been killed and its pipe descriptors are
        # closed below.  A hostile escaped descendant is outside this process
        # object's waitable set; do not turn timeout reporting into another
        # unbounded wait.
        return


def _bounded_timeout_drain(process: subprocess.Popen[bytes]) -> tuple[bytes, bytes]:
    try:
        return _read_process_output(process, _PROCESS_DRAIN_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired as exc:
        return _as_bytes(exc.stdout), _as_bytes(exc.stderr)
    finally:
        _close_process_pipes(process)
        _reap_process_after_timeout(process)


def _run(
    command: Sequence[str], *, cwd: Path | None = None, timeout: float | None = None
) -> subprocess.CompletedProcess[str]:
    """Run one bounded process in a fresh session and reap its process group."""

    process = subprocess.Popen(
        list(command),
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=False,
        start_new_session=True,
    )
    try:
        stdout, stderr = _read_process_output(process, timeout)
    except subprocess.TimeoutExpired as exc:
        partial_stdout = _as_bytes(exc.stdout)
        partial_stderr = _as_bytes(exc.stderr)
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            process.kill()
        drained_stdout, drained_stderr = _bounded_timeout_drain(process)
        stdout = partial_stdout + drained_stdout
        stderr = partial_stderr + drained_stderr
        bounded_stdout, bounded_stderr = _bounded_output_pair(stdout, stderr)
        exc.stdout = bounded_stdout
        exc.stderr = bounded_stderr
        exc.output = bounded_stdout
        raise
    bounded_stdout, bounded_stderr = _bounded_output_pair(stdout, stderr)
    return subprocess.CompletedProcess(list(command), process.returncode, bounded_stdout, bounded_stderr)


def _as_text(value: object) -> str:
    if isinstance(value, bytes):
        return value.decode(errors="replace")
    return str(value) if value else ""


def _as_bytes(value: object) -> bytes:
    if isinstance(value, bytes):
        return value
    if value is None:
        return b""
    return str(value).encode("utf-8", errors="replace")


def _bounded_output_pair(stdout: object, stderr: object) -> tuple[str, str]:
    """Cap combined captured output while retaining deterministic prefixes."""

    marker = "\n[output truncated]"
    output_limit = MAX_CAPTURED_OUTPUT_BYTES
    values = [_as_text(stdout), _as_text(stderr)]
    encoded_lengths = [len(value.encode("utf-8")) for value in values]
    if sum(encoded_lengths) <= output_limit:
        return values[0], values[1]

    bounded: list[str] = []
    remaining = output_limit
    for value in values:
        raw = value.encode("utf-8")
        if remaining <= 0:
            bounded_value = ""
        elif len(raw) <= remaining:
            bounded_value = value
        else:
            marker_bytes = marker.encode("utf-8")
            if remaining < len(marker_bytes):
                bounded_value = marker_bytes[:remaining].decode("utf-8", errors="ignore")
            else:
                prefix_length = remaining - len(marker_bytes)
                bounded_value = raw[:prefix_length].decode("utf-8", errors="replace") + marker
        bounded.append(bounded_value)
        remaining = max(0, remaining - len(bounded_value.encode("utf-8")))
    return bounded[0], bounded[1]


def _failure_output(result: object) -> str:
    output = "\n".join(
        part for part in (_as_text(getattr(result, "stdout", None)), _as_text(getattr(result, "stderr", None))) if part
    )
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    for line in lines:
        if line.startswith(("ERROR:", "Traceback", "Exception", "Error:")):
            return line
    return lines[0] if lines else f"exit {getattr(result, 'returncode', 'unknown')}"


def _run_step(
    command: Sequence[str],
    *,
    cwd: Path | None = None,
    timeout: float,
    label: str,
) -> subprocess.CompletedProcess[str]:
    try:
        return _run(command, cwd=cwd, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        detail = _failure_output(exc)
        suffix = f": {detail}" if detail and detail != "exit unknown" else ""
        raise RuntimeError(f"{label} timed out after {timeout} seconds{suffix}") from exc


def _validate_blender_file(path: Path) -> None:
    """Reject arbitrary regular files where a Blender database is required."""

    _reject_static_symlink_components(path, "Blender source path")
    try:
        mode = path.lstat().st_mode
    except OSError as exc:
        raise ValueError(f"cannot inspect Blender source: {path}") from exc
    if not stat.S_ISREG(mode):
        raise ValueError(f"Blender source must be a regular file: {path}")
    try:
        with path.open("rb") as handle:
            header = handle.read(12)
    except OSError as exc:
        raise ValueError(f"cannot read Blender source: {path}") from exc
    if (
        len(header) != 12
        or header[:7] != b"BLENDER"
        or header[7:8] not in (b"-", b"_")
        or header[8:9] not in (b"v", b"V")
        or not header[9:12].isdigit()
    ):
        raise ValueError(f"source is not a valid Blender file: {path}")


def _copy_source_with_blender(seed: Path, destination: Path) -> None:
    seed = _absolute(seed)
    destination = _absolute(destination)
    _validate_blender_file(seed)
    _reject_static_symlink_components(destination, "Blender source path")
    destination.parent.mkdir(parents=True, exist_ok=True)
    _reject_static_symlink_components(destination.parent, "Blender source parent")
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=str(destination.parent)
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    expression = (
        "import bpy; "
        f"result=bpy.ops.wm.open_mainfile(filepath={str(seed)!r}); "
        "assert 'FINISHED' in result, 'source seed open failed'; "
        f"result=bpy.ops.wm.save_as_mainfile(filepath={str(temporary)!r}); "
        "assert 'FINISHED' in result, 'source seed save failed'"
    )
    try:
        result = _run_step(
            [str(BLENDER), "--background", "--factory-startup", "--python-expr", expression],
            timeout=SOURCE_TIMEOUT_SECONDS,
            label="source Blender copy",
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"required source blend missing and could not be created: {destination}: "
                f"{_failure_output(result)}"
            )
        _validate_blender_file(temporary)
        os.replace(temporary, destination)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def _create_empty_source_with_blender(destination: Path) -> None:
    destination = _absolute(destination)
    _reject_static_symlink_components(destination, "Blender source path")
    destination.parent.mkdir(parents=True, exist_ok=True)
    _reject_static_symlink_components(destination.parent, "Blender source parent")
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".tmp", dir=str(destination.parent)
    )
    os.close(descriptor)
    temporary = Path(temporary_name)
    expression = (
        "import bpy; "
        "bpy.ops.wm.read_factory_settings(use_empty=True); "
        f"result=bpy.ops.wm.save_as_mainfile(filepath={str(temporary)!r}); "
        "assert 'FINISHED' in result, 'empty source save failed'"
    )
    try:
        result = _run_step(
            [str(BLENDER), "--background", "--factory-startup", "--python-expr", expression],
            timeout=SOURCE_TIMEOUT_SECONDS,
            label="source Blender creation",
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"required source blend missing and could not be created: {destination}: "
                f"{_failure_output(result)}"
            )
        _validate_blender_file(temporary)
        os.replace(temporary, destination)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def _choose_seed(root: Path, destination: Path, preferred: Sequence[Path] = ()) -> Path:
    for candidate in preferred:
        if candidate.is_file() and candidate.resolve() != destination.resolve():
            return candidate
    candidates = sorted(path for path in root.rglob("*.blend") if path.is_file() and path.resolve() != destination.resolve())
    if candidates:
        return candidates[0]
    raise FileNotFoundError(f"no valid Blender source seed exists for {destination}")


def _ensure_source(args: argparse.Namespace, asset_id: str) -> Path:
    candidate = source_blend_path(args.structural_source_root, args.props_source_root, asset_id)
    source_root = (
        args.structural_source_root
        if asset_id in contract.STRUCTURAL_IDS
        else args.props_source_root
    )
    root_abs = _absolute(source_root)
    _validate_source_root(args.project_root, root_abs, "source root", asset_id)
    candidate_abs = _absolute(candidate)
    _reject_static_symlink_components(root_abs, "source root")
    _reject_static_symlink_components(candidate_abs, "source path")
    try:
        candidate_abs.relative_to(root_abs)
    except ValueError as exc:
        raise ValueError(f"source path is not beneath its explicit source root: {candidate}") from exc

    # Validate the complete candidate and every protected runtime/staging
    # surface before creating a missing source file.  This helper also rejects
    # hardlinks into those surfaces.
    source = resolve_source_path(
        args.project_root,
        args.structural_source_root,
        args.props_source_root,
        asset_id,
    )
    try:
        source.relative_to(root_abs.resolve(strict=False))
    except ValueError as exc:
        raise ValueError(f"source path is not physically beneath its explicit source root: {candidate}") from exc
    if candidate_abs.exists():
        mode = candidate_abs.lstat().st_mode
        if not stat.S_ISREG(mode):
            raise ValueError(f"focused-nine source is not a regular file: {candidate}")
        _validate_blender_file(candidate_abs)
        return source
    # A fresh empty source is deliberate: copying another focused source can
    # carry a namespaced helper collection with a different module_id and is
    # therefore not a valid seed for this asset.
    _create_empty_source_with_blender(source)
    _validate_blender_file(source)
    return source


def _focused_source_record_paths(source_root: Path, asset_id: str) -> tuple[Path, Path]:
    """Return one focused source's exact blend and provenance paths."""

    if asset_id in source_contract.STRUCTURAL_SOURCE_MODULE_IDS:
        return source_contract.source_output_paths(source_root, asset_id)
    if asset_id not in source_contract.FOCUSED_NINE_CANDIDATE_MODULE_IDS:
        raise ValueError(f"unsupported focused structural source record: {asset_id!r}")

    root = Path(source_root).expanduser()
    module_root = root / asset_id
    if not _contained(root, module_root):
        raise ValueError(f"focused source record path escapes source root: {asset_id}")
    return module_root / f"{asset_id}.blend", module_root / f"{asset_id}.source.json"


def _candidate_spec_for_private_glb(
    project_root: Path, asset_id: str, private_glb: Path
) -> source_contract.StructuralSourceSpec:
    """Load the candidate contract while hashing a private, pre-publication GLB.

    The candidate contract loader intentionally accepts only the canonical
    staged pressure-door path.  During the batch that path may still contain a
    previous candidate (or be absent), so load the same contract and the actual
    private export in a disposable project, then restore the final project
    paths on the immutable spec.  The resulting record can be checked before a
    publication rename without trusting stale staging content.
    """

    if asset_id not in source_contract.FOCUSED_NINE_CANDIDATE_MODULE_IDS:
        raise ValueError(f"unsupported focused candidate source: {asset_id!r}")
    private_path = _absolute(private_glb)
    _reject_static_symlink_components(private_path, "private candidate source GLB")
    try:
        mode = private_path.lstat().st_mode
    except OSError as exc:
        raise ValueError(f"cannot inspect private candidate source GLB: {private_glb}") from exc
    if not stat.S_ISREG(mode):
        raise ValueError(f"private candidate source GLB must be a regular file: {private_glb}")
    _validate_staged_glb_input(private_path)

    project = _absolute(project_root)
    candidate_relative = Path(
        "assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb"
    )
    contract_relative = Path(
        "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
    )
    final_candidate = project / candidate_relative
    final_contract = project / contract_relative
    with tempfile.TemporaryDirectory(prefix="focused-nine-candidate-contract-") as temporary:
        disposable = Path(temporary)
        disposable_candidate = disposable / candidate_relative
        disposable_contract = disposable / contract_relative
        disposable_candidate.parent.mkdir(parents=True, exist_ok=True)
        disposable_contract.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(private_path, disposable_candidate)
        shutil.copy2(final_contract, disposable_contract)
        spec = source_contract.load_candidate_source_spec(
            disposable, asset_id, candidate_relative
        )
    return replace(
        spec,
        contract_path=final_contract,
        source_glb_path=final_candidate,
    )


def _write_structural_source_record(
    args: argparse.Namespace,
    asset_id: str,
    source: Path,
    *,
    candidate_glb: Path | None = None,
) -> Path:
    """Write and immediately validate one focused structural source record.

    Records are written only beside the source under the explicit structural
    source root.  Representative records reference the checked-in structural
    contract and imported source GLB; the pressure-door record references the
    actual private staged GLB that will be published, not an older candidate.
    """

    if asset_id not in contract.STRUCTURAL_IDS:
        raise ValueError(f"focused source record requested for non-structural asset: {asset_id}")
    _validate_source_root(
        args.project_root,
        args.structural_source_root,
        "structural source root",
        asset_id,
    )
    record_root = Path(args.structural_source_root).expanduser()
    blend_path, record_path = _focused_source_record_paths(record_root, asset_id)
    _reject_static_symlink_components(blend_path, "focused structural source path")
    _reject_static_symlink_components(record_path, "focused structural source record path")
    source_abs = _absolute(source)
    if source_abs != _absolute(blend_path):
        raise ValueError(f"focused structural source path does not match its root: {source}")
    try:
        mode = source_abs.lstat().st_mode
    except OSError as exc:
        raise ValueError(f"cannot inspect focused structural source: {source}") from exc
    if not stat.S_ISREG(mode):
        raise ValueError(f"focused structural source must be a regular file: {source}")

    if asset_id == "pressure_door_1x1":
        if candidate_glb is None:
            raise ValueError("pressure-door source record requires its private staged intact GLB")
        spec = _candidate_spec_for_private_glb(args.project_root, asset_id, candidate_glb)
    else:
        if candidate_glb is not None:
            raise ValueError(f"candidate GLB is only valid for pressure_door_1x1: {asset_id}")
        spec = source_contract.load_source_spec(_absolute(args.project_root), asset_id)
    record = source_contract.build_source_record(spec, blend_path)
    errors = structural_validator._validate_source_record(spec, record, blend_path=blend_path)
    if errors:
        raise ValueError(f"focused structural source record validation failed for {asset_id}: {'; '.join(errors)}")
    _atomic_write_bytes(record_path, source_contract.canonical_json(record))
    try:
        written = json.loads(record_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"focused structural source record could not be read back: {record_path}") from exc
    errors = structural_validator._validate_source_record(spec, written, blend_path=blend_path)
    if errors:
        raise ValueError(f"focused structural source record validation failed for {asset_id}: {'; '.join(errors)}")
    return record_path


def _run_recipe(args: argparse.Namespace, asset_id: str) -> None:
    result = _run_step(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python",
            str(RECIPE_SCRIPT),
            "--",
            "--project-root",
            str(args.project_root),
            "--structural-source-root",
            str(args.structural_source_root),
            "--props-source-root",
            str(args.props_source_root),
            "--asset-id",
            asset_id,
            "--overwrite-generated-only",
        ],
        timeout=RECIPE_TIMEOUT_SECONDS,
        label=f"focused-nine recipe for {asset_id}",
    )
    if result.returncode != 0:
        raise RuntimeError(f"focused-nine recipe failed for {asset_id}: {_failure_output(result)}")


def _run_structural_export(source: Path, asset_id: str, destination: Path) -> tuple[Path, ...]:
    destination.mkdir(parents=True, exist_ok=True)
    result = _run_step(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python",
            str(EXPORT_SCRIPT),
            "--",
            "--blend-path",
            str(source),
            "--staging-dir",
            str(destination),
            "--module",
            asset_id,
        ],
        timeout=STRUCTURAL_EXPORT_TIMEOUT_SECONDS,
        label=f"focused-nine export for {asset_id}",
    )
    if result.returncode != 0:
        raise RuntimeError(f"focused-nine export failed for {asset_id}: {_failure_output(result)}")
    paths = tuple(sorted(destination.glob(f"{asset_id}*.glb")))
    expected_roles = contract.VARIANT_ROLES.get(asset_id, ("intact",))
    expected = tuple(destination / (f"{asset_id}.glb" if role == "intact" else f"{asset_id}_{role}.glb") for role in expected_roles)
    if set(paths) != set(expected) or len(paths) != len(expected):
        raise RuntimeError(f"focused-nine export produced incomplete roles for {asset_id}")
    return expected


def _props_export_expression(source: Path, collection_name: str, output: Path) -> str:
    return (
        "import bpy; "
        f"result=bpy.ops.wm.open_mainfile(filepath={str(source)!r}); "
        "assert 'FINISHED' in result, 'prop source open failed'; "
        f"collection=bpy.data.collections.get({collection_name!r}); "
        "assert collection is not None, 'generated prop collection missing'; "
        "bpy.ops.object.select_all(action='DESELECT'); "
        "objects=[obj for obj in collection.objects if obj.type == 'MESH']; "
        "assert objects, 'generated prop collection has no mesh'; "
        "[obj.select_set(True) for obj in objects]; "
        "bpy.context.view_layer.objects.active=objects[0]; "
        f"result=bpy.ops.export_scene.gltf(filepath={str(output)!r}, export_format='GLB', export_apply=True, use_selection=True); "
        "assert 'CANCELLED' not in result, 'prop GLB export cancelled'"
    )


def _run_prop_export(source: Path, asset_id: str, destination: Path) -> tuple[Path, ...]:
    destination.mkdir(parents=True, exist_ok=True)
    output = destination / f".{asset_id}.tmp.glb"
    result = _run_step(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python-expr",
            _props_export_expression(source, f"FocusedNine_{asset_id}_Generated", output),
        ],
        timeout=PROP_EXPORT_TIMEOUT_SECONDS,
        label=f"focused-nine prop export for {asset_id}",
    )
    if result.returncode != 0 or not output.is_file() or output.stat().st_size <= 0:
        raise RuntimeError(f"focused-nine prop export failed for {asset_id}: {_failure_output(result)}")
    final = destination / f"{asset_id}.glb"
    os.replace(output, final)
    return (final,)


def _gate_prop_sidecar(project_root: Path, glb_path: Path, asset_id: str, output: Path) -> dict[str, Any]:
    """Run Task 5's strict validator in a canonical disposable project."""

    _validate_staged_glb_input(glb_path)
    with tempfile.TemporaryDirectory(prefix="focused-nine-sidecar-gate-") as temporary:
        gate_project = Path(temporary)
        gate_glb = gate_project / "assets/_staging/focused_nine/props" / f"{asset_id}.glb"
        gate_glb.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(glb_path, gate_glb)
        sidecar = staged_props.build_staged_sidecar(gate_project, gate_glb, asset_id)
        errors = staged_props.validate_staged_sidecar(gate_project, gate_glb, sidecar)
        if errors:
            raise ValueError(f"staged prop sidecar validation failed for {asset_id}: {'; '.join(errors)}")
    _atomic_write_bytes(output, _canonical_json(sidecar))
    return sidecar


def _metrics_from_evidence(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "sha256": record["sha256"],
        "byte_size": record["byte_size"],
        "mesh_count": record["mesh_count"],
        "triangle_count": record["triangle_count"],
        "material_names": list(record["material_names"]),
        "bounds": {
            "local_min_m": list(record["local_min_m"]),
            "local_max_m": list(record["local_max_m"]),
        },
    }


def _empty_metrics() -> dict[str, Any]:
    return {
        "sha256": "0" * 64,
        "byte_size": 0,
        "mesh_count": 0,
        "triangle_count": 0,
        "material_names": ["unavailable"],
        "bounds": {"local_min_m": [0.0, 0.0, 0.0], "local_max_m": [0.0, 0.0, 0.0]},
    }


def _asset_record(
    project_root: Path,
    args: argparse.Namespace,
    asset_id: str,
    source: Path | None,
    staged_paths: Sequence[Path],
    metrics: dict[str, Any],
    validations: Sequence[str],
    passed: bool,
    first_error: str | None,
    role_metrics: dict[str, Any] | None = None,
) -> dict[str, Any]:
    kind = "structural" if asset_id in contract.STRUCTURAL_IDS else "prop"
    def safe_error(value: str | None) -> str | None:
        if value is None:
            return None
        safe = value
        for root in (args.structural_source_root, args.props_source_root):
            replacement = _source_reference(asset_id)
            for spelling in {_absolute(root), Path(root).resolve(strict=False)}:
                safe = safe.replace(str(spelling), replacement)
        project_spellings = {_absolute(project_root), project_root.resolve(strict=False)}
        for spelling in project_spellings:
            safe = safe.replace(str(spelling), "res://")
        return safe

    safe_validations = [safe_error(validation) or "" for validation in validations]
    # Use the contract helper for exact role spelling, never a filesystem glob.
    staged_glbs = [
        f"res://{contract.asset_stage_glb(project_root, asset_id, role).relative_to(project_root.resolve()).as_posix()}"
        for role in contract.VARIANT_ROLES.get(asset_id, ("intact",))
    ]
    if kind == "prop":
        staged_glbs = [
            f"res://{contract.asset_stage_glb(project_root, asset_id).relative_to(project_root.resolve()).as_posix()}"
        ]
    return {
        "asset_id": asset_id,
        "kind": "prop" if kind == "prop" else "structural",
        "source_path": _source_reference(asset_id),
        "staged_glbs": staged_glbs,
        "metrics": metrics,
        "validation": safe_validations,
        "pass": passed,
        "first_error": safe_error(first_error),
    }


def _structural_backup_path(final: Path) -> Path:
    return final.with_name(f".{final.name}.previous")


def _recover_structural_backup(final: Path) -> None:
    """Recover one exact local backup left by an interrupted transaction."""

    backup = _structural_backup_path(final)
    if not _path_exists_without_following(backup):
        return
    _reject_static_symlink_components(final, "structural publication target")
    _reject_static_symlink_components(backup, "structural publication backup")
    quarantine: Path | None = None
    if _path_exists_without_following(final):
        quarantine = final.with_name(f".{final.name}.recovery-{next(tempfile._get_candidate_names())}")
        os.replace(final, quarantine)
    try:
        os.replace(backup, final)
    except BaseException:
        if quarantine is not None and not _path_exists_without_following(final):
            os.replace(quarantine, final)
        raise
    if quarantine is not None:
        _discard_path_without_unlinking_target(quarantine)


def _publish_structural_asset(private: Path, final: Path) -> None:
    """Replace one structural package with exact-name rollback recovery.

    A same-user crash between the two renames and backup cleanup can leave the
    exact backup marker behind; the next invocation recovers that marker before
    publishing.  This is recoverable, not a claim of power-loss atomicity.
    """

    _validate_publication_target(private, "private structural publication source")
    _validate_publication_target(final.parent, "structural publication target parent")
    _validate_publication_target(final, "structural publication target")
    try:
        if not stat.S_ISDIR(private.lstat().st_mode):
            raise ValueError(f"private structural publication source must be a directory: {private}")
    except FileNotFoundError as exc:
        raise ValueError(f"private structural publication source is missing: {private}") from exc
    final.parent.mkdir(parents=True, exist_ok=True)
    _validate_publication_target(final.parent, "structural publication target parent")
    _validate_publication_target(final, "structural publication target")
    _validate_publication_target_tree(final, "structural publication target")
    _recover_structural_backup(final)
    backup = _structural_backup_path(final)
    if _path_exists_without_following(backup):
        raise RuntimeError(f"structural publication backup was not recovered: {backup}")
    had_final = _path_exists_without_following(final)
    try:
        if had_final:
            os.replace(final, backup)
        os.replace(private, final)
    except BaseException as exc:
        rollback_error: BaseException | None = None
        try:
            if _path_exists_without_following(backup):
                if _path_exists_without_following(final):
                    _discard_path_without_unlinking_target(final)
                os.replace(backup, final)
            elif not had_final and _path_exists_without_following(final):
                _discard_path_without_unlinking_target(final)
        except BaseException as recovery_exc:  # noqa: BLE001 - preserve rollback diagnostics
            rollback_error = recovery_exc
        if rollback_error is not None:
            raise RuntimeError(
                f"structural publication failed and rollback failed for {final}: {rollback_error}"
            ) from exc
        raise
    if _path_exists_without_following(backup):
        _discard_path_without_unlinking_target(backup)


def _path_exists_without_following(path: Path) -> bool:
    return os.path.lexists(os.fspath(path))


def _discard_path_without_unlinking_target(path: Path) -> None:
    """Remove one path by first moving it to a private rollback tombstone."""

    if not _path_exists_without_following(path):
        return
    tombstone = path.with_name(f".{path.name}.rollback-{next(tempfile._get_candidate_names())}")
    os.replace(path, tombstone)
    mode = tombstone.lstat().st_mode
    if stat.S_ISDIR(mode):
        shutil.rmtree(tombstone)
    else:
        os.unlink(tombstone)


def _validate_publication_target(path: Path, label: str) -> None:
    """Pin the static no-follow namespace before any publication mkdir/rename."""

    _reject_static_symlink_components(path, label)
    try:
        mode = path.lstat()
    except FileNotFoundError:
        return
    except OSError as exc:
        raise ValueError(f"cannot inspect {label}: {path}") from exc
    if stat.S_ISLNK(mode.st_mode):
        raise ValueError(f"{label} contains symlink component: {path}")


def _validate_publication_target_tree(path: Path, label: str) -> None:
    """Reject symlinked children before replacing a structural target tree."""

    _validate_publication_target(path, label)
    if not path.is_dir():
        return
    for current, dirnames, filenames in os.walk(path, topdown=True, followlinks=False):
        current_path = Path(current)
        for name in (*dirnames, *filenames):
            _validate_publication_target(current_path / name, label)


def _copy_path_without_following(source: Path, destination: Path) -> None:
    """Copy one snapshot entry without dereferencing a symlink."""

    mode = source.lstat().st_mode
    destination.parent.mkdir(parents=True, exist_ok=True)
    if stat.S_ISLNK(mode):
        destination.symlink_to(os.readlink(source))
    elif stat.S_ISDIR(mode):
        shutil.copytree(source, destination, symlinks=True)
    elif stat.S_ISREG(mode):
        shutil.copy2(source, destination)
    else:
        raise ValueError(f"publication snapshot contains unsupported entry: {source}")


def _publication_auxiliary_paths(target: Path) -> tuple[Path, ...]:
    """Record only this target's known rollback-marker namespace."""

    parent = target.parent
    _validate_publication_target(parent, "publication target parent")
    if not parent.is_dir():
        return ()
    prefixes = (f".{target.name}.previous", f".{target.name}.rollback-")
    return tuple(
        sorted(
            path
            for path in parent.iterdir()
            if path.name.startswith(prefixes)
        )
    )


def _snapshot_publication_targets(
    targets: Sequence[Path], snapshot_root: Path
) -> tuple[tuple[Path, Path | None, tuple[Path, ...]], ...]:
    """Snapshot exact requested final entries before the first stage replace."""

    snapshots: list[tuple[Path, Path | None, tuple[Path, ...]]] = []
    snapshot_root.mkdir(parents=True, exist_ok=True)
    for index, target in enumerate(targets):
        _validate_publication_target(target, "publication target")
        _validate_publication_target(target.parent, "publication target parent")
        snapshot = snapshot_root / str(index)
        if _path_exists_without_following(target):
            _copy_path_without_following(target, snapshot)
            snapshot_path: Path | None = snapshot
        else:
            snapshot_path = None
        snapshots.append((target, snapshot_path, _publication_auxiliary_paths(target)))
    return tuple(snapshots)


def _restore_publication_targets(
    snapshots: Sequence[tuple[Path, Path | None, tuple[Path, ...]]]
) -> None:
    """Restore only the snapshotted requested targets and their own markers."""

    for target, snapshot, old_auxiliary in reversed(snapshots):
        _validate_publication_target(target, "publication target")
        _validate_publication_target(target.parent, "publication target parent")
        if _path_exists_without_following(target):
            _discard_path_without_unlinking_target(target)
        if snapshot is not None:
            _copy_path_without_following(snapshot, target)

        current_auxiliary = _publication_auxiliary_paths(target)
        old_set = set(old_auxiliary)
        for auxiliary in current_auxiliary:
            if auxiliary not in old_set:
                _discard_path_without_unlinking_target(auxiliary)


def _publish_prop_asset(private_glb: Path, private_sidecar: Path, final_glb: Path, final_sidecar: Path) -> None:
    """Publish a prop GLB and sidecar as one rollback-safe pair."""

    for path, label in (
        (final_glb.parent, "prop GLB publication parent"),
        (final_sidecar.parent, "prop sidecar publication parent"),
        (final_glb, "prop GLB publication target"),
        (final_sidecar, "prop sidecar publication target"),
    ):
        _validate_publication_target(path, label)
    for path, label in (
        (private_glb, "private prop GLB"),
        (private_sidecar, "private prop sidecar"),
    ):
        _validate_publication_target(path, label)
        try:
            if not stat.S_ISREG(path.lstat().st_mode):
                raise ValueError(f"{label} must be a regular file: {path}")
        except FileNotFoundError as exc:
            raise ValueError(f"{label} is missing: {path}") from exc

    final_glb.parent.mkdir(parents=True, exist_ok=True)
    final_sidecar.parent.mkdir(parents=True, exist_ok=True)
    _validate_publication_target(final_glb.parent, "prop GLB publication parent")
    _validate_publication_target(final_sidecar.parent, "prop sidecar publication parent")
    transactions: list[tuple[Path, Path | None]] = []
    try:
        for source, target in ((private_glb, final_glb), (private_sidecar, final_sidecar)):
            backup: Path | None = None
            if _path_exists_without_following(target):
                backup = target.with_name(f".{target.name}.previous-{next(tempfile._get_candidate_names())}")
                os.replace(target, backup)
            transactions.append((target, backup))
            os.replace(source, target)
    except BaseException:
        for target, backup in reversed(transactions):
            if backup is None:
                _discard_path_without_unlinking_target(target)
            else:
                os.replace(backup, target)
        raise
    for _target, backup in transactions:
        if backup is not None:
            _discard_path_without_unlinking_target(backup)


def _copy_pressure_package(private_root: Path, project_root: Path) -> None:
    source = project_root / PRESSURE_PACKAGE
    target = private_root / "structural/pressure_door_1x1"
    filenames = (
        "pressure_door_1x1.manifest.json",
        "pressure_door_1x1.input.json",
        "pressure_door_1x1.tscn",
    )
    _validate_publication_target(source, "pressure-door source package")
    _validate_publication_target(target, "private pressure-door package")
    try:
        source_mode = source.lstat().st_mode
    except OSError as exc:
        raise FileNotFoundError(f"pressure-door staged wrapper package is missing: {source}") from exc
    if not stat.S_ISDIR(source_mode):
        raise FileNotFoundError(f"pressure-door staged wrapper package is missing: {source}")
    source_files: list[Path] = []
    for filename in filenames:
        path = source / filename
        _validate_publication_target(path, "pressure-door source package entry")
        try:
            mode = path.lstat().st_mode
        except FileNotFoundError as exc:
            raise FileNotFoundError(f"pressure-door staged wrapper package is missing: {path}") from exc
        if not stat.S_ISREG(mode):
            raise ValueError(f"pressure-door package entry must be a regular file: {path}")
        source_files.append(path)
    destinations = [target / source_file.name for source_file in source_files]
    for destination in destinations:
        _validate_publication_target(destination, "private pressure-door package entry")
    target.mkdir(parents=True, exist_ok=True)
    _validate_publication_target(target, "private pressure-door package")
    for source_file, destination in zip(source_files, destinations, strict=True):
        _validate_publication_target(destination, "private pressure-door package entry")
        shutil.copy2(source_file, destination)


def _validate_staged_glb_input(path: Path) -> None:
    """Validate the immutable GLB input before any evidence copy."""

    _validate_publication_target(path, "staged GLB input")
    try:
        info = path.lstat()
    except OSError as exc:
        raise ValueError(f"cannot inspect staged GLB input: {path}") from exc
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"staged GLB input must be a regular file: {path}")
    if info.st_size > MAX_STAGED_GLB_INPUT_BYTES:
        raise ValueError(
            f"staged GLB input exceeds size cap of {MAX_STAGED_GLB_INPUT_BYTES} bytes: {path}"
        )


def _process_asset(args: argparse.Namespace, asset_id: str, private_root: Path) -> tuple[dict[str, Any], Path | None, dict[str, Any]]:
    if os.environ.get("FOCUSED_NINE_FORCE_EXPORT_FAILURE") == "1":
        error = f"forced export failure: {asset_id}"
        return (_asset_record(args.project_root, args, asset_id, None, (), _empty_metrics(), [error], False, error), None, {})

    source = _ensure_source(args, asset_id)
    _run_recipe(args, asset_id)
    kind = "structural" if asset_id in contract.STRUCTURAL_IDS else "prop"
    role_metrics: dict[str, Any] = {}
    if kind == "structural":
        if asset_id != "pressure_door_1x1":
            _write_structural_source_record(args, asset_id, source)
        destination = private_root / "structural" / asset_id
        staged = _run_structural_export(source, asset_id, destination)
    else:
        destination = private_root / "props"
        staged = _run_prop_export(source, asset_id, destination)
        _validate_staged_glb_input(staged[0])
        sidecar_path = destination / f"{asset_id}.sidecar.json"
        sidecar = _gate_prop_sidecar(args.project_root, staged[0], asset_id, sidecar_path)
        role_metrics["sidecar"] = sidecar

    evidence_records: dict[str, dict[str, Any]] = {}
    for path in staged:
        _validate_staged_glb_input(path)
        record = evidence.inspect_staged_glb(path, BLENDER)
        errors = evidence.validate_evidence(
            record,
            *evidence.DEFAULT_TRIANGLE_BUDGETS["structural" if kind == "structural" else "prop"],
        )
        if errors:
            raise ValueError(f"evidence validation failed for {asset_id}: {'; '.join(errors)}")
        role = "intact" if path.name == f"{asset_id}.glb" else path.stem.removeprefix(f"{asset_id}_")
        evidence_records[role] = record
    if kind == "structural" and asset_id == "pressure_door_1x1":
        _write_structural_source_record(args, asset_id, source, candidate_glb=staged[0])
    if kind == "structural" and asset_id == "pressure_door_1x1":
        _copy_pressure_package(private_root, args.project_root)
    intact = evidence_records["intact"]
    for role, record in evidence_records.items():
        role_metrics[role] = {
            **_metrics_from_evidence(record),
            "path": f"res://{contract.asset_stage_glb(args.project_root, asset_id, role).relative_to(args.project_root.resolve()).as_posix()}",
            "validation": "PASS",
        }
    return (
        _asset_record(args.project_root, args, asset_id, source, staged, _metrics_from_evidence(intact), (), True, None, role_metrics),
        source,
        role_metrics,
    )


def _run_pressure_overlay(project_root: Path, private_root: Path) -> list[str]:
    command = [
        sys.executable,
        str(Path(__file__).with_name("focused_nine_staged_structural.py")),
        "--project-root",
        str(project_root),
        "--staging-root",
        str(private_root),
        "--godot",
        str(GODOT),
    ]
    try:
        result = _run(command, cwd=project_root, timeout=PRESSURE_OVERLAY_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired as exc:
        return [
            f"timed out after {PRESSURE_OVERLAY_TIMEOUT_SECONDS} seconds"
            + (f": {_failure_output(exc)}" if _failure_output(exc) != "exit unknown" else "")
        ]
    except OSError as exc:
        return [f"runner failed: {exc}"]
    if result.returncode != 0:
        return [_failure_output(result)]
    return []


def _preview_relative(project_root: Path, preview_dir: Path) -> str:
    stable = preview_dir / "focused-nine-comparison.png"
    return _canonical_res_path(project_root, stable)


def _capture_output(result: subprocess.CompletedProcess[str] | subprocess.TimeoutExpired) -> str:
    parts: list[str] = []
    for part in (getattr(result, "stdout", None), getattr(result, "stderr", None)):
        if isinstance(part, bytes):
            part = part.decode(errors="replace")
        if part:
            parts.append(str(part))
    return "\n".join(parts).strip()


def _cleanup_capture_temporary_files(preview_dir: Path) -> None:
    """Remove only regular capture temporary leaves after an interrupted run."""

    try:
        if preview_dir.is_symlink() or not preview_dir.is_dir():
            return
        for path in preview_dir.iterdir():
            if not path.name.startswith(".focused-nine-comparison") or path.is_symlink():
                continue
            try:
                if stat.S_ISREG(path.lstat().st_mode):
                    path.unlink()
            except OSError:
                continue
    except OSError:
        return


def _run_capture(project_root: Path, preview_dir: Path) -> tuple[bool, str | None, str]:
    try:
        output_relative = preview_dir.resolve().relative_to(project_root.resolve()).as_posix()
    except ValueError:
        return False, "capture output is outside the project", ""
    try:
        result = _run(
            [
                str(GODOT),
                "--path",
                str(project_root),
                "--scene",
                _CAPTURE_SCENE,
                "--",
                "--output-dir",
                f"res://{output_relative}",
                "--baseline-label",
                "Baseline",
                "--improved-label",
                "Improved",
            ],
            cwd=project_root,
            timeout=CAPTURE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        _cleanup_capture_temporary_files(preview_dir)
        return (
            False,
            f"comparison capture blocker: timed out after {CAPTURE_TIMEOUT_SECONDS} seconds",
            _capture_output(exc),
        )
    except OSError as exc:
        return False, f"comparison capture blocker: runner failed: {exc}", ""
    output = _capture_output(result)
    marker = "FOCUSED_NINE_COMPARISON_CAPTURE PASS output="
    if result.returncode != 0:
        detail = next((line.strip() for line in output.splitlines() if line.strip()), f"exit {result.returncode}")
        return False, f"comparison capture blocker: {detail}", output
    if any(
        line.strip().startswith(_CAPTURE_DIAGNOSTIC_MARKERS)
        for line in output.splitlines()
        if line.strip()
    ):
        return False, _CAPTURE_DIAGNOSTIC_BLOCKER, output
    if marker not in output:
        return False, "comparison capture blocker: missing FOCUSED_NINE_COMPARISON_CAPTURE PASS marker", output
    stable = preview_dir / "focused-nine-comparison.png"
    if not stable.is_file() or stable.stat().st_size <= 0:
        return False, "comparison capture blocker: stable preview was not published", output
    return True, None, output


def _run_live_validators(args: argparse.Namespace) -> tuple[list[str], list[str]]:
    structural_command = [
        sys.executable,
        str(Path(__file__).with_name("validate_structural_sources.py")),
        "--project-root",
        str(args.project_root),
        "--source-root",
        str(_validation_source_root(args)),
        "--all",
        "--blender",
        str(BLENDER),
    ]
    props_command = [
        sys.executable,
        str(Path(__file__).with_name("validate_prop_visual_bindings.py")),
        "--project-root",
        str(args.project_root),
        "--check-index",
    ]
    try:
        structural = _run(
            structural_command,
            cwd=args.project_root,
            timeout=STRUCTURAL_VALIDATOR_TIMEOUT_SECONDS,
        )
        structural_errors = (
            []
            if structural.returncode == 0
            else [f"live structural source validator: {_failure_output(structural)}"]
        )
    except subprocess.TimeoutExpired:
        structural_errors = [
            (
                "live structural source validator: "
                f"timed out after {STRUCTURAL_VALIDATOR_TIMEOUT_SECONDS} seconds"
            )
        ]
    except OSError as exc:
        structural_errors = [f"live structural source validator: {exc}"]
    try:
        props = _run(
            props_command,
            cwd=args.project_root,
            timeout=PROP_VALIDATOR_TIMEOUT_SECONDS,
        )
        prop_errors = (
            [] if props.returncode == 0 else [f"live prop index validator: {_failure_output(props)}"]
        )
    except subprocess.TimeoutExpired:
        prop_errors = [
            (
                "live prop index validator: "
                f"timed out after {PROP_VALIDATOR_TIMEOUT_SECONDS} seconds"
            )
        ]
    except OSError as exc:
        prop_errors = [f"live prop index validator: {exc}"]
    return structural_errors, prop_errors


def _build_report(
    project_root: Path,
    report_path: Path,
    preview_dir: Path,
    records: list[dict[str, Any]],
    source_paths: dict[str, str],
    role_metrics: dict[str, dict[str, Any]],
    *,
    runtime_unchanged: bool,
    capture_attempted: bool = False,
    capture_blocker: str | None = None,
    validator_errors: Sequence[str] = (),
) -> dict[str, Any]:
    blockers = list(validator_errors)
    if capture_blocker:
        blockers.append(capture_blocker)
    if not runtime_unchanged:
        blockers.append("runtime mutation surface content changed")
    if blockers:
        blocker = blockers[0]
        for asset in records:
            if asset["pass"]:
                asset["pass"] = False
                asset["validation"] = [blocker]
                asset["first_error"] = blocker
    overall = bool(records) and all(asset["pass"] for asset in records) and not blockers
    report = {
        "schema_version": "1.0.0",
        "document_kind": "focused_nine_comparison",
        "assets": records,
        "baseline": {
            "label": "current-runtime",
            "asset_count": len(records),
            "runtime_surfaces_unchanged": runtime_unchanged,
            "no_runtime_promotion": True,
            "no_original_source_replacement": True,
        },
        "improved": {
            "label": "focused-nine-staged",
            "asset_count": len(records),
            "source_paths": source_paths,
            "source_origin": "focused-nine-generated-source-root",
            "source_reference_root": "res://assets/_staging/focused_nine/source_refs",
            "no_original_source_replacement": True,
            "asset_role_metrics": role_metrics,
            "no_runtime_promotion": True,
        },
        "preview": {
            "path": _preview_relative(project_root, preview_dir),
            "capture_status": (
                "pass"
                if capture_attempted and capture_blocker is None and not validator_errors
                else "blocked"
                if capture_blocker or validator_errors
                else "not_run"
            ),
            "capture_blocker": capture_blocker,
            "validator_errors": list(validator_errors),
            "no_runtime_promotion": True,
        },
        "overall_pass": overall,
    }
    errors = validate_report(report)
    if errors:
        raise ValueError("focused-nine report schema failed: " + "; ".join(errors))
    return report


def _write_proof(
    project_root: Path,
    records: Sequence[dict[str, Any]],
    source_paths: dict[str, str],
    report_path: Path,
    preview_dir: Path,
    role_metrics: dict[str, dict[str, Any]],
) -> None:
    if (
        len(records) != len(ORDERED_ASSET_IDS)
        or tuple(asset.get("asset_id") for asset in records) != ORDERED_ASSET_IDS
        or any(
            asset.get("pass") is not True
            or asset.get("validation") != []
            or asset.get("first_error") is not None
            for asset in records
        )
    ):
        raise ValueError("cannot write proof before all assets pass")

    lines = [
        "# Focused-nine comparison evidence",
        "",
        "The focused-nine comparison batch passed its staging, evidence, pressure-door overlay, live-validator, and windowed-capture gates.",
        "",
        "**No runtime promotion occurred.** Runtime imported assets, generated catalogs, kit data, and live wrapper surfaces were not modified.",
        "",
        "**No original source replacement occurred.** Focused generated source references use the logical `res://assets/_staging/focused_nine/source_refs/` namespace; absolute source paths are intentionally omitted.",
        "",
        f"- Report: `{report_path.relative_to(project_root).as_posix()}`",
        f"- Preview: `{(preview_dir / 'focused-nine-comparison.png').relative_to(project_root).as_posix()}`",
        "",
        "## Asset validation and role metrics",
        "",
    ]
    for asset in records:
        asset_id = asset["asset_id"]
        if asset_id not in source_paths:
            raise ValueError(f"cannot write proof without source path: {asset_id}")
        lines.extend(
            (
                f"### `{asset_id}`",
                "",
                f"- Source: `{_source_reference(asset_id)}`",
                "- Validation result: `PASS`",
                "",
                "| Role | Validation | Path | SHA-256 | Bytes | Triangles | Meshes | Materials |",
                "| --- | --- | --- | --- | ---: | ---: | ---: | --- |",
            )
        )
        expected_roles = contract.VARIANT_ROLES.get(asset_id, ("intact",))
        asset_role_metrics = role_metrics.get(asset_id)
        if not isinstance(asset_role_metrics, dict):
            raise ValueError(f"cannot write proof without role metrics: {asset_id}")
        for index, role in enumerate(expected_roles):
            metrics = asset_role_metrics.get(role)
            if not isinstance(metrics, dict):
                raise ValueError(f"cannot write proof without role metrics: {asset_id}/{role}")
            required = ("path", "sha256", "byte_size", "triangle_count", "mesh_count", "material_names", "validation")
            if any(field not in metrics for field in required):
                raise ValueError(f"cannot write proof with incomplete role metrics: {asset_id}/{role}")
            if metrics["path"] != asset["staged_glbs"][index] or metrics["validation"] != "PASS":
                raise ValueError(f"cannot write proof with invalid role metrics: {asset_id}/{role}")
            lines.append(
                f"| `{role}` | `{metrics['validation']}` | `{metrics['path']}` | `{metrics['sha256']}` | "
                f"{metrics['byte_size']} | {metrics['triangle_count']} | {metrics['mesh_count']} | "
                f"{', '.join(metrics['material_names'])} |"
            )
        lines.append("")
    lines.extend(("", "Acceptance marker: `FOCUSED_NINE_BATCH PASS assets=9`", ""))
    _atomic_write_bytes(project_root / PROOF_RELATIVE, "\n".join(lines).encode("utf-8"))


def _run_capture_for_private_stage(
    project_root: Path, private_root: Path, preview_dir: Path
) -> tuple[bool, str | None, str]:
    """Run capture against a disposable project containing the private stage."""

    with tempfile.TemporaryDirectory(prefix="focused-nine-capture-overlay-") as temporary:
        overlay = Path(temporary) / "project"
        shutil.copytree(
            project_root,
            overlay,
            symlinks=True,
            ignore=shutil.ignore_patterns(".git", ".godot"),
        )
        overlay_stage = overlay / "assets/_staging/focused_nine"
        if _path_exists_without_following(overlay_stage):
            _discard_path_without_unlinking_target(overlay_stage)
        shutil.copytree(private_root, overlay_stage, symlinks=False)
        overlay_preview = overlay / "artifacts/validation-previews/focused-nine"
        captured, blocker, output = _run_capture(overlay, overlay_preview)
        if captured:
            candidate = private_root / ".focused-nine-comparison.png"
            shutil.copy2(overlay_preview / "focused-nine-comparison.png", candidate)
        return captured, blocker, output


def _publish_requested_assets(
    project_root: Path, asset_ids: Sequence[str], private_root: Path
) -> None:
    """Publish a requested batch with exact-target rollback on late failure."""

    targets: list[Path] = []
    for asset_id in asset_ids:
        if asset_id in contract.STRUCTURAL_IDS:
            targets.append(contract.asset_stage_dir(project_root, asset_id))
        else:
            final_glb = contract.asset_stage_glb(project_root, asset_id)
            targets.extend((final_glb, final_glb.with_name(f"{asset_id}.sidecar.json")))

    snapshot_root = private_root / ".publication-snapshots"
    snapshots = _snapshot_publication_targets(targets, snapshot_root)
    try:
        for asset_id in asset_ids:
            if asset_id in contract.STRUCTURAL_IDS:
                _publish_structural_asset(
                    private_root / "structural" / asset_id,
                    contract.asset_stage_dir(project_root, asset_id),
                )
            else:
                final_glb = contract.asset_stage_glb(project_root, asset_id)
                _publish_prop_asset(
                    private_root / "props" / f"{asset_id}.glb",
                    private_root / "props" / f"{asset_id}.sidecar.json",
                    final_glb,
                    final_glb.with_name(f"{asset_id}.sidecar.json"),
                )
    except BaseException as exc:
        try:
            _restore_publication_targets(snapshots)
        except BaseException as recovery_exc:  # noqa: BLE001 - report rollback failure
            raise RuntimeError(
                f"publication failed and transaction rollback failed: {recovery_exc}"
            ) from exc
        raise


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = parse_args(argv)
        project_root, report_path, preview_dir = _validate_output_paths(
            args.project_root, args.report, args.preview_dir
        )
        before_runtime = snapshot_runtime_surfaces(project_root)
        if args.dry_run:
            print("FOCUSED_NINE_BATCH DRY_RUN assets=" + str(len(args.assets)))
            return 0

        stage_root = _stage_root(project_root)
        stage_root.mkdir(parents=True, exist_ok=True)
        requested_records: list[dict[str, Any]] = []
        source_paths: dict[str, str] = {}
        role_metrics: dict[str, dict[str, Any]] = {}
        full_batch = args.assets == ORDERED_ASSET_IDS
        pressure_requested = "pressure_door_1x1" in args.assets
        capture_blocker: str | None = None
        validator_errors: list[str] = []
        capture_attempted = False
        private_capture: Path | None = None

        # Keep every candidate, wrapper resource, and capture inside one private
        # workspace.  No stage target is touched until every requested gate has
        # passed.
        with tempfile.TemporaryDirectory(prefix="focused-nine-batch-", dir=str(stage_root)) as temporary:
            private_root = Path(temporary)
            for asset_id in args.assets:
                try:
                    record, source, roles = _process_asset(args, asset_id, private_root)
                    requested_records.append(record)
                    if source is not None:
                        source_paths[asset_id] = _source_reference(asset_id)
                    role_metrics[asset_id] = roles
                except BaseException as exc:  # noqa: BLE001 - report every asset gate failure
                    message = str(exc) or f"{type(exc).__name__}"
                    requested_records.append(
                        _asset_record(
                            project_root,
                            args,
                            asset_id,
                            None,
                            (),
                            _empty_metrics(),
                            [message],
                            False,
                            message,
                        )
                    )

            requested_pass = (
                len(requested_records) == len(args.assets)
                and all(record["pass"] for record in requested_records)
            )
            if requested_pass and pressure_requested:
                try:
                    overlay_errors = _run_pressure_overlay(project_root, private_root)
                except BaseException as exc:  # noqa: BLE001 - convert runner failures to blockers
                    overlay_errors = [str(exc) or f"{type(exc).__name__}"]
                if overlay_errors:
                    capture_blocker = "pressure-door overlay blocker: " + "; ".join(overlay_errors)

            if requested_pass and full_batch:
                if capture_blocker is None:
                    capture_attempted = True
                    try:
                        captured, capture_blocker, _capture_output = _run_capture_for_private_stage(
                            project_root, private_root, preview_dir
                        )
                    except BaseException as exc:  # noqa: BLE001 - convert capture failures to blockers
                        captured = False
                        capture_blocker = f"comparison capture blocker: {str(exc) or type(exc).__name__}"
                    if not captured and capture_blocker is None:
                        capture_blocker = "comparison capture blocker: capture did not complete"
                try:
                    structural_errors, prop_errors = _run_live_validators(args)
                except OSError as exc:
                    validator_errors.append(f"live validators runner failed: {exc}")
                else:
                    validator_errors.extend(structural_errors)
                    validator_errors.extend(prop_errors)

            gates_passed = requested_pass and capture_blocker is None and not validator_errors
            if gates_passed:
                try:
                    _publish_requested_assets(project_root, args.assets, private_root)
                except BaseException as exc:  # noqa: BLE001 - restore transaction before reporting
                    message = str(exc) or f"{type(exc).__name__}"
                    validator_errors.append(f"publication blocker: {message}")
                    for record in requested_records:
                        if record["asset_id"] in args.assets:
                            record["pass"] = False
                            record["validation"] = [message]
                            record["first_error"] = message
                    gates_passed = False

            private_capture = private_root / ".focused-nine-comparison.png"
            if gates_passed and private_capture.is_file():
                _atomic_write_bytes(preview_dir / "focused-nine-comparison.png", private_capture.read_bytes())

        report_records: dict[str, dict[str, Any]] = {
            record["asset_id"]: record for record in requested_records
        }
        for asset_id in ORDERED_ASSET_IDS:
            if asset_id not in report_records:
                error = f"asset not requested by subset CLI: {asset_id}"
                report_records[asset_id] = _asset_record(
                    project_root,
                    args,
                    asset_id,
                    None,
                    (),
                    _empty_metrics(),
                    [error],
                    False,
                    error,
                )
        records = [report_records[asset_id] for asset_id in ORDERED_ASSET_IDS]

        after_runtime = snapshot_runtime_surfaces(project_root)
        runtime_unchanged = before_runtime == after_runtime
        report = _build_report(
            project_root,
            report_path,
            preview_dir,
            records,
            source_paths,
            role_metrics,
            runtime_unchanged=runtime_unchanged,
            capture_attempted=capture_attempted,
            capture_blocker=capture_blocker,
            validator_errors=validator_errors,
        )
        _atomic_write_bytes(report_path, _canonical_json(report))

        if report["overall_pass"] and full_batch:
            _write_proof(project_root, records, source_paths, report_path, preview_dir, role_metrics)
            for record in records:
                print(f"FOCUSED_NINE_STAGED asset={record['asset_id']}")
            print(f"FOCUSED_NINE_REPORT path={report_path}")
            print("FOCUSED_NINE_BATCH PASS assets=9")
            return 0
        print(f"FOCUSED_NINE_REPORT path={report_path}")
        for record in records:
            if record["pass"] and record["asset_id"] in args.assets:
                print(f"FOCUSED_NINE_STAGED asset={record['asset_id']}")
        return 1
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
