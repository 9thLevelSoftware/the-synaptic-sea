#!/usr/bin/env python3
"""Single source of truth for the ``survivor_v1`` procedural character kit.

The Blender builder, the host-side GLB validator, the Godot smoke, and the
feature/inventory docs all read these constants so that the authored asset,
its contract, and its validation cannot drift independently.

Coordinate contract (ADR-0058 / ADR-0070):
- Runtime GLB is Y-up, meters, pivot at the floor center between the feet,
  ``+Z`` forward (the visor/face points along +Z).
- Blender authoring is Z-up with the character facing ``-Y``; the glTF
  exporter's ``+Y up`` conversion maps Blender ``-Y`` to glTF ``+Z``.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Tuple

KIT_ID = "survivor_v1"
SCHEMA_VERSION = "1.0.0"
DOCUMENT_KIND = "character_kit_manifest"

RUNTIME_ROOT = Path("assets/imported/characters") / KIT_ID
PREVIEW_ROOT = Path("artifacts/validation-previews/characters") / KIT_ID
MANIFEST_LEAF = f"{KIT_ID}.manifest.json"

# Height of the base survivor in meters (crown of the bare head). The gameplay
# capsule is 0.35 r x 1.6 h (scripts/player/player_controller.gd); the visual is
# allowed to stand a little taller than the capsule, like Project Zomboid.
CHARACTER_HEIGHT_M = 1.75
CHARACTER_HEIGHT_TOLERANCE_M = 0.06
# Footprint must stay inside one 4.0 m cell and clear 1x1 doorway frames.
MAX_FOOTPRINT_M = (0.9, 0.9)

FORWARD_AXIS = "+Z"
PIVOT = "bottom_center"

# Deterministic bone names. Godot imports these verbatim on the Skeleton3D.
BONE_HIERARCHY: List[Tuple[str, str]] = [
    ("root", ""),
    ("hips", "root"),
    ("spine", "hips"),
    ("chest", "spine"),
    ("neck", "chest"),
    ("head", "neck"),
    ("shoulder_L", "chest"),
    ("upper_arm_L", "shoulder_L"),
    ("forearm_L", "upper_arm_L"),
    ("hand_L", "forearm_L"),
    ("shoulder_R", "chest"),
    ("upper_arm_R", "shoulder_R"),
    ("forearm_R", "upper_arm_R"),
    ("hand_R", "forearm_R"),
    ("thigh_L", "hips"),
    ("shin_L", "thigh_L"),
    ("foot_L", "shin_L"),
    ("thigh_R", "hips"),
    ("shin_R", "thigh_R"),
    ("foot_R", "shin_R"),
]
BONE_NAMES: List[str] = [name for name, _parent in BONE_HIERARCHY]

# Attachment sockets exported as empties parented to bones. Godot imports them
# as BoneAttachment3D children of the Skeleton3D so runtime code can mount
# handheld tools, packs, or a headlamp without touching the mesh.
SOCKETS: Dict[str, str] = {
    "Socket_HandR": "hand_R",
    "Socket_HandL": "hand_L",
    "Socket_Back": "chest",
    "Socket_Head": "head",
}

# Base body meshes (always visible). Each is rigidly skinned to one bone.
BODY_PARTS: Dict[str, str] = {
    "Body_Head": "head",
    "Body_Neck": "neck",
    "Body_Chest": "chest",
    "Body_Spine": "spine",
    "Body_Pelvis": "hips",
    "Body_UpperArm_L": "upper_arm_L",
    "Body_Forearm_L": "forearm_L",
    "Body_Hand_L": "hand_L",
    "Body_UpperArm_R": "upper_arm_R",
    "Body_Forearm_R": "forearm_R",
    "Body_Hand_R": "hand_R",
    "Body_Thigh_L": "thigh_L",
    "Body_Shin_L": "shin_L",
    "Body_Boot_L": "foot_L",
    "Body_Thigh_R": "thigh_R",
    "Body_Shin_R": "shin_R",
    "Body_Boot_R": "foot_R",
    "Body_ClassAccent": "chest",
}

# Equipment meshes, hidden by default at runtime and toggled by the equipment
# slot contents (data/characters/character_visual_catalog.json). Node name ->
# bone. Multi-bone equipment is split into one node per bone with a shared
# prefix so visibility toggling is a prefix match.
EQUIPMENT_PARTS: Dict[str, str] = {
    "Equip_Hardsuit_Chest": "chest",
    "Equip_Hardsuit_Spine": "spine",
    "Equip_Hardsuit_Pelvis": "hips",
    "Equip_Hardsuit_Shoulder_L": "upper_arm_L",
    "Equip_Hardsuit_Shoulder_R": "upper_arm_R",
    "Equip_Hardsuit_Forearm_L": "forearm_L",
    "Equip_Hardsuit_Forearm_R": "forearm_R",
    "Equip_Hardsuit_Knee_L": "shin_L",
    "Equip_Hardsuit_Knee_R": "shin_R",
    "Equip_Helmet": "head",
    "Equip_EVABackpack": "chest",
    "Equip_FieldPack": "chest",
    "Equip_ToolBelt": "hips",
}

# Equipment item id (data/items/equipment_definitions.json) -> node prefixes.
EQUIPMENT_VISUALS: Dict[str, List[str]] = {
    "hardsuit": ["Equip_Hardsuit_", "Equip_Helmet"],
    "eva_backpack": ["Equip_EVABackpack"],
    "field_pack": ["Equip_FieldPack"],
    "tool_belt": ["Equip_ToolBelt"],
}

# Animation clips. Names ending in ``-loop`` are imported by Godot as looping.
ANIMATION_CLIPS: Dict[str, Dict[str, object]] = {
    "idle-loop": {"frames": 48, "loop": True},
    "walk-loop": {"frames": 24, "loop": True},
    "crouch_idle-loop": {"frames": 48, "loop": True},
    "crouch_walk-loop": {"frames": 28, "loop": True},
    "work-loop": {"frames": 24, "loop": True},
    "melee_swing": {"frames": 16, "loop": False},
    "aim_ranged": {"frames": 12, "loop": False},
    "downed": {"frames": 12, "loop": False},
}
ANIMATION_NAMES: List[str] = list(ANIMATION_CLIPS.keys())

# Canonical material names. Godot imports them as StandardMaterial3D by name.
MATERIALS: Dict[str, Dict[str, object]] = {
    "MAT_SuitFabric": {"color": (0.23, 0.25, 0.22, 1.0), "roughness": 0.85, "metallic": 0.0},
    "MAT_SuitPlate": {"color": (0.74, 0.75, 0.72, 1.0), "roughness": 0.55, "metallic": 0.15},
    "MAT_Skin": {"color": (0.62, 0.46, 0.36, 1.0), "roughness": 0.75, "metallic": 0.0},
    "MAT_Boot": {"color": (0.10, 0.10, 0.11, 1.0), "roughness": 0.65, "metallic": 0.0},
    "MAT_Strap": {"color": (0.16, 0.14, 0.12, 1.0), "roughness": 0.9, "metallic": 0.0},
    "MAT_Metal": {"color": (0.45, 0.47, 0.50, 1.0), "roughness": 0.4, "metallic": 0.8},
    "MAT_Visor": {"color": (0.08, 0.20, 0.24, 1.0), "roughness": 0.2, "metallic": 0.3, "emission": (0.10, 0.45, 0.55), "emission_strength": 0.8},
    "MAT_ClassAccent": {"color": (0.95, 0.45, 0.10, 1.0), "roughness": 0.7, "metallic": 0.0},
    "MAT_Lamp": {"color": (1.0, 0.95, 0.8, 1.0), "roughness": 0.3, "metallic": 0.0, "emission": (1.0, 0.9, 0.7), "emission_strength": 2.0},
}

# Triangle budgets ("Project Zomboid, but a bit more detailed").
TRIANGLE_BUDGET = {
    "body_min": 800,
    "body_max": 3200,
    "kit_max": 7000,
}

GLB_LEAF = f"{KIT_ID}.glb"


@dataclass(frozen=True)
class KitManifest:
    kit_id: str = KIT_ID
    schema_version: str = SCHEMA_VERSION
    document_kind: str = DOCUMENT_KIND
    glb_path: str = str(RUNTIME_ROOT / GLB_LEAF).replace("\\", "/")
    height_m: float = CHARACTER_HEIGHT_M
    height_tolerance_m: float = CHARACTER_HEIGHT_TOLERANCE_M
    forward_axis: str = FORWARD_AXIS
    pivot: str = PIVOT
    bones: List[str] = field(default_factory=lambda: list(BONE_NAMES))
    sockets: Dict[str, str] = field(default_factory=lambda: dict(SOCKETS))
    body_parts: List[str] = field(default_factory=lambda: list(BODY_PARTS.keys()))
    equipment_parts: List[str] = field(default_factory=lambda: list(EQUIPMENT_PARTS.keys()))
    equipment_visuals: Dict[str, List[str]] = field(default_factory=lambda: {k: list(v) for k, v in EQUIPMENT_VISUALS.items()})
    animations: List[str] = field(default_factory=lambda: list(ANIMATION_NAMES))
    materials: List[str] = field(default_factory=lambda: list(MATERIALS.keys()))
    triangle_budget: Dict[str, int] = field(default_factory=lambda: dict(TRIANGLE_BUDGET))

    def to_dict(self) -> dict:
        return {
            "schema_version": self.schema_version,
            "document_kind": self.document_kind,
            "kit_id": self.kit_id,
            "glb_path": self.glb_path,
            "height_m": self.height_m,
            "height_tolerance_m": self.height_tolerance_m,
            "forward_axis": self.forward_axis,
            "pivot": self.pivot,
            "bones": self.bones,
            "sockets": self.sockets,
            "body_parts": self.body_parts,
            "equipment_parts": self.equipment_parts,
            "equipment_visuals": self.equipment_visuals,
            "animations": self.animations,
            "materials": self.materials,
            "triangle_budget": self.triangle_budget,
        }


def canonical_json(document: dict) -> str:
    return json.dumps(document, sort_keys=True, indent=2, ensure_ascii=False) + "\n"


def write_manifest(path: Path) -> dict:
    document = KitManifest().to_dict()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(canonical_json(document), encoding="utf-8")
    return document


if __name__ == "__main__":
    print(canonical_json(KitManifest().to_dict()), end="")
