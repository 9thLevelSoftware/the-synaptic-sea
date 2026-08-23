#!/usr/bin/env python3
"""Inspect focused-nine staged GLBs and publish bounded evidence safely.

This tool intentionally accepts only caller-provided GLBs physically beneath an
``assets/_staging/focused_nine`` subtree.  It never imports or writes a runtime
asset and publishes JSON through a pinned, no-follow parent directory.

Security boundary (``trusted_workspace``): before the tool takes its initial
filesystem observation and pins descriptors, the project and staging tree must
not be concurrently renamed or rebound by a same-permission actor.  That
pre-observation threat is intentionally outside this boundary; it is not
claimed to be prevented.  After validation, staged reads and evidence
publication use no-follow, descriptor-relative operations plus ``(st_dev,
st_ino)`` identity checks.  Direct runtime and ``assets/imported`` paths remain
denied.  Emitted evidence contains asset metrics and hashes only; it does not
include host paths, usernames, or other personal-data provenance.
"""

from __future__ import annotations

import argparse
import inspect
import json
import math
import os
import secrets
import selectors
import signal
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from tools.prop_visual_metadata import read_glb_metadata
    from tools.validate_promoted_sources import validate_glb_magic
except ModuleNotFoundError:  # pragma: no cover - supports direct script execution
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools.prop_visual_metadata import read_glb_metadata
    from tools.validate_promoted_sources import validate_glb_magic


DEFAULT_TRIANGLE_BUDGETS: dict[str, tuple[int, int]] = {
    "structural": (350, 1500),
    "prop": (300, 1200),
}
SECURITY_BOUNDARY = "trusted_workspace"
TRUST_BOUNDARY_DOCUMENTATION = (
    "trusted_workspace: before initial filesystem observation and descriptor pinning, "
    "the caller must prevent same-permission concurrent rename or rebind of the project "
    "and staging tree; that pre-observation threat is intentionally outside this boundary "
    "and is not claimed to be prevented. Thereafter, FD-relative no-follow operations "
    "and (st_dev, st_ino) identity checks pin staged reads and evidence publication; direct "
    "runtime and assets/imported paths remain denied. Emitted evidence contains asset "
    "metrics and hashes only, without host paths, usernames, or other personal-data provenance."
)
_STAGE_MARKER = ("assets", "_staging", "focused_nine")
_IMPORTED_MARKER = ("assets", "imported")
_CORE_FIELDS = ("triangle_count", "mesh_count", "material_names", "blender_reimport_passed")
_METADATA_FIELDS = (
    "sha256",
    "byte_size",
    "gltf_version",
    "mesh_count",
    "local_min_m",
    "local_max_m",
)
_OPTIONAL_INSPECTOR_FIELDS = ("blender_version", "inspector_version")
_INSPECTOR_FIELDS = frozenset(("triangle_count", "material_names", "blender_reimport_passed"))
_INSPECTOR_MARKER = "FOCUSED_NINE_EVIDENCE_V1:"
_BLENDER_INSPECTOR_TIMEOUT_SECONDS = 120.0
_BLENDER_INSPECTOR_OUTPUT_LIMIT = 64 * 1024
_BLENDER_INSPECTOR_READ_CHUNK = 8192
_BLENDER_INSPECTOR_DRAIN_SECONDS = 0.25
_DIR_FD_SUPPORT = frozenset(getattr(os, "supports_dir_fd", ()))
_DIR_FD_OPERATIONS_SUPPORTED = all(
    function in _DIR_FD_SUPPORT for function in (os.open, os.mkdir, os.unlink)
)
_REPLACE_DIR_FD_SUPPORTED = (
    os.replace in _DIR_FD_SUPPORT
    or all(
        parameter in inspect.signature(os.replace).parameters
        for parameter in ("src_dir_fd", "dst_dir_fd")
    )
)


_BLENDER_INSPECTOR = r'''import bpy
import json
import sys


def _reset_and_import(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=path)
    if "FINISHED" not in result:
        raise RuntimeError("GLB import did not finish")


def _metrics():
    meshes = list(bpy.data.meshes)
    if not meshes:
        raise RuntimeError("GLB import produced no meshes")
    triangles = 0
    materials = set()
    for mesh in meshes:
        mesh.calc_loop_triangles()
        triangles += len(mesh.loop_triangles)
        for slot in mesh.materials:
            if slot is not None and isinstance(slot.name, str) and slot.name:
                materials.add(slot.name)
    if triangles <= 0:
        raise RuntimeError("GLB import produced no triangles")
    if not materials:
        raise RuntimeError("GLB import produced no named materials")
    return {
        "triangle_count": triangles,
        "material_names": sorted(materials),
        "mesh_datablock_count": len(meshes),
    }


try:
    separator = sys.argv.index("--")
    glb_path = sys.argv[separator + 1]
except (ValueError, IndexError):
    raise RuntimeError("inspector requires a GLB path")

_reset_and_import(glb_path)
first = _metrics()
_reset_and_import(glb_path)
second = _metrics()
if first != second:
    raise RuntimeError("clean GLB reimport was not deterministic")

print("FOCUSED_NINE_EVIDENCE_V1:" + json.dumps({
    "triangle_count": first["triangle_count"],
    "material_names": first["material_names"],
    "blender_reimport_passed": True,
}, sort_keys=True))
'''


