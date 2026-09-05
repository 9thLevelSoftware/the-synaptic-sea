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
from tools import meshy_promotion_packet as promotion_packet
from tools.meshy_asset_contract import canonical_json_bytes
from tools.meshy_promotion_packet import (
    ASSET_PROVENANCE_NAME,
    BIOMASS_CATALOG_PATCH_NAME,
    BIOMASS_WRAPPER_PROPOSAL_NAME,
    PROP_OVERLAY_NAME,
    THREAT_PATCH_NAME,
    PromotionPacketError,
    build_biomass_part_promotion_proposal,
    build_prop_promotion_proposal,
    build_threat_promotion_proposal,
    validate_ai_provenance,
    write_biomass_part_promotion_proposal,
    write_prop_promotion_proposal,
    write_threat_promotion_proposal,
)


LIVE_RELATIVE = (
    "assets/imported/props/fixture_triangle.sidecar.json",
    "data/combat/threat_visual_catalog.json",
    "data/props/visual_bindings.generated.json",
    "scenes/wrappers/fixture_triangle.tscn",
)


def test_biomass_part_cli_and_api_surface_is_present() -> None:
    from tools.meshy_promotion_packet import _build_parser

    parser = _build_parser()
    args = parser.parse_args(
        [
            "biomass-part",
            "--project-root",
            "/project",
            "--contract",
            "/project/contract.json",
            "--task-dir",
            "/project/assets/_staging/meshy/biomass_human_arm_v1/task-1",
            "--evidence-dir",
            "/Volumes/Untitled/SynapticSeaAssets/meshy/live-pilot/biomass_human_arm_v1/task-1",
            "--part-catalog",
            "/project/data/combat/biomass_part_catalog.json",
            "--expected-part-catalog-sha256",
            "a" * 64,
        ]
    )
    assert args.command == "biomass-part"
    assert BIOMASS_CATALOG_PATCH_NAME == "biomass_part_catalog.patch.json"
    assert BIOMASS_WRAPPER_PROPOSAL_NAME == "biomass_wrapper.proposal.json"
    assert callable(build_biomass_part_promotion_proposal)
    assert callable(write_biomass_part_promotion_proposal)


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


def _canonical_fixture(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, *, category: str = "gameplay_prop"
) -> Tuple[Path, Path]:
    """Build selected -> promotion_ready evidence through real governed code."""
    tmp_path.mkdir(parents=True, exist_ok=True)
    from tests.test_meshy_runtime_review import _bound_runtime_fixture, _solid_png_bytes
    from tools import meshy_blender_validate as blender_validate
    from tools import meshy_runtime_review as runtime_review
    from tools.meshy_candidate_review import bind_promotion_evidence

    project_root, task_dir, contract = _bound_runtime_fixture(tmp_path, category=category)

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
    staged_visibility = {
        "pass": True,
        "opaque_pixels": 2304,
        "luma_range": 1.0,
    }
    contextual_visibility = {
        "pass": True,
        "reference_pixels": 2304,
        "changed_pixels": 1152,
        "max_delta": 1.0,
    }
    monkeypatch.setattr(runtime_review, "_png_is_visible", lambda _path: True)
    monkeypatch.setattr(
        runtime_review,
        "_derive_pixel_evidence",
        lambda *_paths: (dict(staged_visibility), dict(contextual_visibility)),
    )

    inputs, _review, _generation, root = runtime_review._load_runtime_inputs(
        project_root, None, task_dir
    )
    preview = root / runtime_review.PREVIEW_ROOT_RELATIVE / contract.asset_id
    preview.mkdir(parents=True, mode=0o700)
    preview.chmod(0o700)
    final_png = _visible_png_bytes()
    staged_png = final_png
    reference_png = _solid_png_bytes(0, 0, 0)
    captures = []
    for seed in runtime_review.SEEDS:
        for lighting in runtime_review.LIGHTING_MODES:
            name = runtime_review.capture_name(seed, lighting)
            final_path = preview / name
            final_path.write_bytes(final_png)
            final_path.chmod(0o600)
            staged_path = preview / runtime_review.auxiliary_capture_name(
                seed, lighting, "staged"
            )
            staged_path.write_bytes(staged_png)
            staged_path.chmod(0o600)
            reference_path = preview / runtime_review.auxiliary_capture_name(
                seed, lighting, "reference"
            )
            reference_path.write_bytes(reference_png)
            reference_path.chmod(0o600)
            staged_visibility, contextual_visibility = runtime_review._derive_pixel_evidence(
                staged_path, reference_path, final_path
            )
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
                    "staged_visibility": staged_visibility,
                    "contextual_visibility": contextual_visibility,
                    "output_sha256": hashlib.sha256(final_png).hexdigest(),
                    "_staged_output_sha256": hashlib.sha256(staged_png).hexdigest(),
                    "_reference_output_sha256": hashlib.sha256(reference_png).hexdigest(),
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


