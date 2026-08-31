"""Shared secure policy and publication primitives for Meshy task artifacts.

The helper intentionally has a narrow boundary: task files are confined to the
Meshy staging tree, runtime surfaces are deny-listed, and JSON publication uses
pinned directory descriptors rather than reopening a validated pathname.
"""

from __future__ import annotations

import hashlib
import inspect
import json
import math
import os
import secrets
import stat
from pathlib import Path
from typing import Any, Callable, Dict, List, NamedTuple, Optional, Tuple, Union


STAGING_RELATIVE = Path("assets/_staging/meshy")
PROTECTED_RUNTIME_RELATIVE_PATHS = (
    Path("assets/imported"),
    Path("data/combat"),
    Path("data/props"),
    Path("scenes/wrappers"),
)
DEFAULT_FILE_MAX_BYTES = 64 * 1024 * 1024


class ProtectedSurfaceRecord(NamedTuple):
    """Immutable manifest record for one protected runtime surface."""

    type: str
    path: str
    sha256: Optional[str]
    size: int

    @property
    def hash(self) -> Optional[str]:
        return self.sha256


# Tests and callers may use this seam to deterministically exercise the
# validation-to-open boundary.  It is deliberately a no-op in normal use.
_ATOMIC_VALIDATION_HOOK: Optional[Callable[[Path], None]] = None

# Capture capability markers before tests or callers inject wrappers around the
# low-level functions.  The actual operation still uses the current os.* call.
_ORIGINAL_OPEN = os.open
_ORIGINAL_MKDIR = os.mkdir
_ORIGINAL_UNLINK = os.unlink
_ORIGINAL_REPLACE = os.replace


def physical_project_root(path: Union[str, os.PathLike]) -> Path:
    """Resolve an explicit project-root alias once and require a directory."""

    candidate = Path(path).expanduser()
    try:
        resolved = candidate.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise ValueError(f"project root could not be resolved: {exc}") from exc
    if not resolved.is_dir():
        raise ValueError(f"project root must be a directory: {candidate}")
    return resolved


def protected_runtime_paths(root: Union[str, os.PathLike]) -> Tuple[Path, ...]:
    """Return the exact physical runtime surfaces protected from Meshy writes."""

    physical = physical_project_root(root)
    return tuple(physical / relative for relative in PROTECTED_RUNTIME_RELATIVE_PATHS)


def _absolute_lexical(path: Union[str, os.PathLike], base: Optional[Path] = None) -> Path:
    candidate = Path(path).expanduser()
    if not candidate.is_absolute():
        candidate = (base if base is not None else Path.cwd()) / candidate
    return Path(os.path.abspath(os.fspath(candidate)))


def _path_from_explicit_root(
    project_root: Union[str, os.PathLike], physical_root: Path, path: Union[str, os.PathLike]
) -> Path:
    """Map a path written through the explicit root alias to physical spelling."""

    explicit = _absolute_lexical(project_root)
    candidate = _absolute_lexical(path, physical_root)
    try:
        relative = candidate.relative_to(explicit)
    except ValueError:
        return candidate
    return physical_root / relative


def _contained(root: Path, candidate: Path) -> bool:
    return candidate == root or root in candidate.parents


def _lstat(path: Path, label: str) -> os.stat_result:
    try:
        return os.lstat(path)
    except FileNotFoundError:
        raise
    except OSError as exc:
        raise ValueError(f"{label} could not be inspected: {exc}") from exc


