#!/usr/bin/env python3
"""Build and validate focused-nine visual-only prop sidecars.

These sidecars are deliberately staged-only.  They are not part of the live
prop inventory or the generated runtime visual-binding index.
"""

from __future__ import annotations

import argparse
import inspect
import json
import os
import secrets
import sys
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.focused_nine_contract import (
    PROP_IDS,
    asset_stage_dir,
    asset_stage_glb,
    runtime_mutation_paths,
)
from tools.prop_visual_metadata import read_glb_metadata, validate_sidecar


STAGED_ASSET_IDS = frozenset(PROP_IDS)
STAGED_EXTENSIONS = {
    "comparison_role": "objective_prop",
    "staged_visual_only": True,
}


def _sorted_errors(errors: list[str]) -> list[str]:
    return sorted(set(errors))


def _absolute_path(path: Path) -> Path:
    """Make a path absolute without resolving symlinks."""
    return Path(os.path.abspath(os.fspath(path)))


def _display_path(path: Path, project_root: Path) -> str:
    try:
        return path.relative_to(project_root).as_posix()
    except ValueError:
        return path.as_posix()


def _contained(path: Path, root: Path) -> bool:
    return path == root or root in path.parents


def _location_diagnostics(
    project_root: Path, glb_path: Path, asset_id: str | None
) -> tuple[list[str], Path, bool, bool]:
    """Return strict staged-location diagnostics and the resolved GLB path.

    Lexical paths enforce the exact staged layout.  Resolved paths separately
    enforce that symlinks cannot escape the project or staging roots.
    """
    root_lexical = _absolute_path(Path(project_root))
    lexical = _absolute_path(Path(glb_path))
    errors: list[str] = []

    try:
        root = root_lexical.resolve(strict=False)
        stage_resolved = asset_stage_dir(root_lexical, PROP_IDS[0])
        stage_relative = stage_resolved.relative_to(root)
        stage_lexical = root_lexical / stage_relative
        stage_resolved = stage_lexical.resolve(strict=False)
        resolved = lexical.resolve(strict=False)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        return [f"focused-nine staging path could not be resolved: {exc}"], lexical, False, False

    expected_name = f"{asset_id}.glb" if asset_id else None
    if not isinstance(asset_id, str) or asset_id not in STAGED_ASSET_IDS:
        errors.append(
            f"asset_id must be one of: {', '.join(PROP_IDS)}"
        )
    if lexical.suffix != ".glb" or resolved.suffix != ".glb":
        errors.append("GLB path must have a .glb extension in focused-nine staging")
    if expected_name is not None and lexical.name != expected_name:
        errors.append(f"GLB filename must match asset_id: {expected_name}")
    if expected_name is not None and resolved.name != expected_name:
        errors.append(f"GLB filename must match asset_id: {expected_name}")

    if not _contained(stage_resolved, root):
        errors.append("focused-nine staging path escapes project root via symlink")
    if not _contained(lexical, root_lexical):
        errors.append("GLB path escapes project root lexically")
    if lexical.parent != stage_lexical:
        errors.append(
            "GLB path must be exactly under focused-nine staging: "
            f"{stage_relative.as_posix()}/<asset_id>.glb"
        )
    if not _contained(resolved, stage_resolved) or resolved.parent != stage_resolved:
        errors.append(
            "GLB path escapes focused-nine staging via symlink: "
            f"{_display_path(resolved, root)}"
        )
    elif resolved.relative_to(root) != lexical.relative_to(root_lexical):
        errors.append(
            "GLB path must not use a symlink in focused-nine staging: "
            f"{_display_path(lexical, root)}"
        )

    if not resolved.exists():
        errors.append(f"GLB does not exist in focused-nine staging: {_display_path(lexical, root)}")
    elif not resolved.is_file():
        errors.append(f"GLB is not a regular file in focused-nine staging: {_display_path(lexical, root)}")

    path_valid = not errors
    return _sorted_errors(errors), resolved, path_valid, True


def _expected_visual_scene_path(project_root: Path, asset_id: str) -> str:
    root = _absolute_path(Path(project_root)).resolve(strict=False)
    staged_glb = asset_stage_glb(project_root, asset_id)
    return f"res://{staged_glb.relative_to(root).as_posix()}"


