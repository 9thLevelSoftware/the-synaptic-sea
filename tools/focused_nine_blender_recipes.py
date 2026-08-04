#!/usr/bin/env python3
"""Idempotent, generated-only visual recipes for the focused nine assets.

The contract and selection helpers in this module are importable with ordinary
Python.  Blender is imported lazily, after the asset id and source paths have
been validated, so a typo cannot start a Blender mutation.

The two source roots are intentionally distinct:

* ``--structural-source-root`` contains ``<asset>/<asset>.blend`` under the
  ``ship_structural_v0`` kit source directory.
* ``--props-source-root`` contains ``<asset>.blend`` files directly.

Only objects in the generated namespace ``FocusedNine_<asset_id>_`` are
removed.  Authored objects, helpers, collections, and runtime assets are never
cleared or replaced by this driver.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Iterable, Sequence

try:
    from tools import focused_nine_contract
    from tools.structural_source_contract import load_source_spec
except ModuleNotFoundError:  # Blender executes a script with tools as sys.path[0].
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools import focused_nine_contract
    from tools.structural_source_contract import load_source_spec


STRUCTURAL_ASSET_IDS: tuple[str, ...] = focused_nine_contract.STRUCTURAL_IDS
PROP_ASSET_IDS: tuple[str, ...] = focused_nine_contract.PROP_IDS
ALL_ASSET_IDS: tuple[str, ...] = STRUCTURAL_ASSET_IDS + PROP_ASSET_IDS
REQUIRED_MATERIAL_NAMES: tuple[str, ...] = (
    "MAT_PaintedAlloyGray",
    "MAT_WarningStripe",
    "MAT_ReactorGlow",
    "MAT_Conduit",
)
_GENERATED_PREFIX = "FocusedNine_"
_MATERIAL_LIBRARY_NAME = "salvage_industrial.blend"

# Blender is deliberately not imported at module import time.
_BPY: Any | None = None


def _require_bpy() -> Any:
    """Import bpy only after pure-Python validation has completed."""

    global _BPY
    if _BPY is None:
        _BPY = __import__("bpy")
    return _BPY


def select_asset(asset_id: str) -> str:
    """Return ``structural`` or ``prop`` for a registered focused-nine id."""

    if asset_id in STRUCTURAL_ASSET_IDS:
        return "structural"
    if asset_id in PROP_ASSET_IDS:
        return "prop"
    raise ValueError(f"unknown focused-nine asset id: {asset_id!r}")


def source_blend_path(
    structural_source_root: Path, props_source_root: Path, asset_id: str
) -> Path:
    """Return the exact source `.blend` path for one registered asset.

    Structural roots are rooted at ``ship_structural_v0``; props roots are
    rooted at the flat prop source directory.  No path normalization or
    existence check is performed here, which keeps this helper deterministic
    and useful to Python-only callers.
    """

    kind = select_asset(asset_id)
    if kind == "structural":
        return Path(structural_source_root) / asset_id / f"{asset_id}.blend"
    return Path(props_source_root) / f"{asset_id}.blend"


def source_path(
    structural_source_root: Path, props_source_root: Path, asset_id: str
) -> Path:
    """Compatibility alias for the plan's pure-Python source-path interface."""

    return source_blend_path(structural_source_root, props_source_root, asset_id)


def structural_source_path(structural_source_root: Path, asset_id: str) -> Path:
    """Return the exact structural source path after allowlist validation."""

    if select_asset(asset_id) != "structural":
        raise ValueError(f"asset is not structural: {asset_id!r}")
    return Path(structural_source_root) / asset_id / f"{asset_id}.blend"


def prop_source_path(props_source_root: Path, asset_id: str) -> Path:
    """Return the exact flat prop source path after allowlist validation."""

    if select_asset(asset_id) != "prop":
        raise ValueError(f"asset is not a prop: {asset_id!r}")
    return Path(props_source_root) / f"{asset_id}.blend"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--structural-source-root", type=Path, required=True)
    parser.add_argument("--props-source-root", type=Path, required=True)
    parser.add_argument("--asset-id", required=True)
    parser.add_argument("--overwrite-generated-only", action="store_true")
    return parser


