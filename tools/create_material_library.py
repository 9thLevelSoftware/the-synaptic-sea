#!/usr/bin/env python3
"""Create the shared Salvage Industrial Blender material library.

Run through Blender rather than the system Python::

    blender --background --factory-startup --python tools/create_material_library.py

The default output is the external source root used by Synaptic Sea artists.
Set ``SYNAPTIC_SEA_MATERIAL_LIBRARY`` or pass Blender script arguments after
``--`` to write a different library during validation.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
from typing import Any, Sequence


DEFAULT_OUTPUT = Path(
    "/Volumes/Untitled/SynapticSeaAssets/meshes/source/materials/"
    "salvage_industrial.blend"
)


_MATERIAL_SPECS: tuple[dict[str, Any], ...] = (
    {
        "name": "MAT_PaintedAlloyGray",
        "color": (0.50, 0.50, 0.50, 1.0),
        "roughness": 0.7,
        "metallic": 0.35,
        "description": "Painted structural alloy with worn industrial response",
    },
    {
        "name": "MAT_WarningStripe",
        "color": (1.0, 0.8, 0.0, 1.0),
        "roughness": 0.5,
        "metallic": 0.0,
        "description": "Yellow and black hazard stripe material",
    },
    {
        "name": "MAT_ReactorGlow",
        "color": (0.0, 0.8, 1.0, 1.0),
        "roughness": 0.35,
        "metallic": 0.0,
        "emission_strength": 2.0,
        "description": "Blue-green reactor emissive material",
    },
    {
        "name": "MAT_Biomatter",
        "color": (0.4, 0.05, 0.05, 1.0),
        "roughness": 0.8,
        "metallic": 0.0,
        "subsurface": 0.3,
        "description": "Dark red organic biomatter",
    },
    {
        "name": "MAT_Conduit",
        "color": (0.1, 0.1, 0.1, 1.0),
        "roughness": 0.9,
        "metallic": 0.0,
        "description": "Dark rubber conduit and cable covering",
    },
)


def _set_input(node: Any, names: Sequence[str], value: Any) -> None:
    """Set the first matching Principled input across Blender 4.x versions."""

    for name in names:
        socket = node.inputs.get(name)
        if socket is not None:
            socket.default_value = value
            return
    raise KeyError(f"none of the Blender shader inputs exist: {names!r}")


def _new_principled_material(bpy: Any, spec: dict[str, Any]) -> Any:
    material = bpy.data.materials.new(name=spec["name"])
    material.use_fake_user = True
    material.use_nodes = True
    material.diffuse_color = spec["color"]
    material["asset_role"] = "synaptic_sea_structural_material"
    material["description"] = spec["description"]
    material["base_color_rgba"] = list(spec["color"])
    material["roughness"] = float(spec["roughness"])
    material["metallic"] = float(spec["metallic"])

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    output.name = "Material Output"
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.name = "Principled BSDF"
    shader.label = spec["name"]
    _set_input(shader, ("Base Color",), spec["color"])
    _set_input(shader, ("Roughness",), float(spec["roughness"]))
    _set_input(shader, ("Metallic",), float(spec["metallic"]))

    if "emission_strength" in spec:
        _set_input(shader, ("Emission Color", "Emission"), spec["color"])
        _set_input(shader, ("Emission Strength",), float(spec["emission_strength"]))
        material["emission_strength"] = float(spec["emission_strength"])

    if "subsurface" in spec:
        _set_input(
            shader,
            ("Subsurface Weight", "Subsurface"),
            float(spec["subsurface"]),
        )
        material["subsurface_weight"] = float(spec["subsurface"])

    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def _add_warning_stripe_pattern(material: Any) -> None:
    """Add a procedural yellow/black stripe pattern to the warning material."""

    nodes = material.node_tree.nodes
    links = material.node_tree.links
    shader = nodes.get("Principled BSDF")
    if shader is None:
        raise RuntimeError("warning material is missing its Principled BSDF")

    texture = nodes.new("ShaderNodeTexCoord")
    texture.name = "Hazard Stripe Coordinates"
    wave = nodes.new("ShaderNodeTexWave")
    wave.name = "Hazard Stripe Bands"
    wave.wave_type = "BANDS"
    wave.bands_direction = "X"
    _set_input(wave, ("Scale",), 6.0)
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.name = "Hazard Yellow Black"
    ramp.color_ramp.interpolation = "CONSTANT"
    first, second = ramp.color_ramp.elements
    first.position = 0.42
    first.color = (0.0, 0.0, 0.0, 1.0)
    second.position = 0.58
    second.color = (1.0, 0.8, 0.0, 1.0)
    links.new(texture.outputs["Generated"], wave.inputs["Vector"])
    links.new(wave.outputs["Color"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
    material["pattern"] = "yellow-black hazard stripes"


def create_material_library(output_path: Path) -> list[str]:
    """Create and save the five shared materials, returning their names."""

    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    created: list[str] = []
    for spec in _MATERIAL_SPECS:
        material = _new_principled_material(bpy, spec)
        if material.name == "MAT_WarningStripe":
            _add_warning_stripe_pattern(material)
        created.append(material.name)

    output_path = Path(output_path).expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output_path))
    return created


def _script_args(argv: Sequence[str] | None = None) -> list[str]:
    raw = list(sys.argv[1:] if argv is None else argv)
    if "--" in raw:
        return raw[raw.index("--") + 1 :]
    if argv is None and "--python" in raw:
        # Blender's own flags precede the script path.  With no explicit
        # separator, arguments after the script path belong to this script.
        script_index = raw.index("--python") + 2
        return raw[script_index:]
    return raw


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(os.environ.get("SYNAPTIC_SEA_MATERIAL_LIBRARY", DEFAULT_OUTPUT)),
        help=f"output .blend path (default: {DEFAULT_OUTPUT})",
    )
    return parser.parse_args(_script_args(argv))


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        names = create_material_library(args.output)
    except (KeyError, OSError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"MATERIAL_LIBRARY_CREATED output={args.output.resolve()} materials={','.join(names)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
