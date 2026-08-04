"""Focused-nine staging paths and comparison-report contract.

This module is deliberately pure Python.  It defines the candidate registry and
validates report documents without reading or mutating any runtime surface.
"""

from __future__ import annotations

import math
import re
from pathlib import Path
from typing import Any


STRUCTURAL_IDS: tuple[str, ...] = (
    "floor_1x1",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
    "ceiling_cap_1x1",
    "pressure_door_1x1",
)
PROP_IDS: tuple[str, ...] = (
    "hull_breach_seal_point",
    "fire_suppression_station",
)
VARIANT_ROLES: dict[str, tuple[str, ...]] = {
    "pressure_door_1x1": ("intact", "damaged", "breached"),
}

_STAGE_ROOT = Path("assets/_staging/focused_nine")
_REPORT_NAME = "focused-nine-comparison.json"
_RUNTIME_MUTATION_RELATIVE_PATHS: tuple[Path, ...] = (
    Path("assets/imported"),
    Path("data/props/visual_bindings.generated.json"),
    Path("data/kits/ship_structural_v0.json"),
    Path("scenes/wrappers/structural/ship_structural_v0"),
)
_ROOT_FIELDS = (
    "schema_version",
    "document_kind",
    "assets",
    "baseline",
    "improved",
    "preview",
    "overall_pass",
)
_ASSET_FIELDS = (
    "asset_id",
    "kind",
    "source_path",
    "staged_glbs",
    "metrics",
    "validation",
    "pass",
    "first_error",
)
_METRIC_FIELDS = (
    "sha256",
    "byte_size",
    "mesh_count",
    "triangle_count",
    "material_names",
    "bounds",
)
_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


class _InvalidReport(Exception):
    """Internal marker used only to keep validation helpers small."""


def _project_root(project_root: Path) -> Path:
    return Path(project_root).expanduser().resolve()


def _contained_path(root: Path, candidate: Path) -> Path:
    """Return *candidate* after rejecting symlink/path escapes from *root*."""

    resolved_root = root.resolve()
    resolved_candidate = candidate.resolve(strict=False)
    if resolved_candidate == resolved_root or resolved_root not in resolved_candidate.parents:
        raise ValueError(f"path escapes project root: {candidate}")
    return candidate


def _asset_kind(asset_id: object) -> str:
    if asset_id in STRUCTURAL_IDS:
        return "structural"
    if asset_id in PROP_IDS:
        return "props"
    raise ValueError(f"unknown focused-nine asset id: {asset_id!r}")


def _asset_roles(asset_id: str) -> tuple[str, ...]:
    _asset_kind(asset_id)
    if asset_id in PROP_IDS:
        return ("intact",)
    return VARIANT_ROLES.get(asset_id, ("intact",))


def asset_stage_dir(project_root: Path, asset_id: str) -> Path:
    """Return the contained staging directory for one registered asset."""

    kind = _asset_kind(asset_id)
    root = _project_root(project_root)
    directory = root / _STAGE_ROOT / kind
    if kind == "structural":
        directory /= asset_id
    return _contained_path(root, directory)


def asset_stage_glb(project_root: Path, asset_id: str, role: str = "intact") -> Path:
    """Return the contained staged GLB path for an asset and approved role."""

    roles = _asset_roles(asset_id)
    if not isinstance(role, str) or role not in roles:
        raise ValueError(f"invalid focused-nine role for {asset_id!r}: {role!r}")

    directory = asset_stage_dir(project_root, asset_id)
    filename = f"{asset_id}.glb" if role == "intact" else f"{asset_id}_{role}.glb"
    return _contained_path(_project_root(project_root), directory / filename)


def comparison_report_path(project_root: Path) -> Path:
    """Return the contained deterministic comparison-report path."""

    root = _project_root(project_root)
    return _contained_path(root, root / _STAGE_ROOT / _REPORT_NAME)