def _biomass_fixture(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> Tuple[Path, Path, Path, Path, str]:
    """Create complete Task 11 evidence with independent report authorities mocked."""
    asset_id = "biomass_human_arm_v1"
    task_id = "task-1"
    project_root = tmp_path / "project"
    task_dir = project_root / "assets/_staging/meshy" / asset_id / task_id
    task_dir.mkdir(parents=True)
    task_dir.chmod(0o700)
    contract_source = Path(__file__).resolve().parents[1] / (
        "data/asset_generation/contracts/biomass_human_arm_v1.json"
    )
    contract_path = project_root / "contract.json"
    contract_path.write_bytes(contract_source.read_bytes())
    catalog_source = Path(__file__).resolve().parents[1] / "data/combat/biomass_part_catalog.json"
    catalog_path = project_root / "data/combat/biomass_part_catalog.json"
    catalog_path.parent.mkdir(parents=True)
    catalog_path.write_bytes(catalog_source.read_bytes())
    task_contract = task_dir / "contract.json"
    task_contract.write_bytes(contract_source.read_bytes())
    task_contract.chmod(0o600)
    contract_hash = hashlib.sha256(contract_path.read_bytes()).hexdigest()
    task_contract_hash = hashlib.sha256(task_contract.read_bytes()).hexdigest()
    raw = b"raw-glb"
    raw_path = task_dir / "raw.glb"
    raw_path.write_bytes(raw)
    raw_path.chmod(0o600)
    raw_hash = hashlib.sha256(raw).hexdigest()
    generation = {
        "asset_id": asset_id,
        "task_id": task_id,
        "status": "SUCCEEDED",
        "contract_sha256": contract_hash,
        "contract_artifact_sha256": task_contract_hash,
        "input_image_hashes": {"front": "1" * 64},
        "outputs": {"raw.glb": {"sha256": raw_hash, "byte_size": len(raw)}},
        "provenance": {"provider": "meshy", "model": "meshy-t2", "license_state": "paid-private"},
        "output_license": "paid-private",
    }
    generation_path = task_dir / "generation.json"
    _write_canonical(generation_path, generation)
    review = {"asset_id": asset_id, "task_id": task_id, "state": "promotion_ready", "reviewer": "reviewer"}
    cleaned = task_dir / "cleaned.glb"
    cleaned.write_bytes(b"cleaned-glb")
    cleaned.chmod(0o600)
    report = {
        "schema_version": "1.0.0",
        "document_kind": "meshy_blender_validation",
        "status": "PASS",
        "task_id": task_id,
        "asset_id": asset_id,
        "contract_sha256": contract_hash,
        "sha256": hashlib.sha256(cleaned.read_bytes()).hexdigest(),
        "byte_size": cleaned.stat().st_size,
        "mesh_count": 1,
        "triangle_count": 12,
        "material_names": ["biomass_visual"],
        "bounds": {"min": [-0.14, -0.14, -0.5], "max": [0.14, 0.14, 0.5], "dimensions": [0.28, 0.28, 1.0]},
        "uvs_present": True,
        "uv_evidence": [],
        "blender_reimport_passed": True,
        "master_provenance": None,
    }
    report_path = task_dir / "blender-validation.json"
    _write_canonical(report_path, report)
    evidence_root = tmp_path / "live-pilot"
    evidence_dir = evidence_root / asset_id / task_id
    evidence_dir.mkdir(parents=True)
    evidence_dir.chmod(0o700)
    master_root = tmp_path / "source"
    master_path = master_root / asset_id / f"{asset_id}_master.blend"
    master_path.parent.mkdir(parents=True)
    master_path.write_bytes(b"master")
    source = {
        "schema_version": "1.0.0",
        "document_kind": "biomass_source_raw_manifest_v1",
        "asset_id": asset_id,
        "task_id": task_id,
        "generation_sha256": hashlib.sha256(generation_path.read_bytes()).hexdigest(),
        "contract_sha256": contract_hash,
        "raw_source": {"path": str(raw_path), "sha256": raw_hash, "byte_size": len(raw)},
        "archive": {"path": str(evidence_dir / "source.raw.glb"), "sha256": raw_hash, "byte_size": len(raw)},
    }
    archive_path = evidence_dir / "source.raw.glb"
    archive_path.write_bytes(raw)
    archive_path.chmod(0o600)
    _write_canonical(evidence_dir / "source-raw-manifest.json", source)
    import tools.meshy_biomass_part_recipe as recipe_module

    catalog_document = json.loads(catalog_path.read_text(encoding="utf-8"))
    guides = [
        {"name": guide.name, "position_m": list(guide.position_m), "rotation_deg": list(guide.rotation_deg)}
        for guide in recipe_module.build_socket_guides(catalog_document["parts"][asset_id])
    ]
    preview_glb = evidence_dir / "cleaned.preview.glb"
    preview_glb.write_bytes(b"preview-glb")
    preview_glb.chmod(0o600)
    render_names = ("front.png", "side.png", "three_quarter.png", "socket_overlay.png", "contact_sheet.png")
    renders = {}
    for name in render_names:
        leaf = evidence_dir / name
        leaf.write_bytes(name.encode("ascii"))
        leaf.chmod(0o600)
        renders[name] = {"sha256": hashlib.sha256(leaf.read_bytes()).hexdigest(), "byte_size": leaf.stat().st_size, "width": 1, "height": 1}
    preview = {
        "schema_version": "1.0.0", "document_kind": "biomass_part_preview_v1", "asset_id": asset_id, "task_id": task_id,
        "contract_sha256": contract_hash, "part_catalog_sha256": hashlib.sha256(catalog_path.read_bytes()).hexdigest(),
        "generation_sha256": source["generation_sha256"], "source_raw_manifest_sha256": hashlib.sha256((evidence_dir / "source-raw-manifest.json").read_bytes()).hexdigest(),
        "raw_sha256": raw_hash, "archive_sha256": raw_hash, "master_path": str(master_path), "master_sha256": hashlib.sha256(master_path.read_bytes()).hexdigest(),
        "preview_glb": {"path": str(preview_glb), "sha256": hashlib.sha256(preview_glb.read_bytes()).hexdigest(), "byte_size": preview_glb.stat().st_size},
        "dimensions_m": [0.28, 0.28, 1.0], "low_poly_target": {"status": "met", "target_triangles": 1400, "measured_triangles": 12, "hard_max": 2500},
        "material_names": ["biomass_visual"], "material_slot_count": 1, "uvs_present": True, "socket_guides": guides,
        "socket_guides_exported": False, "source_raw_preserved": True, "runtime_promoted": False, "renders": renders,
    }
    preview_path = evidence_dir / "biomass-part-preview.json"
    _write_canonical(preview_path, preview)
    approval = {
        "schema_version": "1.0.0", "document_kind": "biomass_part_preview_approval_v1", "asset_id": asset_id, "task_id": task_id,
        "reviewer": "reviewer", "decision": "approved", "preview_manifest_sha256": hashlib.sha256(preview_path.read_bytes()).hexdigest(),
        "preview_glb_sha256": preview["preview_glb"]["sha256"], "render_hashes": {name: renders[name]["sha256"] for name in render_names},
        "contract_sha256": contract_hash, "part_catalog_sha256": preview["part_catalog_sha256"], "generation_sha256": source["generation_sha256"],
        "source_raw_manifest_sha256": preview["source_raw_manifest_sha256"], "raw_sha256": raw_hash, "archive_sha256": raw_hash,
        "master_path": str(master_path), "master_sha256": preview["master_sha256"],
    }
    approval_path = evidence_dir / "biomass-part-preview-approval.json"
    _write_canonical(approval_path, approval)
    recipe = {
        "schema_version": "1.0.0", "document_kind": "biomass_part_recipe_v1", "asset_id": asset_id, "task_id": task_id,
        "contract_sha256": contract_hash, "part_catalog_sha256": preview["part_catalog_sha256"], "generation_sha256": source["generation_sha256"],
        "source_raw_manifest_sha256": preview["source_raw_manifest_sha256"], "raw_sha256": raw_hash, "archive_sha256": raw_hash,
        "master_path": str(master_path), "master_sha256": preview["master_sha256"], "preview_approval_sha256": hashlib.sha256(approval_path.read_bytes()).hexdigest(),
        "cleaned_glb": {"path": str(cleaned), "sha256": hashlib.sha256(cleaned.read_bytes()).hexdigest(), "byte_size": cleaned.stat().st_size},
        "dimensions_m": preview["dimensions_m"], "low_poly_target": preview["low_poly_target"], "material_names": preview["material_names"],
        "material_slot_count": 1, "uvs_present": True, "socket_guides": guides, "socket_guides_exported": False,
        "source_raw_preserved": True, "runtime_promoted": False,
    }
    _write_canonical(task_dir / "biomass-part-recipe.json", recipe)
    runtime_path = project_root / "artifacts/validation-previews/meshy" / asset_id / "runtime-review.json"
    runtime_path.parent.mkdir(parents=True)
    runtime_report = {"asset_id": asset_id, "task_id": task_id, "contract_sha256": contract_hash, "cleaned_glb_sha256": recipe["cleaned_glb"]["sha256"], "blender_validation_sha256": hashlib.sha256(report_path.read_bytes()).hexdigest()}
    _write_canonical(runtime_path, runtime_report)
    monkeypatch.setattr(promotion_packet, "BIOMASS_EVIDENCE_ROOT", evidence_root)
    monkeypatch.setattr(promotion_packet, "BIOMASS_MASTER_ROOT", master_root)
    monkeypatch.setattr(promotion_packet.candidate_review, "verify_review", lambda *_args: review)
    monkeypatch.setattr(promotion_packet.candidate_review, "_load_task_record", lambda *_args: (task_dir / "review.json", review, generation, project_root.resolve(), task_dir.parent.resolve()))
    monkeypatch.setattr(promotion_packet, "_hash_file", lambda path, label: hashlib.sha256(Path(path).read_bytes()).hexdigest())
    monkeypatch.setattr(promotion_packet, "_biomass_canonical_document", lambda path, label: (json.loads(Path(path).read_text(encoding="utf-8")), Path(path).read_bytes()))
    monkeypatch.setattr("tools.meshy_blender_validate._validate_report_record", lambda _report: None)
    monkeypatch.setattr("tools.meshy_blender_validate.verify_validation_report", lambda *_args, **_kwargs: report)
    monkeypatch.setattr("tools.meshy_runtime_review.verify_evidence_chain", lambda *_args: runtime_report)
    return project_root, task_dir, contract_path, catalog_path, hashlib.sha256(catalog_path.read_bytes()).hexdigest()


def test_biomass_part_proposal_is_three_immutable_review_only_leaves(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir, contract_path, catalog_path, catalog_hash = _biomass_fixture(tmp_path, monkeypatch)
    proposal = build_biomass_part_promotion_proposal(
        project_root, contract_path, task_dir,
        tmp_path / "live-pilot/biomass_human_arm_v1/task-1", catalog_path, catalog_hash
    )
    assert set(proposal) == {BIOMASS_CATALOG_PATCH_NAME, BIOMASS_WRAPPER_PROPOSAL_NAME, ASSET_PROVENANCE_NAME}
    wrapper = proposal[BIOMASS_WRAPPER_PROPOSAL_NAME]
    assert wrapper["import_target"] == "res://assets/imported/threats/biomass/biomass_human_arm_v1.glb"
    assert wrapper["wrapper_target"] == "res://scenes/wrappers/biomass/biomass_human_arm_v1.tscn"
    assert "collision_shapes" not in json.dumps(wrapper)
    assert proposal[BIOMASS_CATALOG_PATCH_NAME]["catalog_entry"]["wrapper_scene_path"] == wrapper["wrapper_target"]
    assert proposal[ASSET_PROVENANCE_NAME]["document_kind"] == "asset_provenance"
    assert set(proposal[ASSET_PROVENANCE_NAME]) == {
        "asset_id",
        "document_kind",
        "extensions",
        "proposal_only",
        "provenance",
        "task_id",
    }
    assert not (task_dir / BIOMASS_CATALOG_PATCH_NAME).exists()
    written = write_biomass_part_promotion_proposal(
        project_root, contract_path, task_dir,
        tmp_path / "live-pilot/biomass_human_arm_v1/task-1", catalog_path, catalog_hash
    )
    assert written == proposal
    for name in (BIOMASS_CATALOG_PATCH_NAME, BIOMASS_WRAPPER_PROPOSAL_NAME, ASSET_PROVENANCE_NAME):
        leaf = task_dir / name
        assert leaf.read_bytes() == canonical_json_bytes(proposal[name])
        assert stat.S_IMODE(leaf.stat().st_mode) == 0o600


def test_biomass_part_rejects_forged_approval_catalog_binding(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir, contract_path, catalog_path, catalog_hash = _biomass_fixture(
        tmp_path, monkeypatch
    )
    approval_path = tmp_path / "live-pilot/biomass_human_arm_v1/task-1/biomass-part-preview-approval.json"
    approval = json.loads(approval_path.read_text(encoding="utf-8"))
    approval["part_catalog_sha256"] = "f" * 64
    _write_canonical(approval_path, approval)
    recipe_path = task_dir / "biomass-part-recipe.json"
    recipe = json.loads(recipe_path.read_text(encoding="utf-8"))
    recipe["preview_approval_sha256"] = hashlib.sha256(approval_path.read_bytes()).hexdigest()
    _write_canonical(recipe_path, recipe)

    with pytest.raises(PromotionPacketError, match="approval|catalog"):
        build_biomass_part_promotion_proposal(
            project_root,
            contract_path,
            task_dir,
            tmp_path / "live-pilot/biomass_human_arm_v1/task-1",
            catalog_path,
            catalog_hash,
        )


@pytest.mark.parametrize("fail_after", (1, 2))
def test_biomass_part_publication_compensates_after_each_partial_leaf(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, fail_after: int
) -> None:
    project_root, task_dir, contract_path, catalog_path, catalog_hash = _biomass_fixture(
        tmp_path, monkeypatch
    )

    def fail_after_leaf(_path: Path, index: int) -> None:
        if index == fail_after:
            raise RuntimeError("injected biomass publication failure")

    monkeypatch.setattr(promotion_packet, "_BIOMASS_AFTER_LEAF_HOOK", fail_after_leaf)
    with pytest.raises(PromotionPacketError, match="publication failed"):
        write_biomass_part_promotion_proposal(
            project_root,
            contract_path,
            task_dir,
            tmp_path / "live-pilot/biomass_human_arm_v1/task-1",
            catalog_path,
            catalog_hash,
        )
    assert not any(
        (task_dir / name).exists()
        for name in (
            BIOMASS_CATALOG_PATCH_NAME,
            BIOMASS_WRAPPER_PROPOSAL_NAME,
            ASSET_PROVENANCE_NAME,
        )
    )


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


@pytest.mark.parametrize(
    "inputs",
    (
        [["not-a-hash"]],
        [{"not-a-hash": True}],
    ),
)
def test_unhashable_input_entries_return_deterministic_diagnostics(inputs: list[object]) -> None:
    value = {
        "provenance": {"provider": "meshy", "license_state": "paid-private"},
        "extensions": {
            "ai_generated": True,
            "ai_generation": {
                "provider": "meshy",
                "task_id": "task-1",
                "model": "model-1",
                "input_sha256": inputs,
                "raw_output_sha256": "0" * 64,
                "cleaned_output_sha256": "1" * 64,
                "contract_sha256": "2" * 64,
                "human_cleanup": True,
                "reviewer": "reviewer-1",
            },
        },
    }

    diagnostics = validate_ai_provenance(value)

    assert diagnostics == validate_ai_provenance(value)
    assert diagnostics == sorted(diagnostics)
    assert "extensions.ai_generation.input_sha256 must contain hashes" in diagnostics
    assert (
        "extensions.ai_generation.input_sha256[0] must be 64 lowercase hexadecimal characters"
        in diagnostics
    )


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
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch, category="threat_character")
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
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch, category="threat_character")
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
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch, category="threat_character")
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
    project_root, task_dir = _canonical_fixture(tmp_path, monkeypatch, category="threat_character")
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


