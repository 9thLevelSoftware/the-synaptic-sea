#!/usr/bin/env python3
"""Author additional self-authored derelict dressing props as staged GLBs.

Run with Blender 5.2:
  blender --background --factory-startup --python tools/generate_additional_derelict_props.py -- \
    --output-root assets/_staging/additional_derelict_props_v1

The script authors visual-only meshes. Runtime collision and interaction remain
owned by Godot wrappers/catalog bindings.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Any


ASSET_IDS = (
    "fabrication_station_derelict_v1",
    "medical_stasis_pod_derelict_v1",
    "power_cell_cradle_derelict_v1",
    "salvage_sorter_derelict_v1",
)


def _bpy() -> Any:
    try:
        import bpy  # type: ignore

        return bpy
    except ImportError as exc:  # pragma: no cover - only executed outside Blender
        raise SystemExit("run this recipe with Blender, not system Python") from exc


def _parse_args(argv: list[str]) -> argparse.Namespace:
    if "--" in argv:
        argv = argv[argv.index("--") + 1 :]
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-root", type=Path, required=True)
    return parser.parse_args(argv)


def _finish(result: Any, operation: str) -> None:
    if isinstance(result, set) and "CANCELLED" in result:
        raise RuntimeError(f"Blender operation cancelled: {operation}")


def _material(bpy: Any, name: str, color: tuple[float, float, float, float], metallic: float, roughness: float) -> Any:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    material.use_nodes = True
    node = material.node_tree.nodes.get("Principled BSDF")
    if node is None:
        raise RuntimeError(f"missing Principled BSDF for {name}")
    node.inputs["Base Color"].default_value = color
    node.inputs["Metallic"].default_value = metallic
    node.inputs["Roughness"].default_value = roughness
    if "Emission Color" in node.inputs:
        node.inputs["Emission Color"].default_value = color if name == "ScreenGlow" else (0.0, 0.0, 0.0, 1.0)
        if "Emission Strength" in node.inputs:
            node.inputs["Emission Strength"].default_value = 1.8 if name == "ScreenGlow" else 0.0
    return material


def _apply_bevel(bpy: Any, obj: Any, width: float) -> None:
    if width <= 0.0:
        return
    modifier = obj.modifiers.new(name="PurposefulEdgeBevel", type="BEVEL")
    modifier.width = width
    modifier.segments = 2
    modifier.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    _finish(bpy.ops.object.modifier_apply(modifier=modifier.name), f"apply bevel {obj.name}")


def _box(bpy: Any, name: str, location: tuple[float, float, float], size: tuple[float, float, float], material: Any, bevel: float = 0.0) -> Any:
    _finish(bpy.ops.mesh.primitive_cube_add(size=1.0, location=location), f"add box {name}")
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    _finish(bpy.ops.object.transform_apply(location=False, rotation=False, scale=True), f"apply box {name}")
    obj.data.materials.append(material)
    _apply_bevel(bpy, obj, bevel)
    return obj


def _cylinder(
    bpy: Any,
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: Any,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 16,
) -> Any:
    _finish(
        bpy.ops.mesh.primitive_cylinder_add(
            vertices=vertices,
            radius=radius,
            depth=depth,
            location=location,
            rotation=rotation,
        ),
        f"add cylinder {name}",
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    _apply_bevel(bpy, obj, min(radius * 0.18, 0.008))
    return obj


def _sphere(bpy: Any, name: str, location: tuple[float, float, float], scale: tuple[float, float, float], material: Any) -> Any:
    _finish(bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=location), f"add sphere {name}")
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    _finish(bpy.ops.object.transform_apply(location=False, rotation=False, scale=True), f"apply sphere {name}")
    obj.data.materials.append(material)
    return obj


def _torus(bpy: Any, name: str, location: tuple[float, float, float], major: float, minor: float, material: Any) -> Any:
    _finish(
        bpy.ops.mesh.primitive_torus_add(
            major_radius=major,
            minor_radius=minor,
            major_segments=16,
            minor_segments=6,
            location=location,
        ),
        f"add torus {name}",
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    return obj


def _fabrication_station(bpy: Any, mats: dict[str, Any]) -> list[Any]:
    a, d, x, s, w = mats["alloy"], mats["dark"], mats["accent"], mats["screen"], mats["warning"]
    return [
        _box(bpy, "FabBase", (0.0, 0.0, 0.06), (1.28, 0.72, 0.12), d, 0.025),
        _box(bpy, "FabLeftFrame", (-0.52, 0.0, 0.48), (0.12, 0.62, 0.82), a, 0.018),
        _box(bpy, "FabRightFrame", (0.52, 0.0, 0.48), (0.12, 0.62, 0.82), a, 0.018),
        _box(bpy, "FabWorkSurface", (0.0, -0.01, 0.94), (1.22, 0.72, 0.10), a, 0.018),
        _box(bpy, "FabRearHousing", (0.0, 0.22, 1.40), (1.08, 0.20, 0.78), d, 0.025),
        _box(bpy, "FabScreenFrame", (0.0, 0.095, 1.48), (0.58, 0.025, 0.32), x, 0.008),
        _box(bpy, "FabScreen", (0.0, 0.078, 1.48), (0.46, 0.012, 0.20), s, 0.004),
        _box(bpy, "FabTray", (0.26, -0.37, 1.02), (0.42, 0.16, 0.06), x, 0.008),
        _cylinder(bpy, "FabDial", (-0.34, 0.07, 1.08), 0.065, 0.035, x, (math.radians(90.0), 0.0, 0.0)),
        _box(bpy, "FabWarning", (0.0, -0.38, 0.90), (0.72, 0.018, 0.05), w, 0.004),
    ]


def _medical_stasis_pod(bpy: Any, mats: dict[str, Any]) -> list[Any]:
    a, d, x, s = mats["alloy"], mats["dark"], mats["accent"], mats["screen"]
    return [
        _box(bpy, "PodBase", (0.0, 0.0, 0.08), (1.92, 0.92, 0.16), d, 0.035),
        _box(bpy, "PodBody", (0.0, 0.04, 0.38), (1.72, 0.76, 0.56), a, 0.09),
        _box(bpy, "PodCanopy", (0.0, 0.04, 0.73), (1.48, 0.66, 0.16), s, 0.05),
        _box(bpy, "PodHeadHousing", (-0.66, 0.04, 0.68), (0.28, 0.72, 0.40), d, 0.035),
        _box(bpy, "PodFootHousing", (0.72, 0.04, 0.48), (0.20, 0.70, 0.30), d, 0.025),
        _box(bpy, "PodControlFrame", (-0.55, -0.42, 0.74), (0.42, 0.06, 0.30), x, 0.012),
        _box(bpy, "PodControlScreen", (-0.55, -0.455, 0.76), (0.26, 0.015, 0.16), s, 0.004),
        _cylinder(bpy, "PodStatus", (0.70, -0.39, 0.70), 0.045, 0.035, x, (math.radians(90.0), 0.0, 0.0)),
        _box(bpy, "PodRailLeft", (0.0, -0.40, 0.56), (1.34, 0.06, 0.06), x, 0.012),
        _box(bpy, "PodRailRight", (0.0, 0.40, 0.56), (1.34, 0.06, 0.06), x, 0.012),
    ]


def _power_cell_cradle(bpy: Any, mats: dict[str, Any]) -> list[Any]:
    a, d, x, w = mats["alloy"], mats["dark"], mats["accent"], mats["warning"]
    parts = [
        _box(bpy, "CradleBase", (0.0, 0.0, 0.06), (1.04, 0.66, 0.12), d, 0.02),
        _box(bpy, "CradleBack", (0.0, 0.24, 0.78), (0.94, 0.10, 1.42), a, 0.018),
        _box(bpy, "CradleLeft", (-0.46, 0.0, 0.76), (0.10, 0.60, 1.34), a, 0.016),
        _box(bpy, "CradleRight", (0.46, 0.0, 0.76), (0.10, 0.60, 1.34), a, 0.016),
        _box(bpy, "CradleTop", (0.0, 0.0, 1.42), (0.96, 0.62, 0.10), d, 0.015),
        _box(bpy, "CradleWarning", (0.0, -0.32, 1.15), (0.66, 0.025, 0.06), w, 0.004),
    ]
    for index, x_pos in enumerate((-0.25, 0.0, 0.25), start=1):
        parts.append(_cylinder(bpy, f"PowerCell{index}", (x_pos, 0.0, 0.68), 0.105, 0.95, d, vertices=16))
        parts.append(_torus(bpy, f"PowerCellRing{index}", (x_pos, 0.0, 1.17), 0.105, 0.014, x))
        parts.append(_box(bpy, f"PowerCellStatus{index}", (x_pos, -0.115, 0.72), (0.07, 0.02, 0.12), x, 0.004))
    return parts


def _salvage_sorter(bpy: Any, mats: dict[str, Any]) -> list[Any]:
    a, d, x, w = mats["alloy"], mats["dark"], mats["accent"], mats["warning"]
    return [
        _box(bpy, "SorterBase", (0.0, 0.0, 0.06), (1.34, 0.78, 0.12), d, 0.025),
        _box(bpy, "SorterLeftLeg", (-0.48, 0.0, 0.40), (0.12, 0.62, 0.68), a, 0.015),
        _box(bpy, "SorterRightLeg", (0.48, 0.0, 0.40), (0.12, 0.62, 0.68), a, 0.015),
        _box(bpy, "SorterTable", (0.0, 0.0, 0.80), (1.18, 0.70, 0.10), a, 0.02),
        _box(bpy, "SorterRear", (0.0, 0.25, 1.16), (1.08, 0.12, 0.64), d, 0.022),
        _box(bpy, "SorterScreenFrame", (0.0, 0.17, 1.27), (0.42, 0.03, 0.24), x, 0.008),
        _box(bpy, "SorterScreen", (0.0, 0.145, 1.27), (0.32, 0.014, 0.14), mats["screen"], 0.004),
        _box(bpy, "SorterBinLeft", (-0.33, -0.12, 1.06), (0.42, 0.38, 0.26), x, 0.025),
        _box(bpy, "SorterBinRight", (0.33, -0.12, 1.06), (0.42, 0.38, 0.26), w, 0.025),
        _box(bpy, "SorterLabelLeft", (-0.33, -0.325, 1.07), (0.20, 0.018, 0.08), w, 0.004),
        _box(bpy, "SorterLabelRight", (0.33, -0.325, 1.07), (0.20, 0.018, 0.08), x, 0.004),
        _cylinder(bpy, "SorterDial", (-0.46, -0.08, 1.03), 0.055, 0.035, x, (math.radians(90.0), 0.0, 0.0)),
    ]


def _export(bpy: Any, objects: list[Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    for obj in bpy.context.selected_objects:
        obj.select_set(False)
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    supported = {item.identifier for item in bpy.ops.export_scene.gltf.get_rna_type().properties}
    requested = {
        "filepath": str(output),
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_materials": "EXPORT",
        "export_texcoords": True,
        "export_animations": False,
        "export_yup": False,
        "export_cameras": False,
        "export_lights": False,
    }
    kwargs = {key: value for key, value in requested.items() if key in supported}
    for required in ("filepath", "export_format", "use_selection", "export_apply", "export_materials", "export_texcoords"):
        if required not in kwargs:
            raise RuntimeError(f"Blender GLB exporter lacks required option: {required}")
    _finish(bpy.ops.export_scene.gltf(**kwargs), f"export {output.name}")
    if not output.is_file() or output.stat().st_size <= 20 or output.read_bytes()[:4] != b"glTF":
        raise RuntimeError(f"invalid GLB output: {output}")


def _build_one(bpy: Any, asset_id: str, output: Path) -> None:
    _finish(bpy.ops.wm.read_factory_settings(use_empty=True), "reset scene")
    mats = {
        "alloy": _material(bpy, "PaintedAlloy", (0.28, 0.34, 0.38, 1.0), 0.55, 0.45),
        "dark": _material(bpy, "DarkMachinery", (0.055, 0.075, 0.09, 1.0), 0.75, 0.48),
        "accent": _material(bpy, "SafetyAccent", (0.72, 0.30, 0.055, 1.0), 0.35, 0.42),
        "warning": _material(bpy, "WarningStripe", (0.92, 0.64, 0.08, 1.0), 0.25, 0.38),
        "screen": _material(bpy, "ScreenGlow", (0.08, 0.52, 0.58, 1.0), 0.15, 0.22),
    }
    builders = {
        "fabrication_station_derelict_v1": _fabrication_station,
        "medical_stasis_pod_derelict_v1": _medical_stasis_pod,
        "power_cell_cradle_derelict_v1": _power_cell_cradle,
        "salvage_sorter_derelict_v1": _salvage_sorter,
    }
    objects = builders[asset_id](bpy, mats)
    if not objects or any(obj.type != "MESH" for obj in objects):
        raise RuntimeError(f"{asset_id}: recipe emitted no mesh-only visual set")
    _export(bpy, objects, output)
    print(f"ADDITIONAL_PROP_EXPORTED asset_id={asset_id} path={output} bytes={output.stat().st_size}")


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(sys.argv if argv is None else argv)
    bpy = _bpy()
    args.output_root.mkdir(parents=True, exist_ok=True)
    for asset_id in ASSET_IDS:
        _build_one(bpy, asset_id, args.output_root / f"{asset_id}.glb")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