def runtime_mutation_paths(project_root: Path) -> tuple[Path, ...]:
    """Return exactly the live surfaces that a comparison batch must snapshot.

    The comparison workflow must not write these paths; callers use this tuple
    for before/after digest checks around isolated staging work.
    """

    root = _project_root(project_root)
    return tuple(_contained_path(root, root / relative) for relative in _RUNTIME_MUTATION_RELATIVE_PATHS)


def _append_unknown_fields(
    document: object,
    allowed: tuple[str, ...],
    label: str,
    errors: list[str],
) -> None:
    if not isinstance(document, dict):
        return
    for field in sorted(set(document) - set(allowed), key=str):
        errors.append(f"unknown {label} field: {field}")


def _append_missing_fields(
    document: object,
    required: tuple[str, ...],
    label: str,
    errors: list[str],
) -> None:
    if not isinstance(document, dict):
        return
    for field in required:
        if field not in document:
            errors.append(f"{label} missing field: {field}")


def _append_nonfinite(value: object, label: str, errors: list[str], seen: set[int]) -> None:
    """Collect non-finite floats anywhere in a JSON-like document."""

    if isinstance(value, float):
        if not math.isfinite(value):
            errors.append(f"{label} contains non-finite value")
        return
    if isinstance(value, dict):
        identity = id(value)
        if identity in seen:
            return
        seen.add(identity)
        for key in sorted(value, key=str):
            _append_nonfinite(value[key], f"{label}.{key}", errors, seen)
        return
    if isinstance(value, (list, tuple)):
        identity = id(value)
        if identity in seen:
            return
        seen.add(identity)
        for index, item in enumerate(value):
            _append_nonfinite(item, f"{label}[{index}]", errors, seen)


def _is_nonnegative_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _is_finite_vector(value: object) -> bool:
    return (
        isinstance(value, (list, tuple))
        and len(value) == 3
        and all(
            isinstance(item, (int, float))
            and not isinstance(item, bool)
            and math.isfinite(float(item))
            for item in value
        )
    )


def _validate_bounds(bounds: object, label: str, errors: list[str]) -> None:
    if not isinstance(bounds, dict):
        errors.append(f"{label} must be an object")
        return

    # Existing GLB metadata uses local_min_m/local_max_m.  Accept min/max as
    # the compact equivalent while keeping the metric shape unambiguous.
    if {"local_min_m", "local_max_m"}.issubset(bounds):
        minimum = bounds["local_min_m"]
        maximum = bounds["local_max_m"]
        vector_label = "local_min_m/local_max_m"
    elif {"min", "max"}.issubset(bounds):
        minimum = bounds["min"]
        maximum = bounds["max"]
        vector_label = "min/max"
    else:
        errors.append(f"{label} must contain a min/max 3-vector pair")
        return

    if not _is_finite_vector(minimum) or not _is_finite_vector(maximum):
        errors.append(f"{label}.{vector_label} must contain finite 3-vectors")
        return
    if any(low > high for low, high in zip(minimum, maximum)):
        errors.append(f"{label}.{vector_label} minimum must not exceed maximum")


def _validate_metrics(metrics: object, label: str, errors: list[str]) -> None:
    if not isinstance(metrics, dict):
        errors.append(f"{label} must be an object")
        return
    _append_missing_fields(metrics, _METRIC_FIELDS, label, errors)
    _append_unknown_fields(metrics, _METRIC_FIELDS, label, errors)

    sha256 = metrics.get("sha256")
    if not isinstance(sha256, str) or _SHA256_RE.fullmatch(sha256) is None:
        errors.append(f"{label}.sha256 must be 64 lowercase hexadecimal characters")

    for field in ("byte_size", "mesh_count", "triangle_count"):
        value = metrics.get(field)
        if not _is_nonnegative_int(value):
            errors.append(f"{label}.{field} must be a non-negative integer")

    material_names = metrics.get("material_names")
    if not isinstance(material_names, list) or not all(
        isinstance(name, str) and bool(name) for name in material_names
    ):
        errors.append(f"{label}.material_names must be a list of non-empty strings")

    if "bounds" in metrics:
        _validate_bounds(metrics["bounds"], f"{label}.bounds", errors)


