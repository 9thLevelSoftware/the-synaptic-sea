from __future__ import annotations

import copy
import hashlib
import json
import os
import shutil
from pathlib import Path
from typing import Any, Dict

import pytest

from tools import meshy_stage as stage_module
from tools.meshy_asset_contract import canonical_json_bytes, load_contract


ROOT = Path(__file__).resolve().parents[1]
ASSET_ID = "loot_container_derelict_v1"
CONTRACT_RELATIVE = Path("data/asset_generation/contracts") / f"{ASSET_ID}.json"
PRICING_RELATIVE = Path("data/asset_generation/meshy_pricing_v1.json")
FIXTURE_ASSET_ROOT = ROOT / "assets/_staging/meshy" / ASSET_ID
JOURNAL_NAME = "9e04213bc806421d8e64c9c9c23f26d3.json"
PLAN_RELATIVE = Path("assets/_staging/meshy/_plans") / f"{ASSET_ID}.json"
JOURNAL_RELATIVE = Path("assets/_staging/meshy") / ASSET_ID / "_batches" / JOURNAL_NAME


class NoProviderClient:
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        raise AssertionError("offline evidence operation attempted to construct a provider client")


def _copy_fixture_project(tmp_path: Path) -> Path:
    project_root = tmp_path / "project"
    (project_root / CONTRACT_RELATIVE.parent).mkdir(parents=True)
    (project_root / PRICING_RELATIVE.parent).mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / CONTRACT_RELATIVE, project_root / CONTRACT_RELATIVE)
    shutil.copy2(ROOT / PRICING_RELATIVE, project_root / PRICING_RELATIVE)
    shutil.copytree(FIXTURE_ASSET_ROOT, project_root / "assets/_staging/meshy" / ASSET_ID, copy_function=os.link)
    journal_path = project_root / JOURNAL_RELATIVE
    journal_path.unlink()
    shutil.copy2(ROOT / JOURNAL_RELATIVE, journal_path)
    (project_root / PLAN_RELATIVE).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / PLAN_RELATIVE, project_root / PLAN_RELATIVE)
    for relative in stage_module.governance.PROTECTED_RUNTIME_RELATIVE_PATHS:
        (project_root / relative).mkdir(parents=True)
    return project_root


def _copy_reference_set(project_root: Path) -> Path:
    source_task = next(
        path for path in sorted((project_root / "assets/_staging/meshy" / ASSET_ID).iterdir())
        if path.is_dir() and path.name != "_batches"
    )
    reference_root = project_root / "references"
    reference_root.mkdir()
    for view in ("front", "side", "back", "three_quarter"):
        shutil.copy2(source_task / f"source_{view}.png", reference_root / f"source_{view}.png")
    return reference_root


def _contract(project_root: Path):
    return load_contract(project_root / CONTRACT_RELATIVE)


def _journal_path(project_root: Path) -> Path:
    return project_root / "assets/_staging/meshy" / ASSET_ID / "_batches" / JOURNAL_NAME


def _reapprove(project_root: Path, reason: str = "legitimate protected-surface growth", operator: str = "operator@example") -> Dict[str, Any]:
    return stage_module.reapprove_batch(
        _contract(project_root),
        project_root,
        _journal_path(project_root),
        reason=reason,
        operator=operator,
    )


def _reference_specs() -> list[str]:
    return [
        "front=source_front.png",
        "side=source_side.png",
        "back=source_back.png",
        "three_quarter=source_three_quarter.png",
    ]


def _tree_digest(root: Path) -> str:
    entries = []
    for path in sorted(root.rglob("*")):
        if path.is_file():
            entries.append((path.relative_to(root).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest()))
        elif path.is_dir():
            entries.append((path.relative_to(root).as_posix(), "directory"))
    return hashlib.sha256(canonical_json_bytes(entries)).hexdigest()


