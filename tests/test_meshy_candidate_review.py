from __future__ import annotations

import json
import stat
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional

import pytest

from tools.meshy_asset_contract import AssetContract, canonical_json_bytes, load_contract
from tools.meshy_stage import generate_batch
from tools.meshy_candidate_review import (
    CHECK_FIELDS,
    ReviewError,
    reject_candidate,
    select_candidate,
    transition_review,
    validate_review,
    verify_review,
)

ROOT = Path(__file__).resolve().parents[1]
SCHEMA = ROOT / "data/asset_generation/schemas/meshy_candidate_review_v1.schema.json"
SCRIPT = ROOT / "tools/meshy_candidate_review.py"
TASK_ID = "018-test-candidate"
ASSET_ID = "loot_container_derelict_v1"
CONTRACT_PATH = ROOT / "data/asset_generation/contracts/loot_container_derelict_v1.json"
API_FIXTURES = ROOT / "tests/fixtures/meshy_api"
STAGING = Path("assets/_staging/meshy")


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


def _valid_glb() -> bytes:
    json_chunk = b'{"asset":{"version":"2.0"}}'
    json_chunk += b" " * ((-len(json_chunk)) % 4)
    total = 12 + 8 + len(json_chunk)
    return (
        b"glTF"
        + struct.pack("<II", 2, total)
        + struct.pack("<II", len(json_chunk), int.from_bytes(b"JSON", "little"))
        + json_chunk
    )


class _ReviewFakeMeshyClient:
    def __init__(self, status: str = "SUCCEEDED") -> None:
        self.created_tasks = []
        self._counter = 0
        self.account_lock_id = "a" * 64
        self.status = status

    def get_balance(self) -> int:
        return 10000

    def create_task(self, endpoint: str, payload: dict) -> str:
        self._counter += 1
        task_id = "review-task-{0:04d}".format(self._counter)
        self.created_tasks.append(task_id)
        return task_id

    def poll_task(self, endpoint: str, task_id: str) -> dict:
        fixture = "image_to_3d_succeeded.json"
        response = json.loads((API_FIXTURES / fixture).read_text(encoding="utf-8"))
        response["task_id"] = task_id
        response["consumed_credits"] = 5
        response["status"] = self.status
        response["model_urls"]["glb"] = "https://assets.meshy.ai/{0}.glb".format(task_id)
        response["thumbnail_url"] = "https://assets.meshy.ai/{0}.png".format(task_id)
        return response

    def download_bytes(self, url: str, max_bytes: int, deadline: float, clock: Any) -> bytes:
        return _valid_glb() if url.endswith(".glb") else b"\x89PNG\r\n\x1a\nthumbnail"


def _write_review_references(root: Path) -> dict[str, str]:
    names = {
        "front": "front.png",
        "side": "side.png",
        "back": "back.png",
        "three_quarter": "three-quarter.png",
    }
    payload = b"\x89PNG\r\n\x1a\nreference"
    for index, name in enumerate(names.values()):
        (root / name).write_bytes(payload + bytes([index]))
    return names


def _real_staged_task(
    tmp_path: Path, *, generation_status: str = "SUCCEEDED"
) -> tuple[Path, Path, AssetContract]:
    project_root = tmp_path / "project"
    project_root.mkdir()
    references = project_root / "references"
    references.mkdir()
    contract = load_contract(CONTRACT_PATH)
    specs = _write_review_references(references)
    generation_kwargs: dict[str, Any] = {
        "contract": contract,
        "project_root": project_root,
        "client": _ReviewFakeMeshyClient(generation_status),
        "approved_credits": 100,
        "pricing_file": None,
        "reference_root": references,
        "reference_specs": specs,
        "output_license": "paid-private",
        "today": "2026-09-01",
    }
    if generation_status == "FAILED":
        with pytest.raises(RuntimeError, match="Meshy task ended with status FAILED"):
            generate_batch(**generation_kwargs)
    else:
        generate_batch(**generation_kwargs)
    task_root = project_root / STAGING / contract.asset_id
    task_dir = next(path for path in task_root.iterdir() if path.name != "_batches")
    return project_root, task_dir, contract


def test_select_transitions_pending_to_selected(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)

    result = _run(
        "select",
        "--project-root",
        str(project_root),
        "--task-dir",
        str(task_dir),
        "--reviewer",
        "human-reviewer",
        *(item for field in CHECK_FIELDS for item in ("--check", field)),
    )

    assert result.returncode == 0, result.stderr
    review = _read_review(task_dir)
    assert review["state"] == "selected"
    assert review["decision"] == "accept_for_cleanup"
    assert review["reviewer"] == "human-reviewer"
    assert review["rejection_reasons"] == []
    assert review["checks"] == {field: True for field in CHECK_FIELDS}