def _validate_asset(asset: object, index: int, errors: list[str]) -> None:
    label = f"asset[{index}]"
    if not isinstance(asset, dict):
        errors.append(f"{label} must be an object")
        return
    _append_missing_fields(asset, _ASSET_FIELDS, label, errors)
    _append_unknown_fields(asset, _ASSET_FIELDS, label, errors)

    asset_id = asset.get("asset_id")
    expected_kind: str | None = None
    if isinstance(asset_id, str):
        if asset_id in STRUCTURAL_IDS:
            expected_kind = "structural"
        elif asset_id in PROP_IDS:
            expected_kind = "prop"
        else:
            errors.append(f"{label} unknown asset_id: {asset_id}")
    else:
        errors.append(f"{label}.asset_id must be a registered string")

    kind = asset.get("kind")
    if kind not in ("structural", "prop"):
        errors.append(f"{label}.kind must be structural or prop")
    elif expected_kind is not None and kind != expected_kind:
        errors.append(f"{label}.kind does not match registered asset")

    source_path = asset.get("source_path")
    if not isinstance(source_path, str) or not source_path:
        errors.append(f"{label}.source_path must be a non-empty string")

    staged_glbs = asset.get("staged_glbs")
    if not isinstance(staged_glbs, list) or not all(
        isinstance(path, str) and bool(path) for path in staged_glbs
    ):
        errors.append(f"{label}.staged_glbs must be a list of non-empty strings")

    if "metrics" in asset:
        _validate_metrics(asset["metrics"], f"{label}.metrics", errors)

    validation = asset.get("validation")
    if not isinstance(validation, list) or not all(isinstance(item, str) for item in validation):
        errors.append(f"{label}.validation must be a list of strings")

    if not isinstance(asset.get("pass"), bool):
        errors.append(f"{label}.pass must be a boolean")

    first_error = asset.get("first_error")
    if first_error is not None and not isinstance(first_error, str):
        errors.append(f"{label}.first_error must be a string or null")


def validate_report(document: dict) -> list[str]:
    """Return deterministic, sorted diagnostics for a comparison report.

    An empty list is the only valid result.  Validation is intentionally
    side-effect free and rejects non-finite floats even in otherwise opaque
    baseline, improved, and preview payloads.
    """

    errors: list[str] = []
    if not isinstance(document, dict):
        return ["report must be an object"]

    _append_missing_fields(document, _ROOT_FIELDS, "root", errors)
    _append_unknown_fields(document, _ROOT_FIELDS, "root", errors)

    if "schema_version" in document and document["schema_version"] != "1.0.0":
        errors.append("schema_version must be 1.0.0")
    if "document_kind" in document and document["document_kind"] != "focused_nine_comparison":
        errors.append("document_kind must be focused_nine_comparison")
    if "assets" in document:
        if not isinstance(document["assets"], list):
            errors.append("assets must be a list")
        else:
            for index, asset in enumerate(document["assets"]):
                _validate_asset(asset, index, errors)
    for field in ("baseline", "improved", "preview"):
        if field in document and not isinstance(document[field], dict):
            errors.append(f"{field} must be an object")
    if "overall_pass" in document and not isinstance(document["overall_pass"], bool):
        errors.append("overall_pass must be a boolean")

    _append_nonfinite(document, "report", errors, set())
    return sorted(errors)


__all__ = [
    "PROP_IDS",
    "STRUCTURAL_IDS",
    "VARIANT_ROLES",
    "asset_stage_dir",
    "asset_stage_glb",
    "comparison_report_path",
    "runtime_mutation_paths",
    "validate_report",
]