def _sorted_errors(errors: list[str]) -> list[str]:
    return sorted(set(errors))


def _is_nonnegative_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _is_positive_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _is_finite_number(value: object) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    return isinstance(value, float) and math.isfinite(value)


def _finite_vector(value: object) -> bool:
    return isinstance(value, (list, tuple)) and len(value) == 3 and all(
        _is_finite_number(item) for item in value
    )


def _safe_nested_label(label: str, key: object) -> str:
    if type(key) is not str or len(key) > 128:
        return f"{label}.<key>"
    return f"{label}.{key}"


def _append_nonfinite(value: object, label: str, errors: list[str]) -> None:
    """Find non-finite values without assuming a well-formed JSON-like value."""

    stack: list[tuple[object, str]] = [(value, label)]
    seen: set[int] = set()
    inspected = 0
    while stack:
        current, current_label = stack.pop()
        inspected += 1
        if inspected > 10_000:
            errors.append("record contains too many nested values")
            return
        if isinstance(current, float):
            if not math.isfinite(current):
                errors.append(f"{current_label} contains non-finite value")
            continue
        if isinstance(current, dict):
            identity = id(current)
            if identity in seen:
                continue
            seen.add(identity)
            for key in current:
                if not isinstance(key, str):
                    errors.append(f"{current_label} contains a non-string object key")
                    continue
                try:
                    child = current[key]
                except BaseException:
                    errors.append(f"{current_label} contains an unreadable mapping value")
                    continue
                stack.append((child, _safe_nested_label(current_label, key)))
            continue
        if isinstance(current, (list, tuple)):
            identity = id(current)
            if identity in seen:
                continue
            seen.add(identity)
            try:
                length = len(current)
            except BaseException:
                errors.append(f"{current_label} contains an unreadable sequence")
                continue
            for index in range(length - 1, -1, -1):
                try:
                    child = current[index]
                except BaseException:
                    errors.append(f"{current_label} contains an unreadable sequence")
                    break
                stack.append((child, f"{current_label}[{index}]"))


def _record_shape_errors(record: object) -> list[str]:
    errors: list[str] = []
    if not isinstance(record, dict):
        return ["record must be an object"]

    for field in _CORE_FIELDS:
        if field not in record:
            errors.append(f"record missing field: {field}")

    triangle_count = record.get("triangle_count")
    if not _is_nonnegative_int(triangle_count):
        errors.append("triangle_count must be a finite non-negative integer")

    mesh_count = record.get("mesh_count")
    if not _is_positive_int(mesh_count):
        errors.append("mesh_count must be a positive finite integer")

    material_names = record.get("material_names")
    if not isinstance(material_names, list) or not material_names:
        errors.append("material_names must be a non-empty list of non-empty strings")
    elif not all(isinstance(name, str) and bool(name) for name in material_names):
        errors.append("material_names must be a non-empty list of non-empty strings")
    elif material_names != sorted(set(material_names)):
        errors.append("material_names must be sorted and unique")

    if "material_count" in record:
        material_count = record.get("material_count")
        if not _is_nonnegative_int(material_count):
            errors.append("material_count must be a finite non-negative integer")
        elif isinstance(material_names, list) and material_count != len(material_names):
            errors.append("material_count must match material_names length")

    if record.get("blender_reimport_passed") is not True:
        errors.append("blender_reimport_passed must be true")

    if "sha256" in record:
        sha256 = record.get("sha256")
        if not isinstance(sha256, str) or len(sha256) != 64 or any(
            character not in "0123456789abcdef" for character in sha256
        ):
            errors.append("sha256 must be 64 lowercase hexadecimal characters")

    if "byte_size" in record and not _is_positive_int(record.get("byte_size")):
        errors.append("byte_size must be a positive finite integer")

    if "gltf_version" in record and record.get("gltf_version") != "2.0":
        errors.append("gltf_version must be 2.0")

    for field in ("local_min_m", "local_max_m"):
        if field in record and not _finite_vector(record.get(field)):
            errors.append(f"{field} must be a finite 3-vector")

    _append_nonfinite(record, "record", errors)
    return _sorted_errors(errors)


