#!/usr/bin/env python3
"""Run P10's producer/consumer persistence proof in three isolated processes."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "res://scripts/validation/fc_p10_process_smoke.gd"
DIAGNOSTIC = re.compile(r"^(?:ERROR|WARNING|SCRIPT ERROR):.*$", re.M)
PROCESS_MARKER = re.compile(r"^FC P10 PROCESS .*?$", re.M)
ALLOWED_STDOUT_PREFIXES = (
    "Godot Engine ", "Initialize godot-rust", "The Synaptic Sea ", "PLAYABLE ",
    "ACHIEVEMENT ", "LOOT ", "GameplaySliceBuilder ", "CRAFT STARTED ", "CRAFT COMPLETED ",
    "FIELD CRAFT STARTED ", "FIELD CRAFT COMPLETED ", "FC P10 PROCESS ",
    "FC P10 USER DATA PROBE ",
)
Run = Callable[..., subprocess.CompletedProcess[str]]


class RunnerError(RuntimeError):
    pass


def _text(value: str | bytes | None) -> str:
    return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")


def _diagnostics(stdout: str, stderr: str) -> list[str]:
    text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", stdout + "\n" + stderr)
    return DIAGNOSTIC.findall(text)


def _sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else ""
    except OSError:
        return ""


def _terminate_owned_process(process: subprocess.Popen[str]) -> str | None:
    """Terminate only the child tree created by this runner."""
    if os.name == "nt":
        result = subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], text=True,
                                capture_output=True, check=False)
        return None if result.returncode == 0 else f"taskkill failed: {result.returncode}"
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    return None


def _capture(command: list[str], *, cwd: Path, env: dict[str, str], timeout: float,
             run: Run = subprocess.run) -> tuple[str, str, int | None, bool, str | None]:
    if run is not subprocess.run:
        try:
            completed = run(command, cwd=cwd, text=True, encoding="utf-8", errors="replace", capture_output=True, env=env,
                            timeout=timeout, check=False)
            return _text(completed.stdout), _text(completed.stderr), completed.returncode, False, None
        except subprocess.TimeoutExpired as error:
            return _text(error.stdout), _text(error.stderr), None, True, None
    flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    process = subprocess.Popen(command, cwd=cwd, text=True, encoding="utf-8", errors="replace", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, start_new_session=os.name != "nt", creationflags=flags)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        return _text(stdout), _text(stderr), process.returncode, False, None
    except subprocess.TimeoutExpired:
        cleanup_error = _terminate_owned_process(process)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            stdout = stderr = ""
            cleanup_error = cleanup_error or "post-kill output drain timed out"
        return _text(stdout), _text(stderr), None, True, cleanup_error


def _environment(user_data: Path) -> dict[str, str]:
    env = os.environ.copy()
    # Each process receives its own deliberately empty, run-local Godot home.
    env.update({"APPDATA": str(user_data), "LOCALAPPDATA": str(user_data),
                "GODOT_USER_PATH": str(user_data), "XDG_DATA_HOME": str(user_data)})
    return env


def _source_hashes(project_root: Path) -> dict[str, str]:
    """Hash the textual gameplay closure, excluding imports and binary assets."""
    candidates = [project_root / "project.godot", project_root / "tools/run_p10_process_smoke.py",
                  project_root / "tests/test_p10_process_runner.py"]
    for directory, suffixes in (("scripts", {".gd"}), ("scenes", {".tscn"}), ("data", {".json", ".tres"})):
        base = project_root / directory
        if base.is_dir():
            candidates.extend(path for path in base.rglob("*") if path.is_file() and path.suffix in suffixes)
    return {path.relative_to(project_root).as_posix(): _sha256(path)
            for path in sorted(set(candidates), key=lambda item: item.as_posix())}


def _metadata(godot: Path, project_root: Path) -> dict[str, Any]:
    stdout, stderr, exit_code, timed_out, cleanup_error = _capture(
        [str(godot), "--version"], cwd=project_root, env=os.environ.copy(), timeout=10.0)
    version_text = stdout.strip() or stderr.strip()
    if timed_out or cleanup_error or exit_code != 0 or not version_text or _diagnostics(stdout, stderr):
        raise RunnerError("Godot version probe failed exit=%s timeout=%s cleanup=%s" % (
            exit_code, timed_out, cleanup_error))
    hashes = _source_hashes(project_root)
    if not hashes or any(not digest for digest in hashes.values()):
        raise RunnerError("gameplay source manifest contains a missing or unreadable file")
    return {"project_root": str(project_root), "godot": str(godot),
            "godot_version": version_text, "godot_version_exit": exit_code,
            "source_sha256": hashes}


def _execute_mode(mode: str, godot: Path, project_root: Path, evidence: Path, user_data: Path, paths: dict[str, Path],
                  timeout: float, run: Run = subprocess.run) -> dict[str, Any]:
    marker = f"FC P10 PROCESS {mode.upper()} PASS"
    mode_inputs = {
        "producer": ("baseline", "expected"),
        "consumer1": ("baseline", "expected", "post", "post_manifest"),
        "consumer2": ("post", "post_manifest"),
    }[mode]
    command = [str(godot), "--headless", "--path", str(project_root), "--user-data-dir", str(user_data), "--script", SCRIPT,
               "--", f"--mode={mode}", f"--user_data={user_data}"] + [f"--{key}={paths[key]}" for key in mode_inputs]
    started = time.monotonic()
    stdout, stderr, exit_code, timed_out, cleanup_error = _capture(command, cwd=project_root, env=_environment(user_data), timeout=timeout, run=run)
    (evidence / f"{mode}.stdout.log").write_text(stdout, encoding="utf-8")
    (evidence / f"{mode}.stderr.log").write_text(stderr, encoding="utf-8")
    diagnostics = _diagnostics(stdout, stderr)
    process_markers = PROCESS_MARKER.findall(stdout) + PROCESS_MARKER.findall(stderr)
    marker_count = stdout.splitlines().count(marker)
    marker_found = process_markers == [marker]
    unexpected_lines = [line for line in stdout.splitlines()
                        if line and not line.startswith(ALLOWED_STDOUT_PREFIXES)]
    unexpected_stderr = [line for line in stderr.splitlines() if line]
    passed = exit_code == 0 and not timed_out and marker_found and marker_count == 1 and not diagnostics and not unexpected_lines and not unexpected_stderr
    return {"mode": mode, "marker": marker, "passed": passed,
            "reason": "passed" if passed else "timeout" if timed_out else "nonzero exit" if exit_code else "missing marker" if not marker_found else "unexpected diagnostics",
            "exit_code": exit_code, "timed_out": timed_out, "cleanup_error": cleanup_error,
            "diagnostics": diagnostics, "duration_seconds": round(time.monotonic() - started, 6),
            "marker_count": marker_count, "process_markers": process_markers,
            "unexpected_stdout": unexpected_lines, "unexpected_stderr": unexpected_stderr,
            "stdout_log": f"{mode}.stdout.log", "stderr_log": f"{mode}.stderr.log"}


def _execute_containment_probe(mode: str, godot: Path, project_root: Path,
                               evidence: Path, user_data: Path, timeout: float,
                               run: Run = subprocess.run) -> dict[str, Any]:
    marker_prefix = "FC P10 USER DATA PROBE PASS resolved_user="
    command = [str(godot), "--headless", "--path", str(project_root),
               "--log-file", str(evidence / f"{mode}.probe.godot.log"),
               "--user-data-dir", str(user_data), "--script", SCRIPT, "--",
               "--mode=probe", f"--user_data={user_data}"]
    stdout, stderr, exit_code, timed_out, cleanup_error = _capture(
        command, cwd=project_root, env=_environment(user_data), timeout=timeout,
        run=run)
    stdout_name = f"{mode}.probe.stdout.log"
    stderr_name = f"{mode}.probe.stderr.log"
    (evidence / stdout_name).write_text(stdout, encoding="utf-8")
    (evidence / stderr_name).write_text(stderr, encoding="utf-8")
    diagnostics = _diagnostics(stdout, stderr)
    marker_lines = [line for line in stdout.splitlines()
                    if line.startswith(marker_prefix)]
    unexpected_lines = [line for line in stdout.splitlines()
                        if line and not line.startswith(("Godot Engine ",
                                                        "Initialize godot-rust",
                                                        marker_prefix))]
    expected_root = str(user_data).replace("\\", "/")
    resolved_is_owned = len(marker_lines) == 1 and (
        f" root={expected_root}" in marker_lines[0]
        or f" root={str(user_data)}" in marker_lines[0])
    passed = (exit_code == 0 and not timed_out and not cleanup_error
              and not diagnostics and not stderr.splitlines()
              and not unexpected_lines and resolved_is_owned)
    return {"mode": mode, "passed": passed,
            "reason": "passed" if passed else "containment probe failed",
            "exit_code": exit_code, "timed_out": timed_out,
            "cleanup_error": cleanup_error, "diagnostics": diagnostics,
            "marker_count": len(marker_lines),
            "resolved_user_data": marker_lines[0] if len(marker_lines) == 1 else "",
            "expected_root": str(user_data), "unexpected_stdout": unexpected_lines,
            "unexpected_stderr": stderr.splitlines(),
            "stdout_log": stdout_name, "stderr_log": stderr_name}


def execute(godot: Path, evidence: Path, timeout: float = 180.0, run: Run = subprocess.run,
            project_root: Path | None = None) -> dict[str, Any]:
    project_root = (project_root or ROOT).resolve()
    if not godot.is_file():
        raise RunnerError(f"Godot executable does not exist: {godot}")
    if not (project_root / "project.godot").is_file() or not (project_root / SCRIPT.removeprefix("res://")).is_file():
        raise RunnerError(f"--root is not a P10 process-proof Godot project: {project_root}")
    if evidence.exists() and any(evidence.iterdir()):
        raise RunnerError("evidence directory must be a new empty unique directory")
    evidence.mkdir(parents=True, exist_ok=True)
    mode_homes = {mode: evidence / f"{mode}-user-data" for mode in ("producer", "consumer1", "consumer2")}
    for home in mode_homes.values():
        home.mkdir()
    paths = {"baseline": evidence / "baseline.world.json", "expected": evidence / "expected-observations.json",
             "post": evidence / "post-collection.world.json", "post_manifest": evidence / "post-collection-manifest.json"}
    summary: dict[str, Any] = {"metadata": {},
                               "mode_user_data_dirs": {mode: str(home) for mode, home in mode_homes.items()},
                               "containment_probes": [], "results": []}
    try:
        summary["metadata"] = _metadata(godot, project_root)
    except RunnerError as error:
        summary["runner_error"] = str(error)
        summary["artifacts"] = {key: {"path": str(value), "sha256": _sha256(value), "exists": value.is_file()} for key, value in paths.items()}
        summary["passed"] = False
        (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        return summary
    try:
        for mode in ("producer", "consumer1", "consumer2"):
            probe = _execute_containment_probe(
                mode, godot, project_root, evidence, mode_homes[mode],
                min(timeout, 30.0), run)
            summary["containment_probes"].append(probe)
            if not probe["passed"]:
                break
            result = _execute_mode(mode, godot, project_root, evidence, mode_homes[mode], paths, timeout, run)
            summary["results"].append(result)
            if not result["passed"]:
                break
            if mode == "producer":
                try:
                    expected = json.loads(paths["expected"].read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError) as error:
                    result.update({"passed": False, "reason": f"malformed expected manifest: {error}"})
                    break
                if (not isinstance(expected, dict) or expected.get("schema") != "p10-process-1"
                        or not isinstance(expected.get("baseline_sha256"), str)
                        or not re.fullmatch(r"[0-9a-f]{64}", expected["baseline_sha256"])):
                    result.update({"passed": False, "reason": "malformed expected manifest: invalid schema or digest"})
                    break
                digest_ok = _sha256(paths["baseline"]) == expected.get("baseline_sha256")
                result["baseline_digest_verified"] = digest_ok
                if not digest_ok:
                    result.update({"passed": False, "reason": "baseline digest mismatch"})
                    break
            if mode == "consumer1":
                try:
                    post_manifest = json.loads(paths["post_manifest"].read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError) as error:
                    result.update({"passed": False, "reason": f"malformed post manifest: {error}"})
                    break
                if (not isinstance(post_manifest, dict) or post_manifest.get("schema") != "p10-process-post-1"
                        or not isinstance(post_manifest.get("post_sha256"), str)
                        or not re.fullmatch(r"[0-9a-f]{64}", post_manifest["post_sha256"])
                        or _sha256(paths["post"]) != post_manifest["post_sha256"]):
                    result.update({"passed": False, "reason": "post digest or manifest mismatch"})
                    break
    except OSError as error:
        summary["runner_error"] = f"artifact handling failed: {error}"
    summary["artifacts"] = {key: {"path": str(value), "sha256": _sha256(value), "exists": value.is_file()} for key, value in paths.items()}
    summary["metadata"]["source_sha256_after"] = _source_hashes(project_root)
    summary["source_drift_detected"] = summary["metadata"].get("source_sha256", {}) != summary["metadata"]["source_sha256_after"]
    summary["passed"] = (not summary.get("runner_error")
                         and not summary["source_drift_detected"]
                         and len(summary["containment_probes"]) == 3
                         and all(item["passed"] for item in summary["containment_probes"])
                         and len(summary["results"]) == 3
                         and all(item["passed"] for item in summary["results"])
                         and all(item["exists"] for item in summary["artifacts"].values()))
    (evidence / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args(argv)
    try:
        summary = execute(args.godot.resolve(), args.evidence_dir.resolve(), args.timeout, project_root=args.root)
    except RunnerError as error:
        print(f"P10 process FAIL: {error}", file=sys.stderr)
        return 1
    print(f"FC P10 PROCESS {'PASS' if summary['passed'] else 'FAIL'}: {args.evidence_dir / 'summary.json'}")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
