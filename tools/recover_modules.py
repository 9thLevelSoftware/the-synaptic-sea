#!/usr/bin/env python3
"""Author the eight P0 ship structural modules from placement contracts.

Run with Blender's Python, not the system Python:

    blender --background --python tools/recover_modules.py

The placement contracts are Y-up.  Blender is Z-up, so contract positions and
bounds are converted with [x, y, z] -> [x, z, y].  The visual meshes are
hand-authored primitives; socket positions and the collision proxy are always
derived from the contract metadata.
"""

import bpy
import json
import math
import os
from datetime import datetime, timezone

ASSET_ROOT = "/Volumes/Untitled/SynapticSeaAssets"
REPO = os.path.join(ASSET_ROOT, "projects", "the-synaptic-sea")
SOURCE_ROOT = os.path.join(ASSET_ROOT, "meshes", "source", "ship_structural_v0")
PROCESSED_ROOT = os.path.join(ASSET_ROOT, "meshes", "processed", "ship_structural_v0")
CONTRACT_ROOT = os.path.join(
    REPO, "data", "placement", "contracts", "structural", "ship_structural_v0"
)

MODULES = [
    "floor_1x1",
    "floor_2x1",
    "corridor_floor_1x1",
    "corridor_floor_1x2",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
]

GRID_STEP_M = 4.0
PAINTED_ALLOY_RGBA = (0.50, 0.50, 0.50, 1.0)
ROUGHNESS = 0.70


def y_up_to_z_up(vector):
    """Convert a contract vector [x, y, z] into Blender [x, y, z]."""
    return (float(vector[0]), float(vector[2]), float(vector[1]))


def load_contract(module_id):
    contract_path = os.path.join(CONTRACT_ROOT, module_id + "_contract.json")
    meta_path = os.path.join(SOURCE_ROOT, module_id, module_id + ".meta.json")
    if not os.path.isfile(contract_path):
        raise FileNotFoundError(contract_path)
    if not os.path.isfile(meta_path):
        raise FileNotFoundError(meta_path)
    with open(contract_path, "r", encoding="utf-8") as handle:
        contract_file = json.load(handle)
    with open(meta_path, "r", encoding="utf-8") as handle:
        meta = json.load(handle)
    contract = meta.get("contract") or contract_file
    if contract.get("module_id") != module_id:
        raise ValueError("contract module_id mismatch for %s" % module_id)
    return contract, contract_path, meta_path


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != "Collection" and collection.users == 0:
            bpy.data.collections.remove(collection)
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.length_unit = "METERS"


def make_material():
    material = bpy.data.materials.get("MAT_PaintedAlloyGray")
    if material is None:
        material = bpy.data.materials.new("MAT_PaintedAlloyGray")
    material.use_nodes = True
    material.diffuse_color = PAINTED_ALLOY_RGBA
    nodes = material.node_tree.nodes
    principled = nodes.get("Principled BSDF")
    if principled is not None:
        if "Base Color" in principled.inputs:
            principled.inputs["Base Color"].default_value = PAINTED_ALLOY_RGBA
        if "Roughness" in principled.inputs:
            principled.inputs["Roughness"].default_value = ROUGHNESS
        if "Metallic" in principled.inputs:
            principled.inputs["Metallic"].default_value = 0.35
    return material


def create_collection(name):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def link_object_to_collection(obj, collection):
    for existing in list(obj.users_collection):
        existing.objects.unlink(obj)
    collection.objects.link(obj)


def assign_material(obj, material):
    if obj.type != "MESH":
        return
    if len(obj.data.materials) == 0:
        obj.data.materials.append(material)
    else:
        obj.data.materials[0] = material


