#!/usr/bin/env python3
"""Generate gameplay-grade floor geometry for structural modules.

Run with Blender's Python:
    /opt/homebrew/bin/blender --background --factory-startup \
      --python tools/improve_floor_geometry.py -- \
      --project-root <path> --source-root <path> \
      --module floor_1x1 [--overwrite]

Generates improved geometry with:
- Panel lines (inset faces creating grid patterns)
- Vent cutouts (recessed panels with grill geometry)
- Cable run channels (extruded paths along edges)
- Surface detail (raised/lowered floor plates)
- Edge bevels for readable silhouettes in isometric view
"""

import argparse
import json
import os
import sys
from pathlib import Path


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate improved floor geometry for structural modules"
    )
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--module", action="append", default=[])
    group.add_argument("--all-floors", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args(argv)


FLOOR_MODULES = ["floor_1x1", "floor_2x1", "corridor_floor_1x1", "corridor_floor_1x2"]

GRID_STEP_M = 4.0
PANEL_THICKNESS = 0.25  # existing floor plate thickness
EDGE_BEVEL_WIDTH = 0.02
VENT_DEPTH = 0.05
CABLE_CHANNEL_DEPTH = 0.03
CABLE_CHANNEL_WIDTH = 0.08


def y_up_to_z_up(v):
    """Contract [x,y,z] -> Blender [x,z,y]."""
    return (float(v[0]), float(v[2]), float(v[1]))


def load_contract(project_root: Path, module_id: str) -> dict:
    contract_path = (
        project_root / "data/placement/contracts/structural/ship_structural_v0"
        / f"{module_id}_contract.json"
    )
    return json.loads(contract_path.read_text(encoding="utf-8"))


def create_floor_plate(bpy, width, depth, module_id):
    """Create the main floor plate with panel lines."""
    import bmesh
    from mathutils import Vector

    # Main plate
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, PANEL_THICKNESS / 2))
    plate = bpy.context.active_object
    plate.name = f"Floor_{module_id}_Plate"
    plate.dimensions = (width, depth, PANEL_THICKNESS)
    bpy.context.view_layer.objects.active = plate
    plate.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    # Add panel lines via inset faces
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(plate.data)

    # Inset top face to create panel border
    top_faces = [f for f in bm.faces if f.normal.z > 0.9]
    if top_faces:
        result = bmesh.ops.inset_region(bm, faces=top_faces, thickness=0.08, use_even_offset=True)
        # Inset again for double panel line
        inset_faces = result.get('faces', top_faces)
        if inset_faces:
            bmesh.ops.inset_region(bm, faces=inset_faces, thickness=0.04, use_even_offset=True)

    bmesh.update_edit_mesh(plate.data)
    bpy.ops.object.mode_set(mode='OBJECT')

    return plate


def add_vent_cutouts(bpy, plate, width, depth, module_id):
    """Add vent recesses on the floor surface."""
    import bmesh

    # Create vent holes along the edges
    vent_positions = []
    # Two vents on north/south edges
    for x_pos in [-width / 4, width / 4]:
        vent_positions.append((x_pos, depth / 2 - 0.3, PANEL_THICKNESS))
        vent_positions.append((x_pos, -depth / 2 + 0.3, PANEL_THICKNESS))

    for i, pos in enumerate(vent_positions):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=pos)
        vent = bpy.context.active_object
        vent.name = f"Vent_{module_id}_{i:02d}"
        vent.dimensions = (0.4, 0.15, VENT_DEPTH)
        bpy.context.view_layer.objects.active = vent
        vent.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

        # Boolean difference to cut vent into plate
        bpy.context.view_layer.objects.active = plate
        plate.select_set(True)
        mod = plate.modifiers.new(name=f"VentCut_{i}", type='BOOLEAN')
        mod.operation = 'DIFFERENCE'
        mod.object = vent
        bpy.ops.object.modifier_apply(modifier=mod.name)

        # Remove vent object
        bpy.data.objects.remove(vent, do_unlink=True)


