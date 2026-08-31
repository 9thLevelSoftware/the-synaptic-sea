from __future__ import annotations

import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

import pytest

from tools.meshy_asset_contract import (
    canonical_json_bytes,
    load_contract,
    render_prompt_packet,
    validate_contract,
)

FIXTURES = Path(__file__).parent / "fixtures/meshy_asset_contract"
SCHEMA = (
    Path(__file__).parents[1]
    / "data/asset_generation/schemas/ai_asset_contract_v1.schema.json"
)


PILOT_IDS = {
    "stalker_v1",
    "hull_tendril_kit_v1",
    "biomatter_swarm_kit_v1",
    "loot_container_derelict_v1",
    "crafting_station_derelict_v1",
}


def test_all_pilot_contracts_validate_and_share_one_prompt_profile() -> None:
    root = Path(__file__).resolve().parents[1]
    contract_root = root / "data/asset_generation/contracts"
    contracts = [load_contract(path) for path in sorted(contract_root.glob("*.json"))]
    assert {contract.asset_id for contract in contracts} == PILOT_IDS
    assert {contract.document["prompt_profile"] for contract in contracts} == {
        "synaptic_sea_derelict_v1"
    }


def _valid_document() -> dict:
    return json.loads(
        (FIXTURES / "valid_loot_container.json").read_text(encoding="utf-8")
    )


def _write_document(tmp_path: Path, document: dict, name: str = "contract.json") -> Path:
    path = tmp_path / name
    path.write_text(json.dumps(document, ensure_ascii=False), encoding="utf-8")
    return path


def test_valid_contract_renders_deterministic_prompt_packet() -> None:
    contract = load_contract(FIXTURES / "valid_loot_container.json")
    first = render_prompt_packet(contract)
    second = render_prompt_packet(contract)
    assert first == second
    assert first["asset_id"] == "loot_container_derelict_v1"
    assert first["geometry_request"]["should_texture"] is False
    assert first["reference_prompt"].endswith(
        "No environment, no floor, no cast shadow, no readable text, no logo, "
        "no floating parts, no duplicate components, no dramatic perspective, "
        "no depth of field, no baked lighting."
    )