def _reject_symlink_components_below(root: Path, candidate: Path, label: str) -> None:
    """Reject symlink components below an already-resolved project root."""

    if not _contained(root, candidate):
        raise ValueError(f"{label} escapes project root")
    relative = candidate.relative_to(root)
    current = root
    for component in relative.parts:
        current = current / component
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            break
        except OSError as exc:
            raise ValueError(f"{label} could not be inspected: {exc}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise ValueError(f"{label} contains a symlink component")
        if current != candidate and not stat.S_ISDIR(info.st_mode):
            raise ValueError(f"{label} contains a non-directory ancestor")


def _resolved_below(root: Path, candidate: Path, label: str) -> Path:
    try:
        resolved = candidate.resolve(strict=False)
    except (OSError, RuntimeError) as exc:
        raise ValueError(f"{label} could not be resolved: {exc}") from exc
    if not _contained(root, resolved):
        raise ValueError(f"{label} escapes project root")
    return resolved


def governed_task_path(
    root: Union[str, os.PathLike],
    path: Union[str, os.PathLike],
    label: str,
    allow_missing: bool = True,
) -> Path:
    """Validate one task path as physically contained by Meshy staging."""

    physical = physical_project_root(root)
    candidate = _path_from_explicit_root(root, physical, path)
    stage = physical / STAGING_RELATIVE
    _reject_symlink_components_below(physical, stage, label)
    _reject_symlink_components_below(physical, candidate, label)
    resolved_stage = _resolved_below(physical, stage, label)
    resolved_candidate = _resolved_below(physical, candidate, label)
    if not _contained(resolved_stage, resolved_candidate):
        raise ValueError(f"{label} must be physically under Meshy staging")
    if not allow_missing and not candidate.exists():
        raise ValueError(f"{label} is missing")
    return candidate


def reject_protected_output(
    root: Union[str, os.PathLike], path: Union[str, os.PathLike], label: str
) -> Path:
    """Return a resolved output path unless it targets a protected surface."""

    physical = physical_project_root(root)
    candidate = _path_from_explicit_root(root, physical, path)
    try:
        resolved_candidate = candidate.resolve(strict=False)
    except (OSError, RuntimeError) as exc:
        raise ValueError(f"{label} protection check failed: {exc}") from exc
    for relative in PROTECTED_RUNTIME_RELATIVE_PATHS:
        protected = (physical / relative).resolve(strict=False)
        if _contained(protected, resolved_candidate):
            raise ValueError(f"{label} targets protected runtime surface: {relative}")
    return resolved_candidate


def canonical_json_bytes(value: object) -> bytes:
    """Encode JSON deterministically, rejecting non-finite numbers."""

    encoded = json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )
    return (encoded + "\n").encode("utf-8")


def _reject_duplicate_keys(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"non-standard JSON constant: {value}")


def _parse_finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite JSON number: {value}")
    return parsed


def _safe_file_path(path: Union[str, os.PathLike], label: str) -> Path:
    """Reject file symlinks, while accepting macOS /var and /tmp aliases."""

    lexical = _absolute_lexical(path)
    current = Path(lexical.anchor)
    mac_aliases = {
        Path("/var"): Path("/private/var"),
        Path("/tmp"): Path("/private/tmp"),
    }
    for component in lexical.parts[1:]:
        current = current / component
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            break
        except OSError as exc:
            raise ValueError(f"{label} could not be inspected: {exc}") from exc
        if stat.S_ISLNK(info.st_mode):
            resolved = current.resolve(strict=False)
            if current not in mac_aliases or resolved != mac_aliases[current]:
                raise ValueError(f"{label} contains a symlink component")
    try:
        return lexical.resolve(strict=False)
    except (OSError, RuntimeError) as exc:
        raise ValueError(f"{label} could not be resolved: {exc}") from exc


def _read_bounded_regular_file(path: Union[str, os.PathLike], label: str, max_bytes: int) -> bytes:
    if not isinstance(max_bytes, int) or isinstance(max_bytes, bool) or max_bytes < 0:
        raise ValueError(f"{label} max_bytes must be a non-negative integer")
    safe_path = _safe_file_path(path, label)
    try:
        info = os.lstat(safe_path)
    except FileNotFoundError as exc:
        raise ValueError(f"{label} is missing") from exc
    if stat.S_ISLNK(info.st_mode):
        raise ValueError(f"{label} must not be a symlink")
    if not stat.S_ISREG(info.st_mode):
        raise ValueError(f"{label} must be a regular file")
    if info.st_size > max_bytes:
        raise ValueError(f"{label} exceeds maximum size")

    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise ValueError(f"{label} requires O_NOFOLLOW")
    flags = os.O_RDONLY | nofollow
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    descriptor: Optional[int] = None
    try:
        try:
            descriptor = os.open(safe_path, flags)
        except OSError as exc:
            raise ValueError(f"{label} could not be opened safely: {exc}") from exc
        opened = os.fstat(descriptor)
        opened_identity = (opened.st_dev, opened.st_ino)
        if not stat.S_ISREG(opened.st_mode):
            raise ValueError(f"{label} must be a regular file")
        if opened_identity != (info.st_dev, info.st_ino):
            raise ValueError(f"{label} identity changed while opening")
        if opened.st_size > max_bytes:
            raise ValueError(f"{label} exceeds maximum size")
        chunks: List[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, min(1024 * 1024, max_bytes - total + 1))
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ValueError(f"{label} exceeds maximum size")
            chunks.append(chunk)
        finished = os.fstat(descriptor)
        if (finished.st_dev, finished.st_ino) != opened_identity:
            raise ValueError(f"{label} identity changed while reading")
        if finished.st_size != opened.st_size:
            raise ValueError(f"{label} changed while reading")
        return b"".join(chunks)
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _strict_json_source(
    path: Union[str, os.PathLike], label: str, max_bytes: int
) -> Tuple[Dict[str, Any], bytes]:
    raw = _read_bounded_regular_file(path, label, max_bytes)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{label} is not valid UTF-8: {exc}") from exc
    try:
        value = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_json_constant,
            parse_float=_parse_finite_float,
        )
    except RecursionError as exc:
        raise ValueError(f"{label} maximum nesting depth exceeded") from exc
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} contains invalid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value, raw


