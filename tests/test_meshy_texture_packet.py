from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.meshy_asset_contract import canonical_json_bytes, load_contract, render_prompt_packet
from tools.meshy_texture_packet import (
    TexturePacketError,
    build_texture_request,
    load_material_vocabulary,
    write_texture_request,
)


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "tests/fixtures/meshy_asset_contract/valid_loot_container.json"
VOCABULARY_PATH = ROOT / "data/asset_generation/material_vocabulary.json"


@pytest.fixture
def contract():
    return load_contract(CONTRACT_PATH)


def _task_dir(tmp_path: Path, *, status: str = "PASS", uvs_present: bool = True) -> Path:
    task_dir = tmp_path / "task"
    task_dir.mkdir(parents=True)
    (task_dir / "blender-validation.json").write_bytes(
        canonical_json_bytes(
            {
                "asset_id": "loot_container_derelict_v1",
                "status": status,
                "uvs_present": uvs_present,
            }
        )
    )
    return task_dir


def _request(contract, task_dir: Path, **kwargs):
    values = {
        "contract": contract,
        "task_dir": task_dir,
        "material_family": "painted_ship_alloy",
        "resolution": 1024,
        "reviewer": "operator",
        "approved_credits": 10,
    }
    values.update(kwargs)
    return build_texture_request(**values)


def test_texture_packet_validates_blender_pass(contract, tmp_path: Path) -> None:
    missing = tmp_path / "missing-task"
    missing.mkdir()
    with pytest.raises(TexturePacketError, match="blender-validation.json"):
        _request(contract, missing)

    failed = _task_dir(tmp_path / "failed", status="FAIL")
    with pytest.raises(TexturePacketError, match="PASS"):
        _request(contract, failed)


def test_texture_packet_rejects_missing_uvs(contract, tmp_path: Path) -> None:
    task_dir = _task_dir(tmp_path, uvs_present=False)
    with pytest.raises(TexturePacketError, match="UV"):
        _request(contract, task_dir)


def test_texture_packet_rejects_unknown_family(contract, tmp_path: Path) -> None:
    with pytest.raises(TexturePacketError, match="material family"):
        _request(contract, _task_dir(tmp_path), material_family="unknown_family")


def test_texture_packet_requires_remove_lighting(contract, tmp_path: Path) -> None:
    with pytest.raises(TexturePacketError, match="remove_lighting"):
        _request(contract, _task_dir(tmp_path), remove_lighting=False)


def test_texture_packet_requires_pbr(contract, tmp_path: Path) -> None:
    with pytest.raises(TexturePacketError, match="PBR"):
        _request(contract, _task_dir(tmp_path), pbr_enabled=False)


def test_texture_packet_rejects_emission_claim(contract, tmp_path: Path) -> None:
    with pytest.raises(TexturePacketError, match="emission"):
        _request(contract, _task_dir(tmp_path), meshy_emission=True)


def test_texture_packet_respects_resolution_budget(contract, tmp_path: Path) -> None:
    with pytest.raises(TexturePacketError, match="resolution"):
        _request(contract, _task_dir(tmp_path), resolution=2048)


def test_texture_packet_writes_canonical_request(contract, tmp_path: Path) -> None:
    task_dir = _task_dir(tmp_path)
    request = write_texture_request(
        contract,
        task_dir,
        material_family="painted_ship_alloy",
        resolution=1024,
        reviewer="operator",
        approved_credits=10,
    )
    path = task_dir / "texture_request.json"
    assert path.is_file()
    assert path.read_bytes() == canonical_json_bytes(request)
    assert request["asset_id"] == contract.asset_id
    assert request["contract_sha256"] == contract.sha256
    assert request["material_family"] == "painted_ship_alloy"
    assert request["resolution"] == 1024
    assert request["pbr"]["enabled"] is True
    assert request["pbr"]["model"] == "meshy-7"
    assert request["remove_lighting"] is True
    assert request["reviewer"] == "operator"
    assert request["proposal_only"] is True
    assert not (task_dir / "cleaned.glb").exists()


def test_texture_packet_includes_profile_prompt(contract, tmp_path: Path) -> None:
    task_dir = _task_dir(tmp_path)
    request = _request(contract, task_dir)
    profile_prompt = render_prompt_packet(contract)["texture_prompt"]
    assert profile_prompt in request["prompt"]
    assert "painted_ship_alloy" in request["prompt"]
    assert "matte desaturated painted alloy" in request["prompt"]


def test_material_vocabulary_has_nine_families() -> None:
    vocabulary = load_material_vocabulary(VOCABULARY_PATH)
    assert len(vocabulary) == 9
    assert set(vocabulary) == {
        "painted_ship_alloy",
        "exposed_structural_steel",
        "rubber_seal",
        "dirty_polymer",
        "oxidized_brass_copper",
        "biomatter_flesh",
        "calcified_biomatter",
        "wet_membrane",
        "indicator_lens",
    }
    for family in vocabulary.values():
        assert {
            "canonical_name",
            "base_traits",
            "allowed_accent_colors",
            "roughness_range",
            "metallic_range",
            "manual_emission_required",
        } <= set(family)


def test_material_vocabulary_file_is_canonical_json() -> None:
    raw = VOCABULARY_PATH.read_bytes()
    assert raw == canonical_json_bytes(json.loads(raw.decode("utf-8")))