def _argv_from_blender(argv: Sequence[str] | None) -> list[str]:
    if argv is not None:
        return list(argv)
    raw = list(sys.argv[1:])
    return raw[raw.index("--") + 1 :] if "--" in raw else raw


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse the CLI and reject unknown ids without importing Blender."""

    parser = build_parser()
    args = parser.parse_args(_argv_from_blender(argv))
    try:
        select_asset(args.asset_id)
    except ValueError as exc:
        parser.error(str(exc))
    return args


def _generated_name(asset_id: str, token: str) -> str:
    return f"{_GENERATED_PREFIX}{asset_id}_{token}"


def _material_library_candidates(
    project_root: Path, structural_root: Path, props_root: Path
) -> tuple[Path, ...]:
    configured = os.environ.get("FOCUSED_NINE_MATERIAL_LIBRARY")
    candidates: list[Path] = []
    if configured:
        candidates.append(Path(configured).expanduser())
    candidates.extend(
        (
            Path(project_root) / "meshes/source/materials" / _MATERIAL_LIBRARY_NAME,
            Path(structural_root).parent / "materials" / _MATERIAL_LIBRARY_NAME,
            Path(structural_root) / "materials" / _MATERIAL_LIBRARY_NAME,
            Path(props_root).parent / "materials" / _MATERIAL_LIBRARY_NAME,
            Path(project_root).parent / "meshes/source/materials" / _MATERIAL_LIBRARY_NAME,
        )
    )
    unique: list[Path] = []
    seen: set[Path] = set()
    for candidate in candidates:
        candidate = candidate.resolve(strict=False)
        if candidate not in seen:
            seen.add(candidate)
            unique.append(candidate)
    return tuple(unique)


def ensure_material_library(
    project_root: Path, structural_root: Path, props_root: Path
) -> dict[str, Any]:
    """Load and require all four exact Salvage Industrial materials.

    Existing exact-name datablocks are retained, but a configured library must
    still contain every required name before any generated object is created.
    There are intentionally no synthesized fallback materials.
    """

    bpy = _require_bpy()
    existing = {name for name in REQUIRED_MATERIAL_NAMES if bpy.data.materials.get(name)}
    library_path = next(
        (candidate for candidate in _material_library_candidates(project_root, structural_root, props_root) if candidate.is_file()),
        None,
    )
    if library_path is None:
        searched = ", ".join(str(path) for path in _material_library_candidates(project_root, structural_root, props_root))
        raise RuntimeError(f"missing required material library {_MATERIAL_LIBRARY_NAME}; searched: {searched}")

    with bpy.data.libraries.load(str(library_path), link=False) as (data_from, data_to):
        available = set(data_from.materials)
        missing = sorted(set(REQUIRED_MATERIAL_NAMES) - available)
        if missing:
            raise RuntimeError(
                f"material library {library_path} is missing required materials: {', '.join(missing)}"
            )
        data_to.materials = [name for name in REQUIRED_MATERIAL_NAMES if name not in existing]

    missing_after_load = [name for name in REQUIRED_MATERIAL_NAMES if bpy.data.materials.get(name) is None]
    if missing_after_load:
        raise RuntimeError(
            "required materials were not loaded exactly: " + ", ".join(missing_after_load)
        )
    return {"library_path": str(library_path), "material_names": list(REQUIRED_MATERIAL_NAMES)}


def _link_object(obj: Any, collection: Any) -> None:
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    collection.objects.link(obj)


def _activate_only(obj: Any) -> None:
    """Select only a newly created object without touching scene contents."""

    bpy = _require_bpy()
    for selected in list(bpy.context.selected_objects):
        selected.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _apply_transform(obj: Any, *, rotation: bool = True) -> None:
    bpy = _require_bpy()
    _activate_only(obj)
    bpy.ops.object.transform_apply(location=False, rotation=rotation, scale=True)


def _assign_material(obj: Any, material_name: str) -> None:
    bpy = _require_bpy()
    material = bpy.data.materials.get(material_name)
    if material is None:
        raise RuntimeError(f"required material is unavailable: {material_name}")
    if obj.type == "MESH":
        if len(obj.data.materials) == 0:
            obj.data.materials.append(material)
        else:
            obj.data.materials[0] = material


def _bevel(obj: Any, width: float) -> Any:
    """Apply a small non-destructive-looking bevel to a generated box."""

    bpy = _require_bpy()
    modifier = obj.modifiers.new(name="FocusedNineBevel", type="BEVEL")
    modifier.width = max(0.001, float(width))
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    _activate_only(obj)
    result = bpy.ops.object.modifier_apply(modifier=modifier.name)
    if "FINISHED" not in result:
        raise RuntimeError(f"could not apply bevel to generated object {obj.name}")
    return obj


def _box(
    asset_id: str,
    token: str,
    collection: Any,
    size: Sequence[float],
    location: Sequence[float],
    material_name: str,
    *,
    bevel_width: float = 0.0,
) -> Any:
    bpy = _require_bpy()
    dimensions = tuple(max(0.001, float(value)) for value in size)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=tuple(float(value) for value in location))
    obj = bpy.context.active_object
    obj.name = _generated_name(asset_id, token)
    _link_object(obj, collection)
    obj.dimensions = dimensions
    _apply_transform(obj)
    if bevel_width:
        _bevel(obj, bevel_width)
    _assign_material(obj, material_name)
    return obj


def _cylinder(
    asset_id: str,
    token: str,
    collection: Any,
    radius: float,
    depth: float,
    location: Sequence[float],
    material_name: str,
    *,
    rotation: Sequence[float] = (0.0, 0.0, 0.0),
    vertices: int = 12,
) -> Any:
    bpy = _require_bpy()
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=max(0.001, float(radius)),
        depth=max(0.001, float(depth)),
        location=tuple(float(value) for value in location),
        rotation=tuple(float(value) for value in rotation),
    )
    obj = bpy.context.active_object
    obj.name = _generated_name(asset_id, token)
    _link_object(obj, collection)
    _apply_transform(obj)
    _assign_material(obj, material_name)
    return obj


def _dimensions_from_spec(spec: Any) -> tuple[float, float, float]:
    try:
        minimum = tuple(float(value) for value in spec.bounds_min_y_up)
        maximum = tuple(float(value) for value in spec.bounds_max_y_up)
        return (
            max(0.5, maximum[0] - minimum[0]),
            max(0.5, maximum[2] - minimum[2]),
            max(0.25, maximum[1] - minimum[1]),
        )
    except (AttributeError, TypeError, ValueError):
        return (4.0, 4.0, 0.25)


def _base_z(spec: Any) -> float:
    try:
        return float(spec.bounds_min_y_up[1])
    except (AttributeError, IndexError, TypeError, ValueError):
        return 0.0


def _add_floor_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, depth, thickness = _dimensions_from_spec(spec)
    z = _base_z(spec)
    objects: list[Any] = []
    objects.append(_box(asset_id, "floor_panel", collection, (width - 0.12, depth - 0.12, max(0.12, thickness)), (0, 0, z + thickness / 2), "MAT_PaintedAlloyGray", bevel_width=0.025))
    objects.append(_box(asset_id, "panel_seam_ns", collection, (0.025, depth - 0.22, 0.018), (0, 0, z + thickness + 0.012), "MAT_Conduit"))
    objects.append(_box(asset_id, "panel_seam_ew", collection, (width - 0.22, 0.025, 0.018), (0, 0, z + thickness + 0.013), "MAT_Conduit"))
    objects.append(_box(asset_id, "access_plate", collection, (0.72, 0.72, 0.045), (0.55, -0.55, z + thickness + 0.025), "MAT_PaintedAlloyGray", bevel_width=0.02))
    for index, (x, y) in enumerate(((0.26, -0.84), (0.84, -0.84), (0.26, -0.26), (0.84, -0.26))):
        objects.append(_cylinder(asset_id, f"access_bolt_{index:02d}", collection, 0.045, 0.035, (x, y, z + thickness + 0.065), "MAT_WarningStripe", vertices=12))
    for side, x in (("west", -width / 2 + 0.18), ("east", width / 2 - 0.18)):
        objects.append(_box(asset_id, f"conduit_channel_{side}", collection, (0.12, depth - 0.45, 0.07), (x, 0, z + thickness + 0.035), "MAT_Conduit", bevel_width=0.015))
    objects.append(_cylinder(asset_id, "drain_grate", collection, 0.18, 0.035, (0, 0.95, z + thickness + 0.02), "MAT_Conduit", vertices=16))
    for index, x in enumerate((-0.09, 0.09)):
        objects.append(_box(asset_id, f"drain_bar_{index:02d}", collection, (0.025, 0.26, 0.025), (x, 0.95, z + thickness + 0.045), "MAT_WarningStripe"))
    return objects


def _add_wall_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, _depth, height = _dimensions_from_spec(spec)
    height = max(3.5, height)
    thickness = 0.28
    objects = [
        _box(asset_id, "perimeter_left", collection, (0.22, thickness, height), (-width / 2 + 0.12, 0, height / 2), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "perimeter_right", collection, (0.22, thickness, height), (width / 2 - 0.12, 0, height / 2), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "perimeter_top", collection, (width, thickness, 0.22), (0, 0, height - 0.11), "MAT_PaintedAlloyGray", bevel_width=0.02),
    ]
    for index, x in enumerate((-width * 0.22, width * 0.22)):
        objects.append(_box(asset_id, f"inset_panel_{index:02d}", collection, (width * 0.28, 0.06, height * 0.52), (x, -0.17, height * 0.49), "MAT_PaintedAlloyGray", bevel_width=0.025))
    objects.extend(
        (
            _box(asset_id, "conduit_vertical", collection, (0.09, 0.09, height * 0.72), (-width / 2 + 0.42, -0.22, height * 0.46), "MAT_Conduit", bevel_width=0.015),
            _box(asset_id, "service_cover", collection, (0.46, 0.08, 0.38), (width / 2 - 0.42, -0.22, height * 0.3), "MAT_WarningStripe", bevel_width=0.015),
        )
    )
    return objects


def _add_doorway_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, _depth, height = _dimensions_from_spec(spec)
    opening_width = min(width * 0.62, 2.5)
    jamb_height = max(3.4, height)
    objects = [
        _box(asset_id, "jamb_left", collection, (0.32, 0.42, jamb_height), (-opening_width / 2 - 0.2, 0, jamb_height / 2), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "jamb_right", collection, (0.32, 0.42, jamb_height), (opening_width / 2 + 0.2, 0, jamb_height / 2), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "lintel", collection, (opening_width + 0.72, 0.42, 0.34), (0, 0, jamb_height - 0.17), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "indicator_bay_left", collection, (0.12, 0.48, 0.26), (-opening_width / 2 - 0.2, -0.26, jamb_height - 0.5), "MAT_ReactorGlow", bevel_width=0.015),
        _box(asset_id, "indicator_bay_right", collection, (0.12, 0.48, 0.26), (opening_width / 2 + 0.2, -0.26, jamb_height - 0.5), "MAT_ReactorGlow", bevel_width=0.015),
        _box(asset_id, "threshold", collection, (opening_width + 0.72, 0.65, 0.12), (0, 0, 0.06), "MAT_WarningStripe", bevel_width=0.02),
    ]
    return objects


def _add_pillar_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, depth, height = _dimensions_from_spec(spec)
    body = min(width, depth) * 0.34
    objects = [
        _box(asset_id, "pillar_body", collection, (body, body, max(2.8, height - 0.45)), (0, 0, max(2.8, height - 0.45) / 2 + 0.22), "MAT_PaintedAlloyGray", bevel_width=0.04),
        _box(asset_id, "base", collection, (body * 1.45, body * 1.45, 0.22), (0, 0, 0.11), "MAT_PaintedAlloyGray", bevel_width=0.03),
        _box(asset_id, "cap", collection, (body * 1.35, body * 1.35, 0.2), (0, 0, max(2.8, height) - 0.1), "MAT_PaintedAlloyGray", bevel_width=0.03),
        _cylinder(asset_id, "collar", collection, body * 0.55, 0.18, (0, 0, max(2.8, height) * 0.55), "MAT_WarningStripe", vertices=12),
    ]
    for index, x in enumerate((-body * 0.58, body * 0.58)):
        objects.append(_box(asset_id, f"rib_{index:02d}", collection, (0.1, body * 0.98, max(1.8, height * 0.72)), (x, 0, max(1.8, height * 0.72) / 2 + 0.35), "MAT_Conduit", bevel_width=0.015))
    return objects


def _add_ramp_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, depth, _height = _dimensions_from_spec(spec)
    width = max(width, 3.6)
    depth = max(depth, 7.0)
    tread_count = 6
    objects: list[Any] = []
    for index in range(tread_count):
        y = -depth / 2 + (index + 0.5) * depth / tread_count
        z = 0.09 + index * 0.14
        objects.append(_box(asset_id, f"tread_{index:02d}", collection, (width - 0.4, depth / tread_count - 0.04, 0.16), (0, y, z), "MAT_PaintedAlloyGray", bevel_width=0.018))
    for side, x in (("left", -width / 2 + 0.12), ("right", width / 2 - 0.12)):
        objects.append(_box(asset_id, f"curb_{side}", collection, (0.18, depth, 0.42), (x, 0, 0.22), "MAT_WarningStripe", bevel_width=0.02))
    objects.append(_box(asset_id, "raceway", collection, (0.13, depth * 0.78, 0.11), (width / 2 - 0.42, 0, 0.58), "MAT_Conduit", bevel_width=0.015))
    return objects


def _add_ceiling_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, depth, _height = _dimensions_from_spec(spec)
    objects = [
        _box(asset_id, "ceiling_cap", collection, (width - 0.12, depth - 0.12, 0.2), (0, 0, 3.9), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "light_trough", collection, (width * 0.58, 0.3, 0.08), (0, 0, 3.76), "MAT_ReactorGlow", bevel_width=0.015),
        _box(asset_id, "service_tray", collection, (width * 0.3, depth * 0.4, 0.08), (width * 0.28, 0, 3.76), "MAT_Conduit", bevel_width=0.015),
    ]
    for index, x in enumerate((-width * 0.25, -width * 0.08, width * 0.09, width * 0.26)):
        objects.append(_box(asset_id, f"vent_bar_{index:02d}", collection, (0.06, depth * 0.48, 0.08), (x, 0, 3.76), "MAT_WarningStripe"))
    return objects


def _add_pressure_door_recipe(asset_id: str, spec: Any, collection: Any) -> list[Any]:
    width, _depth, height = _dimensions_from_spec(spec)
    portal_width = min(width * 0.68, 2.7)
    height = max(height, 3.4)
    objects = [
        _box(asset_id, "outer_portal_left", collection, (0.35, 0.48, height), (-portal_width / 2 - 0.28, 0, height / 2), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "outer_portal_right", collection, (0.35, 0.48, height), (portal_width / 2 + 0.28, 0, height / 2), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "outer_portal_lintel", collection, (portal_width + 0.91, 0.48, 0.36), (0, 0, height - 0.18), "MAT_PaintedAlloyGray", bevel_width=0.035),
        _box(asset_id, "split_leaf_left", collection, (portal_width * 0.47, 0.18, height * 0.78), (-portal_width * 0.235, -0.06, height * 0.43), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "split_leaf_right", collection, (portal_width * 0.47, 0.18, height * 0.78), (portal_width * 0.235, -0.06, height * 0.43), "MAT_PaintedAlloyGray", bevel_width=0.02),
        _box(asset_id, "motor_housing", collection, (0.82, 0.52, 0.34), (0, 0, height - 0.56), "MAT_Conduit", bevel_width=0.025),
        _box(asset_id, "warning_threshold", collection, (portal_width + 0.7, 0.72, 0.13), (0, 0, 0.065), "MAT_WarningStripe", bevel_width=0.02),
        _box(asset_id, "cyan_indicator_left", collection, (0.09, 0.12, 0.3), (-portal_width / 2 - 0.28, -0.31, height - 0.62), "MAT_ReactorGlow", bevel_width=0.01),
        _box(asset_id, "cyan_indicator_right", collection, (0.09, 0.12, 0.3), (portal_width / 2 + 0.28, -0.31, height - 0.62), "MAT_ReactorGlow", bevel_width=0.01),
    ]
    return objects


def build_structural_recipe(asset_id: str, spec: Any, geometry: Any) -> list[Any]:
    """Build one structural visual recipe using additive primitives only."""

    if select_asset(asset_id) != "structural":
        raise ValueError(f"asset is not structural: {asset_id!r}")
    recipes = {
        "floor_1x1": _add_floor_recipe,
        "wall_straight_1x1": _add_wall_recipe,
        "doorway_frame_open_1x1": _add_doorway_recipe,
        "pillar_support_1x1": _add_pillar_recipe,
        "ramp_up_1x2": _add_ramp_recipe,
        "ceiling_cap_1x1": _add_ceiling_recipe,
        "pressure_door_1x1": _add_pressure_door_recipe,
    }
    return recipes[asset_id](asset_id, spec, geometry)


def _add_hull_breach_prop(asset_id: str, collection: Any) -> list[Any]:
    objects: list[Any] = [
        _box(asset_id, "clamp_frame_top", collection, (2.0, 0.18, 0.18), (0, 0, 1.0), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "clamp_frame_bottom", collection, (2.0, 0.18, 0.18), (0, 0, -1.0), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "clamp_frame_left", collection, (0.18, 0.18, 2.0), (-1.0, 0, 0), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "clamp_frame_right", collection, (0.18, 0.18, 2.0), (1.0, 0, 0), "MAT_PaintedAlloyGray", bevel_width=0.025),
        _box(asset_id, "orange_face", collection, (1.45, 0.14, 0.72), (0, -0.08, 0), "MAT_WarningStripe", bevel_width=0.025),
        _box(asset_id, "conduit", collection, (0.13, 0.35, 1.65), (0.72, -0.16, 0), "MAT_Conduit", bevel_width=0.015),
    ]
    for index, (x, z) in enumerate(((-0.72, -0.72), (0.72, -0.72), (-0.72, 0.72), (0.72, 0.72))):
        objects.append(_box(asset_id, f"clamp_arm_{index:02d}", collection, (0.14, 0.32, 0.72), (x, 0, z), "MAT_Conduit", bevel_width=0.015))
    return objects


def _add_fire_station_prop(asset_id: str, collection: Any) -> list[Any]:
    objects = [
        _box(asset_id, "red_cabinet", collection, (1.1, 0.42, 1.8), (0, 0, 0.9), "MAT_WarningStripe", bevel_width=0.04),
        _cylinder(asset_id, "hose_reel", collection, 0.38, 0.16, (0, -0.28, 0.9), "MAT_Conduit", rotation=(1.570796, 0.0, 0.0), vertices=16),
        _box(asset_id, "emergency_light", collection, (0.22, 0.16, 0.22), (0, -0.28, 1.68), "MAT_ReactorGlow", bevel_width=0.02),
        _box(asset_id, "labeled_shape_panel", collection, (0.6, 0.06, 0.34), (0, -0.25, 0.38), "MAT_PaintedAlloyGray", bevel_width=0.015),
    ]
    objects[-1]["label_shape"] = "emergency_service_panel"
    objects[-1]["text_mesh"] = False
    return objects


def build_prop_recipe(asset_id: str, collection: Any) -> list[Any]:
    """Build one prop visual recipe without touching authored prop objects."""

    if select_asset(asset_id) != "prop":
        raise ValueError(f"asset is not a prop: {asset_id!r}")
    if asset_id == "hull_breach_seal_point":
        return _add_hull_breach_prop(asset_id, collection)
    return _add_fire_station_prop(asset_id, collection)


def _ensure_collection(name: str) -> Any:
    bpy = _require_bpy()
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    scene_root = bpy.context.scene.collection
    if collection.name not in {child.name for child in scene_root.children}:
        scene_root.children.link(collection)
    return collection


def _ensure_empty(name: str, root: Any, helpers: Any, role: str) -> Any:
    bpy = _require_bpy()
    existing = bpy.data.objects.get(name)
    if existing is not None:
        return existing
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.empty_display_size = 0.35
    helpers.objects.link(empty)
    empty.parent = root
    empty["export_role"] = role
    empty["focused_nine_anchor"] = True
    return empty


def ensure_structural_helpers(spec: Any, root: Any, helpers: Any) -> None:
    """Preserve helpers and create only the allowed export-role collections."""

    module_id = getattr(spec, "module_id", "")
    root_name = getattr(root, "name", "")
    if root_name == "ModuleRoot_pressure_door_1x1":
        module_id = "pressure_door_1x1"
    roles = ("intact", "damaged", "breached") if module_id == "pressure_door_1x1" else ("intact",)
    for role in roles:
        name = f"Export_{role}"
        bpy = _require_bpy()
        collection = bpy.data.collections.get(name)
        if collection is None:
            collection = bpy.data.collections.new(name)
        if collection.name not in {child.name for child in helpers.children}:
            helpers.children.link(collection)
        collection["variant_role"] = role
        collection["module_id"] = "pressure_door_1x1" if module_id == "pressure_door_1x1" else module_id
        if module_id == "pressure_door_1x1":
            collection["variant_visual_rule"] = {
                "intact": "all pressure-door panels",
                "damaged": "one cosmetic indicator panel omitted",
                "breached": "central leaf omitted",
            }[role]


def replace_generated_visuals(root: Any, geometry: Any, asset_id: str) -> None:
    """Remove only this asset's generated objects from its target collection."""

    select_asset(asset_id)
    prefix = _generated_name(asset_id, "")
    bpy = _require_bpy()
    target_collections = [geometry]
    target_collections.extend(
        collection
        for collection in bpy.data.collections
        if collection.name.startswith("Export_")
    )
    for collection in target_collections:
        for obj in list(collection.objects):
            if obj.name.startswith(prefix):
                bpy.data.objects.remove(obj, do_unlink=True)


