from __future__ import annotations

import hashlib
import inspect
import json
import os
import shutil
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Iterator, Tuple

import pytest

from tools import meshy_blender_validate as validate_module
from tools import meshy_governance as governance
from tools.meshy_asset_contract import canonical_json_bytes, load_contract, render_prompt_packet
from tools.meshy_candidate_review import CHECK_FIELDS, select_candidate
from tools.meshy_stage import generate_batch
from tools.meshy_texture_packet import (
    TEXTURE_REQUEST_NAME,
    TexturePacketError,
    build_texture_request,
    load_material_vocabulary,
    validate_texture_inputs,
    write_texture_request,
)

ROOT = Path(__file__).resolve().parents[1]
VOCABULARY_PATH = ROOT / "data/asset_generation/material_vocabulary.json"
CONTRACT_PATH = ROOT / "tests/fixtures/meshy_blender/fixture_contract.json"
GLB_PATH = ROOT / "tests/fixtures/meshy_blender/fixture_triangle.glb"
STAGING = Path("assets/_staging/meshy")


class _NoNetworkClient:
    def get_balance(self) -> int:
        return 10000

    def create_task(self, *_args: Any, **_kwargs: Any) -> str:
        raise AssertionError("texture packet must never create a Meshy task")

    def poll_task(self, *_args: Any, **_kwargs: Any) -> dict:
        raise AssertionError("texture packet must never poll a Meshy task")

    def download_bytes(self, *_args: Any, **_kwargs: Any) -> bytes:
        raise AssertionError("texture packet must never download a Meshy texture")


@pytest.fixture()
def governed_task(tmp_path: Path) -> Tuple[Path, Path, Any]:
    """Create a real staged generation, selected review, GLB, and R4 report."""
    from tests.test_meshy_candidate_review import (
        _ReviewFakeMeshyClient,
        _true_checks,
        _write_review_references,
    )

    project_root = tmp_path / "project"
    project_root.mkdir()
    references = project_root / "references"
    references.mkdir()
    contract = load_contract(CONTRACT_PATH)
    specs = _write_review_references(references)
    generate_batch(
        contract,
        project_root,
        _ReviewFakeMeshyClient(),
        100,
        pricing_file=None,
        reference_root=references,
        reference_specs={"front": specs["front"]},
        output_license="paid-private",
        today="2026-09-01",
    )
    task_root = project_root / STAGING / contract.asset_id
    task_dir = next(path for path in task_root.iterdir() if path.name != "_batches")
    select_candidate(project_root, task_dir, "operator", _true_checks())

    shutil.copy2(GLB_PATH, task_dir / "cleaned.glb")
    report = validate_module.validate_cleaned_glb(
        task_dir / "cleaned.glb", contract, task_id=task_dir.name
    )
    report["blender_reimport_passed"] = True
    validate_module._validate_report_record(report)
    (task_dir / "blender-validation.json").write_bytes(canonical_json_bytes(report))
    return project_root, task_dir, contract


def _request_args(project_root: Path, task_dir: Path, contract: Any, **kwargs: Any) -> Dict[str, Any]:
    values: Dict[str, Any] = {
        "project_root": project_root,
        "contract": contract,
        "task_dir": task_dir,
        "material_family": "painted_ship_alloy",
        "resolution": 1024,
        "reviewer": "operator",
        "approved_credits": 10,
    }
    values.update(kwargs)
    return values


def _request(project_root: Path, task_dir: Path, contract: Any, **kwargs: Any) -> Dict[str, Any]:
    return build_texture_request(**_request_args(project_root, task_dir, contract, **kwargs))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _snapshot_task(task_dir: Path) -> Dict[str, bytes]:
    return {
        path.name: path.read_bytes()
        for path in task_dir.iterdir()
        if path.is_file() and not path.is_symlink()
    }


def _true_checks() -> Dict[str, bool]:
    return {field: True for field in CHECK_FIELDS}


