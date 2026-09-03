#!/usr/bin/env python3
"""Strict validation for the canonical procedural biomass catalogs."""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

MAX_ATTACHMENTS = 8
MAX_DEPTH = 3
MAX_TRIANGLES = 30000
MAX_NODES = 160

CATEGORIES = {
    "biomass_core",
    "biomass_limb",
    "biomass_head",
    "biomass_connector",
    "biomass_appendage",
}
LOCOMOTION_HINTS = {"biped", "quadruped", "crawl", "drag", "slither"}
ASSEMBLY_ROLES = {
    "core", "locomotor", "manipulator", "detail", "puller", "slither", "connector",
}
SOCKET_KINDS = {"root", "head", "limb", "appendage", "jaw", "distal"}
SOCKET_RE = re.compile(r"^socket_(root|head|limb|appendage|jaw|distal)_[0-9]+$")
RECIPE_SOCKET_RE = re.compile(r"^(root|head|limb|appendage|jaw|distal)_[0-9]+$")
ALBEDO_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
CONNECTOR_PART_ID = "biomass_gunk_connector_v1"

_PART_FIELDS = {
    "category", "species_tags", "assembly_roles", "wrapper_scene_path",
    "triangle_budget", "sockets", "collision_shapes", "fallback",
}
_SOCKET_FIELDS = {"name", "kind", "accepts_categories", "position_m", "rotation_deg"}
_FALLBACK_FIELDS = {"primitive", "dimensions_m", "albedo"}
_BASE_COLLISION_FIELDS = {"shape", "position_m", "rotation_deg"}
_RECIPE_FIELDS = {"recipe_id", "locomotion_hint", "core", "attachments"}
_CORE_FIELDS = {"instance_id", "part_id"}
_EDGE_FIELDS = {
    "instance_id", "part_id", "parent_instance_id", "parent_socket",
    "child_socket", "connector_part_id",
}

