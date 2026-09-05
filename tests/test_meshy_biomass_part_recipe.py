from __future__ import annotations

import copy
import hashlib
import json
import os
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "data/combat/biomass_part_catalog.json"
CONTRACT_PATH = ROOT / "data/asset_generation/contracts/biomass_human_arm_v1.json"
ASSET_ID = "biomass_human_arm_v1"


def _catalog_hash() -> str:
    return hashlib.sha256(CATALOG_PATH.read_bytes()).hexdigest()


def _manifest_document(kind: str) -> dict[str, Any]:
    digest = "a" * 64
    artifact = {"path": "/tmp/artifact.glb", "sha256": "b" * 64, "byte_size": 12}
    guide = {"name": "socket_root_0", "position_m": [0.0, 0.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0]}
    limits = {"status": "met", "target_triangles": 1400, "measured_triangles": 12, "hard_max": 2500}
    renders = {
        leaf: {"sha256": digest, "byte_size": 10, "width": 640, "height": 640}
        for leaf in ("front.png", "side.png", "three_quarter.png", "socket_overlay.png", "contact_sheet.png")
    }
    if kind == "source":
        return {
            "schema_version": "1.0.0",
            "document_kind": "biomass_source_raw_manifest_v1",
            "asset_id": ASSET_ID,
            "task_id": "task-1",
            "generation_sha256": digest,
            "contract_sha256": digest,
            "raw_source": artifact,
            "archive": artifact,
        }
    if kind == "preview":
        return {
            "schema_version": "1.0.0",
            "document_kind": "biomass_part_preview_v1",
            "asset_id": ASSET_ID,
            "task_id": "task-1",
            "contract_sha256": digest,
            "part_catalog_sha256": digest,
            "generation_sha256": digest,
            "source_raw_manifest_sha256": digest,
            "raw_sha256": digest,
            "archive_sha256": digest,
            "master_path": "/Volumes/Untitled/SynapticSeaAssets/meshy/source/biomass_human_arm_v1/biomass_human_arm_v1_master.blend",
            "master_sha256": digest,
            "preview_glb": artifact,
            "dimensions_m": [0.28, 0.28, 1.0],
            "low_poly_target": limits,
            "material_names": ["biomass_visual"],
            "material_slot_count": 1,
            "uvs_present": True,
            "socket_guides": [guide],
            "socket_guides_exported": False,
            "source_raw_preserved": True,
            "runtime_promoted": False,
            "renders": renders,
        }
    if kind == "approval":
        return {
            "schema_version": "1.0.0",
            "document_kind": "biomass_part_preview_approval_v1",
            "asset_id": ASSET_ID,
            "task_id": "task-1",
            "reviewer": "reviewer",
            "decision": "approved",
            "preview_manifest_sha256": digest,
            "preview_glb_sha256": "b" * 64,
            "render_hashes": {leaf: digest for leaf in renders},
            "contract_sha256": digest,
            "part_catalog_sha256": digest,
            "generation_sha256": digest,
            "source_raw_manifest_sha256": digest,
            "raw_sha256": digest,
            "archive_sha256": digest,
            "master_path": "/Volumes/Untitled/SynapticSeaAssets/meshy/source/biomass_human_arm_v1/biomass_human_arm_v1_master.blend",
            "master_sha256": digest,
        }
    return {
        "schema_version": "1.0.0",
        "document_kind": "biomass_part_recipe_v1",
        "asset_id": ASSET_ID,
        "task_id": "task-1",
        "contract_sha256": digest,
        "part_catalog_sha256": digest,
        "generation_sha256": digest,
        "source_raw_manifest_sha256": digest,
        "raw_sha256": digest,
        "archive_sha256": digest,
        "master_path": "/Volumes/Untitled/SynapticSeaAssets/meshy/source/biomass_human_arm_v1/biomass_human_arm_v1_master.blend",
        "master_sha256": digest,
        "preview_approval_sha256": digest,
        "cleaned_glb": artifact,
        "dimensions_m": [0.28, 0.28, 1.0],
        "low_poly_target": limits,
        "material_names": ["biomass_visual"],
        "material_slot_count": 1,
        "uvs_present": True,
        "socket_guides": [guide],
        "socket_guides_exported": False,
        "source_raw_preserved": True,
        "runtime_promoted": False,
    }


def test_host_import_never_loads_bpy() -> None:
    sys.modules.pop("bpy", None)
    from tools import meshy_biomass_part_recipe as recipe

    assert "bpy" not in sys.modules
    assert recipe.BLENDER == "/opt/homebrew/bin/blender"
    assert recipe.ALLOWED_MODES == (
        "archive-raw",
        "rehydrate-raw",
        "preview",
        "approve-preview",
        "publish-cleaned",
    )