def _parent_generated(root: Any, objects: Iterable[Any]) -> None:
    for obj in objects:
        obj.parent = root
        obj["focused_nine_generated"] = True


def _link_existing_object(obj: Any, collection: Any) -> None:
    if obj.name not in {item.name for item in collection.objects}:
        collection.objects.link(obj)


def _build_export_variants(
    asset_id: str,
    root: Any,
    generated: Sequence[Any],
    export_collections: dict[str, Any],
) -> list[Any]:
    """Link intact visuals and make pressure-door-only variant copies."""

    for obj in generated:
        _link_existing_object(obj, export_collections["intact"])
    if asset_id != "pressure_door_1x1":
        return list(generated)

    variant_objects: list[Any] = list(generated)
    for role in ("damaged", "breached"):
        destination = export_collections[role]
        for obj in generated:
            if role == "damaged" and obj.name.endswith("_cyan_indicator_right"):
                continue
            if role == "breached" and obj.name.endswith("_split_leaf_left"):
                continue
            copy = obj.copy()
            copy.data = obj.data.copy()
            token = obj.name.removeprefix(_generated_name(asset_id, ""))
            copy.name = _generated_name(asset_id, f"{role}_{token}")
            destination.objects.link(copy)
            copy.parent = root
            copy["focused_nine_generated"] = True
            copy["variant_role"] = role
            variant_objects.append(copy)
    return variant_objects


