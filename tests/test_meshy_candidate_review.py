from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, Optional

import pytest

from tools.meshy_asset_contract import canonical_json_bytes
from tools.meshy_candidate_review import (
    CHECK_FIELDS,
    transition_review,
    validate_review,
)

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "data/asset_generation/schemas/meshy_candidate_review_v1.schema.json"
SCRIPT = ROOT / "tools/meshy_candidate_review.py"
TASK_ID = "018-test-candidate"
ASSET_ID = "loot_container_derelict_v1"


def _review(
    *,
    state: str = "pending",
    checks: Optional[Dict[str, bool]] = None,
    rejection_reasons: Optional[list[str]] = None,
) -> dict:
    return {
        "schema_version": "1.0.0",
        "document_kind": "meshy_candidate_review",
        "asset_id": ASSET_ID,
        "task_id": TASK_ID,
        "state": state,
        "decision": (
            "accept_for_cleanup"
            if state == "selected"
            else "reject"
            if state == "rejected"
            else "pending"
        ),
        "checks": checks if checks is not None else {field: False for field in CHECK_FIELDS},
        "rejection_reasons": rejection_reasons if rejection_reasons is not None else [],
        "reviewer": "operator",
    }


def _task_dir(
    tmp_path: Path,
    *,
    review: Optional[dict] = None,
    generation: Optional[dict] = None,
) -> Path:
    task_dir = tmp_path / "candidate-task"
    task_dir.mkdir()
    (task_dir / "generation.json").write_bytes(
        canonical_json_bytes(generation or {"task_id": TASK_ID, "status": "SUCCEEDED"})
    )
    (task_dir / "review.json").write_bytes(canonical_json_bytes(review or _review()))
    return task_dir


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def _read_review(task_dir: Path) -> dict:
    return json.loads((task_dir / "review.json").read_text(encoding="utf-8"))


def test_select_transitions_pending_to_selected(tmp_path: Path) -> None:
    task_dir = _task_dir(tmp_path)

    result = _run("select", "--task-dir", str(task_dir), "--reviewer", "human-reviewer")

    assert result.returncode == 0, result.stderr
    review = _read_review(task_dir)
    assert review["state"] == "selected"
    assert review["decision"] == "accept_for_cleanup"
    assert review["reviewer"] == "human-reviewer"
    assert review["rejection_reasons"] == []
    assert review["checks"] == {field: True for field in CHECK_FIELDS}


def test_reject_transitions_pending_to_rejected(tmp_path: Path) -> None:
    task_dir = _task_dir(tmp_path)

    result = _run(
        "reject",
        "--task-dir",
        str(task_dir),
        "--reason",
        "functional volume is missing",
        "--reviewer",
        "human-reviewer",
    )

    assert result.returncode == 0, result.stderr
    review = _read_review(task_dir)
    assert review["state"] == "rejected"
    assert review["decision"] == "reject"
    assert review["reviewer"] == "human-reviewer"
    assert "functional volume is missing" in review["rejection_reasons"]


def test_select_rejects_non_pending_state(tmp_path: Path) -> None:
    task_dir = _task_dir(tmp_path, review=_review(state="selected", checks={field: True for field in CHECK_FIELDS}))

    result = _run("select", "--task-dir", str(task_dir), "--reviewer", "operator")

    assert result.returncode != 0
    assert "pending" in result.stderr
    assert _read_review(task_dir)["state"] == "selected"


def test_reject_rejects_non_pending_state(tmp_path: Path) -> None:
    task_dir = _task_dir(tmp_path, review=_review(state="rejected", rejection_reasons=["bad silhouette"]))

    result = _run(
        "reject",
        "--task-dir",
        str(task_dir),
        "--reason",
        "another reason",
        "--reviewer",
        "operator",
    )

    assert result.returncode != 0
    assert "pending" in result.stderr
    assert _read_review(task_dir)["state"] == "rejected"


def test_verify_passes_for_complete_review(tmp_path: Path) -> None:
    task_dir = _task_dir(
        tmp_path,
        review=_review(state="selected", checks={field: True for field in CHECK_FIELDS}),
    )

    result = _run("verify", "--task-dir", str(task_dir))

    assert result.returncode == 0, result.stderr
    assert "MESHY CANDIDATE REVIEW PASS" in result.stdout


def test_verify_fails_for_incomplete_review(tmp_path: Path) -> None:
    checks = {field: True for field in CHECK_FIELDS}
    checks.pop("camera_readability")
    task_dir = _task_dir(tmp_path, review=_review(checks=checks))

    result = _run("verify", "--task-dir", str(task_dir))

    assert result.returncode != 0
    assert "checks" in result.stderr


def test_review_record_validates_against_schema(tmp_path: Path) -> None:
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    record = _review(state="selected", checks={field: True for field in CHECK_FIELDS})

    assert schema["properties"]["document_kind"]["const"] == "meshy_candidate_review"
    assert set(schema["required"]) == set(record)
    assert validate_review(record) == []


def test_no_backward_transitions() -> None:
    record = _review(state="selected", checks={field: True for field in CHECK_FIELDS})

    with pytest.raises(ValueError, match="invalid transition"):
        transition_review(record, "pending")


def test_no_direct_promotion_jump() -> None:
    with pytest.raises(ValueError, match="invalid transition"):
        transition_review(_review(), "promotion_ready")


def test_review_json_is_canonical(tmp_path: Path) -> None:
    task_dir = _task_dir(tmp_path)

    result = _run("select", "--task-dir", str(task_dir), "--reviewer", "operator")

    assert result.returncode == 0, result.stderr
    review_path = task_dir / "review.json"
    raw = review_path.read_bytes()
    assert raw == canonical_json_bytes(json.loads(raw.decode("utf-8")))
    assert raw.endswith(b"\n")
    assert not raw.endswith(b"\n\n")
    assert b"aesthetic_score" not in raw
