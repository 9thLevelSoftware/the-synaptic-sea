"""In-process GLB export helpers for the Structural Module Toolkit.

This module intentionally has no top-level Blender import.  It can therefore be
unit-tested with a small fake ``bpy`` object while the actual export operator is
only invoked inside Blender.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys
from typing import Any


_ALLOWED_VARIANTS = frozenset(("intact", "damaged", "breached"))
_MODULE_ID_PATTERN = re.compile(r"[A-Za-z0-9_-]+")
_DIMENSIONS_RELATIVE = Path("data/art/structural_visual_dimensions.v1.json")


def validate_module_id(module_id: str) -> str:
    """Reject IDs that could escape the configured staging root."""

    if not isinstance(module_id, str) or not _MODULE_ID_PATTERN.fullmatch(module_id):
        raise ValueError(
            f"invalid module id {module_id!r}; expected only alphanumeric, "
            "underscore, or hyphen characters"
        )
    return module_id


def detect_module_id(bpy: Any) -> str:
    """Read the module ID from scene metadata or a ModuleRoot object."""

    scene = bpy.context.scene
    for key in ("module_id", "structural_module_id"):
        value = scene.get(key)
        if value is not None and str(value).strip():
            return str(value).strip()
    for attribute in ("structural_module_id",):
        value = getattr(scene, attribute, "")
        if str(value).strip():
            return str(value).strip()

    root_names = sorted(
        obj.name
        for obj in bpy.data.objects
        if obj.name.startswith("ModuleRoot_") and obj.name[len("ModuleRoot_") :]
    )
    if root_names:
        return root_names[0][len("ModuleRoot_") :]
    raise ValueError("could not detect module ID; set the module ID or create a ModuleRoot")


def tagged_export_collections(bpy: Any) -> list[Any]:
    """Return collections explicitly marked for variant export."""

    return sorted(
        (
            collection
            for collection in bpy.data.collections
            if collection.name.startswith("Export_")
        ),
        key=lambda collection: collection.name,
    )


def collections_to_export(bpy: Any) -> list[Any]:
    """Find tagged export collections, falling back to the Geometry collection."""

    tagged = tagged_export_collections(bpy)
    if tagged:
        return tagged
    geometry = bpy.data.collections.get("Geometry")
    if geometry is not None:
        return [geometry]
    raise FileNotFoundError(
        "no tagged Export_* collections and no Geometry collection found"
    )


def variant_role(collection: Any) -> str:
    """Read and validate an export collection's variant role."""

    role = str(collection.get("variant_role", "intact")).strip().lower()
    if role not in _ALLOWED_VARIANTS:
        raise ValueError(
            f"unsupported variant_role {role!r} on collection {collection.name!r}; "
            f"expected one of {', '.join(sorted(_ALLOWED_VARIANTS))}"
        )
    return role


def output_path(staging_root: Path, module_id: str, variant: str) -> Path:
    """Return ``staging_root/<module_id>/<module>[_{variant}].glb``."""

    validate_module_id(module_id)
    if variant not in _ALLOWED_VARIANTS:
        raise ValueError(f"unsupported export variant: {variant!r}")
    suffix = "" if variant == "intact" else f"_{variant}"
    return staging_root / module_id / f"{module_id}{suffix}.glb"


def _temporary_output_path(glb_path: Path) -> Path:
    return glb_path.with_name(f".{glb_path.stem}.tmp{glb_path.suffix}")


def _default_project_root() -> Path:
    """Return the repository root when the add-on is used from a checkout."""

    # export.py -> structural_module_toolkit -> blender_addons -> tools -> repo
    return Path(__file__).resolve().parents[3]


def _validate_with_fresh_blender(
    path: Path,
    module_id: str,
    project_root: Path,
    dimensions: Path,
    *,
    blender_executable: str | Path | None = None,
    timeout: float = 180.0,
) -> dict[str, Any]:
    """Validate one temporary GLB in a disposable Blender process.

    Never call the in-process ``validate_glb`` here: that validator resets the
    current Blender scene, which would destroy an artist's unsaved work.
    """

    try:
        from tools.validate_structural_visual_fit import validate_glb_in_subprocess
    except ModuleNotFoundError:
        # An installed add-on may not have the repository on sys.path.  The
        # operator supplies the configured source/project root when available;
        # this fallback makes the checkout layout work without adding another
        # preference or configuration system.
        root_string = str(project_root)
        if root_string not in sys.path:
            sys.path.insert(0, root_string)
        from tools.validate_structural_visual_fit import validate_glb_in_subprocess

    result = validate_glb_in_subprocess(
        path,
        module_id,
        project_root,
        dimensions=dimensions,
        blender_executable=blender_executable,
        timeout=timeout,
    )
    if not isinstance(result, dict):
        raise RuntimeError("fresh Blender visual validation returned a non-object result")
    if result.get("status") != "pass":
        errors = result.get("errors") or ["visual contract did not pass"]
        raise ValueError(
            f"fresh Blender GLB validation failed for {module_id}: "
            + "; ".join(str(error) for error in errors)
        )
    return result