def _structural_spec(project_root: Path, asset_id: str) -> Any:
    if asset_id != "pressure_door_1x1":
        return load_source_spec(Path(project_root), asset_id)
    candidate_path = focused_nine_contract.asset_stage_glb(project_root, asset_id)
    if candidate_path.is_file():
        from tools.structural_source_contract import load_candidate_source_spec

        return load_candidate_source_spec(project_root, asset_id, candidate_path)
    # The pressure-door source can be authored before its staged candidate GLB
    # is promoted.  Its contract intentionally mirrors the open doorway family.
    return load_source_spec(Path(project_root), "doorway_frame_open_1x1")


def _triangle_count(objects: Iterable[Any]) -> int:
    count = 0
    for obj in objects:
        if obj.type != "MESH":
            continue
        obj.data.calc_loop_triangles()
        count += len(obj.data.loop_triangles)
    return count


def _report(
    asset_id: str,
    kind: str,
    source_path: Path,
    generated: Sequence[Any],
    helpers: Any | None,
    material_info: dict[str, Any],
) -> dict[str, Any]:
    names = sorted(obj.name for obj in generated)
    if any(not name.startswith(_generated_name(asset_id, "")) for name in names):
        raise RuntimeError(f"generated object escaped namespace for {asset_id}")
    helper_names = []
    if helpers is not None:
        bpy = _require_bpy()
        helper_names = sorted(
            collection.name
            for collection in bpy.data.collections
            if collection.name.startswith("Export_")
        )
    modifier_types = sorted(
        {
            modifier.type
            for obj in generated
            for modifier in getattr(obj, "modifiers", ())
        }
    )
    return {
        "asset_id": asset_id,
        "kind": kind,
        "source_path": str(source_path),
        "generated_object_names": names,
        "generated_count": len(names),
        "triangle_count": _triangle_count(generated),
        "helper_names": helper_names,
        "material_names": list(material_info["material_names"]),
        "modifier_types": modifier_types,
        "boolean_modifiers": [
            obj.name
            for obj in generated
            for modifier in getattr(obj, "modifiers", ())
            if modifier.type.casefold() == "boolean"
        ],
    }


