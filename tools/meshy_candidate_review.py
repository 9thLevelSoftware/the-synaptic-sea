#!/usr/bin/env python3
"""Gate staged Meshy candidates through a monotonic review state machine."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.meshy_asset_contract import canonical_json_bytes  # noqa: E402


SCHEMA_VERSION = "1.0.0"
DOCUMENT_KIND = "meshy_candidate_review"
CHECK_FIELDS = (
    "silhouette_readable",
    "proportions_match_contract",
    "functional_volume_present",
    "movable_parts_separable",
    "cleanup_bounded",
    "camera_readability",
)
REVIEW_STATES = (
    "pending",
    "rejected",
    "selected",
    "blender_cleanup_pass",
    "runtime_review_pass",
    "promotion_ready",
)
TRANSITIONS = {
    "pending": frozenset(("rejected", "selected")),
    "selected": frozenset(("blender_cleanup_pass",)),
    "blender_cleanup_pass": frozenset(("runtime_review_pass",)),
    "runtime_review_pass": frozenset(("promotion_ready",)),
    "rejected": frozenset(),
    "promotion_ready": frozenset(),
}
_IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
_TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")


class ReviewError(ValueError):
    """Raised when a review record or state transition is invalid."""


def _is_nonempty_text(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _reject_duplicate_keys(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    result: Dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON field: {0}".format(key))
        result[key] = value
    return result


def validate_review(record: object) -> List[str]:
    """Return validation errors for one Meshy candidate review record."""
    errors: List[str] = []
    required = {
        "schema_version",
        "document_kind",
        "asset_id",
        "task_id",
        "state",
        "decision",
        "checks",
        "rejection_reasons",
        "reviewer",
    }
    if not isinstance(record, dict):
        return ["review record must be an object"]

    unknown = sorted(set(record) - required)
    errors.extend("unknown review field: {0}".format(key) for key in unknown)
    errors.extend("review missing field: {0}".format(key) for key in sorted(required - set(record)))

    if record.get("schema_version") != SCHEMA_VERSION:
        errors.append("schema_version must be {0}".format(SCHEMA_VERSION))
    if record.get("document_kind") != DOCUMENT_KIND:
        errors.append("document_kind must be {0}".format(DOCUMENT_KIND))

    asset_id = record.get("asset_id")
    if not isinstance(asset_id, str) or _IDENTIFIER_RE.fullmatch(asset_id) is None:
        errors.append("asset_id must be a lowercase identifier")

    task_id = record.get("task_id")
    if not isinstance(task_id, str) or _TASK_ID_RE.fullmatch(task_id) is None:
        errors.append("task_id must be a safe identifier")

    state = record.get("state")
    if state not in REVIEW_STATES:
        errors.append("state must be one of: {0}".format(", ".join(REVIEW_STATES)))

    decision = record.get("decision")
    if not _is_nonempty_text(decision):
        errors.append("decision must be non-empty text")

    checks = record.get("checks")
    if not isinstance(checks, dict):
        errors.append("checks must be an object")
    else:
        unknown_checks = sorted(set(checks) - set(CHECK_FIELDS))
        errors.extend("unknown checks field: {0}".format(key) for key in unknown_checks)
        missing_checks = [field for field in CHECK_FIELDS if field not in checks]
        errors.extend("checks missing field: {0}".format(field) for field in missing_checks)
        for field in CHECK_FIELDS:
            if field in checks and not isinstance(checks[field], bool):
                errors.append("checks.{0} must be boolean".format(field))

    rejection_reasons = record.get("rejection_reasons")
    if not isinstance(rejection_reasons, list):
        errors.append("rejection_reasons must be a list")
    else:
        for index, reason in enumerate(rejection_reasons):
            if not _is_nonempty_text(reason):
                errors.append("rejection_reasons[{0}] must be non-empty text".format(index))
        if len(rejection_reasons) == len(
            [reason for reason in rejection_reasons if isinstance(reason, str)]
        ):
            if len(rejection_reasons) != len(set(rejection_reasons)):
                errors.append("rejection_reasons must contain unique values")

    reviewer = record.get("reviewer")
    if not _is_nonempty_text(reviewer):
        errors.append("reviewer must be non-empty text")

    if state == "selected":
        if decision != "accept_for_cleanup":
            errors.append("selected review decision must be accept_for_cleanup")
        if isinstance(checks, dict) and any(checks.get(field) is not True for field in CHECK_FIELDS):
            errors.append("selected review requires every check to be true")
        if rejection_reasons != []:
            errors.append("selected review cannot have rejection reasons")
    elif state == "rejected":
        if decision != "reject":
            errors.append("rejected review decision must be reject")
        if isinstance(rejection_reasons, list) and not rejection_reasons:
            errors.append("rejected review requires at least one rejection reason")
    elif state == "pending":
        if rejection_reasons != []:
            errors.append("pending review cannot have rejection reasons")

    if state not in ("rejected", "pending") and rejection_reasons != []:
        errors.append("accepted review cannot have rejection reasons")
    return errors


def _copy_record(record: Dict[str, Any]) -> Dict[str, Any]:
    return json.loads(canonical_json_bytes(record).decode("utf-8"))


def transition_review(record: Dict[str, Any], target_state: str) -> Dict[str, Any]:
    """Apply one allowed forward transition and return a detached record."""
    current_state = record.get("state") if isinstance(record, dict) else None
    validation_record = record
    # A rejection reason is supplied as part of the pending -> rejected action,
    # so validate the source state before applying that action's payload.
    if current_state == "pending" and target_state == "rejected" and isinstance(record, dict):
        validation_record = _copy_record(record)
        validation_record["rejection_reasons"] = []
    errors = validate_review(validation_record)
    if errors:
        raise ReviewError("invalid review record: {0}".format("; ".join(errors)))
    if target_state not in REVIEW_STATES:
        raise ReviewError("invalid target state: {0}".format(target_state))

    if current_state not in TRANSITIONS:
        raise ReviewError("invalid current state: {0}".format(current_state))
    if target_state not in TRANSITIONS[current_state]:
        raise ReviewError(
            "invalid transition: {0} -> {1}".format(current_state, target_state)
        )

    updated = _copy_record(record)
    updated["state"] = target_state
    if target_state == "selected":
        updated["decision"] = "accept_for_cleanup"
        updated["checks"] = {field: True for field in CHECK_FIELDS}
        updated["rejection_reasons"] = []
    elif target_state == "rejected":
        if not updated["rejection_reasons"]:
            raise ReviewError("rejected transition requires a rejection reason")
        updated["decision"] = "reject"
    return updated


def _task_dir_path(task_dir: Path) -> Path:
    path = Path(task_dir).expanduser()
    if not path.exists() or not path.is_dir() or path.is_symlink():
        raise ReviewError("task directory must be an existing directory")
    try:
        resolved = path.resolve()
    except OSError as exc:
        raise ReviewError("task directory could not be resolved") from exc
    if resolved.is_symlink() or not resolved.is_dir():
        raise ReviewError("task directory must be a regular directory")
    return resolved


def _regular_file(path: Path, label: str) -> Path:
    if path.is_symlink() or not path.is_file():
        raise ReviewError("{0} must be a regular file".format(label))
    return path


def _read_json(path: Path, label: str) -> object:
    try:
        raw = path.read_bytes()
        text = raw.decode("utf-8")
        return json.loads(text, object_pairs_hook=_reject_duplicate_keys)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, RecursionError, ValueError) as exc:
        raise ReviewError("invalid JSON in {0}: {1}".format(label, exc)) from exc


def _load_task_record(task_dir: Path) -> Tuple[Path, Dict[str, Any]]:
    resolved_dir = _task_dir_path(task_dir)
    generation_path = _regular_file(resolved_dir / "generation.json", "generation.json")
    review_path = _regular_file(resolved_dir / "review.json", "review.json")
    generation = _read_json(generation_path, "generation.json")
    if not isinstance(generation, dict):
        raise ReviewError("generation.json must be an object")
    record = _read_json(review_path, "review.json")
    errors = validate_review(record)
    if errors:
        raise ReviewError("invalid review record: {0}".format("; ".join(errors)))
    assert isinstance(record, dict)
    generation_task_id = generation.get("task_id")
    if generation_task_id is not None and generation_task_id != record["task_id"]:
        raise ReviewError("review task_id does not match generation task_id")
    return review_path, record


def _write_review(path: Path, record: Dict[str, Any]) -> None:
    payload = canonical_json_bytes(record)
    descriptor = -1
    temporary_path: Optional[Path] = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix="." + path.name + ".", suffix=".tmp", dir=str(path.parent)
        )
        temporary_path = Path(temporary_name)
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary_path), str(path))
        temporary_path = None
    finally:
        if descriptor != -1:
            os.close(descriptor)
        if temporary_path is not None:
            try:
                temporary_path.unlink()
            except FileNotFoundError:
                pass


def select_candidate(task_dir: Path, reviewer: str) -> Dict[str, Any]:
    """Select a pending candidate after recording a complete checklist."""
    if not _is_nonempty_text(reviewer):
        raise ReviewError("reviewer must be non-empty text")
    review_path, record = _load_task_record(task_dir)
    if record["state"] != "pending":
        raise ReviewError(
            "candidate must be pending; invalid transition from {0}".format(record["state"])
        )
    record["reviewer"] = reviewer
    selected = transition_review(record, "selected")
    _write_review(review_path, selected)
    return selected


def reject_candidate(task_dir: Path, reason: str, reviewer: str) -> Dict[str, Any]:
    """Reject a pending candidate with an explicit human-readable reason."""
    if not _is_nonempty_text(reason):
        raise ReviewError("rejection reason must be non-empty text")
    if not _is_nonempty_text(reviewer):
        raise ReviewError("reviewer must be non-empty text")
    review_path, record = _load_task_record(task_dir)
    if record["state"] != "pending":
        raise ReviewError(
            "candidate must be pending; invalid transition from {0}".format(record["state"])
        )
    record["reviewer"] = reviewer
    record["rejection_reasons"] = [reason]
    rejected = transition_review(record, "rejected")
    _write_review(review_path, rejected)
    return rejected


def verify_review(task_dir: Path) -> Dict[str, Any]:
    """Validate a review and ensure it has left the unreviewed pending state."""
    _review_path, record = _load_task_record(task_dir)
    if record["state"] == "pending":
        raise ReviewError("review is still pending")
    return record


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    select = subparsers.add_parser("select", help="select a pending candidate for Blender cleanup")
    select.add_argument("--task-dir", type=Path, required=True)
    select.add_argument("--reviewer", required=True)

    reject = subparsers.add_parser("reject", help="reject a pending candidate")
    reject.add_argument("--task-dir", type=Path, required=True)
    reject.add_argument("--reason", required=True)
    reject.add_argument("--reviewer", required=True)

    verify = subparsers.add_parser("verify", help="verify a candidate review record")
    verify.add_argument("--task-dir", type=Path, required=True)
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "select":
            record = select_candidate(args.task_dir, args.reviewer)
            print(json.dumps(record, ensure_ascii=False, sort_keys=True))
        elif args.command == "reject":
            record = reject_candidate(args.task_dir, args.reason, args.reviewer)
            print(json.dumps(record, ensure_ascii=False, sort_keys=True))
        elif args.command == "verify":
            record = verify_review(args.task_dir)
            print(
                "MESHY CANDIDATE REVIEW PASS task_id={0} state={1}".format(
                    record["task_id"], record["state"]
                )
            )
        else:  # pragma: no cover - argparse owns the command choices
            return 2
    except (OSError, TypeError, ValueError) as exc:
        print("error: {0}".format(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = [
    "CHECK_FIELDS",
    "DOCUMENT_KIND",
    "REVIEW_STATES",
    "ReviewError",
    "TRANSITIONS",
    "main",
    "reject_candidate",
    "select_candidate",
    "transition_review",
    "validate_review",
    "verify_review",
]