def select_collection_objects(bpy: Any, collection: Any) -> list[Any]:
    """Select exactly the objects directly contained by one collection."""

    bpy.ops.object.select_all(action="DESELECT")
    selected = list(collection.objects)
    for obj in selected:
        obj.select_set(True)
    if selected:
        bpy.context.view_layer.objects.active = selected[0]
    return selected


def export_scene_to_staging(
    bpy: Any,
    staging_root: Path | str,
    module_id: str | None = None,
    *,
    project_root: Path | str | None = None,
    dimensions: Path | str | None = None,
    blender_executable: str | Path | None = None,
    validation_timeout: float = 180.0,
) -> list[Path]:
    """Export, fresh-process validate, then publish every tagged variant.

    Temporary GLBs are validated before any final staging path is replaced.  A
    failed export or validation therefore leaves the previous staged set byte
    identical while the caller's Blender scene remains untouched.
    """

    module_id = validate_module_id(module_id or detect_module_id(bpy))
    staging_root = Path(staging_root).expanduser().resolve()
    project_root = (
        _default_project_root()
        if project_root is None
        else Path(project_root).expanduser().resolve()
    )
    dimensions = (
        project_root / _DIMENSIONS_RELATIVE
        if dimensions is None
        else Path(dimensions).expanduser().resolve()
    )
    collections = collections_to_export(bpy)

    variants: list[tuple[Any, str]] = []
    seen_variants: set[str] = set()
    for collection in collections:
        role = variant_role(collection) if collection.name.startswith("Export_") else "intact"
        if role in seen_variants:
            raise ValueError(
                f"duplicate variant_role {role!r} on collection {collection.name!r}"
            )
        seen_variants.add(role)
        variants.append((collection, role))

    pending: list[tuple[str, Path, Path, int]] = []
    temporary_paths: list[Path] = []
    try:
        # Export every variant first.  No final output is touched until all
        # temporary GLBs have passed the isolated visual-fit gate.
        for collection, role in variants:
            glb_path = output_path(staging_root, module_id, role)
            temporary_path = _temporary_output_path(glb_path)
            glb_path.parent.mkdir(parents=True, exist_ok=True)
            temporary_paths.append(temporary_path)
            temporary_path.unlink(missing_ok=True)
            selected = select_collection_objects(bpy, collection)
            if not selected:
                raise ValueError(f"export collection {collection.name!r} contains no objects")
            result = bpy.ops.export_scene.gltf(
                filepath=str(temporary_path),
                export_format="GLB",
                export_apply=True,
                use_selection=True,
            )
            if result is not None and "CANCELLED" in result:
                raise RuntimeError(
                    f"Blender cancelled GLB export for module={module_id} variant={role}"
                )
            if not temporary_path.is_file():
                raise FileNotFoundError(
                    f"Blender did not create temporary GLB output: {temporary_path}"
                )
            byte_count = temporary_path.stat().st_size
            if byte_count <= 0:
                raise ValueError(f"Blender created an empty GLB output: {temporary_path}")
            pending.append((role, glb_path, temporary_path, byte_count))

        if not pending:
            raise ValueError(f"no structural variants were exported for {module_id}")

        validation_errors: list[str] = []
        for _role, _glb_path, temporary_path, _byte_count in pending:
            try:
                validation = _validate_with_fresh_blender(
                    temporary_path,
                    module_id,
                    project_root,
                    dimensions,
                    blender_executable=blender_executable,
                    timeout=validation_timeout,
                )
                if not isinstance(validation, dict) or validation.get("status") != "pass":
                    errors = (
                        validation.get("errors", [])
                        if isinstance(validation, dict)
                        else []
                    )
                    raise ValueError(
                        "fresh Blender visual validation returned "
                        f"non-pass status: {', '.join(str(error) for error in errors) or 'unknown error'}"
                    )
            except (OSError, RuntimeError, TypeError, ValueError) as exc:
                # Continue so every exported variant gets a gate result before
                # the transaction is rejected.
                validation_errors.append(str(exc))
        if validation_errors:
            raise ValueError(
                f"one or more structural variants failed validation for {module_id}: "
                + "; ".join(validation_errors)
            )

        # Share the CLI's rollback-safe publication path. Fresh-process
        # validation above has already resolved the configured project root.
        try:
            from ...structural_stage_publication import publish_staged_files
        except ImportError:
            root_string = str(project_root)
            if root_string not in sys.path:
                sys.path.insert(0, root_string)
            from tools.structural_stage_publication import publish_staged_files
        publish_staged_files([
            (temporary_path, glb_path)
            for _role, glb_path, temporary_path, _byte_count in pending
        ])
    finally:
        for temporary_path in temporary_paths:
            temporary_path.unlink(missing_ok=True)

    exported: list[Path] = []
    for role, glb_path, _temporary_path, byte_count in pending:
        print(
            "STRUCTURAL_GLB_EXPORTED "
            f"module={module_id} variant={role} glb={glb_path} bytes={byte_count}"
        )
        exported.append(glb_path)
    return exported


__all__ = [
    "collections_to_export",
    "detect_module_id",
    "export_scene_to_staging",
    "output_path",
    "select_collection_objects",
    "tagged_export_collections",
    "validate_module_id",
    "variant_role",
]
