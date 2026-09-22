"""Generate the simple visual wall variants for ship_structural_v0.

Run with Blender, for example:
    blender --background --factory-startup \
      --python tools/generate_ship_structural_wall_meshes.py

The wrapper scenes own collision. These GLBs intentionally contain only the
visual wall slabs and their shared SSV0_BULKHEAD material.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import bpy


GRID_STEP_M = 4.0
WALL_HEIGHT_M = 3.0
WALL_THICKNESS_M = 0.2
MATERIAL_NAME = "SSV0_BULKHEAD"
MATERIAL_RGBA = (0.22, 0.25, 0.29, 1.0)
MATERIAL_ROUGHNESS = 0.7

MODULE_SPECS: dict[str, tuple[tuple[str, tuple[float, float, float], tuple[float, float, float]], ...]] = {
    # A cube is closed on all six sides, including the requested end cap faces.
    "wall_end_cap": (
        ("Cap", (GRID_STEP_M, WALL_THICKNESS_M, WALL_HEIGHT_M), (0.0, 0.0, WALL_HEIGHT_M / 2.0)),
    ),
    # The project collision contract defines both corner variants as north/east
    # SOLID wings. The concave versus convex corner is selected by placement.
    "wall_inner_corner": (
        ("WingNorth", (GRID_STEP_M, WALL_THICKNESS_M, WALL_HEIGHT_M), (0.0, -2.0, WALL_HEIGHT_M / 2.0)),
        ("WingEast", (WALL_THICKNESS_M, GRID_STEP_M, WALL_HEIGHT_M), (2.0, 0.0, WALL_HEIGHT_M / 2.0)),
    ),
    "wall_outer_corner": (
        ("WingNorth", (GRID_STEP_M, WALL_THICKNESS_M, WALL_HEIGHT_M), (0.0, -2.0, WALL_HEIGHT_M / 2.0)),
        ("WingEast", (WALL_THICKNESS_M, GRID_STEP_M, WALL_HEIGHT_M), (2.0, 0.0, WALL_HEIGHT_M / 2.0)),
    ),
    "wall_t_junction": (
        ("WingNorth", (GRID_STEP_M, WALL_THICKNESS_M, WALL_HEIGHT_M), (0.0, -2.0, WALL_HEIGHT_M / 2.0)),
        ("WingEast", (WALL_THICKNESS_M, GRID_STEP_M, WALL_HEIGHT_M), (2.0, 0.0, WALL_HEIGHT_M / 2.0)),
        ("WingWest", (WALL_THICKNESS_M, GRID_STEP_M, WALL_HEIGHT_M), (-2.0, 0.0, WALL_HEIGHT_M / 2.0)),
    ),
}


def get_or_create_material() -> bpy.types.Material:
    material = bpy.data.materials.get(MATERIAL_NAME) or bpy.data.materials.new(MATERIAL_NAME)
    material.diffuse_color = MATERIAL_RGBA
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    if principled is not None:
        principled.inputs["Base Color"].default_value = MATERIAL_RGBA
        principled.inputs["Roughness"].default_value = MATERIAL_ROUGHNESS
        principled.inputs["Metallic"].default_value = 0.0
    return material


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def add_wall_box(
    module_id: str,
    part_name: str,
    dimensions: tuple[float, float, float],
    location: tuple[float, float, float],
    material: bpy.types.Material,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = f"Visual_{module_id}_{part_name}"
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    obj["asset_id"] = module_id
    obj["visual_role"] = "structural_wall_slab"
    return obj


def export_module(module_id: str, specs: tuple[tuple[str, tuple[float, float, float], tuple[float, float, float]], ...], output_root: Path, material: bpy.types.Material) -> Path:
    clear_scene()
    objects = [add_wall_box(module_id, part, dimensions, location, material) for part, dimensions, location in specs]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    output_path = output_root / module_id / f"{module_id}.glb"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        export_apply=True,
        use_selection=True,
    )
    if result != {"FINISHED"}:
        raise RuntimeError(f"GLB export cancelled for {module_id}: {result}")
    data = output_path.read_bytes()
    if len(data) <= 0 or data[:4] != b"glTF":
        raise RuntimeError(f"invalid GLB output for {module_id}: {output_path}")
    print(f"EXPORTED {module_id} path={output_path} bytes={len(data)} parts={len(objects)}")
    return output_path


def main() -> None:
    # Blender's argv after -- is intentionally parsed without importing bpy in
    # any helper, so this file remains a direct Blender CLI authoring script.
    argv = __import__("sys").argv
    user_args = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=Path(__file__).resolve().parents[1] / "assets/imported/structural/ship_structural_v0")
    args = parser.parse_args(user_args)
    output_root = args.output_root.resolve()
    material = get_or_create_material()
    for module_id, specs in MODULE_SPECS.items():
        export_module(module_id, specs, output_root, material)
    print(f"WALL_MESH_GENERATION_PASS modules={len(MODULE_SPECS)} output_root={output_root}")


if __name__ == "__main__":
    main()
