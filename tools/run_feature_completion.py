#!/usr/bin/env python3
"""Strict, evidence-producing runner for the feature-completion program."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "data/validation/feature_completion_cases.json"
VALIDATION_PLAN = ROOT / "docs/game/06_validation_plan.md"
REGRESSION_HEADER = "## Regression bundle"
REGRESSION_MARKER = re.compile(r"^echo (?:'SYNAPTIC_SEA REGRESSION PASS commands=\d+ clean_output=true'|\"SYNAPTIC_SEA REGRESSION PASS commands=\$\{RUN_CLEAN_COUNT\} clean_output=true\")$", re.M)
DIAGNOSTIC = re.compile(r"^(?:ERROR|WARNING|SCRIPT ERROR):.*$", re.M)
Run = Callable[..., subprocess.CompletedProcess[str]]


class RunnerError(RuntimeError):
    pass


def _text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value


def _diagnostics(stdout: str, stderr: str) -> list[str]:
    # Godot and terminals may prefix diagnostics with SGR color sequences.
    plain = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", stdout + "\n" + stderr)
    return DIAGNOSTIC.findall(plain)


def _terminate_owned_process(process: subprocess.Popen[str]) -> str | None:
    """Stop only the process tree created by this invocation."""
    if os.name == "nt":
        killed = subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], text=True,
                                capture_output=True, check=False)
        if killed.returncode != 0:
            return f"taskkill failed: {killed.returncode}"
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return None


def _capture(command: list[str], *, cwd: Path, env: dict[str, str], timeout: float | None,
             run: Run = subprocess.run) -> tuple[str, str, int | None, bool, str | None]:
    """Capture output without pipe deadlock and clean up a timed-out owned tree."""
    # The injectable runner keeps fake-process tests deterministic; production uses Popen.
    if run is not subprocess.run:
        try:
            completed = run(command, cwd=cwd, text=True, capture_output=True, env=env, timeout=timeout, check=False)
            return _text(completed.stdout), _text(completed.stderr), completed.returncode, False, None
        except subprocess.TimeoutExpired as error:
            return _text(error.stdout), _text(error.stderr), None, True, None
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    process = subprocess.Popen(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, start_new_session=os.name != "nt", creationflags=creationflags)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        return _text(stdout), _text(stderr), process.returncode, False, None
    except subprocess.TimeoutExpired:
        cleanup_error = _terminate_owned_process(process)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            cleanup_error = cleanup_error or "post-kill output drain timed out"
            stdout, stderr = "", ""
        return _text(stdout), _text(stderr), None, True, cleanup_error


def load_cases(path: Path = MANIFEST) -> list[dict[str, Any]]:
    try:
        cases = json.loads(path.read_text(encoding="utf-8"))["cases"]
    except (OSError, KeyError, json.JSONDecodeError) as error:
        raise RunnerError(f"invalid case manifest: {error}") from error
    ids = [case.get("id") for case in cases]
    if len(ids) != len(set(ids)):
        raise RunnerError("duplicate feature-completion case ID")
    for case in cases:
        if (not re.fullmatch(r"P\d\d", str(case.get("id", ""))) or not case.get("script")
                or case.get("marker") != f"FC {case.get('id')} PASS"
                or case.get("scope") not in {"model", "scene"}
                or case.get("profile") not in {"crafting", "restoration"}
                or case.get("status") not in {"planned", "active"}):
            raise RunnerError(f"invalid case definition: {case!r}")
    return cases


def extract_regression_bundle(plan: Path = VALIDATION_PLAN) -> tuple[str, int]:
    text = plan.read_text(encoding="utf-8")
    match = re.search(r"^## Regression bundle\r?\n\r?\n```bash\r?\n", text, re.M)
    if not match:
        raise RunnerError("unrecognized Regression bundle section opening")
    end = re.search(r"^```\r?$", text[match.end():], re.M)
    if not end:
        raise RunnerError("unrecognized Regression bundle section closing")
    body = text[match.end():match.end() + end.start()]
    if len(REGRESSION_MARKER.findall(body)) != 1:
        raise RunnerError("Regression bundle has no recognized dynamic PASS marker")
    count = len(re.findall(r"^run_clean\s+", body, re.M))
    if count == 0:
        raise RunnerError("Regression bundle contains no run_clean commands")
    return body, count


def _prepared_bundle(body: str) -> str:
    """Instrument the temporary copy so its terminal count is computed, never copied."""
    if "run_clean() {" not in body:
        raise RunnerError("Regression bundle has no recognized run_clean function")
    if "RUN_CLEAN_COUNT=0" in body and "RUN_CLEAN_COUNT=$((RUN_CLEAN_COUNT + 1))" in body:
        return body
    body = body.replace("run_clean() {", "RUN_CLEAN_COUNT=0\nrun_clean() {\n  RUN_CLEAN_COUNT=$((RUN_CLEAN_COUNT + 1))", 1)
    return REGRESSION_MARKER.sub('echo "SYNAPTIC_SEA REGRESSION PASS commands=${RUN_CLEAN_COUNT} clean_output=true"', body)


def _git(command: list[str]) -> str:
    try:
        return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False).stdout.strip()
    except OSError:
        return "unavailable"


def metadata(godot: Path, run: Run = subprocess.run) -> dict[str, Any]:
    version = run([str(godot), "--version"], text=True, capture_output=True, check=False)
    return {
        "project_root": str(ROOT), "godot": str(godot), "godot_version": version.stdout.strip() or version.stderr.strip(),
        "godot_version_exit": version.returncode, "commit": _git(["git", "rev-parse", "HEAD"]),
        "dirty_paths": _git(["git", "status", "--porcelain"]).splitlines(),
    }


def _environment(user_data: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update({"GODOT_USER_PATH": str(user_data), "XDG_DATA_HOME": str(user_data),
                "APPDATA": str(user_data), "LOCALAPPDATA": str(user_data)})
    return env


def execute_case(case: dict[str, Any], godot: Path, evidence: Path, user_data: Path,
                 run: Run = subprocess.run, timeout: float = 120.0) -> dict[str, Any]:
    script = ROOT / case["script"]
    result: dict[str, Any] = {"id": case["id"], "scope": case["scope"], "script": case["script"], "marker": case["marker"], "player_accepted": False}
    started = time.monotonic()
    stdout = stderr = ""
    exit_code: int | None = None
    timeout_hit = False
    if not script.is_file():
        result.update({"passed": False, "reason": "missing script", "duration_seconds": 0.0})
    else:
        command = [str(godot), "--headless", "--path", str(ROOT), "--user-data-dir", str(user_data), "--script", "res://" + case["script"]]
        stdout, stderr, exit_code, timeout_hit, cleanup_error = _capture(command, cwd=ROOT, env=_environment(user_data), timeout=timeout, run=run)
        diagnostics = _diagnostics(stdout, stderr)
        marker_found = case["marker"] in stdout.splitlines()
        reason = "passed" if exit_code == 0 and marker_found and not diagnostics else (
            "timeout" if timeout_hit else "nonzero exit" if exit_code else "missing marker" if not marker_found else "unexpected diagnostics")
        result.update({"passed": reason == "passed", "reason": reason, "exit_code": exit_code,
                       "duration_seconds": round(time.monotonic() - started, 6), "diagnostics": diagnostics,
                       "cleanup_error": cleanup_error})
    stem = case["id"].lower()
    (evidence / f"{stem}.stdout.log").write_text(stdout, encoding="utf-8")
    (evidence / f"{stem}.stderr.log").write_text(stderr, encoding="utf-8")
    result.update({"stdout_log": f"{stem}.stdout.log", "stderr_log": f"{stem}.stderr.log"})
    return result


def _verified_bash(run: Run) -> str:
    bash = shutil.which("bash")
    if os.name == "nt" and (not bash or "\\windows\\system32\\bash.exe" in bash.lower()):
        for candidate in (r"C:\Program Files\Git\bin\bash.exe", r"C:\Program Files\Git\usr\bin\bash.exe"):
            if Path(candidate).is_file():
                bash = candidate
                break
    if not bash:
        raise RunnerError("verified Bash is required for the documented regression bundle")
    probe = run([bash, "--version"], text=True, capture_output=True, check=False)
    if probe.returncode != 0 or "GNU bash" not in probe.stdout or (os.name == "nt" and "\\windows\\system32\\bash.exe" in bash.lower()):
        raise RunnerError("Bash probe did not identify a Windows-compatible GNU bash")
    return bash


def execute_bundle(godot: Path, evidence: Path, user_data: Path, run: Run = subprocess.run, timeout: float = 3600.0) -> dict[str, Any]:
    body, count = extract_regression_bundle()
    bash = _verified_bash(run)
    temp = evidence / "canonical_regression_bundle.sh"
    temp.write_text(_prepared_bundle(body), encoding="utf-8", newline="\n")
    started = time.monotonic()
    stdout, stderr, exit_code, timed_out, cleanup_error = _capture([bash, str(temp)], cwd=ROOT,
        env={**_environment(user_data), "ROOT": str(ROOT), "GODOT": str(godot)}, timeout=timeout, run=run)
    (evidence / "baseline.stdout.log").write_text(stdout, encoding="utf-8")
    (evidence / "baseline.stderr.log").write_text(stderr, encoding="utf-8")
    marker_lines = [line for line in stdout.splitlines() if re.fullmatch(r"SYNAPTIC_SEA REGRESSION PASS commands=(\d+) clean_output=true", line)]
    stderr_marker_lines = [line for line in stderr.splitlines() if re.fullmatch(r"SYNAPTIC_SEA REGRESSION PASS commands=(\d+) clean_output=true", line)]
    marker = re.fullmatch(r"SYNAPTIC_SEA REGRESSION PASS commands=(\d+) clean_output=true", stdout.rstrip().splitlines()[-1]) if stdout.rstrip() else None
    actual = int(marker.group(1)) if marker else None
    passed = exit_code == 0 and not timed_out and len(marker_lines) == 1 and not stderr_marker_lines and marker is not None and actual == count
    return {"id": "baseline", "scope": "regression", "passed": passed,
            "reason": "passed" if passed else "bundle failure",
            "exit_code": exit_code, "timed_out": timed_out, "duration_seconds": round(time.monotonic() - started, 6),
            "documented_case_count": count, "actual_case_count": actual,
            "cleanup_error": cleanup_error, "stdout_log": "baseline.stdout.log", "stderr_log": "baseline.stderr.log"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    selected = parser.add_mutually_exclusive_group(required=True)
    selected.add_argument("--case", metavar="PNN")
    selected.add_argument("--profile", choices=("baseline", "crafting", "restoration", "all"))
    parser.add_argument("--evidence-dir", required=True, type=Path)
    parser.add_argument("--bundle-timeout", type=float, default=3600.0)
    args = parser.parse_args(argv)
    if not args.godot.is_file():
        parser.error(f"--godot does not name a file: {args.godot}")
    evidence = args.evidence_dir.resolve(); evidence.mkdir(parents=True, exist_ok=True)
    user_data = evidence / "user-data"; user_data.mkdir(exist_ok=True)
    summary: dict[str, Any] = {"metadata": metadata(args.godot), "user_data_dir": str(user_data), "results": []}
    try:
        cases = load_cases()
        if args.case:
            lookup = {case["id"]: case for case in cases}
            if args.case not in lookup:
                raise RunnerError(f"unknown or unregistered case: {args.case}")
            summary["results"].append(execute_case(lookup[args.case], args.godot, evidence, user_data))
        else:
            if args.profile in ("baseline", "all"):
                summary["results"].append(execute_bundle(args.godot, evidence, user_data, timeout=args.bundle_timeout))
            if args.profile != "baseline":
                wanted = cases if args.profile == "all" else [c for c in cases if c["profile"] == args.profile]
                summary["results"].extend(execute_case(case, args.godot, evidence, user_data) for case in wanted)
    except RunnerError as error:
        summary["runner_error"] = str(error)
    summary["passed"] = not summary.get("runner_error") and bool(summary["results"]) and all(r["passed"] for r in summary["results"])
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"feature completion {'PASS' if summary['passed'] else 'FAIL'}: {evidence / 'summary.json'}")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