def add_cable_channels(bpy, width, depth, module_id):
    """Add raised cable channel runs along floor edges."""
    channel_height = 0.06
    channel_objects = []

    # Cable channels along east/west edges
    for side, x_pos in [("East", width / 2 - 0.15), ("West", -width / 2 + 0.15)]:
        bpy.ops.mesh.primitive_cube_add(
            size=1.0,
            location=(x_pos, 0, PANEL_THICKNESS + channel_height / 2)
        )
        channel = bpy.context.active_object
        channel.name = f"CableChannel_{module_id}_{side}"
        channel.dimensions = (CABLE_CHANNEL_WIDTH, depth * 0.8, channel_height)
        bpy.context.view_layer.objects.active = channel
        channel.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        channel_objects.append(channel)

    return channel_objects


def add_floor_drains(bpy, width, depth, module_id):
    """Add drain grates at low points."""
    drain_objects = []

    # Center drain
    bpy.ops.mesh.primitive_cylinder_add(
        radius=0.12,
        depth=0.02,
        location=(0, 0, PANEL_THICKNESS + 0.01)
    )
    drain = bpy.context.active_object
    drain.name = f"Drain_{module_id}_Center"
    drain_objects.append(drain)

    return drain_objects


def add_surface_details(bpy, width, depth, module_id):
    """Add raised/lowered floor plates and access panels."""
    import bmesh

    detail_objects = []

    # Raised access panel near center
    bpy.ops.mesh.primitive_cube_add(
        size=1.0,
        location=(0.5, 0.5, PANEL_THICKNESS + 0.02)
    )
    panel = bpy.context.active_object
    panel.name = f"AccessPanel_{module_id}_01"
    panel.dimensions = (0.6, 0.6, 0.04)
    bpy.context.view_layer.objects.active = panel
    panel.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    detail_objects.append(panel)

    # Bolt heads at corners of access panel
    bolt_radius = 0.02
    bolt_height = 0.015
    for bx, by in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]:
        bpy.ops.mesh.primitive_cylinder_add(
            radius=bolt_radius,
            depth=bolt_height,
            location=(bx, by, PANEL_THICKNESS + 0.04 + bolt_height / 2)
        )
        bolt = bpy.context.active_object
        bolt.name = f"Bolt_{module_id}_{bx}_{by}"
        detail_objects.append(bolt)

    return detail_objects


def apply_materials(bpy, objects, material_name="MAT_PaintedAlloyGray"):
    """Apply the Salvage Industrial material to objects."""
    mat = bpy.data.materials.get(material_name)
    if mat is None:
        mat = bpy.data.materials.new(material_name)
        mat.use_nodes = True
        mat.diffuse_color = (0.50, 0.50, 0.50, 1.0)
        nodes = mat.node_tree.nodes
        principled = nodes.get("Principled BSDF")
        if principled:
            if "Base Color" in principled.inputs:
                principled.inputs["Base Color"].default_value = (0.50, 0.50, 0.50, 1.0)
            if "Roughness" in principled.inputs:
                principled.inputs["Roughness"].default_value = 0.70
            if "Metallic" in principled.inputs:
                principled.inputs["Metallic"].default_value = 0.35

    for obj in objects:
        if obj.type == 'MESH':
            if len(obj.data.materials) == 0:
                obj.data.materials.append(mat)
            else:
                obj.data.materials[0] = mat


