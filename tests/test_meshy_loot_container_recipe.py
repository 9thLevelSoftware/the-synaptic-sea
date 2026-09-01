from __future__ import annotations

import hashlib
import json
import os
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

from tools.meshy_asset_contract import load_contract

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_PATH = ROOT / "data/asset_generation/contracts/loot_container_derelict_v1.json"
TASK_ID = "01a05dcb-fc3b-7418-b105-2170af354088"
ASSET_ID = "loot_container_derelict_v1"


def _task_layout(tmp_path: Path) -> tuple[Path, Path, Path]:
    project_root = tmp_path / "project"
    task_dir = project_root / f"assets/_staging/meshy/{ASSET_ID}/{TASK_ID}"
    evidence_dir = tmp_path / "external-evidence" / ASSET_ID
    task_dir.mkdir(parents=True)
    evidence_dir.mkdir(parents=True)
    return project_root, task_dir, evidence_dir


def test_host_import_does_not_import_bpy() -> None:
    sys.modules.pop("bpy", None)
    from tools import meshy_loot_container_recipe as recipe

    assert "bpy" not in sys.modules
    assert recipe.ASSET_ID == ASSET_ID
    assert recipe.SELECTED_TASK_ID == TASK_ID
    assert recipe.BLENDER == "/opt/homebrew/bin/blender"


def test_paths_are_exact_and_keep_evidence_external(tmp_path: Path, monkeypatch) -> None:
    from tools import meshy_loot_container_recipe as recipe

    project_root, task_dir, _ = _task_layout(tmp_path)
    master_root = tmp_path / "trusted-master"
    trusted_evidence_root = tmp_path / "trusted-evidence"
    trusted_evidence_root.mkdir()
    evidence_dir = trusted_evidence_root / ASSET_ID
    evidence_dir.mkdir()
    monkeypatch.setattr(recipe, "TRUSTED_MASTER_ROOT", master_root)
    monkeypatch.setattr(recipe, "TRUSTED_EVIDENCE_ROOT", trusted_evidence_root)

    paths = recipe.derive_recipe_paths(project_root, task_dir, evidence_dir)

    assert paths.project_root == project_root.resolve()
    assert paths.task_dir == task_dir.resolve()
    assert paths.master_path == master_root / ASSET_ID / f"{ASSET_ID}_master.blend"
    assert paths.evidence_dir == evidence_dir.resolve()
    assert paths.scratch_glb == evidence_dir / "cleaned.preview.glb"
    assert paths.manifest_path == evidence_dir / "build_recipe_manifest.json"
    assert paths.evidence_dir.is_relative_to(trusted_evidence_root)
    assert not paths.evidence_dir.is_relative_to(project_root.resolve())


def _valid_manifest(master_path: Path) -> dict[str, Any]:
    digest = "a" * 64
    return {
        "schema_version": "1.0.0",
        "document_kind": "loot_container_master_recipe",
        "asset_id": ASSET_ID,
        "task_id": TASK_ID,
        "contract_sha256": digest,
        "raw_sha256": "b" * 64,
        "master_path": str(master_path),
        "objects": [
            "ContainerRoot",
            "ContainerBody",
            "HingePivot",
            "ContainerLid",
            "FrontHandle",
            "LatchLeft",
            "LatchRight",
            "LootVisual",
        ],
        "states": {"closed": 1, "open": 30, "looted": 60},
        "hinge": {"axis": "X", "open_degrees": 105.0},
        "dimensions_m": [0.9, 0.55, 0.65],
        "triangle_count": 3000,
        "materials": ["painted_ship_alloy", "warning_accent"],
        "uvs_present": True,
        "source_raw_preserved": True,
        "runtime_promoted": False,
        "renders": {"closed": "closed.png", "open": "open.png", "looted": "looted.png"},
    }