def validate_evidence(record: dict, minimum: int, maximum: int) -> list[str]:
    """Return sorted, deterministic diagnostics for a Blender evidence record.

    The function is deliberately total over malformed JSON-like values: callers
    receive diagnostics instead of a validation-time exception.
    """

    try:
        errors = _record_shape_errors(record)
        try:
            json.dumps(record, allow_nan=False)
        except (TypeError, ValueError, OverflowError, RecursionError):
            errors.append("record must be JSON-serializable")
        if not _is_nonnegative_int(minimum):
            errors.append("minimum must be a non-negative integer")
        if not _is_nonnegative_int(maximum):
            errors.append("maximum must be a non-negative integer")
        if _is_nonnegative_int(minimum) and _is_nonnegative_int(maximum) and minimum > maximum:
            errors.append("minimum must not exceed maximum")

        triangle_count = record.get("triangle_count") if isinstance(record, dict) else None
        if (
            _is_nonnegative_int(triangle_count)
            and _is_nonnegative_int(minimum)
            and _is_nonnegative_int(maximum)
            and minimum <= maximum
        ):
            if triangle_count < minimum:
                errors.append(f"triangle budget below minimum: {triangle_count} < {minimum}")
            if triangle_count > maximum:
                errors.append(f"triangle budget exceeded: {triangle_count} > {maximum}")
        return _sorted_errors(errors)
    except BaseException as exc:  # validation must never throw for hostile JSON-like input
        return [f"record validation failed: {type(exc).__name__}"]


def _raw_absolute_path(path: Path, label: str) -> Path:
    try:
        raw = Path(path)
        if any(part == ".." for part in raw.parts):
            raise ValueError(f"{label} contains parent traversal")
        if any(part == "." for part in raw.parts):
            raise ValueError(f"{label} contains dot alias")
        return Path(os.path.abspath(os.fspath(raw)))
    except (OSError, TypeError, ValueError) as exc:
        if isinstance(exc, ValueError) and str(exc).startswith(label):
            raise
        raise ValueError(f"{label} could not be resolved: {exc}") from exc


def _marker_indexes(parts: tuple[str, ...], marker: tuple[str, ...]) -> list[int]:
    width = len(marker)
    return [index for index in range(len(parts) - width + 1) if parts[index : index + width] == marker]


def _path_from_parts(parts: tuple[str, ...], end: int) -> Path:
    result = Path(parts[0])
    for part in parts[1:end]:
        result /= part
    return result


@dataclass(frozen=True)
class _PathIdentitySnapshot:
    """Immutable identities captured before a descriptor-pinned operation."""

    entries: tuple[tuple[tuple[str, ...], tuple[int, int]], ...]

    def expected(self, parts: tuple[str, ...]) -> tuple[int, int] | None:
        for component_parts, identity in self.entries:
            if component_parts == parts:
                return identity
        return None


@dataclass(frozen=True)
class _ValidatedStagedGLB:
    lexical: Path
    stage_lexical: Path
    stage_resolved: Path
    resolved: Path
    identities: _PathIdentitySnapshot

    def __iter__(self):
        """Keep the historical three-value unpacking API for callers/tests."""

        yield self.lexical
        yield self.stage_lexical
        yield self.stage_resolved


@dataclass(frozen=True)
class _ValidatedJsonTarget:
    lexical: Path
    resolved_stage: Path
    identities: _PathIdentitySnapshot

    def __iter__(self):
        """Keep the historical two-value unpacking API for callers/tests."""

        yield self.lexical
        yield self.resolved_stage