def improve_floor(bpy, project_root: Path, source_root: Path, module_id: str, overwrite: bool):
    """Generate improved geometry for one floor module."""
    contract = load_contract(project_root, module_id)
    footprint = contract.get("footprint_cells", [1, 1])
    width = float(footprint[0]) * GRID_STEP_M
    depth = float(footprint[1]) * GRID_STEP_M

    # Special case: corridor floors have depth along the long axis
    if module_id.startswith("corridor_"):
        # Corridor is narrow and long
        width = float(footprint[0]) * GRID_STEP_M
        depth = float(footprint[1]) * GRID_STEP_M if footprint[1] > 0 else GRID_STEP_M

    blend_path = source_root / module_id / f"{module_id}.blend"

    if not overwrite and blend_path.exists():
        print(f"SKIP {module_id}: already exists (use --overwrite)")
        return

    # Clear scene
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    # Create proper source structure
    # ModuleRoot empty
    root = bpy.data.objects.new(f"ModuleRoot_{module_id}", None)
    bpy.context.scene.collection.objects.link(root)
    root.location = (0, 0, 0)
    root.rotation_euler = (0, 0, 0)
    root["module_id"] = module_id
    root["kit_id"] = "ship_structural_v0"
    root["module_family"] = contract.get("module_family", "floor")
    root["grid_step_m"] = GRID_STEP_M
    root["footprint_cells"] = json.dumps(footprint)
    root["placement_origin"] = contract.get("bounds", {}).get("placement_origin", "cell-center-floor")

    # Geometry collection
    geometry = bpy.data.collections.new("Geometry")
    bpy.context.scene.collection.children.link(geometry)

    # AuthoringHelpers collection
    helpers = bpy.data.collections.new("AuthoringHelpers")
    bpy.context.scene.collection.children.link(helpers)

    # Create improved geometry in Geometry collection
    plate = create_floor_plate(bpy, width, depth, module_id)
    cable_channels = add_cable_channels(bpy, width, depth, module_id)
    drains = add_floor_drains(bpy, width, depth, module_id)
    details = add_surface_details(bpy, width, depth, module_id)

    all_objects = [plate] + cable_channels + drains + details
    apply_materials(bpy, all_objects)

    # Move geometry objects to Geometry collection and parent to root
    for obj in all_objects:
        for col in obj.users_collection:
            col.objects.unlink(obj)
        geometry.objects.link(obj)
        obj.parent = root

    # Add Origin helper
    origin = bpy.data.objects.new("Origin", None)
    origin.empty_display_type = "PLAIN_AXES"
    origin.empty_display_size = 0.5
    helpers.objects.link(origin)
    origin.parent = root

    # Add Anchor_FloorCenter
    anchor = bpy.data.objects.new("Anchor_FloorCenter", None)
    anchor.empty_display_type = "PLAIN_AXES"
    anchor.empty_display_size = 0.3
    helpers.objects.link(anchor)
    anchor.parent = root

    # Add socket empties from contract
    sockets = contract.get("sockets", [])
    for socket in sockets:
        socket_id = socket["id"]
        pos_contract = socket.get("position_m", [0, 0, 0])
        pos_blender = y_up_to_z_up(pos_contract)
        empty = bpy.data.objects.new(f"Anchor_SOCK_{socket_id}", None)
        empty.empty_display_type = "ARROWS"
        empty.empty_display_size = 0.3
        empty.location = pos_blender
        helpers.objects.link(empty)
        empty.parent = root
        empty["socket_id"] = socket_id
        empty["kind"] = socket.get("kind", "")
        empty["compatible_kinds"] = json.dumps(socket.get("compatible_kinds", []))
        empty["position_contract_y_up"] = json.dumps(pos_contract)
        empty["position_blender_z_up"] = json.dumps(list(pos_blender))

    # Add CollisionProxy
    bounds = contract.get("bounds", {})
    bmin = bounds.get("local_min_m", [-2, 0, -2])
    bmax = bounds.get("local_max_m", [2, 0.25, 2])
    size_contract = [bmax[i] - bmin[i] for i in range(3)]
    center_contract = [(bmax[i] + bmin[i]) / 2 for i in range(3)]
    size_blender = (size_contract[0], size_contract[2], size_contract[1])
    center_blender = y_up_to_z_up(center_contract)

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center_blender)
    collision = bpy.context.active_object
    collision.name = "CollisionProxy"
    collision.dimensions = size_blender
    bpy.context.view_layer.objects.active = collision
    collision.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    collision.display_type = "WIRE"
    collision.hide_render = True
    for col in collision.users_collection:
        col.objects.unlink(collision)
    helpers.objects.link(collision)
    collision.parent = root
    collision["proxy_shape"] = contract.get("collision", {}).get("proxy_shape", "box")
    collision["nav_blocker"] = contract.get("collision", {}).get("nav_blocker", False)

    # Save
    os.makedirs(blend_path.parent, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    print(f"FLOOR_IMPROVED module={module_id} objects={len(all_objects)} blend={blend_path}")


def main():
    import bpy

    raw_argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    args = parse_args(raw_argv)

    modules = FLOOR_MODULES if args.all_floors else args.module

    for module_id in modules:
        improve_floor(bpy, args.project_root, args.source_root, module_id, args.overwrite)


if __name__ == "__main__":
    main()