@pytest.mark.parametrize(
    ("fixture", "message"),
    [
        ("invalid_structural_meshy.json", "structural geometry cannot use Meshy"),
        ("invalid_independent_states.json", "alternate states must derive from one master"),
        ("invalid_rigging_target.json", "Meshy rigging is limited to humanoid bipeds"),
        ("invalid_reference_rights.json", "reference rights must be explicit"),
    ],
)
def test_invalid_contracts_fail_closed(fixture: str, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        load_contract(FIXTURES / fixture)


def test_canonical_json_is_sorted_compact_unicode_and_single_newline() -> None:
    assert canonical_json_bytes({"z": "café", "a": [True, 1]}) == (
        b'{"a":[true,1],"z":"caf\xc3\xa9"}\n'
    )
    with pytest.raises(ValueError):
        canonical_json_bytes({"value": math.nan})


def test_load_contract_hashes_original_bytes(tmp_path: Path) -> None:
    document = _valid_document()
    raw = json.dumps(document, ensure_ascii=False, indent=2).encode("utf-8") + b"\n"
    path = tmp_path / "contract.json"
    path.write_bytes(raw)
    contract = load_contract(path)
    assert contract.sha256 == hashlib.sha256(raw).hexdigest()
    assert contract.asset_id == document["asset_id"]


def test_prompt_packet_uses_immutable_snapshot_after_document_mutation() -> None:
    contract = load_contract(FIXTURES / "valid_loot_container.json")
    before = render_prompt_packet(contract)

    contract.document["asset_id"] = "mutated_asset"
    contract.document["visual_brief"] = "mutated brief"
    contract.document["generation"]["target_polycount"] = 99

    after = render_prompt_packet(contract)
    assert after == before
    assert after["asset_id"] == "loot_container_derelict_v1"
    assert after["geometry_request"]["target_polycount"] == 3000
    assert after["contract_sha256"] == contract.sha256


def test_duplicate_json_keys_are_rejected(tmp_path: Path) -> None:
    path = tmp_path / "duplicate.json"
    path.write_text('{"asset_id":"x","asset_id":"y"}', encoding="utf-8")
    with pytest.raises(ValueError, match="duplicate JSON key"):
        load_contract(path)


def test_nested_duplicate_json_keys_are_rejected(tmp_path: Path) -> None:
    path = tmp_path / "nested-duplicate.json"
    path.write_text(
        '{"generation":{"provider":"meshy","provider":"other"}}',
        encoding="utf-8",
    )
    with pytest.raises(ValueError, match="duplicate JSON key"):
        load_contract(path)


def test_cli_deep_json_recursion_is_nonzero_path_scoped_without_traceback(
    tmp_path: Path,
) -> None:
    path = tmp_path / "deep.json"
    depth = 3000
    path.write_text("[" * depth + "]" * depth, encoding="utf-8")
    result = subprocess.run(
        [sys.executable, "tools/meshy_asset_contract.py", "validate", str(path)],
        cwd=Path(__file__).parents[1],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
    assert f"{path}:" in result.stderr
    assert "invalid JSON" in result.stderr
    assert "Traceback" not in result.stderr


def test_unknown_top_level_and_nested_fields_are_rejected() -> None:
    document = _valid_document()
    document["unexpected"] = True
    document["animation"]["unexpected"] = True
    errors = validate_contract(document)
    assert errors == sorted(set(errors))
    assert "unknown top-level field: unexpected" in errors
    assert "unknown animation field: unexpected" in errors


def test_nonfinite_values_are_rejected_recursively() -> None:
    document = _valid_document()
    document["budget"]["triangles"] = [math.inf]
    errors = validate_contract(document)
    assert "budget.triangles[0] contains non-finite value" in errors


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("asset_id", "Not-Lowercase"),
        ("dimensions_m", [0.9, 0, 0.65]),
        ("pivot", "bad"),
        ("forward_axis", "-Z"),
    ],
)
def test_core_contract_fields_are_fail_closed(field: str, value: object) -> None:
    document = _valid_document()
    document[field] = value
    errors = validate_contract(document)
    if field == "asset_id":
        assert any("must be a lowercase identifier" in error for error in errors)
    elif field == "dimensions_m":
        assert any("dimensions_m must contain exactly 3 positive" in error for error in errors)
    elif field == "pivot":
        assert any("pivot must be one of" in error for error in errors)
    else:
        assert any("forward_axis must be +Z" in error for error in errors)


@pytest.mark.parametrize("candidate_count", [2, 7])
def test_candidate_count_must_be_between_three_and_six(candidate_count: int) -> None:
    document = _valid_document()
    document["generation"]["candidate_count"] = candidate_count
    errors = validate_contract(document)
    assert "candidate_count must be between 3 and 6" in errors


def test_geometry_candidates_must_be_untextured() -> None:
    document = _valid_document()
    document["generation"]["should_texture"] = True
    assert "geometry candidates must be untextured" in validate_contract(document)


@pytest.mark.parametrize("target_polycount", [99, 15001])
def test_smart_topology_target_polycount_has_bounded_range(target_polycount: int) -> None:
    document = _valid_document()
    document["generation"]["target_polycount"] = target_polycount
    assert (
        "Smart Topology target_polycount must be between 100 and 15000"
        in validate_contract(document)
    )


def test_reference_collage_input_is_rejected() -> None:
    document = _valid_document()
    document["references"]["input_layout"] = "collage"
    errors = validate_contract(document)
    assert "references.input_layout must be separate_files; collage is not allowed" in errors


def test_collision_owner_must_remain_with_godot_wrapper() -> None:
    document = _valid_document()
    document["collision_owner"] = "blender"
    assert "collision ownership must remain with godot_wrapper" in validate_contract(document)


def test_multi_image_rejects_t2_and_too_few_views() -> None:
    document = _valid_document()
    document["generation"].update(
        mode="multi_image_to_3d", model_type="smart-topology", ai_model="meshy-t2"
    )
    document["references"]["required_views"] = ["front"]
    errors = validate_contract(document)
    assert "Multi-Image does not support Smart Topology T2" in errors
    assert "multi_image_to_3d requires 2-4 reference views" in errors


