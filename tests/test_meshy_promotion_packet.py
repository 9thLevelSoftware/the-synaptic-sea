from __future__ import annotations

import binascii
import hashlib
import json
import os
import stat
import struct
import time
import zlib
from pathlib import Path
from types import SimpleNamespace
from typing import Any, Dict, Tuple

import pytest

from tools import meshy_governance as governance
from tools.meshy_asset_contract import canonical_json_bytes
from tools.meshy_promotion_packet import (
    ASSET_PROVENANCE_NAME,
    PROP_OVERLAY_NAME,
    THREAT_PATCH_NAME,
    PromotionPacketError,
    build_prop_promotion_proposal,
    build_threat_promotion_proposal,
    validate_ai_provenance,
    write_prop_promotion_proposal,
    write_threat_promotion_proposal,
)


LIVE_RELATIVE = (
    "assets/imported/props/fixture_triangle.sidecar.json",
    "data/combat/threat_visual_catalog.json",
    "data/props/visual_bindings.generated.json",
    "scenes/wrappers/fixture_triangle.tscn",
)


def _visible_png_bytes() -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)
        )

    dark = b"\x00\x00\x00\xff" * 800
    light = b"\xff\xff\xff\xff" * 800
    row = b"\x00" + dark + light
    rows = row * 900
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1600, 900, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def _canonical_fixture(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Tuple[Path, Path]:
    """Build selected -> promotion_ready evidence through real governed code."""
    tmp_path.mkdir(parents=True, exist_ok=True)
    from tests.test_meshy_runtime_review import _bound_runtime_fixture
    from tools import meshy_blender_validate as blender_validate
    from tools import meshy_runtime_review as runtime_review
    from tools.meshy_candidate_review import bind_promotion_evidence

    project_root, task_dir, contract = _bound_runtime_fixture(tmp_path)

    def fake_reimport(glb_path: Path, expected_triangles: int) -> SimpleNamespace:
        return SimpleNamespace(
            sha256=governance.file_sha256(glb_path),
            byte_size=glb_path.stat().st_size,
            triangle_count=expected_triangles,
        )

    monkeypatch.setattr(blender_validate, "_reimport_with_blender", fake_reimport, raising=False)
    monkeypatch.setattr(
        blender_validate, "_reimport_with_blender_process", fake_reimport, raising=False
    )

    inputs, _review, _generation, root = runtime_review._load_runtime_inputs(
        project_root, None, task_dir
    )
    preview = root / runtime_review.PREVIEW_ROOT_RELATIVE / contract.asset_id
    preview.mkdir(parents=True, mode=0o700)
    png = _visible_png_bytes()
    captures = []
    for seed in runtime_review.SEEDS:
        for lighting in runtime_review.LIGHTING_MODES:
            name = runtime_review.capture_name(seed, lighting)
            (preview / name).write_bytes(png)
            (preview / name).chmod(0o600)
            captures.append(
                {
                    "seed": seed,
                    "lighting": lighting,
                    "camera_transform": {
                        "projection": "orthogonal",
                        "position": [19.742138317, 18.236871003, 19.242143317],
                        "target": [0.5, 1.399999976, 0.000005],
                        "size": 1.5,
                    },
                    "staged_visibility": {
                        "pass": True,
                        "opaque_pixels": 2304,
                        "luma_range": 1.0,
                    },
                    "output_sha256": hashlib.sha256(png).hexdigest(),
                    "pass": True,
                    "reason": "pass",
                }
            )
    runtime_document = runtime_review.build_runtime_review_document(inputs, captures)
    report = preview / "runtime-review.json"
    report.write_bytes(canonical_json_bytes(runtime_document))
    report.chmod(0o600)
    bind_promotion_evidence(project_root, task_dir)
    return project_root, task_dir


def _proposal_target() -> str:
    return "res://assets/imported/props/fixture_triangle.sidecar.json"


def _prop(project_root: Path, task_dir: Path) -> Dict[str, Any]:
    return build_prop_promotion_proposal(project_root, task_dir, target_path=_proposal_target())


def _threat(project_root: Path, task_dir: Path) -> Dict[str, Any]:
    mesh = "res://assets/_staging/meshy/{0}/{1}/cleaned.glb".format(
        task_dir.parent.name, task_dir.name
    )
    return build_threat_promotion_proposal(
        project_root, task_dir, mesh_path=mesh, archetype="fixture_triangle"
    )


def _write_canonical(path: Path, value: object, mode: int = 0o600) -> None:
    path.write_bytes(canonical_json_bytes(value))
    path.chmod(mode)


def _live_snapshot(project_root: Path) -> Dict[str, bytes]:
    return {
        relative: (project_root / relative).read_bytes()
        for relative in LIVE_RELATIVE
        if (project_root / relative).exists()
    }


def _make_live_surfaces(project_root: Path) -> Dict[str, bytes]:
    expected = {}
    for index, relative in enumerate(LIVE_RELATIVE):
        path = project_root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        payload = ("live-{0}".format(index)).encode("ascii")
        path.write_bytes(payload)
        expected[relative] = payload
    return expected


def test_positive_prop_is_derived_from_canonical_promotion_ready_evidence(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)

    proposal = _prop(project_root, task_dir)
    generation = json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))
    review = json.loads((task_dir / "review.json").read_text(encoding="utf-8"))
    expected_ai = {
        "provider": "meshy",
        "task_id": generation["task_id"],
        "model": generation["provenance"]["model"],
        "input_sha256": [generation["input_image_hashes"][key] for key in sorted(generation["input_image_hashes"])],
        "raw_output_sha256": generation["outputs"]["raw.glb"]["sha256"],
        "cleaned_output_sha256": hashlib.sha256((task_dir / "cleaned.glb").read_bytes()).hexdigest(),
        "contract_sha256": generation["contract_sha256"],
        "human_cleanup": True,
        "reviewer": review["reviewer"],
    }
    assert proposal["provenance"] == {
        "provider": "meshy",
        "license_state": generation["output_license"],
    }
    assert proposal["extensions"] == {"ai_generated": True, "ai_generation": expected_ai}
    assert validate_ai_provenance(
        {"provenance": proposal["provenance"], "extensions": proposal["extensions"]}
    ) == []

    written = write_prop_promotion_proposal(
        project_root, task_dir, target_path=_proposal_target()
    )
    leaf = task_dir / PROP_OVERLAY_NAME
    assert written == proposal
    assert leaf.read_bytes() == canonical_json_bytes(proposal)
    assert stat.S_IMODE(leaf.stat().st_mode) == 0o600