def test_reject_transitions_pending_to_rejected(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)

    result = _run(
        "reject",
        "--project-root",
        str(project_root),
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
    project_root, task_dir, _contract = _real_staged_task(tmp_path)
    selected = _read_review(task_dir)
    selected.update({"state": "selected", "decision": "accept_for_cleanup", "checks": _true_checks(), "rejection_reasons": []})
    (task_dir / "review.json").write_bytes(canonical_json_bytes(selected))

    result = _run(
        "select",
        "--project-root",
        str(project_root),
        "--task-dir",
        str(task_dir),
        "--reviewer",
        "operator",
        *(item for field in CHECK_FIELDS for item in ("--check", field)),
    )

    assert result.returncode != 0
    assert "pending" in result.stderr
    assert _read_review(task_dir)["state"] == "selected"


def test_reject_rejects_non_pending_state(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)
    rejected = _read_review(task_dir)
    rejected.update({"state": "rejected", "decision": "reject", "rejection_reasons": ["bad silhouette"]})
    (task_dir / "review.json").write_bytes(canonical_json_bytes(rejected))

    result = _run(
        "reject",
        "--project-root",
        str(project_root),
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
    project_root, task_dir, _contract = _real_staged_task(tmp_path)
    selected = _read_review(task_dir)
    selected.update({"state": "selected", "decision": "accept_for_cleanup", "checks": _true_checks(), "rejection_reasons": []})
    (task_dir / "review.json").write_bytes(canonical_json_bytes(selected))

    result = _run(
        "verify",
        "--project-root",
        str(project_root),
        "--task-dir",
        str(task_dir),
    )

    assert result.returncode == 0, result.stderr
    assert "MESHY CANDIDATE REVIEW PASS" in result.stdout


def test_r3_verify_rejects_selected_review_with_failed_generation(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(
        tmp_path, generation_status="FAILED"
    )
    assert json.loads((task_dir / "generation.json").read_text(encoding="utf-8"))["status"] == "FAILED"
    selected = _read_review(task_dir)
    selected.update(
        {
            "state": "selected",
            "decision": "accept_for_cleanup",
            "checks": _true_checks(),
            "rejection_reasons": [],
        }
    )
    (task_dir / "review.json").write_bytes(canonical_json_bytes(selected))

    with pytest.raises(ReviewError, match="selected review requires SUCCEEDED generation evidence"):
        verify_review(project_root, task_dir)


def test_r3_cli_verify_rejects_selected_review_with_failed_generation(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(
        tmp_path, generation_status="FAILED"
    )
    selected = _read_review(task_dir)
    selected.update(
        {
            "state": "selected",
            "decision": "accept_for_cleanup",
            "checks": _true_checks(),
            "rejection_reasons": [],
        }
    )
    (task_dir / "review.json").write_bytes(canonical_json_bytes(selected))

    result = _run(
        "verify",
        "--project-root",
        str(project_root),
        "--task-dir",
        str(task_dir),
    )

    assert result.returncode != 0
    assert "selected review requires SUCCEEDED generation evidence" in result.stderr
    assert "PASS" not in result.stdout


def test_verify_fails_for_incomplete_review(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)
    checks = _true_checks()
    checks.pop("camera_readability")
    incomplete = _read_review(task_dir)
    incomplete["checks"] = checks
    (task_dir / "review.json").write_bytes(canonical_json_bytes(incomplete))

    result = _run(
        "verify",
        "--project-root",
        str(project_root),
        "--task-dir",
        str(task_dir),
    )

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
    with pytest.raises(ValueError, match="evidence-bound"):
        transition_review(_review(), "promotion_ready")


def test_review_json_is_canonical(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)

    result = _run(
        "select",
        "--project-root",
        str(project_root),
        "--task-dir",
        str(task_dir),
        "--reviewer",
        "operator",
        *(item for field in CHECK_FIELDS for item in ("--check", field)),
    )

    assert result.returncode == 0, result.stderr
    review_path = task_dir / "review.json"
    raw = review_path.read_bytes()
    assert raw == canonical_json_bytes(json.loads(raw.decode("utf-8")))
    assert raw.endswith(b"\n")
    assert not raw.endswith(b"\n\n")
    assert b"aesthetic_score" not in raw


def _true_checks() -> dict[str, bool]:
    return {field: True for field in CHECK_FIELDS}


def test_r3_select_requires_real_bound_generation_and_explicit_checklist(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)

    selected = select_candidate(project_root, task_dir, "human-reviewer", _true_checks())

    assert selected["state"] == "selected"
    assert selected["decision"] == "accept_for_cleanup"
    assert selected["checks"] == _true_checks()
    assert stat.S_IMODE((task_dir / "review.json").stat().st_mode) == 0o600
    assert _read_review(task_dir) == selected


@pytest.mark.parametrize(
    "checks",
    [
        {field: True for field in CHECK_FIELDS[:-1]},
        {**{field: True for field in CHECK_FIELDS[:-1]}, CHECK_FIELDS[-1]: False},
        {**{field: True for field in CHECK_FIELDS}, "unexpected": True},
    ],
)
def test_r3_select_rejects_missing_false_or_unknown_checklist(
    tmp_path: Path, checks: dict[str, bool]
) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)

    with pytest.raises(ReviewError, match="check"):
        select_candidate(project_root, task_dir, "human-reviewer", checks)

    assert _read_review(task_dir)["state"] == "pending"


def test_r3_reject_and_verify_are_distinct_nonpassing_outcome(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)

    rejected = reject_candidate(project_root, task_dir, "bad silhouette", "human-reviewer")
    assert rejected["state"] == "rejected"
    assert rejected["decision"] == "reject"

    verified = verify_review(project_root, task_dir)
    assert verified["state"] == "rejected"

    result = _run(
        "verify",
        "--project-root",
        str(project_root),
        "--task-dir",
        str(task_dir),
    )
    assert result.returncode == 1
    assert "MESHY CANDIDATE REVIEW REJECTED" in result.stdout
    assert "PASS" not in result.stdout


def test_r3_cli_select_requires_each_exact_check_field(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)
    command = ["select", "--project-root", str(project_root), "--task-dir", str(task_dir), "--reviewer", "operator"]

    missing = _run(*command)
    assert missing.returncode != 0
    assert "check" in missing.stderr

    duplicate = _run(*command, "--check", CHECK_FIELDS[0], "--check", CHECK_FIELDS[0])
    assert duplicate.returncode != 0
    assert "duplicate" in duplicate.stderr

    selected = _run(*command, *(item for field in CHECK_FIELDS for item in ("--check", field)))
    assert selected.returncode == 0, selected.stderr
    assert _read_review(task_dir)["checks"] == _true_checks()


def test_r3_rejects_external_nested_and_symlink_task_paths(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)
    outside = tmp_path / "outside"
    outside.mkdir()
    with pytest.raises(ReviewError, match="staging|project root"):
        verify_review(project_root, outside)
    with pytest.raises(ReviewError, match="direct|task"):
        verify_review(project_root, task_dir / "nested")

    linked = project_root / STAGING / "linked"
    linked.symlink_to(outside, target_is_directory=True)
    with pytest.raises(ReviewError, match="symlink"):
        verify_review(project_root, linked)


def test_r3_post_selected_transitions_require_evidence_binder(tmp_path: Path) -> None:
    record = _review(state="selected", checks=_true_checks())

    with pytest.raises(ReviewError, match="evidence-bound"):
        transition_review(record, "blender_cleanup_pass")


def test_r3_direct_validation_rejects_nonfinite_and_deep_json() -> None:
    nonfinite = _review()
    nonfinite["checks"]["silhouette_readable"] = float("nan")
    assert validate_review(nonfinite)

    deep: object = _review()
    for _index in range(100):
        deep = {"nested": deep}
    assert validate_review(deep)


def test_r3_tampered_or_missing_bound_generation_artifacts_fail_closed(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)
    generation_path = task_dir / "generation.json"
    original_generation = generation_path.read_bytes()
    original_raw = (task_dir / "raw.glb").read_bytes()
    try:
        generation_path.write_text('{"task_id":"forged"}', encoding="utf-8")
        with pytest.raises(ReviewError, match="generation evidence"):
            verify_review(project_root, task_dir)
        generation_path.write_bytes(original_generation)

        (task_dir / "raw.glb").unlink()
        with pytest.raises(ReviewError, match="generation evidence"):
            verify_review(project_root, task_dir)
    finally:
        generation_path.write_bytes(original_generation)
        (task_dir / "raw.glb").write_bytes(original_raw)


def test_r3_review_leaf_symlink_and_duplicate_json_do_not_escape_or_pass(
    tmp_path: Path,
) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)
    review_path = task_dir / "review.json"
    original = review_path.read_bytes()
    victim = tmp_path / "victim.json"
    victim.write_bytes(b"outside-original")
    try:
        review_path.unlink()
        review_path.symlink_to(victim)
        with pytest.raises(ReviewError, match="symlink"):
            verify_review(project_root, task_dir)
        assert victim.read_bytes() == b"outside-original"

        review_path.unlink()
        review_path.write_bytes(b'{"schema_version":"1.0.0","schema_version":"1.0.0"}')
        with pytest.raises(ReviewError, match="duplicate"):
            verify_review(project_root, task_dir)
    finally:
        if review_path.is_symlink() or review_path.exists():
            review_path.unlink()
        review_path.write_bytes(original)


def test_r3_lexical_escape_is_rejected_before_resolution(tmp_path: Path) -> None:
    project_root, task_dir, _contract = _real_staged_task(tmp_path)

    with pytest.raises(ReviewError, match="lexical"):
        verify_review(project_root, task_dir / ".." / task_dir.name)
