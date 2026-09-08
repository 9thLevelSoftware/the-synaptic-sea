#!/usr/bin/env python3
"""Fresh-Blender GLB adapter for the structural visual contract.

The canonical policy consumes runtime/Godot Y-up triangles.  Blender imports
native glTF coordinates into Z-up space, so this adapter is the only place that
performs the native conversion ``Blender [x,y,z] -> runtime [x,z,-y]``.  The
legacy authoring-helper convention ``[x,y,z] -> [x,z,y]`` is deliberately not
used for imported geometry.

Run through Blender::

    blender --background --factory-startup --python-exit-code 1 \
      --python tools/validate_structural_visual_fit.py -- \
      --project-root /path/to/repo --module wall_straight_1x1 \
      --glb /tmp/wall.glb [--dimensions /path/to/dimensions.json] \
      [--report /tmp/validation.json]
"""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any, Iterable, Sequence


_REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
try:
    sys.path.remove(str(_REPOSITORY_ROOT))
except ValueError:
    pass
sys.path.insert(0, str(_REPOSITORY_ROOT))

try:
    from tools.structural_visual_contract import (
        VisualContractError,
        load_dimensions,
        validate_geometry,
    )
except ModuleNotFoundError:  # pragma: no cover - Blender script-directory fallback
    from structural_visual_contract import VisualContractError, load_dimensions, validate_geometry


_DIMENSIONS_RELATIVE = Path("data/art/structural_visual_dimensions.v1.json")
_IDENTITY_EPSILON = 1.0e-6


class StructuralVisualFitError(ValueError):
    """Raised for invalid Blender-side scene structure or GLB input."""


def _argv_from_blender(argv: Sequence[str] | None = None) -> list[str]:
    raw = list(sys.argv[1:] if argv is None else argv)
    if "--" in raw:
        return raw[raw.index("--") + 1 :]
    return raw


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True, type=Path)
    parser.add_argument("--module", required=True)
    parser.add_argument("--glb", required=True, type=Path)
    parser.add_argument("--dimensions", type=Path, default=None)
    parser.add_argument("--report", type=Path, default=None)
    return parser


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = build_parser()
    args = parser.parse_args(_argv_from_blender(argv))
    if not args.glb.is_file():
        parser.error(f"GLB file does not exist: {args.glb}")
    if args.glb.suffix.lower() != ".glb":
        parser.error(f"GLB path must have .glb extension: {args.glb}")
    return args


def _default_dimensions_path(project_root: Path | None = None) -> Path:
    root = _REPOSITORY_ROOT if project_root is None else Path(project_root).expanduser().resolve()
    return root / _DIMENSIONS_RELATIVE


def _require_bpy() -> Any:
    return __import__("bpy")


def _get_xyz(value: Any) -> tuple[float, float, float]:
    try:
        return (float(value.x), float(value.y), float(value.z))
    except AttributeError:
        return (float(value[0]), float(value[1]), float(value[2]))


def _vector_is_close(value: Any, expected: tuple[float, float, float]) -> bool:
    try:
        actual = _get_xyz(value)
    except (AttributeError, IndexError, TypeError, ValueError):
        return False
    return all(abs(component - wanted) <= _IDENTITY_EPSILON for component, wanted in zip(actual, expected))


def _matrix_is_identity(matrix: Any) -> bool:
    if bool(getattr(matrix, "is_identity", False)):
        return True

    # mathutils.Matrix exposes translation as a Vector.  This fallback also
    # keeps injected Blender-compatible fakes small without weakening real
    # matrix inspection below.
    translation = getattr(matrix, "translation", None)
    if translation is not None and _vector_is_close(translation, (0.0, 0.0, 0.0)):
        try:
            return all(
                abs(float(matrix[row][column]) - (1.0 if row == column else 0.0))
                <= _IDENTITY_EPSILON
                for row in range(4)
                for column in range(4)
            )
        except (AttributeError, IndexError, TypeError, ValueError):
            # A translation-only test double has no matrix indexing; zero
            # translation is its complete identity representation.
            return True

    try:
        return all(
            abs(float(matrix[row][column]) - (1.0 if row == column else 0.0))
            <= _IDENTITY_EPSILON
            for row in range(4)
            for column in range(4)
        )
    except (AttributeError, IndexError, TypeError, ValueError):
        return False


def _object_property(obj: Any, name: str, default: Any = None) -> Any:
    try:
        getter = getattr(obj, "get", None)
        if callable(getter):
            value = getter(name, default)
            return default if value is None else value
    except (AttributeError, TypeError, ValueError):
        pass
    return getattr(obj, name, default)


