#!/usr/bin/env python3
"""Apply a tile PNG to a structural module GLB in Blender.

Usage::

    blender --background --python tools/apply_tile_texture.py -- \
        --module floor_1x1 \
        --texture assets/tiles/synaptic_sea/floor_1x1_seamless.png \
        --output assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1_textured.glb

``--module`` accepts either a structural module ID (resolved under
``assets/imported/structural/ship_structural_v0``) or a path to a GLB.  Existing
UV maps are preserved; meshes without UVs receive a Blender Smart Project UV
unwrap before the textured GLB is exported.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys
from typing import Any, Iterable, Sequence

try:
    import bpy as _bpy  # type: ignore[import-not-found]
except ModuleNotFoundError:  # Allows ``python3 ... --help`` outside Blender.
    _bpy = None

bpy: Any = _bpy


PROJECT_ROOT = Path(__file__).resolve().parents[1]
STRUCTURAL_MODULE_ROOT = (
    PROJECT_ROOT / "assets" / "imported" / "structural" / "ship_structural_v0"
)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse arguments after Blender's own command-line options."""

    blender_args = list(sys.argv if argv is None else argv)
    if "--" in blender_args:
        blender_args = blender_args[blender_args.index("--") + 1 :]
    elif argv is None:
        # When called directly by Python, sys.argv includes the script name.
        blender_args = blender_args[1:]

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--module",
        required=True,
        help="module ID such as floor_1x1, or a path to a source GLB",
    )
    parser.add_argument("--texture", required=True, help="texture PNG path")
    parser.add_argument("--output", required=True, help="destination textured GLB path")
    return parser.parse_args(blender_args)


def resolve_project_path(value: str | Path) -> Path:
    """Resolve relative paths against the Synaptic Sea project root."""

    path = Path(value).expanduser()
    return path if path.is_absolute() else PROJECT_ROOT / path


def resolve_module_path(module: str) -> tuple[str, Path]:
    """Return a stable module ID and source GLB path."""

    candidate = Path(module).expanduser()
    looks_like_path = candidate.suffix.lower() == ".glb" or len(candidate.parts) > 1
    if looks_like_path:
        path = resolve_project_path(candidate)
        return path.stem, path

    module_id = candidate.name
    return module_id, STRUCTURAL_MODULE_ROOT / module_id / f"{module_id}.glb"


def require_blender() -> None:
    """Fail clearly when a Blender-only operation is attempted with Python."""

    if bpy is None:
        raise RuntimeError(
            "This script must run inside Blender. Use: blender --background --python "
            "tools/apply_tile_texture.py -- --module ... --texture ... --output ..."
        )


def clear_scene() -> None:
    """Remove all imported/default objects from the current Blender scene."""

    require_blender()
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def mesh_objects() -> list:
    """Return all mesh objects in the current scene."""

    require_blender()
    return [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]


def ensure_uv_maps(objects: Iterable) -> None:
    """Smart-project only meshes that do not already have UV coordinates."""

    require_blender()
    for obj in objects:
        if obj.data.uv_layers or not obj.data.polygons:
            continue

        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        try:
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="SELECT")
            bpy.ops.uv.smart_project(island_margin=0.03)
        finally:
            if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
                bpy.ops.object.mode_set(mode="OBJECT")
            obj.select_set(False)

        print(f"[uv] smart project: {obj.name}", flush=True)


def load_texture(texture_path: Path):
    """Load and pack the PNG so it is embedded in the exported GLB."""

    require_blender()
    try:
        image = bpy.data.images.load(str(texture_path), check_existing=True)
    except RuntimeError as exc:
        raise RuntimeError(f"Unable to load texture PNG {texture_path}: {exc}") from exc

    # Generated tile art is color data rather than a normal/roughness map.
    try:
        image.colorspace_settings.name = "sRGB"
    except (AttributeError, TypeError):
        pass
    image.pack()
    return image


def create_textured_material(module_id: str, image):
    """Create a Principled BSDF material with ``image`` as Base Color."""

    require_blender()
    material = bpy.data.materials.new(name=f"{module_id}_TileTexture")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    output.name = "Material Output"
    output.location = (420, 0)

    principled = nodes.new("ShaderNodeBsdfPrincipled")
    principled.name = "Principled BSDF"
    principled.location = (100, 0)
    roughness = principled.inputs.get("Roughness")
    if roughness is not None:
        roughness.default_value = 0.8

    texture = nodes.new("ShaderNodeTexImage")
    texture.name = f"{module_id}_BaseColorTexture"
    texture.image = image
    texture.interpolation = "Linear"
    texture.location = (-220, 0)

    links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    links.new(principled.outputs["BSDF"], output.inputs["Surface"])
    return material


def assign_material(objects: Iterable, material) -> None:
    """Replace each mesh's material slots with the generated tile material."""

    require_blender()
    for obj in objects:
        obj.data.materials.clear()
        obj.data.materials.append(material)


def export_glb(output_path: Path) -> None:
    """Export the current scene as a GLB with embedded textures."""

    require_blender()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    result = bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        export_image_format="AUTO",
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_apply=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"Blender GLB export failed: {result}")
    if not output_path.is_file() or output_path.stat().st_size <= 0:
        raise RuntimeError(f"Blender did not create a non-empty output GLB: {output_path}")


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    require_blender()

    module_id, module_path = resolve_module_path(args.module)
    texture_path = resolve_project_path(args.texture)
    output_path = resolve_project_path(args.output)
    if not module_path.is_file():
        raise FileNotFoundError(f"Module GLB does not exist: {module_path}")
    if not texture_path.is_file():
        raise FileNotFoundError(f"Texture PNG does not exist: {texture_path}")

    print(f"[module] {module_id}", flush=True)
    print(f"[input]  {module_path}", flush=True)
    print(f"[texture] {texture_path}", flush=True)
    print(f"[output] {output_path}", flush=True)

    clear_scene()
    result = bpy.ops.import_scene.gltf(filepath=str(module_path))
    if "FINISHED" not in result:
        raise RuntimeError(f"GLB import failed for {module_path}: {result}")

    objects = mesh_objects()
    if not objects:
        raise RuntimeError(f"GLB import produced no mesh objects: {module_path}")
    ensure_uv_maps(objects)

    image = load_texture(texture_path)
    material = create_textured_material(module_id, image)
    assign_material(objects, material)
    export_glb(output_path)
    print(f"[done] textured GLB: {output_path}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
