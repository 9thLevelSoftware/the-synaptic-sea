from __future__ import annotations

import json
from pathlib import Path

import pytest

from tools.meshy_asset_contract import canonical_json_bytes
from tools.meshy_promotion_packet import (
    PromotionPacketError,
    build_prop_promotion_proposal,
    build_threat_promotion_proposal,
    write_prop_promotion_proposal,
    write_threat_promotion_proposal,
)


ASSET_ID = "stalker_v1"
TASK_ID = "018-test-promotion"
HASH = "a" * 64


def _provenance() -> dict:
    return {
        "provenance": {
            "license_state": "paid-private",
            "source_platform": "meshy",
        },
        "extensions": {
            "ai_generation": {
                "provider": "meshy",
                "task_id": TASK_ID,
                "model": "meshy-t2",
                "input_sha256": [HASH],
                "raw_output_sha256": "b" * 64,
                "cleaned_output_sha256": "c" * 64,
                "contract_sha256": "d" * 64,
                "human_cleanup": True,
                "reviewer": "operator",
            }
        },
    }


def _project_and_task(tmp_path: Path) -> tuple[Path, Path]:
    project = tmp_path / "project"
    task = project / "assets/_staging/meshy" / ASSET_ID / TASK_ID
    task.mkdir(parents=True)
    return project, task


def _build_prop(project: Path, task: Path, **kwargs: object) -> dict:
    values = {"provenance": _provenance(), "target_path": "res://assets/imported/props/stalker_v1.glb"}
    values.update(kwargs)
    return build_prop_promotion_proposal(project, task, **values)


def test_proposal_includes_correct_provenance(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    proposal = _build_prop(project, task)

    assert proposal["provenance"] == {
        "license_state": "paid-private",
        "source_platform": "meshy",
    }


def test_proposal_includes_ai_generation_extension(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    proposal = _build_prop(project, task)

    assert proposal["extensions"]["ai_generation"] == {
        "provider": "meshy",
        "task_id": TASK_ID,
        "model": "meshy-t2",
        "input_sha256": [HASH],
        "raw_output_sha256": "b" * 64,
        "cleaned_output_sha256": "c" * 64,
        "contract_sha256": "d" * 64,
        "human_cleanup": True,
        "reviewer": "operator",
    }


def test_proposal_rejects_missing_rights(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    provenance = _provenance()
    provenance["provenance"].pop("license_state")

    with pytest.raises(PromotionPacketError, match="license_state"):
        build_prop_promotion_proposal(
            project,
            task,
            provenance=provenance,
            target_path="res://assets/imported/props/stalker_v1.glb",
        )


def test_proposal_rejects_missing_hashes(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    provenance = _provenance()
    provenance["extensions"]["ai_generation"].pop("raw_output_sha256")

    with pytest.raises(PromotionPacketError, match="hash"):
        build_prop_promotion_proposal(
            project,
            task,
            provenance=provenance,
            target_path="res://assets/imported/props/stalker_v1.glb",
        )


def test_proposal_rejects_human_cleanup_false(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    provenance = _provenance()
    provenance["extensions"]["ai_generation"]["human_cleanup"] = False

    with pytest.raises(PromotionPacketError, match="human_cleanup"):
        build_prop_promotion_proposal(
            project,
            task,
            provenance=provenance,
            target_path="res://assets/imported/props/stalker_v1.glb",
        )


def test_proposal_rejects_self_authored(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    provenance = _provenance()
    provenance["provenance"]["source_platform"] = "self-authored"

    with pytest.raises(PromotionPacketError, match="source_platform"):
        build_prop_promotion_proposal(
            project,
            task,
            provenance=provenance,
            target_path="res://assets/imported/props/stalker_v1.glb",
        )


def test_proposal_rejects_signed_urls(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    provenance = _provenance()
    provenance["extensions"]["ai_generation"]["download_url"] = (
        "https://cdn.example/cleaned.glb?X-Amz-Signature=secret"
    )

    with pytest.raises(PromotionPacketError, match="signed URL"):
        build_prop_promotion_proposal(
            project,
            task,
            provenance=provenance,
            target_path="res://assets/imported/props/stalker_v1.glb",
        )


def test_proposal_rejects_api_keys(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    provenance = _provenance()
    provenance["extensions"]["ai_generation"]["api_key"] = "meshy-secret"

    with pytest.raises(PromotionPacketError, match="API key"):
        build_prop_promotion_proposal(
            project,
            task,
            provenance=provenance,
            target_path="res://assets/imported/props/stalker_v1.glb",
        )


def test_proposal_rejects_output_outside_staging(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)

    with pytest.raises(PromotionPacketError, match="staging"):
        build_prop_promotion_proposal(
            project,
            task,
            provenance=_provenance(),
            target_path="res://assets/imported/props/stalker_v1.glb",
            output_path=project / "assets/imported/props/stalker_v1.sidecar-overlay.json",
        )


def test_proposal_never_writes_live_paths(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    live_files = {
        "assets/imported/props/stalker_v1.glb": b"live glb",
        "data/combat/threat_visual_catalog.json": b"live catalog",
        "data/props/visual_bindings.generated.json": b"live index",
        "scenes/wrappers/stalker_v1.tscn": b"live wrapper",
    }
    for relative, contents in live_files.items():
        path = project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(contents)

    write_prop_promotion_proposal(
        project,
        task,
        provenance=_provenance(),
        target_path="res://assets/imported/props/stalker_v1.sidecar.json",
    )
    write_threat_promotion_proposal(
        project,
        task,
        provenance=_provenance(),
        mesh_path="res://assets/_staging/meshy/stalker_v1/018-test-promotion/cleaned.glb",
    )

    assert {relative: (project / relative).read_bytes() for relative in live_files} == live_files


def test_proposal_output_is_canonical_json(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    proposal = write_prop_promotion_proposal(
        project,
        task,
        provenance=_provenance(),
        target_path="res://assets/imported/props/stalker_v1.sidecar.json",
    )
    output = task / "sidecar-overlay.json"

    assert output.read_bytes() == canonical_json_bytes(proposal)
    assert json.loads(output.read_text(encoding="utf-8"))["proposal_only"] is True


def test_threat_proposal_contains_catalog_patch_and_generic_provenance(tmp_path: Path) -> None:
    project, task = _project_and_task(tmp_path)
    proposal = write_threat_promotion_proposal(
        project,
        task,
        provenance=_provenance(),
        mesh_path="res://assets/_staging/meshy/stalker_v1/018-test-promotion/cleaned.glb",
    )

    patch_path = task / "threat_visual_catalog.patch.json"
    provenance_path = task / "asset-provenance.json"
    assert patch_path.read_bytes() == canonical_json_bytes(proposal["catalog_patch"])
    assert provenance_path.read_bytes() == canonical_json_bytes(proposal["asset_provenance"])
    assert proposal["catalog_patch"]["target_path"] == "data/combat/threat_visual_catalog.json"
    assert proposal["asset_provenance"]["provenance"] == _provenance()["provenance"]