def _run(args: argparse.Namespace) -> dict[str, Any]:
    """Open, mutate, report, and save one requested source blend."""

    # This path selection is deliberately before _require_bpy().
    kind = select_asset(args.asset_id)
    source_path = source_blend_path(args.structural_source_root, args.props_source_root, args.asset_id)
    if not source_path.is_file():
        raise FileNotFoundError(f"requested focused-nine source blend does not exist: {source_path}")
    spec = _structural_spec(args.project_root, args.asset_id) if kind == "structural" else None
    bpy = _require_bpy()
    result = bpy.ops.wm.open_mainfile(filepath=str(source_path))
    if "FINISHED" not in result:
        raise RuntimeError(f"Blender could not open source blend: {source_path}")
    material_info = ensure_material_library(args.project_root, args.structural_source_root, args.props_source_root)

    if kind == "structural":
        root = bpy.data.objects.get(f"ModuleRoot_{args.asset_id}")
        if root is None:
            root = bpy.data.objects.new(f"ModuleRoot_{args.asset_id}", None)
            bpy.context.scene.collection.objects.link(root)
        geometry = _ensure_collection("Geometry")
        helpers = _ensure_collection("AuthoringHelpers")
        replace_generated_visuals(root, geometry, args.asset_id)
        ensure_structural_helpers(spec, root, helpers)
        generated = build_structural_recipe(args.asset_id, spec, geometry)
        _parent_generated(root, generated)
        export_collections = {
            role: bpy.data.collections.get(f"Export_{role}")
            for role in ("intact", "damaged", "breached")
            if bpy.data.collections.get(f"Export_{role}") is not None
        }
        if "intact" not in export_collections:
            raise RuntimeError(f"missing Export_intact collection for {args.asset_id}")
        generated = _build_export_variants(args.asset_id, root, generated, export_collections)
    else:
        root = None
        helpers = None
        geometry = _ensure_collection(f"FocusedNine_{args.asset_id}_Generated")
        replace_generated_visuals(root, geometry, args.asset_id)
        generated = build_prop_recipe(args.asset_id, geometry)

    report = _report(args.asset_id, kind, source_path, generated, helpers, material_info)
    save_result = bpy.ops.wm.save_as_mainfile(filepath=str(source_path))
    if "FINISHED" not in save_result:
        raise RuntimeError(f"Blender could not save source blend: {source_path}")
    return report


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entrypoint; validation errors are reported without Blender import."""

    args = parse_args(argv)
    if not args.overwrite_generated_only:
        print("ERROR: --overwrite-generated-only is required for the safe generated-only driver", file=sys.stderr)
        return 2
    try:
        report = _run(args)
    except (FileNotFoundError, RuntimeError, ValueError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print("FOCUSED_NINE_REPORT " + json.dumps(report, sort_keys=True, separators=(",", ":"), allow_nan=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
