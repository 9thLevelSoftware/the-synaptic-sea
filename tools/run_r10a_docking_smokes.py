#!/usr/bin/env python3
"""Run the mandatory R10-A docking prerequisites in isolated process homes."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
CASE_FILENAMES = (
    "r10a_dock_endpoint_contract_smoke.gd",
    "r10a_dock_traversal_smoke.gd",
    "r10a_ceiling_clearance_smoke.gd",
    "canonical_opening_smoke.gd",
    "docking_manager_smoke.gd",
    "dock_ports_smoke.gd",
    "boot_dock_aligned_smoke.gd",
    "occupancy_flip_smoke.gd",
    "physical_travel_smoke.gd",
    "docking_persistence_smoke.gd",
    "combat_persistence_smoke.gd",
    "save_migration_world_smoke.gd",
    "save_migration_service_smoke.gd",
    "world_snapshot_smoke.gd",
    "hallucination_director_smoke.gd",
)
EXACT_MARKERS = {
    "docking_manager_smoke.gd": (
        "DOCKING MANAGER PASS aligned=true relationship=true undock=true "
        "rejects=true self_guard=true resevers=true"),
    "save_migration_world_smoke.gd": (
        "SAVE MIGRATION WORLD PASS unknown_version_passthrough=true "
        "legacy_home_ship_migrated=true current_world_home_ship_migrated=true"),
}
Execute = Callable[[dict[str, Any], Path, Path, Path], dict[str, Any]]


def _load_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load required module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_cards = _load_module("feature_acceptance_cards", ROOT / "tools" / "build_feature_acceptance.py")
_hardened = _load_module("feature_completion_runner", ROOT / "tools" / "run_feature_completion.py")
RunnerError = _hardened.RunnerError


def _case_id(filename: str) -> str:
    stem = filename.removesuffix(".gd").removesuffix("_smoke")
    return re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")


def mandatory_cases() -> list[dict[str, Any]]:
    """Return the fifteen governance-listed R10-A prerequisite cases."""
    return [{
        "id": _case_id(filename),
        "filename": filename,
        "scope": "r10a-docking-prerequisite",
        "script": f"scripts/validation/{filename}",
        "marker": EXACT_MARKERS.get(filename, _cards._smoke_marker(ROOT, filename)),
        "player_accepted": False,
    } for filename in CASE_FILENAMES]


def _prepare_new_evidence_root(evidence: Path) -> None:
    if evidence.exists():
        raise RunnerError("evidence directory must be a new unique directory")
    evidence.mkdir(parents=True)


def _retain_hashes(evidence: Path) -> None:
    entries = []
    for path in sorted(evidence.rglob("*")):
        if path.is_file() and path.name != "artifact_hashes.json":
            payload = path.read_bytes()
            entries.append({
                "path": path.relative_to(evidence).as_posix(),
                "bytes": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            })
    (evidence / "artifact_hashes.json").write_text(
        json.dumps({"schema_version": "r10a-artifact-hashes-v1", "entries": entries}, indent=2) + "\n",
        encoding="utf-8")


def _verify_retained_case(case: dict[str, Any], result: dict[str, Any], evidence: Path) -> dict[str, Any]:
    if result.get("passed") is not True:
        return result
    stdout_name = result.get("stdout_log")
    stderr_name = result.get("stderr_log")
    if not isinstance(stdout_name, str) or not isinstance(stderr_name, str):
        result.update({"passed": False, "reason": "missing retained raw output"})
        return result
    stdout_path = evidence / stdout_name
    stderr_path = evidence / stderr_name
    if not stdout_path.is_file() or not stderr_path.is_file():
        result.update({"passed": False, "reason": "missing retained raw output"})
        return result
    lines = stdout_path.read_text(encoding="utf-8", errors="replace").splitlines()
    marker_count = sum(line == case["marker"] for line in lines)
    result["marker_count"] = marker_count
    if result.get("passed") is True and marker_count != 1:
        result.update({"passed": False, "reason": "missing marker" if marker_count == 0 else "duplicate marker"})
    return result


def run(godot: Path, evidence: Path, execute: Execute | None = None) -> dict[str, Any]:
    """Run every mandatory case through the hardened isolated-case seam."""
    evidence = evidence.resolve()
    _prepare_new_evidence_root(evidence)
    cases = mandatory_cases()
    user_data_root = evidence / "user-data"
    user_data_root.mkdir()
    execute = execute or _hardened.execute_isolated_case
    results: list[dict[str, Any]] = []
    for case in cases:
        result = _verify_retained_case(
            case, execute(case, godot, evidence, user_data_root / case["id"]), evidence)
        result.setdefault("filename", case["filename"])
        results.append(result)
        (evidence / f"{case['id']}.result.json").write_text(
            json.dumps(result, indent=2) + "\n", encoding="utf-8")
    passed = bool(results) and all(result.get("passed") is True for result in results)
    summary = {
        "suite": "R10-A docking prerequisite",
        "case_count": len(cases),
        "godot": str(godot),
        "user_data_root": str(user_data_root),
        "results": results,
        "passed": passed,
        "marker": f"R10-A DOCKING PREREQUISITE PASS cases={len(cases)}" if passed else "",
    }
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    _retain_hashes(evidence)
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    if args.root.resolve() != ROOT:
        parser.error(f"--root must name this project root: {ROOT}")
    if not args.godot.is_file():
        parser.error(f"--godot does not name a file: {args.godot}")
    try:
        summary = run(args.godot, args.evidence_dir)
    except RunnerError as error:
        print(f"R10-A DOCKING PREREQUISITE FAIL: {error}", file=sys.stderr)
        return 1
    print(summary["marker"] or f"R10-A DOCKING PREREQUISITE FAIL: {args.evidence_dir / 'summary.json'}")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
