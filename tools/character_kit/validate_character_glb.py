#!/usr/bin/env python3
"""Host-side (no Blender, no Godot) validator for the ``survivor_v1`` kit GLB.

Checks the exported GLB against ``character_kit_spec``: skin joints equal the
spec bone list, every body/equipment/socket node exists, every animation clip
is present, triangle budgets hold, the rest-pose bounds give a ~1.75 m figure
standing on the floor with its pivot at the floor center, and the boots point
along +Z (forward-axis proof). Prints one PASS/FAIL marker line and optionally
writes a JSON report.

    PYTHONPATH=. python3 tools/character_kit/validate_character_glb.py \
        --glb assets/imported/characters/survivor_v1/survivor_v1.glb \
        [--manifest assets/imported/characters/survivor_v1/survivor_v1.manifest.json] \
        [--report <path>]
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path
from typing import Dict, List, Tuple

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.character_kit import character_kit_spec as spec

PASS_PREFIX = "CHARACTER KIT VALIDATE PASS"
FAIL_PREFIX = "CHARACTER KIT VALIDATE FAIL"

_COMPONENT_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
_COMPONENT_FORMAT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}


class GlbError(ValueError):
    pass


def read_glb(path: Path) -> Tuple[dict, bytes]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"glTF":
        raise GlbError("not a GLB file")
    version, total_length = struct.unpack_from("<II", data, 4)
    if version != 2 or total_length != len(data):
        raise GlbError(f"bad GLB header version={version} length={total_length} actual={len(data)}")
    offset = 12
    document = None
    binary = b""
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<I4s", data, offset)
        offset += 8
        chunk = data[offset : offset + chunk_length]
        offset += chunk_length
        if chunk_type == b"JSON":
            document = json.loads(chunk.decode("utf-8"))
        elif chunk_type == b"BIN\0":
            binary = chunk
    if document is None:
        raise GlbError("missing JSON chunk")
    return document, binary


def _read_accessor(document: dict, binary: bytes, index: int) -> List[Tuple[float, ...]]:
    accessor = document["accessors"][index]
    view = document["bufferViews"][accessor["bufferView"]]
    count = int(accessor["count"])
    components = _COMPONENT_COUNT[accessor["type"]]
    fmt = _COMPONENT_FORMAT[int(accessor["componentType"])]
    item_size = struct.calcsize(fmt) * components
    stride = int(view.get("byteStride", item_size))
    base = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    out = []
    for i in range(count):
        start = base + i * stride
        out.append(struct.unpack_from("<" + fmt * components, binary, start))
    return out


def _mesh_triangles(document: dict, mesh_index: int) -> int:
    total = 0
    for primitive in document["meshes"][mesh_index].get("primitives", []):
        mode = int(primitive.get("mode", 4))
        if mode != 4:
            continue
        if "indices" in primitive:
            total += int(document["accessors"][primitive["indices"]]["count"]) // 3
        else:
            total += int(document["accessors"][primitive["attributes"]["POSITION"]]["count"]) // 3
    return total


def _mesh_bounds(document: dict, mesh_index: int) -> Tuple[List[float], List[float]]:
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    for primitive in document["meshes"][mesh_index].get("primitives", []):
        accessor = document["accessors"][primitive["attributes"]["POSITION"]]
        for axis in range(3):
            mins[axis] = min(mins[axis], float(accessor["min"][axis]))
            maxs[axis] = max(maxs[axis], float(accessor["max"][axis]))
    return mins, maxs


def _node_by_name(document: dict) -> Dict[str, dict]:
    return {str(node.get("name", "")): node for node in document.get("nodes", [])}


def project_relative(path: Path, project_root: Path | None) -> str:
    """Project-relative POSIX path when ``path`` is under the root, else as given
    (keeps tracked reports identical across machines)."""
    try:
        root = (project_root or Path.cwd()).resolve()
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return path.as_posix()


def validate(glb_path: Path, manifest_path: Path | None = None, project_root: Path | None = None) -> dict:
    errors: List[str] = []
    document, binary = read_glb(glb_path)
    if manifest_path is not None:
        disk = json.loads(manifest_path.read_text(encoding="utf-8"))
        disk_glb = str(disk.get("glb_path", ""))
        if not disk_glb.endswith(spec.GLB_LEAF):
            errors.append(f"manifest glb_path must point at {spec.GLB_LEAF}: {disk_glb!r}")
        expected = spec.KitManifest(glb_path=disk_glb or spec.KitManifest().glb_path).to_dict()
        if disk != expected:
            errors.append("manifest on disk differs from character_kit_spec (rebuild the kit)")

    nodes = _node_by_name(document)
    node_names = set(nodes)

    # Skeleton / skin.
    skins = document.get("skins", [])
    joint_names: List[str] = []
    if len(skins) != 1:
        errors.append(f"expected exactly one skin, found {len(skins)}")
    else:
        joint_names = [str(document["nodes"][j].get("name", "")) for j in skins[0]["joints"]]
        if set(joint_names) != set(spec.BONE_NAMES):
            errors.append(
                "skin joints != spec bones: missing="
                f"{sorted(set(spec.BONE_NAMES) - set(joint_names))} extra={sorted(set(joint_names) - set(spec.BONE_NAMES))}"
            )

    # Parts and sockets.
    for name in list(spec.BODY_PARTS) + list(spec.EQUIPMENT_PARTS):
        if name not in node_names:
            errors.append(f"missing mesh node {name}")
        elif "mesh" not in nodes[name]:
            errors.append(f"node {name} has no mesh")
        elif "skin" not in nodes[name]:
            errors.append(f"node {name} is not skinned")
    for socket, bone in spec.SOCKETS.items():
        if socket not in node_names:
            errors.append(f"missing socket node {socket}")
            continue
        parent = next((n for n in document["nodes"] if socket in [str(document["nodes"][c].get("name")) for c in n.get("children", [])]), None)
        if parent is None or str(parent.get("name")) != bone:
            errors.append(f"socket {socket} must be a child of bone {bone}")

    # Animations.
    animation_names = [str(a.get("name", "")) for a in document.get("animations", [])]
    if set(animation_names) != set(spec.ANIMATION_NAMES):
        errors.append(
            "animations != spec: missing="
            f"{sorted(set(spec.ANIMATION_NAMES) - set(animation_names))} extra={sorted(set(animation_names) - set(spec.ANIMATION_NAMES))}"
        )
    for animation in document.get("animations", []):
        if not animation.get("channels"):
            errors.append(f"animation {animation.get('name')} has no channels")

    # Materials.
    material_names = {str(m.get("name", "")) for m in document.get("materials", [])}
    missing_materials = set(spec.MATERIALS) - material_names
    if missing_materials:
        errors.append(f"materials missing from GLB: {sorted(missing_materials)}")

    # Triangles and bounds (rest pose: skinned mesh positions are model space).
    body_tris = 0
    kit_tris = 0
    mins = [float("inf")] * 3
    maxs = [float("-inf")] * 3
    per_part: Dict[str, int] = {}
    for name in list(spec.BODY_PARTS) + list(spec.EQUIPMENT_PARTS):
        node = nodes.get(name)
        if node is None or "mesh" not in node:
            continue
        tris = _mesh_triangles(document, node["mesh"])
        per_part[name] = tris
        kit_tris += tris
        if name in spec.BODY_PARTS:
            body_tris += tris
            part_min, part_max = _mesh_bounds(document, node["mesh"])
            for axis in range(3):
                mins[axis] = min(mins[axis], part_min[axis])
                maxs[axis] = max(maxs[axis], part_max[axis])
    budget = spec.TRIANGLE_BUDGET
    if not (budget["body_min"] <= body_tris <= budget["body_max"]):
        errors.append(f"body triangles {body_tris} outside [{budget['body_min']}, {budget['body_max']}]")
    if kit_tris > budget["kit_max"]:
        errors.append(f"kit triangles {kit_tris} exceed {budget['kit_max']}")

    height = maxs[1] - mins[1] if body_tris else 0.0
    if abs(height - spec.CHARACTER_HEIGHT_M) > spec.CHARACTER_HEIGHT_TOLERANCE_M:
        errors.append(f"height {height:.3f} m outside {spec.CHARACTER_HEIGHT_M}±{spec.CHARACTER_HEIGHT_TOLERANCE_M}")
    if body_tris and abs(mins[1]) > 0.02:
        errors.append(f"pivot is not at the floor: min_y={mins[1]:.3f}")
    if body_tris and (abs(mins[0] + maxs[0]) > 0.03):
        errors.append(f"figure is not centered on x: min_x={mins[0]:.3f} max_x={maxs[0]:.3f}")
    footprint = (maxs[0] - mins[0], maxs[2] - mins[2]) if body_tris else (0.0, 0.0)
    if footprint[0] > spec.MAX_FOOTPRINT_M[0] or footprint[1] > spec.MAX_FOOTPRINT_M[1]:
        errors.append(f"footprint {footprint} exceeds {spec.MAX_FOOTPRINT_M}")

    # Forward axis: boot toes extend further toward +Z than the heel toward -Z.
    forward_ok = False
    boot = nodes.get("Body_Boot_L")
    if boot is not None and "mesh" in boot:
        b_min, b_max = _mesh_bounds(document, boot["mesh"])
        forward_ok = b_max[2] > abs(b_min[2]) + 0.05
        if not forward_ok:
            errors.append(f"boot does not point +Z: z-range [{b_min[2]:.3f}, {b_max[2]:.3f}]")

    report = {
        "glb": project_relative(glb_path, project_root),
        "kit_id": spec.KIT_ID,
        "ok": not errors,
        "errors": errors,
        "bones": joint_names,
        "animations": animation_names,
        "body_triangles": body_tris,
        "kit_triangles": kit_tris,
        "triangles_per_part": per_part,
        "height_m": round(height, 4),
        "bounds_min": [round(v, 4) for v in mins] if body_tris else None,
        "bounds_max": [round(v, 4) for v in maxs] if body_tris else None,
        "forward_axis_ok": forward_ok,
        "byte_size": glb_path.stat().st_size,
    }
    return report


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glb", required=True)
    parser.add_argument("--manifest", default=None)
    parser.add_argument("--report", default=None)
    parser.add_argument("--project-root", default=None, help="root for project-relative report paths (default: cwd)")
    args = parser.parse_args(argv)
    glb_path = Path(args.glb)
    try:
        report = validate(
            glb_path,
            Path(args.manifest) if args.manifest else None,
            Path(args.project_root) if args.project_root else None,
        )
    except (GlbError, FileNotFoundError, KeyError, json.JSONDecodeError) as exc:
        print(f"{FAIL_PREFIX} reason={exc}")
        return 1
    if args.report:
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if report["ok"]:
        print(
            f"{PASS_PREFIX} kit={report['kit_id']} bones={len(report['bones'])} "
            f"animations={len(report['animations'])} body_tris={report['body_triangles']} "
            f"kit_tris={report['kit_triangles']} height={report['height_m']:.2f} forward=+Z"
        )
        return 0
    for error in report["errors"]:
        print(f"  - {error}")
    print(f"{FAIL_PREFIX} errors={len(report['errors'])}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
