#!/usr/bin/env python3
"""Run a governed, no-promotion locked-isometric Meshy review.

The runtime review is intentionally task-bound.  It consumes only a selected
Meshy task's canonical contract, SUCCEEDED generation record, cleaned GLB, and
R4 Blender validation report.  Godot runs in a disposable project overlay and
publishes six fixed captures followed by one immutable report through the
shared governance writer.  Fixed leaves and atomic writes constrain this
Python API; same-UID malicious raw filesystem writes outside this API remain
outside its trusted-workspace guarantee.
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
import math
import os
import re
import shutil
import stat
import struct
import sys
import tempfile
import zlib
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterator, Optional, Tuple

try:
    from tools import meshy_governance as governance
    from tools.meshy_asset_contract import AssetContract, canonical_json_bytes, load_contract
    from tools.meshy_blender_master import _run_bounded_process as _master_run_bounded_process
except ModuleNotFoundError:  # pragma: no cover - direct script execution
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools import meshy_governance as governance
    from tools.meshy_asset_contract import AssetContract, canonical_json_bytes, load_contract
    from tools.meshy_blender_master import _run_bounded_process as _master_run_bounded_process


GODOT = Path(os.environ.get("GODOT", "/opt/homebrew/bin/godot"))
CAPTURE_TIMEOUT_SECONDS = 120.0
MAX_CAPTURED_OUTPUT_BYTES = 64 * 1024
PROTECTED_SNAPSHOT_MAX_FILE_BYTES = 1 * 1024 * 1024 * 1024
PROTECTED_SNAPSHOT_MAX_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
PROTECTED_SNAPSHOT_MAX_ENTRIES = 20_000
PROTECTED_SNAPSHOT_MAX_DEPTH = 128
CAPTURE_SCRIPT = "res://scripts/validation/meshy_asset_review_capture.gd"
REVIEW_ROOT_RELATIVE = Path("assets/_review/meshy")
PREVIEW_ROOT_RELATIVE = Path("artifacts/validation-previews/meshy")
SEEDS = (42, 777)
LIGHTING_MODES = ("normal", "emergency", "dark")
CAPTURE_SIZE = (1600, 900)
CAPTURE_MARKER = "MESHY RUNTIME CAPTURE PASS"
DIAGNOSTIC_MARKERS = ("WARNING:", "ERROR:", "SCRIPT ERROR:")
IDENTIFIER_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
TASK_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
SCHEMA_VERSION = "1.0.0"
DOCUMENT_KIND = "meshy_runtime_review"
LOCKED_CAMERA_DIRECTION = (16.0, 14.0, 16.0)
LOCKED_CAMERA_DIRECTION_TOLERANCE = 1e-4
CAMERA_SIZE_MIN = 1.5
CAMERA_SIZE_MAX = 4096.0
CAMERA_SIZE_DIMENSION_SCALE = 16.0
STAGED_SAMPLE_STEP_X = max(1, CAPTURE_SIZE[0] // 64)
STAGED_SAMPLE_STEP_Y = max(1, CAPTURE_SIZE[1] // 36)
STAGED_SAMPLE_MAX = len(range(0, CAPTURE_SIZE[0], STAGED_SAMPLE_STEP_X)) * len(
    range(0, CAPTURE_SIZE[1], STAGED_SAMPLE_STEP_Y)
)
RUNTIME_DOCUMENT_FIELDS = frozenset(
    (
        "schema_version",
        "document_kind",
        "asset_id",
        "task_id",
        "contract_sha256",
        "cleaned_glb_sha256",
        "blender_validation_sha256",
        "seeds",
        "lighting",
        "captures",
        "output_hashes",
        "pass",
        "reason",
    )
)
CAPTURE_FIELDS = frozenset(
    (
        "seed",
        "lighting",
        "camera_transform",
        "staged_visibility",
        "output_sha256",
        "pass",
        "reason",
    )
)
FIXED_OUTPUT_NAMES = tuple(
    "seed-{0}-{1}.png".format(seed, lighting)
    for seed in SEEDS
    for lighting in LIGHTING_MODES
) + ("runtime-review.json",)
# Kept for the small public helper API used by older callers.  Runtime runs
# never use this value as evidence; they record the marker's actual transform.
DEFAULT_CAMERA_TRANSFORM: Dict[str, Any] = {
    "projection": "orthogonal",
    "position": [19.742138317, 18.236871003, 19.242143317],
    "target": [0.5, 1.399999976, 0.000005],
    "size": 1.5,
}


class CaptureTimeout(RuntimeError):
    """Raised when one bounded Godot capture times out."""


class ReviewError(ValueError):
    """Raised when governed review input, evidence, or publication is invalid."""


@dataclass
class ValidatedTask:
    asset_id: str
    task_dir: Path
    cleaned_glb: Path
    validation_report: Path
    contract_hash: str
    cleaned_glb_hash: str
    cleaned_glb_overlay: Optional[Path] = None
    task_id: str = ""
    blender_validation_hash: str = ""
    cleaned_glb_size: int = 0
    category: str = ""
    bounds_dimensions: Optional[Tuple[float, float, float]] = None


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
    """Reject symlinked existing components for disposable workspace paths."""

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
        # /var and /tmp are the only macOS aliases intentionally accepted by
        # the shared governance layer.  The project itself must remain real.
        if stat.S_ISLNK(mode) and current not in (Path("/var"), Path("/tmp")):
            raise ValueError("{0} contains symlink component: {1}".format(label, current))


def _regular_file(path: Path, label: str, *, nonempty: bool = True) -> Path:
    _reject_symlink(path, label)
    try:
        info = path.lstat()
    except FileNotFoundError as exc:
        raise ReviewError("missing {0}: {1}".format(label, path)) from exc
    except OSError as exc:
        raise ReviewError("cannot inspect {0}: {1}".format(label, path)) from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ReviewError("{0} must be a regular file: {1}".format(label, path))
    if nonempty and info.st_size <= 0:
        raise ReviewError("{0} is empty: {1}".format(label, path))
    return path


def _regular_directory(path: Path, label: str) -> Path:
    _reject_symlink(path, label)
    try:
        info = path.lstat()
    except FileNotFoundError as exc:
        raise ReviewError("missing {0}: {1}".format(label, path)) from exc
    except OSError as exc:
        raise ReviewError("cannot inspect {0}: {1}".format(label, path)) from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise ReviewError("{0} must be a regular directory: {1}".format(label, path))
    return path


def _load_json(path: Path, label: str) -> Dict[str, Any]:
    try:
        document = json.loads(
            path.read_bytes().decode("utf-8"), object_pairs_hook=_reject_duplicate_keys
        )
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, RecursionError, ValueError) as exc:
        raise ReviewError("invalid JSON in {0}: {1}".format(label, exc)) from exc
    if not isinstance(document, dict):
        raise ReviewError("{0} must be a JSON object".format(label))
    return document


def validate_task_dir(task_dir: Path, contract: AssetContract) -> ValidatedTask:
    """Validate the fixed cleaned/report leaves for a disposable overlay.

    Full task governance is performed by ``_load_runtime_inputs``.  This small
    helper remains useful to callers that only construct an external overlay.
    """

    resolved_dir = _regular_directory(_absolute(task_dir), "task directory")
    cleaned_glb = _regular_file(resolved_dir / "cleaned.glb", "cleaned.glb")
    validation_path = _regular_file(
        resolved_dir / "blender-validation.json", "blender-validation.json"
    )
    validation = _load_json(validation_path, "blender-validation.json")
    try:
        from tools.meshy_blender_validate import _validate_report_record

        _validate_report_record(validation)
    except (ImportError, OSError, TypeError, ValueError, RuntimeError) as exc:
        raise ReviewError("Blender validation report is not canonical R4 evidence") from exc
    raw_validation = validation_path.read_bytes()
    cleaned_hash = hashlib.sha256(cleaned_glb.read_bytes()).hexdigest()
    if (
        validation.get("asset_id") != contract.asset_id
        or validation.get("contract_sha256") != contract.sha256
        or validation.get("sha256") != cleaned_hash
        or validation.get("byte_size") != cleaned_glb.stat().st_size
    ):
        raise ReviewError("Blender validation evidence does not match the cleaned.glb and contract")
    return ValidatedTask(
        asset_id=contract.asset_id,
        task_dir=resolved_dir,
        cleaned_glb=cleaned_glb,
        validation_report=validation_path,
        contract_hash=contract.sha256,
        cleaned_glb_hash=cleaned_hash,
        task_id=str(validation.get("task_id") or resolved_dir.name),
        blender_validation_hash=hashlib.sha256(raw_validation).hexdigest(),
        cleaned_glb_size=cleaned_glb.stat().st_size,
        category=str(contract.document.get("category", "")),
        bounds_dimensions=(
            float(validation["bounds"]["dimensions"][0]),
            float(validation["bounds"]["dimensions"][1]),
            float(validation["bounds"]["dimensions"][2]),
        ),
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
    if parts[:3] in (("artifacts", "validation-previews", "meshy"), ("assets", "_review", "meshy")):
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


def build_review_overlay(project_root: Path, inputs: ValidatedTask, destination: Path) -> Path:
    """Build an external project copy and mount the candidate below ``assets/_review``."""

    project = _regular_directory(_absolute(project_root), "project root")
    overlay = _absolute(destination)
    _reject_symlink(overlay, "overlay destination")
    if overlay.exists() or overlay.is_symlink():
        raise ReviewError("overlay destination already exists: {0}".format(overlay))
    overlay.mkdir(parents=True)
    _copy_project_regular_files(project, overlay)
    _copy_structural_runtime_files(project, overlay)
    # Imports are regenerated by the disposable editor prime; copying the
    # repository's potentially multi-gigabyte .godot cache is unnecessary.
    staged_path = review_overlay_path(overlay, inputs.asset_id) / "cleaned.glb"
    _copy_regular(inputs.cleaned_glb, staged_path, "cleaned.glb")
    inputs.cleaned_glb_overlay = staged_path
    return overlay


def _fixed_preview_path(root: Path, asset_id: str, supplied: Optional[Path] = None) -> Path:
    if IDENTIFIER_RE.fullmatch(asset_id) is None:
        raise ReviewError("asset_id must be a safe lowercase identifier")
    expected = _absolute(root) / PREVIEW_ROOT_RELATIVE / asset_id
    if supplied is not None and _absolute(supplied) != expected:
        raise ReviewError("preview directory must be the exact asset validation-preview leaf")
    try:
        governance.reject_protected_output(root, expected, "preview directory")
        governance._reject_symlink_components_below(_absolute(root), expected, "preview directory")
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        raise ReviewError(str(exc)) from exc
    if expected.exists() or expected.is_symlink():
        if expected.is_symlink() or not expected.is_dir():
            raise ReviewError("preview directory must be a regular directory")
        try:
            if stat.S_IMODE(expected.lstat().st_mode) != 0o700:
                raise ReviewError("preview directory must use mode 0700")
        except OSError as exc:
            raise ReviewError("preview directory could not be inspected") from exc
    return expected


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
        project_root = governance.physical_project_root(args.project_root)
        contract_path = _project_path(project_root, args.contract, "contract")
        task_dir = _project_path(project_root, args.task_dir, "task directory")
        caller_contract = load_contract(contract_path)
        preview_dir = _fixed_preview_path(
            project_root, caller_contract.asset_id, _project_path(project_root, args.preview_dir, "preview directory")
        )
        _reject_symlink(contract_path, "contract")
        _reject_symlink(task_dir, "task directory")
    except (OSError, TypeError, ValueError, ReviewError) as exc:
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


def _bounded_text(value: object) -> str:
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value or "")


def _cap_text(value: object) -> str:
    text = _bounded_text(value)
    encoded = text.encode("utf-8")
    if len(encoded) <= MAX_CAPTURED_OUTPUT_BYTES:
        return text
    marker = b"\n[output truncated]"
    return (encoded[: MAX_CAPTURED_OUTPUT_BYTES - len(marker)] + marker).decode(
        "utf-8", errors="replace"
    )


def _run_bounded_process(
    command: Sequence[str], *, cwd: Optional[Path] = None, timeout: float = CAPTURE_TIMEOUT_SECONDS
) -> Any:
    """Reuse the audited process-group runner used by Blender master review."""

    try:
        return _master_run_bounded_process(command, cwd=cwd or Path.cwd(), timeout=timeout)
    except CaptureTimeout:
        raise
    except Exception as exc:
        raise ReviewError("bounded Godot process failed: " + (str(exc) or exc.__class__.__name__)) from exc


def _check_process_output(result: Any) -> Tuple[str, str]:
    stdout = _bounded_text(getattr(result, "stdout", ""))
    stderr = _bounded_text(getattr(result, "stderr", ""))
    if len(stdout.encode("utf-8")) + len(stderr.encode("utf-8")) > MAX_CAPTURED_OUTPUT_BYTES:
        raise ReviewError("Godot capture output exceeded the bounded limit")
    return stdout, stderr


def _godot_render_args() -> Tuple[str, ...]:
    """Select a real renderer on macOS and retain headless portability elsewhere."""

    if sys.platform == "darwin":
        return ("--display-driver", "macos", "--rendering-method", "gl_compatibility")
    return ("--headless",)


def build_godot_command(
    overlay_root: Path,
    seed: int,
    lighting: str,
    output: Path,
    *,
    asset_id: Optional[str] = None,
    category: Optional[str] = None,
) -> list[str]:
    """Construct the exact no-shell bounded capture command."""

    capture_name(seed, lighting)
    command = [
        str(GODOT),
        *_godot_render_args(),
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
    if asset_id is not None or category is not None:
        if not isinstance(asset_id, str) or not isinstance(category, str):
            raise ReviewError("asset_id and category must be supplied together")
        command[10:10] = ["--asset-id", asset_id, "--category", category]
    return command


def _parse_finite_vector(value: str, label: str) -> list[float]:
    parts = value.split(",")
    if len(parts) != 3:
        raise ReviewError("camera {0} must contain three values".format(label))
    try:
        numbers = [float(part) for part in parts]
    except ValueError as exc:
        raise ReviewError("camera {0} is not numeric".format(label)) from exc
    if any(not math.isfinite(number) for number in numbers):
        raise ReviewError("camera {0} contains a non-finite value".format(label))
    return numbers


def _camera_size_limit(
    bounds_dimensions: Optional[Tuple[float, float, float]] = None,
) -> float:
    if bounds_dimensions is None:
        return CAMERA_SIZE_MAX
    diagonal = math.sqrt(sum(float(value) ** 2 for value in bounds_dimensions))
    if not math.isfinite(diagonal) or diagonal < 0.0:
        raise ReviewError("runtime GLB bounds dimensions are invalid")
    return min(CAMERA_SIZE_MAX, max(CAMERA_SIZE_MIN, diagonal * CAMERA_SIZE_DIMENSION_SCALE))


def _validate_camera_transform(
    value: object,
    *,
    bounds_dimensions: Optional[Tuple[float, float, float]] = None,
) -> Dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"projection", "position", "target", "size"}:
        raise ReviewError("camera transform is not canonical")
    if value.get("projection") != "orthogonal":
        raise ReviewError("camera projection is not orthogonal")
    vectors: Dict[str, list[float]] = {}
    for field in ("position", "target"):
        raw_values = value.get(field)
        if not isinstance(raw_values, list) or len(raw_values) != 3:
            raise ReviewError("camera transform vector is invalid")
        values = [float(item) for item in raw_values] if all(
            not isinstance(item, bool) and isinstance(item, (int, float)) for item in raw_values
        ) else []
        if len(values) != 3 or any(not math.isfinite(item) for item in values):
            raise ReviewError("camera transform vector is invalid")
        vectors[field] = values
    delta = [vectors["position"][index] - vectors["target"][index] for index in range(3)]
    distance = math.sqrt(sum(item * item for item in delta))
    if not math.isfinite(distance) or distance <= 1e-9:
        raise ReviewError("camera position and target must be distinct and finite")
    locked_length = math.sqrt(sum(item * item for item in LOCKED_CAMERA_DIRECTION))
    normalized = [item / distance for item in delta]
    locked = [item / locked_length for item in LOCKED_CAMERA_DIRECTION]
    if math.sqrt(sum((normalized[index] - locked[index]) ** 2 for index in range(3))) > LOCKED_CAMERA_DIRECTION_TOLERANCE:
        raise ReviewError("camera transform direction is not locked isometric")
    size = value.get("size")
    if isinstance(size, bool) or not isinstance(size, (int, float)):
        raise ReviewError("camera size is invalid")
    size = float(size)
    if not math.isfinite(size) or size < CAMERA_SIZE_MIN or size > _camera_size_limit(bounds_dimensions):
        raise ReviewError("camera size is outside the governed bound")
    return {
        "projection": "orthogonal",
        "position": vectors["position"],
        "target": vectors["target"],
        "size": size,
    }


def _validate_staged_visibility(value: object) -> Dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"pass", "opaque_pixels", "luma_range"}:
        raise ReviewError("staged visibility evidence is not canonical")
    opaque_pixels = value.get("opaque_pixels")
    luma_range = value.get("luma_range")
    if (
        value.get("pass") is not True
        or type(opaque_pixels) is not int
        or opaque_pixels < 2
        or opaque_pixels > STAGED_SAMPLE_MAX
        or isinstance(luma_range, bool)
        or not isinstance(luma_range, (int, float))
        or not math.isfinite(float(luma_range))
        or float(luma_range) < 0.004
        or float(luma_range) > 1.0
    ):
        raise ReviewError("staged visibility evidence is outside the strict pixel gate")
    return {
        "pass": True,
        "opaque_pixels": opaque_pixels,
        "luma_range": float(luma_range),
    }


def parse_capture_marker(stdout: str, seed: int, lighting: str) -> Dict[str, Any]:
    """Parse the exact marker and retain the camera values emitted by Godot."""

    if not isinstance(stdout, str):
        raise ReviewError("Godot capture output must be text")
    expected = "{0} seed={1} lighting={2} ".format(CAPTURE_MARKER, seed, lighting)
    lines = [line.strip() for line in stdout.splitlines() if expected in line]
    if len(lines) != 1:
        raise ReviewError("Godot capture did not emit exactly one camera marker")
    line = lines[0]
    pattern = re.compile(
        r"^" + re.escape(expected)
        + r"camera_position=(?P<position>[^ ]+) camera_target=(?P<target>[^ ]+) "
        + r"camera_size=(?P<size>[^ ]+) "
        + r"staged_visibility=(?P<visibility>pass|fail) "
        + r"staged_opaque_pixels=(?P<pixels>[0-9]+) "
        + r"staged_luma_range=(?P<luma>[^ ]+)"
        + r"(?: output=(?P<output>.+))?$"
    )
    match = pattern.fullmatch(line)
    if match is None:
        raise ReviewError("Godot capture marker is not canonical")
    try:
        size = float(match.group("size"))
    except ValueError as exc:
        raise ReviewError("camera size is not numeric") from exc
    try:
        opaque_pixels = int(match.group("pixels"))
        luma_range = float(match.group("luma"))
    except ValueError as exc:
        raise ReviewError("staged visibility evidence is not numeric") from exc
    staged_visibility = _validate_staged_visibility(
        {
            "pass": match.group("visibility") == "pass",
            "opaque_pixels": opaque_pixels,
            "luma_range": luma_range,
        }
    )
    camera_transform = _validate_camera_transform(
        {
            "projection": "orthogonal",
            "position": _parse_finite_vector(match.group("position"), "position"),
            "target": _parse_finite_vector(match.group("target"), "target"),
            "size": size,
        }
    )
    camera_transform["staged_visibility"] = staged_visibility
    return {
        **camera_transform,
    }


def _prime_overlay_imports(overlay_root: Path) -> None:
    """Populate disposable imports using a fixed dummy MCP token."""

    command = [
        "/usr/bin/env",
        "GODOT_MCP_TOKEN=" + ("x" * 32),
        str(GODOT),
        *_godot_render_args(),
        "--quiet",
        "--editor",
        "--path",
        str(_absolute(overlay_root)),
        "--quit",
    ]
    last_output = ""
    for _attempt in range(2):
        result = _run_bounded_process(command, cwd=overlay_root)
        stdout, stderr = _check_process_output(result)
        combined = "\n".join((stdout, stderr))
        last_output = combined
        if getattr(result, "returncode", 1) != 0:
            raise ReviewError("overlay import failed exit={0}: {1}".format(result.returncode, _cap_text(combined)))
        if not any(marker in combined for marker in DIAGNOSTIC_MARKERS):
            return
    raise ReviewError("overlay import emitted a diagnostic: {0}".format(_cap_text(last_output)))


def check_capture_output(stdout: str, stderr: str, seed: int, lighting: str) -> bool:
    """Accept only a canonical marker with no diagnostics or unbounded output."""

    try:
        stdout_text, stderr_text = _check_process_output(
            type("Result", (), {"stdout": stdout, "stderr": stderr})()
        )
    except ReviewError:
        return False
    combined = "\n".join((stdout_text, stderr_text))
    if any(marker in combined for marker in DIAGNOSTIC_MARKERS):
        return False
    marker = "{0} seed={1} lighting={2} ".format(CAPTURE_MARKER, seed, lighting)
    try:
        parse_capture_marker(stdout_text, seed, lighting)
    except ReviewError:
        return False
    return marker in stdout_text


def _png_chunks(raw: bytes, path: Path) -> Tuple[int, int, int, bytes]:
    if not raw.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ReviewError("capture is not a PNG: {0}".format(path))
    offset = 8
    width = height = bit_depth = color_type = None
    idat: list[bytes] = []
    saw_iend = False
    while offset + 12 <= len(raw):
        length = int.from_bytes(raw[offset : offset + 4], "big")
        kind = raw[offset + 4 : offset + 8]
        end = offset + 12 + length
        if end > len(raw):
            raise ReviewError("capture PNG has a truncated chunk: {0}".format(path))
        payload = raw[offset + 8 : offset + 8 + length]
        crc = int.from_bytes(raw[offset + 8 + length : end], "big")
        if (binascii.crc32(kind + payload) & 0xFFFFFFFF) != crc:
            raise ReviewError("capture PNG has an invalid chunk checksum: {0}".format(path))
        if kind == b"IHDR":
            if length != 13 or width is not None:
                raise ReviewError("capture PNG has an invalid IHDR: {0}".format(path))
            width = int.from_bytes(payload[0:4], "big")
            height = int.from_bytes(payload[4:8], "big")
            bit_depth = payload[8]
            color_type = payload[9]
            if payload[10:] != b"\x00\x00\x00":
                raise ReviewError("capture PNG uses unsupported compression/filter/interlace")
        elif kind == b"IDAT":
            idat.append(payload)
        elif kind == b"IEND":
            if length != 0:
                raise ReviewError("capture PNG has a non-empty IEND")
            saw_iend = True
            offset = end
            break
        offset = end
    if offset != len(raw) or width is None or height is None or not idat or not saw_iend:
        raise ReviewError("capture PNG is incomplete: {0}".format(path))
    if (width, height) != CAPTURE_SIZE or bit_depth != 8 or color_type not in (2, 4, 6):
        raise ReviewError("capture PNG is not an 8-bit {0}x{1} image: {2}".format(*CAPTURE_SIZE, path))
    try:
        decoded = zlib.decompress(b"".join(idat))
    except zlib.error as exc:
        raise ReviewError("capture PNG image data is invalid: {0}".format(path)) from exc
    return width, height, color_type, decoded


def _validate_png(path: Path) -> None:
    _regular_file(path, "capture PNG")
    _png_chunks(path.read_bytes(), path)


def _png_is_visible(path: Path) -> bool:
    """Apply the same conservative nonblank gate used by the Godot capture."""

    width, height, color_type, decoded = _png_chunks(path.read_bytes(), path)
    channels = {2: 3, 4: 2, 6: 4}[color_type]
    row_bytes = width * channels
    expected = height * (row_bytes + 1)
    if len(decoded) != expected:
        raise ReviewError("capture PNG scanlines are invalid: {0}".format(path))
    previous = bytearray(row_bytes)
    samples: list[Tuple[float, float]] = []
    for y in range(height):
        filter_type = decoded[y * (row_bytes + 1)]
        source = decoded[y * (row_bytes + 1) + 1 : (y + 1) * (row_bytes + 1)]
        row = bytearray(row_bytes)
        for index, value in enumerate(source):
            left = row[index - channels] if index >= channels else 0
            up = previous[index]
            upper_left = previous[index - channels] if index >= channels else 0
            if filter_type == 0:
                result = value
            elif filter_type == 1:
                result = (value + left) & 0xFF
            elif filter_type == 2:
                result = (value + up) & 0xFF
            elif filter_type == 3:
                result = (value + ((left + up) // 2)) & 0xFF
            elif filter_type == 4:
                estimate = left + up - upper_left
                pa = abs(estimate - left)
                pb = abs(estimate - up)
                pc = abs(estimate - upper_left)
                predictor = left if pa <= pb and pa <= pc else up if pb <= pc else upper_left
                result = (value + predictor) & 0xFF
            else:
                raise ReviewError("capture PNG uses an unknown filter: {0}".format(path))
            row[index] = result
        if y in {0, height // 8, height // 4, height // 2, (3 * height) // 4, height - 1}:
            for x in range(0, width, max(1, width // 32)):
                pixel = row[x * channels : (x + 1) * channels]
                alpha = float(pixel[-1]) / 255.0 if color_type in (4, 6) else 1.0
                if color_type == 6:
                    rgb = pixel[:3]
                elif color_type == 4:
                    rgb = pixel[:1] * 3
                else:
                    rgb = pixel[:3]
                luma = (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255.0
                samples.append((luma, alpha))
        previous = row
    visible = [luma for luma, alpha in samples if alpha >= 0.05]
    if len(visible) < max(2, len(samples) // 8):
        return False
    return max(visible) - min(visible) >= 0.004


def run_capture(
    overlay_root: Path,
    asset_id: str,
    category: str,
    seed: int,
    lighting: str,
    output: Path,
) -> Dict[str, Any]:
    command = build_godot_command(
        overlay_root, seed, lighting, output, asset_id=asset_id, category=category
    )
    result = _run_bounded_process(command, cwd=overlay_root)
    stdout, stderr = _check_process_output(result)
    if getattr(result, "returncode", 1) != 0:
        raise ReviewError(
            "Godot capture failed seed={0} lighting={1} exit={2}: {3}".format(
                seed, lighting, result.returncode, _cap_text(stderr or stdout)
            )
        )
    if not check_capture_output(stdout, stderr, seed, lighting):
        raise ReviewError(
            "Godot capture emitted an unexpected marker or diagnostic seed={0} lighting={1}: {2}".format(
                seed, lighting, _cap_text(stdout + "\n" + stderr)
            )
        )
    camera_transform = parse_capture_marker(stdout, seed, lighting)
    staged_visibility = camera_transform.pop("staged_visibility")
    _validate_png(output)
    if not _png_is_visible(output):
        raise ReviewError("Godot capture is blank or near-uniform")
    return {
        "seed": seed,
        "lighting": lighting,
        "camera_transform": camera_transform,
        "staged_visibility": staged_visibility,
        "output_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "pass": True,
        "reason": "pass",
    }


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
    """Build the historical per-capture helper record.

    New runtime runs use the closed ``CAPTURE_FIELDS`` record built by
    ``run_capture``; this helper remains source-compatible for older callers.
    """

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
    by_key: Dict[Tuple[int, str], Mapping[str, Any]] = {}
    for item in captures:
        if set(item) != CAPTURE_FIELDS:
            raise ReviewError("runtime capture fields are not canonical")
        seed = item.get("seed")
        lighting = item.get("lighting")
        if type(seed) is not int or not isinstance(lighting, str):
            raise ReviewError("runtime capture identity is invalid")
        capture_name(seed, lighting)
        _validate_camera_transform(
            item.get("camera_transform"),
            bounds_dimensions=inputs.bounds_dimensions,
        )
        _validate_staged_visibility(item.get("staged_visibility"))
        key = (seed, lighting)
        if key in by_key:
            raise ReviewError("duplicate runtime capture")
        by_key[key] = item
    if set(by_key) != set(expected):
        raise ReviewError("runtime review requires exactly six captures")
    ordered = [by_key[key] for key in expected]
    if any(item.get("pass") is not True or item.get("reason") != "pass" for item in ordered):
        raise ReviewError("runtime review cannot publish failed captures")
    task_id = inputs.task_id or inputs.task_dir.name
    if TASK_ID_RE.fullmatch(task_id) is None:
        raise ReviewError("runtime task_id is invalid")
    if not HASH_RE.fullmatch(inputs.contract_hash) or not HASH_RE.fullmatch(inputs.cleaned_glb_hash):
        raise ReviewError("runtime input hashes are invalid")
    if not HASH_RE.fullmatch(inputs.blender_validation_hash):
        raise ReviewError("runtime Blender validation hash is invalid")
    output_hashes = {
        capture_name(int(item["seed"]), str(item["lighting"])): str(item["output_sha256"])
        for item in ordered
    }
    if any(not HASH_RE.fullmatch(value) for value in output_hashes.values()):
        raise ReviewError("runtime capture hash is invalid")
    return {
        "schema_version": SCHEMA_VERSION,
        "document_kind": DOCUMENT_KIND,
        "asset_id": inputs.asset_id,
        "task_id": task_id,
        "contract_sha256": inputs.contract_hash,
        "cleaned_glb_sha256": inputs.cleaned_glb_hash,
        "blender_validation_sha256": inputs.blender_validation_hash,
        "seeds": list(SEEDS),
        "lighting": list(LIGHTING_MODES),
        "captures": [dict(item) for item in ordered],
        "output_hashes": output_hashes,
        "pass": True,
        "reason": "pass",
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


def _output_entries(destination: Path) -> list[str]:
    if not destination.exists():
        return []
    if destination.is_symlink() or not destination.is_dir():
        raise ReviewError("preview directory is not a regular directory")
    try:
        return sorted(entry.name for entry in os.scandir(destination))
    except OSError as exc:
        raise ReviewError("preview directory could not be read") from exc


def _validate_existing_leaf(path: Path, expected: Optional[bytes], label: str) -> None:
    if not os.path.lexists(path):
        return
    try:
        info = path.lstat()
    except OSError as exc:
        raise ReviewError("cannot inspect existing {0}".format(label)) from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise ReviewError("existing {0} must be a regular file".format(label))
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise ReviewError("existing {0} must use mode 0600".format(label))
    if expected is not None and path.read_bytes() != expected:
        raise ReviewError("existing {0} differs from the requested evidence".format(label))


def snapshot_runtime_surfaces(project_root: Path) -> tuple[Any, ...]:
    """Use the shared immutable protected-surface authority."""

    try:
        return governance.snapshot_protected_surfaces(
            _absolute(project_root),
            max_file_bytes=PROTECTED_SNAPSHOT_MAX_FILE_BYTES,
            max_total_bytes=PROTECTED_SNAPSHOT_MAX_TOTAL_BYTES,
            max_entries=PROTECTED_SNAPSHOT_MAX_ENTRIES,
            max_depth=PROTECTED_SNAPSHOT_MAX_DEPTH,
        )
    except (OSError, TypeError, ValueError, RuntimeError) as exc:
        raise ReviewError("protected runtime snapshot failed: " + str(exc)) from exc


def _load_runtime_inputs(
    project_root: Path, contract_path: Optional[Path], task_dir: Path
) -> Tuple[ValidatedTask, Dict[str, Any], Dict[str, Any], Path]:
    """Load the only permitted task, contract, generation, and R4 evidence."""

    try:
        from tools import meshy_candidate_review as candidate_review

        review_path, review, generation, root, _asset_root = candidate_review._load_task_record(
            project_root, task_dir
        )
        resolved_task = Path(review_path).parent
        task_contract_path = candidate_review._governed_artifact(root, resolved_task, "contract.json")
        for private_path, private_label in (
            (review_path, "review.json"),
            (task_contract_path, "contract.json"),
            (candidate_review._governed_artifact(root, resolved_task, "generation.json"), "generation.json"),
        ):
            if private_path.lstat().st_mode & 0o077:
                raise ReviewError("task {0} must be private".format(private_label))
        task_contract, task_contract_raw = governance.strict_load_json_bytes(
            task_contract_path, "task contract", 4 * 1024 * 1024
        )
        if task_contract_raw != canonical_json_bytes(task_contract):
            raise ReviewError("task contract is not canonical JSON")
        task_contract_model = load_contract(task_contract_path)
        if review.get("state") not in ("selected", "promotion_ready"):
            raise ReviewError("runtime review requires a selected or promotion_ready candidate")
        if generation.get("status") != "SUCCEEDED":
            raise ReviewError("runtime review requires SUCCEEDED generation evidence")
        if generation.get("asset_id") != task_contract_model.asset_id or generation.get("task_id") != resolved_task.name:
            raise ReviewError("generation identity is not bound to the task")
        if generation.get("contract_artifact_sha256") != hashlib.sha256(task_contract_raw).hexdigest():
            raise ReviewError("generation contract artifact is not bound")
        caller = load_contract(contract_path) if contract_path is not None else task_contract_model
        if caller.snapshot_bytes() != task_contract_model.snapshot_bytes():
            raise ReviewError("caller contract does not match task-local contract")
        if contract_path is not None and generation.get("contract_sha256") != caller.sha256:
            raise ReviewError("generation contract hash is not bound to caller contract")
        if contract_path is None:
            if generation.get("contract_sha256") != task_contract_model.sha256:
                raise ReviewError("generation contract hash is not bound to the task-local contract")
        bound_contract_hash = task_contract_model.sha256
        cleaned = candidate_review._governed_artifact(root, resolved_task, "cleaned.glb")
        r4_path = candidate_review._governed_artifact(root, resolved_task, "blender-validation.json")
        cleaned_info = cleaned.lstat()
        if stat.S_ISLNK(cleaned_info.st_mode) or not stat.S_ISREG(cleaned_info.st_mode) or cleaned_info.st_size <= 0:
            raise ReviewError("cleaned.glb must be a bounded regular file")
        cleaned_hash = governance.file_sha256(cleaned)
        r4, r4_raw = governance.strict_load_json_bytes(
            r4_path, "Blender validation report", 4 * 1024 * 1024
        )
        if r4_raw != canonical_json_bytes(r4):
            raise ReviewError("Blender validation report is not canonical JSON")
        from tools import meshy_blender_validate as blender_validate

        try:
            expected_r4 = blender_validate.verify_validation_report(
                cleaned, task_contract_path, r4, task_id=resolved_task.name
            )
        except (OSError, TypeError, ValueError, RuntimeError) as exc:
            raise ReviewError("R4 Blender evidence does not match the current task: " + str(exc)) from exc
        inputs = ValidatedTask(
            asset_id=task_contract_model.asset_id,
            task_id=resolved_task.name,
            task_dir=resolved_task,
            cleaned_glb=cleaned,
            validation_report=r4_path,
            contract_hash=bound_contract_hash,
            cleaned_glb_hash=cleaned_hash,
            blender_validation_hash=hashlib.sha256(r4_raw).hexdigest(),
            cleaned_glb_size=cleaned_info.st_size,
            category=str(task_contract_model.document.get("category", "")),
            bounds_dimensions=(
                float(expected_r4["bounds"]["dimensions"][0]),
                float(expected_r4["bounds"]["dimensions"][1]),
                float(expected_r4["bounds"]["dimensions"][2]),
            ),
        )
        return inputs, review, generation, root
    except ReviewError:
        raise
    except (OSError, TypeError, ValueError, RuntimeError, RecursionError) as exc:
        raise ReviewError("runtime task evidence is not fully governed: " + str(exc)) from exc


def _validate_runtime_document(
    document: Mapping[str, Any], inputs: ValidatedTask
) -> Dict[str, Any]:
    if not isinstance(document, dict):
        raise ReviewError("runtime review document must be an object")
    stack: list[Tuple[Any, int]] = [(document, 0)]
    seen: set[int] = set()
    while stack:
        current, depth = stack.pop()
        if depth > 64:
            raise ReviewError("runtime review JSON maximum nesting depth exceeded")
        if isinstance(current, (dict, list)):
            identity = id(current)
            if identity in seen:
                raise ReviewError("runtime review JSON contains a cyclic value")
            seen.add(identity)
            if isinstance(current, dict):
                for key, value in current.items():
                    if not isinstance(key, str):
                        raise ReviewError("runtime review JSON keys must be strings")
                    stack.append((value, depth + 1))
            else:
                stack.extend((value, depth + 1) for value in current)
    if set(document) != RUNTIME_DOCUMENT_FIELDS:
        raise ReviewError("runtime review document fields are not canonical")
    if (
        document.get("schema_version") != SCHEMA_VERSION
        or document.get("document_kind") != DOCUMENT_KIND
        or document.get("asset_id") != inputs.asset_id
        or document.get("task_id") != (inputs.task_id or inputs.task_dir.name)
        or document.get("contract_sha256") != inputs.contract_hash
        or document.get("cleaned_glb_sha256") != inputs.cleaned_glb_hash
        or document.get("blender_validation_sha256") != inputs.blender_validation_hash
        or document.get("seeds") != list(SEEDS)
        or document.get("lighting") != list(LIGHTING_MODES)
        or document.get("pass") is not True
        or document.get("reason") != "pass"
    ):
        raise ReviewError("runtime review document identity or gate is invalid")
    if not HASH_RE.fullmatch(str(document["contract_sha256"])) or not HASH_RE.fullmatch(str(document["cleaned_glb_sha256"])) or not HASH_RE.fullmatch(str(document["blender_validation_sha256"])):
        raise ReviewError("runtime review input hashes are invalid")
    captures = document.get("captures")
    if not isinstance(captures, list) or len(captures) != 6:
        raise ReviewError("runtime review must contain six captures")
    expected = [(seed, lighting) for seed in SEEDS for lighting in LIGHTING_MODES]
    by_key: Dict[Tuple[int, str], Mapping[str, Any]] = {}
    for item in captures:
        if not isinstance(item, dict) or set(item) != CAPTURE_FIELDS:
            raise ReviewError("runtime capture fields are not canonical")
        seed = item.get("seed")
        lighting = item.get("lighting")
        if type(seed) is not int or lighting not in LIGHTING_MODES:
            raise ReviewError("runtime capture identity is invalid")
        key = (seed, str(lighting))
        if key in by_key:
            raise ReviewError("runtime review contains duplicate capture")
        by_key[key] = item
        if item.get("pass") is not True or item.get("reason") != "pass":
            raise ReviewError("runtime review contains a failed capture")
        output_sha = item.get("output_sha256")
        if not isinstance(output_sha, str) or HASH_RE.fullmatch(output_sha) is None:
            raise ReviewError("runtime capture output hash is invalid")
        _validate_camera_transform(
            item.get("camera_transform"),
            bounds_dimensions=inputs.bounds_dimensions,
        )
        _validate_staged_visibility(item.get("staged_visibility"))
    if set(by_key) != set(expected):
        raise ReviewError("runtime review capture identity is invalid")
    if [(item["seed"], item["lighting"]) for item in captures] != expected:
        raise ReviewError("runtime review capture order is not canonical")
    output_hashes = document.get("output_hashes")
    if not isinstance(output_hashes, dict) or set(output_hashes) != set(FIXED_OUTPUT_NAMES[:-1]):
        raise ReviewError("runtime output hash map is not canonical")
    for seed, lighting in expected:
        name = capture_name(seed, lighting)
        if output_hashes.get(name) != by_key[(seed, lighting)].get("output_sha256"):
            raise ReviewError("runtime output hash map does not match captures")
    return dict(document)


def verify_evidence_chain(
    project_root: Path, task_dir: Path
) -> Dict[str, Any]:
    """Verify only evidence derived from the fixed governed task/report/leaves."""

    inputs, _review, _generation, root = _load_runtime_inputs(project_root, None, task_dir)
    destination = _fixed_preview_path(root, inputs.asset_id)
    entries = _output_entries(destination)
    if sorted(entries) != sorted(FIXED_OUTPUT_NAMES):
        raise ReviewError("fixed runtime preview directory is incomplete or has unexpected entries")
    report_path = destination / "runtime-review.json"
    try:
        document, raw = governance.strict_load_json_bytes(
            report_path, "runtime-review.json", 4 * 1024 * 1024
        )
    except (OSError, TypeError, ValueError, RecursionError) as exc:
        raise ReviewError("runtime-review.json is invalid") from exc
    if raw != canonical_json_bytes(document) or stat.S_IMODE(report_path.lstat().st_mode) != 0o600:
        raise ReviewError("runtime-review.json is not canonical mode-0600 evidence")
    _validate_runtime_document(document, inputs)
    for seed, lighting in ((seed, lighting) for seed in SEEDS for lighting in LIGHTING_MODES):
        path = destination / capture_name(seed, lighting)
        _validate_existing_leaf(path, None, "capture " + path.name)
        capture_bytes = path.read_bytes()
        _validate_png(path)
        if not _png_is_visible(path):
            raise ReviewError("runtime capture is blank or near-uniform: " + path.name)
        if hashlib.sha256(capture_bytes).hexdigest() != document["output_hashes"][path.name]:
            raise ReviewError("runtime capture hash does not match report: " + path.name)
    return document


def _compare_surfaces(before: tuple[Any, ...], root: Path, label: str) -> None:
    after = snapshot_runtime_surfaces(root)
    if after != before:
        raise ReviewError("protected runtime surfaces changed " + label)


def run(args: argparse.Namespace) -> RunResult:
    """Run the complete governed review, bind evidence, and publish no runtime asset."""

    primary: Optional[BaseException] = None
    result: Optional[RunResult] = None
    try:
        before = snapshot_runtime_surfaces(args.project_root)
        inputs, _review, _generation, root = _load_runtime_inputs(
            args.project_root, args.contract, args.task_dir
        )
        _fixed_preview_path(root, inputs.asset_id, args.preview_dir)
        if args.dry_run:
            _compare_surfaces(before, root, "during dry-run")
            result = RunResult(0, "dry-run validation passed; no outputs written", dry_run=True)
        else:
            def publish_fixed_captures() -> Path:
                """Publish only this run's real captures, report last."""

                expected_keys = {(seed, lighting) for seed in SEEDS for lighting in LIGHTING_MODES}
                normalised = _normalise_capture_mapping(captures)
                if set(normalised) != expected_keys:
                    raise ReviewError("runtime review requires all six captures before publication")
                if set(document) != RUNTIME_DOCUMENT_FIELDS or document.get("pass") is not True:
                    raise ReviewError("runtime review report is not canonical PASS")
                destination = _fixed_preview_path(root, inputs.asset_id)
                if destination.exists():
                    entries = _output_entries(destination)
                    if any(entry not in FIXED_OUTPUT_NAMES for entry in entries):
                        raise ReviewError("preview directory contains an unexpected entry")
                payloads: Dict[str, bytes] = {}
                for key, source in normalised.items():
                    _validate_png(source)
                    payloads[capture_name(*key)] = source.read_bytes()
                report_bytes = canonical_json_bytes(document)
                report_path = destination / "runtime-review.json"

                # An existing report is authoritative.  It is reusable only if
                # every fixed byte, mode, and canonical field still matches.
                if os.path.lexists(report_path):
                    _validate_existing_leaf(report_path, report_bytes, "runtime-review.json")
                    try:
                        persisted, raw = governance.strict_load_json_bytes(
                            report_path, "runtime runtime-review.json", 4 * 1024 * 1024
                        )
                    except (OSError, TypeError, ValueError, RecursionError) as exc:
                        raise ReviewError("existing runtime-review.json is invalid") from exc
                    if raw != report_bytes or persisted != document:
                        raise ReviewError("existing runtime-review.json differs from the requested evidence")
                    for name, payload in payloads.items():
                        _validate_existing_leaf(destination / name, payload, "capture " + name)
                    if sorted(_output_entries(destination)) != sorted(FIXED_OUTPUT_NAMES):
                        raise ReviewError("authoritative preview directory is incomplete")
                    return destination

                # Validate all pre-existing leaves before writing any new leaf.
                for name, payload in payloads.items():
                    _validate_existing_leaf(destination / name, payload, "capture " + name)

                try:
                    for name in FIXED_OUTPUT_NAMES[:-1]:
                        target = destination / name
                        if os.path.lexists(target):
                            continue
                        governance.atomic_write_bytes(
                            target,
                            payloads[name],
                            project_root=root,
                            allowed_root=destination,
                            mode=0o600,
                        )
                    # The report is deliberately the last public write.
                    governance.atomic_write_json(
                        report_path,
                        document,
                        project_root=root,
                        allowed_root=destination,
                        mode=0o600,
                    )
                except (OSError, TypeError, ValueError, RuntimeError) as exc:
                    raise ReviewError("runtime evidence publication failed: " + str(exc)) from exc

                _validate_existing_leaf(report_path, report_bytes, "runtime-review.json")
                try:
                    persisted, raw = governance.strict_load_json_bytes(
                        report_path, "published runtime-review.json", 4 * 1024 * 1024
                    )
                except (OSError, TypeError, ValueError, RecursionError) as exc:
                    raise ReviewError("published runtime-review.json is invalid") from exc
                if raw != report_bytes or persisted != document:
                    raise ReviewError("published runtime-review.json was not exact")
                for name, payload in payloads.items():
                    _validate_existing_leaf(destination / name, payload, "capture " + name)
                return destination

            category = inputs.category
            captures: Dict[Tuple[int, str], Path] = {}
            capture_records = []
            with tempfile.TemporaryDirectory(prefix="meshy-runtime-review-") as temporary:
                overlay_root = Path(temporary) / "project"
                build_review_overlay(args.project_root, inputs, overlay_root)
                _prime_overlay_imports(overlay_root)
                capture_root = Path(temporary) / "captures"
                capture_root.mkdir()
                for seed in SEEDS:
                    for lighting in LIGHTING_MODES:
                        output = capture_root / capture_name(seed, lighting)
                        capture_records.append(
                            run_capture(
                                overlay_root, inputs.asset_id, category, seed, lighting, output
                            )
                        )
                        captures[(seed, lighting)] = output
                _compare_surfaces(before, root, "before publication")
                document = build_runtime_review_document(inputs, capture_records)
                destination = publish_fixed_captures()
                _compare_surfaces(before, root, "after capture publication")
            from tools import meshy_candidate_review as candidate_review

            bound = candidate_review.bind_promotion_evidence(root, inputs.task_dir)
            if bound.get("state") != "promotion_ready":
                raise ReviewError("evidence binder did not produce promotion_ready")
            candidate_review.verify_review(root, inputs.task_dir)
            _compare_surfaces(before, root, "after evidence binding")
            result = RunResult(0, "runtime review passed and evidence bound", destination / "runtime-review.json")
    except (CaptureTimeout, OSError, ReviewError, ValueError, RuntimeError, TypeError) as exc:
        primary = exc
    finally:
        try:
            if "before" in locals():
                final = snapshot_runtime_surfaces(args.project_root)
                if final != before and primary is None:
                    primary = ReviewError("protected runtime surfaces changed during final review check")
        except (OSError, TypeError, ValueError, RuntimeError) as exc:
            if primary is None:
                primary = ReviewError("final protected runtime snapshot failed: " + str(exc))
    if primary is not None:
        return RunResult(1, str(primary) or primary.__class__.__name__)
    if result is None:
        return RunResult(1, "runtime review did not produce a result")
    return result


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    result = run(args)
    if result.success:
        if result.dry_run:
            print("MESHY RUNTIME REVIEW DRY-RUN PASS")
        else:
            print(
                "MESHY RUNTIME REVIEW PASS asset={0} task_id={1} seeds=42,777 "
                "lighting=normal,emergency,dark captures=6".format(
                    args.contract.read_text(encoding="utf-8") and load_contract(args.contract).asset_id,
                    args.task_dir.name,
                )
            )
        return 0
    print("meshy_runtime_review: " + result.reason, file=sys.stderr)
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
