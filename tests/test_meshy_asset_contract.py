from __future__ import annotations

import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

import pytest

from tools import meshy_asset_contract as contract_module
from tools.meshy_asset_contract import (
    canonical_json_bytes,
    load_contract,
    load_prompt_profile,
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

BIOMASS_CATEGORIES = getattr(
    contract_module,
    "BIOMASS_CATEGORIES",
    frozenset({
        "biomass_core",
        "biomass_limb",
        "biomass_head",
        "biomass_connector",
        "biomass_appendage",
    }),
)

PILOT_POLICY_MATRIX = {
    "stalker_v1": {
        "required_views": ["front", "side", "back", "three_quarter"],
        "generation": {
            "mode": "multi_image_to_3d",
            "model_type": "standard",
            "ai_model": "meshy-7",
            "candidate_count": 4,
        },
        "triangles": {"min": 6000, "max": 12000, "scope": "whole_asset"},
        "animation": {
            "kind": "optional_humanoid_biped_rig_after_selection",
            "meshy_rigging_allowed": True,
            "rigging_target": "humanoid_biped",
        },
        "visual_marker": "Low stalking silhouette",
    },
    "hull_tendril_kit_v1": {
        "kit_parts": [
            "root",
            "trunk_module_a",
            "trunk_module_b",
            "trunk_module_c",
            "branch_a",
            "branch_b",
            "attack_tip",
            "severed_tip",
        ],
        "required_states": ["living", "severed"],
        "state_derivation": "one_blender_master",
        "animation": {
            "kind": "blender_segmented_chain_rig",
            "meshy_rigging_allowed": False,
        },
    },
    "biomatter_swarm_kit_v1": {
        "kit_parts": [
            "body_a",
            "body_b",
            "body_c",
            "larva_a",
            "larva_b",
            "ground_wall_cluster",
            "strand",
            "dead_burned_cluster",
        ],
        "triangles": {"min": 300, "max": 800, "scope": "per_part"},
        "animation_kind": "godot_multimesh_particles_behavior",
        "visual_marker": "one shared material atlas",
    },
    "loot_container_derelict_v1": {
        "required_states": ["closed", "open", "looted"],
        "state_derivation": "one_blender_master",
        "animation": {"kind": "hinge", "meshy_rigging_allowed": False},
        "visual_marker": "Generate the closed master only",
    },
    "crafting_station_derelict_v1": {
        "generation": {
            "mode": "image_to_3d",
            "model_type": "smart-topology",
            "ai_model": "meshy-t2",
            "target_polycount": 6000,
        },
        "triangles": {"min": 3000, "max": 6000, "scope": "whole_asset"},
        "visual_marker": "clear front-side interaction silhouette",
    },
}


def test_all_pilot_contracts_validate_and_share_one_prompt_profile() -> None:
    root = Path(__file__).resolve().parents[1]
    contract_root = root / "data/asset_generation/contracts"
    contracts = [
        load_contract(path)
        for path in sorted(contract_root.glob("*.json"))
        if path.stem in PILOT_IDS
    ]
    assert {contract.asset_id for contract in contracts} == PILOT_IDS
    assert {contract.document["prompt_profile"] for contract in contracts} == {
        "synaptic_sea_derelict_v1"
    }


def test_pilot_contracts_match_exact_task_four_policy_matrix() -> None:
    root = Path(__file__).resolve().parents[1]
    contract_root = root / "data/asset_generation/contracts"
    documents = {
        contract.asset_id: contract.document
        for contract in (
            load_contract(path)
            for path in sorted(contract_root.glob("*.json"))
            if path.stem in PILOT_IDS
        )
    }
    assert set(documents) == set(PILOT_POLICY_MATRIX)

    stalker = documents["stalker_v1"]
    stalker_expected = PILOT_POLICY_MATRIX["stalker_v1"]
    assert stalker["references"]["required_views"] == stalker_expected["required_views"]
    assert {
        key: stalker["generation"][key]
        for key in ("mode", "model_type", "ai_model", "candidate_count")
    } == stalker_expected["generation"]
    assert stalker["budget"]["triangles"] == stalker_expected["triangles"]
    assert stalker["animation"] == stalker_expected["animation"]
    assert stalker_expected["visual_marker"] in stalker["visual_brief"]

    tendril = documents["hull_tendril_kit_v1"]
    tendril_expected = PILOT_POLICY_MATRIX["hull_tendril_kit_v1"]
    assert tendril["kit_parts"] == tendril_expected["kit_parts"]
    assert tendril["required_states"] == tendril_expected["required_states"]
    assert tendril["state_derivation"] == tendril_expected["state_derivation"]
    assert tendril["animation"]["kind"] == tendril_expected["animation"]["kind"]
    assert tendril["animation"]["meshy_rigging_allowed"] is tendril_expected["animation"][
        "meshy_rigging_allowed"
    ]

    swarm = documents["biomatter_swarm_kit_v1"]
    swarm_expected = PILOT_POLICY_MATRIX["biomatter_swarm_kit_v1"]
    assert swarm["kit_parts"] == swarm_expected["kit_parts"]
    assert swarm["budget"]["triangles"] == swarm_expected["triangles"]
    assert swarm["animation"]["kind"] == swarm_expected["animation_kind"]
    assert swarm_expected["visual_marker"] in swarm["visual_brief"]

    loot = documents["loot_container_derelict_v1"]
    loot_expected = PILOT_POLICY_MATRIX["loot_container_derelict_v1"]
    assert loot["required_states"] == loot_expected["required_states"]
    assert loot["state_derivation"] == loot_expected["state_derivation"]
    assert loot["animation"]["kind"] == loot_expected["animation"]["kind"]
    assert loot["animation"]["meshy_rigging_allowed"] is loot_expected["animation"][
        "meshy_rigging_allowed"
    ]
    assert loot_expected["visual_marker"] in loot["visual_brief"]

    crafting = documents["crafting_station_derelict_v1"]
    crafting_expected = PILOT_POLICY_MATRIX["crafting_station_derelict_v1"]
    assert {
        key: crafting["generation"][key]
        for key in ("mode", "model_type", "ai_model", "target_polycount")
    } == crafting_expected["generation"]
    assert crafting["budget"]["triangles"] == crafting_expected["triangles"]
    assert crafting_expected["visual_marker"] in crafting["visual_brief"]


def test_shared_style_literal_is_only_in_versioned_prompt_profile() -> None:
    root = Path(__file__).resolve().parents[1]
    profile_path = root / "data/asset_generation/prompt_profiles/synaptic_sea_derelict_v1.json"
    style_vocabulary = json.loads(profile_path.read_text(encoding="utf-8"))["style_vocabulary"]
    tool_text = (root / "tools/meshy_asset_contract.py").read_text(encoding="utf-8")
    contract_text = "\\n".join(
        path.read_text(encoding="utf-8") for path in (root / "data/asset_generation/contracts").glob("*.json")
    )
    assert style_vocabulary not in tool_text
    assert style_vocabulary not in contract_text


def test_prompt_profile_exists_and_contains_rendering_guidance() -> None:
    root = Path(__file__).resolve().parents[1]
    profile_path = root / "data/asset_generation/prompt_profiles/synaptic_sea_derelict_v1.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    assert profile["document_kind"] == "asset_prompt_profile"
    assert profile["profile_id"] == "synaptic_sea_derelict_v1"
    for field in (
        "style_vocabulary",
        "reference_prompt_template",
        "neutral_presentation",
        "texture_guidance",
    ):
        assert isinstance(profile[field], str)
        assert profile[field].strip()
    assert "{style_vocabulary}" in profile["reference_prompt_template"]
    assert "{neutral_presentation}" in profile["reference_prompt_template"]


def test_render_prompt_packet_uses_changed_profile_content_without_repo_mutation(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = Path(__file__).resolve().parents[1]
    profile_path = root / "data/asset_generation/prompt_profiles/synaptic_sea_derelict_v1.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    profile.update(
        style_vocabulary="PROFILE STYLE",
        neutral_presentation="PROFILE NEGATIVE",
        texture_guidance="PROFILE TEXTURE",
        reference_prompt_template="{style_vocabulary} [{visual_brief}] {neutral_presentation}",
    )
    (tmp_path / profile_path.name).write_text(json.dumps(profile), encoding="utf-8")
    monkeypatch.setattr(contract_module, "PROMPT_PROFILE_ROOT", tmp_path, raising=False)

    contract = load_contract(FIXTURES / "valid_loot_container.json")
    packet = render_prompt_packet(contract)

    assert packet["reference_prompt"] == (
        "PROFILE STYLE [searchable loot container] PROFILE NEGATIVE"
    )
    assert packet["negative_prompt"] == "PROFILE NEGATIVE"
    assert packet["texture_prompt"] == "PROFILE STYLE PROFILE TEXTURE"


@pytest.mark.parametrize(
    ("profile_record", "message"),
    [
        (None, "profile must be an object"),
        ("mismatched", "profile_id must match"),
        ({"profile_id": "synaptic_sea_derelict_v1"}, "profile missing field"),
        ("not-json", "invalid JSON"),
    ],
)
def test_render_prompt_packet_rejects_invalid_prompt_profiles(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    profile_record: object,
    message: str,
) -> None:
    profile_path = tmp_path / "synaptic_sea_derelict_v1.json"
    if profile_record == "not-json":
        profile_path.write_text("{not valid", encoding="utf-8")
    elif profile_record == "mismatched":
        root = Path(__file__).resolve().parents[1]
        source = root / "data/asset_generation/prompt_profiles/synaptic_sea_derelict_v1.json"
        mismatched = json.loads(source.read_text(encoding="utf-8"))
        mismatched["profile_id"] = "other_profile"
        profile_path.write_text(json.dumps(mismatched), encoding="utf-8")
    else:
        profile_path.write_text(json.dumps(profile_record), encoding="utf-8")
    monkeypatch.setattr(contract_module, "PROMPT_PROFILE_ROOT", tmp_path, raising=False)

    contract = load_contract(FIXTURES / "valid_loot_container.json")
    with pytest.raises(ValueError, match=message):
        render_prompt_packet(contract)


def test_render_prompt_packet_rejects_missing_prompt_profile(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(contract_module, "PROMPT_PROFILE_ROOT", tmp_path, raising=False)
    contract = load_contract(FIXTURES / "valid_loot_container.json")
    with pytest.raises(ValueError, match="prompt profile.*not found"):
        render_prompt_packet(contract)


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
    assert contract.snapshot_bytes() == canonical_json_bytes(document)


def test_load_contract_uses_strict_bounded_descriptor_reader(tmp_path: Path) -> None:
    source = FIXTURES / "valid_loot_container.json"
    link = tmp_path / "linked-contract.json"
    link.symlink_to(source)
    with pytest.raises(ValueError, match="symlink"):
        load_contract(link)

    oversized = tmp_path / "oversized-contract.json"
    oversized.write_bytes(b" " * (1024 * 1024 + 1))
    with pytest.raises(ValueError, match="size|large"):
        load_contract(oversized)

    nonfinite = tmp_path / "nonfinite-contract.json"
    nonfinite.write_text('{"value":NaN}', encoding="utf-8")
    with pytest.raises(ValueError, match="non-standard|non-finite"):
        load_contract(nonfinite)


def test_asset_contract_document_is_a_fresh_defensive_copy() -> None:
    contract = load_contract(FIXTURES / "valid_loot_container.json")
    first = contract.document
    first["asset_id"] = "mutated"
    first["generation"]["target_polycount"] = 1

    second = contract.document
    assert second["asset_id"] == "loot_container_derelict_v1"
    assert second["generation"]["target_polycount"] == 3000
    assert first is not second


def test_prompt_profile_preserves_original_hash_and_defensive_snapshot(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = Path(__file__).resolve().parents[1] / "data/asset_generation/prompt_profiles/synaptic_sea_derelict_v1.json"
    raw = source.read_bytes() + b"\n"
    profile_path = tmp_path / source.name
    profile_path.write_bytes(raw)
    monkeypatch.setattr(contract_module, "PROMPT_PROFILE_ROOT", tmp_path, raising=False)

    profile = load_prompt_profile("synaptic_sea_derelict_v1")
    profile.document["profile_id"] = "mutated"

    assert profile.profile_id == "synaptic_sea_derelict_v1"
    assert profile.sha256 == hashlib.sha256(raw).hexdigest()
    assert profile.document["profile_id"] == "synaptic_sea_derelict_v1"
    assert profile.snapshot_bytes() != raw


def test_prompt_profile_rejects_unknown_fields(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    source = Path(__file__).resolve().parents[1] / "data/asset_generation/prompt_profiles/synaptic_sea_derelict_v1.json"
    profile = json.loads(source.read_text(encoding="utf-8"))
    profile["unexpected"] = True
    (tmp_path / source.name).write_text(json.dumps(profile), encoding="utf-8")
    monkeypatch.setattr(contract_module, "PROMPT_PROFILE_ROOT", tmp_path, raising=False)

    with pytest.raises(ValueError, match="unknown prompt profile field"):
        load_prompt_profile("synaptic_sea_derelict_v1")


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
        "prompt_profile_id",
        "prompt_profile_sha256",
        "reference_prompt",
        "negative_prompt",
        "geometry_request",
        "texture_prompt",
        "blender_cleanup_brief",
        "runtime_review_brief",
    }
    packet["geometry_request"]["target_polycount"] = 99
    assert contract.document["generation"]["target_polycount"] == 3000
    assert packet["prompt_profile_id"] == "synaptic_sea_derelict_v1"
    profile_path = Path(__file__).resolve().parents[1] / "data/asset_generation/prompt_profiles/synaptic_sea_derelict_v1.json"
    assert packet["prompt_profile_sha256"] == hashlib.sha256(profile_path.read_bytes()).hexdigest()
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


BIOMASS_CONTRACT_SPECS = {
    "biomass_human_arm_v1": ("biomass_limb", [0.28, 0.28, 1.00], 1400, 2500, "attachment"),
    "biomass_insect_leg_v1": ("biomass_limb", [0.35, 0.30, 0.90], 1400, 2500, "attachment"),
    "biomass_cephalopod_tentacle_v1": ("biomass_limb", [0.32, 0.32, 1.20], 1600, 2500, "attachment"),
    "biomass_animal_skull_v1": ("biomass_head", [0.45, 0.40, 0.60], 2200, 3500, "attachment"),
    "biomass_humanoid_torso_v1": ("biomass_core", [0.65, 0.90, 0.40], 3200, 5000, "scene_origin"),
    "biomass_gunk_connector_v1": ("biomass_connector", [0.35, 0.35, 0.25], 300, 500, "attachment"),
    "biomass_claw_v1": ("biomass_appendage", [0.35, 0.20, 0.20], 900, 1500, "attachment"),
    "biomass_maw_v1": ("biomass_appendage", [0.40, 0.30, 0.35], 1000, 1500, "attachment"),
}


def _biomass_document(asset_id: str, category: str) -> dict:
    document = _valid_document()
    document.update(
        asset_id=asset_id,
        category=category,
        pivot="scene_origin" if asset_id == "biomass_humanoid_torso_v1" else "attachment",
        required_states=["default"],
        state_derivation="single_state",
        collision_owner="godot_wrapper",
    )
    document["animation"] = {
        "kind": "static_mesh",
        "meshy_rigging_allowed": False,
        "rigging_target": "none",
    }
    document["generation"]["should_texture"] = False
    return document


def test_biomass_categories_are_closed_and_all_contracts_match_fixed_envelopes() -> None:
    assert BIOMASS_CATEGORIES == {
        "biomass_core",
        "biomass_limb",
        "biomass_head",
        "biomass_connector",
        "biomass_appendage",
    }
    root = Path(__file__).resolve().parents[1]
    contract_root = root / "data/asset_generation/contracts"
    for asset_id, (category, dimensions, target, maximum, pivot) in BIOMASS_CONTRACT_SPECS.items():
        document = load_contract(contract_root / (asset_id + ".json")).document
        assert set(document) <= {
            "schema_version", "document_kind", "asset_id", "category", "gameplay_role",
            "dimensions_m", "dimension_tolerance_m", "pivot", "forward_axis", "allowed_yaw_deg",
            "required_states", "state_derivation", "collision_owner", "animation", "budget",
            "references", "generation", "review", "prompt_profile", "visual_brief",
        }
        assert document["category"] == category
        assert document["dimensions_m"] == dimensions
        assert document["pivot"] == pivot
        assert document["forward_axis"] == "+Z"
        assert document["required_states"] == ["default"]
        assert document["state_derivation"] == "single_state"
        assert document["collision_owner"] == "godot_wrapper"
        assert document["animation"] == {
            "kind": "static_mesh", "meshy_rigging_allowed": False, "rigging_target": "none"
        }
        assert document["budget"]["triangles"] == {
            "min": 1, "max": maximum, "scope": "whole_asset"
        }
        assert document["budget"]["material_slots"] == 2
        assert document["budget"]["texture_resolution"] == 2048
        assert document["generation"]["target_polycount"] == target
        assert document["generation"]["candidate_count"] == 4
        assert document["generation"]["should_texture"] is False
        assert document["references"] == {
            "required_views": ["three_quarter"],
            "input_layout": "separate_files",
            "rights_state": "project-owned",
        }


@pytest.mark.parametrize("category", sorted(BIOMASS_CATEGORIES))
@pytest.mark.parametrize(
    ("field", "value", "message"),
    [
        ("collision_owner", "blender", "biomass assets require collision_owner=godot_wrapper"),
        ("animation", {"kind": "rigged", "meshy_rigging_allowed": False, "rigging_target": "none"}, "biomass assets require animation.kind=static_mesh"),
        ("animation", {"kind": "static_mesh", "meshy_rigging_allowed": True, "rigging_target": "humanoid_biped"}, "biomass assets prohibit Meshy rigging"),
        ("required_states", ["living", "dead"], "biomass assets require required_states=[default]"),
        ("state_derivation", "one_blender_master", "biomass assets require state_derivation=single_state"),
        ("pivot", "bottom_center", "biomass assets require pivot=attachment"),
    ],
)
def test_biomass_policy_rejects_runtime_authority_and_non_visual_variants(
    category: str, field: str, value: object, message: str
) -> None:
    document = _biomass_document("biomass_test_part_v1", category)
    if field == "animation":
        document[field] = value
    else:
        document[field] = value
    errors = validate_contract(document)
    assert message in errors


def test_biomass_policy_rejects_texturing_and_torso_attachment_pivot() -> None:
    document = _biomass_document("biomass_test_part_v1", "biomass_limb")
    document["generation"]["should_texture"] = True
    assert "biomass assets require generation.should_texture=false" in validate_contract(document)

    torso = _biomass_document("biomass_humanoid_torso_v1", "biomass_core")
    torso["pivot"] = "attachment"
    assert "biomass_humanoid_torso_v1 requires pivot=scene_origin" in validate_contract(torso)