def test_packet_type_must_match_task_contract_category(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path / "prop", monkeypatch)
    with pytest.raises(PromotionPacketError, match="incompatible with contract category gameplay_prop"):
        _threat(project_root, task_dir)

    project_root, task_dir = _canonical_fixture(
        tmp_path / "threat", monkeypatch, category="threat_character"
    )
    with pytest.raises(PromotionPacketError, match="incompatible with contract category threat_character"):
        _prop(project_root, task_dir)


def test_success_and_failure_leave_protected_runtime_surfaces_unchanged(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir = _canonical_fixture(tmp_path / "prop", monkeypatch)
    expected = _make_live_surfaces(project_root)
    before = _live_snapshot(project_root)
    write_prop_promotion_proposal(project_root, task_dir, target_path=_proposal_target())
    assert before == expected == _live_snapshot(project_root)

    threat_root, threat_dir = _canonical_fixture(
        tmp_path / "threat", monkeypatch, category="threat_character"
    )
    threat_expected = _make_live_surfaces(threat_root)
    threat_before = _live_snapshot(threat_root)
    write_threat_promotion_proposal(
        threat_root,
        threat_dir,
        mesh_path="res://assets/_staging/meshy/{0}/{1}/cleaned.glb".format(
            threat_dir.parent.name, threat_dir.name
        ),
        archetype="fixture_triangle",
    )
    assert threat_before == threat_expected == _live_snapshot(threat_root)

    failed = task_dir / "cleaned.glb"
    original = failed.read_bytes()
    failed.write_bytes(original + b"tampered")
    with pytest.raises(PromotionPacketError):
        write_prop_promotion_proposal(project_root, task_dir, target_path=_proposal_target())
    assert before == _live_snapshot(project_root)
