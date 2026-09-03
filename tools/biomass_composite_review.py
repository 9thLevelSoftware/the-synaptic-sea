#!/usr/bin/env python3
"""Run and verify the governed placeholder biomass composite review.

The renderer is deliberately one production capture per process.  This host
orchestrator owns the 5 x 2 x 3 matrix, the canonical report, and the evidence
root; the Godot script only reports facts observed in the production scene.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Mapping

SCHEMA_VERSION = "1.0.0"
DOCUMENT_KIND = "biomass_composite_review_v1"
CAPTURE_MARKER = "BIOMASS COMPOSITE CASE PASS "
FINAL_MARKER = "BIOMASS COMPOSITE REVIEW PASS stage={stage} gaits=5 seeds=2 lighting=3 captures=30"
CAPTURE_SCRIPT = "res://scripts/validation/biomass_visual_review.gd"
MAIN_SCENE = "res://scenes/main.tscn"
CAMERA_SCRIPT = "res://scripts/camera/iso_camera_rig.gd"
PLACEHOLDER_ROOT = Path("artifacts/validation-previews/biomass-assembly-placeholder")
FINAL_ROOT = Path("artifacts/validation-previews/biomass-assembly-final")
RECIPE_IDS = (
    "biped_puppet_v1",
    "four_legged_scrambler_v1",
    "intestinal_dragger_v1",
    "tendril_knot_v1",
    "tripod_hound_v1",
)
SEEDS = (42, 777)
LIGHTING_MODES = ("normal", "emergency", "dark")
ARCHETYPE_IDS = (
    "biomatter_swarm",
    "drone_swarm",
    "hull_tendril",
    "mimic",
    "puppet_corpse",
    "stalker",
)
RECIPE_SEED_ARCHETYPES: dict[tuple[str, int], str] = {
    ("biped_puppet_v1", 42): "stalker",
    ("biped_puppet_v1", 777): "puppet_corpse",
    ("four_legged_scrambler_v1", 42): "stalker",
    ("four_legged_scrambler_v1", 777): "mimic",
    ("tripod_hound_v1", 42): "biomatter_swarm",
    ("tripod_hound_v1", 777): "drone_swarm",
    ("intestinal_dragger_v1", 42): "biomatter_swarm",
    ("intestinal_dragger_v1", 777): "hull_tendril",
    ("tendril_knot_v1", 42): "hull_tendril",
    ("tendril_knot_v1", 777): "drone_swarm",
}
POOL_MEMBERSHIP: dict[str, tuple[str, ...]] = {
    "biomatter_swarm": ("tripod_hound_v1", "intestinal_dragger_v1"),
    "stalker": ("biped_puppet_v1", "four_legged_scrambler_v1"),
    "hull_tendril": ("tendril_knot_v1", "intestinal_dragger_v1"),
    "puppet_corpse": ("biped_puppet_v1", "tripod_hound_v1"),
    "mimic": ("four_legged_scrambler_v1", "tripod_hound_v1"),
    "drone_swarm": ("tendril_knot_v1", "tripod_hound_v1"),
}
ORACLES: dict[str, dict[str, int]] = {
    "biped_puppet_v1": {"attachments": 4, "occurrences": 9, "nodes": 58, "triangles": 17000},
    "four_legged_scrambler_v1": {"attachments": 6, "occurrences": 13, "nodes": 78, "triangles": 23000},
    "tripod_hound_v1": {"attachments": 5, "occurrences": 11, "nodes": 58, "triangles": 16500},
    "intestinal_dragger_v1": {"attachments": 3, "occurrences": 7, "nodes": 39, "triangles": 11500},
    "tendril_knot_v1": {"attachments": 4, "occurrences": 9, "nodes": 53, "triangles": 15000},
}
# These are validation-owned stress profiles applied through the production
# SliceAtmosphereApplier.  They intentionally do not become game configuration.
LIGHTING_PROFILES: dict[str, dict[str, Any]] = {
    "normal": {
        "ambient_color": [0.12, 0.20, 0.40],
        "ambient_energy": 0.72,
        "key_light_color": [0.72, 0.84, 1.0],
        "key_light_energy": 1.5,
        "fog_enabled": True,
        "fog_density": 0.032,
        "away_fog_density_mult": 1.6,
        "emergency_accent": None,
        "emergency_accent_energy": None,
        "is_away": True,
    },
    "emergency": {
        "ambient_color": [0.22, 0.035, 0.02],
        "ambient_energy": 0.38,
        "key_light_color": [1.0, 0.22, 0.10],
        "key_light_energy": 0.65,
        "fog_enabled": True,
        "fog_density": 0.032,
        "away_fog_density_mult": 1.6,
        "emergency_accent": "#ff6a3d",
        "emergency_accent_energy": 0.16,
        "is_away": True,
    },
    "dark": {
        "ambient_color": [0.025, 0.045, 0.10],
        "ambient_energy": 0.16,
        "key_light_color": [0.18, 0.28, 0.55],
        "key_light_energy": 0.18,
        "fog_enabled": True,
        "fog_density": 0.032,
        "away_fog_density_mult": 1.6,
        "emergency_accent": None,
        "emergency_accent_energy": None,
        "is_away": True,
    },
}
PROTECTED_PATHS = (
    "scenes/main.tscn",
    "scripts/procgen/playable_generated_ship.gd",
    "scripts/procgen/generated_ship_loader.gd",
    "scripts/procgen/slice_atmosphere_applier.gd",
    "scripts/camera/iso_camera_rig.gd",
    "scripts/systems/threat_manager.gd",
    "scripts/threats/biomass_assembler.gd",
    "scripts/threats/biomass_threat_visual.gd",
    "data/combat/biomass_part_catalog.json",
    "data/combat/biomass_recipe_catalog.json",
    "data/combat/threat_visual_catalog.json",
    "data/procgen/biomes/breach_field.json",
)
# Only these two baseline teardown diagnostics are inherited from the project.
ALLOWED_TEARDOWN_DIAGNOSTICS = (
    "ERROR: Capture not registered: 'gdaimcp'.",
    "WARNING: ObjectDB instances leaked at exit",
)
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")

TOP_LEVEL_FIELDS = frozenset(
    {
        "schema_version",
        "document_kind",
        "visual_stage",
        "commit",
        "godot_version",
        "catalogs",
        "recipes",
        "cases",
        "protected_digests",
        "pass",
    }
)
CATALOG_FIELDS = frozenset({"parts", "recipes"})
CATALOG_RECORD_FIELDS = frozenset({"path", "sha256", "byte_size"})
RECIPE_RECORD_FIELDS = frozenset({"recipe_document", "sha256", "oracle"})
CASE_FIELDS = frozenset(
    {
        "case_id",
        "recipe_id",
        "seed",
        "lighting",
        "visual_stage",
        "archetype_id",
        "pool_membership",
        "recipe_sha256",
        "recipe_document",
        "command",
        "exit_code",
        "stdout",
        "stderr",
        "output",
        "runtime",
        "pass",
    }
)
OUTPUT_FIELDS = frozenset({"path", "sha256", "byte_size", "width", "height"})
RUNTIME_FIELDS = frozenset(
    {
        "attachments",
        "occurrences",
        "nodes",
        "triangles",
        "max_nodes",
        "max_triangles",
        "aabb_extents_m",
        "collision_count",
        "enabled_collision_count",
        "disabled_connector_collision_count",
        "direct_body_collision_children",
        "body_collision_layer",
        "body_collision_mask",
        "ray_hit",
        "ray_miss_after_free",
        "gait_frames",
        "gait_delta_seconds",
        "wrapper_paths_empty",
        "primitive_mesh_parts",
        "lighting",
        "paired_visibility",
    }
)
LIGHTING_FIELDS = frozenset(
    {
        "applied",
        "key_light_applied",
        "is_away",
        "ambient_color",
        "ambient_energy",
        "key_light_color",
        "key_light_energy",
        "fog_enabled",
        "fog_density",
        "emergency_accent_present",
        "emergency_accent_applied",
        "emergency_accent_energy",
    }
)
PAIRED_FIELDS = frozenset({"rgb_delta", "changed_pixels", "changed_bbox_width", "changed_bbox_height"})


class ReviewError(ValueError):
    """Raised for malformed input or untrusted review evidence."""


def canonical_json_bytes(value: Any) -> bytes:
    """Return compact, sorted, newline-terminated JSON with finite numbers only."""
    try:
        text = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (TypeError, ValueError) as exc:
        raise ReviewError(f"cannot canonicalize JSON: {exc}") from exc
    return (text + "\n").encode("utf-8")


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_bytes().decode("utf-8"), object_pairs_hook=_reject_duplicate_keys)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError, RecursionError) as exc:
        raise ReviewError(f"invalid JSON: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ReviewError(f"JSON document must be an object: {path}")
    return value


def sha256_file(path: Path) -> str:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError as exc:
        raise ReviewError(f"cannot hash file: {path}") from exc


def _absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(path.expanduser())))


def _contained(root: Path, path: Path) -> bool:
    root = _absolute(root)
    path = _absolute(path)
    return path == root or root in path.parents


def _reject_symlink(path: Path, label: str) -> None:
    current = Path(path.anchor)
    for part in _absolute(path).parts[1:]:
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            continue
        except OSError as exc:
            raise ReviewError(f"cannot inspect {label}: {path}") from exc
        if stat.S_ISLNK(mode):
            raise ReviewError(f"{label} contains symlink: {current}")


def _regular_file(path: Path, label: str, *, nonempty: bool = True) -> Path:
    _reject_symlink(path, label)
    try:
        info = path.lstat()
    except FileNotFoundError as exc:
        raise ReviewError(f"missing {label}: {path}") from exc
    if not stat.S_ISREG(info.st_mode) or (nonempty and info.st_size <= 0):
        raise ReviewError(f"{label} must be a non-empty regular file: {path}")
    return path


def _project_relative(project_root: Path, path: Path) -> str:
    try:
        return _absolute(path).relative_to(_absolute(project_root)).as_posix()
    except ValueError as exc:
        raise ReviewError(f"path escapes project root: {path}") from exc


def _expected_root(project_root: Path, stage: str) -> Path:
    if stage not in {"placeholder", "final"}:
        raise ReviewError(f"unsupported visual stage: {stage}")
    return _absolute(project_root) / (PLACEHOLDER_ROOT if stage == "placeholder" else FINAL_ROOT)


def case_id(stage: str, recipe_id: str, seed: int, lighting: str) -> str:
    if stage not in {"placeholder", "final"} or recipe_id not in RECIPE_IDS or seed not in SEEDS or lighting not in LIGHTING_MODES:
        raise ReviewError("invalid case identity")
    return f"{stage}/{recipe_id}/seed-{seed}/{lighting}"


def capture_name(recipe_id: str, seed: int, lighting: str) -> str:
    return f"{recipe_id}__seed-{seed}__{lighting}.png"


def validate_archetype_mapping(mapping: Mapping[tuple[str, int], str]) -> list[str]:
    errors: list[str] = []
    expected = set(RECIPE_SEED_ARCHETYPES)
    actual = set(mapping)
    for missing in sorted(expected - actual, key=str):
        errors.append(f"mapping missing: {missing[0]} seed={missing[1]}")
    for extra in sorted(actual - expected, key=str):
        errors.append(f"mapping extra: {extra!r}")
    for key in sorted(expected & actual, key=str):
        expected_value = RECIPE_SEED_ARCHETYPES[key]
        if mapping[key] != expected_value:
            errors.append(f"mapping altered for {key[0]} seed={key[1]}: {mapping[key]!r}")
        if mapping[key] not in ARCHETYPE_IDS:
            errors.append(f"mapping unknown archetype: {mapping[key]}")
    if set(mapping.values()) != set(ARCHETYPE_IDS):
        errors.append("mapping does not cover all six archetype pools")
    for recipe, seed in expected:
        archetype = mapping.get((recipe, seed))
        if archetype in POOL_MEMBERSHIP and recipe not in POOL_MEMBERSHIP[archetype]:
            errors.append(f"mapping incompatible: {recipe} seed={seed} -> {archetype}")
    return errors


def build_case_matrix(stage: str) -> list[dict[str, Any]]:
    errors = validate_archetype_mapping(RECIPE_SEED_ARCHETYPES)
    if errors:
        raise ReviewError("; ".join(errors))
    cases = [
        {
            "case_id": case_id(stage, recipe, seed, lighting),
            "recipe_id": recipe,
            "seed": seed,
            "lighting": lighting,
            "visual_stage": stage,
            "archetype_id": RECIPE_SEED_ARCHETYPES[(recipe, seed)],
        }
        for recipe in RECIPE_IDS
        for seed in SEEDS
        for lighting in LIGHTING_MODES
    ]
    cases.sort(key=lambda item: item["case_id"])
    return cases


def validate_case_matrix(cases: list[Mapping[str, Any]], stage: str) -> list[str]:
    errors: list[str] = []
    if len(cases) != 30:
        errors.append(f"matrix must contain exactly 30 cases, got {len(cases)}")
    actual_ids = [str(case.get("case_id", "")) for case in cases]
    expected = build_case_matrix(stage)
    expected_ids = [case["case_id"] for case in expected]
    if actual_ids != sorted(actual_ids):
        errors.append("case IDs are not sorted")
    if len(set(actual_ids)) != len(actual_ids):
        errors.append("duplicate case ID")
    if actual_ids != expected_ids:
        errors.append("case matrix is missing, extra, stale, or incorrectly qualified")
    for case in cases:
        recipe = case.get("recipe_id")
        seed = case.get("seed")
        lighting = case.get("lighting")
        if (recipe, seed) in RECIPE_SEED_ARCHETYPES and case.get("archetype_id") != RECIPE_SEED_ARCHETYPES[(recipe, seed)]:
            errors.append(f"mapping mismatch for {case.get('case_id', '<unknown>')}")
        if case.get("visual_stage") != stage:
            errors.append(f"case stage mismatch for {case.get('case_id', '<unknown>')}")
        if recipe not in RECIPE_IDS or seed not in SEEDS or lighting not in LIGHTING_MODES:
            errors.append(f"unknown case coordinates for {case.get('case_id', '<unknown>')}")
    return sorted(set(errors))


def _png_dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ReviewError("output is not a PNG")
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    if width <= 0 or height <= 0:
        raise ReviewError("PNG dimensions must be positive")
    return width, height


def inspect_png(path: Path) -> dict[str, int]:
    _regular_file(path, "PNG")
    data = path.read_bytes()
    width, height = _png_dimensions(data)
    return {"width": width, "height": height, "byte_size": len(data)}


def _unknown(errors: list[str], value: Any, allowed: frozenset[str], path: str) -> None:
    if not isinstance(value, dict):
        errors.append(f"{path}: must be an object")
        return
    for key in sorted(set(value) - allowed):
        errors.append(f"{path}: unknown field '{key}'")


def _require_fields(errors: list[str], value: Any, fields: frozenset[str], path: str) -> None:
    if isinstance(value, dict):
        for key in sorted(fields - set(value)):
            errors.append(f"{path}: missing field '{key}'")


def _finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _equal_float_list(actual: Any, expected: list[float], path: str, errors: list[str], tolerance: float = 1e-6) -> None:
    if not isinstance(actual, list) or len(actual) != len(expected) or not all(_finite_number(item) for item in actual):
        errors.append(f"{path}: expected finite numeric array")
        return
    if any(abs(float(a) - b) > tolerance for a, b in zip(actual, expected)):
        errors.append(f"{path}: observed value differs from production profile")


def _validate_lighting(value: Any, lighting: str, errors: list[str]) -> None:
    path = "runtime.lighting"
    _unknown(errors, value, LIGHTING_FIELDS, path)
    _require_fields(errors, value, LIGHTING_FIELDS, path)
    if not isinstance(value, dict):
        return
    profile = LIGHTING_PROFILES[lighting]
    for key in ("applied", "key_light_applied", "is_away", "fog_enabled"):
        if value.get(key) is not (True):
            errors.append(f"{path}.{key}: must be true")
    _equal_float_list(value.get("ambient_color"), profile["ambient_color"], f"{path}.ambient_color", errors)
    _equal_float_list(value.get("key_light_color"), profile["key_light_color"], f"{path}.key_light_color", errors)
    for key in ("ambient_energy", "key_light_energy", "fog_density"):
        if not _finite_number(value.get(key)) or abs(float(value[key]) - float(profile[key])) > 1e-6:
            errors.append(f"{path}.{key}: differs from expected {profile[key]}")
    emergency_present = value.get("emergency_accent_present")
    emergency_applied = value.get("emergency_accent_applied")
    expected_emergency = lighting == "emergency"
    if emergency_present is not expected_emergency or emergency_applied is not expected_emergency:
        errors.append(f"{path}: emergency accent presence does not match lighting")
    expected_energy = profile["emergency_accent_energy"]
    if expected_energy is None:
        if value.get("emergency_accent_energy") is not None:
            errors.append(f"{path}.emergency_accent_energy: must be null outside emergency")
    elif not _finite_number(value.get("emergency_accent_energy")) or abs(float(value["emergency_accent_energy"]) - expected_energy) > 1e-6:
        errors.append(f"{path}.emergency_accent_energy: expected {expected_energy}")


def _validate_runtime(value: Any, case: Mapping[str, Any], errors: list[str]) -> None:
    _unknown(errors, value, RUNTIME_FIELDS, "runtime")
    _require_fields(errors, value, RUNTIME_FIELDS, "runtime")
    if not isinstance(value, dict):
        return
    recipe = str(case["recipe_id"])
    oracle = ORACLES[recipe]
    for key in ("attachments", "occurrences", "nodes", "triangles", "max_nodes", "max_triangles", "collision_count", "enabled_collision_count", "disabled_connector_collision_count", "direct_body_collision_children", "body_collision_layer", "body_collision_mask", "gait_frames"):
        if not isinstance(value.get(key), int) or isinstance(value.get(key), bool):
            errors.append(f"runtime.{key}: must be an integer")
    expected_values = {
        "attachments": oracle["attachments"],
        "occurrences": oracle["occurrences"],
        "nodes": oracle["nodes"],
        "triangles": oracle["triangles"],
        "max_nodes": 160,
        "max_triangles": 24000,
        "collision_count": oracle["occurrences"],
        "enabled_collision_count": oracle["occurrences"] - oracle["attachments"],
        "disabled_connector_collision_count": oracle["attachments"],
        "direct_body_collision_children": oracle["occurrences"],
        "body_collision_layer": 1,
        "body_collision_mask": 1,
        "gait_frames": 120,
    }
    for key, expected in expected_values.items():
        if value.get(key) != expected:
            errors.append(f"runtime.{key}: expected {expected}, got {value.get(key)!r}")
    if value.get("nodes", 0) > 160 or value.get("triangles", 0) > 24000:
        errors.append("runtime exceeds review caps")
    extents = value.get("aabb_extents_m")
    if not isinstance(extents, list) or len(extents) != 3 or not all(_finite_number(item) for item in extents):
        errors.append("runtime.aabb_extents_m: expected three finite extents")
    elif any(float(item) < 0.05 or float(item) > 20.0 for item in extents):
        errors.append("runtime.aabb_extents_m: every extent must be within 0.05..20m")
    for key in ("ray_hit", "ray_miss_after_free", "wrapper_paths_empty", "primitive_mesh_parts"):
        if value.get(key) is not True:
            errors.append(f"runtime.{key}: must be true for placeholder review")
    if not _finite_number(value.get("gait_delta_seconds")) or abs(float(value["gait_delta_seconds"]) - (1.0 / 60.0)) > 1e-9:
        errors.append("runtime.gait_delta_seconds: must be exactly 1/60")
    _validate_lighting(value.get("lighting"), str(case["lighting"]), errors)
    paired = value.get("paired_visibility")
    _unknown(errors, paired, PAIRED_FIELDS, "runtime.paired_visibility")
    _require_fields(errors, paired, PAIRED_FIELDS, "runtime.paired_visibility")
    if isinstance(paired, dict):
        if not _finite_number(paired.get("rgb_delta")) or float(paired["rgb_delta"]) < 8.0 / 255.0:
            errors.append("runtime.paired_visibility.rgb_delta: below 8/255")
        for key, minimum in (("changed_pixels", 64), ("changed_bbox_width", 8), ("changed_bbox_height", 8)):
            if not isinstance(paired.get(key), int) or paired[key] < minimum:
                errors.append(f"runtime.paired_visibility.{key}: below required threshold")


def _validate_output(value: Any, case: Mapping[str, Any], project_root: Path, errors: list[str], artifact_root: Path | None = None) -> None:
    _unknown(errors, value, OUTPUT_FIELDS, "output")
    _require_fields(errors, value, OUTPUT_FIELDS, "output")
    if not isinstance(value, dict):
        return
    path_value = value.get("path")
    expected_name = capture_name(str(case["recipe_id"]), int(case["seed"]), str(case["lighting"]))
    stage_root = _expected_root(project_root, str(case["visual_stage"]))
    if not isinstance(path_value, str) or Path(path_value).is_absolute() or ".." in Path(path_value).parts:
        errors.append("output.path: must be project-relative and contained")
        return
    if path_value != (_project_relative(project_root, stage_root) + "/" + expected_name):
        errors.append(f"output.path: expected canonical capture path, got {path_value!r}")
    disk_root = artifact_root if artifact_root is not None else stage_root
    path = disk_root / expected_name
    try:
        info = inspect_png(path)
    except ReviewError as exc:
        errors.append(str(exc))
        return
    if value.get("sha256") != sha256_file(path) or not isinstance(value.get("sha256"), str) or not HEX64_RE.fullmatch(value["sha256"]):
        errors.append("output.sha256: hash drift or malformed hash")
    for key in ("byte_size", "width", "height"):
        if value.get(key) != info[key]:
            errors.append(f"output.{key}: does not match PNG")


def _validate_command(value: Any, case: Mapping[str, Any], errors: list[str]) -> None:
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        errors.append("command: must be an argv array")
        return
    try:
        separator = value.index("--")
    except ValueError:
        errors.append("command: missing user-argument separator")
        return
    expected_user = [
        "--recipe-id", str(case["recipe_id"]),
        "--seed", str(case["seed"]),
        "--archetype-id", str(case["archetype_id"]),
        "--lighting", str(case["lighting"]),
        "--visual-stage", str(case["visual_stage"]),
    ]
    user = value[separator + 1 :]
    if user[: len(expected_user)] != expected_user:
        errors.append("command: renderer arguments are not exact")
    if "shell=True" in value or CAPTURE_SCRIPT not in value:
        errors.append("command: unsafe or wrong renderer invocation")


def validate_manifest(document: Mapping[str, Any], project_root: Path, artifact_root: Path | None = None) -> list[str]:
    errors: list[str] = []
    _unknown(errors, document, TOP_LEVEL_FIELDS, "manifest")
    _require_fields(errors, document, TOP_LEVEL_FIELDS, "manifest")
    if not isinstance(document, dict):
        return errors
    if document.get("schema_version") != SCHEMA_VERSION:
        errors.append("manifest.schema_version: unsupported")
    if document.get("document_kind") != DOCUMENT_KIND:
        errors.append("manifest.document_kind: wrong kind")
    stage = document.get("visual_stage")
    if stage not in {"placeholder", "final"}:
        errors.append("manifest.visual_stage: must be placeholder or final")
        stage = "placeholder"
    if not isinstance(document.get("commit"), str) or not HEX40_RE.fullmatch(document["commit"]):
        errors.append("manifest.commit: must be a 40-character SHA")
    if not isinstance(document.get("godot_version"), str) or not document["godot_version"].strip():
        errors.append("manifest.godot_version: required")
    catalogs = document.get("catalogs")
    _unknown(errors, catalogs, CATALOG_FIELDS, "manifest.catalogs")
    _require_fields(errors, catalogs, CATALOG_FIELDS, "manifest.catalogs")
    expected_catalogs = {
        "parts": "data/combat/biomass_part_catalog.json",
        "recipes": "data/combat/biomass_recipe_catalog.json",
    }
    if isinstance(catalogs, dict):
        for key, relative in expected_catalogs.items():
            record = catalogs.get(key)
            _unknown(errors, record, CATALOG_RECORD_FIELDS, f"manifest.catalogs.{key}")
            _require_fields(errors, record, CATALOG_RECORD_FIELDS, f"manifest.catalogs.{key}")
            if not isinstance(record, dict) or record.get("path") != relative:
                errors.append(f"manifest.catalogs.{key}.path: wrong protected path")
            else:
                path = _absolute(project_root) / relative
                try:
                    info = _regular_file(path, "catalog")
                    if record.get("sha256") != sha256_file(info) or record.get("byte_size") != info.stat().st_size:
                        errors.append(f"manifest.catalogs.{key}: hash drift")
                except ReviewError as exc:
                    errors.append(str(exc))
    recipe_records = document.get("recipes")
    if not isinstance(recipe_records, dict) or set(recipe_records) != set(RECIPE_IDS):
        errors.append("manifest.recipes: must contain exactly the five curated recipes")
    recipes_doc: dict[str, Any] = {}
    recipes_path = _absolute(project_root) / expected_catalogs["recipes"]
    try:
        source_recipes = load_json(recipes_path).get("recipes", {})
        if not isinstance(source_recipes, dict):
            raise ReviewError("recipe catalog recipes is not an object")
        recipes_doc = source_recipes
    except ReviewError as exc:
        errors.append(str(exc))
    if isinstance(recipe_records, dict):
        for recipe_id in RECIPE_IDS:
            record = recipe_records.get(recipe_id)
            _unknown(errors, record, RECIPE_RECORD_FIELDS, f"manifest.recipes.{recipe_id}")
            _require_fields(errors, record, RECIPE_RECORD_FIELDS, f"manifest.recipes.{recipe_id}")
            if not isinstance(record, dict):
                continue
            recipe_document = record.get("recipe_document")
            if recipe_document != recipes_doc.get(recipe_id):
                errors.append(f"manifest.recipes.{recipe_id}: recipe document drift")
            if isinstance(recipe_document, dict):
                recipe_hash = hashlib.sha256(canonical_json_bytes(recipe_document)).hexdigest()
                if record.get("sha256") != recipe_hash:
                    errors.append(f"manifest.recipes.{recipe_id}: recipe hash drift")
            if record.get("oracle") != ORACLES.get(recipe_id):
                errors.append(f"manifest.recipes.{recipe_id}: oracle drift")
    cases = document.get("cases")
    if not isinstance(cases, list):
        errors.append("manifest.cases: must be an array")
        cases = []
    else:
        errors.extend(validate_case_matrix(cases, stage))
    for index, case in enumerate(cases):
        prefix = f"manifest.cases[{index}]"
        _unknown(errors, case, CASE_FIELDS, prefix)
        _require_fields(errors, case, CASE_FIELDS, prefix)
        if not isinstance(case, dict):
            continue
        coordinates = (case.get("recipe_id"), case.get("seed"), case.get("lighting"))
        if coordinates[0] in RECIPE_IDS and coordinates[1] in SEEDS:
            expected_arch = RECIPE_SEED_ARCHETYPES[coordinates[:2]]
            if case.get("archetype_id") != expected_arch:
                errors.append(f"{prefix}.archetype_id: mapping drift")
            if case.get("pool_membership") is not True or coordinates[0] not in POOL_MEMBERSHIP.get(expected_arch, ()):
                errors.append(f"{prefix}.pool_membership: verified pool membership required")
            expected_recipe_doc = recipes_doc.get(str(coordinates[0]))
            if case.get("recipe_document") != expected_recipe_doc:
                errors.append(f"{prefix}.recipe_document: drift")
            if isinstance(expected_recipe_doc, dict):
                expected_hash = hashlib.sha256(canonical_json_bytes(expected_recipe_doc)).hexdigest()
                if case.get("recipe_sha256") != expected_hash:
                    errors.append(f"{prefix}.recipe_sha256: drift")
        _validate_command(case.get("command"), case, errors)
        if case.get("exit_code") != 0:
            errors.append(f"{prefix}.exit_code: renderer failed")
        if not isinstance(case.get("stdout"), str) or CAPTURE_MARKER not in case.get("stdout", ""):
            errors.append(f"{prefix}.stdout: missing case pass marker")
        if not isinstance(case.get("stderr"), str):
            errors.append(f"{prefix}.stderr: must be captured text")
        _validate_output(case.get("output"), case, _absolute(project_root), errors, artifact_root)
        _validate_runtime(case.get("runtime"), case, errors)
        if case.get("pass") is not True:
            errors.append(f"{prefix}.pass: must be true")
    digests = document.get("protected_digests")
    if not isinstance(digests, dict) or set(digests) != {"before", "after"}:
        errors.append("manifest.protected_digests: requires before and after")
    elif digests.get("before") != digests.get("after"):
        errors.append("manifest.protected_digests: protected surface changed during run")
    else:
        for side in ("before", "after"):
            values = digests.get(side)
            if not isinstance(values, dict):
                errors.append(f"manifest.protected_digests.{side}: must be an object")
            else:
                for relative, digest in values.items():
                    if relative not in PROTECTED_PATHS or not isinstance(digest, str) or not HEX64_RE.fullmatch(digest):
                        errors.append(f"manifest.protected_digests.{side}: invalid protected record")
    if document.get("pass") is not True:
        errors.append("manifest.pass: must be true")
    return sorted(set(errors))


def snapshot_protected_surfaces(project_root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for relative in PROTECTED_PATHS:
        path = _absolute(project_root) / relative
        _regular_file(path, "protected surface")
        result[relative] = sha256_file(path)
    return result


def _catalog_documents(project_root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    parts_path = _absolute(project_root) / "data/combat/biomass_part_catalog.json"
    recipes_path = _absolute(project_root) / "data/combat/biomass_recipe_catalog.json"
    return load_json(parts_path), load_json(recipes_path)


def _catalog_records(project_root: Path) -> dict[str, dict[str, Any]]:
    records: dict[str, dict[str, Any]] = {}
    for key, relative in (("parts", "data/combat/biomass_part_catalog.json"), ("recipes", "data/combat/biomass_recipe_catalog.json")):
        path = _absolute(project_root) / relative
        _regular_file(path, "catalog")
        records[key] = {"path": relative, "sha256": sha256_file(path), "byte_size": path.stat().st_size}
    return records


def _recipe_records(recipes_document: Mapping[str, Any]) -> dict[str, dict[str, Any]]:
    raw = recipes_document.get("recipes")
    if not isinstance(raw, dict) or set(raw) != set(RECIPE_IDS):
        raise ReviewError("recipe catalog does not contain exactly the five curated recipes")
    return {
        recipe_id: {
            "recipe_document": raw[recipe_id],
            "sha256": hashlib.sha256(canonical_json_bytes(raw[recipe_id])).hexdigest(),
            "oracle": ORACLES[recipe_id],
        }
        for recipe_id in RECIPE_IDS
    }


def case_marker(payload: Mapping[str, Any]) -> str:
    return CAPTURE_MARKER + canonical_json_bytes(dict(payload)).decode("utf-8").rstrip("\n")


def parse_case_marker(stdout: str, case: Mapping[str, Any]) -> dict[str, Any]:
    lines = [line for line in stdout.splitlines() if line.startswith(CAPTURE_MARKER)]
    if len(lines) != 1:
        raise ReviewError("expected exactly one biomass composite case pass marker")
    try:
        payload = json.loads(lines[0][len(CAPTURE_MARKER) :], object_pairs_hook=_reject_duplicate_keys)
    except (json.JSONDecodeError, ValueError) as exc:
        raise ReviewError(f"case marker JSON is invalid: {exc}") from exc
    if not isinstance(payload, dict):
        raise ReviewError("case marker payload must be an object")
    for key in ("case_id", "recipe_id", "seed", "lighting", "visual_stage", "archetype_id", "runtime"):
        if key not in payload:
            raise ReviewError(f"case marker missing {key}")
    for key in ("case_id", "recipe_id", "seed", "lighting", "visual_stage", "archetype_id"):
        if payload[key] != case[key]:
            raise ReviewError(f"case marker {key} does not match requested case")
    return payload


def _diagnostic_lines(text: str) -> list[str]:
    return [
        line
        for line in text.splitlines()
        if any(token in line for token in ("WARNING:", "ERROR:", "SCRIPT ERROR:"))
        and not any(allowed in line for allowed in ALLOWED_TEARDOWN_DIAGNOSTICS)
    ]


def parse_case_output(stdout: str, stderr: str, case: Mapping[str, Any]) -> dict[str, Any]:
    diagnostics = _diagnostic_lines(stdout) + _diagnostic_lines(stderr)
    if diagnostics:
        raise ReviewError("unallowlisted diagnostic output: " + " | ".join(diagnostics))
    if CAPTURE_MARKER not in stdout:
        raise ReviewError("missing case pass marker")
    return parse_case_marker(stdout, case)


def build_godot_command(project_root: Path, output: Path, godot: Path, case: Mapping[str, Any]) -> list[str]:
    return [
        str(godot),
        "--headless",
        "--path",
        str(_absolute(project_root)),
        "--script",
        CAPTURE_SCRIPT,
        "--",
        "--recipe-id",
        str(case["recipe_id"]),
        "--seed",
        str(case["seed"]),
        "--archetype-id",
        str(case["archetype_id"]),
        "--lighting",
        str(case["lighting"]),
        "--visual-stage",
        str(case["visual_stage"]),
        "--output",
        str(_absolute(output)),
    ]


def run_capture_command(command: list[str]) -> tuple[subprocess.CompletedProcess[str], list[str]]:
    """Run one case, retrying GUI rendering when headless selects dummy storage."""
    result = subprocess.run(command, capture_output=True, text=True, check=False, timeout=180)
    combined = (result.stdout or "") + "\n" + (result.stderr or "")
    if result.returncode == 0 or "--headless" not in command or "production viewport did not produce a visible image" not in combined:
        return result, command
    gui_command = [argument for argument in command if argument != "--headless"]
    return subprocess.run(gui_command, capture_output=True, text=True, check=False, timeout=180), gui_command


def plan_document(project_root: Path, visual_stage: str, godot_version: str = "4.7.1", commit: str = "") -> dict[str, Any]:
    # This function is intentionally pure: plan never probes the process, git,
    # or filesystem and never writes the fixed evidence root.
    if visual_stage not in {"placeholder", "final"}:
        raise ReviewError("visual stage must be placeholder or final")
    return {
        "schema_version": SCHEMA_VERSION,
        "document_kind": DOCUMENT_KIND,
        "visual_stage": visual_stage,
        "commit": commit,
        "godot_version": godot_version,
        "cases": build_case_matrix(visual_stage),
    }


def _git_value(project_root: Path, *args: str) -> str:
    result = subprocess.run(["git", *args], cwd=_absolute(project_root), capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise ReviewError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def _godot_version(godot: Path) -> str:
    result = subprocess.run([str(godot), "--version"], capture_output=True, text=True, check=False, timeout=30)
    if result.returncode != 0:
        raise ReviewError(f"Godot version probe failed: {result.stderr.strip()}")
    match = re.search(r"(\d+\.\d+(?:\.\d+)?)", result.stdout + "\n" + result.stderr)
    if match is None:
        raise ReviewError("Godot version probe returned no version")
    return match.group(1)


def build_manifest(
    project_root: Path,
    visual_stage: str,
    cases: list[Mapping[str, Any]],
    protected_before: Mapping[str, str],
    protected_after: Mapping[str, str],
    commit: str,
    godot_version: str,
) -> dict[str, Any]:
    _parts_document, recipes_document = _catalog_documents(project_root)
    return {
        "schema_version": SCHEMA_VERSION,
        "document_kind": DOCUMENT_KIND,
        "visual_stage": visual_stage,
        "commit": commit,
        "godot_version": godot_version,
        "catalogs": _catalog_records(project_root),
        "recipes": _recipe_records(recipes_document),
        "cases": [dict(case) for case in cases],
        "protected_digests": {"before": dict(protected_before), "after": dict(protected_after)},
        "pass": True,
    }


def _fixed_output_root(project_root: Path, stage: str, requested: Path | None = None) -> Path:
    fixed = _expected_root(project_root, stage)
    if requested is not None and _absolute(requested) != fixed:
        raise ReviewError(f"output root must be fixed: {fixed}")
    return fixed


def _check_not_ignored(project_root: Path, path: Path) -> None:
    git_dir = _absolute(project_root) / ".git"
    if not git_dir.exists():
        return
    result = subprocess.run(["git", "check-ignore", "--no-index", str(path)], cwd=_absolute(project_root), capture_output=True, text=True, check=False)
    if result.returncode == 0:
        raise ReviewError(f"stable biomass evidence path is ignored: {path}")


def _clean_root(root: Path) -> None:
    if root.is_symlink():
        raise ReviewError(f"evidence root is a symlink: {root}")
    if root.exists():
        if not root.is_dir():
            raise ReviewError(f"evidence root is not a directory: {root}")
        shutil.rmtree(root)
    root.mkdir(parents=True, mode=0o700)


def _write_private(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    os.chmod(path, 0o600)


def run_review(project_root: Path, godot: Path, visual_stage: str, output_root: Path, report_path: Path) -> dict[str, Any]:
    if visual_stage != "placeholder":
        raise ReviewError("Task 8 only runs visual-stage placeholder")
    project_root = _absolute(project_root)
    godot = _absolute(godot)
    root = _fixed_output_root(project_root, visual_stage, output_root)
    report = _absolute(report_path)
    if report != root / "review.json":
        raise ReviewError(f"report must be the canonical path: {root / 'review.json'}")
    _check_not_ignored(project_root, root / "review.json")
    _regular_file(project_root / CAPTURE_SCRIPT.removeprefix("res://"), "capture script")
    _regular_file(project_root / "scenes/main.tscn", "production main scene")
    protected_before = snapshot_protected_surfaces(project_root)
    cases = build_case_matrix(visual_stage)
    private = Path(tempfile.mkdtemp(prefix=f".{root.name}.", dir=str(root.parent)))
    _clean_root(root)
    try:
        case_records: list[dict[str, Any]] = []
        _parts_document, recipes_document = _catalog_documents(project_root)
        for case in cases:
            output = private / capture_name(case["recipe_id"], case["seed"], case["lighting"])
            command = build_godot_command(project_root, output, godot, case)
            try:
                result, executed_command = run_capture_command(command)
            except (OSError, subprocess.TimeoutExpired) as exc:
                raise ReviewError(f"Godot case failed to execute: {case['case_id']}: {exc}") from exc
            stdout = result.stdout or ""
            stderr = result.stderr or ""
            payload = parse_case_output(stdout, stderr, case)
            if result.returncode != 0:
                raise ReviewError(f"Godot case exited {result.returncode}: {case['case_id']}")
            recipe_document = recipes_document["recipes"][case["recipe_id"]]
            record = dict(case)
            record.update(
                {
                    "pool_membership": case["recipe_id"] in POOL_MEMBERSHIP[case["archetype_id"]],
                    "recipe_sha256": hashlib.sha256(canonical_json_bytes(recipe_document)).hexdigest(),
                    "recipe_document": recipe_document,
                    "command": executed_command,
                    "exit_code": result.returncode,
                    "stdout": stdout,
                    "stderr": stderr,
                    "output": {
                        "path": _project_relative(project_root, root / output.name),
                        "sha256": sha256_file(output),
                        "byte_size": output.stat().st_size,
                        **{key: value for key, value in inspect_png(output).items() if key in {"width", "height"}},
                    },
                    "runtime": payload["runtime"],
                    "pass": True,
                }
            )
            # The marker is untrusted evidence too; validate its metric payload
            # before it enters the canonical report.
            runtime_errors: list[str] = []
            _validate_runtime(record["runtime"], case, runtime_errors)
            if runtime_errors:
                raise ReviewError(f"{case['case_id']}: {'; '.join(runtime_errors)}")
            case_records.append(record)
        protected_after = snapshot_protected_surfaces(project_root)
        document = build_manifest(project_root, visual_stage, case_records, protected_before, protected_after, _git_value(project_root, "rev-parse", "HEAD"), _godot_version(godot))
        errors = validate_manifest(document, project_root, private)
        if errors:
            raise ReviewError("manifest validation failed: " + "; ".join(errors))
        for png in sorted(private.glob("*.png")):
            os.replace(png, root / png.name)
        _write_private(root / "review.json.tmp", canonical_json_bytes(document))
        os.replace(root / "review.json.tmp", report)
        shutil.rmtree(private)
        return document
    except Exception:
        shutil.rmtree(private, ignore_errors=True)
        shutil.rmtree(root, ignore_errors=True)
        raise


def _verify_inventory(project_root: Path, report: Path, stage: str) -> None:
    root = _expected_root(project_root, stage)
    if report != root / "review.json":
        raise ReviewError("report is not at the canonical evidence root")
    _regular_file(report, "review.json")
    entries = sorted(path.name for path in root.iterdir())
    expected = [capture_name(recipe, seed, lighting) for recipe in RECIPE_IDS for seed in SEEDS for lighting in LIGHTING_MODES]
    expected.sort()
    if entries != sorted(expected + ["review.json"]):
        raise ReviewError("evidence inventory is not exactly 30 PNGs plus review.json")
    for path in root.iterdir():
        if path.is_symlink() or not path.is_file():
            raise ReviewError("evidence inventory contains a non-regular file")
        if path.name != "review.json":
            inspect_png(path)


def verify_report(project_root: Path, report_path: Path) -> dict[str, Any]:
    project_root = _absolute(project_root)
    report = _absolute(report_path)
    document = load_json(report)
    stage = document.get("visual_stage")
    if stage not in {"placeholder", "final"}:
        raise ReviewError("manifest visual stage is invalid")
    _verify_inventory(project_root, report, stage)
    errors = validate_manifest(document, project_root)
    if errors:
        raise ReviewError("manifest verification failed: " + "; ".join(errors))
    return document


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    plan = subparsers.add_parser("plan")
    plan.add_argument("--project-root", type=Path, default=Path("."))
    plan.add_argument("--visual-stage", choices=("placeholder", "final"), required=True)
    plan.add_argument("--godot-version", default="4.7.1")
    plan.add_argument("--commit", default="")
    run = subparsers.add_parser("run")
    run.add_argument("--project-root", type=Path, default=Path("."))
    run.add_argument("--godot", type=Path, required=True)
    run.add_argument("--visual-stage", choices=("placeholder", "final"), required=True)
    run.add_argument("--output-root", type=Path, required=True)
    run.add_argument("--report", type=Path, required=True)
    verify = subparsers.add_parser("verify")
    verify.add_argument("--project-root", type=Path, default=Path("."))
    verify.add_argument("--report", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "plan":
            print(canonical_json_bytes(plan_document(args.project_root, args.visual_stage, args.godot_version, args.commit)).decode("utf-8"), end="")
            return 0
        if args.command == "run":
            run_review(args.project_root, args.godot, args.visual_stage, args.output_root, args.report)
            print(FINAL_MARKER.format(stage=args.visual_stage))
            return 0
        document = verify_report(args.project_root, args.report)
        print(FINAL_MARKER.format(stage=document["visual_stage"]))
        return 0
    except ReviewError as exc:
        print(f"BIOMASS COMPOSITE REVIEW FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
