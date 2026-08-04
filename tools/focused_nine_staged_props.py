#!/usr/bin/env python3
"""Build and validate focused-nine visual-only prop sidecars.

These sidecars are deliberately staged-only.  They are not part of the live
prop inventory or the generated runtime visual-binding index.
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
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
from tools.prop_visual_metadata import read_glb_metadata, validate_sidecar, write_canonical_json


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


def _write_sidecar_atomically(path: Path, sidecar: dict) -> None:
    """Write canonical JSON through a sibling temporary file and replace."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
        )
        os.close(descriptor)
        temporary_path = Path(temporary_name)
        write_canonical_json(temporary_path, sidecar)
        os.replace(temporary_path, path)
        temporary_path = None
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass


def _protected_output_error(project_root: Path, output_path: Path) -> str | None:
    """Reject output paths that name or resolve into live runtime surfaces."""
    output_lexical = _absolute_path(Path(output_path))
    try:
        output_resolved = output_lexical.resolve(strict=False)
        protected_paths = runtime_mutation_paths(project_root)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        raise ValueError(f"sidecar output protection check failed: {exc}") from exc

    for protected_path in protected_paths:
        protected_lexical = _absolute_path(protected_path)
        try:
            protected_resolved = protected_lexical.resolve(strict=False)
        except (OSError, RuntimeError, TypeError, ValueError) as exc:
            raise ValueError(f"sidecar output protection check failed: {exc}") from exc
        if _contained(output_lexical, protected_lexical) or _contained(
            output_resolved, protected_resolved
        ):
            return f"sidecar output must not target live runtime surface: {protected_path}"
    return None


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
        output_error = _protected_output_error(args.project_root, args.sidecar_out)
        if output_error:
            raise ValueError(output_error)
        _write_sidecar_atomically(args.sidecar_out, sidecar)
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