def test_review_matrix_must_match_governed_values() -> None:
    document = _valid_document()
    document["review"] = {"seeds": [1], "lighting_modes": ["normal"]}
    errors = validate_contract(document)
    assert "review.seeds must equal [42, 777]" in errors
    assert "review.lighting_modes must equal [normal, emergency, dark]" in errors


def test_kit_requires_parts_and_accepts_bounded_triangle_range() -> None:
    document = _valid_document()
    document["asset_id"] = "salvage_kit"
    document["budget"]["triangles"] = {
        "min": 100,
        "max": 3000,
        "scope": "per_part",
    }
    assert "kit contract must declare kit_parts or deliverables" in validate_contract(document)
    document["kit_parts"] = ["lid", "base"]
    assert validate_contract(document) == []


@pytest.mark.parametrize(
    ("asset_id", "requires_metadata"),
    [("kit_v1", True), ("toolkit", False), ("foo_kitten", False)],
)
def test_kit_detection_matches_schema_token_boundaries(
    asset_id: str, requires_metadata: bool
) -> None:
    document = _valid_document()
    document["asset_id"] = asset_id
    errors = validate_contract(document)
    message = "kit contract must declare kit_parts or deliverables"
    assert (message in errors) is requires_metadata


def test_reversed_triangle_range_is_rejected_by_python_validator() -> None:
    document = _valid_document()
    document["budget"]["triangles"] = {
        "min": 3000,
        "max": 100,
        "scope": "whole_asset",
    }
    assert "budget.triangles min must not exceed max" in validate_contract(document)


def test_prompt_packet_has_exact_keys_and_does_not_alias_generation() -> None:
    contract = load_contract(FIXTURES / "valid_loot_container.json")
    packet = render_prompt_packet(contract)
    assert set(packet) == {
        "asset_id",
        "contract_sha256",
        "reference_prompt",
        "negative_prompt",
        "geometry_request",
        "texture_prompt",
        "blender_cleanup_brief",
        "runtime_review_brief",
    }
    packet["geometry_request"]["target_polycount"] = 99
    assert contract.document["generation"]["target_polycount"] == 3000
    assert "Grounded utilitarian industrial science fiction" in packet["reference_prompt"]
    assert "Grounded utilitarian industrial science fiction" in packet["texture_prompt"]
    assert "texture_resolution=1024" in packet["blender_cleanup_brief"]
    assert "42/777" in packet["runtime_review_brief"]
    assert "breach_field" in packet["runtime_review_brief"]


def test_schema_records_runtime_cross_field_constraints() -> None:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    encoded = json.dumps(schema["allOf"], sort_keys=True)
    assert "one_blender_master" in encoded
    assert "humanoid_biped" in encoded
    assert "^structural(?:_|$)" in encoded
    assert "multi_image_to_3d" in encoded
    assert "kit_parts" in encoded and "deliverables" in encoded
    assert "min <= max" in schema["$defs"]["triangleBudget"]["$comment"]
    assert "Python validator is authoritative" in schema["$defs"]["triangleBudget"]["$comment"]


def test_schema_visual_brief_rejects_whitespace_only() -> None:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    assert schema["properties"]["visual_brief"]["pattern"] == r"\S"


def test_cli_validate_success_prints_marker() -> None:
    result = subprocess.run(
        [
            sys.executable,
            "tools/meshy_asset_contract.py",
            "validate",
            str(FIXTURES / "valid_loot_container.json"),
        ],
        cwd=Path(__file__).parents[1],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert result.stdout.strip() == "MESHY ASSET CONTRACT PASS assets=1"


def test_cli_validate_invalid_is_nonzero_and_path_scoped(tmp_path: Path) -> None:
    document = _valid_document()
    document["generation"]["candidate_count"] = 2
    path = _write_document(tmp_path, document)
    result = subprocess.run(
        [sys.executable, "tools/meshy_asset_contract.py", "validate", str(path)],
        cwd=Path(__file__).parents[1],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert f"{path}: candidate_count must be between 3 and 6" in result.stderr
