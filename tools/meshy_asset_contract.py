#!/usr/bin/env python3
"""Validate governed Meshy candidate contracts and render prompt packets."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, cast

SCHEMA_VERSION = "1.0.0"
DOCUMENT_KIND = "ai_asset_contract"
IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
KIT_TOKEN_RE = re.compile(r"(^|_)kit(_|$)")
RIGHTS_STATES = {"project-owned", "paid-private", "free-cc-by-4.0"}
REFERENCE_VIEWS = {"front", "side", "back", "left", "right", "three_quarter"}
PIVOTS = {"bottom_center", "attachment", "scene_origin"}
LIGHTING_MODES = ["normal", "emergency", "dark"]
REVIEW_SEEDS = [42, 777]

STYLE_VOCABULARY = (
    "Grounded utilitarian industrial science fiction; late-20th-century analog technology "
    "translated into space; heavy serviceable construction; matte desaturated painted alloy; "
    "dark oxidized steel; black rubber seals; restrained safety-yellow accents; asymmetrical "
    "field repairs; localized corrosion and grime; large readable forms; readable from a high "
    "locked-isometric camera."
)
NEUTRAL_PRESENTATION = (
    "No environment, no floor, no cast shadow, no readable text, no logo, no floating parts, "
    "no duplicate components, no dramatic perspective, no depth of field, no baked lighting."
)
TEXTURE_VOCABULARY = STYLE_VOCABULARY + (
    " Texture as grounded derelict spacecraft construction: matte desaturated painted alloy, dark oxidized "
    "steel exposed at worn edges, black rubber seals, restrained safety-yellow accents, grime "
    "concentrated in seams and hand-contact areas, subtle moisture staining, isolated corrosion, "
    "practical field repairs, low gloss, readable medium-scale wear. No readable text, no logos, "
    "no decorative neon, no baked shadows, no directional lighting, no environment reflection."
)

_REQUIRED_TOP_FIELDS = (
    "schema_version",
    "document_kind",
    "asset_id",
    "category",
    "gameplay_role",
    "dimensions_m",
    "dimension_tolerance_m",
    "pivot",
    "forward_axis",
    "allowed_yaw_deg",
    "required_states",
    "state_derivation",
    "collision_owner",
    "animation",
    "budget",
    "references",
    "generation",
    "review",
)
_OPTIONAL_TOP_FIELDS = (
    "prompt_profile",
    "visual_brief",
    "kit_parts",
    "deliverables",
)
_ALLOWED_TOP_FIELDS = _REQUIRED_TOP_FIELDS + _OPTIONAL_TOP_FIELDS
_NESTED_FIELDS: dict[str, tuple[str, ...]] = {
    "animation": ("kind", "meshy_rigging_allowed", "rigging_target"),
    "budget": ("triangles", "material_slots", "texture_resolution"),
    "references": ("required_views", "input_layout", "rights_state"),
    "generation": (
        "provider",
        "mode",
        "model_type",
        "ai_model",
        "target_polycount",
        "should_texture",
        "candidate_count",
        "target_formats",
    ),
    "review": ("seeds", "lighting_modes"),
}


@dataclass(frozen=True)
class AssetContract:
    path: Path
    document: dict[str, Any]
    sha256: str
    _snapshot: bytes = field(repr=False, compare=False)

    @property
    def asset_id(self) -> str:
        return str(self._snapshot_document()["asset_id"])

    def _snapshot_document(self) -> dict[str, Any]:
        document = json.loads(self._snapshot)
        if not isinstance(document, dict):  # pragma: no cover - load_contract validates this
            raise ValueError("contract snapshot must be an object")
        return document


def canonical_json_bytes(value: object) -> bytes:
    """Return the canonical timestamp-free JSON representation."""

    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        )
        + "\n"
    ).encode("utf-8")


def _is_int(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def _is_positive_int(value: object) -> bool:
    return _is_int(value) and cast(int, value) > 0


def _is_finite_number(value: object) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    return isinstance(value, float) and math.isfinite(value)


def _is_positive_number(value: object) -> bool:
    return (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(float(value))
        and float(value) > 0.0
    )


def _is_bounded_int(value: object, minimum: int, maximum: int) -> bool:
    return _is_int(value) and minimum <= cast(int, value) <= maximum


def _walk_nonfinite(value: object, label: str, errors: list[str]) -> None:
    stack: list[tuple[object, str]] = [(value, label)]
    seen: set[int] = set()
    while stack:
        current, current_label = stack.pop()
        if isinstance(current, float):
            if not math.isfinite(current):
                errors.append(f"{current_label} contains non-finite value")
            continue
        if isinstance(current, dict):
            identity = id(current)
            if identity in seen:
                continue
            seen.add(identity)
            for key in sorted(current, key=lambda item: str(item), reverse=True):
                child_label = f"{current_label}.{key}" if current_label else str(key)
                stack.append((current[key], child_label))
            continue
        if isinstance(current, (list, tuple)):
            identity = id(current)
            if identity in seen:
                continue
            seen.add(identity)
            for index in range(len(current) - 1, -1, -1):
                stack.append((current[index], f"{current_label}[{index}]"))


def _check_object_fields(
    value: object,
    *,
    label: str,
    allowed: tuple[str, ...],
    required: tuple[str, ...] = (),
    errors: list[str],
) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return None
    for key in sorted(value, key=lambda item: str(item)):
        if not isinstance(key, str):
            errors.append(f"{label} contains a non-string key")
        elif key not in allowed:
            errors.append(f"unknown {label} field: {key}")
    for field in required:
        if field not in value:
            errors.append(f"{label} missing field: {field}")
    return value


def _check_identifier(value: object, label: str, errors: list[str]) -> bool:
    if not isinstance(value, str) or IDENTIFIER_RE.fullmatch(value) is None:
        errors.append(f"{label} must be a lowercase identifier")
        return False
    return True


def _check_identifier_list(value: object, label: str, errors: list[str]) -> bool:
    if not isinstance(value, list) or not value:
        errors.append(f"{label} must be a non-empty list of lowercase identifiers")
        return False
    valid = True
    if len(value) != len(set(item for item in value if isinstance(item, str))):
        errors.append(f"{label} must contain unique values")
        valid = False
    for index, item in enumerate(value):
        valid = _check_identifier(item, f"{label}[{index}]", errors) and valid
    return valid


def _check_triangle_budget(value: object, errors: list[str]) -> None:
    if _is_positive_int(value):
        return
    if not isinstance(value, dict):
        errors.append("budget.triangles must be a positive integer or a range object")
        return
    triangle = _check_object_fields(
        value,
        label="budget.triangles",
        allowed=("min", "max", "scope"),
        required=("min", "max", "scope"),
        errors=errors,
    )
    if triangle is None:
        return
    minimum = triangle.get("min")
    maximum = triangle.get("max")
    if not _is_positive_int(minimum) or not _is_positive_int(maximum):
        errors.append("budget.triangles min/max must be positive integers")
    elif isinstance(minimum, int) and isinstance(maximum, int) and minimum > maximum:
        errors.append("budget.triangles min must not exceed max")
    if triangle.get("scope") not in ("whole_asset", "per_part"):
        errors.append("budget.triangles scope must be whole_asset or per_part")


def validate_contract(document: object) -> list[str]:
    """Return deterministic diagnostics; an empty list is the only valid result."""

    errors: list[str] = []
    if not isinstance(document, dict):
        return ["contract must be an object"]

    _walk_nonfinite(document, "", errors)
    top = _check_object_fields(
        document,
        label="top-level",
        allowed=_ALLOWED_TOP_FIELDS,
        required=_REQUIRED_TOP_FIELDS,
        errors=errors,
    )
    if top is None:
        return sorted(set(errors))

    if top.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION}")
    if top.get("document_kind") != DOCUMENT_KIND:
        errors.append(f"document_kind must be {DOCUMENT_KIND}")

    asset_id = top.get("asset_id")
    category = top.get("category")
    gameplay_role = top.get("gameplay_role")
    _check_identifier(asset_id, "asset_id", errors)
    _check_identifier(category, "category", errors)
    _check_identifier(gameplay_role, "gameplay_role", errors)

    dimensions = top.get("dimensions_m")
    if not (
        isinstance(dimensions, list)
        and len(dimensions) == 3
        and all(_is_positive_number(item) for item in dimensions)
    ):
        errors.append("dimensions_m must contain exactly 3 positive finite numbers")
    tolerance = top.get("dimension_tolerance_m")
    if not _is_positive_number(tolerance):
        errors.append("dimension_tolerance_m must be a positive finite number")
    if top.get("pivot") not in PIVOTS:
        errors.append("pivot must be one of bottom_center, attachment, scene_origin")
    if top.get("forward_axis") != "+Z":
        errors.append("forward_axis must be +Z")

    yaw = top.get("allowed_yaw_deg")
    if not (
        isinstance(yaw, list)
        and yaw
        and len(yaw) == len(set(item for item in yaw if _is_finite_number(item)))
        and all(_is_finite_number(item) for item in yaw)
    ):
        errors.append("allowed_yaw_deg must be a non-empty list of unique finite numbers")

    states = top.get("required_states")
    states_valid = _check_identifier_list(states, "required_states", errors)
    if (
        states_valid
        and isinstance(states, list)
        and len(states) > 1
        and top.get("state_derivation") != "one_blender_master"
    ):
        errors.append("alternate states must derive from one master")
    if top.get("state_derivation") not in ("one_blender_master", "single_state"):
        if not (states_valid and isinstance(states, list) and len(states) > 1):
            errors.append("state_derivation must be one_blender_master or single_state")
    if top.get("collision_owner") != "godot_wrapper":
        errors.append("collision ownership must remain with godot_wrapper")

    animation = _check_object_fields(
        top.get("animation"),
        label="animation",
        allowed=_NESTED_FIELDS["animation"],
        required=_NESTED_FIELDS["animation"],
        errors=errors,
    )
    if animation is not None:
        if not isinstance(animation.get("kind"), str) or not animation.get("kind"):
            errors.append("animation.kind must be a non-empty string")
        if not isinstance(animation.get("meshy_rigging_allowed"), bool):
            errors.append("animation.meshy_rigging_allowed must be a boolean")
        _check_identifier(animation.get("rigging_target"), "animation.rigging_target", errors)
        if (
            animation.get("meshy_rigging_allowed") is True
            and animation.get("rigging_target") != "humanoid_biped"
        ):
            errors.append("Meshy rigging is limited to humanoid bipeds")

    budget = _check_object_fields(
        top.get("budget"),
        label="budget",
        allowed=_NESTED_FIELDS["budget"],
        required=_NESTED_FIELDS["budget"],
        errors=errors,
    )
    if budget is not None:
        _check_triangle_budget(budget.get("triangles"), errors)
        if not _is_positive_int(budget.get("material_slots")):
            errors.append("budget.material_slots must be a positive integer")
        if not _is_positive_int(budget.get("texture_resolution")):
            errors.append("budget.texture_resolution must be a positive integer")

    references = _check_object_fields(
        top.get("references"),
        label="references",
        allowed=_NESTED_FIELDS["references"],
        required=_NESTED_FIELDS["references"],
        errors=errors,
    )
    views: object = None
    if references is not None:
        views = references.get("required_views")
        if not (
            isinstance(views, list)
            and 1 <= len(views) <= 4
            and len(views) == len(set(item for item in views if isinstance(item, str)))
            and all(item in REFERENCE_VIEWS for item in views)
        ):
            errors.append("references.required_views must contain 1-4 unique supported views")
        if references.get("input_layout") != "separate_files":
            errors.append("references.input_layout must be separate_files; collage is not allowed")
        if references.get("rights_state") not in RIGHTS_STATES:
            errors.append("reference rights must be explicit")

    generation = _check_object_fields(
        top.get("generation"),
        label="generation",
        allowed=_NESTED_FIELDS["generation"],
        required=_NESTED_FIELDS["generation"],
        errors=errors,
    )
    provider: object = None
    if generation is not None:
        provider = generation.get("provider")
        if provider != "meshy":
            errors.append("generation.provider must be meshy")
        mode = generation.get("mode")
        if mode not in ("image_to_3d", "multi_image_to_3d"):
            errors.append("generation.mode must be image_to_3d or multi_image_to_3d")
        candidate_count = generation.get("candidate_count")
        if not _is_bounded_int(candidate_count, 3, 6):
            errors.append("candidate_count must be between 3 and 6")
        if generation.get("should_texture") is not False:
            errors.append("geometry candidates must be untextured")
        if generation.get("target_formats") != ["glb"]:
            errors.append("generation.target_formats must equal [glb]")

        target = generation.get("target_polycount")
        model_type = generation.get("model_type")
        ai_model = generation.get("ai_model")
        if mode == "image_to_3d":
            if model_type != "smart-topology" or ai_model != "meshy-t2":
                errors.append("image_to_3d must use Smart Topology meshy-t2")
            if not _is_bounded_int(target, 100, 15000):
                errors.append("Smart Topology target_polycount must be between 100 and 15000")
        elif mode == "multi_image_to_3d":
            if model_type == "smart-topology" or ai_model == "meshy-t2":
                errors.append("Multi-Image does not support Smart Topology T2")
            if model_type != "standard" or ai_model not in ("meshy-7", "latest"):
                errors.append("multi_image_to_3d must use standard meshy-7 or latest")
            if not _is_bounded_int(target, 100, 300000):
                errors.append("Multi-Image target_polycount must be between 100 and 300000")
            if not isinstance(views, list) or not 2 <= len(views) <= 4:
                errors.append("multi_image_to_3d requires 2-4 reference views")

    if (
        isinstance(category, str)
        and (category == "structural" or category.startswith("structural_"))
        and provider == "meshy"
    ):
        errors.append("structural geometry cannot use Meshy")

    review = _check_object_fields(
        top.get("review"),
        label="review",
        allowed=_NESTED_FIELDS["review"],
        required=_NESTED_FIELDS["review"],
        errors=errors,
    )
    if review is not None:
        if review.get("seeds") != REVIEW_SEEDS:
            errors.append("review.seeds must equal [42, 777]")
        if review.get("lighting_modes") != LIGHTING_MODES:
            errors.append("review.lighting_modes must equal [normal, emergency, dark]")

    for optional_identifier in ("prompt_profile",):
        if optional_identifier in top:
            _check_identifier(top.get(optional_identifier), optional_identifier, errors)
    if "visual_brief" in top and (
        not isinstance(top.get("visual_brief"), str) or not top.get("visual_brief", "").strip()
    ):
        errors.append("visual_brief must be a non-empty string")
    for parts_field in ("kit_parts", "deliverables"):
        if parts_field in top:
            _check_identifier_list(top.get(parts_field), parts_field, errors)

    is_kit = any(
        isinstance(value, str) and KIT_TOKEN_RE.search(value) is not None
        for value in (asset_id, category)
    )
    if is_kit and not (
        isinstance(top.get("kit_parts"), list)
        and top.get("kit_parts")
        or isinstance(top.get("deliverables"), list)
        and top.get("deliverables")
    ):
        errors.append("kit contract must declare kit_parts or deliverables")

    return sorted(set(errors))


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_contract(path: Path) -> AssetContract:
    """Load and validate one contract while preserving its original byte hash."""

    source = Path(path)
    raw = source.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"contract is not valid UTF-8: {exc}") from exc
    try:
        document = json.loads(text, object_pairs_hook=_reject_duplicate_keys)
    except RecursionError as exc:
        raise ValueError("invalid JSON: maximum nesting depth exceeded") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON: {exc}") from exc
    except ValueError:
        raise
    if not isinstance(document, dict):
        raise ValueError("contract must be an object")
    errors = validate_contract(document)
    if errors:
        raise ValueError("; ".join(errors))
    return AssetContract(
        source,
        document,
        hashlib.sha256(raw).hexdigest(),
        canonical_json_bytes(document),
    )


def _triangle_budget_text(value: object) -> str:
    if isinstance(value, dict):
        return f"{value.get('min')}-{value.get('max')} triangles {value.get('scope')}"
    return f"{value} triangles"


def render_prompt_packet(contract: AssetContract) -> dict[str, Any]:
    """Render a deterministic, JSON-serializable production prompt packet."""

    document = contract._snapshot_document()
    brief = document.get("visual_brief")
    if not isinstance(brief, str) or not brief.strip():
        brief = str(document["gameplay_role"]).replace("_", " ")
    dimensions = document["dimensions_m"]
    states = ", ".join(document["required_states"])
    budget = document["budget"]
    reference_prompt = f"{STYLE_VOCABULARY} Single isolated {brief.strip()}. {NEUTRAL_PRESENTATION}"
    cleanup = (
        f"Create the canonical Blender master at exact dimensions {dimensions} meters; "
        f"pivot={document['pivot']}; forward=+Z; derive states [{states}] from one master; "
        f"budget={_triangle_budget_text(budget['triangles'])}, "
        f"material_slots={budget['material_slots']}, "
        f"texture_resolution={budget['texture_resolution']}; "
        "collision remains owned by godot_wrapper."
    )
    runtime = (
        "Review through a temporary no-promotion Godot overlay using the production "
        "locked-isometric camera in breach_field at seeds 42/777 under "
        "normal/emergency/dark lighting."
    )
    return {
        "asset_id": contract.asset_id,
        "contract_sha256": contract.sha256,
        "reference_prompt": reference_prompt,
        "negative_prompt": NEUTRAL_PRESENTATION,
        "geometry_request": document["generation"],
        "texture_prompt": TEXTURE_VOCABULARY,
        "blender_cleanup_brief": cleanup,
        "runtime_review_brief": runtime,
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    validate = subparsers.add_parser("validate", help="validate one or more contract files")
    validate.add_argument("paths", type=Path, nargs="+")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.command != "validate":  # pragma: no cover - argparse owns command choices
        return 2
    failures: list[str] = []
    for path in args.paths:
        try:
            load_contract(path)
        except (OSError, ValueError) as exc:
            failures.append(f"{path}: {exc}")
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(f"MESHY ASSET CONTRACT PASS assets={len(args.paths)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
