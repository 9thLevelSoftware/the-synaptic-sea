#!/usr/bin/env python3
"""Export structural Blender source collections as staged GLB files.

The script is intentionally Blender-compatible but keeps its argument parsing
free of a top-level ``bpy`` import so the CLI contract can be tested with a
normal Python interpreter.

Run it through Blender, for example::

    blender --background --factory-startup \
        --python tools/export_structural_glb.py -- \
        --blend-path /absolute/path/module.blend \
        --staging-dir /absolute/path/staging \
        --module floor_1x1
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys
from typing import Any, Sequence


_ALLOWED_VARIANTS = frozenset(("intact", "damaged", "breached"))
_MODULE_ID_PATTERN = re.compile(r"[A-Za-z0-9_-]+")
_DIMENSIONS_RELATIVE = Path("data/art/structural_visual_dimensions.v1.json")
_REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

try:
    from tools.structural_stage_publication import publish_staged_files
except ModuleNotFoundError:  # pragma: no cover - Blender script-directory fallback
    sys.path.insert(0, str(_REPOSITORY_ROOT))
    from tools.structural_stage_publication import publish_staged_files


def build_parser() -> argparse.ArgumentParser:
    """Build the parser without importing Blender's Python API."""

    parser = argparse.ArgumentParser(
        description="Export tagged structural Blender collections as GLB files."
    )
    parser.add_argument(
        "--blend-path",
        required=True,
        type=Path,
        help="source .blend file to open",
    )
    parser.add_argument(
        "--staging-dir",
        required=True,
        type=Path,
        help="directory receiving exported GLB files",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path.cwd(),
        help="repository root containing the canonical visual policy",
    )
    parser.add_argument(
        "--dimensions",
        type=Path,
        default=None,
        help="explicit canonical dimensions policy path",
    )
    parser.add_argument(
        "--module",
        default=None,
        help="module identifier; detected from the source when omitted",
    )
    return parser