def _snapshot_path_identities(path: Path, label: str) -> _PathIdentitySnapshot:
    """Capture no-follow ``(st_dev, st_ino)`` identities for existing prefixes."""

    if not path.is_absolute() or path.anchor != os.sep:
        raise ValueError(f"{label} requires an absolute POSIX path")
    entries: list[tuple[tuple[str, ...], tuple[int, int]]] = []
    for end in range(1, len(path.parts) + 1):
        component_parts = path.parts[:end]
        component = _path_from_parts(path.parts, end)
        try:
            info = os.lstat(component)
        except FileNotFoundError:
            break
        except OSError as exc:
            raise ValueError(f"{label} identity snapshot failed: {exc}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise ValueError(f"{label} contains a symlink component")
        entries.append((component_parts, (info.st_dev, info.st_ino)))
    return _PathIdentitySnapshot(tuple(entries))


def _validated_staged_glb(result: object) -> _ValidatedStagedGLB:
    if isinstance(result, _ValidatedStagedGLB):
        return result
    try:
        lexical, stage_lexical, stage_resolved = result  # type: ignore[misc]
    except (TypeError, ValueError) as exc:
        raise ValueError("GLB validation returned an invalid result") from exc
    identities = _snapshot_path_identities(lexical, "GLB path")
    return _ValidatedStagedGLB(
        lexical,
        stage_lexical,
        stage_resolved,
        lexical.resolve(strict=False),
        identities,
    )


def _validated_json_target(result: object) -> _ValidatedJsonTarget:
    if isinstance(result, _ValidatedJsonTarget):
        return result
    try:
        lexical, resolved_stage = result  # type: ignore[misc]
    except (TypeError, ValueError) as exc:
        raise ValueError("json-out validation returned an invalid result") from exc
    return _ValidatedJsonTarget(
        lexical,
        resolved_stage,
        _snapshot_path_identities(lexical, "json-out"),
    )


def _check_fd_identity(
    descriptor: int,
    expected: tuple[int, int] | None,
    label: str,
    *,
    required: bool,
) -> None:
    if expected is None:
        if required:
            raise ValueError(f"{label} identity snapshot is missing")
        return
    actual_stat = os.fstat(descriptor)
    actual = (actual_stat.st_dev, actual_stat.st_ino)
    if actual != expected:
        raise ValueError(f"{label} identity changed after validation")


def _stage_roots(path: Path, label: str) -> tuple[Path, Path, Path, Path]:
    lexical = _raw_absolute_path(path, label)
    indexes = _marker_indexes(lexical.parts, _STAGE_MARKER)
    if len(indexes) != 1:
        raise ValueError(f"{label} must be under focused-nine staging")
    stage_lexical = _path_from_parts(lexical.parts, indexes[0] + len(_STAGE_MARKER))
    try:
        stage_resolved = stage_lexical.resolve(strict=False)
        resolved = lexical.resolve(strict=False)
    except (OSError, RuntimeError) as exc:
        raise ValueError(f"{label} path could not be resolved: {exc}") from exc
    return lexical, stage_lexical, stage_resolved, resolved


def _contained(root: Path, candidate: Path) -> bool:
    return candidate == root or root in candidate.parents


def _has_symlink_component(path: Path) -> bool:
    current = Path(path.anchor)
    for component in path.parts[1:]:
        current /= component
        if current.is_symlink():
            return True
    return False


def _validate_staged_glb(glb_path: Path) -> _ValidatedStagedGLB:
    lexical, stage_lexical, stage_resolved, resolved = _stage_roots(glb_path, "GLB path")
    if _marker_indexes(lexical.parts, _IMPORTED_MARKER):
        raise ValueError("GLB path must not use assets/imported; caller must provide staged GLB")
    if lexical.suffix != ".glb":
        raise ValueError("GLB path must have a .glb extension")
    if not stage_lexical.is_dir() or _has_symlink_component(stage_lexical):
        raise ValueError("focused-nine staging root must be a real directory")
    if not _contained(stage_resolved, resolved):
        raise ValueError("GLB path escapes focused-nine staging via symlink")
    try:
        lexical_relative = lexical.relative_to(stage_lexical)
        resolved_relative = resolved.relative_to(stage_resolved)
    except ValueError as exc:
        raise ValueError("GLB path escapes focused-nine staging via symlink") from exc
    if lexical_relative != resolved_relative:
        raise ValueError("GLB path must not use a symlink alias in focused-nine staging")
    if lexical.is_symlink():
        raise ValueError("GLB path must not be a symlink alias")
    identities = _snapshot_path_identities(lexical, "GLB path")
    if identities.expected(lexical.parts) is None:
        raise ValueError("GLB path must exist")
    return _ValidatedStagedGLB(
        lexical,
        stage_lexical,
        stage_resolved,
        resolved,
        identities,
    )


def _pinned_input_open_flags() -> tuple[int, int]:
    directory_flag = getattr(os, "O_DIRECTORY", None)
    nofollow_flag = getattr(os, "O_NOFOLLOW", None)
    if directory_flag is None or nofollow_flag is None:
        raise OSError("staged GLB inspection requires O_DIRECTORY and O_NOFOLLOW")
    if os.open not in _DIR_FD_SUPPORT:
        raise OSError("staged GLB inspection requires directory-fd open operations")
    directory_flags = os.O_RDONLY | directory_flag | nofollow_flag
    file_flags = os.O_RDONLY | nofollow_flag
    if hasattr(os, "O_CLOEXEC"):
        directory_flags |= os.O_CLOEXEC
        file_flags |= os.O_CLOEXEC
    return directory_flags, file_flags


def _open_pinned_input_fd(
    path: Path, identities: _PathIdentitySnapshot | None = None
) -> int:
    directory_flags, file_flags = _pinned_input_open_flags()
    if not path.is_absolute() or path.anchor != os.sep or not path.name:
        raise OSError("staged GLB inspection requires an absolute POSIX path")
    if identities is not None and identities.expected(path.parts) is None:
        raise OSError("staged GLB final identity snapshot is missing")

    current_fd: int | None = os.open(os.sep, directory_flags)
    try:
        if identities is not None:
            _check_fd_identity(
                current_fd,
                identities.expected(path.parts[:1]),
                "staged GLB root",
                required=True,
            )
        for index, component in enumerate(path.parts[1:-1], start=2):
            if component in {"", ".", ".."}:
                raise OSError("staged GLB path contains an unsafe component")
            child_fd: int | None = None
            try:
                child_fd = os.open(component, directory_flags, dir_fd=current_fd)
                if identities is not None:
                    _check_fd_identity(
                        child_fd,
                        identities.expected(path.parts[:index]),
                        f"staged GLB component {component}",
                        required=True,
                    )
                previous_fd = current_fd
                current_fd = child_fd
                child_fd = None
                os.close(previous_fd)
            finally:
                if child_fd is not None:
                    os.close(child_fd)
        if current_fd is None:
            raise OSError("staged GLB inspection lost its parent directory fd")
        descriptor = os.open(path.name, file_flags, dir_fd=current_fd)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise OSError("staged GLB must be a regular file")
            if identities is not None:
                _check_fd_identity(
                    descriptor,
                    identities.expected(path.parts),
                    "staged GLB final file",
                    required=True,
                )
        except BaseException:
            os.close(descriptor)
            raise
        return descriptor
    finally:
        if current_fd is not None:
            os.close(current_fd)


def _copy_pinned_staged_glb(
    path: Path, temporary_directory: Path, identities: _PathIdentitySnapshot | None = None
) -> Path:
    source_fd: int | None = None
    temporary_path: Path | None = None
    try:
        source_fd = _open_pinned_input_fd(path, identities)
        # After this identity check, all input reads use source_fd.  A later
        # pathname rename cannot redirect the descriptor to another object.
        with tempfile.NamedTemporaryFile(
            mode="wb",
            prefix="staged-input-",
            suffix=".glb",
            dir=temporary_directory,
            delete=False,
        ) as destination:
            temporary_path = Path(destination.name)
            while True:
                chunk = os.read(source_fd, 1024 * 1024)
                if not chunk:
                    break
                destination.write(chunk)
            destination.flush()
            os.fsync(destination.fileno())
        os.chmod(temporary_path, 0o400)
        return temporary_path
    except (OSError, ValueError):
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except OSError:
                pass
        raise
    finally:
        if source_fd is not None:
            os.close(source_fd)


def _validate_json_target(target: Path, expected_stage: Path) -> _ValidatedJsonTarget:
    lexical, stage_lexical, stage_resolved, resolved = _stage_roots(target, "json-out")
    if _marker_indexes(lexical.parts, _IMPORTED_MARKER):
        raise ValueError("json-out must not target assets/imported or runtime surfaces")
    if stage_lexical != expected_stage:
        raise ValueError("json-out must use the caller's focused-nine staging subtree")
    if not stage_lexical.is_dir() or _has_symlink_component(stage_lexical):
        raise ValueError("focused-nine staging root must be a real directory")
    if lexical.suffix != ".json":
        raise ValueError("json-out must have a .json extension")
    if not _contained(stage_resolved, resolved):
        raise ValueError("json-out escapes focused-nine staging via symlink")
    try:
        lexical_relative = lexical.relative_to(stage_lexical)
        resolved_relative = resolved.relative_to(stage_resolved)
    except ValueError as exc:
        raise ValueError("json-out escapes focused-nine staging via symlink") from exc
    if lexical_relative != resolved_relative:
        raise ValueError("json-out must not use a symlink alias in focused-nine staging")
    if lexical.is_symlink():
        raise ValueError("json-out must not be a symlink")
    if lexical.exists() and not lexical.is_file():
        raise ValueError("json-out must be a regular file")
    return _ValidatedJsonTarget(
        lexical,
        stage_resolved,
        _snapshot_path_identities(lexical, "json-out"),
    )


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant: {value}")


def _reject_duplicate_json_keys(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("inspector evidence contains duplicate object keys")
        result[key] = value
    return result


def _validate_inspector_record(record: object) -> dict[str, Any]:
    if not isinstance(record, dict):
        raise ValueError("Blender inspector returned a non-object evidence record")
    if set(record) != _INSPECTOR_FIELDS:
        raise ValueError("Blender inspector returned unexpected inspector fields")

    triangle_count = record.get("triangle_count")
    if not _is_positive_int(triangle_count):
        raise ValueError("Blender inspector returned an invalid triangle_count")
    material_names = record.get("material_names")
    if (
        not isinstance(material_names, list)
        or not material_names
        or not all(type(name) is str and bool(name) for name in material_names)
        or material_names != sorted(set(material_names))
    ):
        raise ValueError("Blender inspector returned invalid material_names")
    if record.get("blender_reimport_passed") is not True:
        raise ValueError("Blender inspector did not confirm clean reimport")
    return record


def _parse_inspector_output(output: bytes | str) -> dict[str, Any]:
    try:
        text = output.decode("utf-8") if isinstance(output, bytes) else output
        result_lines = [line for line in text.splitlines() if line.startswith(_INSPECTOR_MARKER)]
    except (UnicodeDecodeError, AttributeError, TypeError):
        raise ValueError("Blender inspector returned malformed evidence") from None
    if len(result_lines) != 1:
        raise ValueError("Blender inspector returned no deterministic evidence record")
    try:
        result = json.loads(
            result_lines[0][len(_INSPECTOR_MARKER) :],
            object_pairs_hook=_reject_duplicate_json_keys,
            parse_constant=_reject_json_constant,
        )
    except (json.JSONDecodeError, RecursionError, TypeError, ValueError):
        raise ValueError("Blender inspector returned malformed evidence") from None
    return _validate_inspector_record(result)


def _require_process_group_support() -> None:
    if os.name != "posix" or any(
        not callable(getattr(os, name, None)) for name in ("getpgid", "killpg")
    ):
        raise ValueError("Blender inspector requires POSIX process-group support")
    if not all(hasattr(signal, name) for name in ("SIGTERM", "SIGKILL")):
        raise ValueError("Blender inspector requires POSIX process-group signals")


def _isolated_process_group_id(process: Any) -> int:
    pid = getattr(process, "pid", None)
    if type(pid) is not int or pid <= 1:
        raise OSError("Blender inspector process has no safe PID")
    try:
        process_group = os.getpgid(pid)
    except ProcessLookupError:
        # The session leader can exit before its descendants.  Its PID is
        # still the only safe group identifier established by Popen.
        process_group = pid
    except OSError as exc:
        raise OSError(f"could not verify Blender inspector process group: {exc}") from exc
    if process_group != pid:
        raise OSError("Blender inspector process is not an isolated session leader")
    return process_group


def _signal_process_group(signal_number: int, process_group: int) -> None:
    try:
        os.killpg(process_group, signal_number)
    except ProcessLookupError:
        pass


def _terminate_and_drain_process(process: Any, selector: selectors.BaseSelector) -> None:
    _require_process_group_support()
    process_group = _isolated_process_group_id(process)
    signal_error: OSError | None = None
    try:
        _signal_process_group(signal.SIGTERM, process_group)
    except OSError as exc:
        signal_error = exc
    try:
        process.wait(timeout=0.1)
    except (subprocess.TimeoutExpired, OSError):
        pass
    try:
        # Always send SIGKILL after the grace period: the session leader may
        # have exited while a descendant inherited the inspector's pipes.
        _signal_process_group(signal.SIGKILL, process_group)
    except OSError as exc:
        if signal_error is None:
            signal_error = exc
    try:
        process.wait(timeout=0.1)
    except (subprocess.TimeoutExpired, OSError):
        pass
    if signal_error is not None:
        raise signal_error

    deadline = time.monotonic() + _BLENDER_INSPECTOR_DRAIN_SECONDS
    while selector.get_map() and time.monotonic() < deadline:
        events = selector.select(max(0.0, deadline - time.monotonic()))
        if not events:
            break
        for key, _mask in events:
            try:
                chunk = os.read(key.fd, _BLENDER_INSPECTOR_READ_CHUNK)
            except OSError:
                chunk = b""
            if not chunk:
                try:
                    selector.unregister(key.fileobj)
                except (KeyError, ValueError):
                    pass


def _collect_bounded_process_output(process: Any) -> tuple[bytes, bytes, int, str | None]:
    selector = selectors.DefaultSelector()
    captured = {"stdout": bytearray(), "stderr": bytearray()}
    total = 0
    reason: str | None = None
    streams = (("stdout", process.stdout), ("stderr", process.stderr))
    try:
        for label, stream in streams:
            if stream is not None:
                selector.register(stream, selectors.EVENT_READ, label)
        deadline = time.monotonic() + _BLENDER_INSPECTOR_TIMEOUT_SECONDS
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                reason = "Blender inspector timed out"
                break
            events = selector.select(remaining)
            if not events:
                reason = "Blender inspector timed out"
                break
            for key, _mask in events:
                try:
                    chunk = os.read(key.fd, _BLENDER_INSPECTOR_READ_CHUNK)
                except OSError as exc:
                    reason = f"Blender inspector output read failed: {exc}"
                    break
                if not chunk:
                    try:
                        selector.unregister(key.fileobj)
                    except (KeyError, ValueError):
                        pass
                    continue
                total += len(chunk)
                if total > _BLENDER_INSPECTOR_OUTPUT_LIMIT:
                    reason = "Blender inspector output exceeded cap"
                    break
                captured[key.data].extend(chunk)
            if reason is not None:
                break

        if reason is None:
            while process.poll() is None:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    reason = "Blender inspector timed out"
                    break
                time.sleep(min(0.01, remaining))
        if reason is not None:
            _terminate_and_drain_process(process, selector)

        if reason is None:
            try:
                returncode = process.wait(timeout=max(0.0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                reason = "Blender inspector timed out"
                _terminate_and_drain_process(process, selector)
                returncode = process.returncode if process.returncode is not None else -1
        else:
            returncode = process.returncode if process.returncode is not None else -1
        return bytes(captured["stdout"]), bytes(captured["stderr"]), returncode, reason
    finally:
        selector.close()
        for _label, stream in streams:
            if stream is not None:
                stream.close()


def _run_blender_inspector(glb_path: Path, blender: Path) -> dict[str, Any]:
    _require_process_group_support()
    with tempfile.TemporaryDirectory(prefix="focused-nine-inspector-") as temporary:
        script = Path(temporary) / "inspect_glb.py"
        script.write_text(_BLENDER_INSPECTOR, encoding="utf-8")
        command = [
            os.fspath(blender),
            "--background",
            "--factory-startup",
            "--python",
            os.fspath(script),
            "--",
            os.fspath(glb_path),
        ]
        try:
            process = subprocess.Popen(
                command,
                cwd=temporary,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                start_new_session=True,
            )
        except OSError as exc:
            raise ValueError(f"could not invoke Blender inspector: {exc}") from exc

        stdout, _stderr, returncode, reason = _collect_bounded_process_output(process)
        if reason is not None:
            raise ValueError(reason)
        if returncode != 0:
            raise ValueError(f"Blender inspector failed with exit code {returncode}")
        return _parse_inspector_output(stdout)


def inspect_staged_glb(glb_path: Path, blender: Path) -> dict:
    """Read static GLB metadata, then inspect a clean Blender re-import.

    The caller supplies the ``trusted_workspace`` pre-observation boundary;
    after validation this function pins the staged input through FD-relative
    no-follow opens and identity checks before any GLB bytes are consumed.
    """

    validated = _validated_staged_glb(_validate_staged_glb(Path(glb_path)))
    staged_glb = validated.lexical
    with tempfile.TemporaryDirectory(prefix="focused-nine-input-") as temporary:
        try:
            immutable_glb = _copy_pinned_staged_glb(
                staged_glb,
                Path(temporary),
                validated.identities,
            )
        except OSError as exc:
            raise ValueError(f"could not securely copy staged GLB: {exc}") from exc

        magic_errors = validate_glb_magic(immutable_glb)
        if magic_errors:
            raise ValueError("; ".join(magic_errors))
        try:
            metadata = read_glb_metadata(immutable_glb)
        except (OSError, RuntimeError, TypeError, ValueError) as exc:
            raise ValueError(f"GLB metadata validation failed: {exc}") from exc

        blender_record = _validate_inspector_record(
            _run_blender_inspector(immutable_glb, Path(blender))
        )
        try:
            result = {field: metadata[field] for field in _METADATA_FIELDS}
        except (KeyError, TypeError) as exc:
            raise ValueError("GLB metadata validation returned incomplete static evidence") from exc
        result["triangle_count"] = blender_record["triangle_count"]
        result["material_names"] = list(blender_record["material_names"])
        result["material_count"] = len(result["material_names"])
        result["blender_reimport_passed"] = blender_record["blender_reimport_passed"]
        return result


def _canonical_json_bytes(record: dict) -> bytes:
    try:
        encoded = json.dumps(
            record,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        )
    except (TypeError, ValueError, OverflowError, RecursionError) as exc:
        raise ValueError(str(exc) or "evidence record is not JSON-serializable") from exc
    return (encoded + "\n").encode("utf-8")


def _pinned_directory_open_flags() -> int:
    directory_flag = getattr(os, "O_DIRECTORY", None)
    nofollow_flag = getattr(os, "O_NOFOLLOW", None)
    if directory_flag is None or nofollow_flag is None:
        raise OSError("evidence publication requires O_DIRECTORY and O_NOFOLLOW")
    if not _DIR_FD_OPERATIONS_SUPPORTED:
        raise OSError("evidence publication requires directory-fd operations")
    if not _REPLACE_DIR_FD_SUPPORTED:
        raise OSError("evidence publication requires directory-fd replace operations")
    return os.O_RDONLY | directory_flag | nofollow_flag


def _open_pinned_parent_directory(
    path: Path,
    directory_flags: int,
    identities: _PathIdentitySnapshot | None = None,
) -> int:
    if not path.is_absolute() or path.anchor != os.sep:
        raise OSError("evidence publication requires an absolute POSIX path")
    parent_parts = path.parent.parts
    current_fd: int | None = os.open(os.sep, directory_flags)
    try:
        if identities is not None:
            _check_fd_identity(
                current_fd,
                identities.expected(path.parts[:1]),
                "json-out root",
                required=True,
            )
        created_prefix = False
        for index, component in enumerate(parent_parts[1:], start=2):
            child_fd: int | None = None
            created_here = False
            try:
                try:
                    child_fd = os.open(component, directory_flags, dir_fd=current_fd)
                except FileNotFoundError:
                    try:
                        os.mkdir(component, mode=0o700, dir_fd=current_fd)
                    except FileExistsError as exc:
                        raise OSError(
                            f"json-out component {component} appeared during validation"
                        ) from exc
                    created_here = True
                    child_fd = os.open(component, directory_flags, dir_fd=current_fd)
                if identities is not None and not (created_prefix or created_here):
                    _check_fd_identity(
                        child_fd,
                        identities.expected(parent_parts[:index]),
                        f"json-out component {component}",
                        required=True,
                    )
                previous_fd = current_fd
                current_fd = child_fd
                child_fd = None
                os.close(previous_fd)
                created_prefix = created_prefix or created_here
            finally:
                if child_fd is not None:
                    os.close(child_fd)
        if current_fd is None:
            raise OSError("evidence publication lost its parent directory fd")
        result = current_fd
        current_fd = None
        return result
    finally:
        if current_fd is not None:
            os.close(current_fd)


def _validate_existing_json_leaf(
    directory_fd: int, path: Path, identities: _PathIdentitySnapshot | None
) -> None:
    nofollow_flag = getattr(os, "O_NOFOLLOW", None)
    if nofollow_flag is None:
        raise OSError("evidence publication requires O_NOFOLLOW")
    flags = os.O_RDONLY | nofollow_flag
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    expected = identities.expected(path.parts) if identities is not None else None
    try:
        descriptor = os.open(path.name, flags, dir_fd=directory_fd)
    except FileNotFoundError:
        if expected is not None:
            raise OSError("json-out target disappeared after validation") from None
        return
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise OSError("json-out target must be a regular file")
        if expected is None:
            raise OSError("json-out target appeared after validation")
        _check_fd_identity(descriptor, expected, "json-out target", required=True)
    finally:
        os.close(descriptor)


def _create_sibling_temp(directory_fd: int, target_name: str) -> tuple[int, str]:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    for _attempt in range(32):
        name = f".{target_name}.{secrets.token_hex(12)}.tmp"
        try:
            descriptor = os.open(name, flags, 0o600, dir_fd=directory_fd)
        except FileExistsError:
            continue
        return descriptor, name
    raise OSError("could not allocate an evidence temporary file")


def _publish_bytes_atomically(
    path: Path | _ValidatedJsonTarget, payload: bytes
) -> None:
    if isinstance(path, _ValidatedJsonTarget):
        target = path.lexical
        identities = path.identities
    else:
        target = path
        identities = None
    directory_flags = _pinned_directory_open_flags()
    directory_fd: int | None = None
    temporary_fd: int | None = None
    temporary_name: str | None = None
    primary_error: BaseException | None = None
    primary_traceback = None
    try:
        directory_fd = _open_pinned_parent_directory(target, directory_flags, identities)
        os.fsync(directory_fd)
        _validate_existing_json_leaf(directory_fd, target, identities)
        temporary_fd, temporary_name = _create_sibling_temp(directory_fd, target.name)
        handle = os.fdopen(temporary_fd, "wb")
        try:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        finally:
            handle.close()
            temporary_fd = None
        # POSIX does not let us prevent a rename after the final checks.  This
        # replace is nevertheless relative to the already-pinned directory fd
        # and never follows a pathname through a newly-resolved ancestor.
        os.replace(
            temporary_name,
            target.name,
            src_dir_fd=directory_fd,
            dst_dir_fd=directory_fd,
        )
        temporary_name = None
        os.fsync(directory_fd)
    except BaseException as exc:
        primary_error = exc
        primary_traceback = exc.__traceback__

    cleanup_error: BaseException | None = None
    cleanup_traceback = None
    if temporary_fd is not None:
        try:
            os.close(temporary_fd)
        except BaseException as exc:
            cleanup_error = exc
            cleanup_traceback = exc.__traceback__
    if temporary_name is not None and directory_fd is not None:
        try:
            os.unlink(temporary_name, dir_fd=directory_fd)
        except FileNotFoundError:
            pass
        except BaseException as exc:
            if cleanup_error is None:
                cleanup_error = exc
                cleanup_traceback = exc.__traceback__
    if directory_fd is not None:
        try:
            os.close(directory_fd)
        except BaseException as exc:
            if cleanup_error is None:
                cleanup_error = exc
                cleanup_traceback = exc.__traceback__

    if primary_error is not None:
        raise primary_error.with_traceback(primary_traceback)
    if cleanup_error is not None:
        raise cleanup_error.with_traceback(cleanup_traceback)


def publish_json_atomically(target: Path, record: dict) -> None:
    """Validate, canonicalize, and durably replace evidence JSON in staging.

    The caller supplies the ``trusted_workspace`` pre-observation boundary;
    after validation, the publisher pins the parent directory and rejects
    post-validation inode/device rebinds before its FD-relative replacement.
    """

    shape_errors = _record_shape_errors(record)
    if shape_errors:
        raise ValueError("; ".join(shape_errors))
    payload = _canonical_json_bytes(record)
    lexical_target = _raw_absolute_path(Path(target), "json-out")
    _lexical_target, stage_lexical, _stage_resolved, _resolved_target = _stage_roots(
        lexical_target, "json-out"
    )
    validated_target = _validated_json_target(
        _validate_json_target(lexical_target, stage_lexical)
    )
    _publish_bytes_atomically(validated_target, payload)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, epilog=TRUST_BOUNDARY_DOCUMENTATION)
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--kind", choices=tuple(DEFAULT_TRIANGLE_BUDGETS), required=True)
    parser.add_argument("--min-triangles", type=int)
    parser.add_argument("--max-triangles", type=int)
    parser.add_argument("--blender", type=Path, required=True)
    parser.add_argument("--json-out", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    default_minimum, default_maximum = DEFAULT_TRIANGLE_BUDGETS[args.kind]
    minimum = default_minimum if args.min_triangles is None else args.min_triangles
    maximum = default_maximum if args.max_triangles is None else args.max_triangles
    try:
        staged_glb, stage_lexical, _stage_resolved = _validate_staged_glb(args.glb)
        _validate_json_target(args.json_out, stage_lexical)
        record = inspect_staged_glb(staged_glb, args.blender)
        errors = validate_evidence(record, minimum, maximum)
        if errors:
            raise ValueError("; ".join(errors))
        publish_json_atomically(args.json_out, record)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(
        f"FOCUSED_NINE_EVIDENCE_PASS triangles={record['triangle_count']} "
        f"materials={record['material_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "DEFAULT_TRIANGLE_BUDGETS",
    "SECURITY_BOUNDARY",
    "TRUST_BOUNDARY_DOCUMENTATION",
    "inspect_staged_glb",
    "publish_json_atomically",
    "validate_evidence",
]