def strict_load_json(
    path: Union[str, os.PathLike], label: str, max_bytes: int
) -> Dict[str, Any]:
    """Load a bounded regular JSON object with strict parser settings."""

    value, _raw = _strict_json_source(path, label, max_bytes)
    return value


def strict_load_json_bytes(
    path: Union[str, os.PathLike], label: str, max_bytes: int
) -> Tuple[Dict[str, Any], bytes]:
    """Load strict JSON and return the exact source bytes for evidence hashing."""

    return _strict_json_source(path, label, max_bytes)


def file_sha256(
    path: Union[str, os.PathLike], max_bytes: Optional[int] = DEFAULT_FILE_MAX_BYTES
) -> str:
    """Hash a regular non-symlink file through a bounded descriptor stream."""

    if max_bytes is None:
        max_bytes = DEFAULT_FILE_MAX_BYTES
    raw = _read_bounded_regular_file(path, "file", max_bytes)
    return hashlib.sha256(raw).hexdigest()


def _snapshot_directory(
    path: Path, root: Path, max_file_bytes: int
) -> Tuple[str, int, List[Tuple[str, str, Optional[str], int]]]:
    entries: List[Tuple[str, str, Optional[str], int]] = []
    total_size = 0
    try:
        with os.scandir(path) as iterator:
            children = sorted(iterator, key=lambda entry: entry.name)
    except OSError as exc:
        raise ValueError(f"protected directory could not be read: {exc}") from exc
    for entry in children:
        child = Path(entry.path)
        try:
            info = os.lstat(child)
        except OSError as exc:
            raise ValueError(f"protected directory could not be inspected: {exc}") from exc
        relative = child.relative_to(root).as_posix()
        if stat.S_ISLNK(info.st_mode):
            raise ValueError(f"protected surface contains a symlink: {relative}")
        if stat.S_ISDIR(info.st_mode):
            child_hash, child_size, _child_entries = _snapshot_directory(
                child, root, max_file_bytes
            )
            entries.append((relative, "directory", child_hash, child_size))
            total_size += child_size
        elif stat.S_ISREG(info.st_mode):
            child_hash = file_sha256(child, max_bytes=max_file_bytes)
            entries.append((relative, "file", child_hash, info.st_size))
            total_size += info.st_size
        else:
            raise ValueError(f"protected surface contains a non-regular entry: {relative}")
    digest = hashlib.sha256(canonical_json_bytes(entries)).hexdigest()
    return digest, total_size, entries