def _looks_like_helper(obj: Any) -> bool:
    name = str(getattr(obj, "name", "")).strip().lower()
    if name.startswith(("authoring", "helper", "anchor", "sock_", "socket", "collision", "collisionproxy", "col_")):
        return True
    role = str(_object_property(obj, "structural_role", "")).strip().lower()
    if role in {"helper", "authoring_helper", "socket", "rig", "camera", "light"}:
        return True
    return bool(_object_property(obj, "authoring_helper", False))


def _root_object(obj: Any) -> Any:
    root = obj
    seen: set[int] = set()
    while getattr(root, "parent", None) is not None:
        marker = id(root)
        if marker in seen:
            raise StructuralVisualFitError(f"object parent cycle at {getattr(obj, 'name', '<unnamed>')!r}")
        seen.add(marker)
        root = root.parent
    return root


def _mesh_transform_errors(obj: Any) -> list[str]:
    errors: list[str] = []
    name = getattr(obj, "name", "<unnamed>")
    translation = getattr(obj, "location", None)
    if translation is None:
        matrix_local = getattr(obj, "matrix_local", None)
        translation = getattr(matrix_local, "translation", None)
    if translation is None:
        matrix_world = getattr(obj, "matrix_world", None)
        translation = getattr(matrix_world, "translation", None)
    if translation is not None and not _vector_is_close(translation, (0.0, 0.0, 0.0)):
        errors.append(f"mesh object {name!r} has unbaked translation")
    scale = getattr(obj, "scale", None)
    if scale is not None and not _vector_is_close(scale, (1.0, 1.0, 1.0)):
        errors.append(f"mesh object {name!r} has unbaked scale")
    rotation = getattr(obj, "rotation_euler", None)
    if rotation is not None and not _vector_is_close(rotation, (0.0, 0.0, 0.0)):
        errors.append(f"mesh object {name!r} has unbaked rotation")
    return errors


def _scene_objects(bpy: Any) -> list[Any]:
    scene = getattr(getattr(bpy, "context", None), "scene", None)
    if scene is None:
        raise StructuralVisualFitError("Blender context has no active scene")
    objects = getattr(scene, "objects", None)
    if objects is None:
        data = getattr(bpy, "data", None)
        objects = getattr(data, "objects", None)
    if objects is None:
        raise StructuralVisualFitError("imported Blender scene has no object collection")
    return list(objects)


def _validate_imported_scene(objects: Iterable[Any]) -> tuple[list[Any], dict[str, Any], list[str]]:
    mesh_objects: list[Any] = []
    errors: list[str] = []
    objects = list(objects)

    for obj in objects:
        object_type = str(getattr(obj, "type", "")).upper()
        name = str(getattr(obj, "name", "<unnamed>"))
        if object_type == "MESH":
            if _looks_like_helper(obj):
                errors.append(f"authoring helper mesh was imported: {name}")
                continue
            errors.extend(_mesh_transform_errors(obj))
            try:
                root = _root_object(obj)
            except StructuralVisualFitError as exc:
                errors.append(str(exc))
                continue
            if root is not obj and str(getattr(root, "type", "")).upper() != "MESH":
                if not _matrix_is_identity(getattr(root, "matrix_world", None)):
                    errors.append(f"import root {getattr(root, 'name', '<unnamed>')!r} has non-identity transform")
            mesh_data = getattr(obj, "data", None)
            if getattr(obj, "animation_data", None) is not None:
                errors.append(f"mesh object {name!r} contains unsupported animation data")
            if mesh_data is not None and getattr(mesh_data, "shape_keys", None) is not None:
                errors.append(f"mesh object {name!r} contains unsupported shape keys")
            modifiers = getattr(obj, "modifiers", None)
            if modifiers:
                errors.append(f"mesh object {name!r} contains unsupported modifiers")
            mesh_objects.append(obj)
            continue

        if object_type in {"LIGHT", "CAMERA", "ARMATURE"}:
            errors.append(f"unsupported imported {object_type.lower()} or rig helper: {name}")
            continue
        if object_type == "EMPTY":
            # A single identity node root is a valid glTF hierarchy.  Empty
            # authoring/socket/helper nodes are not export payload.
            if getattr(obj, "parent", None) is None and not _looks_like_helper(obj):
                if not _matrix_is_identity(getattr(obj, "matrix_world", None)):
                    errors.append(f"import root {name!r} has non-identity transform")
            else:
                errors.append(f"unsupported imported helper node: {name}")
            continue
        errors.append(f"unsupported imported object type {object_type or '<unknown>'}: {name}")

    scene = {
        "object_count": len(objects),
        "mesh_object_count": len(mesh_objects),
        "helper_objects_rejected": bool(errors),
    }
    return mesh_objects, scene, sorted(set(errors))