def _metadata_mismatch_errors(sidecar: dict[str, Any], metadata: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    source = sidecar.get("source")
    if isinstance(source, dict):
        for field in ("sha256", "byte_size", "mesh_count", "gltf_version"):
            if source.get(field) != metadata[field]:
                errors.append(f"{field} mismatch")

    bounds = sidecar.get("bounds")
    if isinstance(bounds, dict):
        if (
            bounds.get("local_min_m") != metadata["local_min_m"]
            or bounds.get("local_max_m") != metadata["local_max_m"]
        ):
            errors.append("bounds mismatch")
    return errors


def build_staged_sidecar(project_root: Path, glb_path: Path, asset_id: str) -> dict:
    """Build a validated sidecar for one of the two focused-nine staged props."""
    location_errors, resolved_glb, path_valid, _path_resolved = _location_diagnostics(
        project_root, Path(glb_path), asset_id
    )
    if location_errors:
        raise ValueError("; ".join(location_errors))
    if not path_valid:
        raise ValueError("invalid focused-nine staging GLB path")

    metadata = read_glb_metadata(resolved_glb)
    sidecar: dict[str, Any] = {
        "schema_version": "1.0.0",
        "document_kind": "prop_visual_binding",
        "asset_id": asset_id,
        "prop_kind": "dressing",
        "visual_scene_path": _expected_visual_scene_path(project_root, asset_id),
        "binding": {"namespace": "visual_prop_id", "ids": [asset_id]},
        "placement": {
            "origin": "scene_origin",
            "offset_m": [0.0, 0.0, 0.0],
            "rotation_degrees": [0.0, 0.0, 0.0],
            "allowed_yaw_deg": [0.0, 90.0, 180.0, 270.0],
            "scale": 1.0,
        },
        "source": {
            "sha256": metadata["sha256"],
            "byte_size": metadata["byte_size"],
            "mesh_count": metadata["mesh_count"],
            "gltf_version": metadata["gltf_version"],
        },
        "bounds": {
            "local_min_m": metadata["local_min_m"],
            "local_max_m": metadata["local_max_m"],
        },
        "collision_policy": "none_visual_only",
        "provenance": {
            "license_state": "self-authored",
            "source_platform": "self-authored",
        },
        "extensions": dict(STAGED_EXTENSIONS),
    }
    errors = validate_staged_sidecar(project_root, Path(glb_path), sidecar)
    if errors:
        raise ValueError("; ".join(errors))
    return sidecar


def validate_staged_sidecar(project_root: Path, glb_path: Path, sidecar: dict) -> list[str]:
    """Return sorted deterministic diagnostics for one staged-only sidecar."""
    sidecar_asset_id = sidecar.get("asset_id") if isinstance(sidecar, dict) else None
    location_errors, resolved_glb, path_valid, path_resolved = _location_diagnostics(
        project_root, Path(glb_path), sidecar_asset_id if isinstance(sidecar_asset_id, str) else None
    )
    errors = list(location_errors)
    if path_resolved:
        try:
            errors.extend(validate_sidecar(sidecar, resolved_glb, project_root))
        except (OSError, RuntimeError, TypeError, ValueError) as exc:
            errors.append(f"sidecar validation error: {exc}")

    if not path_resolved:
        return _sorted_errors(errors)
    if not isinstance(sidecar, dict):
        return _sorted_errors(errors)

    asset_id = sidecar.get("asset_id")
    if not isinstance(asset_id, str) or asset_id not in STAGED_ASSET_IDS:
        errors.append(
            f"asset_id must be one of: {', '.join(PROP_IDS)}"
        )
    else:
        expected_path = _expected_visual_scene_path(project_root, asset_id)
        if sidecar.get("visual_scene_path") != expected_path:
            errors.append(f"visual_scene_path must be exactly {expected_path}")
        expected_binding = {"namespace": "visual_prop_id", "ids": [asset_id]}
        if sidecar.get("binding") != expected_binding:
            errors.append(f"binding must be exactly {expected_binding!r}")

    if sidecar.get("prop_kind") != "dressing":
        errors.append("prop_kind must be dressing for focused-nine staged props")
    if sidecar.get("collision_policy") != "none_visual_only":
        errors.append("collision_policy must be none_visual_only for focused-nine staged props")
    if sidecar.get("extensions") != STAGED_EXTENSIONS:
        errors.append(
            "extensions must be exactly "
            "{'comparison_role': 'objective_prop', 'staged_visual_only': True}"
        )

    if path_valid:
        try:
            metadata = read_glb_metadata(resolved_glb)
        except (OSError, RuntimeError, TypeError, ValueError) as exc:
            errors.append(f"GLB metadata error: {exc}")
        else:
            errors.extend(_metadata_mismatch_errors(sidecar, metadata))

    return _sorted_errors(errors)


def _canonical_json_bytes(document: dict) -> bytes:
    payload = json.dumps(
        document,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )
    return (payload + "\n").encode("utf-8")


def _pinned_directory_open_flags() -> int:
    directory_flag = getattr(os, "O_DIRECTORY", None)
    nofollow_flag = getattr(os, "O_NOFOLLOW", None)
    supports_dir_fd = getattr(os, "supports_dir_fd", ())
    if directory_flag is None or nofollow_flag is None:
        raise OSError("sidecar output requires O_DIRECTORY and O_NOFOLLOW")
    required_functions = (os.open, os.mkdir, os.unlink)
    if not all(function in supports_dir_fd for function in required_functions):
        raise OSError("sidecar output requires directory-fd operations")
    # CPython on macOS exposes os.replace's src_dir_fd/dst_dir_fd parameters,
    # and the call works, but omits the alias from os.supports_dir_fd.  Require
    # the dir-fd-capable os.rename entry as the platform capability marker and
    # verify that replace still exposes both keyword parameters.
    replace_support = os.replace in supports_dir_fd
    if not replace_support and os.rename in supports_dir_fd:
        replace_parameters = inspect.signature(os.replace).parameters
        replace_support = all(
            parameter in replace_parameters
            for parameter in ("src_dir_fd", "dst_dir_fd")
        )
    if not replace_support:
        raise OSError("sidecar output requires directory-fd replace operations")
    return os.O_RDONLY | directory_flag | nofollow_flag


def _create_sibling_temp(directory_fd: int, target_name: str) -> tuple[int, str]:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    nofollow_flag = getattr(os, "O_NOFOLLOW", None)
    if nofollow_flag is not None:
        flags |= nofollow_flag
    for _attempt in range(32):
        temporary_name = f".{target_name}.{secrets.token_hex(12)}.tmp"
        try:
            descriptor = os.open(
                temporary_name,
                flags,
                0o600,
                dir_fd=directory_fd,
            )
        except FileExistsError:
            continue
        return descriptor, temporary_name
    raise OSError("could not allocate a unique sidecar temporary file")


def _open_pinned_parent_directory(path: Path, directory_flags: int) -> int:
    """Open *path*'s parent by walking pinned, no-followed components."""
    path = Path(path)
    if not path.is_absolute() or path.anchor != os.sep:
        raise OSError("sidecar output requires an absolute POSIX path")

    current_fd: int | None = os.open(os.sep, directory_flags)
    try:
        for component in path.parent.parts[1:]:
            child_fd: int | None = None
            try:
                try:
                    child_fd = os.open(
                        component,
                        directory_flags,
                        dir_fd=current_fd,
                    )
                except FileNotFoundError:
                    os.mkdir(component, mode=0o700, dir_fd=current_fd)
                    child_fd = os.open(
                        component,
                        directory_flags,
                        dir_fd=current_fd,
                    )

                previous_fd = current_fd
                current_fd = child_fd
                child_fd = None
                os.close(previous_fd)
            finally:
                if child_fd is not None:
                    os.close(child_fd)

        if current_fd is None:
            raise OSError("sidecar output parent walk lost its directory fd")
        result = current_fd
        current_fd = None
        return result
    finally:
        if current_fd is not None:
            os.close(current_fd)


def _write_sidecar_atomically(path: Path, sidecar: dict) -> None:
    """Publish canonical JSON through a pinned parent directory FD."""
    path = Path(path)
    payload = _canonical_json_bytes(sidecar)
    directory_flags = _pinned_directory_open_flags()

    directory_fd: int | None = None
    temporary_fd: int | None = None
    temporary_name: str | None = None
    primary_error: BaseException | None = None
    primary_traceback = None
    try:
        directory_fd = _open_pinned_parent_directory(path, directory_flags)
        # Probe directory fsync before creating a temporary file so platforms
        # without durable directory publication fail closed without writing.
        os.fsync(directory_fd)
        temporary_fd, temporary_name = _create_sibling_temp(directory_fd, path.name)
        handle = os.fdopen(temporary_fd, "wb")
        try:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        finally:
            try:
                handle.close()
            except BaseException:
                raise
            else:
                temporary_fd = None
        os.replace(
            temporary_name,
            path.name,
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


def _protected_output_error(
    project_root: Path, output_path: Path
) -> tuple[Path, str | None]:
    """Return one canonical output target and any live-surface rejection."""
    try:
        # Resolve the original path directly.  In particular, do not normalize
        # alias/../name before resolving symlinks: POSIX resolves the alias first.
        output_resolved = Path(output_path).resolve(strict=False)
        protected_paths = runtime_mutation_paths(project_root)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        raise ValueError(f"sidecar output protection check failed: {exc}") from exc

    for protected_path in protected_paths:
        try:
            protected_resolved = Path(protected_path).resolve(strict=False)
        except (OSError, RuntimeError, TypeError, ValueError) as exc:
            raise ValueError(f"sidecar output protection check failed: {exc}") from exc
        if _contained(output_resolved, protected_resolved):
            return output_resolved, (
                "sidecar output must not target live runtime surface: "
                f"{protected_path}"
            )
    return output_resolved, None


def _argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument("--sidecar-out", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _argument_parser().parse_args(argv)
    try:
        sidecar = build_staged_sidecar(args.project_root, args.glb, args.asset_id)
        errors = validate_staged_sidecar(args.project_root, args.glb, sidecar)
        if errors:
            raise ValueError("; ".join(errors))
        output_path, output_error = _protected_output_error(
            args.project_root, args.sidecar_out
        )
        if output_error:
            raise ValueError(output_error)
        _write_sidecar_atomically(output_path, sidecar)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