def test_triangle_limits_supports_biomass_object_budget() -> None:
    from tools.meshy_biomass_part_recipe import triangle_limits
    from tools.meshy_asset_contract import load_contract

    assert triangle_limits(load_contract(CONTRACT_PATH)) == (1400, 2500)


def test_build_socket_guides_is_sorted_and_defensive() -> None:
    from tools.meshy_biomass_part_recipe import build_socket_guides

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    entry = catalog["parts"][ASSET_ID]
    guides = build_socket_guides(entry)
    assert [guide.name for guide in guides] == sorted(socket["name"] for socket in entry["sockets"])
    root_guide = next(guide for guide in guides if guide.name == "socket_root_0")
    assert root_guide.position_m == (0.0, 0.0, 0.0)
    entry["sockets"][0]["position_m"][0] = 99
    assert root_guide.position_m == (0.0, 0.0, 0.0)


def test_build_socket_guides_rejects_duplicate_socket_names() -> None:
    from tools.meshy_biomass_part_recipe import BiomassRecipeError, build_socket_guides

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    entry = copy.deepcopy(catalog["parts"][ASSET_ID])
    entry["sockets"].append(copy.deepcopy(entry["sockets"][0]))
    with pytest.raises(BiomassRecipeError, match="duplicate"):
        build_socket_guides(entry)


@pytest.mark.parametrize("loader_name,kind", [
    ("load_source_raw_manifest", "source"),
    ("load_preview_manifest", "preview"),
    ("load_preview_approval", "approval"),
    ("load_recipe_manifest", "recipe"),
])
def test_manifest_loaders_accept_exact_closed_documents(tmp_path: Path, loader_name: str, kind: str) -> None:
    from tools import meshy_biomass_part_recipe as recipe

    path = tmp_path / "document.json"
    path.write_bytes(recipe.canonical_json_bytes(_manifest_document(kind)))
    loaded = getattr(recipe, loader_name)(path)
    assert loaded == _manifest_document(kind)
    loaded["asset_id"] = "mutated"
    assert getattr(recipe, loader_name)(path)["asset_id"] == ASSET_ID


@pytest.mark.parametrize("loader_name,kind", [
    ("load_source_raw_manifest", "source"),
    ("load_preview_manifest", "preview"),
    ("load_preview_approval", "approval"),
    ("load_recipe_manifest", "recipe"),
])
def test_manifest_loaders_reject_malformed_json_boundaries(tmp_path: Path, loader_name: str, kind: str) -> None:
    from tools import meshy_biomass_part_recipe as recipe

    path = tmp_path / "document.json"
    valid = recipe.canonical_json_bytes(_manifest_document(kind))
    cases = [
        b"{",
        b"\xff",
        valid.replace(b"\"asset_id\":\"biomass_human_arm_v1\"", b"\"asset_id\":\"biomass_human_arm_v1\",\"asset_id\":\"duplicate\""),
        valid.replace(b"\"schema_version\":\"1.0.0\"", b"\"schema_version\":1.0"),
        recipe.canonical_json_bytes({**_manifest_document(kind), "unknown": True}),
    ]
    for payload in cases:
        path.write_bytes(payload)
        with pytest.raises((ValueError, OSError, RecursionError)):
            getattr(recipe, loader_name)(path)


def test_manifest_loaders_reject_noncanonical_and_deep_documents(tmp_path: Path) -> None:
    from tools import meshy_biomass_part_recipe as recipe

    path = tmp_path / "document.json"
    document = _manifest_document("source")
    path.write_text(json.dumps(document, indent=2), encoding="utf-8")
    with pytest.raises(ValueError, match="canonical"):
        recipe.load_source_raw_manifest(path)
    deep: Any = "leaf"
    for _ in range(recipe.MAX_JSON_DEPTH + 2):
        deep = [deep]
    path.write_text(json.dumps(deep), encoding="utf-8")
    with pytest.raises(ValueError, match="depth"):
        recipe.load_source_raw_manifest(path)


def test_public_resolver_has_no_root_override_and_rejects_disposable_roots(tmp_path: Path) -> None:
    from tools import meshy_biomass_part_recipe as recipe

    project = tmp_path / "project"
    task = project / "assets/_staging/meshy" / ASSET_ID / "task-1"
    evidence = tmp_path / "evidence" / ASSET_ID / "task-1"
    task.mkdir(parents=True)
    evidence.mkdir(parents=True)
    contract = project / "contract.json"
    contract.write_bytes(CONTRACT_PATH.read_bytes())
    catalog = project / "catalog.json"
    catalog.write_bytes(CATALOG_PATH.read_bytes())
    with pytest.raises(ValueError):
        recipe.resolve_recipe_paths(project, contract, catalog, _catalog_hash(), task, evidence, "archive-raw")
    assert "trusted_roots" not in recipe.resolve_recipe_paths.__code__.co_varnames