def test_positive_threat_writes_two_fixed_leaves_with_patch_last(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    live_before = _make_live_surfaces(project_root)

    proposal = write_threat_promotion_proposal(
        project_root,
        task_dir,
        mesh_path="res://assets/_staging/meshy/{0}/{1}/cleaned.glb".format(
            task_dir.parent.name, task_dir.name
        ),
        archetype="fixture_triangle",
    )
    patch = task_dir / THREAT_PATCH_NAME
    provenance = task_dir / ASSET_PROVENANCE_NAME
    assert patch.read_bytes() == canonical_json_bytes(proposal["catalog_patch"])
    assert provenance.read_bytes() == canonical_json_bytes(proposal["asset_provenance"])
    assert stat.S_IMODE(patch.stat().st_mode) == 0o600
    assert stat.S_IMODE(provenance.stat().st_mode) == 0o600
    assert proposal["catalog_patch"]["target_path"] == "data/combat/threat_visual_catalog.json"
    assert proposal["catalog_patch"]["proposal_only"] is True
    assert _live_snapshot(project_root) == live_before


def test_caller_provenance_and_publication_authority_are_not_api_inputs(tmp_path: Path) -> None:
    project_root = tmp_path / "project"
    task_dir = project_root / "assets/_staging/meshy/asset/task"
    task_dir.mkdir(parents=True)
    for function in (build_prop_promotion_proposal, write_prop_promotion_proposal):
        for kwargs in (
            {"provenance": {}},
            {"output_path": task_dir / "forged.json"},
            {"staging_root": project_root / "forged"},
        ):
            with pytest.raises(TypeError):
                function(project_root, task_dir, **kwargs)  # type: ignore[arg-type]


def test_selected_pending_failed_and_forged_ready_never_publish(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from tools.meshy_candidate_review import CHECK_FIELDS

    # A selected candidate is not promotion_ready, even when its checklist is true.
    project_root, task_dir = _canonical_fixture(tmp_path / "selected", monkeypatch)
    review_path = task_dir / "review.json"
    review = json.loads(review_path.read_text(encoding="utf-8"))
    review.update(
        {
            "state": "selected",
            "decision": "accept_for_cleanup",
            "checks": {field: True for field in CHECK_FIELDS},
            "rejection_reasons": [],
        }
    )
    _write_canonical(review_path, review)
    with pytest.raises(PromotionPacketError, match="promotion_ready"):
        _prop(project_root, task_dir)
    assert not (task_dir / PROP_OVERLAY_NAME).exists()

    # A pending review is rejected before evidence is considered.
    project_root, task_dir = _canonical_fixture(tmp_path / "pending", monkeypatch)
    review_path = task_dir / "review.json"
    review = json.loads(review_path.read_text(encoding="utf-8"))
    review.update({"state": "pending", "decision": "pending"})
    _write_canonical(review_path, review)
    with pytest.raises(PromotionPacketError):
        _prop(project_root, task_dir)
    assert not (task_dir / PROP_OVERLAY_NAME).exists()


def test_failed_generation_and_forged_ready_without_runtime_are_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from tests.test_meshy_candidate_review import _real_staged_task
    from tools.meshy_candidate_review import CHECK_FIELDS

    (tmp_path / "failed").mkdir(parents=True, exist_ok=True)
    project_root, task_dir, _contract = _real_staged_task(
        tmp_path / "failed", generation_status="FAILED"
    )
    with pytest.raises(PromotionPacketError):
        _prop(project_root, task_dir)
    assert not (task_dir / PROP_OVERLAY_NAME).exists()

    project_root, task_dir = _canonical_fixture(tmp_path / "forged", monkeypatch)
    review_path = task_dir / "review.json"
    review = json.loads(review_path.read_text(encoding="utf-8"))
    review.update(
        {
            "state": "promotion_ready",
            "decision": "promotion_ready",
            "checks": {field: True for field in CHECK_FIELDS},
            "rejection_reasons": [],
        }
    )
    _write_canonical(review_path, review)
    preview = project_root / "artifacts/validation-previews/meshy" / task_dir.parent.name
    for child in preview.iterdir():
        child.unlink()
    preview.rmdir()
    with pytest.raises(PromotionPacketError, match="runtime|preview"):
        _prop(project_root, task_dir)
    assert not (task_dir / PROP_OVERLAY_NAME).exists()


@pytest.mark.parametrize(
    ("field", "value"),
    (
        ("asset_id", "forged_asset"),
        ("task_id", "forged-task"),
        ("contract_sha256", "f" * 64),
    ),
)
def test_mismatched_generation_identity_or_contract_is_rejected(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    field: str,
    value: object,
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    generation_path = task_dir / "generation.json"
    generation = json.loads(generation_path.read_text(encoding="utf-8"))
    generation[field] = value
    _write_canonical(generation_path, generation)

    with pytest.raises(PromotionPacketError):
        _prop(project_root, task_dir)
    assert not (task_dir / PROP_OVERLAY_NAME).exists()


def test_raw_hash_mismatch_and_replaced_cleaned_glb_are_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path / "raw", monkeypatch)
    generation_path = task_dir / "generation.json"
    generation = json.loads(generation_path.read_text(encoding="utf-8"))
    generation["outputs"]["raw.glb"]["sha256"] = "e" * 64
    _write_canonical(generation_path, generation)
    with pytest.raises(PromotionPacketError):
        _prop(project_root, task_dir)
    assert not (task_dir / PROP_OVERLAY_NAME).exists()

    project_root, task_dir = _canonical_fixture(tmp_path / "cleaned", monkeypatch)
    cleaned = task_dir / "cleaned.glb"
    cleaned.write_bytes(cleaned.read_bytes() + b"stale replacement")
    with pytest.raises(PromotionPacketError, match="cleaned|Blender|runtime"):
        _prop(project_root, task_dir)
    assert not (task_dir / PROP_OVERLAY_NAME).exists()


def test_task_alias_nested_outside_and_symlink_paths_are_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    output = task_dir / PROP_OVERLAY_NAME

    with pytest.raises(PromotionPacketError, match="lexical|task"):
        _prop(project_root, task_dir / ".." / task_dir.name)
    with pytest.raises(PromotionPacketError, match="direct|task"):
        _prop(project_root, task_dir / "nested")
    outside = tmp_path / "outside"
    outside.mkdir()
    with pytest.raises(PromotionPacketError, match="staging|project root"):
        _prop(project_root, outside)

    linked = project_root / "assets/_staging/meshy/linked-task"
    linked.symlink_to(task_dir, target_is_directory=True)
    with pytest.raises(PromotionPacketError, match="symlink"):
        _prop(project_root, linked)
    assert not output.exists()


def test_exact_existing_prop_leaf_is_read_only_idempotent(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    proposal = _prop(project_root, task_dir)
    leaf = task_dir / PROP_OVERLAY_NAME
    _write_canonical(leaf, proposal)
    before = leaf.stat()
    time.sleep(0.01)

    assert write_prop_promotion_proposal(project_root, task_dir, target_path=_proposal_target()) == proposal
    after = leaf.stat()
    assert (after.st_ino, after.st_mtime_ns) == (before.st_ino, before.st_mtime_ns)


@pytest.mark.parametrize("variant", ("malformed", "noncanonical", "different", "wrong_mode", "symlink", "directory"))
def test_existing_prop_leaf_is_immutable_evidence(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, variant: str
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    proposal = _prop(project_root, task_dir)
    leaf = task_dir / PROP_OVERLAY_NAME
    victim = tmp_path / "victim.json"
    if variant == "malformed":
        leaf.write_bytes(b"{")
        leaf.chmod(0o600)
    elif variant == "noncanonical":
        leaf.write_text(json.dumps(proposal, indent=2), encoding="utf-8")
        leaf.chmod(0o600)
    elif variant == "different":
        changed = dict(proposal)
        changed["target_path"] = "res://assets/imported/props/forged.sidecar.json"
        _write_canonical(leaf, changed)
    elif variant == "wrong_mode":
        _write_canonical(leaf, proposal, mode=0o644)
    elif variant == "symlink":
        victim.write_bytes(b"victim")
        leaf.symlink_to(victim)
    else:
        leaf.mkdir()

    before = os.lstat(leaf)
    before_bytes = leaf.read_bytes() if stat.S_ISREG(before.st_mode) else None
    victim_before = victim.read_bytes() if victim.exists() else None
    with pytest.raises(PromotionPacketError):
        write_prop_promotion_proposal(project_root, task_dir, target_path=_proposal_target())
    after = os.lstat(leaf)
    assert (after.st_mode, after.st_ino, after.st_size) == (
        before.st_mode,
        before.st_ino,
        before.st_size,
    )
    if before_bytes is not None:
        assert leaf.read_bytes() == before_bytes
    if victim_before is not None:
        assert victim.read_bytes() == victim_before


def test_threat_preflights_both_leaves_before_first_write(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    proposal = _threat(project_root, task_dir)
    patch = task_dir / THREAT_PATCH_NAME
    provenance = task_dir / ASSET_PROVENANCE_NAME
    patch.write_bytes(b"not canonical json")
    patch.chmod(0o600)
    patch_before = patch.read_bytes()

    with pytest.raises(PromotionPacketError):
        write_threat_promotion_proposal(
            project_root,
            task_dir,
            mesh_path="res://assets/_staging/meshy/{0}/{1}/cleaned.glb".format(
                task_dir.parent.name, task_dir.name
            ),
            archetype="fixture_triangle",
        )
    assert not provenance.exists()
    assert patch.read_bytes() == patch_before
    assert proposal["catalog_patch"]["proposal_only"] is True


def test_threat_exact_first_leaf_retry_resumes_without_replacement(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    proposal = _threat(project_root, task_dir)
    provenance = task_dir / ASSET_PROVENANCE_NAME
    _write_canonical(provenance, proposal["asset_provenance"])
    before = provenance.stat()
    time.sleep(0.01)

    write_threat_promotion_proposal(
        project_root,
        task_dir,
        mesh_path="res://assets/_staging/meshy/{0}/{1}/cleaned.glb".format(
            task_dir.parent.name, task_dir.name
        ),
        archetype="fixture_triangle",
    )
    after = provenance.stat()
    assert (after.st_ino, after.st_mtime_ns) == (before.st_ino, before.st_mtime_ns)
    assert (task_dir / THREAT_PATCH_NAME).read_bytes() == canonical_json_bytes(
        proposal["catalog_patch"]
    )


def test_threat_existing_first_leaf_mismatch_blocks_final_leaf(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    provenance = task_dir / ASSET_PROVENANCE_NAME
    provenance.write_bytes(b"different")
    provenance.chmod(0o600)
    with pytest.raises(PromotionPacketError):
        write_threat_promotion_proposal(
            project_root,
            task_dir,
            mesh_path="res://assets/_staging/meshy/{0}/{1}/cleaned.glb".format(
                task_dir.parent.name, task_dir.name
            ),
            archetype="fixture_triangle",
        )
    assert not (task_dir / THREAT_PATCH_NAME).exists()
    assert provenance.read_bytes() == b"different"


def test_success_and_failure_leave_protected_runtime_surfaces_unchanged(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch)
    expected = _make_live_surfaces(project_root)
    before = _live_snapshot(project_root)
    write_prop_promotion_proposal(project_root, task_dir, target_path=_proposal_target())
    write_threat_promotion_proposal(
        project_root,
        task_dir,
        mesh_path="res://assets/_staging/meshy/{0}/{1}/cleaned.glb".format(
            task_dir.parent.name, task_dir.name
        ),
        archetype="fixture_triangle",
    )
    assert before == expected == _live_snapshot(project_root)

    failed = task_dir / "cleaned.glb"
    original = failed.read_bytes()
    failed.write_bytes(original + b"tampered")
    with pytest.raises(PromotionPacketError):
        write_prop_promotion_proposal(project_root, task_dir, target_path=_proposal_target())
    assert before == _live_snapshot(project_root)
