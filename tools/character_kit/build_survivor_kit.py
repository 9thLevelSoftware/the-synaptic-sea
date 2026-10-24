#!/usr/bin/env python3
"""Blender-only builder for the ``survivor_v1`` procedural character kit.

Run inside Blender (headless):

    blender --background --factory-startup --python tools/character_kit/build_survivor_kit.py -- \
        --project-root . [--out assets/imported/characters/survivor_v1] [--blend <path>]

The script builds a "Project Zomboid, but a bit more detailed" low-poly
survivor from bevelled boxes, 8-segment cylinders and coarse spheres, rigs it
to a 20-bone deform skeleton (rigid per-part binding, PZ style), authors a
small set of procedurally keyframed animation clips on NLA tracks, builds the
modular equipment meshes that the live equipment slots toggle, and exports one
normalized GLB (Y-up, meters, pivot at the floor center, +Z forward).

Everything is derived from ``tools/character_kit/character_kit_spec.py`` so the
GLB validator and the Godot smoke check the same contract this script builds
to. Nothing here touches ``scenes/wrappers``, ``data/combat`` or any gameplay
data: collision, navigation, and gameplay bindings stay owned by Godot
(ADR-0052 / ADR-0058 authority split).
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path


def _parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--out", default=None, help="runtime kit directory (default: spec RUNTIME_ROOT)")
    parser.add_argument("--blend", default=None, help="optional .blend master to save beside the staging output")
    parser.add_argument("--skip-tools", action="store_true", help="do not build the handheld tool GLBs")
    return parser.parse_args(argv)


def main() -> int:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    args = _parse_args(argv)
    project_root = Path(args.project_root).resolve()
    sys.path.insert(0, str(project_root))

    import bpy  # noqa: WPS433 (Blender-only import at the command boundary)

    from tools.character_kit import character_kit_spec as spec
    from tools.character_kit.bpy_lowpoly import (
        MeshBuilder,
        make_materials,
        new_collection,
        reset_scene,
    )
    from tools.character_kit.survivor_animation import author_animations

    out_dir = project_root / (args.out if args.out else spec.RUNTIME_ROOT)
    out_dir.mkdir(parents=True, exist_ok=True)

    reset_scene()
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    materials = make_materials(spec.MATERIALS)
    kit_collection = new_collection(spec.KIT_ID)

    armature = _build_armature(bpy, spec, kit_collection)
    _build_body(spec, materials, armature, kit_collection, MeshBuilder)
    _build_equipment(spec, materials, armature, kit_collection, MeshBuilder)
    _build_sockets(bpy, spec, armature, kit_collection)
    author_animations(bpy, armature, spec)

    glb_path = out_dir / spec.GLB_LEAF
    _export_glb(bpy, glb_path)
    try:
        relative_glb = glb_path.resolve().relative_to(project_root).as_posix()
    except ValueError:
        relative_glb = glb_path.as_posix()
    spec.write_manifest(out_dir / spec.MANIFEST_LEAF, glb_path=relative_glb)

    if args.blend:
        blend_path = Path(args.blend)
        blend_path.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    if not args.skip_tools:
        from tools.character_kit.build_handheld_tools import build_all_tools

        build_all_tools(bpy, project_root, materials_spec=spec.MATERIALS)

    print(f"CHARACTER KIT BUILD OK kit={spec.KIT_ID} glb={glb_path}")
    return 0


# --------------------------------------------------------------------------- rig


# Blender authoring space: Z-up, character faces -Y. Bone (head, tail) in meters.
def _bone_table(spec):
    L, R = 1.0, -1.0
    table = {
        "root": ((0.0, 0.0, 0.0), (0.0, 0.0, 0.12)),
        "hips": ((0.0, 0.0, 0.90), (0.0, 0.0, 1.02)),
        "spine": ((0.0, 0.0, 1.02), (0.0, 0.0, 1.20)),
        "chest": ((0.0, 0.0, 1.20), (0.0, 0.0, 1.42)),
        "neck": ((0.0, 0.0, 1.42), (0.0, 0.0, 1.50)),
        "head": ((0.0, 0.0, 1.50), (0.0, 0.0, 1.75)),
    }
    for side, sign in (("L", L), ("R", R)):
        x_arm = 0.235 * sign
        x_leg = 0.10 * sign
        table[f"shoulder_{side}"] = ((0.06 * sign, 0.0, 1.40), (x_arm, 0.0, 1.38))
        table[f"upper_arm_{side}"] = ((x_arm, 0.0, 1.38), (x_arm, 0.0, 1.10))
        table[f"forearm_{side}"] = ((x_arm, 0.0, 1.10), (x_arm, 0.0, 0.84))
        table[f"hand_{side}"] = ((x_arm, 0.0, 0.84), (x_arm, 0.0, 0.67))
        table[f"thigh_{side}"] = ((x_leg, 0.0, 0.90), (x_leg, 0.0, 0.50))
        table[f"shin_{side}"] = ((x_leg, 0.0, 0.50), (x_leg, 0.0, 0.12))
        table[f"foot_{side}"] = ((x_leg, 0.0, 0.12), (x_leg, -0.17, 0.02))
    missing = set(spec.BONE_NAMES) - set(table)
    if missing:
        raise RuntimeError(f"bone table missing {sorted(missing)}")
    return table


def _build_armature(bpy, spec, collection):
    arm_data = bpy.data.armatures.new("SurvivorRig")
    arm_data.display_type = "STICK"
    armature = bpy.data.objects.new("SurvivorRig", arm_data)
    collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    table = _bone_table(spec)
    edit_bones = {}
    for name, parent in spec.BONE_HIERARCHY:
        head, tail = table[name]
        bone = arm_data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.roll = 0.0
        bone.use_deform = True
        bone.use_connect = False
        edit_bones[name] = bone
    for name, parent in spec.BONE_HIERARCHY:
        if parent:
            edit_bones[name].parent = edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)
    return armature


def _build_sockets(bpy, spec, armature, collection):
    # Sockets are empties parented to bones. In bone-parent space the origin is
    # the bone TAIL and +Y points from head to tail, so offsets are expressed
    # back along -Y toward the joint.
    offsets = {
        "Socket_HandR": (0.0, -0.085, 0.0),
        "Socket_HandL": (0.0, -0.085, 0.0),
        "Socket_Back": (0.0, -0.11, -0.16),
        "Socket_Head": (0.0, -0.05, 0.0),
    }
    for name, bone in spec.SOCKETS.items():
        empty = bpy.data.objects.new(name, None)
        empty.empty_display_type = "ARROWS"
        empty.empty_display_size = 0.08
        collection.objects.link(empty)
        empty.parent = armature
        empty.parent_type = "BONE"
        empty.parent_bone = bone
        empty.location = offsets.get(name, (0.0, 0.0, 0.0))


# -------------------------------------------------------------------------- body


def _build_body(spec, mats, armature, collection, MeshBuilder):
    fabric, skin, boot, strap = mats["MAT_SuitFabric"], mats["MAT_Skin"], mats["MAT_Boot"], mats["MAT_Strap"]
    metal, accent = mats["MAT_Metal"], mats["MAT_ClassAccent"]

    def part(name):
        return MeshBuilder(name, bone=spec.BODY_PARTS[name], armature=armature, collection=collection)

    # Head: bevelled box with a slightly narrower crown, dark cropped hair cap,
    # and a shallow face plane so the front reads at iso distance.
    b = part("Body_Head")
    b.box((0.20, 0.22, 0.23), (0.0, 0.0, 1.625), skin, bevel=0.035, taper_top=(0.92, 0.9))
    b.box((0.205, 0.225, 0.06), (0.0, 0.01, 1.73), strap, bevel=0.03, taper_top=(0.8, 0.8))
    b.box((0.12, 0.012, 0.035), (0.0, -0.112, 1.615), skin, bevel=0.0)  # shallow nose/brow step
    b.finish()

    b = part("Body_Neck")
    b.cylinder(0.052, 0.056, 0.10, (0.0, 0.0, 1.455), skin, segments=8)
    b.finish()

    # Chest: jumpsuit torso with collar and two chest pockets.
    b = part("Body_Chest")
    b.box((0.40, 0.24, 0.24), (0.0, 0.0, 1.31), fabric, bevel=0.035, taper_top=(1.08, 1.0))
    b.cylinder(0.085, 0.09, 0.03, (0.0, 0.0, 1.435), fabric, segments=8)
    for sx in (-1.0, 1.0):
        b.box((0.08, 0.02, 0.07), (0.10 * sx, -0.128, 1.30), strap, bevel=0.0)
    b.finish()

    b = part("Body_Spine")
    b.box((0.35, 0.215, 0.19), (0.0, 0.0, 1.11), fabric, bevel=0.03)
    b.finish()

    b = part("Body_Pelvis")
    b.box((0.36, 0.225, 0.17), (0.0, 0.0, 0.94), fabric, bevel=0.03)
    b.box((0.372, 0.235, 0.04), (0.0, 0.0, 0.99), strap, bevel=0.005)  # waistband
    b.box((0.05, 0.03, 0.035), (0.0, -0.125, 0.99), metal, bevel=0.0)  # buckle
    b.finish()

    # Class accent: a chest patch the runtime can recolor per class.
    b = part("Body_ClassAccent")
    b.box((0.17, 0.012, 0.05), (0.0, -0.127, 1.385), accent, bevel=0.0)
    for sx in (-1.0, 1.0):
        b.box((0.09, 0.26, 0.014), (0.165 * sx, 0.0, 1.422), accent, bevel=0.0)  # shoulder stripes
    b.finish()

    for side, sx in (("L", 1.0), ("R", -1.0)):
        x_arm = 0.235 * sx
        b = part(f"Body_UpperArm_{side}")
        b.sphere(0.072, (x_arm, 0.0, 1.375), fabric)
        b.cylinder(0.064, 0.056, 0.28, (x_arm, 0.0, 1.24), fabric)
        b.finish()

        b = part(f"Body_Forearm_{side}")
        b.sphere(0.058, (x_arm, 0.0, 1.10), fabric)
        b.cylinder(0.056, 0.048, 0.24, (x_arm, 0.0, 0.975), fabric)
        b.cylinder(0.052, 0.052, 0.03, (x_arm, 0.0, 0.855), strap)  # glove cuff
        b.finish()

        # Gloved mitten hand with a thumb wedge on the inner side.
        b = part(f"Body_Hand_{side}")
        b.box((0.075, 0.055, 0.16), (x_arm, 0.0, 0.76), strap, bevel=0.015, taper_top=(1.0, 1.0))
        b.box((0.03, 0.03, 0.065), (x_arm - 0.045 * sx, -0.012, 0.79), strap, bevel=0.008)
        b.finish()

        x_leg = 0.10 * sx
        b = part(f"Body_Thigh_{side}")
        b.sphere(0.088, (x_leg, 0.0, 0.885), fabric)
        b.cylinder(0.086, 0.074, 0.40, (x_leg, 0.0, 0.70), fabric)
        b.finish()

        b = part(f"Body_Shin_{side}")
        b.sphere(0.074, (x_leg, 0.0, 0.50), fabric)
        b.cylinder(0.072, 0.062, 0.36, (x_leg, 0.0, 0.31), fabric)
        b.finish()

        # Boot: toe box forward (-Y in Blender == +Z forward in glTF).
        b = part(f"Body_Boot_{side}")
        b.box((0.12, 0.28, 0.12), (x_leg, -0.05, 0.06), boot, bevel=0.02, taper_top=(0.95, 0.9))
        b.cylinder(0.07, 0.068, 0.08, (x_leg, 0.0, 0.15), boot)
        b.box((0.125, 0.06, 0.03), (x_leg, -0.18, 0.015), boot, bevel=0.0)  # toe cap
        b.finish()


def _build_equipment(spec, mats, armature, collection, MeshBuilder):
    plate, metal, strap, visor, lamp = (
        mats["MAT_SuitPlate"],
        mats["MAT_Metal"],
        mats["MAT_Strap"],
        mats["MAT_Visor"],
        mats["MAT_Lamp"],
    )

    def part(name):
        return MeshBuilder(name, bone=spec.EQUIPMENT_PARTS[name], armature=armature, collection=collection)

    # Hardsuit shell: plates over torso and limbs, chest console with a lamp.
    b = part("Equip_Hardsuit_Chest")
    b.box((0.45, 0.29, 0.265), (0.0, 0.0, 1.31), plate, bevel=0.04, taper_top=(1.06, 1.0))
    b.cylinder(0.105, 0.11, 0.05, (0.0, 0.0, 1.455), metal, segments=10)
    b.box((0.11, 0.03, 0.07), (0.0, -0.157, 1.30), metal, bevel=0.005)
    b.box((0.03, 0.012, 0.02), (0.03, -0.175, 1.315), lamp, bevel=0.0)
    for sx in (-1.0, 1.0):
        b.box((0.10, 0.14, 0.05), (0.19 * sx, -0.07, 1.41), plate, bevel=0.01)  # pauldron lip
    b.finish()

    b = part("Equip_Hardsuit_Spine")
    b.box((0.385, 0.255, 0.20), (0.0, 0.0, 1.11), plate, bevel=0.035)
    b.finish()

    b = part("Equip_Hardsuit_Pelvis")
    b.box((0.405, 0.265, 0.175), (0.0, 0.0, 0.94), plate, bevel=0.035)
    b.finish()

    for side, sx in (("L", 1.0), ("R", -1.0)):
        x_arm = 0.235 * sx
        b = part(f"Equip_Hardsuit_Shoulder_{side}")
        b.sphere(0.098, (x_arm, 0.0, 1.375), plate)
        b.cylinder(0.078, 0.068, 0.26, (x_arm, 0.0, 1.245), plate)
        b.finish()

        b = part(f"Equip_Hardsuit_Forearm_{side}")
        b.cylinder(0.07, 0.062, 0.23, (x_arm, 0.0, 0.985), plate)
        b.box((0.06, 0.03, 0.08), (x_arm + 0.06 * sx, 0.0, 0.99), metal, bevel=0.005)  # wrist unit
        b.finish()

        x_leg = 0.10 * sx
        b = part(f"Equip_Hardsuit_Knee_{side}")
        b.sphere(0.088, (x_leg, 0.0, 0.50), plate)
        b.cylinder(0.084, 0.072, 0.30, (x_leg, 0.0, 0.335), plate)
        b.finish()

    # EVA helmet: dome, emissive visor on the -Y (forward) face, chin ring, lamp.
    b = part("Equip_Helmet")
    b.sphere(0.168, (0.0, 0.0, 1.635), plate, segments=12, rings=7)
    b.box((0.19, 0.06, 0.13), (0.0, -0.14, 1.645), visor, bevel=0.02)
    b.cylinder(0.125, 0.13, 0.045, (0.0, 0.0, 1.485), metal, segments=10)
    b.box((0.045, 0.035, 0.035), (0.11, -0.095, 1.705), lamp, bevel=0.005)
    b.box((0.05, 0.04, 0.05), (-0.145, 0.0, 1.60), metal, bevel=0.005)  # comms puck
    b.finish()

    # EVA backpack: life-support box with two tanks and shoulder straps.
    b = part("Equip_EVABackpack")
    b.box((0.34, 0.17, 0.42), (0.0, 0.20, 1.21), plate, bevel=0.03)
    for sx in (-1.0, 1.0):
        b.cylinder(0.055, 0.055, 0.36, (0.095 * sx, 0.315, 1.21), metal, segments=10)
        b.sphere(0.055, (0.095 * sx, 0.315, 1.395), metal)
        b.box((0.05, 0.30, 0.025), (0.135 * sx, 0.0, 1.43), strap, bevel=0.0)
    b.box((0.10, 0.03, 0.05), (0.0, 0.295, 1.41), metal, bevel=0.0)  # regulator block
    b.finish()

    # Field pack: soft rounded duffel with a flap and side pockets.
    b = part("Equip_FieldPack")
    b.box((0.30, 0.19, 0.34), (0.0, 0.20, 1.17), strap, bevel=0.05)
    b.box((0.31, 0.20, 0.07), (0.0, 0.20, 1.34), strap, bevel=0.02)
    for sx in (-1.0, 1.0):
        b.box((0.06, 0.12, 0.16), (0.18 * sx, 0.20, 1.12), strap, bevel=0.015)
        b.box((0.05, 0.30, 0.025), (0.135 * sx, 0.0, 1.43), strap, bevel=0.0)
    b.finish()

    # Tool belt: belt ring with four pouches and a back holster.
    b = part("Equip_ToolBelt")
    b.box((0.40, 0.26, 0.055), (0.0, 0.0, 0.955), strap, bevel=0.01)
    for sx in (-1.0, 1.0):
        b.box((0.08, 0.06, 0.11), (0.17 * sx, -0.10, 0.905), strap, bevel=0.012)
        b.box((0.08, 0.06, 0.10), (0.17 * sx, 0.10, 0.91), strap, bevel=0.012)
    b.cylinder(0.025, 0.025, 0.16, (0.0, 0.15, 0.90), metal, segments=6)  # wrench holster
    b.finish()


# ------------------------------------------------------------------------ export


def _export_glb(bpy, glb_path: Path) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path),
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_extras=True,
        export_skins=True,
        export_all_influences=False,
        export_def_bones=True,
        export_rest_position_armature=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_force_sampling=True,
        export_frame_range=False,
        export_optimize_animation_size=False,
        export_anim_single_armature=True,
        export_reset_pose_bones=True,
        export_current_frame=False,
    )


if __name__ == "__main__":
    sys.exit(main())
