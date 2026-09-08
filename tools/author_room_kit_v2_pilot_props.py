"""Author the three room-kit-v2 pilot prop Blender masters and neutral renders.

Run with Blender in an isolated process:
    blender --background --factory-startup --python tools/author_room_kit_v2_pilot_props.py -- \
      --source-root /Volumes/.../meshes/source/room_kit_v2 \
      --artifact-root artifacts/room_kit_v2/pilot-props

This script deliberately authors only the three pilot masters. Runtime GLB export is
owned by tools/export_static_room_prop.py; Export_Static contains baked-source copies
for that exporter and is never used as a second publishing path here.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import sys
from pathlib import Path
from typing import Iterable

import bpy
from mathutils import Vector


ASSET_SPECS = {
    "fabrication_station_derelict_v1": {
        "max_size_m": [1.8, 1.85, 1.1],
        "triangles_max": 5000,
        "assemblies": [
            "open C-frame uprights and rear service base",
            "broad worktop with empty knee bay",
            "rear tool rail with three hanging tool silhouettes",
            "off-center bench vise",
            "recessed display off",
            "connected rear cable and service box",
        ],
    },
    "coolant_pump_skid_derelict_v1": {
        "max_size_m": [1.8, 1.2, 1.1],
        "triangles_max": 4500,
        "assemblies": [
            "low open skid rails and cross members",
            "horizontal pump body",
            "finned motor",
            "elbow return pipe into reservoir",
            "removable perforated guard",
            "service fittings and restrained warning marks",
        ],
    },
    "suit_service_stand_derelict_v1": {
        "max_size_m": [1.3, 1.9, 1.0],
        "triangles_max": 3500,
        "assemblies": [
            "empty human-proportioned hanger yoke",
            "vertical back rail and base",
            "paired boot rests",
            "connected hose loop with end fittings",
            "offset equipment tray",
            "restrained maintenance warning detail",
        ],
    },
}

LIBRARY_PATH = Path("/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/salvage_industrial.blend")
MATERIAL_NAMES = [
    "MAT_PaintedAlloyGray",
    "MAT_Conduit",
    "MAT_WarningStripe",
    "MAT_RoomKitDisplayOff",
]
FALLBACK_RGB = {
    "MAT_PaintedAlloyGray": (0x62 / 255.0, 0x68 / 255.0, 0x6A / 255.0),
    "MAT_Conduit": (0x20 / 255.0, 0x2A / 255.0, 0x2D / 255.0),
    "MAT_WarningStripe": (0xB3 / 255.0, 0x91 / 255.0, 0x40 / 255.0),
    "MAT_RoomKitDisplayOff": (0.035, 0.075, 0.085),
}
FALLBACK_METALLIC = {
    "MAT_PaintedAlloyGray": 0.0,
    "MAT_Conduit": 0.0,
    "MAT_WarningStripe": 0.0,
    "MAT_RoomKitDisplayOff": 0.0,
}
FALLBACK_ROUGHNESS = {
    "MAT_PaintedAlloyGray": 0.65,
    "MAT_Conduit": 0.83,
    "MAT_WarningStripe": 0.72,
    "MAT_RoomKitDisplayOff": 0.28,
}


# Blender receives Principled values in scene-linear space for explicit values.
def srgb_to_linear(channel: float) -> float:
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    if "--" not in sys.argv:
        raise SystemExit("Blender arguments must follow --")
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--artifact-root", type=Path, required=True)
    parser.add_argument("--asset", choices=tuple(ASSET_SPECS), action="append")
    parser.add_argument("--no-render", action="store_true")
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("RoomKitNeutralWorld")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs["Color"].default_value = (0.035, 0.045, 0.05, 1.0)
        background.inputs["Strength"].default_value = 0.12


def ensure_collection(name: str, parent: bpy.types.Collection | None = None) -> bpy.types.Collection:
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
    if parent is None:
        if collection.name not in bpy.context.scene.collection.children:
            bpy.context.scene.collection.children.link(collection)
    elif collection.name not in parent.children:
        parent.children.link(collection)
    return collection


def clear_collection(collection: bpy.types.Collection) -> None:
    for obj in list(collection.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for child in list(collection.children):
        collection.children.unlink(child)


def material_from_library_or_fallback(name: str) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing

    if LIBRARY_PATH.is_file():
        with bpy.data.libraries.load(str(LIBRARY_PATH), link=False) as (data_from, data_to):
            if name in data_from.materials:
                data_to.materials = [name]
        loaded = bpy.data.materials.get(name)
        if loaded is not None:
            return loaded

    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.inputs["Base Color"].default_value = tuple(
        srgb_to_linear(c) for c in FALLBACK_RGB[name]
    ) + (1.0,)
    principled.inputs["Metallic"].default_value = FALLBACK_METALLIC[name]
    principled.inputs["Roughness"].default_value = FALLBACK_ROUGHNESS[name]
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    material.diffuse_color = tuple(FALLBACK_RGB[name]) + (1.0,)
    return material


def load_materials() -> dict[str, bpy.types.Material]:
    return {name: material_from_library_or_fallback(name) for name in MATERIAL_NAMES}


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    if obj.type != "MESH":
        return
    obj.data.materials.clear()
    obj.data.materials.append(material)


def add_bevel(obj: bpy.types.Object, width: float = 0.015) -> None:
    if obj.type != "MESH" or width <= 0.0:
        return
    modifier = obj.modifiers.new(name="EdgeBevel_2seg", type="BEVEL")
    modifier.width = min(width, 0.03)
    modifier.segments = 2
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(25.0)


def link_to(collection: bpy.types.Collection, obj: bpy.types.Object) -> None:
    if obj.name not in collection.objects:
        collection.objects.link(obj)


def add_box(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    size: tuple[float, float, float],
    material: bpy.types.Material,
    bevel: float = 0.012,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    add_bevel(obj, bevel)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    link_to(collection, obj)
    return obj


def add_cylinder(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    material: bpy.types.Material,
    axis: str = "Z",
    sides: int = 16,
    bevel: float = 0.0,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=sides, radius=radius, depth=depth, location=location)
    obj = bpy.context.object
    obj.name = name
    if axis == "X":
        obj.rotation_euler[1] = math.radians(90.0)
    elif axis == "Y":
        obj.rotation_euler[0] = math.radians(90.0)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    assign_material(obj, material)
    add_bevel(obj, bevel)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    link_to(collection, obj)
    return obj


def add_sphere(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    radius: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=4, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    link_to(collection, obj)
    return obj


def add_torus(
    collection: bpy.types.Collection,
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    material: bpy.types.Material,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_segments=16,
        minor_segments=8,
        location=location,
        major_radius=major_radius,
        minor_radius=minor_radius,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    link_to(collection, obj)
    return obj


def add_pipe_path(
    collection: bpy.types.Collection,
    prefix: str,
    points: Iterable[tuple[float, float, float]],
    radius: float,
    material: bpy.types.Material,
    fitting_material: bpy.types.Material | None = None,
) -> list[bpy.types.Object]:
    points = [Vector(p) for p in points]
    result: list[bpy.types.Object] = []
    fitting_material = fitting_material or material
    for index, (start, end) in enumerate(zip(points, points[1:])):
        delta = end - start
        length = delta.length
        if length <= 1e-5:
            continue
        mid = (start + end) * 0.5
        obj = add_cylinder(
            collection,
            f"{prefix}__segment_{index:02d}",
            tuple(mid),
            radius,
            length,
            material,
            axis="Z",
            sides=16,
            bevel=0.0,
        )
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(delta.normalized())
        result.append(obj)
    for index, point in enumerate(points):
        result.append(add_sphere(collection, f"{prefix}__fitting_{index:02d}", tuple(point), radius * 1.35, fitting_material))
    return result


def add_label_panel(
    collection: bpy.types.Collection,
    prefix: str,
    location: tuple[float, float, float],
    size: tuple[float, float, float],
    alloy: bpy.types.Material,
    display: bpy.types.Material,
    warning: bpy.types.Material,
) -> None:
    add_box(collection, f"{prefix}__frame", location, size, alloy, bevel=0.008)
    inner = (size[0] * 0.72, size[1] * 0.08, size[2] * 0.62)
    inset = (location[0], location[1] - size[1] * 0.52, location[2])
    add_box(collection, f"{prefix}__display_recess_off", inset, inner, display, bevel=0.004)
    stripe = (size[0] * 0.20, size[1] * 0.09, size[2] * 0.06)
    stripe_loc = (location[0] - size[0] * 0.26, location[1] - size[1] * 0.53, location[2] + size[2] * 0.32)
    add_box(collection, f"{prefix}__warning_label", stripe_loc, stripe, warning, bevel=0.002)


def add_bolt_set(
    collection: bpy.types.Collection,
    prefix: str,
    positions: Iterable[tuple[float, float, float]],
    material: bpy.types.Material,
) -> None:
    for index, position in enumerate(positions):
        add_cylinder(collection, f"{prefix}__bolt_{index:02d}", position, 0.018, 0.012, material, sides=12, bevel=0.002)


def smart_uv(objects: Iterable[bpy.types.Object]) -> None:
    for obj in objects:
        if obj.type != "MESH" or obj.data is None:
            continue
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        try:
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(angle_limit=math.radians(66.0), island_margin=0.03)
            bpy.ops.object.mode_set(mode="OBJECT")
        except RuntimeError:
            if bpy.context.object and bpy.context.object.mode != "OBJECT":
                bpy.ops.object.mode_set(mode="OBJECT")
        finally:
            obj.select_set(False)


def make_export_copies(geometry: bpy.types.Collection, export: bpy.types.Collection) -> None:
    """Expose the editable Geometry objects in Export_Static without hidden clones.

    Hidden clone objects can be evaluated with identity matrices by Blender's depsgraph,
    which would drop assembly translations during export. A single object linked to both
    collections preserves editable subassemblies and gives the static exporter the real
    world transforms while still exporting only the tagged collection.
    """
    clear_collection(export)
    for source in list(geometry.objects):
        if source.type == "MESH":
            link_to(export, source)


def add_authoring_helpers(
    helpers: bpy.types.Collection,
    asset_id: str,
    max_size: tuple[float, float, float],
) -> None:
    empty = bpy.data.objects.new("AuthoringFront", None)
    empty.empty_display_type = "ARROWS"
    empty.empty_display_size = 0.18
    empty.location = (0.0, -1.0, 0.0)
    helpers.objects.link(empty)

    # A source-only floor outline and envelope wire frame. These never enter Export_Static.
    floor_outline = add_box(helpers, f"{asset_id}__helper_floor_outline", (0, 0, 0.006), (max_size[0], max_size[2], 0.012), bpy.data.materials.get("MAT_Conduit"), bevel=0.0)
    floor_outline.hide_render = True
    x, y, z = max_size[0] * 0.5, max_size[2] * 0.5, max_size[1] * 0.5
    wire = add_box(helpers, f"{asset_id}__helper_envelope", (0, 0, z), (max_size[0], max_size[2], max_size[1]), bpy.data.materials.get("MAT_Conduit"), bevel=0.0)
    wire.display_type = "WIRE"
    wire.hide_render = True


def add_render_setup(
    helpers: bpy.types.Collection,
    max_size: tuple[float, float, float],
    materials: dict[str, bpy.types.Material],
) -> tuple[bpy.types.Object, bpy.types.Object, bpy.types.Object, bpy.types.Object]:
    # Floor is in helper collection and is not part of Export_Static.
    floor = add_box(helpers, "RenderFloor", (0.0, 0.0, -0.022), (6.0, 6.0, 0.04), materials["MAT_Conduit"], bevel=0.0)
    floor.hide_render = False
    bpy.ops.object.camera_add(location=(0.0, -4.0, max_size[1] * 0.52))
    camera = bpy.context.object
    camera.name = "RenderCamera"
    camera.data.type = "ORTHO"
    aspect = bpy.context.scene.render.resolution_x / bpy.context.scene.render.resolution_y
    # Blender's ortho_scale is the horizontal span; include vertical extent times aspect.
    camera.data.ortho_scale = max(max_size[0], max_size[1] * aspect, max_size[2]) * 1.15
    helpers.objects.link(camera)
    for old in list(camera.users_collection):
        if old != helpers:
            old.objects.unlink(camera)

    def make_light(name: str, location: tuple[float, float, float], energy: float, size: float):
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.shape = "DISK"
        light.data.size = size
        helpers.objects.link(light)
        for old in list(light.users_collection):
            if old != helpers:
                old.objects.unlink(light)
        return light

    key = make_light("KeyLight", (-3.0, -4.0, 4.5), 320.0, 4.0)
    fill = make_light("FillLight", (3.0, -1.0, 2.4), 160.0, 3.0)
    rim = make_light("RimLight", (0.0, 3.0, 4.0), 240.0, 3.0)
    underside = make_light("UndersideFill", (0.0, -1.5, -2.0), 420.0, 3.5)
    underside.rotation_euler = (Vector((0.0, 0.0, max_size[1] * 0.5)) - underside.location).to_track_quat("-Z", "Y").to_euler()
    underside.hide_render = True
    return camera, key, fill, rim


def point_camera(camera: bpy.types.Object, direction: Vector, target: Vector) -> None:
    camera.location = target + direction.normalized() * 5.0
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def bounds_for_collection(collection: bpy.types.Collection) -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    first = True
    lo = Vector((0.0, 0.0, 0.0))
    hi = Vector((0.0, 0.0, 0.0))
    for obj in collection.objects:
        if obj.type != "MESH":
            continue
        eval_obj = obj.evaluated_get(depsgraph)
        corners = [eval_obj.matrix_world @ Vector(corner) for corner in eval_obj.bound_box]
        for corner in corners:
            if first:
                lo = corner.copy()
                hi = corner.copy()
                first = False
            else:
                lo.x = min(lo.x, corner.x)
                lo.y = min(lo.y, corner.y)
                lo.z = min(lo.z, corner.z)
                hi.x = max(hi.x, corner.x)
                hi.y = max(hi.y, corner.y)
                hi.z = max(hi.z, corner.z)
    if first:
        raise RuntimeError(f"no geometry in {collection.name}")
    return lo, hi


def normalize_floor_center(collection: bpy.types.Collection) -> None:
    """Center the assembled footprint on Blender X/Y before Y-up export."""
    bpy.context.view_layer.update()
    lo, hi = bounds_for_collection(collection)
    offset = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, 0.0))
    for obj in collection.objects:
        obj.location.x -= offset.x
        obj.location.y -= offset.y
    bpy.context.view_layer.update()


def orient_and_render(
    asset_id: str,
    geometry: bpy.types.Collection,
    camera: bpy.types.Object,
    floor: bpy.types.Object,
    output_dir: Path,
    max_size: tuple[float, float, float],
    alloy: bpy.types.Material,
) -> None:
    scene = bpy.context.scene
    scene.camera = camera
    underside_fill = bpy.data.objects.get("UndersideFill")
    target = Vector((0.0, 0.0, max_size[1] * 0.50))
    directions = {
        "front": Vector((0.0, -1.0, 0.0)),
        "back": Vector((0.0, 1.0, 0.0)),
        "left": Vector((-1.0, 0.0, 0.0)),
        "right": Vector((1.0, 0.0, 0.0)),
        "top": Vector((0.0, 0.0, 1.0)),
        "underside": Vector((0.0, 0.0, -1.0)),
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    normal_materials: dict[bpy.types.Object, list[bpy.types.Material]] = {}
    for obj in geometry.objects:
        if obj.type == "MESH":
            normal_materials[obj] = list(obj.data.materials)
    clay = bpy.data.materials.get("RenderClayNeutral") or bpy.data.materials.new("RenderClayNeutral")
    clay.use_nodes = True
    principled = clay.node_tree.nodes.get("Principled BSDF")
    if principled:
        principled.inputs["Base Color"].default_value = (0.34, 0.37, 0.39, 1.0)
        principled.inputs["Metallic"].default_value = 0.0
        principled.inputs["Roughness"].default_value = 0.76
    clay.diffuse_color = (0.34, 0.37, 0.39, 1.0)

    for view_name, direction in directions.items():
        point_camera(camera, direction, target)
        floor.hide_render = view_name == "underside"
        if underside_fill is not None:
            underside_fill.hide_render = view_name != "underside"
        scene.render.filepath = str(output_dir / f"{view_name}_normal.png")
        for obj, mats in normal_materials.items():
            obj.data.materials.clear()
            for mat in mats:
                obj.data.materials.append(mat)
        bpy.ops.render.render(write_still=True)
        scene.render.filepath = str(output_dir / f"{view_name}_clay.png")
        for obj in geometry.objects:
            if obj.type == "MESH":
                obj.data.materials.clear()
                obj.data.materials.append(clay)
        bpy.ops.render.render(write_still=True)
    for obj, mats in normal_materials.items():
        obj.data.materials.clear()
        for mat in mats:
            obj.data.materials.append(mat)
    floor.hide_render = False
    if underside_fill is not None:
        underside_fill.hide_render = True


def add_fabrication_station(
    geometry: bpy.types.Collection,
    materials: dict[str, bpy.types.Material],
    asset_id: str,
) -> None:
    alloy = materials["MAT_PaintedAlloyGray"]
    conduit = materials["MAT_Conduit"]
    warning = materials["MAT_WarningStripe"]
    display = materials["MAT_RoomKitDisplayOff"]
    # C-frame kept visibly open at the front; rear lies toward +Y.
    add_box(geometry, f"{asset_id}__left_upright", (-0.77, 0.16, 0.91), (0.16, 0.80, 1.82), alloy)
    add_box(geometry, f"{asset_id}__right_upright", (0.77, 0.16, 0.91), (0.16, 0.80, 1.82), alloy)
    add_box(geometry, f"{asset_id}__worktop", (0.0, 0.00, 1.22), (1.56, 0.82, 0.13), alloy, bevel=0.02)
    add_box(geometry, f"{asset_id}__rear_lower_rail", (0.0, 0.43, 0.34), (1.46, 0.13, 0.18), alloy)
    add_box(geometry, f"{asset_id}__rear_upper_rail", (0.0, 0.43, 1.58), (1.47, 0.13, 0.15), alloy)
    add_box(geometry, f"{asset_id}__rear_service_panel", (0.0, 0.38, 0.82), (1.30, 0.08, 0.72), conduit, bevel=0.01)
    add_label_panel(geometry, f"{asset_id}__display", (-0.28, 0.325, 1.02), (0.40, 0.055, 0.24), alloy, display, warning)

    # Rear tool rail and three readable silhouettes.
    add_cylinder(geometry, f"{asset_id}__tool_rail", (0.0, 0.31, 1.48), 0.026, 1.22, conduit, axis="X", sides=16)
    add_box(geometry, f"{asset_id}__tool_wrench_handle", (-0.44, 0.25, 1.25), (0.055, 0.055, 0.34), alloy, bevel=0.006)
    add_box(geometry, f"{asset_id}__tool_wrench_head", (-0.44, 0.25, 1.46), (0.16, 0.055, 0.08), alloy, bevel=0.012)
    add_box(geometry, f"{asset_id}__tool_spanner_handle", (0.02, 0.25, 1.27), (0.05, 0.05, 0.38), alloy, bevel=0.006)
    add_box(geometry, f"{asset_id}__tool_spanner_head", (0.02, 0.25, 1.49), (0.13, 0.05, 0.06), alloy, bevel=0.01)
    add_box(geometry, f"{asset_id}__tool_driver_handle", (0.42, 0.25, 1.30), (0.07, 0.07, 0.25), conduit, bevel=0.008)
    add_box(geometry, f"{asset_id}__tool_driver_tip", (0.42, 0.25, 1.48), (0.04, 0.04, 0.12), alloy, bevel=0.004)

    # Off-center vise on the front-right of the worktop.
    add_box(geometry, f"{asset_id}__vise_base", (0.42, -0.30, 1.34), (0.34, 0.24, 0.08), conduit, bevel=0.012)
    add_box(geometry, f"{asset_id}__vise_body", (0.42, -0.26, 1.45), (0.25, 0.22, 0.16), alloy, bevel=0.015)
    add_box(geometry, f"{asset_id}__vise_fixed_jaw", (0.32, -0.39, 1.55), (0.08, 0.06, 0.16), alloy, bevel=0.008)
    add_box(geometry, f"{asset_id}__vise_moving_jaw", (0.52, -0.39, 1.55), (0.08, 0.06, 0.16), alloy, bevel=0.008)
    add_cylinder(geometry, f"{asset_id}__vise_screw", (0.42, -0.36, 1.46), 0.018, 0.16, conduit, axis="Y", sides=16)

    # Connected rear cable to a visible service box.
    add_box(geometry, f"{asset_id}__rear_service_box", (0.54, 0.48, 0.75), (0.24, 0.12, 0.30), conduit, bevel=0.008)
    add_pipe_path(geometry, f"{asset_id}__rear_cable", [(0.67, 0.29, 1.44), (0.67, 0.49, 1.44), (0.67, 0.49, 0.88), (0.54, 0.49, 0.88)], 0.028, conduit)
    add_bolt_set(geometry, f"{asset_id}__joint_fasteners", [(-0.69, -0.27, 1.28), (0.69, -0.27, 1.28), (-0.69, 0.43, 0.33), (0.69, 0.43, 0.33)], alloy)
    add_box(geometry, f"{asset_id}__warning_toe_strip", (0.0, -0.405, 0.12), (0.70, 0.035, 0.055), warning, bevel=0.004)


def add_coolant_pump_skid(
    geometry: bpy.types.Collection,
    materials: dict[str, bpy.types.Material],
    asset_id: str,
) -> None:
    alloy = materials["MAT_PaintedAlloyGray"]
    conduit = materials["MAT_Conduit"]
    warning = materials["MAT_WarningStripe"]
    # Low open skid: no enclosing cabinet.
    add_box(geometry, f"{asset_id}__left_runner", (-0.69, 0.0, 0.08), (0.14, 0.88, 0.16), alloy, bevel=0.015)
    add_box(geometry, f"{asset_id}__right_runner", (0.69, 0.0, 0.08), (0.14, 0.88, 0.16), alloy, bevel=0.015)
    for index, y in enumerate((-0.34, 0.34)):
        add_box(geometry, f"{asset_id}__cross_member_{index}", (0.0, y, 0.13), (1.46, 0.11, 0.13), alloy)
    add_box(geometry, f"{asset_id}__drip_pan", (0.0, 0.08, 0.22), (1.35, 0.67, 0.06), conduit, bevel=0.012)

    # Horizontal pump and distinct finned motor along X.
    add_cylinder(geometry, f"{asset_id}__pump_body", (-0.22, -0.02, 0.55), 0.23, 0.58, alloy, axis="X", sides=24)
    add_cylinder(geometry, f"{asset_id}__pump_front_flange", (-0.53, -0.02, 0.55), 0.29, 0.07, alloy, axis="X", sides=24)
    add_cylinder(geometry, f"{asset_id}__pump_hub", (-0.58, -0.02, 0.55), 0.12, 0.10, conduit, axis="X", sides=16)
    add_cylinder(geometry, f"{asset_id}__motor_core", (0.47, -0.02, 0.55), 0.24, 0.48, conduit, axis="X", sides=20)
    for index, x in enumerate((0.28, 0.38, 0.48, 0.58, 0.68)):
        add_cylinder(geometry, f"{asset_id}__motor_fin_{index}", (x, -0.02, 0.55), 0.285, 0.035, alloy, axis="X", sides=20)
    add_box(geometry, f"{asset_id}__motor_terminal_box", (0.50, -0.02, 0.86), (0.22, 0.18, 0.12), alloy, bevel=0.008)

    # Reservoir and connected elbow return path.
    add_cylinder(geometry, f"{asset_id}__reservoir", (-0.52, 0.28, 0.45), 0.20, 0.42, alloy, axis="Z", sides=20)
    add_cylinder(geometry, f"{asset_id}__reservoir_cap", (-0.52, 0.28, 0.68), 0.10, 0.04, conduit, sides=16)
    add_pipe_path(geometry, f"{asset_id}__elbow_return", [(0.05, 0.20, 0.72), (0.05, 0.37, 0.72), (-0.29, 0.37, 0.72), (-0.29, 0.28, 0.66)], 0.045, conduit, alloy)
    add_cylinder(geometry, f"{asset_id}__pump_suction_fitting", (-0.53, 0.10, 0.55), 0.065, 0.20, conduit, axis="Y", sides=16)

    # Removable perforated guard in the front half: frame plus four clear apertures.
    y = -0.43
    add_box(geometry, f"{asset_id}__guard_top", (0.30, y, 0.94), (0.83, 0.055, 0.07), alloy, bevel=0.008)
    add_box(geometry, f"{asset_id}__guard_bottom", (0.30, y, 0.25), (0.83, 0.055, 0.07), alloy, bevel=0.008)
    add_box(geometry, f"{asset_id}__guard_left", (-0.10, y, 0.59), (0.07, 0.055, 0.73), alloy, bevel=0.008)
    add_box(geometry, f"{asset_id}__guard_right", (0.70, y, 0.59), (0.07, 0.055, 0.73), alloy, bevel=0.008)
    for index, x in enumerate((0.08, 0.26, 0.44, 0.62)):
        add_cylinder(geometry, f"{asset_id}__guard_perforation_bar_{index}", (x, y - 0.01, 0.59), 0.018, 0.62, conduit, axis="Z", sides=12)
    add_box(geometry, f"{asset_id}__guard_warning_mark", (0.66, y - 0.035, 0.80), (0.12, 0.02, 0.06), warning, bevel=0.002)
    add_bolt_set(geometry, f"{asset_id}__mount_fasteners", [(-0.69, -0.36, 0.18), (0.69, -0.36, 0.18), (-0.69, 0.36, 0.18), (0.69, 0.36, 0.18)], alloy)


def add_suit_service_stand(
    geometry: bpy.types.Collection,
    materials: dict[str, bpy.types.Material],
    asset_id: str,
) -> None:
    alloy = materials["MAT_PaintedAlloyGray"]
    conduit = materials["MAT_Conduit"]
    warning = materials["MAT_WarningStripe"]
    # Compact floor base and vertical rail. Empty center is deliberate.
    add_box(geometry, f"{asset_id}__base_foot", (0.0, 0.18, 0.07), (0.98, 0.34, 0.14), alloy, bevel=0.018)
    add_box(geometry, f"{asset_id}__back_rail", (0.0, 0.31, 0.98), (0.13, 0.13, 1.78), alloy, bevel=0.015)
    add_box(geometry, f"{asset_id}__rail_backplate", (0.0, 0.37, 1.10), (0.48, 0.08, 1.36), conduit, bevel=0.012)

    # Angular hanger yoke / shoulders, no suit or human mesh.
    add_box(geometry, f"{asset_id}__yoke_left", (-0.27, 0.08, 1.60), (0.48, 0.12, 0.11), alloy, bevel=0.014)
    left_arm = add_box(geometry, f"{asset_id}__yoke_left_drop", (-0.46, 0.08, 1.49), (0.11, 0.12, 0.26), alloy, bevel=0.012)
    left_arm.rotation_euler[1] = math.radians(-18.0)
    right_arm = add_box(geometry, f"{asset_id}__yoke_right_drop", (0.46, 0.08, 1.49), (0.11, 0.12, 0.26), alloy, bevel=0.012)
    right_arm.rotation_euler[1] = math.radians(18.0)
    add_box(geometry, f"{asset_id}__yoke_crossbar", (0.0, 0.08, 1.73), (0.83, 0.12, 0.10), alloy, bevel=0.012)
    add_box(geometry, f"{asset_id}__neck_hook", (0.0, -0.01, 1.79), (0.16, 0.11, 0.10), conduit, bevel=0.008)

    # Boot rests at human lower-leg spacing; each has an end lip.
    for index, x in enumerate((-0.28, 0.28)):
        add_box(geometry, f"{asset_id}__boot_rest_{index}", (x, -0.07, 0.18), (0.25, 0.40, 0.08), alloy, bevel=0.012)
        add_box(geometry, f"{asset_id}__boot_lip_{index}", (x, -0.27, 0.26), (0.25, 0.07, 0.15), alloy, bevel=0.008)
    add_box(geometry, f"{asset_id}__boot_warning_strip", (0.0, -0.29, 0.13), (0.72, 0.025, 0.04), warning, bevel=0.002)

    # Offset service tray to the right, deliberately outside the hanger opening.
    add_box(geometry, f"{asset_id}__equipment_tray_arm", (0.43, 0.06, 0.93), (0.28, 0.09, 0.09), alloy, bevel=0.01)
    add_box(geometry, f"{asset_id}__equipment_tray", (0.48, -0.17, 0.83), (0.42, 0.34, 0.09), alloy, bevel=0.015)
    add_box(geometry, f"{asset_id}__equipment_tray_cavity", (0.48, -0.17, 0.89), (0.30, 0.20, 0.025), conduit, bevel=0.004)
    add_box(geometry, f"{asset_id}__tray_label", (0.65, -0.355, 0.84), (0.08, 0.018, 0.045), warning, bevel=0.002)

    # Connected hose loop: both fittings terminate on rail and tray.
    add_pipe_path(
        geometry,
        f"{asset_id}__service_hose",
        [(0.20, -0.02, 1.22), (0.62, -0.05, 1.22), (0.68, -0.30, 1.03), (0.63, -0.30, 0.94), (0.57, -0.24, 0.90)],
        0.032,
        conduit,
        alloy,
    )
    add_bolt_set(geometry, f"{asset_id}__rail_fasteners", [(-0.20, 0.23, 0.92), (0.20, 0.23, 0.92)], alloy)


def build_asset(asset_id: str, source_root: Path, artifact_root: Path, do_render: bool) -> dict:
    spec = ASSET_SPECS[asset_id]
    reset_scene()
    materials = load_materials()
    geometry = ensure_collection("Geometry")
    helpers = ensure_collection("AuthoringHelpers")
    export = ensure_collection("Export_Static")
    clear_collection(geometry)
    clear_collection(helpers)
    clear_collection(export)

    max_w, max_h, max_d = spec["max_size_m"]
    if asset_id.startswith("fabrication"):
        add_fabrication_station(geometry, materials, asset_id)
    elif asset_id.startswith("coolant"):
        add_coolant_pump_skid(geometry, materials, asset_id)
    elif asset_id.startswith("suit_service"):
        add_suit_service_stand(geometry, materials, asset_id)
    else:
        raise ValueError(asset_id)

    normalize_floor_center(geometry)
    smart_uv(list(geometry.objects))
    add_authoring_helpers(helpers, asset_id, (max_w, max_h, max_d))
    camera, _key, _fill, _rim = add_render_setup(helpers, (max_w, max_h, max_d), materials)
    make_export_copies(geometry, export)
    source_lo, source_hi = bounds_for_collection(geometry)
    measured = source_hi - source_lo
    if source_lo.z < -0.003 or source_hi.z > max_h + 0.02:
        raise RuntimeError(f"{asset_id} source floor/envelope mismatch: {source_lo} {source_hi}")
    if measured.x > max_w + 0.02 or measured.y > max_d + 0.02:
        raise RuntimeError(f"{asset_id} source footprint/envelope mismatch: {measured}")

    source_dir = source_root / "props" / asset_id
    source_dir.mkdir(parents=True, exist_ok=True)
    blend_path = source_dir / f"{asset_id}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    render_dir = artifact_root / asset_id / "renders"
    if do_render:
        orient_and_render(asset_id, geometry, camera, bpy.data.objects["RenderFloor"], render_dir, (max_w, max_h, max_d), materials["MAT_PaintedAlloyGray"])

    script_path = Path(__file__).resolve()
    inputs = {
        "material_library": {
            "path": str(LIBRARY_PATH),
            "sha256": sha256_file(LIBRARY_PATH) if LIBRARY_PATH.is_file() else None,
            "requested_materials": MATERIAL_NAMES,
        },
        "authoring_script": {"path": str(script_path), "sha256": sha256_file(script_path)},
    }
    receipt = {
        "schema_version": "1.0.0",
        "asset_id": asset_id,
        "source_master": str(blend_path),
        "source_input_hashes": inputs,
        "intended_dimensions_m": {"width": max_w, "height": max_h, "depth": max_d},
        "measured_source_bounds_blender_m": {
            "min": [round(v, 6) for v in source_lo],
            "max": [round(v, 6) for v in source_hi],
            "size": [round(v, 6) for v in measured],
            "coordinate_note": "Blender X width, Y depth (-Y front), Z height (+Z up)",
        },
        "triangle_budget_max": spec["triangles_max"],
        "materials": MATERIAL_NAMES,
        "assembly_list": spec["assemblies"],
        "collections": {
            "geometry": "Geometry",
            "authoring_helpers": "AuthoringHelpers",
            "export_static": "Export_Static",
            "export_static_policy": "mesh-only editable Geometry objects linked into Export_Static; exporter bakes transforms and excludes helpers",
        },
        "front_marker": {"name": "AuthoringFront", "location_blender": [0.0, -1.0, 0.0]},
        "render_outputs": [str(path) for path in sorted(render_dir.glob("*.png"))] if do_render else [],
        "export_results": {"status": "awaiting_export_static_room_prop.py", "staged_glb": None},
        "review_notes": [
            "Pilot only; no bulk expansion authorized in this run.",
            "Static visual-only dressing; no collision or gameplay semantics exported.",
        ],
    }
    receipt_path = source_dir / "authoring.json"
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n")
    return {"asset_id": asset_id, "blend": str(blend_path), "authoring": str(receipt_path), "renders": len(receipt["render_outputs"]), "size": [round(v, 6) for v in measured]}


def main() -> None:
    args = parse_args()
    source_root = args.source_root.resolve()
    artifact_root = args.artifact_root.resolve()
    source_root.mkdir(parents=True, exist_ok=True)
    artifact_root.mkdir(parents=True, exist_ok=True)
    assets = args.asset or list(ASSET_SPECS)
    results = []
    for asset_id in assets:
        results.append(build_asset(asset_id, source_root, artifact_root, not args.no_render))
    print("ROOM_KIT_V2_PILOT_AUTHOR_PASS " + json.dumps({"assets": results}, sort_keys=True))


if __name__ == "__main__":
    main()