def _argv_from_blender(argv: Sequence[str] | None = None) -> list[str]:
    """Return script arguments, removing Blender's ``--`` separator."""

    if argv is not None:
        raw = list(argv)
    else:
        raw = list(sys.argv[1:])
    if "--" in raw:
        return raw[raw.index("--") + 1 :]
    return raw


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse and validate CLI arguments without importing ``bpy``."""

    parser = build_parser()
    args = parser.parse_args(_argv_from_blender(argv))
    if not args.blend_path.is_file():
        parser.error(f"blend file does not exist: {args.blend_path}")
    return args


def _require_bpy() -> Any:
    """Import Blender lazily, after parser validation has completed."""

    return __import__("bpy")


def _detect_module_id(bpy: Any) -> str:
    """Detect a module ID from scene metadata, then the ModuleRoot object."""

    scene = bpy.context.scene
    module_id = scene.get("module_id")
    if module_id is not None and str(module_id):
        return str(module_id)

    root_names = sorted(
        obj.name
        for obj in bpy.data.objects
        if obj.name.startswith("ModuleRoot_") and obj.name[len("ModuleRoot_") :]
    )
    if root_names:
        return root_names[0][len("ModuleRoot_") :]
    return "unknown"


def _tagged_export_collections(bpy: Any) -> list[Any]:
    """Return collections explicitly tagged for structural export."""

    return sorted(
        (
            collection
            for collection in bpy.data.collections
            if collection.name.startswith("Export_")
            and collection.get("variant_role") is not None
        ),
        key=lambda collection: collection.name,
    )


def _collections_to_export(bpy: Any) -> list[Any]:
    """Find tagged variants, or use Geometry as the intact fallback."""

    tagged = _tagged_export_collections(bpy)
    if tagged:
        return tagged

    geometry = bpy.data.collections.get("Geometry")
    if geometry is not None:
        return [geometry]

    raise FileNotFoundError(
        "no tagged Export_* collections and no Geometry collection found"
    )


def _variant_role(collection: Any) -> str:
    """Return and validate the role stored on an export collection."""

    role = str(collection.get("variant_role", "intact")).strip().lower()
    if role not in _ALLOWED_VARIANTS:
        raise ValueError(
            f"unsupported variant_role {role!r} on collection {collection.name!r}; "
            f"expected one of {', '.join(sorted(_ALLOWED_VARIANTS))}"
        )
    return role


def _select_collection_objects(bpy: Any, collection: Any) -> None:
    """Select exportable mesh objects while preserving source helpers."""

    bpy.ops.object.select_all(action="DESELECT")
    selected = [obj for obj in collection.objects if _is_exportable_object(obj)]
    for obj in selected:
        obj.select_set(True)
    if selected:
        bpy.context.view_layer.objects.active = selected[0]
        transform_apply = getattr(bpy.ops.object, "transform_apply", None)
        if callable(transform_apply):
            applied = transform_apply(location=True, rotation=True, scale=True)
            finished = (
                isinstance(applied, (set, frozenset, list, tuple))
                and "FINISHED" in applied
            )
            if not finished:
                raise RuntimeError(
                    f"Blender transform apply did not finish for collection {collection.name!r}: {applied!r}"
                )


def _output_path(staging_dir: Path, module_id: str, variant: str) -> Path:
    """Return the canonical staging filename for a module variant."""

    suffix = "" if variant == "intact" else f"_{variant}"
    return staging_dir / f"{module_id}{suffix}.glb"


def _validate_module_id(module_id: str) -> str:
    """Ensure the module ID can only name a file within the staging directory."""

    if not _MODULE_ID_PATTERN.fullmatch(module_id):
        raise ValueError(
            f"invalid module id {module_id!r}; expected only alphanumeric, "
            "underscore, or hyphen characters"
        )
    return module_id


def _temporary_output_path(glb_path: Path) -> Path:
    """Return a temporary sibling path for an atomic GLB export."""

    return glb_path.with_name(f".{glb_path.stem}.tmp{glb_path.suffix}")


def _object_property(obj: Any, name: str, default: Any = None) -> Any:
    try:
        getter = getattr(obj, "get", None)
        if callable(getter):
            value = getter(name, default)
            return default if value is None else value
    except (AttributeError, TypeError, ValueError):
        pass
    return getattr(obj, name, default)


def _is_authoring_helper(obj: Any) -> bool:
    name = str(getattr(obj, "name", "")).strip().lower()
    if name.startswith(("authoring", "helper", "anchor", "sock_", "socket", "collision", "collisionproxy", "col_")):
        return True
    role = str(_object_property(obj, "structural_role", "")).strip().lower()
    return role in {"helper", "authoring_helper", "socket", "rig", "camera", "light"} or bool(
        _object_property(obj, "authoring_helper", False)
    )


def _is_exportable_object(obj: Any) -> bool:
    """Keep authoring helpers in the source while excluding them from GLB."""

    return str(getattr(obj, "type", "MESH")).upper() == "MESH" and not _is_authoring_helper(obj)


def _default_dimensions_path(project_root: Path | None = None) -> Path:
    root = Path.cwd() if project_root is None else Path(project_root).expanduser().resolve()
    return root / _DIMENSIONS_RELATIVE


def _validate_exported_glb(
    path: Path,
    module_id: str,
    project_root: Path,
    dimensions: Path | None,
    bpy: Any,
) -> dict[str, Any]:
    """Fresh-import and validate an export before it can replace staging."""

    try:
        sys.path.remove(str(_REPOSITORY_ROOT))
    except ValueError:
        pass
    sys.path.insert(0, str(_REPOSITORY_ROOT))
    try:
        from tools.validate_structural_visual_fit import validate_glb
    except ModuleNotFoundError:  # pragma: no cover - Blender script-directory fallback
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from tools.validate_structural_visual_fit import validate_glb

    policy = dimensions if dimensions is not None else _default_dimensions_path(project_root)
    result = validate_glb(path, module_id, policy, bpy)
    if result.get("status") != "pass":
        errors = result.get("errors") or ["visual contract did not pass"]
        raise ValueError(
            f"fresh Blender GLB validation failed for {module_id}: "
            + "; ".join(str(error) for error in errors)
        )
    return result


def export_blend(args: argparse.Namespace, bpy: Any) -> list[Path]:
    """Export every variant, validate every GLB, then publish atomically."""

    opened = bpy.ops.wm.open_mainfile(filepath=str(args.blend_path))
    if opened is None or "FINISHED" not in opened or "CANCELLED" in opened:
        raise RuntimeError(f"Blender source open did not finish: {opened!r}")
    module_id = _validate_module_id(str(args.module or _detect_module_id(bpy)))
    collections = _collections_to_export(bpy)

    variants: list[tuple[Any, str]] = []
    seen_variants: set[str] = set()
    for collection in collections:
        variant = (
            _variant_role(collection)
            if collection.name.startswith("Export_")
            else "intact"
        )
        if variant in seen_variants:
            raise ValueError(
                f"duplicate variant_role {variant!r} on collection {collection.name!r}"
            )
        seen_variants.add(variant)
        variants.append((collection, variant))

    staging_dir = Path(args.staging_dir)
    staging_dir.mkdir(parents=True, exist_ok=True)
    project_root = Path(getattr(args, "project_root", Path.cwd())).expanduser().resolve()
    dimensions = getattr(args, "dimensions", None)
    pending: list[tuple[str, Path, Path, int]] = []
    temporary_paths: list[Path] = []
    try:
        # Export all requested variants first.  No final staging path is
        # replaced until every output has passed the fresh-import gate.
        for collection, variant in variants:
            glb_path = _output_path(staging_dir, module_id, variant)
            temporary_path = _temporary_output_path(glb_path)
            temporary_paths.append(temporary_path)
            temporary_path.unlink(missing_ok=True)
            if not any(_is_exportable_object(obj) for obj in collection.objects):
                raise ValueError(
                    f"export collection {collection.name!r} contains no exportable mesh objects"
                )
            _select_collection_objects(bpy, collection)
            result = bpy.ops.export_scene.gltf(
                filepath=str(temporary_path),
                export_format="GLB",
                export_apply=True,
                use_selection=True,
            )
            if result is not None and "CANCELLED" in result:
                raise RuntimeError(
                    f"Blender cancelled GLB export for module={module_id} variant={variant}"
                )
            if not temporary_path.is_file():
                raise FileNotFoundError(
                    f"Blender did not create temporary GLB output: {temporary_path}"
                )
            byte_count = temporary_path.stat().st_size
            if byte_count <= 0:
                raise ValueError(
                    f"Blender created an empty temporary GLB output: {temporary_path}"
                )
            pending.append((variant, glb_path, temporary_path, byte_count))

        if not pending:
            raise ValueError(f"no structural variants were exported for {module_id}")

        validation_errors: list[str] = []
        for _variant, _glb_path, temporary_path, _byte_count in pending:
            try:
                _validate_exported_glb(
                    temporary_path,
                    module_id,
                    project_root,
                    dimensions,
                    bpy,
                )
            except (OSError, RuntimeError, TypeError, ValueError) as exc:
                validation_errors.append(str(exc))
        if validation_errors:
            raise ValueError(
                f"one or more structural variants failed validation for {module_id}: "
                + "; ".join(validation_errors)
            )

        targets = {glb_path for _variant, glb_path, _temporary_path, _byte_count in pending}
        obsolete = [
            candidate
            for variant in sorted(_ALLOWED_VARIANTS)
            for candidate in (_output_path(staging_dir, module_id, variant),)
            if candidate not in targets and (candidate.is_file() or candidate.is_symlink())
        ]
        publish_staged_files(
            [(temporary_path, glb_path) for _variant, glb_path, temporary_path, _byte_count in pending],
            obsolete=obsolete,
        )
    finally:
        for temporary_path in temporary_paths:
            temporary_path.unlink(missing_ok=True)

    exported: list[Path] = []
    for variant, glb_path, _temporary_path, byte_count in pending:
        print(
            "STRUCTURAL_GLB_EXPORTED "
            f"module={module_id} variant={variant} "
            f"glb={glb_path} bytes={byte_count}"
        )
        exported.append(glb_path)
    return exported


def main(argv: Sequence[str] | None = None) -> int:
    """Run the staged export and return a process exit status."""

    args = parse_args(argv)
    args.blend_path = args.blend_path.resolve()
    args.staging_dir = args.staging_dir.resolve()
    args.project_root = args.project_root.resolve()
    if args.dimensions is not None:
        args.dimensions = args.dimensions.resolve()
    bpy = _require_bpy()
    try:
        export_blend(args, bpy)
    except (FileNotFoundError, OSError, RuntimeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    # Do not call bpy.ops.wm.quit_blender here: Blender owns process teardown,
    # and quitting from the script can mask the real --python-exit-code result.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