# These values are intentionally duplicated here: validation must reject a catalog that
# merely has valid shapes but is not the canonical eight-part pilot set.
CANONICAL_PARTS: dict[str, dict[str, Any]] = {
    "biomass_human_arm_v1": {
        "category": "biomass_limb", "species_tags": ["human"],
        "assembly_roles": ["locomotor", "manipulator", "puller"], "wrapper_scene_path": "",
        "triangle_budget": 2500,
        "sockets": [
            {"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0]},
            {"name": "socket_distal_0", "kind": "distal", "accepts_categories": ["biomass_appendage", "biomass_limb"], "position_m": [0, 0, 1.0], "rotation_deg": [0, 0, 0]},
        ],
        "collision_shapes": [{"shape": "capsule", "position_m": [0, 0, 0.45], "rotation_deg": [90, 0, 0], "radius_m": 0.12, "height_m": 0.90}],
        "fallback": {"primitive": "capsule", "dimensions_m": [0.24, 0.24, 1.0], "albedo": "#8b5252"},
    },
    "biomass_insect_leg_v1": {
        "category": "biomass_limb", "species_tags": ["insectoid"],
        "assembly_roles": ["locomotor"], "wrapper_scene_path": "", "triangle_budget": 2500,
        "sockets": [
            {"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0]},
            {"name": "socket_distal_0", "kind": "distal", "accepts_categories": ["biomass_appendage", "biomass_limb"], "position_m": [0, 0, 0.90], "rotation_deg": [0, 0, 0]},
        ],
        "collision_shapes": [{"shape": "capsule", "position_m": [0, 0, 0.42], "rotation_deg": [90, 0, 0], "radius_m": 0.10, "height_m": 0.84}],
        "fallback": {"primitive": "capsule", "dimensions_m": [0.22, 0.22, 0.90], "albedo": "#6f7046"},
    },
    "biomass_cephalopod_tentacle_v1": {
        "category": "biomass_limb", "species_tags": ["cephalopodic"],
        "assembly_roles": ["locomotor", "puller", "slither"], "wrapper_scene_path": "", "triangle_budget": 2500,
        "sockets": [
            {"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0]},
            {"name": "socket_distal_0", "kind": "distal", "accepts_categories": ["biomass_appendage", "biomass_limb"], "position_m": [0, 0, 1.20], "rotation_deg": [0, 0, 0]},
        ],
        "collision_shapes": [{"shape": "capsule", "position_m": [0, 0, 0.55], "rotation_deg": [90, 0, 0], "radius_m": 0.11, "height_m": 1.10}],
        "fallback": {"primitive": "capsule", "dimensions_m": [0.24, 0.24, 1.20], "albedo": "#765070"},
    },
    "biomass_animal_skull_v1": {
        "category": "biomass_head", "species_tags": ["animal"],
        "assembly_roles": ["core", "detail"], "wrapper_scene_path": "", "triangle_budget": 3500,
        "sockets": [
            {"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0]},
            {"name": "socket_appendage_0", "kind": "appendage", "accepts_categories": ["biomass_limb", "biomass_appendage"], "position_m": [-0.20, 0.05, 0.20], "rotation_deg": [0, -65, 0]},
            {"name": "socket_appendage_1", "kind": "appendage", "accepts_categories": ["biomass_limb", "biomass_appendage"], "position_m": [0.20, 0.05, 0.20], "rotation_deg": [0, 65, 0]},
            {"name": "socket_appendage_2", "kind": "appendage", "accepts_categories": ["biomass_limb", "biomass_appendage"], "position_m": [-0.18, -0.10, 0.35], "rotation_deg": [25, -40, 0]},
            {"name": "socket_appendage_3", "kind": "appendage", "accepts_categories": ["biomass_limb", "biomass_appendage"], "position_m": [0.18, -0.10, 0.35], "rotation_deg": [25, 40, 0]},
            {"name": "socket_jaw_0", "kind": "jaw", "accepts_categories": ["biomass_appendage"], "position_m": [0, -0.18, 0.50], "rotation_deg": [15, 0, 0]},
        ],
        "collision_shapes": [{"shape": "box", "position_m": [0, 0, 0.30], "rotation_deg": [0, 0, 0], "dimensions_m": [0.45, 0.40, 0.60]}],
        "fallback": {"primitive": "box", "dimensions_m": [0.45, 0.40, 0.60], "albedo": "#8a806b"},
    },
    "biomass_humanoid_torso_v1": {
        "category": "biomass_core", "species_tags": ["human"],
        "assembly_roles": ["core"], "wrapper_scene_path": "", "triangle_budget": 5000,
        "sockets": [
            {"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0]},
            {"name": "socket_head_0", "kind": "head", "accepts_categories": ["biomass_head", "biomass_appendage"], "position_m": [0, 0.45, 0.05], "rotation_deg": [-90, 0, 0]},
            {"name": "socket_limb_0", "kind": "limb", "accepts_categories": ["biomass_limb"], "position_m": [-0.34, 0.28, 0], "rotation_deg": [0, -90, 0]},
            {"name": "socket_limb_1", "kind": "limb", "accepts_categories": ["biomass_limb"], "position_m": [0.34, 0.28, 0], "rotation_deg": [0, 90, 0]},
            {"name": "socket_limb_2", "kind": "limb", "accepts_categories": ["biomass_limb"], "position_m": [-0.34, -0.05, 0], "rotation_deg": [0, -90, 0]},
            {"name": "socket_limb_3", "kind": "limb", "accepts_categories": ["biomass_limb"], "position_m": [0.34, -0.05, 0], "rotation_deg": [0, 90, 0]},
            {"name": "socket_limb_4", "kind": "limb", "accepts_categories": ["biomass_limb"], "position_m": [-0.20, -0.45, 0], "rotation_deg": [90, 0, 0]},
            {"name": "socket_limb_5", "kind": "limb", "accepts_categories": ["biomass_limb"], "position_m": [0.20, -0.45, 0], "rotation_deg": [90, 0, 0]},
            {"name": "socket_appendage_0", "kind": "appendage", "accepts_categories": ["biomass_head", "biomass_appendage"], "position_m": [0, 0.15, -0.20], "rotation_deg": [0, 180, 0]},
            {"name": "socket_appendage_1", "kind": "appendage", "accepts_categories": ["biomass_head", "biomass_appendage"], "position_m": [-0.22, 0.15, -0.18], "rotation_deg": [0, -135, 0]},
            {"name": "socket_appendage_2", "kind": "appendage", "accepts_categories": ["biomass_head", "biomass_appendage"], "position_m": [0.22, 0.15, -0.18], "rotation_deg": [0, 135, 0]},
        ],
        "collision_shapes": [{"shape": "box", "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0], "dimensions_m": [0.65, 0.90, 0.40]}],
        "fallback": {"primitive": "box", "dimensions_m": [0.65, 0.90, 0.40], "albedo": "#80585d"},
    },
    "biomass_gunk_connector_v1": {
        "category": "biomass_connector", "species_tags": ["biomass"],
        "assembly_roles": ["connector"], "wrapper_scene_path": "", "triangle_budget": 500,
        "sockets": [{"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0]}],
        "collision_shapes": [{"shape": "sphere", "position_m": [0, 0, 0.10], "rotation_deg": [0, 0, 0], "radius_m": 0.18}],
        "fallback": {"primitive": "sphere", "dimensions_m": [0.35, 0.35, 0.25], "albedo": "#704b63"},
    },
    "biomass_claw_v1": {
        "category": "biomass_appendage", "species_tags": ["alien"],
        "assembly_roles": ["detail", "manipulator"], "wrapper_scene_path": "", "triangle_budget": 1500,
        "sockets": [{"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0]}],
        "collision_shapes": [{"shape": "box", "position_m": [0, 0, 0.10], "rotation_deg": [0, 0, 0], "dimensions_m": [0.35, 0.20, 0.20]}],
        "fallback": {"primitive": "box", "dimensions_m": [0.35, 0.20, 0.20], "albedo": "#6d6148"},
    },
    "biomass_maw_v1": {
        "category": "biomass_appendage", "species_tags": ["alien"],
        "assembly_roles": ["detail"], "wrapper_scene_path": "", "triangle_budget": 1500,
        "sockets": [{"name": "socket_root_0", "kind": "root", "accepts_categories": [], "position_m": [0, 0, 0], "rotation_deg": [0, 0, 0]}],
        "collision_shapes": [{"shape": "box", "position_m": [0, 0, 0.175], "rotation_deg": [0, 0, 0], "dimensions_m": [0.40, 0.30, 0.35]}],
        "fallback": {"primitive": "box", "dimensions_m": [0.40, 0.30, 0.35], "albedo": "#8c4851"},
    },
}

EXPECTED_POOLS = {
    "biomatter_swarm": ["tripod_hound_v1", "intestinal_dragger_v1"],
    "stalker": ["biped_puppet_v1", "four_legged_scrambler_v1"],
    "hull_tendril": ["tendril_knot_v1", "intestinal_dragger_v1"],
    "puppet_corpse": ["biped_puppet_v1", "tripod_hound_v1"],
    "mimic": ["four_legged_scrambler_v1", "tripod_hound_v1"],
    "drone_swarm": ["tendril_knot_v1", "tripod_hound_v1"],
}


def _edge(instance_id: str, part_id: str, parent: str, socket: str) -> dict[str, str]:
    return {
        "instance_id": instance_id, "part_id": part_id, "parent_instance_id": parent,
        "parent_socket": socket, "child_socket": "root_0", "connector_part_id": CONNECTOR_PART_ID,
    }


EXPECTED_RECIPES: dict[str, dict[str, Any]] = {
    "biped_puppet_v1": {
        "recipe_id": "biped_puppet_v1", "locomotion_hint": "biped",
        "core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
        "attachments": [
            _edge("leg_left", "biomass_human_arm_v1", "core", "limb_0"),
            _edge("leg_right", "biomass_human_arm_v1", "core", "limb_1"),
            _edge("head", "biomass_animal_skull_v1", "core", "head_0"),
            _edge("left_claw", "biomass_claw_v1", "leg_left", "distal_0"),
        ],
    },
    "four_legged_scrambler_v1": {
        "recipe_id": "four_legged_scrambler_v1", "locomotion_hint": "quadruped",
        "core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
        "attachments": [
            _edge("leg_0", "biomass_insect_leg_v1", "core", "limb_0"),
            _edge("leg_1", "biomass_insect_leg_v1", "core", "limb_1"),
            _edge("leg_2", "biomass_insect_leg_v1", "core", "limb_2"),
            _edge("leg_3", "biomass_insect_leg_v1", "core", "limb_3"),
            _edge("head", "biomass_animal_skull_v1", "core", "head_0"),
            _edge("maw", "biomass_maw_v1", "head", "jaw_0"),
        ],
    },
    "tripod_hound_v1": {
        "recipe_id": "tripod_hound_v1", "locomotion_hint": "crawl",
        "core": {"instance_id": "core", "part_id": "biomass_animal_skull_v1"},
        "attachments": [
            _edge("leg_0", "biomass_insect_leg_v1", "core", "appendage_0"),
            _edge("leg_1", "biomass_insect_leg_v1", "core", "appendage_1"),
            _edge("leg_2", "biomass_insect_leg_v1", "core", "appendage_2"),
            _edge("maw", "biomass_maw_v1", "core", "jaw_0"),
            _edge("claw", "biomass_claw_v1", "leg_0", "distal_0"),
        ],
    },
    "intestinal_dragger_v1": {
        "recipe_id": "intestinal_dragger_v1", "locomotion_hint": "drag",
        "core": {"instance_id": "core", "part_id": "biomass_animal_skull_v1"},
        "attachments": [
            _edge("puller", "biomass_cephalopod_tentacle_v1", "core", "appendage_0"),
            _edge("arm", "biomass_human_arm_v1", "core", "appendage_1"),
            _edge("maw", "biomass_maw_v1", "core", "jaw_0"),
        ],
    },
    "tendril_knot_v1": {
        "recipe_id": "tendril_knot_v1", "locomotion_hint": "slither",
        "core": {"instance_id": "core", "part_id": "biomass_humanoid_torso_v1"},
        "attachments": [
            _edge("tendril_0", "biomass_cephalopod_tentacle_v1", "core", "limb_0"),
            _edge("tendril_1", "biomass_cephalopod_tentacle_v1", "core", "limb_1"),
            _edge("maw", "biomass_maw_v1", "tendril_0", "distal_0"),
            _edge("claw", "biomass_claw_v1", "tendril_1", "distal_0"),
        ],
    },
}


def _append(errors: list[str], message: str) -> None:
    errors.append(message)


def _finite_walk(value: Any, path: str, errors: list[str]) -> None:
    if isinstance(value, float) and not math.isfinite(value):
        _append(errors, f"{path}: non-finite number")
    elif isinstance(value, Mapping):
        for key, child in value.items():
            _finite_walk(child, f"{path}.{key}", errors)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _finite_walk(child, f"{path}[{index}]", errors)


def _object(value: Any, expected: set[str], path: str, errors: list[str]) -> bool:
    if not isinstance(value, dict):
        _append(errors, f"{path}: must be an object")
        return False
    for key in value:
        if key not in expected:
            _append(errors, f"{path}: unknown field '{key}'")
    for key in sorted(expected - set(value)):
        _append(errors, f"{path}: missing field '{key}'")
    return True


def _number(value: Any) -> bool:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(value)
    except (OverflowError, ValueError):
        return False


def _vector(value: Any, path: str, errors: list[str]) -> bool:
    if not isinstance(value, list) or len(value) != 3 or not all(_number(item) for item in value):
        _append(errors, f"{path}: must be a finite numeric [x, y, z] array")
        return False
    return True


def _positive_vector(value: Any, path: str, errors: list[str]) -> bool:
    if not _vector(value, path, errors):
        return False
    if any(item <= 0 for item in value):
        _append(errors, f"{path}: dimensions must be positive")
        return False
    return True


def _validate_wrapper(path: Any, part_id: str, project_root: Path, errors: list[str]) -> None:
    label = f"parts.{part_id}.wrapper_scene_path"
    if not isinstance(path, str):
        _append(errors, f"{label}: must be a string")
        return
    if path == "":
        return
    if path.startswith("/") or path.startswith("\\") or re.match(r"^[A-Za-z]:[\\/]", path):
        _append(errors, f"{label}: absolute wrapper path is not allowed")
        return
    if not path.startswith("res://"):
        _append(errors, f"{label}: non-empty wrapper path must use res://")
        return
    relative = path[6:]
    if not relative:
        _append(errors, f"{label}: res:// path must name a file")
        return
    try:
        root = project_root.resolve()
        candidate = (root / relative).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            _append(errors, f"{label}: wrapper path escapes project root")
            return
        if not candidate.is_file():
            _append(errors, f"{label}: wrapper path does not exist: {path}")
    except (ValueError, OSError, RuntimeError):
        _append(errors, f"{label}: wrapper path could not be resolved or checked")


def _validate_socket(socket: Any, part_id: str, index: int, fallback_dimensions: Any, errors: list[str], names: set[str]) -> None:
    path = f"parts.{part_id}.sockets[{index}]"
    if not _object(socket, _SOCKET_FIELDS, path, errors):
        return
    name = socket.get("name")
    if not isinstance(name, str) or SOCKET_RE.fullmatch(name) is None:
        _append(errors, f"{path}.name: invalid socket name")
    elif name in names:
        _append(errors, f"{path}.name: duplicate socket name '{name}'")
    else:
        names.add(name)
    kind = socket.get("kind")
    if not isinstance(kind, str) or kind not in SOCKET_KINDS:
        _append(errors, f"{path}.kind: unsupported socket kind")
    elif isinstance(name, str) and SOCKET_RE.fullmatch(name):
        named_kind = name.split("_")[1]
        if kind != named_kind:
            _append(errors, f"{path}.kind: does not match socket name")
    accepts = socket.get("accepts_categories")
    if not isinstance(accepts, list) or any(not isinstance(item, str) or item not in CATEGORIES for item in accepts):
        _append(errors, f"{path}.accepts_categories: unknown category")
    elif len(set(accepts)) != len(accepts):
        _append(errors, f"{path}.accepts_categories: duplicate category")
    if kind == "root" and accepts != []:
        _append(errors, f"{path}: root socket must have empty accepts_categories")
    if kind != "root" and isinstance(accepts, list) and not accepts:
        _append(errors, f"{path}: non-root socket must accept at least one category")
    if _vector(socket.get("position_m"), f"{path}.position_m", errors) and _vector(fallback_dimensions, "fallback.dimensions_m", errors):
        if any(abs(coordinate) > dimension + 0.05 for coordinate, dimension in zip(socket["position_m"], fallback_dimensions)):
            _append(errors, f"{path}.position_m: position is outside fallback bounds")
    _vector(socket.get("rotation_deg"), f"{path}.rotation_deg", errors)


def _validate_collision(shape: Any, part_id: str, index: int, errors: list[str]) -> None:
    path = f"parts.{part_id}.collision_shapes[{index}]"
    if not isinstance(shape, dict):
        _append(errors, f"{path}: must be an object")
        return
    kind = shape.get("shape")
    if kind == "box":
        expected = _BASE_COLLISION_FIELDS | {"dimensions_m"}
    elif kind == "capsule":
        expected = _BASE_COLLISION_FIELDS | {"radius_m", "height_m"}
    elif kind == "sphere":
        expected = _BASE_COLLISION_FIELDS | {"radius_m"}
    else:
        _append(errors, f"{path}.shape: unsupported collision shape")
        expected = _BASE_COLLISION_FIELDS
    _object(shape, expected, path, errors)
    _vector(shape.get("position_m"), f"{path}.position_m", errors)
    _vector(shape.get("rotation_deg"), f"{path}.rotation_deg", errors)
    if kind == "box":
        _positive_vector(shape.get("dimensions_m"), f"{path}.dimensions_m", errors)
    elif kind == "capsule":
        radius = shape.get("radius_m")
        height = shape.get("height_m")
        if not _number(radius) or radius <= 0:
            _append(errors, f"{path}.radius_m: must be positive")
        if not _number(height) or height <= 0:
            _append(errors, f"{path}.height_m: must be positive")
    elif kind == "sphere":
        radius = shape.get("radius_m")
        if not _number(radius) or radius <= 0:
            _append(errors, f"{path}.radius_m: must be positive")


def _validate_part(part: Any, part_id: str, project_root: Path, errors: list[str]) -> None:
    path = f"parts.{part_id}"
    if not _object(part, _PART_FIELDS, path, errors):
        return
    category = part.get("category")
    if not isinstance(category, str) or category not in CATEGORIES:
        _append(errors, f"{path}.category: unsupported category")
    species = part.get("species_tags")
    if not isinstance(species, list) or not species or any(not isinstance(item, str) or not item for item in species):
        _append(errors, f"{path}.species_tags: must be a non-empty string array")
    elif len(set(species)) != len(species):
        _append(errors, f"{path}.species_tags: duplicate species tag")
    roles = part.get("assembly_roles")
    if not isinstance(roles, list) or not roles or any(not isinstance(item, str) or item not in ASSEMBLY_ROLES for item in roles):
        _append(errors, f"{path}.assembly_roles: unknown role")
    elif len(set(roles)) != len(roles):
        _append(errors, f"{path}.assembly_roles: duplicate assembly role")
    budget = part.get("triangle_budget")
    if not isinstance(budget, int) or isinstance(budget, bool) or budget <= 0:
        _append(errors, f"{path}.triangle_budget: must be a positive integer")
    _validate_wrapper(part.get("wrapper_scene_path"), part_id, project_root, errors)
    fallback = part.get("fallback")
    fallback_dimensions = None
    if _object(fallback, _FALLBACK_FIELDS, f"{path}.fallback", errors):
        primitive = fallback.get("primitive")
        if not isinstance(primitive, str) or primitive not in {"box", "capsule", "sphere"}:
            _append(errors, f"{path}.fallback.primitive: unsupported primitive")
        fallback_dimensions = fallback.get("dimensions_m")
        _positive_vector(fallback_dimensions, f"{path}.fallback.dimensions_m", errors)
        if not isinstance(fallback.get("albedo"), str) or ALBEDO_RE.fullmatch(fallback["albedo"]) is None:
            _append(errors, f"{path}.fallback.albedo: must be a #RRGGBB value")
    sockets = part.get("sockets")
    names: set[str] = set()
    if not isinstance(sockets, list) or not sockets:
        _append(errors, f"{path}.sockets: must be a non-empty array")
    else:
        for index, socket in enumerate(sockets):
            _validate_socket(socket, part_id, index, fallback_dimensions, errors, names)
        if "socket_root_0" not in names:
            _append(errors, f"{path}.sockets: missing root socket socket_root_0")
    shapes = part.get("collision_shapes")
    if not isinstance(shapes, list) or not shapes:
        _append(errors, f"{path}.collision_shapes: must be a non-empty array")
    else:
        for index, shape in enumerate(shapes):
            _validate_collision(shape, part_id, index, errors)


def validate_part_catalog(document: object, project_root: Path) -> list[str]:
    """Return stable diagnostics for the canonical part catalog."""
    errors: list[str] = []
    _finite_walk(document, "document", errors)
    if not _object(document, {"schema_version", "document_kind", "limits", "parts"}, "document", errors):
        return sorted(set(errors))
    if document.get("schema_version") != "1.0.0":
        _append(errors, "document.schema_version: must equal 1.0.0")
    if document.get("document_kind") != "biomass_part_catalog":
        _append(errors, "document.document_kind: must equal biomass_part_catalog")
    limits = document.get("limits")
    if _object(limits, {"max_attachments", "max_depth", "max_triangles", "max_nodes"}, "document.limits", errors):
        expected_limits = {"max_attachments": MAX_ATTACHMENTS, "max_depth": MAX_DEPTH, "max_triangles": MAX_TRIANGLES, "max_nodes": MAX_NODES}
        if limits != expected_limits:
            _append(errors, "document.limits: values do not match canonical limits")
    parts = document.get("parts")
    if not isinstance(parts, dict):
        _append(errors, "document.parts: must be an object")
        return sorted(set(errors))
    expected_ids = set(CANONICAL_PARTS)
    for part_id in sorted(parts, key=str):
        if part_id not in expected_ids:
            _append(errors, f"parts: unknown part id '{part_id}'")
    for part_id in sorted(expected_ids - set(parts)):
        _append(errors, f"parts: missing part id '{part_id}'")
    for part_id in sorted(set(parts) & expected_ids):
        part = parts[part_id]
        _validate_part(part, part_id, project_root, errors)
        expected = CANONICAL_PARTS[part_id]
        if isinstance(part, dict):
            for field in ("category", "species_tags", "assembly_roles", "wrapper_scene_path", "triangle_budget", "sockets", "collision_shapes", "fallback"):
                if field in part and part.get(field) != expected[field]:
                    _append(errors, f"parts.{part_id}.{field}: value does not match canonical contract")
    return sorted(set(errors))


def _as_part_map(part_catalog: Mapping[str, Any]) -> Mapping[str, Any]:
    if isinstance(part_catalog, Mapping) and isinstance(part_catalog.get("parts"), Mapping):
        return part_catalog["parts"]
    return part_catalog


def _find_socket(part: Any, socket_name: str) -> dict[str, Any] | None:
    if not isinstance(part, Mapping) or not isinstance(part.get("sockets"), list):
        return None
    catalog_name = f"socket_{socket_name}"
    for socket in part["sockets"]:
        if isinstance(socket, Mapping) and socket.get("name") == catalog_name:
            return socket
    return None


def _part_roles(part: Any) -> set[str]:
    roles = part.get("assembly_roles", []) if isinstance(part, Mapping) else []
    return {role for role in roles if isinstance(role, str)} if isinstance(roles, list) else set()


def _part_category(part: Any) -> str | None:
    category = part.get("category") if isinstance(part, Mapping) else None
    return category if isinstance(category, str) else None


def _part_budget(part: Any) -> int:
    value = part.get("triangle_budget", 0) if isinstance(part, Mapping) else 0
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0 or value > MAX_TRIANGLES:
        return MAX_TRIANGLES + 1
    return value


def _part_descriptor_count(part: Any) -> int:
    if not isinstance(part, Mapping):
        return 0
    sockets = part.get("sockets")
    shapes = part.get("collision_shapes")
    return (len(sockets) if isinstance(sockets, list) else 0) + (len(shapes) if isinstance(shapes, list) else 0)


def _validate_locomotion(hint: Any, parts: list[Any], errors: list[str]) -> None:
    if not isinstance(hint, str) or hint not in LOCOMOTION_HINTS:
        _append(errors, "locomotion_hint: unsupported locomotion")
        return
    role_counts: dict[str, int] = {}
    for part in parts:
        for role in _part_roles(part):
            role_counts[role] = role_counts.get(role, 0) + 1
    heads = sum(1 for part in parts if _part_category(part) == "biomass_head")
    if hint == "biped":
        if role_counts.get("locomotor", 0) != 2:
            _append(errors, "locomotion_hint: biped requires exactly 2 locomotor parts")
        if heads < 1:
            _append(errors, "locomotion_hint: biped requires a head")
    elif hint == "quadruped":
        if role_counts.get("locomotor", 0) != 4:
            _append(errors, "locomotion_hint: quadruped requires exactly 4 locomotor parts")
        if heads < 1:
            _append(errors, "locomotion_hint: quadruped requires a head")
    elif hint == "crawl" and role_counts.get("locomotor", 0) < 1:
        _append(errors, "locomotion_hint: crawl requires a locomotor part")
    elif hint == "drag" and role_counts.get("puller", 0) < 1:
        _append(errors, "locomotion_hint: drag requires a puller part")
    elif hint == "slither" and role_counts.get("slither", 0) < 1:
        _append(errors, "locomotion_hint: slither requires a slither part")


def validate_recipe(recipe: object, part_catalog: Mapping[str, Any]) -> list[str]:
    """Return stable diagnostics for one attachment-graph recipe."""
    errors: list[str] = []
    _finite_walk(recipe, "recipe", errors)
    if not _object(recipe, _RECIPE_FIELDS, "recipe", errors):
        return sorted(set(errors))
    if not isinstance(recipe, dict):
        return sorted(set(errors))
    parts = _as_part_map(part_catalog)
    if not isinstance(parts, Mapping):
        _append(errors, "part_catalog: must be a mapping")
        return sorted(set(errors))
    if not isinstance(recipe.get("recipe_id"), str) or not recipe["recipe_id"]:
        _append(errors, "recipe.recipe_id: must be a non-empty string")
    if not isinstance(recipe.get("locomotion_hint"), str) or recipe.get("locomotion_hint") not in LOCOMOTION_HINTS:
        _append(errors, "recipe.locomotion_hint: unsupported locomotion")
    core = recipe.get("core")
    core_instance = None
    core_part = None
    if _object(core, _CORE_FIELDS, "recipe.core", errors):
        core_record = core if isinstance(core, dict) else {}
        core_instance = core_record.get("instance_id")
        core_part_id = core_record.get("part_id")
        if not isinstance(core_instance, str) or not core_instance:
            _append(errors, "recipe.core.instance_id: must be a non-empty string")
        if not isinstance(core_part_id, str):
            _append(errors, "recipe.core.part_id: must be a string")
        elif core_part_id not in parts:
            _append(errors, f"recipe.core.part_id: unknown part_id '{core_part_id}'")
        else:
            core_part = parts[core_part_id]
            if "core" not in _part_roles(core_part):
                _append(errors, "recipe.core.part_id: core part lacks core role")
    attachments = recipe.get("attachments")
    if not isinstance(attachments, list):
        _append(errors, "recipe.attachments: must be an array")
        return sorted(set(errors))
    if len(attachments) > MAX_ATTACHMENTS:
        _append(errors, f"recipe.attachments: max attachments exceeded ({len(attachments)} > {MAX_ATTACHMENTS})")

    instances: dict[str, Any] = {}
    depths: dict[str, int] = {}
    part_occurrences: list[Any] = []
    if isinstance(core_instance, str):
        instances[core_instance] = core_part
        depths[core_instance] = 0
        if core_part is not None:
            part_occurrences.append(core_part)
    occupied: set[tuple[str, str]] = set()
    parent_of: dict[str, str] = {}
    edge_parents: list[tuple[str, str]] = []
    for index, edge in enumerate(attachments):
        path = f"recipe.attachments[{index}]"
        if not _object(edge, _EDGE_FIELDS, path, errors):
            continue
        instance_id = edge.get("instance_id")
        parent_id = edge.get("parent_instance_id")
        part_id = edge.get("part_id")
        parent_socket_name = edge.get("parent_socket")
        child_socket_name = edge.get("child_socket")
        connector_id = edge.get("connector_part_id")
        if not isinstance(instance_id, str) or not instance_id:
            _append(errors, f"{path}.instance_id: must be a non-empty string")
        elif instance_id in instances or instance_id in {item[0] for item in edge_parents}:
            _append(errors, f"{path}.instance_id: duplicate instance_id '{instance_id}'")
        if not isinstance(parent_id, str) or not parent_id:
            _append(errors, f"{path}.parent_instance_id: must be a non-empty string")
        if not isinstance(part_id, str):
            _append(errors, f"{path}.part_id: must be a string")
            child_part = None
        elif part_id not in parts:
            _append(errors, f"{path}.part_id: unknown part_id '{part_id}'")
            child_part = None
        else:
            child_part = parts[part_id]
        if connector_id != CONNECTOR_PART_ID:
            _append(errors, f"{path}.connector_part_id: connector must be {CONNECTOR_PART_ID}")
            connector_part = parts.get(connector_id) if isinstance(connector_id, str) else None
        else:
            connector_part = parts.get(CONNECTOR_PART_ID)
        if connector_part is None:
            _append(errors, f"{path}.connector_part_id: unknown connector part")
        elif _part_category(connector_part) != "biomass_connector" or "connector" not in _part_roles(connector_part):
            _append(errors, f"{path}.connector_part_id: connector lacks connector role/category")
        if not isinstance(parent_id, str) or parent_id not in instances:
            _append(errors, f"{path}.parent_instance_id: parent-before-child reference required")
        elif not isinstance(parent_socket_name, str):
            _append(errors, f"{path}.parent_socket: must be a string")
        else:
            if RECIPE_SOCKET_RE.fullmatch(parent_socket_name) is None:
                _append(errors, f"{path}.parent_socket: invalid socket reference")
            parent_part = instances[parent_id]
            parent_socket = _find_socket(parent_part, parent_socket_name)
            if parent_socket is None:
                _append(errors, f"{path}.parent_socket: unknown parent socket")
            else:
                accepts = parent_socket.get("accepts_categories")
                child_category = _part_category(child_part)
                if isinstance(accepts, list) and child_category not in accepts:
                    _append(errors, f"{path}.parent_socket: child category is not accepted")
                occupancy = (parent_id, parent_socket_name)
                if occupancy in occupied:
                    _append(errors, f"{path}.parent_socket: socket occupancy is already used")
                occupied.add(occupancy)
        if child_socket_name != "root_0":
            _append(errors, f"{path}.child_socket: child socket must be root_0")
        if child_part is not None and _find_socket(child_part, "root_0") is None:
            _append(errors, f"{path}.child_socket: child part is missing root socket")
        if isinstance(instance_id, str) and instance_id and instance_id not in instances:
            instances[instance_id] = child_part
            if isinstance(parent_id, str) and parent_id in depths:
                depths[instance_id] = depths[parent_id] + 1
            else:
                depths[instance_id] = MAX_DEPTH + 1
            if child_part is not None:
                part_occurrences.append(child_part)
            if connector_part is not None:
                part_occurrences.append(connector_part)
        if isinstance(instance_id, str) and isinstance(parent_id, str):
            parent_of[instance_id] = parent_id
            edge_parents.append((instance_id, parent_id))
    # Detect cycles separately from the parent-before-child check so malformed graphs
    # cannot evade the graph invariant through an earlier diagnostic path.
    for start in sorted(parent_of):
        seen: set[str] = set()
        current = start
        while current in parent_of:
            if current in seen:
                _append(errors, f"recipe: cycle detected at instance_id '{current}'")
                break
            seen.add(current)
            current = parent_of[current]
    for instance_id, depth in depths.items():
        if depth > MAX_DEPTH:
            _append(errors, f"recipe: max depth exceeded at {instance_id} ({depth} > {MAX_DEPTH})")

    triangle_total = sum(_part_budget(part) for part in part_occurrences)
    if triangle_total > MAX_TRIANGLES:
        _append(errors, f"recipe: triangle limit exceeded ({triangle_total} > {MAX_TRIANGLES})")
    # Conservative host-contract estimate: one assembler root plus two wrapper/visual
    # nodes per occurrence, plus one node per authored socket and collision descriptor.
    runtime_nodes = 1 + sum(2 + _part_descriptor_count(part) for part in part_occurrences)
    if runtime_nodes > MAX_NODES:
        _append(errors, f"recipe: runtime node limit exceeded ({runtime_nodes} > {MAX_NODES})")
    _validate_locomotion(recipe.get("locomotion_hint"), part_occurrences, errors)
    return sorted(set(errors))


def validate_recipe_catalog(document: object, part_catalog: Mapping[str, Any]) -> list[str]:
    """Return stable diagnostics for the recipe catalog and all curated recipes."""
    errors: list[str] = []
    _finite_walk(document, "document", errors)
    if not _object(document, {"schema_version", "document_kind", "recipes", "archetype_pools"}, "document", errors):
        return sorted(set(errors))
    if document.get("schema_version") != "1.0.0":
        _append(errors, "document.schema_version: must equal 1.0.0")
    if document.get("document_kind") != "biomass_recipe_catalog":
        _append(errors, "document.document_kind: must equal biomass_recipe_catalog")
    recipes = document.get("recipes")
    if not isinstance(recipes, dict):
        _append(errors, "document.recipes: must be an object")
        recipes = {}
    expected_ids = set(EXPECTED_RECIPES)
    for recipe_id in sorted(recipes, key=str):
        if recipe_id not in expected_ids:
            _append(errors, f"recipes: unknown recipe id '{recipe_id}'")
    for recipe_id in sorted(expected_ids - set(recipes)):
        _append(errors, f"recipes: missing recipe id '{recipe_id}'")
    seen_recipe_ids: dict[str, str] = {}
    part_map = _as_part_map(part_catalog)
    for recipe_id in sorted(recipes, key=str):
        item = recipes[recipe_id]
        if isinstance(item, dict):
            actual_id = item.get("recipe_id")
            if isinstance(actual_id, str):
                if actual_id in seen_recipe_ids:
                    _append(errors, f"recipes: duplicate recipe_id '{actual_id}'")
                seen_recipe_ids[actual_id] = str(recipe_id)
        if recipe_id not in expected_ids:
            continue
        errors.extend(validate_recipe(item, part_map))
        if isinstance(item, dict) and item != EXPECTED_RECIPES[recipe_id]:
            _append(errors, f"recipes.{recipe_id}: value does not match canonical recipe")
    pools = document.get("archetype_pools")
    if not isinstance(pools, dict):
        _append(errors, "document.archetype_pools: must be an object")
        pools = {}
    for pool_id in sorted(pools, key=str):
        if pool_id not in EXPECTED_POOLS:
            _append(errors, f"archetype_pools: unknown pool '{pool_id}'")
    for pool_id in sorted(set(EXPECTED_POOLS) - set(pools)):
        _append(errors, f"archetype_pools: missing pool '{pool_id}'")
    for pool_id in sorted(set(pools) & set(EXPECTED_POOLS)):
        value = pools[pool_id]
        if not isinstance(value, list):
            _append(errors, f"archetype_pools.{pool_id}: must be an array")
        elif value != EXPECTED_POOLS[pool_id]:
            _append(errors, f"archetype_pools.{pool_id}: value does not match canonical pool")
        for recipe_id in value if isinstance(value, list) else []:
            if not isinstance(recipe_id, str):
                _append(errors, f"archetype_pools.{pool_id}: recipe id must be a string")
            elif recipe_id not in recipes:
                _append(errors, f"archetype_pools.{pool_id}: unknown recipe id '{recipe_id}'")
    return sorted(set(errors))


def canonical_recipe_bytes(recipe: Mapping[str, Any]) -> bytes:
    """Serialize a recipe using the repository's canonical JSON byte contract."""
    return (json.dumps(recipe, sort_keys=True, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON object key: {key}")
        value[key] = item
    return value


def _reject_constant(value: str) -> Any:
    raise ValueError(f"non-finite JSON constant: {value}")


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_reject_duplicate_keys, parse_constant=_reject_constant)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path("."))
    parser.add_argument("--parts", type=Path, default=Path("data/combat/biomass_part_catalog.json"))
    parser.add_argument("--recipes", type=Path, default=Path("data/combat/biomass_recipe_catalog.json"))
    args = parser.parse_args(argv)
    project_root = args.project_root.expanduser().resolve()
    errors: list[str] = []

    def resolve_input(path: Path) -> Path:
        return path if path.is_absolute() else project_root / path

    try:
        parts_document = _load_json(resolve_input(args.parts))
    except (OSError, ValueError) as exc:
        errors.append(f"parts: {exc}")
        parts_document = {}
    try:
        errors.extend(validate_part_catalog(parts_document, project_root))
    except (ValueError, OSError, RuntimeError):
        errors.append("parts: validation failed due to malformed data or filesystem state")
    part_map = parts_document.get("parts", {}) if isinstance(parts_document, dict) else {}
    try:
        recipes_document = _load_json(resolve_input(args.recipes))
    except (OSError, ValueError) as exc:
        errors.append(f"recipes: {exc}")
        recipes_document = {}
    try:
        errors.extend(validate_recipe_catalog(recipes_document, part_map if isinstance(part_map, Mapping) else {}))
    except (ValueError, OSError, RuntimeError):
        errors.append("recipes: validation failed due to malformed data or filesystem state")
    errors = sorted(set(errors))
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print("BIOMASS CATALOG VALIDATION PASS parts=8 recipes=5 archetypes=6")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
