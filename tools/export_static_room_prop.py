"""Export the tagged static room-kit collection as a normalized Y-up GLB."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct
import sys
from typing import Any, Callable, Iterable

import bpy
from mathutils import Matrix


_HELPER_PREFIXES = ("anchor", "collision", "socket", "helper")


def _source_path(value: Path) -> Path:
    value = Path(value)
    if value.suffix.lower() != ".blend":
        raise RuntimeError("expected .blend source")
    if value.is_symlink():
        raise RuntimeError("source must not be a symlink")
    try:
        resolved = value.resolve(strict=True)
    except FileNotFoundError as exc:
        raise RuntimeError(f"missing source: {value}") from exc
    if not resolved.is_file():
        raise RuntimeError(f"source is not a file: {value}")
    return resolved


def _output_path(value: Path) -> Path:
    value = Path(value).absolute()
    if value.suffix.lower() != ".glb":
        raise RuntimeError("expected .glb output")
    if value.exists() or value.is_symlink():
        raise RuntimeError("output exists; choose a fresh revision")
    return value


def _finite_matrix(matrix: Matrix) -> bool:
    return all(math.isfinite(float(component)) for row in matrix for component in row)


def _validate_parent_chain(obj: Any) -> None:
    parent = obj.parent
    while parent is not None:
        if parent.type == "ARMATURE":
            raise RuntimeError(f"armature parent not supported: {obj.name}")
        if parent.animation_data is not None or parent.constraints:
            raise RuntimeError(f"animated/dynamic parent not supported: {obj.name}")
        parent = parent.parent


def _validate_source_objects(objects: Iterable[Any]) -> list[Any]:
    objects = list(objects)
    if not objects:
        raise RuntimeError("Export_Static must contain at least one mesh")
    for obj in objects:
        if obj.type != "MESH":
            raise RuntimeError(f"Export_Static must contain meshes only: {obj.name}")
        if obj.name.lower().startswith(_HELPER_PREFIXES):
            raise RuntimeError(f"helper in Export_Static: {obj.name}")
        if obj.animation_data is not None or obj.data.animation_data is not None:
            raise RuntimeError(f"animations not supported: {obj.name}")
        if obj.constraints:
            raise RuntimeError(f"dynamic constraints not supported: {obj.name}")
        _validate_parent_chain(obj)
        if obj.data.shape_keys is not None:
            raise RuntimeError(f"morph targets not supported: {obj.name}")
        if any(modifier.type == "ARMATURE" for modifier in obj.modifiers):
            raise RuntimeError(f"armature modifiers not supported: {obj.name}")
        if not _finite_matrix(obj.matrix_world):
            raise RuntimeError(f"non-finite transform: {obj.name}")
        if any(float(scale) <= 0.0 for scale in obj.scale):
            raise RuntimeError(f"repair nonpositive scales before export: {obj.name}")
        if obj.matrix_world.to_3x3().determinant() <= 0.0:
            raise RuntimeError(f"repair negative/zero scales before export: {obj.name}")
    scene = bpy.context.scene
    if scene.animation_data is not None:
        raise RuntimeError("scene animation is not supported")
    if any(action.users for action in bpy.data.actions):
        raise RuntimeError("animation actions are not supported")
    return objects


def _read_exported_glb(path: Path) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise RuntimeError(f"unable to read exported GLB: {exc}") from exc
    if len(raw) < 20 or len(raw) % 4:
        raise RuntimeError("exported GLB is too small or unaligned")
    magic, version, declared_length = struct.unpack_from("<4sII", raw, 0)
    if magic != b"glTF" or version != 2 or declared_length != len(raw):
        raise RuntimeError("exported GLB has an invalid header")

    offset = 12
    json_chunk: bytes | None = None
    binary_chunk: bytes | None = None
    while offset < declared_length:
        if declared_length - offset < 8:
            raise RuntimeError("exported GLB has a truncated chunk header")
        chunk_length, chunk_type = struct.unpack_from("<I4s", raw, offset)
        if chunk_length % 4:
            raise RuntimeError("exported GLB has an unaligned chunk")
        start = offset + 8
        end = start + chunk_length
        if end > declared_length:
            raise RuntimeError("exported GLB has a truncated chunk")
        chunk = raw[start:end]
        if offset == 12:
            if chunk_type != b"JSON":
                raise RuntimeError("exported GLB must start with a JSON chunk")
            json_chunk = chunk
        elif chunk_type == b"JSON":
            raise RuntimeError("exported GLB has duplicate JSON chunks")
        elif chunk_type == bytes((66, 73, 78, 0)):
            if binary_chunk is not None:
                raise RuntimeError("exported GLB has duplicate BIN chunks")
            binary_chunk = chunk
        offset = end
    if offset != declared_length or json_chunk is None or binary_chunk is None:
        raise RuntimeError("exported GLB is missing its JSON or BIN chunk")

    try:
        text = json_chunk.decode("utf-8")
        decoder = json.JSONDecoder()
        document, end = decoder.raw_decode(text)
        if any(character != " " for character in text[end:]):
            raise ValueError("invalid JSON padding")
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise RuntimeError("exported GLB has invalid JSON") from exc
    if not isinstance(document, dict):
        raise RuntimeError("exported GLB JSON is not an object")
    asset = document.get("asset")
    if not isinstance(asset, dict) or asset.get("version") != "2.0":
        raise RuntimeError("exported GLB is not glTF 2.0")
    buffers = document.get("buffers")
    if not isinstance(buffers, list) or not buffers or not isinstance(buffers[0], dict):
        raise RuntimeError("exported GLB has no buffer declaration")
    byte_length = buffers[0].get("byteLength")
    if not isinstance(byte_length, int) or isinstance(byte_length, bool) or byte_length < 0 or byte_length > len(binary_chunk):
        raise RuntimeError("exported GLB has an invalid BIN length")
    if any(binary_chunk[byte_length:]):
        raise RuntimeError("exported GLB has nonzero BIN padding")
    if not document.get("nodes") or not document.get("meshes"):
        raise RuntimeError("exported GLB contains no mesh scene")
    if document.get("skins") or document.get("animations"):
        raise RuntimeError("exported GLB contains unsupported rigging or animation")
    if any(isinstance(item, dict) and item.get("uri") for item in buffers):
        raise RuntimeError("exported GLB contains an external buffer")
    if any(isinstance(item, dict) and item.get("uri") for item in document.get("images", [])):
        raise RuntimeError("exported GLB contains an external image")
    return document


def export_static(
    source: Path,
    output: Path,
    *,
    export_operator: Callable[..., Any] | None = None,
) -> dict[str, Any]:
    """Export only ``Export_Static`` while leaving the opened source unsaved."""
    source = _source_path(source)
    output = _output_path(output)
    baked: list[Any] = []
    baked_collection = None
    succeeded = False
    try:
        open_result = bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False, use_scripts=False)
        if "FINISHED" not in open_result:
            raise RuntimeError(f"opening source failed: {sorted(open_result)}")
        collection = bpy.data.collections.get("Export_Static")
        if collection is None:
            raise RuntimeError("missing Export_Static collection")
        originals = _validate_source_objects(collection.all_objects)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        baked_collection = bpy.data.collections.new("RoomKitV2_Baked")
        bpy.context.scene.collection.children.link(baked_collection)
        for original in originals:
            evaluated = original.evaluated_get(depsgraph)
            mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
            if mesh is None:
                raise RuntimeError(f"evaluated mesh missing: {original.name}")
            if not mesh.uv_layers:
                raise RuntimeError(f"missing UVMap: {original.name}")
            mesh.transform(evaluated.matrix_world)
            mesh.update()
            baked_object = bpy.data.objects.new(f"V2_{original.name}", mesh)
            baked_collection.objects.link(baked_object)
            baked_object.matrix_world = Matrix.Identity(4)
            baked.append(baked_object)

        bpy.ops.object.select_all(action="DESELECT")
        for baked_object in baked:
            baked_object.select_set(True)
        bpy.context.view_layer.objects.active = baked[0]
        bpy.context.view_layer.update()
        output.parent.mkdir(parents=True, exist_ok=True)
        operator = export_operator or bpy.ops.export_scene.gltf
        result = operator(
            filepath=str(output),
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=True,
            export_materials="EXPORT",
            export_animations=False,
            export_cameras=False,
            export_lights=False,
            export_extras=False,
        )
        if not result or "FINISHED" not in result:
            raise RuntimeError(f"static GLB export cancelled: {sorted(result or ())}")
        document = _read_exported_glb(output)
        succeeded = True
        print(
            "ROOM_KIT_STATIC_EXPORT_PASS "
            + json.dumps(
                {"source": str(source), "output": str(output), "meshes": len(baked), "nodes": len(document["nodes"])},
                sort_keys=True,
            )
        )
        return document
    finally:
        if not succeeded and (output.is_file() or output.is_symlink()):
            try:
                output.unlink()
            except OSError:
                pass
        for baked_object in baked:
            if baked_object.name in bpy.data.objects:
                bpy.data.objects.remove(baked_object, do_unlink=True)
        if baked_collection is not None and baked_collection.name in bpy.data.collections:
            bpy.data.collections.remove(baked_collection)


def _arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args(argv)


def main() -> None:
    separator = sys.argv.index("--") if "--" in sys.argv else 0
    args = _arguments(sys.argv[separator + 1 :] if separator else sys.argv[1:])
    export_static(args.source, args.output)


if __name__ == "__main__":
    main()