def create_box(name, size, location, collection, material=None, bevel=0.0):
    """Create an applied-transform cube with dimensions in Blender meters."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.active_object
    obj.name = name
    link_object_to_collection(obj, collection)
    obj.dimensions = tuple(float(value) for value in size)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if material is not None:
        assign_material(obj, material)
    if bevel > 0.0:
        modifier = obj.modifiers.new(name="EdgeSoftening", type="BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
    return obj


def create_ramp(name, width, length, rise, collection, material):
    """Create a solid wedge, low at -Y and high at +Y."""
    half_w = width / 2.0
    half_l = length / 2.0
    thickness = 0.15
    vertices = [
        (-half_w, -half_l, 0.0),
        (half_w, -half_l, 0.0),
        (half_w, half_l, 0.0),
        (-half_w, half_l, 0.0),
        (-half_w, -half_l, thickness),
        (half_w, -half_l, thickness),
        (half_w, half_l, rise),
        (-half_w, half_l, rise),
    ]
    faces = [
        (0, 3, 2, 1),  # underside
        (4, 5, 6, 7),  # walking surface
        (0, 1, 5, 4),  # low end
        (1, 2, 6, 5),  # east side
        (2, 3, 7, 6),  # high end
        (3, 0, 4, 7),  # west side
    ]
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    return obj


def create_origin(root, helpers):
    origin = bpy.data.objects.new("Origin", None)
    origin.empty_display_type = "PLAIN_AXES"
    origin.empty_display_size = 0.5
    helpers.objects.link(origin)
    origin.parent = root
    origin["marker_kind"] = "placement_origin"
    origin["origin_policy"] = "contract_defined"
    return origin


def socket_normal_from_id(socket_id):
    lower = socket_id.lower()
    if "north" in lower or "up" in lower:
        return (0.0, 1.0, 0.0)
    if "south" in lower or "down" in lower:
        return (0.0, -1.0, 0.0)
    if "east" in lower or "right" in lower:
        return (1.0, 0.0, 0.0)
    if "west" in lower or "left" in lower:
        return (-1.0, 0.0, 0.0)
    return (0.0, 0.0, 1.0)


def add_sockets(contract, root, helpers):
    socket_names = []
    socket_records = []
    for socket in contract.get("sockets", []):
        socket_id = socket["id"]
        position_contract = socket.get("position_m", [0.0, 0.0, 0.0])
        position_blender = y_up_to_z_up(position_contract)
        empty = bpy.data.objects.new("Anchor_SOCK_" + socket_id, None)
        empty.empty_display_type = "ARROWS"
        empty.empty_display_size = 0.3
        empty.location = position_blender
        helpers.objects.link(empty)
        empty.parent = root
        empty["socket_id"] = socket_id
        empty["kind"] = socket.get("kind", "")
        empty["compatible_kinds"] = json.dumps(socket.get("compatible_kinds", []))
        empty["position_contract_y_up"] = json.dumps(position_contract)
        empty["position_blender_z_up"] = json.dumps(list(position_blender))
        empty["normal_local"] = json.dumps(list(socket_normal_from_id(socket_id)))
        empty["up_local"] = json.dumps([0.0, 0.0, 1.0])
        empty["rotation_step_deg"] = 90
        empty["terminal_allowed"] = True
        socket_names.append(empty.name)
        socket_records.append(
            {
                "id": socket_id,
                "kind": socket.get("kind", ""),
                "position_contract_y_up": list(position_contract),
                "position_blender_z_up": list(position_blender),
                "compatible_kinds": list(socket.get("compatible_kinds", [])),
            }
        )
    return socket_names, socket_records


def add_collision_proxy(contract, root, helpers):
    bounds = contract.get("bounds", {})
    bounds_min = bounds.get("local_min_m", [-2.0, 0.0, -2.0])
    bounds_max = bounds.get("local_max_m", [2.0, 0.25, 2.0])
    size_contract = [
        float(bounds_max[index]) - float(bounds_min[index]) for index in range(3)
    ]
    center_contract = [
        (float(bounds_max[index]) + float(bounds_min[index])) / 2.0 for index in range(3)
    ]
    # Contract X/Y/Z -> Blender X/Z/Y, including the contract's exact dimensions.
    size_blender = (size_contract[0], size_contract[2], size_contract[1])
    center_blender = y_up_to_z_up(center_contract)
    collision = create_box(
        "CollisionProxy",
        size_blender,
        center_blender,
        helpers,
        material=None,
    )
    collision.display_type = "WIRE"
    collision.hide_render = True
    collision.parent = root
    collision["proxy_shape"] = contract.get("collision", {}).get("proxy_shape", "box")
    collision["bounds_min_contract_y_up"] = json.dumps(list(bounds_min))
    collision["bounds_max_contract_y_up"] = json.dumps(list(bounds_max))
    collision["bounds_min_blender_z_up"] = json.dumps(list(y_up_to_z_up(bounds_min)))
    collision["bounds_max_blender_z_up"] = json.dumps(list(y_up_to_z_up(bounds_max)))
    collision["nav_blocker"] = bool(contract.get("collision", {}).get("nav_blocker", False))
    return collision, {
        "name": collision.name,
        "proxy_shape": contract.get("collision", {}).get("proxy_shape", "box"),
        "bounds_min_contract_y_up": list(bounds_min),
        "bounds_max_contract_y_up": list(bounds_max),
        "bounds_min_blender_z_up": list(y_up_to_z_up(bounds_min)),
        "bounds_max_blender_z_up": list(y_up_to_z_up(bounds_max)),
        "center_blender_z_up": list(center_blender),
        "size_blender_z_up": list(size_blender),
        "nav_blocker": bool(contract.get("collision", {}).get("nav_blocker", False)),
    }


def author_visual_geometry(module_id, contract, visual, material):
    """Author readable structural geometry for one contract family."""
    family = contract.get("module_family", "")
    footprint = contract.get("footprint_cells", [1, 1])
    width = float(footprint[0]) * GRID_STEP_M
    depth = float(footprint[1]) * GRID_STEP_M
    objects = []

    if family == "floor":
        objects.append(
            create_box(
                "Visual_" + module_id + "_Plate",
                (width, depth, 0.25),
                (0.0, 0.0, 0.125),
                visual,
                material,
                bevel=0.03,
            )
        )

    elif family == "corridor_floor":
        objects.append(
            create_box(
                "Visual_" + module_id + "_Floor",
                (width, depth, 0.25),
                (0.0, 0.0, 0.125),
                visual,
                material,
                bevel=0.03,
            )
        )
        # Corridor side walls run along the long axis and leave the north/south
        # sockets open.  They are intentionally low enough to read as guard
        # walls while retaining a walkable corridor silhouette.
        wall_thickness = 0.15
        wall_height = 2.5
        x = width / 2.0 - wall_thickness / 2.0
        for side, x_pos in (("East", x), ("West", -x)):
            objects.append(
                create_box(
                    "Visual_" + module_id + "_" + side + "Wall",
                    (wall_thickness, depth, wall_height),
                    (x_pos, 0.0, wall_height / 2.0),
                    visual,
                    material,
                    bevel=0.025,
                )
            )

    elif family == "wall":
        objects.append(
            create_box(
                "Visual_" + module_id + "_Panel",
                (width, 0.15, 3.0),
                (0.0, 0.0, 1.5),
                visual,
                material,
                bevel=0.025,
            )
        )
        # Small end caps make the authored wall legible in the isometric view
        # without changing the nominal panel envelope.
        for side, x_pos in (("West", -width / 2.0 + 0.075), ("East", width / 2.0 - 0.075)):
            objects.append(
                create_box(
                    "Visual_" + module_id + "_" + side + "Post",
                    (0.15, 0.22, 3.0),
                    (x_pos, 0.0, 1.5),
                    visual,
                    material,
                    bevel=0.02,
                )
            )

    elif family == "portal":
        opening_width = 1.0
        opening_height = 2.2
        total_height = 3.2
        side_width = (width - opening_width) / 2.0
        for side, x_pos in (("West", -(opening_width / 2.0 + side_width / 2.0)), ("East", opening_width / 2.0 + side_width / 2.0)):
            objects.append(
                create_box(
                    "Visual_" + module_id + "_" + side + "Jamb",
                    (side_width, 0.15, opening_height),
                    (x_pos, 0.0, opening_height / 2.0),
                    visual,
                    material,
                    bevel=0.025,
                )
            )
        objects.append(
            create_box(
                "Visual_" + module_id + "_Lintel",
                (opening_width, 0.15, total_height - opening_height),
                (0.0, 0.0, opening_height + (total_height - opening_height) / 2.0),
                visual,
                material,
                bevel=0.025,
            )
        )

    elif family == "support":
        # Structural support is intentionally a compact 0.4 m square post;
        # the placement contract still owns its placement/collision envelope.
        objects.append(
            create_box(
                "Visual_" + module_id + "_Post",
                (0.4, 0.4, 3.0),
                (0.0, 0.0, 1.5),
                visual,
                material,
                bevel=0.035,
            )
        )
        objects.append(
            create_box(
                "Visual_" + module_id + "_Foot",
                (0.55, 0.55, 0.12),
                (0.0, 0.0, 0.06),
                visual,
                material,
                bevel=0.02,
            )
        )
        objects.append(
            create_box(
                "Visual_" + module_id + "_Cap",
                (0.55, 0.55, 0.12),
                (0.0, 0.0, 2.94),
                visual,
                material,
                bevel=0.02,
            )
        )

    elif family == "vertical_transition":
        objects.append(create_ramp("Visual_" + module_id + "_Wedge", width, depth, 3.0, visual, material))
        # Low side curbs provide a clear edge for the locked-isometric camera.
        curb_height = 0.18
        curb_width = 0.12
        x = width / 2.0 - curb_width / 2.0
        for side, x_pos in (("East", x), ("West", -x)):
            objects.append(
                create_box(
                    "Visual_" + module_id + "_" + side + "Curb",
                    (curb_width, depth, curb_height),
                    (x_pos, 0.0, curb_height / 2.0),
                    visual,
                    material,
                    bevel=0.02,
                )
            )

    else:
        raise ValueError("unsupported module family %r for %s" % (family, module_id))

    for obj in objects:
        obj["module_id"] = module_id
        obj["geometry_role"] = "structural_visual"
        obj["material_role"] = "painted_alloy_gray"
    return objects


def bounds_of_objects(objects):
    coordinates = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        for vertex in obj.data.vertices:
            coordinates.append(obj.matrix_world @ vertex.co)
    if not coordinates:
        return None
    mins = [min(vector[index] for vector in coordinates) for index in range(3)]
    maxs = [max(vector[index] for vector in coordinates) for index in range(3)]
    return {"min_blender_z_up": mins, "max_blender_z_up": maxs}


def set_root_properties(root, module_id, contract):
    root["module_id"] = module_id
    root["kit_id"] = contract.get("kit_id", "ship_structural_v0")
    root["module_family"] = contract.get("module_family", "")
    root["grid_step_m"] = float(contract.get("grid_step_m", GRID_STEP_M))
    root["footprint_cells"] = json.dumps(contract.get("footprint_cells", []))
    root["bounds_min_contract_y_up"] = json.dumps(contract.get("bounds", {}).get("local_min_m", []))
    root["bounds_max_contract_y_up"] = json.dumps(contract.get("bounds", {}).get("local_max_m", []))
    root["placement_origin"] = contract.get("bounds", {}).get("placement_origin", "")
    root["authoring_source"] = "hand-authored Blender Python primitives"
    root["socket_contract_source"] = "meta.json contract"


def export_visual_glb(filepath, visual_objects):
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in visual_objects:
        obj.select_set(True)
    if visual_objects:
        bpy.context.view_layer.objects.active = visual_objects[0]
    # use_selection keeps authoring helpers, socket empties, and the source-only
    # wireframe collision proxy out of the runtime visual GLB.
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        export_apply=True,
        use_selection=True,
    )
    bpy.ops.object.select_all(action="DESELECT")


def author_module(module_id):
    contract, contract_path, meta_path = load_contract(module_id)
    clear_scene()
    material = make_material()
    visual = create_collection("Visual")
    helpers = create_collection("AuthoringHelpers")

    root = bpy.data.objects.new("ModuleRoot_" + module_id, None)
    bpy.context.scene.collection.objects.link(root)
    set_root_properties(root, module_id, contract)

    visual_objects = author_visual_geometry(module_id, contract, visual, material)
    for obj in visual_objects:
        obj.parent = root
    create_origin(root, helpers)
    socket_names, socket_records = add_sockets(contract, root, helpers)
    _, collision_record = add_collision_proxy(contract, root, helpers)

    blend_path = os.path.join(SOURCE_ROOT, module_id, module_id + ".blend")
    glb_path = os.path.join(PROCESSED_ROOT, module_id, module_id + "_intact.glb")
    sidecar_path = os.path.join(SOURCE_ROOT, module_id, module_id + ".sidecar.json")
    os.makedirs(os.path.dirname(blend_path), exist_ok=True)
    os.makedirs(os.path.dirname(sidecar_path), exist_ok=True)

    visual_bounds = bounds_of_objects(visual_objects)
    bpy.context.scene["module_id"] = module_id
    bpy.context.scene["source_contract"] = contract_path
    bpy.context.scene["source_meta"] = meta_path
    bpy.context.scene["socket_count"] = len(socket_names)
    bpy.context.scene["collision_proxy_name"] = "CollisionProxy"
    bpy.context.scene["base_material"] = material.name

    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    export_visual_glb(glb_path, visual_objects)

    sidecar = {
        "schema_version": "1.0.0",
        "asset_id": module_id,
        "module_id": module_id,
        "kit_id": contract.get("kit_id", "ship_structural_v0"),
        "module_family": contract.get("module_family", ""),
        "source_type": "hand_authored_blender_geometry",
        "source_script": "tools/recover_modules.py",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "blender_coordinate_system": "Z-up",
        "contract_coordinate_system": "Y-up",
        "coordinate_conversion": "contract [x,y,z] -> Blender [x,z,y]",
        "grid_step_m": contract.get("grid_step_m", GRID_STEP_M),
        "footprint_cells": contract.get("footprint_cells", []),
        "pivot_policy": contract.get("bounds", {}).get("placement_origin", ""),
        "contract_path": contract_path,
        "meta_path": meta_path,
        "contract_bounds_y_up": contract.get("bounds", {}),
        "contract_bounds_blender_z_up": {
            "local_min_m": list(y_up_to_z_up(contract.get("bounds", {}).get("local_min_m", [0, 0, 0]))),
            "local_max_m": list(y_up_to_z_up(contract.get("bounds", {}).get("local_max_m", [0, 0, 0]))),
        },
        "visual_geometry_bounds_blender_z_up": visual_bounds,
        "sockets": socket_records,
        "socket_names": socket_names,
        "collision": collision_record,
        "material_list": [
            {
                "name": material.name,
                "role": "painted_alloy_gray",
                "base_color_rgba": list(PAINTED_ALLOY_RGBA),
                "roughness": ROUGHNESS,
                "metallic": 0.35,
            }
        ],
        "outputs": {
            "blend": blend_path,
            "glb": glb_path,
            "sidecar": sidecar_path,
        },
        "provenance": contract.get("provenance", {
            "source_platform": "self-authored",
            "license_state": "self-authored",
        }),
        "validation_status": "authored_and_exported",
    }
    with open(sidecar_path, "w", encoding="utf-8") as handle:
        json.dump(sidecar, handle, indent=2, sort_keys=True)
        handle.write("\n")

    return {
        "module_id": module_id,
        "family": contract.get("module_family", ""),
        "socket_count": len(socket_names),
        "blend": blend_path,
        "blend_bytes": os.path.getsize(blend_path),
        "glb": glb_path,
        "glb_bytes": os.path.getsize(glb_path),
        "sidecar": sidecar_path,
        "sidecar_bytes": os.path.getsize(sidecar_path),
        "visual_bounds": visual_bounds,
    }


def main():
    print("Recovering %d P0 ship structural modules" % len(MODULES))
    summaries = []
    for module_id in MODULES:
        summary = author_module(module_id)
        summaries.append(summary)
        print(
            "AUTHORED %-28s family=%-20s sockets=%d blend=%dB glb=%dB sidecar=%dB"
            % (
                summary["module_id"],
                summary["family"],
                summary["socket_count"],
                summary["blend_bytes"],
                summary["glb_bytes"],
                summary["sidecar_bytes"],
            )
        )
    print("P0_RECOVERY_SUMMARY_BEGIN")
    print(json.dumps(summaries, indent=2, sort_keys=True))
    print("P0_RECOVERY_SUMMARY_END")


if __name__ == "__main__":
    main()
