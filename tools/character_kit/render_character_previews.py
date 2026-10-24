#!/usr/bin/env python3
"""Blender-only preview renderer for the ``survivor_v1`` kit (round-trip proof).

Re-imports the exported GLB (so the renders show what Godot will receive, not
the authoring scene), then renders with Cycles on the CPU:

- ``turnaround_<variant>.png``: front / side / back / three-quarter close-ups
  for base, hardsuit+EVA pack, and fieldpack+belt variants.
- ``poses_contact_sheet.png``: one frame from each animation clip.
- ``gameplay_distance_iso.png``: the character on a 4 m grid at the game's
  locked-iso camera direction and orthographic size (22 m vertical), so the
  on-screen footprint matches the real HUD-scale readability.

    blender --background --factory-startup --python tools/character_kit/render_character_previews.py -- \
        --project-root . --glb assets/imported/characters/survivor_v1/survivor_v1.glb \
        --out artifacts/validation-previews/characters/survivor_v1 [--samples 24]
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path


def _args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--samples", type=int, default=24)
    parser.add_argument("--size", type=int, default=512)
    return parser.parse_args(argv)


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    args = _args(argv)
    project_root = Path(args.project_root).resolve()
    sys.path.insert(0, str(project_root))

    import bpy
    from mathutils import Vector

    from tools.character_kit import character_kit_spec as spec

    out_dir = project_root / args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = args.samples
    scene.cycles.use_denoising = False
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world = bpy.data.worlds.new("World")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.045, 0.05, 0.06, 1.0)
    bg.inputs[1].default_value = 1.0

    bpy.ops.import_scene.gltf(filepath=str(project_root / args.glb))
    armature = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = {o.name: o for o in bpy.data.objects if o.type == "MESH"}

    _lights(bpy)
    floor = _floor_grid(bpy, bpy.data.materials)
    camera = bpy.data.objects.new("PreviewCamera", bpy.data.cameras.new("PreviewCamera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = "ORTHO"

    variants = {
        "base": [],
        "hardsuit_eva": ["Equip_Hardsuit_", "Equip_Helmet", "Equip_EVABackpack"],
        "fieldpack_belt": ["Equip_FieldPack", "Equip_ToolBelt"],
    }

    def apply_variant(prefixes):
        for name, obj in meshes.items():
            if name.startswith("Equip_"):
                visible = any(name.startswith(p) for p in prefixes)
                obj.hide_render = not visible
                obj.hide_viewport = not visible

    def shoot(path: Path, location, target, ortho_scale, res):
        camera.location = location
        direction = Vector(target) - Vector(location)
        camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = ortho_scale
        scene.render.resolution_x, scene.render.resolution_y = res
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)

    half = 1.0
    target = (0.0, 0.0, 0.9)
    views = {
        "front": (0.0, -6.0, 0.9),
        "three_quarter": (4.2, -4.2, 2.6),
        "side": (6.0, 0.0, 0.9),
        "back": (0.0, 6.0, 0.9),
    }
    if armature.animation_data is not None:
        for track in armature.animation_data.nla_tracks:
            track.mute = True
        armature.animation_data.action = None
    _reset_pose(armature)
    scene.frame_set(1)
    floor.hide_render = True
    for variant, prefixes in variants.items():
        apply_variant(prefixes)
        tiles = []
        for view, loc in views.items():
            tile = out_dir / f"_tile_{variant}_{view}.png"
            shoot(tile, loc, target, 2.3 * half, (args.size, args.size))
            tiles.append(tile)
        _contact_sheet(bpy, tiles, out_dir / f"turnaround_{variant}.png", columns=4)

    # Pose sheet: one representative frame per clip (hardsuit variant). The
    # importer names actions "<clip>_<rig>" but keeps the clip name on the NLA
    # track, so resolve through the track and mute the NLA stack while posing.
    apply_variant(variants["hardsuit_eva"])
    tiles = []
    anim_data = armature.animation_data
    track_actions = {}
    if anim_data is not None:
        for track in anim_data.nla_tracks:
            track.mute = True
            if track.strips:
                track_actions[track.name] = track.strips[0].action
    for clip in spec.ANIMATION_NAMES:
        action = track_actions.get(clip) or bpy.data.actions.get(clip)
        if action is None:
            continue
        armature.animation_data.action = action
        frames = int(spec.ANIMATION_CLIPS[clip]["frames"])
        frame = 1 + frames // 3 if spec.ANIMATION_CLIPS[clip]["loop"] else frames
        scene.frame_set(frame)
        tile = out_dir / f"_tile_pose_{clip}.png"
        shoot(tile, (4.2, -4.2, 2.6), (0.0, 0.0, 0.8), 2.6, (args.size, args.size))
        tiles.append(tile)
    _contact_sheet(bpy, tiles, out_dir / "poses_contact_sheet.png", columns=4)
    armature.animation_data.action = None
    _reset_pose(armature)

    # Gameplay distance: Godot IsoCameraRig offset (16, 18, 16) Y-up -> Blender
    # (16, -16, 18) Z-up, orthographic size 22 m vertical at 1280x720.
    floor.hide_render = False
    apply_variant(variants["hardsuit_eva"])
    aspect = 1280.0 / 720.0
    shoot(out_dir / "gameplay_distance_iso.png", (16.0, -16.0, 18.0), (0.0, 0.0, 0.0), 22.0 * aspect, (1280, 720))
    # A closer "recommended" framing (ortho size 12 m) for comparison.
    shoot(out_dir / "gameplay_distance_iso_size12.png", (16.0, -16.0, 18.0), (0.0, 0.0, 0.0), 12.0 * aspect, (1280, 720))

    for tile in out_dir.glob("_tile_*.png"):
        tile.unlink()
    print(f"CHARACTER PREVIEW RENDER OK out={out_dir}")
    return 0


def _reset_pose(armature):
    for pbone in armature.pose.bones:
        pbone.rotation_euler = (0.0, 0.0, 0.0)
        pbone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pbone.location = (0.0, 0.0, 0.0)


def _lights(bpy):
    scene = bpy.context.scene
    key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
    key.data.energy = 3.0
    key.data.angle = math.radians(8.0)
    key.rotation_euler = (math.radians(50.0), math.radians(-15.0), math.radians(35.0))
    scene.collection.objects.link(key)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "SUN"))
    fill.data.energy = 0.9
    fill.data.color = (0.75, 0.85, 1.0)
    fill.rotation_euler = (math.radians(60.0), math.radians(20.0), math.radians(-120.0))
    scene.collection.objects.link(fill)


def _floor_grid(bpy, materials):
    """A 12 m x 12 m floor with 4 m cell lines so the gameplay render shows
    the character against the CELL_SIZE grid."""
    import bmesh

    mat = materials.new("PreviewFloor")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.16, 0.17, 0.18, 1.0)
    mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    line = materials.new("PreviewGridLine")
    line.use_nodes = True
    line.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.44, 0.40, 1.0)

    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6.0)
    mesh = bpy.data.meshes.new("PreviewFloor")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    floor = bpy.data.objects.new("PreviewFloor", mesh)
    floor.location = (0.0, 0.0, -0.01)
    bpy.context.scene.collection.objects.link(floor)

    lines = bmesh.new()
    for i in range(-1, 2):
        for axis in ("x", "y"):
            tmp = bmesh.new()
            size = (0.03, 12.0, 0.002) if axis == "x" else (12.0, 0.03, 0.002)
            bmesh.ops.create_cube(tmp, size=1.0)
            bmesh.ops.scale(tmp, vec=size, verts=tmp.verts)
            offset = (i * 4.0 + 2.0, 0.0, 0.0) if axis == "x" else (0.0, i * 4.0 + 2.0, 0.0)
            bmesh.ops.translate(tmp, vec=offset, verts=tmp.verts)
            tmp_mesh = bpy.data.meshes.new("_line")
            tmp.to_mesh(tmp_mesh)
            lines.from_mesh(tmp_mesh)
            bpy.data.meshes.remove(tmp_mesh)
            tmp.free()
    line_mesh = bpy.data.meshes.new("PreviewGridLines")
    lines.to_mesh(line_mesh)
    lines.free()
    line_mesh.materials.append(line)
    line_obj = bpy.data.objects.new("PreviewGridLines", line_mesh)
    line_obj.parent = floor
    bpy.context.scene.collection.objects.link(line_obj)
    return floor


def _contact_sheet(bpy, tiles, out_path: Path, columns: int) -> None:
    """Compose rendered tiles into one PNG using Blender's image pixel API."""
    images = [bpy.data.images.load(str(t)) for t in tiles]
    if not images:
        return
    w, h = images[0].size
    rows = (len(images) + columns - 1) // columns
    sheet = bpy.data.images.new("ContactSheet", width=w * columns, height=h * rows, alpha=True)
    buffer = [0.0] * (w * columns * h * rows * 4)
    for index, image in enumerate(images):
        px = list(image.pixels)
        col = index % columns
        row = rows - 1 - index // columns
        for y in range(h):
            src = y * w * 4
            dst = ((row * h + y) * (w * columns) + col * w) * 4
            buffer[dst : dst + w * 4] = px[src : src + w * 4]
    sheet.pixels = buffer
    sheet.filepath_raw = str(out_path)
    sheet.file_format = "PNG"
    sheet.save()
    for image in images:
        bpy.data.images.remove(image)
    bpy.data.images.remove(sheet)


if __name__ == "__main__":
    sys.exit(main())