def test_atomic_archive_and_rehydrate_are_offline_and_idempotent(tmp_path: Path, monkeypatch) -> None:
    from tools import meshy_biomass_part_recipe as recipe

    project = tmp_path / "project"
    task = project / "assets/_staging/meshy" / ASSET_ID / "task-1"
    evidence = tmp_path / "external" / ASSET_ID / "task-1"
    task.mkdir(parents=True)
    evidence.mkdir(parents=True)
    os.chmod(evidence, 0o700)
    raw = b"synthetic raw glb"
    (task / "raw.glb").write_bytes(raw)
    os.chmod(task, 0o700)
    os.chmod(task / "raw.glb", 0o600)
    contract = project / "contract.json"
    contract.write_bytes(CONTRACT_PATH.read_bytes())
    catalog = project / "catalog.json"
    catalog.write_bytes(CATALOG_PATH.read_bytes())
    generation = {
        "asset_id": ASSET_ID,
        "task_id": "task-1",
        "status": "SUCCEEDED",
        "contract_sha256": hashlib.sha256(CONTRACT_PATH.read_bytes()).hexdigest(),
        "outputs": {"raw.glb": {"sha256": hashlib.sha256(raw).hexdigest(), "byte_size": len(raw)}},
    }
    review = {"asset_id": ASSET_ID, "task_id": "task-1", "state": "selected"}
    review_path = task / "review.json"
    generation_path = task / "generation.json"
    review_path.write_bytes(b"{}")
    generation_path.write_bytes(recipe.canonical_json_bytes(generation))
    roots = recipe.RecipeRoots(tmp_path / "masters", tmp_path / "external")
    monkeypatch.setattr(recipe.candidate_review, "_load_task_record", lambda *_: (review_path, review, generation, project.resolve(), (project / "assets/_staging/meshy" / ASSET_ID).resolve()))
    _resolved_contract, _entry, paths = recipe._resolve_recipe_paths(project, contract, catalog, _catalog_hash(), task, evidence, "archive-raw", trusted_roots=roots)
    monkeypatch.setattr(recipe, "_AFTER_LEAF_HOOK", lambda *_args: (_ for _ in ()).throw(RuntimeError("injected publication failure")))
    with pytest.raises(recipe.BiomassRecipeError, match="publication failed"):
        recipe.run_blender_recipe(paths, _resolved_contract, json.loads(CATALOG_PATH.read_text())["parts"][ASSET_ID], "archive-raw")
    assert not (evidence / "source.raw.glb").exists()
    assert not (evidence / "source-raw-manifest.json").exists()
    monkeypatch.setattr(recipe, "_AFTER_LEAF_HOOK", None)
    first = recipe.run_blender_recipe(paths, _resolved_contract, json.loads(CATALOG_PATH.read_text())["parts"][ASSET_ID], "archive-raw")
    second = recipe.run_blender_recipe(paths, _resolved_contract, json.loads(CATALOG_PATH.read_text())["parts"][ASSET_ID], "archive-raw")
    assert first["archive"]["sha256"] == second["archive"]["sha256"]
    assert (evidence / "source.raw.glb").read_bytes() == raw
    assert stat.S_IMODE((evidence / "source.raw.glb").stat().st_mode) == 0o600
    (task / "raw.glb").unlink()
    hydrated = recipe.run_blender_recipe(paths, recipe.load_contract(contract), json.loads(CATALOG_PATH.read_text())["parts"][ASSET_ID], "rehydrate-raw")
    assert hydrated["raw_source"]["sha256"] == hashlib.sha256(raw).hexdigest()
    assert (task / "raw.glb").read_bytes() == raw