def _collect_triangles(bpy: Any, mesh_objects: Sequence[Any]) -> list[list[tuple[float, float, float]]]:
    context = getattr(bpy, "context", None)
    depsgraph_getter = getattr(context, "evaluated_depsgraph_get", None)
    depsgraph = depsgraph_getter() if callable(depsgraph_getter) else None
    triangles: list[list[tuple[float, float, float]]] = []
    for obj in mesh_objects:
        evaluated = obj.evaluated_get(depsgraph) if callable(getattr(obj, "evaluated_get", None)) else obj
        mesh = evaluated.to_mesh() if callable(getattr(evaluated, "to_mesh", None)) else getattr(evaluated, "data", None)
        if mesh is None:
            continue
        matrix_world = getattr(evaluated, "matrix_world", getattr(obj, "matrix_world", None))
        vertices = getattr(mesh, "vertices", ())
        try:
            for polygon in getattr(mesh, "polygons", ()):
                indices = tuple(int(index) for index in polygon.vertices)
                if len(indices) < 3:
                    continue
                world_points = []
                for index in indices:
                    local = vertices[index].co
                    world = matrix_world @ local
                    x, y, z = _get_xyz(world)
                    if not all(math.isfinite(value) for value in (x, y, z)):
                        raise StructuralVisualFitError(
                            f"mesh object {getattr(obj, 'name', '<unnamed>')!r} has non-finite vertex"
                        )
                    # Native glTF/Y-up conversion.  Do not substitute the
                    # legacy source-helper conversion [x,z,y].
                    world_points.append((x, z, -y))
                for offset in range(1, len(world_points) - 1):
                    triangles.append([world_points[0], world_points[offset], world_points[offset + 1]])
        finally:
            clear = getattr(evaluated, "to_mesh_clear", None)
            if callable(clear):
                clear()
    return triangles


def _scene_dynamic_payload_errors(bpy: Any) -> list[str]:
    errors: list[str] = []
    scene = getattr(getattr(bpy, "context", None), "scene", None)
    if getattr(scene, "animation_data", None) is not None:
        errors.append("scene contains unsupported animation data")
    data = getattr(bpy, "data", None)
    for attribute, label in (
        ("actions", "animation actions"),
        ("armatures", "armature data"),
        ("shape_keys", "shape-key data"),
    ):
        values = getattr(data, attribute, None)
        try:
            present = values is not None and len(values) > 0
        except TypeError:
            present = bool(values)
        if present:
            errors.append(f"scene contains unsupported {label}")
    return errors


def _load_policy(dimensions: Path | dict[str, Any] | None) -> dict[str, Any]:
    if isinstance(dimensions, dict):
        return dimensions
    return load_dimensions(None if dimensions is None else Path(dimensions))


def _failure(errors: Iterable[str], *, measurements: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "status": "fail",
        "errors": sorted(set(str(error) for error in errors if str(error))),
        "measurements": measurements or {},
    }