def snapshot_protected_surfaces(
    root: Union[str, os.PathLike], max_file_bytes: int = DEFAULT_FILE_MAX_BYTES
) -> Tuple[ProtectedSurfaceRecord, ...]:
    """Return deterministic immutable type/path/hash/size records for surfaces."""

    physical = physical_project_root(root)
    records: List[ProtectedSurfaceRecord] = []
    for relative in PROTECTED_RUNTIME_RELATIVE_PATHS:
        surface = physical / relative
        _reject_symlink_components_below(physical, surface, "protected surface")
        try:
            info = os.lstat(surface)
        except FileNotFoundError:
            records.append(ProtectedSurfaceRecord("missing", relative.as_posix(), None, 0))
            continue
        except OSError as exc:
            raise ValueError(f"protected surface could not be inspected: {exc}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise ValueError(f"protected surface must not be a symlink: {relative}")
        if stat.S_ISREG(info.st_mode):
            digest = file_sha256(surface, max_bytes=max_file_bytes)
            records.append(ProtectedSurfaceRecord("file", relative.as_posix(), digest, info.st_size))
        elif stat.S_ISDIR(info.st_mode):
            digest, size, _entries = _snapshot_directory(surface, physical, max_file_bytes)
            records.append(ProtectedSurfaceRecord("directory", relative.as_posix(), digest, size))
        else:
            raise ValueError(f"protected surface must be a regular file or directory: {relative}")
    return tuple(records)


def _pinned_directory_flags() -> int:
    directory_flag = getattr(os, "O_DIRECTORY", None)
    nofollow_flag = getattr(os, "O_NOFOLLOW", None)
    supports_dir_fd = getattr(os, "supports_dir_fd", ())
    if directory_flag is None or nofollow_flag is None:
        raise OSError("Meshy publication requires O_DIRECTORY and O_NOFOLLOW")
    if not all(
        original in supports_dir_fd and callable(current)
        for original, current in (
            (_ORIGINAL_OPEN, os.open),
            (_ORIGINAL_MKDIR, os.mkdir),
            (_ORIGINAL_UNLINK, os.unlink),
        )
    ):
        raise OSError("Meshy publication requires directory-fd operations")
    try:
        replace_parameters = inspect.signature(_ORIGINAL_REPLACE).parameters
    except (TypeError, ValueError) as exc:
        raise OSError("Meshy publication requires directory-fd replace operations") from exc
    replace_supported = _ORIGINAL_REPLACE in supports_dir_fd or (
        os.rename in supports_dir_fd
        and all(name in replace_parameters for name in ("src_dir_fd", "dst_dir_fd"))
        and callable(os.replace)
    )
    if not replace_supported:
        raise OSError("Meshy publication requires directory-fd replace operations")
    flags = os.O_RDONLY | directory_flag | nofollow_flag
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    return flags


def _snapshot_identities(path: Path, label: str) -> Dict[Tuple[str, ...], Tuple[int, int]]:
    if not path.is_absolute() or path.anchor != os.sep:
        raise OSError(f"{label} requires an absolute POSIX path")
    identities: Dict[Tuple[str, ...], Tuple[int, int]] = {}
    for end in range(1, len(path.parts) + 1):
        parts = path.parts[:end]
        component = Path(parts[0])
        for part in parts[1:]:
            component /= part
        try:
            info = os.lstat(component)
        except FileNotFoundError:
            break
        except OSError as exc:
            raise OSError(f"{label} identity snapshot failed: {exc}") from exc
        if stat.S_ISLNK(info.st_mode):
            raise OSError(f"{label} contains a symlink component")
        identities[parts] = (info.st_dev, info.st_ino)
    return identities


def _check_fd_identity(
    descriptor: int,
    expected: Optional[Tuple[int, int]],
    label: str,
    required: bool = True,
) -> None:
    if expected is None:
        if required:
            raise OSError(f"{label} appeared during validation")
        return
    info = os.fstat(descriptor)
    actual = (info.st_dev, info.st_ino)
    if actual != expected:
        raise OSError(f"{label} identity changed after validation")


def _open_pinned_parent(path: Path, identities: Dict[Tuple[str, ...], Tuple[int, int]], flags: int) -> int:
    current_fd: Optional[int] = os.open(os.sep, flags)
    try:
        _check_fd_identity(current_fd, identities.get(path.parts[:1]), "Meshy root")
        created_prefix = False
        for index, component in enumerate(path.parent.parts[1:], start=2):
            child_fd: Optional[int] = None
            created_here = False
            component_parts = path.parts[:index]
            try:
                try:
                    child_fd = os.open(component, flags, dir_fd=current_fd)
                except FileNotFoundError:
                    if not created_prefix and identities.get(component_parts) is not None:
                        raise OSError(f"Meshy component {component} disappeared after validation")
                    try:
                        os.mkdir(component, mode=0o700, dir_fd=current_fd)
                    except FileExistsError as exc:
                        raise OSError(f"Meshy component {component} appeared during validation") from exc
                    created_here = True
                    child_fd = os.open(component, flags, dir_fd=current_fd)
                if identities.get(component_parts) is None and not (created_prefix or created_here):
                    raise OSError(f"Meshy component {component} appeared during validation")
                if identities.get(component_parts) is not None and not created_prefix:
                    _check_fd_identity(child_fd, identities.get(component_parts), f"Meshy component {component}")
                previous_fd = current_fd
                current_fd = child_fd
                child_fd = None
                os.close(previous_fd)
                created_prefix = created_prefix or created_here
            finally:
                if child_fd is not None:
                    os.close(child_fd)
        if current_fd is None:
            raise OSError("Meshy publication lost its parent directory fd")
        result = current_fd
        current_fd = None
        return result
    finally:
        if current_fd is not None:
            os.close(current_fd)


def _validate_existing_leaf(
    parent_fd: int, target: Path, identities: Dict[Tuple[str, ...], Tuple[int, int]]
) -> None:
    nofollow = getattr(os, "O_NOFOLLOW", None)
    if nofollow is None:
        raise OSError("Meshy publication requires O_NOFOLLOW")
    flags = os.O_RDONLY | nofollow
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    expected = identities.get(target.parts)
    descriptor: Optional[int] = None
    try:
        try:
            descriptor = os.open(target.name, flags, dir_fd=parent_fd)
        except FileNotFoundError:
            if expected is not None:
                raise OSError("Meshy output target disappeared after validation")
            return
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode):
            raise OSError("Meshy output target must be a regular file")
        if expected is None:
            raise OSError("Meshy output target appeared during validation")
        _check_fd_identity(descriptor, expected, "Meshy output target")
    finally:
        if descriptor is not None:
            os.close(descriptor)


