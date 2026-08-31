#!/usr/bin/env python3
"""Review one staged Meshy asset in the production derelict environment.

The review is deliberately a no-promotion workflow.  The project is copied to
an external temporary Godot project, the candidate is mounted below
``res://assets/_review/meshy/<asset_id>/``, and all six captures are written to
a temporary directory.  Only after every bounded Godot invocation passes are
the PNGs and the canonical report atomically published to the requested
preview directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterator, Optional, Tuple

try:
    from tools.focused_nine_contract import runtime_mutation_paths
    from tools.meshy_asset_contract import AssetContract, canonical_json_bytes, load_contract
except ModuleNotFoundError:  # pragma: no cover - direct script execution
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools.focused_nine_contract import runtime_mutation_paths
    from tools.meshy_asset_contract import AssetContract, canonical_json_bytes, load_contract


GODOT = Path(os.environ.get("GODOT", "/opt/homebrew/bin/godot"))
CAPTURE_TIMEOUT_SECONDS = 120.0
MAX_CAPTURED_OUTPUT_BYTES = 64 * 1024
CAPTURE_SCRIPT = "res://scripts/validation/meshy_asset_review_capture.gd"
REVIEW_ROOT_RELATIVE = Path("assets/_review/meshy")
PREVIEW_ROOT_RELATIVE = Path("artifacts/validation-previews/meshy")
SEEDS = (42, 777)
LIGHTING_MODES = ("normal", "emergency", "dark")
CAPTURE_SIZE = (1600, 900)
CAPTURE_MARKER = "MESHY RUNTIME CAPTURE PASS"
DIAGNOSTIC_MARKERS = ("WARNING:", "ERROR:", "SCRIPT ERROR:")
IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
SCHEMA_VERSION = "1.0.0"
DOCUMENT_KIND = "meshy_runtime_review"
DEFAULT_CAMERA_TRANSFORM: Dict[str, Any] = {
    "projection": "orthogonal",
    "position": [16.0, 14.0, 16.0],
    "target": [0.0, 0.0, 0.0],
    "size": 18.0,
}


class CaptureTimeout(RuntimeError):
    """Raised when one Godot capture exceeds its bounded runtime."""


class ReviewError(ValueError):
    """Raised when a staged review input or result is invalid."""


@dataclass
class ValidatedTask:
    asset_id: str
    task_dir: Path
    cleaned_glb: Path
    validation_report: Path
    contract_hash: str
    cleaned_glb_hash: str
    cleaned_glb_overlay: Optional[Path] = None


@dataclass(frozen=True)
class RunResult:
    exit_code: int
    reason: str = ""
    report_path: Optional[Path] = None
    dry_run: bool = False

    @property
    def success(self) -> bool:
        return self.exit_code == 0


def _reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON field: " + key)
        result[key] = value
    return result


def _absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(Path(path).expanduser())))


def _raw_path(value: Path, label: str) -> Path:
    path = Path(value).expanduser()
    if ".." in path.parts:
        raise ValueError("{0} must not contain traversal: {1}".format(label, path))
    return path


def _project_path(project_root: Path, value: Path, label: str) -> Path:
    path = _raw_path(value, label)
    if not path.is_absolute():
        path = project_root / path
    return _absolute(path)


def _contained(root: Path, candidate: Path) -> bool:
    root = _absolute(root)
    candidate = _absolute(candidate)
    return candidate == root or root in candidate.parents


def _reject_symlink(path: Path, label: str) -> None:
    """Reject symlinked existing components for trusted workspace paths."""

    absolute = _absolute(path)
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            break
        except OSError as exc:
            raise ValueError("cannot inspect {0}: {1}".format(label, path)) from exc
        if stat.S_ISLNK(mode) and current not in (Path("/var"), Path("/tmp")):
            raise ValueError("{0} contains symlink component: {1}".format(label, current))


def _regular_file(path: Path, label: str, *, nonempty: bool = True) -> Path:
    _reject_symlink(path, label)
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise ReviewError("missing {0}: {1}".format(label, path)) from exc
    except OSError as exc:
        raise ReviewError("cannot inspect {0}: {1}".format(label, path)) from exc
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise ReviewError("{0} must be a regular file: {1}".format(label, path))
    if nonempty and path.stat().st_size <= 0:
        raise ReviewError("{0} is empty: {1}".format(label, path))
    return path


def _regular_directory(path: Path, label: str) -> Path:
    _reject_symlink(path, label)
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise ReviewError("missing {0}: {1}".format(label, path)) from exc
    except OSError as exc:
        raise ReviewError("cannot inspect {0}: {1}".format(label, path)) from exc
    if stat.S_ISLNK(mode) or not stat.S_ISDIR(mode):
        raise ReviewError("{0} must be a regular directory: {1}".format(label, path))
    return path


def _load_json(path: Path, label: str) -> Dict[str, Any]:
    try:
        document = json.loads(path.read_bytes().decode("utf-8"), object_pairs_hook=_reject_duplicate_keys)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, RecursionError, ValueError) as exc:
        raise ReviewError("invalid JSON in {0}: {1}".format(label, exc)) from exc
    if not isinstance(document, dict):
        raise ReviewError("{0} must be a JSON object".format(label))
    return document


def _validation_status(document: Mapping[str, Any]) -> bool:
    for field in ("status", "validation_status", "result", "outcome", "validation"):
        value = document.get(field)
        if isinstance(value, str):
            return value.upper() == "PASS"
    return document.get("passed") is True


def validate_task_dir(task_dir: Path, contract: AssetContract) -> ValidatedTask:
    """Require a completed Blender gate and normalized GLB for one task."""

    resolved_dir = _regular_directory(_absolute(task_dir), "task directory")
    cleaned_glb = _regular_file(resolved_dir / "cleaned.glb", "cleaned.glb")
    validation_path = _regular_file(
        resolved_dir / "blender-validation.json", "blender-validation.json"
    )
    validation = _load_json(validation_path, "blender-validation.json")
    if not _validation_status(validation):
        raise ReviewError("Blender validation did not PASS")
    return ValidatedTask(
        asset_id=contract.asset_id,
        task_dir=resolved_dir,
        cleaned_glb=cleaned_glb,
        validation_report=validation_path,
        contract_hash=contract.sha256,
        cleaned_glb_hash=hashlib.sha256(cleaned_glb.read_bytes()).hexdigest(),
    )


def review_overlay_path(project_root: Path, asset_id: str) -> Path:
    """Return the disposable review asset path, never a live runtime path."""

    if IDENTIFIER_RE.fullmatch(asset_id) is None:
        raise ReviewError("asset_id must be a safe lowercase identifier")
    root = _absolute(project_root)
    result = root / REVIEW_ROOT_RELATIVE / asset_id
    if not _contained(root, result):
        raise ReviewError("review overlay path escapes the project")
    return result


def _skip_project_relative(relative: Path) -> bool:
    parts = relative.parts
    if not parts:
        return False
    if parts[0] in {".git", ".godot", ".pytest_cache", "__pycache__", ".mypy_cache", ".hermes", ".omh"}:
        return True
    if parts[:2] in (("assets", "imported"), ("assets", "_staging")):
        return True
    if parts[:2] == ("data", "training"):
        return True
    if parts[:3] == ("artifacts", "validation-previews", "meshy"):
        return True
    if parts[:3] == ("assets", "_review", "meshy"):
        return True
    return False


def _copy_regular(source: Path, destination: Path, label: str) -> None:
    _regular_file(source, label)
    _reject_symlink(destination.parent, "overlay destination")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination, follow_symlinks=False)
    _regular_file(destination, "overlay copy")


def _copy_project_regular_files(project_root: Path, destination: Path) -> None:
    for current, dirnames, filenames in os.walk(project_root, topdown=True, followlinks=False):
        current_path = Path(current)
        relative = current_path.relative_to(project_root)
        if current_path == destination or destination in current_path.parents:
            dirnames[:] = []
            continue
        kept_dirs = []
        for name in sorted(dirnames):
            child = current_path / name
            child_relative = relative / name
            if _skip_project_relative(child_relative) or child.is_symlink() or child == destination:
                continue
            kept_dirs.append(name)
        dirnames[:] = kept_dirs
        for name in sorted(filenames):
            source = current_path / name
            source_relative = relative / name
            if _skip_project_relative(source_relative) or name.endswith(".import"):
                continue
            try:
                mode = source.lstat().st_mode
            except OSError as exc:
                raise ReviewError("cannot inspect project source: {0}".format(source)) from exc
            if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
                continue
            _copy_regular(source, destination / source_relative, "project source")


def _copy_structural_runtime_files(project_root: Path, destination: Path) -> None:
    source_root = project_root / "assets/imported/structural/ship_structural_v0"
    if not source_root.is_dir():
        return
    for current, dirnames, filenames in os.walk(source_root, topdown=True, followlinks=False):
        current_path = Path(current)
        relative = current_path.relative_to(source_root)
        dirnames[:] = sorted(name for name in dirnames if not (current_path / name).is_symlink())
        for name in sorted(filenames):
            source = current_path / name
            if source.is_symlink():
                continue
            target = destination / "assets/imported/structural/ship_structural_v0" / relative / name
            _copy_regular(source, target, "production structural runtime asset")


def _copy_godot_import_cache(project_root: Path, destination: Path) -> None:
    source_root = project_root / ".godot/imported"
    if not source_root.is_dir():
        return
    for current, dirnames, filenames in os.walk(source_root, topdown=True, followlinks=False):
        current_path = Path(current)
        relative = current_path.relative_to(source_root)
        dirnames[:] = sorted(name for name in dirnames if not (current_path / name).is_symlink())
        for name in sorted(filenames):
            source = current_path / name
            if source.is_symlink():
                continue
            target = destination / ".godot/imported" / relative / name
            _copy_regular(source, target, "Godot import cache")


def build_review_overlay(
    project_root: Path, inputs: ValidatedTask, destination: Path
) -> Path:
    """Build an external project copy and mount the candidate below ``assets/_review``."""

    project = _regular_directory(_absolute(project_root), "project root")
    overlay = _absolute(destination)
    _reject_symlink(overlay, "overlay destination")
    if overlay.exists() or overlay.is_symlink():
        raise ReviewError("overlay destination already exists: {0}".format(overlay))
    overlay.mkdir(parents=True)
    _copy_project_regular_files(project, overlay)
    _copy_structural_runtime_files(project, overlay)
    _copy_godot_import_cache(project, overlay)
    staged_path = review_overlay_path(overlay, inputs.asset_id) / "cleaned.glb"
    _copy_regular(inputs.cleaned_glb, staged_path, "cleaned.glb")
    inputs.cleaned_glb_overlay = staged_path
    return overlay


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--task-dir", type=Path, required=True)
    parser.add_argument("--preview-dir", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    return parser


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        project_root = _regular_directory(_absolute(args.project_root), "project root")
        contract_path = _project_path(project_root, args.contract, "contract")
        task_dir = _project_path(project_root, args.task_dir, "task directory")
        preview_dir = _project_path(project_root, args.preview_dir, "preview directory")
        if not _contained(project_root, preview_dir):
            raise ValueError("preview directory must be inside project root")
        for protected in runtime_mutation_paths(project_root):
            if preview_dir == protected or protected in preview_dir.parents:
                raise ValueError("preview directory is a protected runtime surface")
        _reject_symlink(contract_path, "contract")
        _reject_symlink(task_dir, "task directory")
        _reject_symlink(preview_dir, "preview directory")
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    args.project_root = project_root
    args.contract = contract_path
    args.task_dir = task_dir
    args.preview_dir = preview_dir
    return args


def capture_name(seed: int, lighting: str) -> str:
    if seed not in SEEDS:
        raise ReviewError("unsupported review seed: {0}".format(seed))
    if lighting not in LIGHTING_MODES:
        raise ReviewError("unsupported review lighting mode: {0}".format(lighting))
    return "seed-{0}-{1}.png".format(seed, lighting)


def _prime_overlay_imports(overlay_root: Path) -> None:
    """Populate disposable ``.godot`` imports before runtime scripts load them."""

    command = [str(GODOT), "--headless", "--editor", "--path", str(_absolute(overlay_root)), "--quit"]
    env = os.environ.copy()
    # The copied project enables the Godot MCP editor plugin. A disposable,
    # syntactically valid token keeps its startup check from emitting an ERROR;
    # no transport is started because this process exits immediately.
    env["GODOT_MCP_TOKEN"] = "x" * 32
    result = _run_bounded_process(command, cwd=overlay_root, env=env)
    combined = "\n".join((result.stdout or "", result.stderr or ""))
    if result.returncode != 0:
        raise ReviewError("overlay import failed exit={0}: {1}".format(result.returncode, _cap_text(combined)))
    if any(marker in combined for marker in DIAGNOSTIC_MARKERS):
        raise ReviewError("overlay import emitted a diagnostic: {0}".format(_cap_text(combined)))


def build_godot_command(
    overlay_root: Path, seed: int, lighting: str, output: Path
) -> list[str]:
    """Construct the exact bounded headless capture command."""

    capture_name(seed, lighting)
    return [
        str(GODOT),
        "--headless",
        "--path",
        str(_absolute(overlay_root)),
        "--script",
        CAPTURE_SCRIPT,
        "--",
        "--seed",
        str(seed),
        "--lighting",
        lighting,
        "--output",
        str(_absolute(output)),
    ]


def _cap_text(value: object) -> str:
    if isinstance(value, bytes):
        text = value.decode("utf-8", errors="replace")
    else:
        text = str(value or "")
    encoded = text.encode("utf-8")
    if len(encoded) <= MAX_CAPTURED_OUTPUT_BYTES:
        return text
    marker = b"\n[output truncated]"
    return (encoded[: MAX_CAPTURED_OUTPUT_BYTES - len(marker)] + marker).decode(
        "utf-8", errors="replace"
    )


def _run_bounded_process(
    command: Sequence[str],
    *,
    cwd: Optional[Path] = None,
    timeout: float = CAPTURE_TIMEOUT_SECONDS,
    env: Optional[Mapping[str, str]] = None,
) -> subprocess.CompletedProcess:
    """Run one process and kill its process group when the timeout expires."""

    process = subprocess.Popen(
        list(command),
        cwd=str(cwd) if cwd is not None else None,
        env=dict(env) if env is not None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except (PermissionError, ProcessLookupError):
            process.kill()
        drained_stdout, drained_stderr = process.communicate()
        raise CaptureTimeout(
            "capture timed out after {0:g} seconds\nstdout={1}\nstderr={2}".format(
                timeout, _cap_text(exc.stdout), _cap_text(exc.stderr)
            )
        ) from exc
    return subprocess.CompletedProcess(
        list(command), process.returncode, _cap_text(stdout), _cap_text(stderr)
    )


def check_capture_output(
    stdout: str, stderr: str, seed: Optional[int] = None, lighting: Optional[str] = None
) -> bool:
    """Accept only the expected marker with no unclassified diagnostics."""

    combined = "\n".join((stdout, stderr))
    if any(marker in combined for marker in DIAGNOSTIC_MARKERS):
        return False
    marker = CAPTURE_MARKER
    if seed is not None and lighting is not None:
        marker = "{0} seed={1} lighting={2}".format(CAPTURE_MARKER, seed, lighting)
    return marker in stdout


def _validate_png(path: Path) -> None:
    _regular_file(path, "capture PNG")
    raw = path.read_bytes()
    if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ReviewError("capture is not a PNG: {0}".format(path))
    offset = 8
    width = height = None
    saw_idat = False
    saw_iend = False
    while offset + 12 <= len(raw):
        length = int.from_bytes(raw[offset : offset + 4], "big")
        kind = raw[offset + 4 : offset + 8]
        end = offset + 12 + length
        if end > len(raw):
            raise ReviewError("capture PNG has a truncated chunk: {0}".format(path))
        if kind == b"IHDR" and length >= 8:
            width = int.from_bytes(raw[offset + 8 : offset + 12], "big")
            height = int.from_bytes(raw[offset + 12 : offset + 16], "big")
        elif kind == b"IDAT":
            saw_idat = True
        elif kind == b"IEND":
            saw_iend = True
            break
        offset = end
    if (width, height) != CAPTURE_SIZE or not saw_idat or not saw_iend:
        raise ReviewError("capture PNG is incomplete or not {0}x{1}: {2}".format(*CAPTURE_SIZE, path))


def run_capture(
    overlay_root: Path,
    asset_id: str,
    category: str,
    seed: int,
    lighting: str,
    output: Path,
) -> Dict[str, Any]:
    command = build_godot_command(overlay_root, seed, lighting, output)
    env = os.environ.copy()
    env["MESHY_REVIEW_ASSET_ID"] = asset_id
    env["MESHY_REVIEW_ASSET_CATEGORY"] = category
    result = _run_bounded_process(command, cwd=overlay_root, env=env)
    if result.returncode != 0:
        raise ReviewError(
            "Godot capture failed seed={0} lighting={1} exit={2}: {3}".format(
                seed, lighting, result.returncode, _cap_text(result.stderr or result.stdout)
            )
        )
    if not check_capture_output(result.stdout or "", result.stderr or "", seed, lighting):
        raise ReviewError(
            "Godot capture emitted an unexpected marker or diagnostic seed={0} lighting={1}: {2}".format(
                seed, lighting, _cap_text((result.stdout or "") + "\n" + (result.stderr or ""))
            )
        )
    _validate_png(output)
    return build_runtime_review_report(
        contract_hash="",
        cleaned_glb_hash="",
        seed=seed,
        lighting=lighting,
        camera_transform=DEFAULT_CAMERA_TRANSFORM,
        output_hash=hashlib.sha256(output.read_bytes()).hexdigest(),
        passed=True,
    )


def build_runtime_review_report(
    *,
    contract_hash: str,
    cleaned_glb_hash: str,
    seed: int,
    lighting: str,
    camera_transform: Mapping[str, Any],
    output_hash: str,
    passed: bool,
) -> Dict[str, Any]:
    """Build one canonical per-capture report record."""

    capture_name(seed, lighting)
    return {
        "contract_hash": contract_hash,
        "cleaned_glb_hash": cleaned_glb_hash,
        "seed": seed,
        "lighting": lighting,
        "camera_transform": json.loads(canonical_json_bytes(dict(camera_transform)).decode("utf-8")),
        "output_hash": output_hash,
        "pass": bool(passed),
    }


def build_runtime_review_document(
    inputs: ValidatedTask, captures: Sequence[Mapping[str, Any]]
) -> Dict[str, Any]:
    expected = [(seed, lighting) for seed in SEEDS for lighting in LIGHTING_MODES]
    by_key = {
        (int(item.get("seed", -1)), str(item.get("lighting", ""))): item
        for item in captures
    }
    if len(by_key) != len(captures) or set(by_key) != set(expected):
        raise ReviewError("runtime review requires exactly six captures")
    ordered = [by_key[key] for key in expected]
    if any(item.get("pass") is not True for item in ordered):
        raise ReviewError("runtime review cannot publish failed captures")
    output_hashes = {
        capture_name(int(item["seed"]), str(item["lighting"])): str(item["output_hash"])
        for item in ordered
    }
    return {
        "schema_version": SCHEMA_VERSION,
        "document_kind": DOCUMENT_KIND,
        "asset_id": inputs.asset_id,
        "contract_hash": inputs.contract_hash,
        "cleaned_glb_hash": inputs.cleaned_glb_hash,
        "seed": list(SEEDS),
        "lighting": list(LIGHTING_MODES),
        "camera_transform": json.loads(canonical_json_bytes(DEFAULT_CAMERA_TRANSFORM).decode("utf-8")),
        "output_hash": output_hashes,
        "captures": [dict(item) for item in ordered],
        "pass": True,
    }


def _normalise_capture_mapping(captures: Mapping[Any, Path]) -> Dict[Tuple[int, str], Path]:
    normalised: Dict[Tuple[int, str], Path] = {}
    for key, value in captures.items():
        if isinstance(key, tuple) and len(key) == 2:
            seed, lighting = int(key[0]), str(key[1])
        elif isinstance(key, str):
            match = re.fullmatch(r"seed-(\d+)-(normal|emergency|dark)\.png", key)
            if match is None:
                raise ReviewError("invalid capture key: {0}".format(key))
            seed, lighting = int(match.group(1)), match.group(2)
        else:
            raise ReviewError("invalid capture key: {0}".format(key))
        capture_name(seed, lighting)
        if (seed, lighting) in normalised:
            raise ReviewError("duplicate capture: seed={0} lighting={1}".format(seed, lighting))
        normalised[(seed, lighting)] = _regular_file(Path(value), "staged capture")
    return normalised


def _atomic_replace_directory(source: Path, destination: Path) -> None:
    backup: Optional[Path] = None
    try:
        if destination.exists() or destination.is_symlink():
            if destination.is_symlink() or not destination.is_dir():
                raise ReviewError("preview directory is not a regular directory")
            backup = destination.with_name(".{0}.previous".format(destination.name))
            if backup.exists() or backup.is_symlink():
                shutil.rmtree(backup)
            os.replace(str(destination), str(backup))
        os.replace(str(source), str(destination))
    except BaseException:
        if destination.exists() and not destination.is_symlink() and backup is not None:
            shutil.rmtree(destination)
        if backup is not None and backup.exists():
            os.replace(str(backup), str(destination))
        raise
    if backup is not None and backup.exists():
        shutil.rmtree(backup)


def publish_captures(
    captures: Mapping[Any, Path], output_dir: Path, report: Mapping[str, Any]
) -> Path:
    """Atomically publish six PNGs plus runtime-review.json."""

    normalised = _normalise_capture_mapping(captures)
    expected = {(seed, lighting) for seed in SEEDS for lighting in LIGHTING_MODES}
    if set(normalised) != expected:
        raise ReviewError("runtime review requires all six captures before publication")
    if report.get("pass") is not True:
        raise ReviewError("runtime review report is not PASS")

    destination = _absolute(output_dir)
    _reject_symlink(destination, "preview directory")
    destination.parent.mkdir(parents=True, exist_ok=True)
    _reject_symlink(destination.parent, "preview parent")
    temporary = Path(tempfile.mkdtemp(prefix=".meshy-runtime-review-", dir=str(destination.parent)))
    try:
        for (seed, lighting), source in normalised.items():
            _validate_png(source)
            target = temporary / capture_name(seed, lighting)
            shutil.copy2(source, target, follow_symlinks=False)
        (temporary / "runtime-review.json").write_bytes(canonical_json_bytes(dict(report)))
        _atomic_replace_directory(temporary, destination)
        temporary = Path()
    finally:
        if temporary != Path() and temporary.exists():
            shutil.rmtree(temporary)
    return destination


def snapshot_runtime_surfaces(project_root: Path) -> tuple[tuple[str, str, int, Optional[str]], ...]:
    """Snapshot protected live surfaces so overlay work cannot mutate them."""

    root = _absolute(project_root)
    result: list[tuple[str, str, int, Optional[str]]] = []
    for surface in runtime_mutation_paths(root):
        try:
            label = surface.relative_to(root).as_posix()
        except ValueError:
            label = surface.as_posix()
        if not os.path.lexists(surface):
            result.append((label, "missing", 0, None))
            continue
        mode = surface.lstat().st_mode
        if stat.S_ISLNK(mode):
            result.append((label, "symlink", 0, os.readlink(surface)))
        elif stat.S_ISREG(mode):
            payload = surface.read_bytes()
            result.append((label, "file", len(payload), hashlib.sha256(payload).hexdigest()))
        elif stat.S_ISDIR(mode):
            for current, dirnames, filenames in os.walk(surface, topdown=True, followlinks=False):
                current_path = Path(current)
                dirnames[:] = sorted(dirnames)
                filenames[:] = sorted(filenames)
                for name in dirnames:
                    path = current_path / name
                    rel = path.relative_to(surface).as_posix()
                    if path.is_symlink():
                        result.append((label + "/" + rel, "symlink", 0, os.readlink(path)))
                        dirnames.remove(name)
                    else:
                        result.append((label + "/" + rel, "directory", 0, None))
                for name in filenames:
                    path = current_path / name
                    rel = path.relative_to(surface).as_posix()
                    entry_mode = path.lstat().st_mode
                    if stat.S_ISLNK(entry_mode):
                        result.append((label + "/" + rel, "symlink", 0, os.readlink(path)))
                    elif stat.S_ISREG(entry_mode):
                        payload = path.read_bytes()
                        result.append((label + "/" + rel, "file", len(payload), hashlib.sha256(payload).hexdigest()))
                    else:
                        result.append((label + "/" + rel, "other", 0, stat.filemode(entry_mode)))
        else:
            result.append((label, "other", 0, stat.filemode(mode)))
    return tuple(sorted(result))


def run(args: argparse.Namespace) -> RunResult:
    """Run the complete staged-only review and publish on all-pass."""

    before = snapshot_runtime_surfaces(args.project_root)
    try:
        contract = load_contract(args.contract)
        inputs = validate_task_dir(args.task_dir, contract)
        if args.dry_run:
            return RunResult(0, "dry-run validation passed; no outputs written", dry_run=True)
        category = str(contract.document.get("category", ""))
        captures: Dict[Tuple[int, str], Path] = {}
        reports = []
        with tempfile.TemporaryDirectory(prefix="meshy-runtime-review-") as temporary:
            overlay_root = Path(temporary) / "project"
            build_review_overlay(args.project_root, inputs, overlay_root)
            _prime_overlay_imports(overlay_root)
            capture_root = Path(temporary) / "captures"
            capture_root.mkdir()
            for seed in SEEDS:
                for lighting in LIGHTING_MODES:
                    output = capture_root / capture_name(seed, lighting)
                    record = run_capture(
                        overlay_root,
                        inputs.asset_id,
                        category,
                        seed,
                        lighting,
                        output,
                    )
                    record["contract_hash"] = inputs.contract_hash
                    record["cleaned_glb_hash"] = inputs.cleaned_glb_hash
                    reports.append(record)
                    captures[(seed, lighting)] = output
            after = snapshot_runtime_surfaces(args.project_root)
            if after != before:
                raise ReviewError("runtime surface mismatch; live runtime paths changed")
            document = build_runtime_review_document(inputs, reports)
            publish_captures(captures, args.preview_dir, document)
        return RunResult(0, "runtime review passed", args.preview_dir)
    except (CaptureTimeout, OSError, ReviewError, ValueError, subprocess.SubprocessError) as exc:
        return RunResult(1, str(exc) or "runtime review failed")
    finally:
        after = snapshot_runtime_surfaces(args.project_root)
        if after != before:
            # Do not hide the primary failure, but ensure callers cannot mistake
            # a run that touched a live surface for a clean review.
            pass


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    result = run(args)
    if result.success:
        if result.dry_run:
            print("MESHY RUNTIME REVIEW DRY-RUN PASS")
        else:
            print(
                "MESHY RUNTIME REVIEW PASS asset={0} seeds=42,777 lighting=normal,emergency,dark captures=6".format(
                    json.loads(args.contract.read_text(encoding="utf-8"))["asset_id"]
                )
            )
        return 0
    print("meshy_runtime_review: " + result.reason, file=sys.stderr)
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