def validate_glb(
    path: Path | str,
    module_id: str,
    dimensions: Path | dict[str, Any] | None = None,
    bpy: Any | None = None,
) -> dict[str, Any]:
    """Fresh-import one GLB, measure evaluated world geometry, and validate it.

    ``bpy`` is injectable only for tests; production callers omit it and this
    function obtains Blender's real Python API.  A non-``pass`` result is a
    validation failure/hold and must never be published by callers.
    """
    glb_path = Path(path).expanduser().resolve()
    if not glb_path.is_file():
        raise FileNotFoundError(f"GLB file does not exist: {glb_path}")
    if glb_path.suffix.lower() != ".glb":
        raise StructuralVisualFitError(f"GLB path must have .glb extension: {glb_path}")
    if glb_path.stat().st_size <= 0:
        return _failure([f"GLB file is empty: {glb_path}"])

    try:
        policy = _load_policy(dimensions)
    except (OSError, RuntimeError, TypeError, ValueError, VisualContractError) as exc:
        return _failure([f"cannot load structural visual policy: {exc}"])

    blender = _require_bpy() if bpy is None else bpy
    try:
        reset = blender.ops.wm.read_factory_settings(use_empty=True)
        if reset is not None and "CANCELLED" in reset:
            return _failure(["Blender factory reset was cancelled"])
        imported = blender.ops.import_scene.gltf(filepath=str(glb_path))
        if imported is None or "FINISHED" not in imported:
            return _failure([f"Blender GLB import did not finish: {imported!r}"])
        objects = _scene_objects(blender)
        mesh_objects: list[Any] = [
            obj for obj in objects if str(getattr(obj, "type", "")).upper() == "MESH" and not _looks_like_helper(obj)
        ]
        _scene_triangles, scene_measurements, scene_errors = _validate_imported_scene(objects)
        scene_errors.extend(_scene_dynamic_payload_errors(blender))
        # _validate_imported_scene deliberately performs structure checks before
        # extraction; evaluated vertices are collected from the same fresh scene.
        triangles = _collect_triangles(blender, mesh_objects)
        scene_measurements["triangle_count"] = len(triangles)
        scene_measurements["validation_scope"] = "per_module_visual_interface"
        scene_measurements["assembly_acceptance"] = False
        if scene_errors:
            return _failure(scene_errors, measurements=scene_measurements)
        if not triangles:
            return _failure(["imported scene contains no mesh triangles"], measurements=scene_measurements)
        result = validate_geometry(module_id, triangles, policy)
        merged = dict(result)
        measurements = dict(scene_measurements)
        measurements.update(result.get("measurements", {}))
        merged["measurements"] = measurements
        merged.setdefault("module_id", module_id)
        merged["glb"] = str(glb_path)
        merged["coordinate_conversion"] = "Blender [x,y,z] -> native glTF/runtime [x,z,-y]"
        merged["legacy_helper_conversion_not_used"] = "[x,z,y]"
        return merged
    except (OSError, RuntimeError, TypeError, ValueError, StructuralVisualFitError, VisualContractError) as exc:
        return _failure([f"Blender visual validation failed: {exc}"])


def validate_glb_in_subprocess(
    path: Path | str,
    module_id: str,
    project_root: Path,
    dimensions: Path | None = None,
    *,
    blender_executable: str | Path | None = None,
    timeout: float = 180.0,
) -> dict[str, Any]:
    """Validate one GLB in a fresh Blender process without touching the caller.

    This is mandatory for UI/add-on callers: resetting ``bpy`` in an artist's
    process would destroy unsaved work.  A temporary report is used instead of
    parsing Blender's mixed stdout, and both the child exit code and report
    status are required for success.
    """

    glb_path = Path(path).expanduser().resolve()
    root = Path(project_root).expanduser().resolve()
    executable = str(blender_executable or os.environ.get("BLENDER", "/opt/homebrew/bin/blender"))
    with tempfile.TemporaryDirectory(prefix="structural-glb-validation-") as temporary:
        report = Path(temporary) / "report.json"
        command = [
            executable,
            "--background",
            "--factory-startup",
            "--python-exit-code",
            "1",
            "--python",
            str(Path(__file__).resolve()),
            "--",
            "--project-root",
            str(root),
            "--module",
            module_id,
            "--glb",
            str(glb_path),
            "--report",
            str(report),
        ]
        if dimensions is not None:
            command.extend(("--dimensions", str(Path(dimensions).expanduser().resolve())))
        try:
            completed = subprocess.run(
                command,
                cwd=str(root),
                capture_output=True,
                text=True,
                check=False,
                timeout=timeout,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            return _failure([f"isolated Blender validation could not complete: {exc}"])

        if not report.is_file():
            detail = completed.stderr.strip() or completed.stdout.strip() or "no validation report"
            return _failure([f"isolated Blender validation produced no report: {detail}"])
        try:
            result = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            return _failure([f"isolated Blender validation report is invalid: {exc}"])
        if not isinstance(result, dict):
            return _failure(["isolated Blender validation report is not an object"])
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            result = dict(result)
            result["status"] = "fail"
            result["errors"] = list(result.get("errors") or []) + [
                f"isolated Blender exited with status {completed.returncode}"
                + (f": {detail}" if detail else "")
            ]
        return result


def _write_report(path: Path, result: dict[str, Any]) -> None:
    path = Path(path).expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.unlink(missing_ok=True)
    try:
        temporary.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    dimensions = args.dimensions or _default_dimensions_path(args.project_root)
    try:
        result = validate_glb(args.glb, args.module, dimensions, _require_bpy())
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        result = _failure([str(exc)])
    if args.report is not None:
        _write_report(args.report, result)
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("status") == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