def test_reapprove_updates_drifted_snapshot_and_preserves_original_approval(tmp_path: Path) -> None:
    project_root = _copy_fixture_project(tmp_path)
    imported = project_root / "assets/imported"
    (imported / "user-import.glb").write_bytes(b"legitimate user import")
    original = json.loads(_journal_path(project_root).read_text(encoding="utf-8"))
    original_approval = copy.deepcopy(original["approval"])

    result = _reapprove(project_root)
    updated = json.loads(_journal_path(project_root).read_text(encoding="utf-8"))

    assert result["old_snapshot"]["sha256"] != result["new_snapshot"]["sha256"]
    assert result["old_snapshot"]["size"] != result["new_snapshot"]["size"]
    assert updated["approval"]["protected_snapshot"] == result["new_snapshot"]["records"]
    for key, value in original_approval.items():
        if key != "protected_snapshot":
            assert updated["approval"][key] == value
    assert updated["approval"]["reapprove_reason"] == "legitimate protected-surface growth"
    assert updated["approval"]["reapprove_operator"] == "operator@example"
    assert updated["approval"]["reapproved_at"].endswith("Z")
    assert updated["approval_history"] == [original_approval]


def test_reapprove_fails_closed_when_terminal_state_is_not_completed(tmp_path: Path) -> None:
    project_root = _copy_fixture_project(tmp_path)
    journal_path = _journal_path(project_root)
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    journal["state"] = "SUBMITTING"
    journal["tasks"][0]["state"] = "PENDING"
    journal["tasks"][0]["task_id"] = None
    journal["tasks"][0]["consumed_credits"] = None
    journal["cumulative_consumed_credits"] -= 5
    journal_path.write_bytes(canonical_json_bytes(journal))

    with pytest.raises(ValueError, match="COMPLETED"):
        _reapprove(project_root)


def test_reapprove_fails_closed_when_task_is_unverified_or_unresolved(tmp_path: Path) -> None:
    project_root = _copy_fixture_project(tmp_path)
    journal_path = _journal_path(project_root)
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    missing_record = project_root / "assets/_staging/meshy" / ASSET_ID / journal["tasks"][0]["task_id"] / "generation.json"
    missing_record.unlink()

    with pytest.raises(ValueError, match="unresolved|verified"):
        _reapprove(project_root)


@pytest.mark.parametrize("field", ["reason", "operator"])
def test_reapprove_fails_closed_on_empty_reason_or_operator(tmp_path: Path, field: str) -> None:
    project_root = _copy_fixture_project(tmp_path)
    kwargs = {"reason": "valid", "operator": "valid"}
    kwargs[field] = "   "

    with pytest.raises(ValueError, match=field):
        _reapprove(project_root, **kwargs)


def test_reapprove_makes_no_provider_or_network_call(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project_root = _copy_fixture_project(tmp_path)
    monkeypatch.setattr(stage_module, "MeshyClient", NoProviderClient)

    result = _reapprove(project_root)

    assert result["batch_id"] == Path(JOURNAL_NAME).stem


def test_verify_passes_after_reapprove_on_same_fixture_tree(tmp_path: Path) -> None:
    project_root = _copy_fixture_project(tmp_path)
    (project_root / "assets/imported/user-import.glb").write_bytes(b"legitimate user import")
    _reapprove(project_root)

    result = stage_module.verify_batch(
        project_root,
        _contract(project_root),
        _journal_path(project_root),
        pricing_file=project_root / PRICING_RELATIVE,
    )

    assert result["pass"] is True
    assert result["unresolved"] == []
    assert result["errors"] == []


def test_legacy_journal_without_approval_history_still_validates(tmp_path: Path) -> None:
    project_root = _copy_fixture_project(tmp_path)
    journal = json.loads(_journal_path(project_root).read_text(encoding="utf-8"))

    assert "approval_history" not in journal
    assert stage_module.validate_batch_journal(journal) == []


def test_reapprove_twice_appends_two_history_entries_and_verify_still_passes(tmp_path: Path) -> None:
    project_root = _copy_fixture_project(tmp_path)
    (project_root / "assets/imported/user-import.glb").write_bytes(b"legitimate user import")
    first = _reapprove(project_root, reason="first", operator="one")
    journal_after_first = json.loads(_journal_path(project_root).read_text(encoding="utf-8"))
    first_approval = journal_after_first["approval"]
    original_approval = journal_after_first["approval_history"][0]
    second = _reapprove(project_root, reason="second", operator="two")
    journal = json.loads(_journal_path(project_root).read_text(encoding="utf-8"))

    assert first["new_snapshot"] == second["new_snapshot"]
    assert journal["approval"]["reapprove_reason"] == "second"
    assert journal["approval_history"] == [original_approval, first_approval]
    assert len(journal["approval_history"]) == 2
    assert stage_module.verify_batch(project_root, _contract(project_root), _journal_path(project_root), pricing_file=project_root / PRICING_RELATIVE)["pass"] is True
