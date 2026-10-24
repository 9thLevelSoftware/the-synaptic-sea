"""Blender-only builder for the ``handheld_tools_v1`` prop kit.

Each tool is a static (unrigged) low-poly GLB with its pivot at the grip and
the working end pointing along glTF ``+Z`` (Blender ``-Y``), so a runtime
BoneAttachment3D on ``Socket_HandR`` can mount it with an identity transform.

Tool ids mirror the ``primary_hand`` / ``secondary_hand`` equipment items in
``data/items/item_definitions.json`` plus the two tool pickups in
``data/tools/tool_definitions.json``.
"""

from __future__ import annotations

from pathlib import Path

TOOL_KIT_ID = "handheld_tools_v1"
TOOL_RUNTIME_ROOT = Path("assets/imported/characters") / TOOL_KIT_ID

# id -> (equipment slot or pickup kind, description)
TOOL_IDS = {
    "crowbar": "primary_hand",
    "welding_lance": "primary_hand",
    "flare_pistol": "primary_hand",
    "shock_probe": "secondary_hand",
    "portable_oxygen_pump": "tool_pickup",
    "junction_calibrator": "tool_pickup",
}


def build_all_tools(bpy, project_root: Path, materials_spec) -> None:
    from tools.character_kit.bpy_lowpoly import MeshBuilder, export_glb, make_materials, new_collection, reset_scene

    out_dir = project_root / TOOL_RUNTIME_ROOT
    out_dir.mkdir(parents=True, exist_ok=True)
    for tool_id in TOOL_IDS:
        reset_scene()
        mats = make_materials(materials_spec)
        collection = new_collection(tool_id)
        builder = MeshBuilder(f"Tool_{tool_id}", bone=None, armature=None, collection=collection)
        _BUILDERS[tool_id](builder, mats)
        builder.finish()
        export_glb(str(out_dir / f"{tool_id}.glb"), animated=False)
        print(f"HANDHELD TOOL BUILD OK id={tool_id}")


# All tools: grip centred at the origin, length along -Y (forward), Z up.
def _crowbar(b, m):
    metal = m["MAT_Metal"]
    b.box((0.03, 0.62, 0.03), (0.0, -0.22, 0.0), metal, bevel=0.006)
    b.box((0.035, 0.09, 0.03), (0.0, -0.56, 0.035), metal, bevel=0.006, rotate=(0.6, "X"))
    b.box((0.034, 0.06, 0.03), (0.0, 0.09, 0.0), m["MAT_ClassAccent"], bevel=0.006)  # grip tape


def _welding_lance(b, m):
    metal, strap, lamp = m["MAT_Metal"], m["MAT_Strap"], m["MAT_Lamp"]
    b.cylinder(0.022, 0.022, 0.16, (0.0, 0.0, 0.0), strap, segments=8, axis="Y")  # grip
    b.box((0.05, 0.12, 0.07), (0.0, -0.13, 0.02), metal, bevel=0.008)  # body
    b.cylinder(0.012, 0.009, 0.26, (0.0, -0.32, 0.03), metal, segments=6, axis="Y")  # barrel
    b.cylinder(0.014, 0.006, 0.04, (0.0, -0.46, 0.03), lamp, segments=6, axis="Y")  # tip
    b.box((0.03, 0.06, 0.03), (0.0, 0.10, -0.02), metal, bevel=0.004)  # hose stub


def _flare_pistol(b, m):
    metal, strap, accent = m["MAT_Metal"], m["MAT_Strap"], m["MAT_ClassAccent"]
    b.box((0.03, 0.045, 0.11), (0.0, 0.02, -0.05), strap, bevel=0.006, rotate=(0.25, "X"))  # grip
    b.box((0.034, 0.17, 0.045), (0.0, -0.08, 0.02), accent, bevel=0.008)  # frame
    b.cylinder(0.022, 0.022, 0.14, (0.0, -0.13, 0.045), metal, segments=8, axis="Y")  # barrel
    b.box((0.02, 0.03, 0.03), (0.0, -0.03, 0.055), metal, bevel=0.003)  # hammer


def _shock_probe(b, m):
    metal, strap, visor = m["MAT_Metal"], m["MAT_Strap"], m["MAT_Visor"]
    b.cylinder(0.02, 0.02, 0.2, (0.0, 0.0, 0.0), strap, segments=8, axis="Y")
    b.cylinder(0.012, 0.012, 0.3, (0.0, -0.25, 0.0), metal, segments=6, axis="Y")
    for sx in (-1.0, 1.0):
        b.box((0.012, 0.05, 0.012), (0.014 * sx, -0.42, 0.0), visor, bevel=0.0)  # electrodes


def _portable_oxygen_pump(b, m):
    metal, strap, plate = m["MAT_Metal"], m["MAT_Strap"], m["MAT_SuitPlate"]
    b.box((0.18, 0.12, 0.22), (0.0, 0.0, 0.0), plate, bevel=0.012)
    b.cylinder(0.035, 0.035, 0.2, (0.06, -0.08, 0.0), metal, segments=8, axis="Z")
    b.box((0.03, 0.14, 0.03), (0.0, 0.0, 0.14), strap, bevel=0.005)  # handle
    b.cylinder(0.01, 0.01, 0.12, (-0.05, -0.1, 0.03), strap, segments=6, axis="Y")  # hose


def _junction_calibrator(b, m):
    metal, strap, visor = m["MAT_Metal"], m["MAT_Strap"], m["MAT_Visor"]
    b.box((0.08, 0.16, 0.04), (0.0, 0.0, 0.0), strap, bevel=0.008)
    b.box((0.06, 0.05, 0.012), (0.0, -0.02, 0.026), visor, bevel=0.0)  # screen
    b.cylinder(0.008, 0.008, 0.08, (0.0, -0.12, 0.0), metal, segments=6, axis="Y")  # probe


_BUILDERS = {
    "crowbar": _crowbar,
    "welding_lance": _welding_lance,
    "flare_pistol": _flare_pistol,
    "shock_probe": _shock_probe,
    "portable_oxygen_pump": _portable_oxygen_pump,
    "junction_calibrator": _junction_calibrator,
}