def test_texture_api_requires_project_root_first() -> None:
    assert list(inspect.signature(validate_texture_inputs).parameters)[0] == "project_root"
    assert list(inspect.signature(build_texture_request).parameters)[0] == "project_root"
    assert list(inspect.signature(write_texture_request).parameters)[0] == "project_root"
    with pytest.raises(TypeError):
        build_texture_request(
            contract=CONTRACT_PATH,
            task_dir=Path("task"),
            material_family="painted_ship_alloy",
            resolution=1024,
            reviewer="operator",
            approved_credits=10,
        )


def test_texture_packet_cli_requires_project_root_and_has_no_legacy_paths() -> None:
    result = subprocess.run(
        [sys.executable, "tools/meshy_texture_packet.py", "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert "--project-root" in result.stdout
    assert "--output" not in result.stdout
    assert "--report" not in result.stdout
    assert "--validation" not in result.stdout


def test_texture_packet_requires_exact_governed_task_layout(governed_task) -> None:
    project_root, task_dir, contract = governed_task
    outside = project_root.parent / "outside-task"
    outside.mkdir()
    nested = task_dir / "nested"
    nested.mkdir()
    for candidate in (outside, nested):
        with pytest.raises(TexturePacketError, match="staging|direct|task"):
            _request(project_root, candidate, contract)

    linked_staging = project_root / "linked-staging"
    linked_staging.symlink_to(project_root / "assets/_staging", target_is_directory=True)
    linked_asset = linked_staging / "meshy" / contract.asset_id
    linked_task = linked_asset / task_dir.name
    with pytest.raises(TexturePacketError, match="symlink|staging|task"):
        _request(project_root, linked_task, contract)

    linked_asset_root = project_root / STAGING / "linked-asset"
    linked_asset_root.symlink_to(task_dir.parent, target_is_directory=True)
    with pytest.raises(TexturePacketError, match="symlink|staging|task"):
        _request(project_root, linked_asset_root / task_dir.name, contract)

    linked_task = task_dir.parent / "linked-task"
    linked_task.symlink_to(task_dir, target_is_directory=True)
    with pytest.raises(TexturePacketError, match="symlink|task"):
        _request(project_root, linked_task, contract)


def test_texture_packet_requires_canonical_bound_generation_review_and_report(governed_task) -> None:
    project_root, task_dir, contract = governed_task
    report_path = task_dir / "blender-validation.json"
    original = report_path.read_bytes()
    try:
        minimal = {"status": "PASS", "uvs_present": True}
        report_path.write_bytes(canonical_json_bytes(minimal))
        with pytest.raises(TexturePacketError, match="canonical|fields|validation"):
            _request(project_root, task_dir, contract)

        report_path.write_bytes(original[:-1])
        with pytest.raises(TexturePacketError, match="canonical"):
            _request(project_root, task_dir, contract)

        report = json.loads(original.decode("utf-8"))
        for field, value in (
            ("status", "PASS"),
            ("uvs_present", True),
            ("blender_reimport_passed", True),
        ):
            report[field] = value
        report.pop("uv_evidence")
        report_path.write_bytes(canonical_json_bytes(report))
        with pytest.raises(TexturePacketError, match="UV|canonical|validation"):
            _request(project_root, task_dir, contract)

        report = json.loads(original.decode("utf-8"))
        report["blender_reimport_passed"] = False
        report_path.write_bytes(canonical_json_bytes(report))
        with pytest.raises(TexturePacketError, match="re-import|reimport|validation"):
            _request(project_root, task_dir, contract)
    finally:
        report_path.write_bytes(original)


def test_texture_packet_rejects_report_identity_and_cleaned_mutations(governed_task) -> None:
    project_root, task_dir, contract = governed_task
    report_path = task_dir / "blender-validation.json"
    original_report = report_path.read_bytes()
    original_cleaned = (task_dir / "cleaned.glb").read_bytes()
    try:
        for field, value in (
            ("task_id", "other-task"),
            ("asset_id", "other_asset"),
            ("contract_sha256", "0" * 64),
            ("sha256", "0" * 64),
            ("byte_size", 1),
        ):
            report = json.loads(original_report.decode("utf-8"))
            report[field] = value
            report_path.write_bytes(canonical_json_bytes(report))
            with pytest.raises(TexturePacketError, match="match|identity|cleaned|report|contract"):
                _request(project_root, task_dir, contract)
            report_path.write_bytes(original_report)

        (task_dir / "cleaned.glb").write_bytes(original_cleaned + b"\0")
        with pytest.raises(TexturePacketError, match="cleaned|hash|report"):
            _request(project_root, task_dir, contract)
    finally:
        (task_dir / "cleaned.glb").write_bytes(original_cleaned)
        report_path.write_bytes(original_report)


def test_texture_packet_uses_canonical_loader_state_gates(governed_task) -> None:
    project_root, task_dir, contract = governed_task
    review_path = task_dir / "review.json"
    generation_path = task_dir / "generation.json"
    original_review = review_path.read_bytes()
    original_generation = generation_path.read_bytes()
    try:
        review = json.loads(original_review.decode("utf-8"))
        review.update(state="pending", decision="pending", checks={field: False for field in CHECK_FIELDS})
        review_path.write_bytes(canonical_json_bytes(review))
        with pytest.raises(TexturePacketError, match="selected|review"):
            _request(project_root, task_dir, contract)
        review_path.write_bytes(original_review)

        generation = json.loads(original_generation.decode("utf-8"))
        generation["status"] = "PENDING"
        generation["completed_at"] = None
        generation["consumed_credits"] = None
        generation["outputs"] = {}
        generation["error"] = None
        generation["budget_violation"] = False
        generation_path.write_bytes(canonical_json_bytes(generation))
        with pytest.raises(TexturePacketError, match="generation|SUCCEEDED"):
            _request(project_root, task_dir, contract)
    finally:
        review_path.write_bytes(original_review)
        generation_path.write_bytes(original_generation)


def test_texture_packet_preserves_family_gates_and_profile_prompt(governed_task) -> None:
    project_root, task_dir, contract = governed_task
    with pytest.raises(TexturePacketError, match="material family"):
        _request(project_root, task_dir, contract, material_family="unknown_family")
    with pytest.raises(TexturePacketError, match="remove_lighting"):
        _request(project_root, task_dir, contract, remove_lighting=False)
    with pytest.raises(TexturePacketError, match="PBR"):
        _request(project_root, task_dir, contract, pbr_enabled=False)
    with pytest.raises(TexturePacketError, match="emission"):
        _request(project_root, task_dir, contract, meshy_emission=True)
    with pytest.raises(TexturePacketError, match="resolution"):
        _request(project_root, task_dir, contract, resolution=2048)
    with pytest.raises(TexturePacketError, match="credit"):
        _request(project_root, task_dir, contract, approved_credits=9)

    request = _request(project_root, task_dir, contract)
    assert render_prompt_packet(contract)["texture_prompt"] in request["prompt"]
    assert request["material_family"] == "painted_ship_alloy"
    assert request["remove_lighting"] is True
    assert request["pbr"] == {"enabled": True, "emission": False, "model": "meshy-7"}
    assert request["proposal_only"] is True


def test_texture_packet_success_binds_all_canonical_evidence(governed_task) -> None:
    project_root, task_dir, contract = governed_task
    request = _request(project_root, task_dir, contract, reviewer=" operator ")
    evidence = request["evidence"]
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    review = json.loads((task_dir / "review.json").read_text(encoding="utf-8"))
    report = json.loads((task_dir / "blender-validation.json").read_text(encoding="utf-8"))

    assert request["asset_id"] == contract.asset_id
    assert request["contract_sha256"] == contract.sha256
    assert request["task_id"] == task_dir.name
    assert request["reviewer"] == "operator"
    assert request["contract"] == {"asset_id": contract.asset_id, "sha256": contract.sha256}

    for key, filename, source in (
        ("generation", "generation.json", generation),
        ("review", "review.json", review),
        ("blender_validation", "blender-validation.json", report),
    ):
        assert evidence[key]["basename"] == filename
        assert evidence[key]["sha256"] == _sha256(task_dir / filename)
    assert evidence["generation"]["status"] == "SUCCEEDED"
    assert evidence["review"]["state"] == "selected"
    assert evidence["blender_validation"]["status"] == "PASS"
    assert evidence["blender_validation"]["uvs_present"] is True
    assert evidence["blender_validation"]["blender_reimport_passed"] is True
    assert evidence["blender_validation"]["uv_evidence"] is True
    assert evidence["cleaned_glb"] == {
        "basename": "cleaned.glb",
        "sha256": _sha256(task_dir / "cleaned.glb"),
        "byte_size": (task_dir / "cleaned.glb").stat().st_size,
    }
    assert evidence["generation"]["raw_glb"] == {
        "basename": "raw.glb",
        "sha256": generation["outputs"]["raw.glb"]["sha256"],
        "byte_size": generation["outputs"]["raw.glb"]["byte_size"],
    }
    assert all(
        isinstance(value, str) and len(value) == 64 and value == value.lower()
        for value in (
            evidence["generation"]["sha256"],
            evidence["review"]["sha256"],
            evidence["blender_validation"]["sha256"],
            evidence["cleaned_glb"]["sha256"],
            evidence["generation"]["raw_glb"]["sha256"],
        )
    )
    encoded = json.dumps(request, sort_keys=True)
    assert str(project_root) not in encoded
    assert str(task_dir) not in encoded


def test_texture_packet_writes_only_fixed_leaf_atomically_and_preserves_surfaces(governed_task) -> None:
    project_root, task_dir, contract = governed_task
    before = _snapshot_task(task_dir)
    protected_before = governance.snapshot_protected_surfaces(project_root)
    request = write_texture_request(**_request_args(project_root, task_dir, contract))
    destination = task_dir / TEXTURE_REQUEST_NAME

    assert destination.is_file()
    assert stat.S_IMODE(destination.stat().st_mode) == 0o600
    assert destination.read_bytes() == canonical_json_bytes(request)
    assert destination.read_bytes() == canonical_json_bytes(json.loads(destination.read_text()))
    after = _snapshot_task(task_dir)
    assert set(after) == set(before) | {TEXTURE_REQUEST_NAME}
    for name, payload in before.items():
        assert after[name] == payload
    assert governance.snapshot_protected_surfaces(project_root) == protected_before
    assert not list(task_dir.glob(".*texture_request.json.*.tmp"))


def test_texture_packet_rejects_output_symlink_and_non_regular_without_touching_outside(governed_task) -> None:
    project_root, task_dir, contract = governed_task
    sentinel = project_root.parent / "outside-sentinel"
    sentinel.write_bytes(b"untouched")
    destination = task_dir / TEXTURE_REQUEST_NAME
    destination.symlink_to(sentinel)
    before = _snapshot_task(task_dir)
    with pytest.raises(TexturePacketError, match="regular|symlink|output"):
        write_texture_request(**_request_args(project_root, task_dir, contract))
    assert sentinel.read_bytes() == b"untouched"
    assert _snapshot_task(task_dir) == before
    destination.unlink()

    destination.mkdir()
    with pytest.raises(TexturePacketError, match="regular|directory|output"):
        write_texture_request(**_request_args(project_root, task_dir, contract))
    assert sentinel.read_bytes() == b"untouched"
    destination.rmdir()


def test_texture_packet_rejects_ordinary_directory_rebind_at_governance_hook(governed_task, monkeypatch) -> None:
    project_root, task_dir, contract = governed_task
    sentinel = project_root.parent / "outside-rebind"
    sentinel.write_bytes(b"untouched")
    destination = task_dir / TEXTURE_REQUEST_NAME

    def rebind(_target: Path) -> None:
        destination.mkdir()

    monkeypatch.setattr(governance, "_ATOMIC_VALIDATION_HOOK", rebind)
    before = _snapshot_task(task_dir)
    with pytest.raises(TexturePacketError, match="regular|directory|output|appeared"):
        write_texture_request(**_request_args(project_root, task_dir, contract))
    assert sentinel.read_bytes() == b"untouched"
    assert _snapshot_task(task_dir) == before
    assert not list(task_dir.glob(".*texture_request.json.*.tmp"))
    destination.rmdir()


def test_material_vocabulary_remains_closed() -> None:
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