@pytest.mark.skipif(not Path("/opt/homebrew/bin/blender").exists(), reason="Blender executable is absent")
def test_synthetic_blender_recipe_runs_bounded_visual_only_pipeline(tmp_path: Path, monkeypatch) -> None:
    from tools import meshy_biomass_part_recipe as recipe
    from tools.meshy_blender_validate import validate_cleaned_glb
    from tools.meshy_asset_contract import load_contract

    project = tmp_path / "project"
    task = project / "assets/_staging/meshy" / ASSET_ID / "task-1"
    evidence_root = tmp_path / "external"
    evidence = evidence_root / ASSET_ID / "task-1"
    master_root = tmp_path / "masters"
    master = master_root / ASSET_ID / f"{ASSET_ID}_master.blend"
    task.mkdir(parents=True)
    evidence.mkdir(parents=True)
    master.parent.mkdir(parents=True)
    for directory in (task, evidence):
        os.chmod(directory, 0o700)
    contract = project / "contract.json"
    contract.write_bytes(CONTRACT_PATH.read_bytes())
    catalog = project / "catalog.json"
    catalog.write_bytes(CATALOG_PATH.read_bytes())
    raw = b"synthetic raw glb bytes"
    (task / "raw.glb").write_bytes(raw)
    os.chmod(task / "raw.glb", 0o600)
    generation = {
        "asset_id": ASSET_ID,
        "task_id": "task-1",
        "status": "SUCCEEDED",
        "contract_sha256": hashlib.sha256(contract.read_bytes()).hexdigest(),
        "outputs": {"raw.glb": {"sha256": hashlib.sha256(raw).hexdigest(), "byte_size": len(raw)}},
    }
    generation_path = task / "generation.json"
    generation_path.write_bytes(recipe.canonical_json_bytes(generation))
    os.chmod(generation_path, 0o600)
    review_path = task / "review.json"
    review_path.write_bytes(b"{}")
    os.chmod(review_path, 0o600)
    expression = (
        "import bpy; bpy.ops.mesh.primitive_cube_add(size=2, location=(0,0,0)); "
        "bpy.context.object.name='Candidate'; "
        f"bpy.ops.wm.save_as_mainfile(filepath={str(master)!r})"
    )
    blender = subprocess.run(
        [recipe.BLENDER, "--background", "--python-expr", expression],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )
    assert blender.returncode == 0, blender.stderr[-4000:]
    assert master.is_file()
    review = {"asset_id": ASSET_ID, "task_id": "task-1", "state": "selected"}
    original_loader = recipe.candidate_review._load_task_record
    monkeypatch.setattr(
        recipe.candidate_review,
        "_load_task_record",
        lambda *_args: (review_path, review, generation, project.resolve(), (project / "assets/_staging/meshy" / ASSET_ID).resolve()),
    )
    roots = recipe.RecipeRoots(master_root, evidence_root)
    catalog_hash = _catalog_hash()
    try:
        resolved_contract, entry, paths = recipe._resolve_recipe_paths(
            project, contract, catalog, catalog_hash, task, evidence, "archive-raw", trusted_roots=roots
        )
        recipe.run_blender_recipe(paths, resolved_contract, entry, "archive-raw")
        resolved_contract, entry, paths = recipe._resolve_recipe_paths(
            project, contract, catalog, catalog_hash, task, evidence, "preview", trusted_roots=roots
        )
        preview = recipe.run_blender_recipe(paths, resolved_contract, entry, "preview")
        assert preview["socket_guides_exported"] is False
        assert set(RENDER_LEAVES := recipe.RENDER_LEAVES) == {
            "front.png", "side.png", "three_quarter.png", "socket_overlay.png", "contact_sheet.png"
        }
        assert (evidence / "cleaned.preview.glb").read_bytes()[:4] == b"glTF"
        resolved_contract, entry, paths = recipe._resolve_recipe_paths(
            project, contract, catalog, catalog_hash, task, evidence, "approve-preview", trusted_roots=roots
        )
        approved = recipe.run_blender_recipe(
            recipe.replace(paths, reviewer="integration-reviewer"), resolved_contract, entry, "approve-preview"
        )
        assert approved["decision"] == "approved"
        resolved_contract, entry, paths = recipe._resolve_recipe_paths(
            project, contract, catalog, catalog_hash, task, evidence, "publish-cleaned", trusted_roots=roots
        )
        recipe.run_blender_recipe(paths, resolved_contract, entry, "publish-cleaned")
        validation_contract = load_contract(contract)
        validation_document = validation_contract.document_copy()
        validation_document["animation"]["rigging_target"] = "non_humanoid"
        validation_snapshot = recipe.canonical_json_bytes(validation_document)
        validation_contract = recipe.AssetContract(
            validation_contract.path,
            hashlib.sha256(validation_snapshot).hexdigest(),
            validation_snapshot,
        )
        report = validate_cleaned_glb(task / "cleaned.glb", validation_contract, task_id="task-1")
        assert report["status"] == "PASS"
        assert report["master_provenance"] is None
    finally:
        monkeypatch.setattr(recipe.candidate_review, "_load_task_record", original_loader)