def test_manifest_document_accepts_exact_contract() -> None:
    from tools.meshy_loot_container_recipe import validate_manifest_document

    assert validate_manifest_document(_valid_manifest(Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend"))) == []


def test_manifest_document_rejects_missing_and_extra_top_level_fields() -> None:
    from tools.meshy_loot_container_recipe import validate_manifest_document

    document = _valid_manifest(Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend"))
    document.pop("renders")
    document["unexpected"] = True

    errors = validate_manifest_document(document)

    assert any("missing top-level field: renders" in error for error in errors)
    assert any("unknown top-level field: unexpected" in error for error in errors)


@pytest.mark.parametrize(
    "mutate",
    [
        lambda document: document.update(asset_id="other_asset"),
        lambda document: document.update(task_id="other-task"),
        lambda document: document.update(contract_sha256="A" * 64),
        lambda document: document.update(raw_sha256="not-a-hash"),
        lambda document: document.update(master_path="/repo/assets/imported/loot.glb"),
        lambda document: document.update(objects=["ContainerRoot"]),
        lambda document: document.update(states={"closed": 1, "open": 31, "looted": 60}),
        lambda document: document.update(hinge={"axis": "Y", "open_degrees": 105.0}),
        lambda document: document.update(dimensions_m=[0.92, 0.55, 0.65]),
        lambda document: document.update(triangle_count=3001),
        lambda document: document.update(materials=["warning_accent", "painted_ship_alloy"]),
        lambda document: document.update(uvs_present=False),
        lambda document: document.update(source_raw_preserved=False),
        lambda document: document.update(runtime_promoted=True),
        lambda document: document.update(renders=[]),
    ],
)
def test_manifest_document_rejects_policy_violations(mutate) -> None:
    from tools.meshy_loot_container_recipe import validate_manifest_document

    document = _valid_manifest(Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend"))
    mutate(document)

    assert validate_manifest_document(document)


def test_manifest_materials_accept_one_permitted_name_in_canonical_order() -> None:
    from tools.meshy_loot_container_recipe import validate_manifest_document

    one = _valid_manifest(Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend"))
    one["materials"] = ["painted_ship_alloy"]
    assert validate_manifest_document(one) == []

    empty = _valid_manifest(Path("/Volumes/Untitled/SynapticSeaAssets/meshy/source/loot_container_derelict_v1/loot_container_derelict_v1_master.blend"))
    empty["materials"] = []
    assert validate_manifest_document(empty)


def test_manifest_document_accepts_empty_renders_for_task_one() -> None:
    from tools.meshy_loot_container_recipe import validate_manifest_document

    document = _valid_manifest(Path(
        "/Volumes/Untitled/SynapticSeaAssets/meshy/source/"
        "loot_container_derelict_v1/loot_container_derelict_v1_master.blend"
    ))
    document["renders"] = {}

    assert validate_manifest_document(document) == []


def _governed_inputs(tmp_path: Path, monkeypatch):
    from tools import meshy_candidate_review as candidate_review
    from tools import meshy_loot_container_recipe as recipe

    project_root, task_dir, _ = _task_layout(tmp_path)
    master_root = tmp_path / "masters"
    trusted_evidence_root = tmp_path / "evidence"
    evidence_dir = trusted_evidence_root / ASSET_ID
    master_path = master_root / ASSET_ID / f"{ASSET_ID}_master.blend"
    master_path.parent.mkdir(parents=True)
    trusted_evidence_root.mkdir()
    evidence_dir.mkdir()
    master_path.write_bytes(b"canonical master")
    os.chmod(master_path, 0o600)
    raw = b"raw glb bytes"
    raw_path = task_dir / "raw.glb"
    raw_path.write_bytes(raw)
    os.chmod(raw_path, 0o600)
    contract = load_contract(CONTRACT_PATH)
    contract_path = project_root / "contract.json"
    contract_path.write_bytes(CONTRACT_PATH.read_bytes())
    review = {"asset_id": ASSET_ID, "task_id": TASK_ID, "state": "selected"}
    generation = {
        "asset_id": ASSET_ID,
        "task_id": TASK_ID,
        "status": "SUCCEEDED",
        "contract_sha256": contract.sha256,
        "outputs": {
            "raw.glb": {"sha256": hashlib.sha256(raw).hexdigest(), "byte_size": len(raw)}
        },
    }
    review_path = task_dir / "review.json"
    review_path.write_text("{}", encoding="utf-8")
    monkeypatch.setattr(recipe, "TRUSTED_MASTER_ROOT", master_root)
    monkeypatch.setattr(recipe, "TRUSTED_EVIDENCE_ROOT", trusted_evidence_root)
    monkeypatch.setattr(
        candidate_review,
        "_load_task_record",
        lambda *_args: (review_path, review, generation, project_root, project_root / f"assets/_staging/meshy/{ASSET_ID}"),
    )
    return recipe, project_root, task_dir, evidence_dir, master_path, contract


def test_resolve_recipe_paths_reuses_governed_selected_task_and_hash(tmp_path: Path, monkeypatch) -> None:
    recipe, project_root, task_dir, evidence_dir, master_path, contract = _governed_inputs(
        tmp_path, monkeypatch
    )

    loaded, paths = recipe.resolve_recipe_paths(
        project_root, project_root / "contract.json", task_dir, evidence_dir
    )

    assert loaded.sha256 == contract.sha256
    assert paths.task_dir == task_dir.resolve()
    assert paths.master_path == master_path
    assert paths.scratch_glb == evidence_dir / "cleaned.preview.glb"


def test_resolve_recipe_paths_rejects_unselected_or_failed_task(tmp_path: Path, monkeypatch) -> None:
    recipe, project_root, task_dir, evidence_dir, _master_path, _contract = _governed_inputs(
        tmp_path, monkeypatch
    )
    from tools import meshy_candidate_review as candidate_review

    review_path, review, generation, root, asset_root = candidate_review._load_task_record(
        project_root, task_dir
    )
    review["state"] = "pending"
    with pytest.raises(ValueError, match="selected"):
        recipe.resolve_recipe_paths(project_root, project_root / "contract.json", task_dir, evidence_dir)

    review["state"] = "selected"
    generation["status"] = "FAILED"
    with pytest.raises(ValueError, match="SUCCEEDED"):
        recipe.resolve_recipe_paths(project_root, project_root / "contract.json", task_dir, evidence_dir)

    assert review_path.parent == task_dir
    assert root == project_root
    assert asset_root == project_root / f"assets/_staging/meshy/{ASSET_ID}"


def test_publish_cleaned_is_idempotent_and_returns_hash(tmp_path: Path) -> None:
    from tools.meshy_loot_container_recipe import publish_cleaned

    allowed_root = tmp_path / "evidence"
    allowed_root.mkdir(mode=0o700)
    source = tmp_path / "source.glb"
    destination = allowed_root / "cleaned.glb"
    payload = b"cleaned glb"
    source.write_bytes(payload)

    first = publish_cleaned(source, destination, allowed_root)
    second = publish_cleaned(source, destination, allowed_root)

    expected = hashlib.sha256(payload).hexdigest()
    assert first == second
    assert first.path == destination
    assert first.sha256 == expected
    assert first.byte_size == len(payload)
    assert destination.read_bytes() == payload
    assert stat.S_IMODE(destination.stat().st_mode) == 0o600


def test_publish_cleaned_rejects_mismatch_without_touching_destination(tmp_path: Path) -> None:
    from tools.meshy_loot_container_recipe import publish_cleaned

    allowed_root = tmp_path / "evidence"
    allowed_root.mkdir(mode=0o700)
    source = tmp_path / "source.glb"
    destination = allowed_root / "cleaned.glb"
    source.write_bytes(b"new bytes")
    destination.write_bytes(b"old bytes")

    with pytest.raises(ValueError, match="does not match|mismatch|already exists"):
        publish_cleaned(source, destination, allowed_root)
    assert destination.read_bytes() == b"old bytes"


def test_publish_cleaned_rejects_destination_escape_and_symlink(tmp_path: Path) -> None:
    from tools.meshy_loot_container_recipe import publish_cleaned

    allowed_root = tmp_path / "evidence"
    allowed_root.mkdir(mode=0o700)
    source = tmp_path / "source.glb"
    source.write_bytes(b"source")
    outside = tmp_path / "outside.glb"
    outside.write_bytes(b"untouched")

    with pytest.raises(ValueError, match="allowed|outside"):
        publish_cleaned(source, tmp_path / "escape.glb", allowed_root)

    linked = allowed_root / "cleaned.glb"
    linked.symlink_to(outside)
    with pytest.raises(ValueError, match="symlink"):
        publish_cleaned(source, linked, allowed_root)
    assert outside.read_bytes() == b"untouched"


def test_publish_cleaned_rejects_symlinked_allowed_root(tmp_path: Path) -> None:
    from tools.meshy_loot_container_recipe import publish_cleaned

    canonical_tmp_path = tmp_path.resolve()
    real_allowed_root = canonical_tmp_path / "real-evidence"
    real_allowed_root.mkdir(mode=0o700)
    symlinked_allowed_root = canonical_tmp_path / "alias-evidence"
    symlinked_allowed_root.symlink_to(real_allowed_root, target_is_directory=True)
    source = canonical_tmp_path / "source.glb"
    source.write_bytes(b"source")

    with pytest.raises(ValueError, match="allowed root.*symlink|symlink"):
        publish_cleaned(source, real_allowed_root / "cleaned.glb", symlinked_allowed_root)


def test_build_blender_command_has_exact_argv(tmp_path: Path) -> None:
    from tools.meshy_loot_container_recipe import build_blender_command, derive_recipe_paths

    project_root, task_dir, _ = _task_layout(tmp_path)
    trusted_evidence_root = tmp_path / "evidence"
    evidence_dir = trusted_evidence_root / ASSET_ID
    evidence_dir.mkdir(parents=True)
    import tools.meshy_loot_container_recipe as recipe

    original = recipe.TRUSTED_EVIDENCE_ROOT
    recipe.TRUSTED_EVIDENCE_ROOT = trusted_evidence_root
    try:
        paths = derive_recipe_paths(project_root, task_dir, evidence_dir)
        contract_path = project_root / "contract.json"
        command = build_blender_command(paths, contract_path, "preview")
    finally:
        recipe.TRUSTED_EVIDENCE_ROOT = original

    assert command == [
        "/opt/homebrew/bin/blender",
        "--background",
        str(paths.master_path),
        "--python",
        str(paths.project_root / "tools/meshy_loot_container_recipe.py"),
        "--",
        "--project-root",
        str(paths.project_root),
        "--contract",
        str(contract_path),
        "--task-dir",
        str(paths.task_dir),
        "--evidence-dir",
        str(paths.evidence_dir),
        "--mode",
        "preview",
    ]


@pytest.mark.parametrize("mode", ["", "author", "export", "publish"])
def test_build_blender_command_rejects_unknown_mode(tmp_path: Path, mode: str) -> None:
    from tools.meshy_loot_container_recipe import build_blender_command, derive_recipe_paths
    import tools.meshy_loot_container_recipe as recipe

    project_root, task_dir, _ = _task_layout(tmp_path)
    trusted_evidence_root = tmp_path / "evidence"
    evidence_dir = trusted_evidence_root / ASSET_ID
    evidence_dir.mkdir(parents=True)
    original = recipe.TRUSTED_EVIDENCE_ROOT
    recipe.TRUSTED_EVIDENCE_ROOT = trusted_evidence_root
    try:
        paths = derive_recipe_paths(project_root, task_dir, evidence_dir)
    finally:
        recipe.TRUSTED_EVIDENCE_ROOT = original

    with pytest.raises(ValueError, match="mode"):
        build_blender_command(paths, project_root / "contract.json", mode)


def test_cli_recognizes_modes_without_importing_bpy() -> None:
    sys.modules.pop("bpy", None)
    script = ROOT / "tools/meshy_loot_container_recipe.py"
    result = subprocess.run(
        [sys.executable, str(script), "--help"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0
    assert "preview" in result.stdout
    assert "publish-cleaned" in result.stdout
    assert "bpy" not in sys.modules
