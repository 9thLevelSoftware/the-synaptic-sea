#!/usr/bin/env python3
"""Run the accepted focused physical-work smoke groups in isolated homes."""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path
from typing import Any, Callable


ROOT = Path(__file__).resolve().parents[1]
GROUPS = ("P11", "P12", "P13")


def _load_module(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load required module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_cards = _load_module("feature_acceptance_cards", ROOT / "tools" / "build_feature_acceptance.py")
_hardened = _load_module("feature_completion_runner", ROOT / "tools" / "run_feature_completion.py")
CARD_SMOKES: dict[str, list[str]] = {
    group: list(_cards.CARD_SMOKES[group]) for group in GROUPS
}
RunnerError = _hardened.RunnerError
Execute = Callable[[dict[str, Any], Path, Path, Path], dict[str, Any]]


def _case_id(group: str, filename: str) -> str:
    stem = filename.removesuffix(".gd").removesuffix("_smoke")
    return f"{group.lower()}-{re.sub(r'[^a-z0-9]+', '-', stem.lower()).strip('-')}"


def focused_cases(group: str) -> list[dict[str, Any]]:
    if group not in GROUPS:
        raise RunnerError(f"unknown physical-work group: {group}")
    return [
        {
            "id": _case_id(group, filename),
            "filename": filename,
            "scope": "focused",
            "script": f"scripts/validation/{filename}",
            "marker": _cards._smoke_marker(ROOT, filename),
            "player_accepted": False,
        }
        for filename in CARD_SMOKES[group]
    ]


def _prepare_new_evidence_root(evidence: Path) -> None:
    if evidence.exists():
        raise RunnerError("evidence directory must be a new unique directory")
    evidence.mkdir(parents=True)


def run_group(group: str, godot: Path, evidence: Path,
              execute: Execute | None = None) -> dict[str, Any]:
    """Delegate one focused card group to the hardened isolated-case runner."""
    evidence = evidence.resolve()
    _prepare_new_evidence_root(evidence)
    cases = focused_cases(group)
    user_data_root = evidence / "user-data"
    user_data_root.mkdir()
    execute = execute or _hardened.execute_isolated_case
    results: list[dict[str, Any]] = []
    for case in cases:
        result = execute(case, godot, evidence, user_data_root / case["id"])
        results.append(result)
        (evidence / f"{case['id']}.result.json").write_text(
            json.dumps(result, indent=2) + "\n", encoding="utf-8")
    passed = bool(results) and all(result.get("passed") is True for result in results)
    summary = {
        "group": group,
        "case_count": len(cases),
        "godot": str(godot),
        "user_data_root": str(user_data_root),
        "results": results,
        "passed": passed,
        "marker": f"R06 {group} FOCUSED PASS cases={len(cases)}" if passed else "",
    }
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--group", required=True, choices=GROUPS)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    args = parser.parse_args(argv)
    if not args.godot.is_file():
        parser.error(f"--godot does not name a file: {args.godot}")
    try:
        summary = run_group(args.group, args.godot, args.evidence_dir)
    except RunnerError as error:
        print(f"R06 {args.group} FOCUSED FAIL: {error}", file=sys.stderr)
        return 1
    print(summary["marker"] or f"R06 {args.group} FOCUSED FAIL: {args.evidence_dir / 'summary.json'}")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
