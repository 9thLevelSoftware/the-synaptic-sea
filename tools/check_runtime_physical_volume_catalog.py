"""Fail-closed source validation for ADR-0065 runtime physical volumes."""
from __future__ import annotations

import json
import math
from pathlib import Path

CATALOG_PATH = "data/physics/runtime_physical_volume_profiles.json"
SCHEMA = "runtime_physical_volume_profiles_v1"
ROOT_KEYS = frozenset(("schema", "profiles"))
PROFILE_KEYS = frozenset((
    "profile_id", "shape_kind", "dimensions", "local_position",
    "local_yaw_degrees", "mount_kind", "collision_layer", "collision_mask",
    "blocking_purposes",
))

# This is the reviewed ADR-0065 §3A authority, deliberately duplicated from
# neither visual assets nor scene geometry.  Any authored drift is a blocker.
AUTHORED_PROFILES = {
    "cart": ("box", (0.75, 0.56, 0.50), (0.0, 0.28, 0.0), 0.0, "floor"),
    "floor_drop": ("box", (0.35, 0.25, 0.35), (0.0, 0.20, 0.0), 0.0, "floor"),
    "air_recycler": ("box", (0.80, 0.56, 0.60), (0.0, 0.28, 0.0), 0.0, "deck"),
    "conduit": ("box", (0.30, 1.00, 0.22), (0.0, 0.50, 0.11), 0.0, "wall"),
    "console_generic_wall": ("box", (0.60, 0.54, 0.34), (0.0, 0.27, 0.17), 0.0, "wall"),
    "console_generic_deck": ("box", (0.60, 0.54, 0.34), (0.0, 0.27, 0.0), 0.0, "deck"),
    "hull_plating": ("box", (1.00, 1.00, 0.08), (0.0, 0.50, 0.04), 0.0, "wall"),
    "locker_wall": ("box", (0.60, 0.75, 0.34), (0.0, 0.375, 0.17), 0.0, "wall"),
    "machinery_block": ("box", (0.80, 0.90, 0.60), (0.0, 0.45, 0.0), 0.0, "deck"),
    "nav_console": ("box", (0.90, 0.71, 0.36), (0.0, 0.355, 0.18), 0.0, "wall"),
    "pump": ("box", (0.40, 0.52, 0.40), (0.0, 0.26, 0.0), 0.0, "deck"),
    "reactor_console": ("box", (0.60, 0.75, 0.35), (0.0, 0.375, 0.175), 0.0, "wall"),
    "sensor_rack": ("box", (0.40, 0.78, 0.28), (0.0, 0.39, 0.14), 0.0, "wall"),
    "thruster_control": ("box", (0.68, 0.48, 0.37), (0.0, 0.24, 0.185), 0.0, "wall"),
}


def _read_json(path: Path) -> object:
    def reject_nonfinite(value: str) -> None:
        raise ValueError(f"nonfinite JSON value {value}")

    try:
        return json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_nonfinite)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"invalid catalog {path.as_posix()}: {error}") from error


def _finite_number(value: object) -> bool:
    return type(value) in (int, float) and math.isfinite(float(value))


def _exact_numeric(value: object, expected: float) -> bool:
    return _finite_number(value) and float(value) == expected


def _finite_vector(value: object, size: int, *, positive: bool = False) -> bool:
    return (
        isinstance(value, list)
        and len(value) == size
        and all(_finite_number(item) and (not positive or float(item) > 0.0) for item in value)
    )


def validate_catalog(catalog: object) -> dict[str, object]:
    blockers: set[str] = set()
    mismatches: list[str] = []
    if not isinstance(catalog, dict) or set(catalog) != ROOT_KEYS:
        return {"ok": False, "blockers": ["catalog_schema"], "mismatches": []}
    if catalog.get("schema") != SCHEMA:
        blockers.add("schema")
    profiles = catalog.get("profiles")
    if not isinstance(profiles, list):
        return {"ok": False, "blockers": ["profiles"], "mismatches": []}
    ids: list[str] = []
    for profile in profiles:
        if not isinstance(profile, dict) or set(profile) != PROFILE_KEYS:
            blockers.add("profile_schema")
            continue
        profile_id = profile.get("profile_id")
        if not isinstance(profile_id, str) or not profile_id:
            blockers.add("profile_id")
            continue
        ids.append(profile_id)
        shape_kind = profile.get("shape_kind")
        dimensions = profile.get("dimensions")
        if shape_kind == "box":
            valid_shape = _finite_vector(dimensions, 3, positive=True)
        elif shape_kind == "capsule":
            valid_shape = _finite_vector(dimensions, 2, positive=True) and float(dimensions[1]) >= float(dimensions[0]) * 2.0
        else:
            valid_shape = False
        if not valid_shape:
            blockers.add("shape")
        if not _finite_vector(profile.get("local_position"), 3) or not _finite_number(profile.get("local_yaw_degrees")):
            blockers.add("transform")
        if profile.get("mount_kind") not in {"floor", "deck", "wall"}:
            blockers.add("mount_kind")
        if not _exact_numeric(profile.get("collision_layer"), 2.0):
            blockers.add("collision_layer")
        if not _exact_numeric(profile.get("collision_mask"), 0.0):
            blockers.add("collision_mask")
        if profile.get("blocking_purposes") != ["structural_rebuild"]:
            blockers.add("blocking_purposes")
        expected = AUTHORED_PROFILES.get(profile_id)
        if expected is not None:
            actual = (shape_kind, tuple(dimensions) if isinstance(dimensions, list) else None,
                      tuple(profile.get("local_position")) if isinstance(profile.get("local_position"), list) else None,
                      profile.get("local_yaw_degrees"), profile.get("mount_kind"))
            if actual != expected:
                mismatches.append(profile_id)
    if len(ids) != len(set(ids)):
        blockers.add("duplicate_profile_id")
    if set(ids) != set(AUTHORED_PROFILES) or len(profiles) != len(AUTHORED_PROFILES):
        blockers.add("coverage")
    if mismatches:
        blockers.add("authored_values")
    return {"ok": not blockers, "blockers": sorted(blockers), "mismatches": sorted(set(mismatches))}


def check(root: Path) -> dict[str, object]:
    try:
        return validate_catalog(_read_json(root / CATALOG_PATH))
    except ValueError as error:
        return {"ok": False, "blockers": ["source_invalid"], "mismatches": [], "reason": str(error)}


def main() -> int:
    report = check(Path("."))
    print("RUNTIME PHYSICAL VOLUME CATALOG PASS" if report["ok"] else "RUNTIME PHYSICAL VOLUME CATALOG BLOCKED", json.dumps(report, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