def _create_sibling_temp(parent_fd: int, target_name: str) -> Tuple[int, str]:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    for _attempt in range(32):
        name = f".{target_name}.{secrets.token_hex(12)}.tmp"
        try:
            return os.open(name, flags, 0o600, dir_fd=parent_fd), name
        except FileExistsError:
            continue
    raise OSError("could not allocate a unique Meshy temporary file")


def _write_all(descriptor: int, payload: bytes) -> None:
    offset = 0
    while offset < len(payload):
        written = os.write(descriptor, payload[offset:])
        if written <= 0:
            raise OSError("Meshy temporary write made no progress")
        offset += written


def atomic_write_json(
    path: Union[str, os.PathLike],
    value: object,
    project_root: Union[str, os.PathLike],
    allowed_root: Union[str, os.PathLike],
) -> None:
    """Publish canonical JSON only through a pinned allowed directory FD."""

    payload = canonical_json_bytes(value)
    physical = physical_project_root(project_root)
    target = _path_from_explicit_root(project_root, physical, path)
    allowed = _path_from_explicit_root(project_root, physical, allowed_root)

    # Deny protected targets before the allowed-root diagnostic, including
    # aliases and missing descendants resolved through a protected surface.
    reject_protected_output(physical, target, "Meshy output")
    _reject_symlink_components_below(physical, target, "Meshy output")
    _reject_symlink_components_below(physical, allowed, "Meshy allowed root")
    resolved_allowed = _resolved_below(physical, allowed, "Meshy allowed root")
    resolved_target = _resolved_below(physical, target, "Meshy output")
    if not _contained(allowed, target) or not _contained(resolved_allowed, resolved_target):
        raise ValueError("Meshy output must be within the allowed staging root")
    if target.name in {"", ".", ".."}:
        raise ValueError("Meshy output must have a file name")

    identities = _snapshot_identities(target, "Meshy output")
    hook = _ATOMIC_VALIDATION_HOOK
    if hook is not None:
        hook(target)

    directory_fd: Optional[int] = None
    temporary_fd: Optional[int] = None
    temporary_name: Optional[str] = None
    primary_error: Optional[BaseException] = None
    primary_traceback = None
    try:
        flags = _pinned_directory_flags()
        directory_fd = _open_pinned_parent(target, identities, flags)
        os.fsync(directory_fd)
        _validate_existing_leaf(directory_fd, target, identities)
        temporary_fd, temporary_name = _create_sibling_temp(directory_fd, target.name)
        try:
            _write_all(temporary_fd, payload)
            os.fsync(temporary_fd)
        finally:
            os.close(temporary_fd)
            temporary_fd = None
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

    cleanup_error: Optional[BaseException] = None
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


__all__ = [
    "STAGING_RELATIVE",
    "PROTECTED_RUNTIME_RELATIVE_PATHS",
    "ProtectedSurfaceRecord",
    "atomic_write_json",
    "canonical_json_bytes",
    "file_sha256",
    "governed_task_path",
    "physical_project_root",
    "protected_runtime_paths",
    "reject_protected_output",
    "snapshot_protected_surfaces",
    "strict_load_json",
    "strict_load_json_bytes",
]
