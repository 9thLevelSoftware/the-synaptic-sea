#!/usr/bin/env python3
"""Re-author the three canonical corner/T modules as vertex-owned 2 m rays.

Run only through Blender with ``--background --factory-startup``. The caller
supplies an owned recovered source root; this script updates those Blend files,
exports the tracked runtime GLBs atomically, and rewrites timestamp-free source
records from the resulting contract and GLB bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import sys
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from tools.recover_modules import (  # noqa: E402
    _save_blend_atomically,
    add_sockets,
    build_source_record,
    canonical_json,
    create_box,
    load_source_spec,
    set_root_properties,
)


MODULE_RAYS: dict[str, tuple[tuple[str, tuple[float, float, float], tuple[float, float, float]], ...]] = {
    "wall_inner_corner": (
        ("North", (0.2, 3.0, 2.0), (0.0, 1.5, -1.0)),
        ("East", (2.0, 3.0, 0.2), (1.0, 1.5, 0.0)),
    ),
    "wall_outer_corner": (
        ("North", (0.2, 3.0, 2.0), (0.0, 1.5, -1.0)),
        ("East", (2.0, 3.0, 0.2), (1.0, 1.5, 0.0)),
    ),
    "wall_t_junction": (
        ("North", (0.2, 3.0, 2.0), (0.0, 1.5, -1.0)),
        ("East", (2.0, 3.0, 0.2), (1.0, 1.5, 0.0)),
        ("West", (2.0, 3.0, 0.2), (-1.0, 1.5, 0.0)),
    ),
}

# Verified against the immutable recovered-source manifest and its beforeimage.
# Re-authoring starts from the last authored GLB, but must never replace this
# historical provenance with that intermediate asset's hash.
RECOVERED_ORIGINAL_GLB_SHA256 = {
    "wall_inner_corner": "0d82759e1c2bed4590c8a00a57897c0a539a67f5565dde7b4beaa198d6a8bf32",
    "wall_outer_corner": "1dd3d6d3aabe3239bcce14c591ef203d953346ae90146cfd077e95d1c6f65505",
    "wall_t_junction": "bc5a56f27a9d4387f8ceacb4f5291c3cde9a3443eba431549e0e030423355e3b",
}


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _bpy() -> Any:
    import bpy  # type: ignore

    return bpy


def _z_up(value: tuple[float, float, float]) -> tuple[float, float, float]:
    return (value[0], value[2], value[1])


def _gltf_y_up_location_to_blender(
    value: tuple[float, float, float],
) -> tuple[float, float, float]:
    """Return Blender coordinates that export to this GLB's direct Y-up location.

    Blender's ``export_yup`` conversion maps Blender ``(x, y, z)`` to glTF
    ``(x, z, -y)``.  Visual geometry is consumed in those direct glTF/Godot
    axes, so its location must use the inverse conversion.  Authoring helpers
    remain Z-up and continue to use :func:`_z_up`.
    """

    return (value[0], -value[2], value[1])


def _temporary_visual_export_location(
    canonical_blender_location: tuple[float, float, float],
) -> tuple[float, float, float]:
    """Map a canonical saved Blender location to the temporary export location."""

    return (
        canonical_blender_location[0],
        -canonical_blender_location[1],
        canonical_blender_location[2],
    )


def _remove_object(obj: Any) -> None:
    bpy = _bpy()
    bpy.data.objects.remove(obj, do_unlink=True)


def _material_before_rebuild() -> Any:
    bpy = _bpy()
    preferred = bpy.data.materials.get("SSV0_BULKHEAD")
    if preferred is not None:
        return preferred
    for obj in bpy.data.objects:
        if obj.type == "MESH" and len(obj.data.materials) > 0:
            return obj.data.materials[0]
    raise RuntimeError("recovered source has no visual material")


def _add_ray_collision_proxies(
    spec: Any,
    root: Any,
    helpers: Any,
    ray_specs: tuple[tuple[str, tuple[float, float, float], tuple[float, float, float]], ...],
) -> list[Any]:
    """Author collision helpers from the same ray records as the visible mesh."""

    proxies: list[Any] = []
    for direction, dimensions_y_up, center_y_up in ray_specs:
        collision = create_box(
            f"CollisionRay_{direction}",
            _z_up(dimensions_y_up),
            _z_up(center_y_up),
            helpers,
        )
        collision.display_type = "WIRE"
        collision.hide_render = True
        collision.parent = root
        collision["proxy_shape"] = spec.collision_proxy_shape
        collision["nav_blocker"] = spec.nav_blocker
        collision["structural_ray_direction"] = direction.lower()
        collision["dimensions_contract_y_up"] = json.dumps(list(dimensions_y_up))
        collision["center_contract_y_up"] = json.dumps(list(center_y_up))
        proxies.append(collision)
    return proxies


def _validate_exported_world_bounds(
    glb_path: Path,
    ray_specs: tuple[tuple[str, tuple[float, float, float], tuple[float, float, float]], ...],
) -> None:
    """Reimport the GLB and prove every world-mesh ray has the intended sign."""

    bpy = _bpy()
    from mathutils import Vector  # type: ignore

    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=str(glb_path))
    if "FINISHED" not in result:
        raise RuntimeError(f"could not reimport exported GLB: {glb_path}")
    for direction, dimensions_y_up, center_y_up in ray_specs:
        obj = bpy.data.objects.get(f"VisualRay_{direction}")
        if obj is None or obj.type != "MESH":
            raise RuntimeError(f"reimported ray missing: {direction}")
        corners_z_up = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
        corners_y_up = [(corner.x, corner.z, corner.y) for corner in corners_z_up]
        actual_min = tuple(min(corner[i] for corner in corners_y_up) for i in range(3))
        actual_max = tuple(max(corner[i] for corner in corners_y_up) for i in range(3))
        expected_min = tuple(center_y_up[i] - dimensions_y_up[i] * 0.5 for i in range(3))
        expected_max = tuple(center_y_up[i] + dimensions_y_up[i] * 0.5 for i in range(3))
        for actual, expected in zip(actual_min + actual_max, expected_min + expected_max, strict=True):
            if abs(actual - expected) > 0.00001:
                raise RuntimeError(
                    f"reimported {direction} bound mismatch: "
                    f"actual={actual_min, actual_max} expected={expected_min, expected_max}"
                )
        print(
            "VERTEX_SPAN_GLTF_BOUND "
            f"ray={direction.lower()} min={actual_min} max={actual_max}"
        )


def _matrix_multiply(
    left: list[list[float]], right: list[list[float]]
) -> list[list[float]]:
    return [
        [sum(left[row][index] * right[index][column] for index in range(4)) for column in range(4)]
        for row in range(4)
    ]


def _node_matrix(node: dict[str, Any]) -> list[list[float]]:
    """Return the direct glTF Y-up transform for one scene node."""

    if "matrix" in node:
        flat = node["matrix"]
        if not isinstance(flat, list) or len(flat) != 16:
            raise RuntimeError("GLB node matrix is not a 4x4 matrix")
        return [[float(flat[column * 4 + row]) for column in range(4)] for row in range(4)]
    x, y, z, w = (float(value) for value in node.get("rotation", [0, 0, 0, 1]))
    sx, sy, sz = (float(value) for value in node.get("scale", [1, 1, 1]))
    tx, ty, tz = (float(value) for value in node.get("translation", [0, 0, 0]))
    return [
        [(1 - 2 * y * y - 2 * z * z) * sx, (2 * x * y - 2 * z * w) * sy, (2 * x * z + 2 * y * w) * sz, tx],
        [(2 * x * y + 2 * z * w) * sx, (1 - 2 * x * x - 2 * z * z) * sy, (2 * y * z - 2 * x * w) * sz, ty],
        [(2 * x * z - 2 * y * w) * sx, (2 * y * z + 2 * x * w) * sy, (1 - 2 * x * x - 2 * y * y) * sz, tz],
        [0, 0, 0, 1],
    ]


def _read_glb(glb_path: Path) -> tuple[dict[str, Any], bytes]:
    raw = glb_path.read_bytes()
    if len(raw) < 20:
        raise RuntimeError(f"GLB is truncated: {glb_path}")
    magic, version, length = struct.unpack_from("<III", raw)
    if magic != 0x46546C67 or version != 2 or length != len(raw):
        raise RuntimeError(f"GLB header is invalid: {glb_path}")
    json_length, json_kind = struct.unpack_from("<II", raw, 12)
    if json_kind != 0x4E4F534A:
        raise RuntimeError(f"GLB JSON chunk is missing: {glb_path}")
    binary_offset = 20 + json_length
    binary_length, binary_kind = struct.unpack_from("<II", raw, binary_offset)
    if binary_kind != 0x004E4942:
        raise RuntimeError(f"GLB binary chunk is missing: {glb_path}")
    document = json.loads(raw[20:binary_offset].decode("utf-8"))
    return document, raw[binary_offset + 8:binary_offset + 8 + binary_length]


def _direct_gltf_world_matrices(document: dict[str, Any]) -> dict[int, list[list[float]]]:
    nodes = document.get("nodes")
    scenes = document.get("scenes")
    if not isinstance(nodes, list) or not isinstance(scenes, list) or not scenes:
        raise RuntimeError("GLB does not contain a scene graph")
    scene_index = int(document.get("scene", 0))
    scene = scenes[scene_index]
    root_nodes = scene.get("nodes", [])
    identity = [[1.0 if row == column else 0.0 for column in range(4)] for row in range(4)]
    result: dict[int, list[list[float]]] = {}

    def visit(index: int, parent: list[list[float]]) -> None:
        if index in result:
            raise RuntimeError("GLB scene graph reuses a node")
        node = nodes[index]
        world = _matrix_multiply(parent, _node_matrix(node))
        result[index] = world
        for child in node.get("children", []):
            visit(int(child), world)

    for root_node in root_nodes:
        visit(int(root_node), identity)
    return result


def _direct_positions(
    document: dict[str, Any], binary: bytes, accessor_index: int
) -> list[tuple[float, float, float]]:
    accessor = document["accessors"][accessor_index]
    if accessor.get("componentType") != 5126 or accessor.get("type") != "VEC3":
        raise RuntimeError("GLB POSITION accessor must be float VEC3")
    view = document["bufferViews"][accessor["bufferView"]]
    offset = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    stride = int(view.get("byteStride", 12))
    return [
        struct.unpack_from("<fff", binary, offset + index * stride)
        for index in range(int(accessor["count"]))
    ]


def _transform_point(
    matrix: list[list[float]], point: tuple[float, float, float]
) -> tuple[float, float, float]:
    x, y, z = point
    return tuple(
        sum(matrix[row][column] * (x, y, z, 1.0)[column] for column in range(4))
        for row in range(3)
    )


def _validate_direct_exported_world_bounds(
    glb_path: Path,
    ray_specs: tuple[tuple[str, tuple[float, float, float], tuple[float, float, float]], ...],
) -> None:
    """Assert direct GLB node/accessor bounds in Godot's Y-up export axes.

    This deliberately does not import the GLB into Blender or apply an inverse
    axis conversion.  It reads each POSITION accessor and composes the glTF
    scene-node transforms that Godot receives, so a north-to-south Z flip fails.
    """

    document, binary = _read_glb(glb_path)
    worlds = _direct_gltf_world_matrices(document)
    expected_names = {f"VisualRay_{direction}" for direction, _, _ in ray_specs}
    mesh_nodes = [
        (index, node)
        for index, node in enumerate(document.get("nodes", []))
        if "mesh" in node
    ]
    actual_names = [str(node.get("name", "")) for _, node in mesh_nodes]
    if len(actual_names) != len(set(actual_names)) or set(actual_names) != expected_names:
        raise RuntimeError(
            f"direct GLB visual nodes mismatch: actual={actual_names} expected={sorted(expected_names)}"
        )
    for direction, dimensions, center in ray_specs:
        node_name = f"VisualRay_{direction}"
        node_index, node = next(item for item in mesh_nodes if item[1].get("name") == node_name)
        vertices: list[tuple[float, float, float]] = []
        mesh = document["meshes"][node["mesh"]]
        for primitive in mesh.get("primitives", []):
            attributes = primitive.get("attributes", {})
            if "POSITION" not in attributes:
                raise RuntimeError(f"direct GLB mesh has no POSITION accessor: {node_name}")
            vertices.extend(
                _transform_point(worlds[node_index], position)
                for position in _direct_positions(document, binary, int(attributes["POSITION"]))
            )
        if not vertices:
            raise RuntimeError(f"direct GLB mesh has no positions: {node_name}")
        actual_min = tuple(min(point[axis] for point in vertices) for axis in range(3))
        actual_max = tuple(max(point[axis] for point in vertices) for axis in range(3))
        expected_min = tuple(center[axis] - dimensions[axis] * 0.5 for axis in range(3))
        expected_max = tuple(center[axis] + dimensions[axis] * 0.5 for axis in range(3))
        if any(abs(actual - expected) > 0.00001 for actual, expected in zip(actual_min + actual_max, expected_min + expected_max)):
            raise RuntimeError(
                f"direct GLB {direction} bound mismatch: actual={actual_min, actual_max} "
                f"expected={expected_min, expected_max}"
            )
        print(
            "VERTEX_SPAN_GLTF_DIRECT_BOUND "
            f"ray={direction.lower()} min={actual_min} max={actual_max}"
        )
    print(f"VERTEX_SPAN_GLTF_DIRECT_EXPORT PASS module={glb_path.stem} rays={len(ray_specs)}")


def _rebuild_loaded_source(project_root: Path, source_root: Path, module_id: str) -> dict[str, str]:
    bpy = _bpy()
    blend_path = source_root / module_id / f"{module_id}.blend"
    record_path = source_root / module_id / f"{module_id}.source.json"
    if not blend_path.is_file():
        raise FileNotFoundError(f"recovered Blend source missing: {blend_path}")
    if not record_path.is_file():
        raise FileNotFoundError(f"recovered source record missing: {record_path}")
    recovered_record = json.loads(record_path.read_text(encoding="utf-8"))
    expected_current_glb_sha256 = str(recovered_record["source_glb"]["sha256"])
    prior_authority = recovered_record.get("authority", {})
    if prior_authority and "recovered_original_glb_sha256" not in prior_authority:
        raise RuntimeError(f"newly-authored source lacks recovered provenance: {module_id}")
    recovered_original_glb_sha256 = RECOVERED_ORIGINAL_GLB_SHA256[module_id]
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))

    spec = load_source_spec(project_root, module_id)
    root = bpy.data.objects.get(f"ModuleRoot_{module_id}")
    geometry = bpy.data.collections.get("Geometry")
    helpers = bpy.data.collections.get("AuthoringHelpers")
    if root is None or geometry is None or helpers is None:
        raise RuntimeError(f"recovered source structure is incomplete: {module_id}")
    material = _material_before_rebuild()

    for obj in list(bpy.data.objects):
        if obj.type == "MESH" or obj.name.startswith("Anchor_SOCK_"):
            _remove_object(obj)

    set_root_properties(root, spec)
    add_sockets(spec, root, helpers)
    _add_ray_collision_proxies(spec, root, helpers, MODULE_RAYS[module_id])

    visual_objects: list[Any] = []
    for direction, dimensions_y_up, center_y_up in MODULE_RAYS[module_id]:
        visual = create_box(
            f"VisualRay_{direction}",
            _z_up(dimensions_y_up),
            _z_up(center_y_up),
            geometry,
        )
        visual.parent = root
        visual["structural_ray_direction"] = direction.lower()
        visual["dimensions_contract_y_up"] = json.dumps(list(dimensions_y_up))
        visual.data.materials.append(material)
        visual_objects.append(visual)

    bpy.ops.object.select_all(action="DESELECT")
    for visual in visual_objects:
        visual.select_set(True)
    bpy.context.view_layer.objects.active = visual_objects[0]

    glb_path = (
        project_root
        / "assets/imported/structural/ship_structural_v0"
        / module_id
        / f"{module_id}.glb"
    )
    if _sha256(glb_path) != expected_current_glb_sha256:
        raise RuntimeError(f"tracked GLB no longer matches recovered authority: {module_id}")
    temporary_glb = glb_path.with_name(f".{module_id}.vertex-span.tmp.glb")
    if temporary_glb.exists():
        temporary_glb.unlink()
    canonical_locations = {visual: visual.location.copy() for visual in visual_objects}
    try:
        # Keep the saved recovered source fully Z-up: visual and collision rays
        # share the same canonical authoring positions.  Correct only the
        # selected visual objects while generating the direct glTF Y-up asset.
        for visual, canonical_location in canonical_locations.items():
            visual.location = _temporary_visual_export_location(tuple(canonical_location))
        result = bpy.ops.export_scene.gltf(
            filepath=str(temporary_glb),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
        )
        if "FINISHED" not in result or not temporary_glb.is_file():
            raise RuntimeError(f"Blender failed to export vertex-span GLB: {module_id}")
        _validate_direct_exported_world_bounds(temporary_glb, MODULE_RAYS[module_id])
        os.replace(temporary_glb, glb_path)
    finally:
        for visual, canonical_location in canonical_locations.items():
            visual.location = canonical_location

    refreshed_spec = load_source_spec(project_root, module_id)
    set_root_properties(root, refreshed_spec)
    bpy.context.scene["source_authority"] = "recovered_glb_then_new_vertex_half_span"
    bpy.context.scene["source_glb_sha256"] = refreshed_spec.source_glb_sha256
    bpy.context.scene["contract_sha256"] = refreshed_spec.contract_sha256
    _save_blend_atomically(blend_path)

    record = build_source_record(refreshed_spec, blend_path)
    record["blend_path"] = blend_path.relative_to(project_root).as_posix()
    record["contract"]["path"] = refreshed_spec.contract_path.relative_to(project_root).as_posix()
    record["source_glb"]["path"] = refreshed_spec.source_glb_path.relative_to(project_root).as_posix()
    record["authority"] = {
        "kind": "recovered_then_newly_authored",
        "recovered_from": refreshed_spec.source_glb_path.relative_to(project_root).as_posix(),
        "recovered_original_glb_sha256": recovered_original_glb_sha256,
        "authored_glb_sha256": refreshed_spec.source_glb_sha256,
        "historical_original_available": False,
        "geometry_contract": "vertex_owned_2m_rays",
        "export_coordinate_conversion": {
            "saved_source": "contract[x,y,z]->blender[x,z,y]",
            "selected_visual_export": "blender[x,y,z]->gltf[x,z,-y]",
            "temporary_visual_location": "contract[x,y,z]->blender[x,-z,y]",
            "direct_validation_axes": "gltf_y_up_godot[x,y,z]",
        },
        "rays": [
            {
                "direction": direction.lower(),
                "dimensions_m": list(dimensions),
                "center_m": list(center),
            }
            for direction, dimensions, center in MODULE_RAYS[module_id]
        ],
    }
    record_path.write_bytes(canonical_json(record))
    return {
        "module_id": module_id,
        "blend": blend_path.as_posix(),
        "glb": glb_path.as_posix(),
        "source_record": record_path.as_posix(),
    }


def _arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--module", action="append", required=True, choices=sorted(MODULE_RAYS))
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    raw = list(sys.argv[sys.argv.index("--") + 1 :]) if argv is None and "--" in sys.argv else (argv or [])
    args = _arguments(raw)
    project_root = args.project_root.resolve()
    source_root = args.source_root.resolve()
    if project_root not in source_root.parents:
        raise ValueError("source root must remain inside the owned project worktree")
    rows = [_rebuild_loaded_source(project_root, source_root, module) for module in args.module]
    print("VERTEX_SPAN_SOURCES_REBUILT " + json.dumps(rows, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
