"""Render structural kit modules as isometric beauty, depth, and normal tiles.

This script intentionally avoids Blender compositor nodes. Blender 5.2 does not
expose the scene compositor node tree through the context API, so the non-beauty
passes are produced with temporary material assignments instead.

Usage::

    blender --background --python tools/render_module_passes.py -- --module floor_1x1
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import sys
from typing import Iterable, Sequence

import bpy
from mathutils import Vector


MODULE_IDS = (
    "floor_1x1",
    "floor_2x1",
    "corridor_floor_1x1",
    "corridor_floor_1x2",
    "wall_straight_1x1",
    "wall_end_cap",
    "wall_inner_corner",
    "wall_outer_corner",
    "wall_t_junction",
    "doorway_frame_open_1x1",
    "doorway_frame_blocked_1x1",
    "bulkhead_portal_2x1",
    "ceiling_cap_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
)

RENDER_SIZE = 1024
OUTPUT_DIR = Path("/tmp/tile_renders")

# The material colors are deliberately kept as constants so the tile appearance
# can be tuned without changing the scene/camera setup.
BEAUTY_BASE_COLOR = (0.15, 0.15, 0.18, 1.0)
DEPTH_BASE_COLOR = (1.0, 1.0, 1.0, 1.0)
DARK_WORLD_COLOR = (0.02, 0.03, 0.05, 1.0)


def parse_module_id(argv: Sequence[str]) -> str:
    """Parse the module argument from the portion of argv after ``--``."""

    blender_args = list(argv)
    if "--" in blender_args:
        blender_args = blender_args[blender_args.index("--") + 1 :]

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module", required=True, choices=MODULE_IDS)
    args = parser.parse_args(blender_args)
    return args.module


def clear_scene() -> None:
    """Remove every object from the current scene before importing the GLB."""

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    # Delete any orphaned datablocks left by a previous in-process invocation.
    # This is harmless for the normal one-shot background render and keeps the
    # script deterministic when run repeatedly from Blender's Python console.
    for datablocks in (bpy.data.cameras, bpy.data.lights, bpy.data.materials):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def mesh_objects() -> list[bpy.types.Object]:
    """Return imported mesh objects, excluding no geometry by name."""

    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def mesh_bounds(objects: Iterable[bpy.types.Object]) -> tuple[Vector, Vector]:
    """Compute world-space bounds from every vertex in every mesh object."""

    min_corner = Vector((float("inf"), float("inf"), float("inf")))
    max_corner = Vector((float("-inf"), float("-inf"), float("-inf")))
    found_vertex = False

    for obj in objects:
        for vertex in obj.data.vertices:
            world_vertex = obj.matrix_world @ vertex.co
            min_corner.x = min(min_corner.x, world_vertex.x)
            min_corner.y = min(min_corner.y, world_vertex.y)
            min_corner.z = min(min_corner.z, world_vertex.z)
            max_corner.x = max(max_corner.x, world_vertex.x)
            max_corner.y = max(max_corner.y, world_vertex.y)
            max_corner.z = max(max_corner.z, world_vertex.z)
            found_vertex = True

    if not found_vertex:
        raise RuntimeError("Imported GLB contains no mesh vertices")

    return min_corner, max_corner


def set_input(material: bpy.types.Material, name: str, value: object) -> None:
    """Set a node input if it exists, keeping minor Blender API drift benign."""

    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is None:
        raise RuntimeError(f"Material {material.name!r} has no Principled BSDF")
    socket = principled.inputs.get(name)
    if socket is not None:
        socket.default_value = value


def make_beauty_material() -> bpy.types.Material:
    """Create the dark metallic material used by the beauty pass."""

    material = bpy.data.materials.new("Tile_Beauty_DarkMetal")
    material.use_nodes = True
    set_input(material, "Base Color", BEAUTY_BASE_COLOR)
    set_input(material, "Metallic", 0.8)
    set_input(material, "Roughness", 0.5)
    return material


def make_depth_material() -> bpy.types.Material:
    """Create a flat white, lit material for the depth/silhouette pass."""

    material = bpy.data.materials.new("Tile_Depth_FlatWhite")
    material.use_nodes = True
    set_input(material, "Base Color", DEPTH_BASE_COLOR)
    set_input(material, "Metallic", 0.0)
    set_input(material, "Roughness", 0.85)
    return material


def make_normal_material() -> bpy.types.Material:
    """Create an emission material that maps surface normals to RGB colors.

    Geometry normals are in the -1..1 range.  Scaling by 0.5 and adding 0.5
    maps them to the 0..1 range expected by an RGB image.  Emission keeps the
    result independent of the warm/cool lighting used by the beauty pass.
    """

    material = bpy.data.materials.new("Tile_Normal_XYZ")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (520, 0)
    emission = nodes.new("ShaderNodeEmission")
    emission.location = (280, 0)
    emission.inputs["Strength"].default_value = 1.0

    geometry = nodes.new("ShaderNodeNewGeometry")
    geometry.location = (-520, 0)

    scale = nodes.new("ShaderNodeVectorMath")
    scale.operation = "MULTIPLY"
    scale.location = (-280, 40)
    scale.inputs[1].default_value = (0.5, 0.5, 0.5)

    offset = nodes.new("ShaderNodeVectorMath")
    offset.operation = "ADD"
    offset.location = (0, 40)
    offset.inputs[1].default_value = (0.5, 0.5, 0.5)

    links.new(geometry.outputs["Normal"], scale.inputs[0])
    links.new(scale.outputs[0], offset.inputs[0])
    links.new(offset.outputs[0], emission.inputs["Color"])
    links.new(emission.outputs[0], output.inputs["Surface"])
    return material


def assign_material(objects: Iterable[bpy.types.Object], material: bpy.types.Material) -> None:
    """Replace every mesh material slot with one pass-specific material."""

    for obj in objects:
        obj.data.materials.clear()
        obj.data.materials.append(material)


def point_object_at(obj: bpy.types.Object, target: Vector) -> None:
    """Aim a camera/light along its local -Z axis at target."""

    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def configure_lighting(center: Vector) -> None:
    """Create the required warm and cool area lights aimed at the module."""

    bpy.ops.object.light_add(
        type="AREA", location=(center.x + 6.0, center.y - 6.0, center.z + 8.0)
    )
    warm = bpy.context.active_object
    warm.name = "Tile_Warm_Key"
    warm.data.energy = 200.0
    warm.data.size = 8.0
    warm.data.color = (1.0, 0.9, 0.7)
    point_object_at(warm, center)

    bpy.ops.object.light_add(
        type="AREA", location=(center.x - 4.0, center.y + 4.0, center.z + 6.0)
    )
    cool = bpy.context.active_object
    cool.name = "Tile_Cool_Fill"
    cool.data.energy = 100.0
    cool.data.size = 6.0
    cool.data.color = (0.6, 0.8, 1.0)
    point_object_at(cool, center)


def configure_camera(center: Vector, extent: float) -> bpy.types.Object:
    """Create the fixed orthographic isometric camera."""

    camera_data = bpy.data.cameras.new("Tile_IsoCam")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(extent * 2.5, 8.0)
    camera_data.clip_start = 0.01
    camera_data.clip_end = max(extent * 20.0, 200.0)

    camera = bpy.data.objects.new("Tile_IsoCam", camera_data)
    bpy.context.scene.collection.objects.link(camera)
    bpy.context.scene.camera = camera

    # Elevation is measured from the horizontal plane.  This is the canonical
    # isometric angle: atan(1/sqrt(2)) = 35.264 degrees.
    azimuth = math.radians(45.0)
    elevation = math.atan(1.0 / math.sqrt(2.0))
    distance = max(extent * 4.0, 8.0)
    camera.location = (
        center.x + distance * math.cos(elevation) * math.sin(azimuth),
        center.y + distance * math.cos(elevation) * math.cos(azimuth),
        center.z + distance * math.sin(elevation),
    )
    point_object_at(camera, center)
    return camera


def configure_world() -> bpy.types.World:
    """Set the dark world background without creating compositor nodes."""

    world = bpy.context.scene.world
    if world is None:
        world = bpy.data.worlds.new("Tile_World")
        bpy.context.scene.world = world

    world.color = DARK_WORLD_COLOR[:3]
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs["Color"].default_value = DARK_WORLD_COLOR
        background.inputs["Strength"].default_value = 1.0
    return world


def configure_render() -> None:
    """Set a deterministic 1024x1024 PNG render configuration."""

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        # Compatibility with older Blender builds used to regenerate the tiles.
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = RENDER_SIZE
    scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False


def render_pass(
    module_id: str,
    pass_name: str,
    objects: list[bpy.types.Object],
    material: bpy.types.Material,
) -> Path:
    """Render one material pass and verify its non-empty PNG output."""

    assign_material(objects, material)
    output_path = OUTPUT_DIR / f"{module_id}_{pass_name}.png"
    bpy.context.scene.render.filepath = str(output_path)
    print(f"[render] {pass_name:>6} -> {output_path}", flush=True)
    result = bpy.ops.render.render(write_still=True)
    if "FINISHED" not in result:
        raise RuntimeError(f"Blender render cancelled for {pass_name}: {result}")
    if not output_path.is_file():
        raise RuntimeError(f"Render output missing: {output_path}")
    size = output_path.stat().st_size
    if size <= 0:
        raise RuntimeError(f"Render output is empty: {output_path}")
    print(f"[render] {pass_name:>6} size={size:,} bytes", flush=True)
    return output_path


def main() -> None:
    module_id = parse_module_id(sys.argv)
    project_root = Path(__file__).resolve().parents[1]
    glb_path = (
        project_root
        / "assets"
        / "imported"
        / "structural"
        / "ship_structural_v0"
        / module_id
        / f"{module_id}.glb"
    )
    if not glb_path.is_file():
        raise FileNotFoundError(f"Module GLB does not exist: {glb_path}")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    print(f"[module] {module_id}", flush=True)
    print(f"[input]  {glb_path}", flush=True)
    print(f"[output] {OUTPUT_DIR}", flush=True)

    clear_scene()
    result = bpy.ops.import_scene.gltf(filepath=str(glb_path))
    if "FINISHED" not in result:
        raise RuntimeError(f"GLB import failed for {glb_path}: {result}")

    objects = mesh_objects()
    if not objects:
        raise RuntimeError(f"GLB import produced no MESH objects: {glb_path}")
    min_corner, max_corner = mesh_bounds(objects)
    center = (min_corner + max_corner) * 0.5
    extents = max_corner - min_corner
    extent = max(extents.x, extents.y, extents.z)
    print(
        "[bounds] "
        f"min={tuple(round(value, 4) for value in min_corner)} "
        f"max={tuple(round(value, 4) for value in max_corner)} "
        f"center={tuple(round(value, 4) for value in center)} "
        f"extent={extent:.4f}",
        flush=True,
    )

    configure_camera(center, extent)
    configure_lighting(center)
    configure_world()
    configure_render()

    beauty = make_beauty_material()
    depth = make_depth_material()
    normal = make_normal_material()

    outputs = (
        render_pass(module_id, "beauty", objects, beauty),
        render_pass(module_id, "depth", objects, depth),
        render_pass(module_id, "normal", objects, normal),
    )
    print("[done] output files:", flush=True)
    for output in outputs:
        print(f"       {output} ({output.stat().st_size:,} bytes)", flush=True)


if __name__ == "__main__":
    main()
