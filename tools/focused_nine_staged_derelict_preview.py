#!/usr/bin/env python3
"""Capture a staged-only, runtime-generated derelict preview.

The runner is intentionally disposable: staged focused-nine inputs are
preflighted, copied as regular files into an external Godot overlay at the
production wrapper/import paths, and never promoted into the checkout. The
capture itself runs the real procgen scripts and publishes the PNG/proof pair
only after protected runtime surfaces are proven unchanged.

Trusted-workspace boundary: path observations and no-follow checks do not pin a
same-user namespace against a concurrent rename/rebind. The external overlay
and atomic publication are defense in depth, not descriptor-level race
immunity.
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
import struct
import subprocess
import sys
import tempfile
import zlib
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

try:
    from tools import focused_nine_batch as batch
    from tools import focused_nine_contract as contract
    from tools import focused_nine_staged_props as staged_props
    from tools import focused_nine_staged_structural as staged_structural
except ModuleNotFoundError:  # pragma: no cover - direct script execution
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools import focused_nine_batch as batch
    from tools import focused_nine_contract as contract
    from tools import focused_nine_staged_props as staged_props
    from tools import focused_nine_staged_structural as staged_structural


GODOT = Path(os.environ.get("GODOT", "/opt/homebrew/bin/godot"))
CAPTURE_TIMEOUT_SECONDS = 120.0
MAX_CAPTURED_OUTPUT_BYTES = 64 * 1024
CAPTURE_SCENE = "res://scenes/validation/focused_nine_staged_derelict_harness.tscn"
CAPTURE_SCENE_RELATIVE = Path("scenes/validation/focused_nine_staged_derelict_harness.tscn")
CAPTURE_SCRIPT_RELATIVE = Path("scripts/validation/focused_nine_staged_derelict_capture.gd")
CAPTURE_OUTPUT_RELATIVE = Path("artifacts/validation-previews/focused-nine")
CAPTURE_IMAGE_NAME = "focused-nine-staged-derelict.png"
DEBUG_BUNDLE_NAME = "edge_map.json"
PROOF_RELATIVE = Path("docs/superpowers/proofs/focused-nine-staged-derelict.md")
STAGED_ROOT_RELATIVE = Path("assets/_staging/focused_nine")
CANONICAL_IMPORTED_RELATIVE = Path("assets/imported/structural/ship_structural_v0")
CANONICAL_PROP_IMPORTED_RELATIVE = Path("assets/imported/props")
COMPARISON_REPORT_NAME = "focused-nine-comparison.json"
CAPTURE_MARKER_PREFIX = "FOCUSED_NINE_STAGED_DERELICT_CAPTURE PASS "
PREVIEW_MARKER_PREFIX = "FOCUSED_NINE_STAGED_DERELICT_PREVIEW PASS "
DIAGNOSTIC_MARKERS = ("WARNING:", "ERROR:", "SCRIPT ERROR:")
DEBUG_BUNDLE_SCHEMA = "focused_nine_canonical_edge_map_v1"
DEBUG_CAPTURE_ID = "StagedFocusedNine"
PRIVATE_DIRECTORY_MODE = 0o700
PRIVATE_FILE_MODE = 0o600
PRESSURE_ROLES = ("intact", "damaged", "breached")
NON_PRESSURE_ROLES = ("intact", "damaged", "breached")


class CaptureTimeout(RuntimeError):
    """A bounded capture process exceeded its timeout."""

    def __init__(self, message: str, stdout: str = "", stderr: str = "") -> None:
        super().__init__(message)
        self.stdout = stdout
        self.stderr = stderr


class PublicationError(RuntimeError):
    """The preview/proof pair could not be published transactionally."""


@dataclass(frozen=True)
class ValidatedInputs:
    paths: tuple[Path, ...]
    staged_hashes: tuple[tuple[str, str], ...] = ()


@dataclass(frozen=True)
class RunResult:
    exit_code: int
    reason: str = ""
    path: Path | None = None
    dry_run: bool = False

    @property
    def success(self) -> bool:
        return self.exit_code == 0


@dataclass(frozen=True)
class _PriorLeaf:
    existed: bool
    payload: bytes | None


@dataclass(frozen=True)
class _CaptureMetadata:
    seed: int
    room_count: int
    placement_count: int
    wall_count: int
    portal_count: int
    staged_wrapper_count: int
    staged_input_count: int
    debug_bundle: str
    output: str


# The exact runtime surfaces are shared with the established focused-nine
# batch helper. This makes the no-diff fence cover the live imported/wrapper,
# kit, and generated prop surfaces without duplicating that contract here.
def snapshot_runtime_surfaces(project_root: Path) -> tuple[tuple[str, str, int | None, str | None], ...]:
    return batch.snapshot_runtime_surfaces(project_root)


def _raw_path(value: Path | str, label: str) -> Path:
    path = Path(value).expanduser()
    if ".." in path.parts:
        raise ValueError(f"{label} must not contain traversal: {path}")
    return path if path.is_absolute() else Path.cwd() / path


def _absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(path)))


def _safe_system_alias(path: Path) -> bool:
    return path == Path("/var")


def _symlink_components(path: Path) -> Iterator[Path]:
    absolute = _absolute(path)
    current = Path(absolute.anchor)
    for part in absolute.parts[1:]:
        current /= part
        try:
            mode = current.lstat().st_mode
        except FileNotFoundError:
            break
        except OSError as exc:
            raise ValueError(f"cannot inspect path component {current}") from exc
        if stat.S_ISLNK(mode) and not _safe_system_alias(current):
            yield current


def _reject_static_symlink_components(path: Path, label: str) -> None:
    aliases = tuple(_symlink_components(path))
    if aliases:
        raise ValueError(f"{label} contains symlink component: {aliases[0]}")


def _canonical_project_root(value: Path | str) -> Path:
    lexical = _raw_path(value, "project root")
    _reject_static_symlink_components(lexical, "project root")
    resolved = lexical.resolve(strict=False)
    if not resolved.is_dir():
        raise ValueError(f"project root is not a directory: {lexical}")
    return resolved


def _canonical_staging_root(project_root: Path, value: Path | str) -> Path:
    lexical = _raw_path(value, "staging root")
    _reject_static_symlink_components(lexical, "staging root")
    resolved = lexical.resolve(strict=False)
    expected = project_root / STAGED_ROOT_RELATIVE
    if resolved != expected:
        if resolved == project_root / "assets/imported" or project_root / "assets/imported" in resolved.parents:
            raise ValueError("staging root is a runtime alias under assets/imported")
        raise ValueError("staging root must be physically exactly project/assets/_staging/focused_nine")
    if not resolved.is_dir():
        raise ValueError(f"staging root is not a directory: {lexical}")
    return resolved


def _contained(root: Path, candidate: Path) -> bool:
    return candidate == root or root in candidate.parents


def _canonical_output_path(project_root: Path, value: Path | str, label: str) -> Path:
    lexical = _raw_path(value, label)
    _reject_static_symlink_components(lexical, label)
    resolved = lexical.resolve(strict=False)
    if not _contained(project_root, resolved):
        raise ValueError(f"{label} must be physically contained in project root")
    for runtime_surface in contract.runtime_mutation_paths(project_root):
        if resolved == runtime_surface or runtime_surface in resolved.parents:
            raise ValueError(f"{label} is on a protected runtime surface")
    return resolved


def _normalise_args(args: argparse.Namespace) -> argparse.Namespace:
    project_root = _canonical_project_root(args.project_root)
    staging_root = _canonical_staging_root(project_root, args.staging_root)
    preview_dir = _canonical_output_path(project_root, args.preview_dir, "preview-dir")
    proof = _canonical_output_path(project_root, args.proof, "proof")
    if preview_dir == proof or preview_dir in proof.parents or proof in preview_dir.parents:
        raise ValueError("preview-dir and proof must be separate output leaves")
    return argparse.Namespace(
        project_root=project_root,
        staging_root=staging_root,
        preview_dir=preview_dir,
        proof=proof,
        dry_run=bool(getattr(args, "dry_run", False)),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--staging-root", type=Path, required=True)
    parser.add_argument("--preview-dir", type=Path, required=True)
    parser.add_argument("--proof", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    return parser


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return _normalise_args(args)
    except (OSError, RuntimeError, ValueError) as exc:
        parser.error(str(exc))


def _regular_file(path: Path, label: str) -> Path:
    _reject_static_symlink_components(path, label)
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError as exc:
        raise ValueError(f"missing {label}: {path}") from exc
    except OSError as exc:
        raise ValueError(f"cannot inspect {label}: {path}") from exc
    if stat.S_ISLNK(mode):
        raise ValueError(f"{label} is symlinked: {path}")
    if not stat.S_ISREG(mode):
        raise ValueError(f"{label} is not a regular file: {path}")
    if path.stat().st_size <= 0:
        raise ValueError(f"{label} is empty: {path}")
    return path


def _sidecar_path(staging_root: Path, asset_id: str) -> Path:
    candidates = tuple(staging_root / "props" / f"{asset_id}{suffix}" for suffix in (".visual.json", ".sidecar.json"))
    present = [candidate for candidate in candidates if os.path.lexists(candidate)]
    if len(present) > 1:
        raise ValueError(f"multiple visual sidecars for {asset_id}")
    if not present:
        raise ValueError(f"missing prop visual sidecar for {asset_id}")
    return present[0]


def _required_paths(staging_root: Path) -> tuple[Path, ...]:
    paths: list[Path] = []
    for asset_id in contract.STRUCTURAL_IDS:
        paths.append(staging_root / "structural" / asset_id / f"{asset_id}.glb")
    for asset_id in contract.PROP_IDS:
        paths.extend((staging_root / "props" / f"{asset_id}.glb", _sidecar_path(staging_root, asset_id)))
    pressure_package = staging_root / "structural" / "pressure_door_1x1"
    paths.extend(
        pressure_package / filename
        for filename in (
            "pressure_door_1x1_damaged.glb",
            "pressure_door_1x1_breached.glb",
            "pressure_door_1x1.manifest.json",
            "pressure_door_1x1.input.json",
            "pressure_door_1x1.tscn",
        )
    )
    paths.append(staging_root / COMPARISON_REPORT_NAME)
    return tuple(paths)


def required_staged_paths(inputs: ValidatedInputs) -> tuple[Path, ...]:
    return inputs.paths


def _validate_pressure_package(project_root: Path, staging_root: Path) -> None:
    package = staging_root / "structural" / "pressure_door_1x1"
    staged_structural._validate_staged_package(project_root, staging_root, package)
    for role in PRESSURE_ROLES:
        filename = "pressure_door_1x1.glb" if role == "intact" else f"pressure_door_1x1_{role}.glb"
        staged_structural._validate_glb(package / filename, role)


def _validate_comparison_report(path: Path) -> None:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError("focused-nine comparison report is invalid JSON") from exc
    errors = contract.validate_report(document)
    if errors:
        raise ValueError("focused-nine comparison report validation failed: " + "; ".join(errors))


def validate_inputs(args: argparse.Namespace) -> ValidatedInputs:
    normalised = _normalise_args(args)
    paths = _required_paths(normalised.staging_root)
    for path in paths:
        try:
            _regular_file(path, "staged focused-nine input")
        except ValueError as exc:
            if "missing staged focused-nine input" in str(exc):
                raise ValueError(f"missing staged input: {path}") from exc
            raise

    for asset_id in contract.STRUCTURAL_IDS:
        staged_structural._validate_glb(
            normalised.staging_root / "structural" / asset_id / f"{asset_id}.glb", "intact"
        )
    for asset_id in contract.PROP_IDS:
        path = normalised.staging_root / "props" / f"{asset_id}.glb"
        staged_structural._validate_glb(path, "prop")

    _validate_pressure_package(normalised.project_root, normalised.staging_root)
    for asset_id in contract.PROP_IDS:
        glb = normalised.staging_root / "props" / f"{asset_id}.glb"
        sidecar_path = _sidecar_path(normalised.staging_root, asset_id)
        try:
            document = json.loads(sidecar_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise ValueError(f"prop sidecar validation failed for {asset_id}: invalid JSON") from exc
        errors = staged_props.validate_staged_sidecar(normalised.project_root, glb, document)
        if errors:
            raise ValueError(f"prop sidecar validation failed for {asset_id}: {'; '.join(errors)}")
    _validate_comparison_report(normalised.staging_root / COMPARISON_REPORT_NAME)

    hashes = tuple(
        (path.relative_to(normalised.project_root).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest())
        for path in paths
    )
    return ValidatedInputs(paths=paths, staged_hashes=hashes)


def _copy_regular(source: Path, destination: Path, label: str) -> None:
    _regular_file(source, label)
    _reject_static_symlink_components(destination.parent, f"overlay destination {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination, follow_symlinks=False)
    mode = destination.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise ValueError(f"overlay copy is not a regular file: {destination}")


def _skip_overlay_relative(relative: Path) -> bool:
    parts = relative.parts
    if not parts:
        return False
    if parts[0] in {".git", ".godot", ".pytest_cache", "__pycache__", ".mypy_cache", ".hermes", ".omh"}:
        return True
    if parts[:2] == ("assets", "imported") or parts[:2] == ("assets", "_staging"):
        return True
    return parts[:3] == ("artifacts", "validation-previews", "focused-nine")


def _copy_project_regular_files(project_root: Path, destination: Path) -> None:
    for current, dirnames, filenames in os.walk(project_root, topdown=True, followlinks=False):
        current_path = Path(current)
        relative = current_path.relative_to(project_root)
        dirnames[:] = sorted(
            name
            for name in dirnames
            if not _skip_overlay_relative(relative / name)
            and not (current_path / name).is_symlink()
        )
        for name in sorted(filenames):
            source = current_path / name
            source_relative = relative / name
            if _skip_overlay_relative(source_relative) or name.endswith(".import"):
                continue
            try:
                mode = source.lstat().st_mode
            except OSError as exc:
                raise ValueError(f"cannot inspect project source {source}") from exc
            if stat.S_ISLNK(mode):
                continue
            if not stat.S_ISREG(mode):
                continue
            _copy_regular(source, destination / source_relative, f"project source {source_relative}")


def _canonical_import_path(asset_id: str, role: str = "intact") -> Path:
    filename = f"{asset_id}.glb" if role == "intact" else f"{asset_id}_{role}.glb"
    return CANONICAL_IMPORTED_RELATIVE / asset_id / filename


def _build_overlay(project_root: Path, inputs: ValidatedInputs, destination: Path) -> Path:
    """Copy regular project files and stage focused-nine bytes at production paths."""

    if destination.exists() or destination.is_symlink():
        raise ValueError(f"overlay destination already exists: {destination}")
    _reject_static_symlink_components(destination, "overlay destination")
    destination.mkdir(parents=True)
    _copy_project_regular_files(project_root, destination)

    # Every focused structural wrapper uses canonical imported paths. The new
    # stage only contains intact candidates for non-pressure modules, so the
    # disposable overlay supplies those hidden variant leaves from the same
    # staged identity. Pressure's real triplet is copied byte-for-byte.
    for asset_id in contract.STRUCTURAL_IDS:
        source_intact = contract.asset_stage_glb(project_root, asset_id, "intact")
        roles = PRESSURE_ROLES if asset_id == "pressure_door_1x1" else NON_PRESSURE_ROLES
        for role in roles:
            source = contract.asset_stage_glb(project_root, asset_id, role) if role in contract.VARIANT_ROLES.get(asset_id, ()) else source_intact
            _copy_regular(source, destination / _canonical_import_path(asset_id, role), f"staged {asset_id}/{role} GLB")

    # The production kit's canonical DOOR wrapper is bulkhead_portal_2x1,
    # while focused-nine stages the visually compatible doorway_frame asset.
    # Keep this compatibility mapping disposable and overlay-only: the live
    # wrapper/kit paths and staged registry are never rewritten or promoted.
    _copy_regular(
        contract.asset_stage_glb(project_root, "doorway_frame_open_1x1"),
        destination / _canonical_import_path("bulkhead_portal_2x1"),
        "staged bulkhead portal compatibility visual",
    )

    # Props are preflighted for the package gate and copied only into the
    # overlay, never into the live runtime surface. The runtime prop binder is
    # not part of this structural preview, but this preserves the staged-only
    # identity if a loader resolves a prop during import.
    for asset_id in contract.PROP_IDS:
        source = project_root / STAGED_ROOT_RELATIVE / "props" / f"{asset_id}.glb"
        _copy_regular(source, destination / CANONICAL_PROP_IMPORTED_RELATIVE / f"{asset_id}.glb", f"staged prop {asset_id}")

    # The staged pressure package is itself the production-shaped wrapper for
    # the triplet. Install it only in the external overlay at the canonical
    # wrapper path; the checkout's wrapper tree is untouched.
    pressure_scene = project_root / STAGED_ROOT_RELATIVE / "structural/pressure_door_1x1/pressure_door_1x1.tscn"
    _copy_regular(
        pressure_scene,
        destination / "scenes/wrappers/structural/ship_structural_v0/pressure_door_1x1.tscn",
        "staged pressure-door wrapper",
    )
    return destination


@contextmanager
def disposable_overlay(project_root: Path, inputs: ValidatedInputs) -> Iterator[Path]:
    with tempfile.TemporaryDirectory(prefix="focused-nine-staged-derelict-") as temporary:
        destination = Path(temporary) / "project"
        yield _build_overlay(project_root, inputs, destination)


def _cap_text(value: object) -> str:
    text = value.decode("utf-8", errors="replace") if isinstance(value, bytes) else str(value or "")
    encoded = text.encode("utf-8")
    if len(encoded) <= MAX_CAPTURED_OUTPUT_BYTES:
        return text
    marker = b"\n[output truncated]"
    return encoded[: MAX_CAPTURED_OUTPUT_BYTES - len(marker)].decode("utf-8", errors="replace") + marker.decode()


def _run_bounded_process(
    command: Sequence[str], *, timeout: float, label: str, cwd: Path | None = None
) -> subprocess.CompletedProcess[str]:
    process = subprocess.Popen(
        list(command),
        cwd=str(cwd) if cwd is not None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        partial_stdout = _cap_text(exc.stdout)
        partial_stderr = _cap_text(exc.stderr)
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except (PermissionError, ProcessLookupError):
            process.kill()
        try:
            drained_stdout, drained_stderr = process.communicate(timeout=1.0)
        except subprocess.TimeoutExpired as drain_exc:
            drained_stdout = drain_exc.stdout or ""
            drained_stderr = drain_exc.stderr or ""
            try:
                process.kill()
            except ProcessLookupError:
                pass
        raise CaptureTimeout(
            f"{label} timed out after {timeout:g} seconds",
            _cap_text(partial_stdout) + _cap_text(drained_stdout),
            _cap_text(partial_stderr) + _cap_text(drained_stderr),
        ) from exc
    return subprocess.CompletedProcess(list(command), process.returncode, _cap_text(stdout), _cap_text(stderr))


def _combined_output(result: subprocess.CompletedProcess[str]) -> str:
    return _cap_text("\n".join(part for part in (result.stdout, result.stderr) if part))


def _parse_capture_marker(line: str) -> _CaptureMetadata:
    pattern = re.compile(
        re.escape(CAPTURE_MARKER_PREFIX)
        + r"seed=(?P<seed>-?\d+) rooms=(?P<rooms>\d+) "
        + r"placements=(?P<placements>\d+) walls=(?P<walls>\d+) portals=(?P<portals>\d+) "
        + r"staged_wrapper_count=(?P<wrappers_new>\d+) staged=(?P<staged>\d+) "
        + r"debug=(?P<debug>\S+) output=(?P<output>\S+)"
    )
    match = pattern.fullmatch(line.strip())
    if match is None:
        raise ValueError("capture marker has invalid metadata")
    return _CaptureMetadata(
        seed=int(match.group("seed")),
        room_count=int(match.group("rooms")),
        placement_count=int(match.group("placements")),
        wall_count=int(match.group("walls")),
        portal_count=int(match.group("portals")),
        staged_wrapper_count=int(match.group("wrappers_new")),
        staged_input_count=int(match.group("staged")),
        debug_bundle=match.group("debug"),
        output=match.group("output"),
    )


def _run_capture_process(
    command: Sequence[str], *, cwd: Path, timeout: float = CAPTURE_TIMEOUT_SECONDS
) -> tuple[bool, str, _CaptureMetadata | None]:
    try:
        result = _run_bounded_process(command, timeout=timeout, label="staged derelict capture", cwd=cwd)
    except CaptureTimeout as exc:
        return False, str(exc), None
    except OSError as exc:
        return False, f"cannot invoke Godot capture: {exc}", None
    output = _combined_output(result)
    diagnostics = [line.strip() for line in output.splitlines() if any(marker in line for marker in DIAGNOSTIC_MARKERS)]
    if diagnostics:
        return False, "capture diagnostic blocker: " + diagnostics[0], None
    if result.returncode != 0:
        return False, f"capture failed: exit {result.returncode}", None
    marker = next((line.strip() for line in output.splitlines() if line.strip().startswith(CAPTURE_MARKER_PREFIX)), None)
    if marker is None:
        return False, "capture did not emit the required pass marker", None
    try:
        return True, marker, _parse_capture_marker(marker)
    except ValueError as exc:
        return False, str(exc), None


def _prime_overlay_imports(overlay: Path, timeout: float = CAPTURE_TIMEOUT_SECONDS) -> tuple[bool, str]:
    """Import overlay GLBs into overlay-only .godot state before capture."""

    command = [str(GODOT), "--headless", "--editor", "--path", str(overlay), "--quit"]
    try:
        result = _run_bounded_process(command, timeout=timeout, label="staged overlay import", cwd=overlay)
    except CaptureTimeout as exc:
        return False, str(exc)
    except OSError as exc:
        return False, f"cannot invoke Godot overlay import: {exc}"
    output = _combined_output(result)
    diagnostics = [line.strip() for line in output.splitlines() if any(marker in line for marker in DIAGNOSTIC_MARKERS)]
    if diagnostics:
        return False, "overlay import diagnostic blocker: " + diagnostics[0]
    if result.returncode != 0:
        return False, f"overlay import failed: exit {result.returncode}"
    return True, "staged overlay imports completed"


def _validate_capture_image(path: Path) -> tuple[int, int]:
    """Validate the complete PNG chunk stream, not just its dimensions."""

    _regular_file(path, "capture image")
    payload = path.read_bytes()
    signature = b"\x89PNG\r\n\x1a\n"
    if not payload.startswith(signature):
        raise ValueError("capture image is not a valid PNG signature")

    # Godot's PNG writer uses standard PNG chunks. Rejecting unknown chunk
    # types is deliberate: a forged stream must not smuggle arbitrary bytes
    # past this publication gate while still looking like a PNG header.
    known_chunks = {
        b"IHDR",
        b"PLTE",
        b"IDAT",
        b"IEND",
        b"cHRM",
        b"gAMA",
        b"iCCP",
        b"sBIT",
        b"sRGB",
        b"tEXt",
        b"tIME",
        b"zTXt",
        b"bKGD",
        b"hIST",
        b"pHYs",
        b"sPLT",
        b"tRNS",
        b"iTXt",
        b"eXIf",
        b"acTL",
        b"fcTL",
        b"fdAT",
    }
    offset = len(signature)
    saw_ihdr = False
    saw_idat = False
    saw_iend = False
    dimensions: tuple[int, int] | None = None

    while offset < len(payload):
        if len(payload) - offset < 12:
            raise ValueError("capture PNG chunk header is truncated")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        chunk_type = payload[offset + 4 : offset + 8]
        if chunk_type not in known_chunks or not all(65 <= byte <= 122 and not (91 <= byte <= 96) for byte in chunk_type):
            raise ValueError(f"capture PNG contains an unknown or malformed chunk: {chunk_type!r}")
        data_start = offset + 8
        data_end = data_start + length
        chunk_end = data_end + 4
        if data_end < data_start or chunk_end > len(payload):
            raise ValueError(f"capture PNG chunk is truncated: {chunk_type.decode('ascii', errors='replace')}")
        chunk_data = payload[data_start:data_end]
        expected_crc = struct.unpack(">I", payload[data_end:chunk_end])[0]
        actual_crc = zlib.crc32(chunk_type + chunk_data) & 0xFFFFFFFF
        if expected_crc != actual_crc:
            raise ValueError(f"capture PNG chunk CRC is invalid: {chunk_type.decode('ascii', errors='replace')}")

        if not saw_ihdr:
            if chunk_type != b"IHDR":
                raise ValueError("capture PNG must begin with IHDR")
            if length != 13:
                raise ValueError("capture PNG IHDR is malformed")
            width, height = struct.unpack(">II", chunk_data[:8])
            if width <= 0 or height <= 0:
                raise ValueError("capture PNG dimensions are invalid")
            dimensions = (width, height)
            saw_ihdr = True
        elif chunk_type == b"IHDR":
            raise ValueError("capture PNG contains duplicate IHDR")

        if chunk_type == b"IDAT" and length > 0:
            saw_idat = True
        if chunk_type == b"IEND":
            if length != 0:
                raise ValueError("capture PNG IEND is malformed")
            saw_iend = True
            offset = chunk_end
            if offset != len(payload):
                raise ValueError("capture PNG contains data after terminal IEND")
            break
        offset = chunk_end

    if not saw_ihdr or dimensions is None:
        raise ValueError("capture PNG has no IHDR")
    if not saw_idat:
        raise ValueError("capture PNG has no non-empty IDAT chunk")
    if not saw_iend:
        raise ValueError("capture PNG has no terminal IEND chunk")

    width, height = dimensions
    if (width, height) != (1600, 900):
        raise ValueError(f"capture image must be exactly 1600x900, got {width}x{height}")
    return dimensions


def _validate_debug_bundle(path: Path, metadata: _CaptureMetadata | None = None) -> dict[str, object]:
    """Validate canonical edge evidence and its loader-wrapper bijection."""

    _regular_file(path, "canonical edge debug bundle")
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValueError("canonical edge debug bundle is invalid JSON") from exc
    if not isinstance(document, dict):
        raise TypeError("canonical edge debug bundle must be a JSON object")

    required_fields = ("schema", "capture_id", "seed", "rooms", "occupancy", "edges", "placements", "wrapper_metadata", "validation")
    missing = [field for field in required_fields if field not in document]
    if missing:
        raise ValueError("canonical edge debug bundle missing " + ", ".join(missing))
    if document["schema"] != DEBUG_BUNDLE_SCHEMA:
        raise ValueError("canonical edge debug bundle schema is invalid")
    if document["capture_id"] != DEBUG_CAPTURE_ID:
        raise ValueError("canonical edge debug bundle capture_id is invalid")

    edges = document["edges"]
    placements = document["placements"]
    wrapper_metadata = document["wrapper_metadata"]
    if not isinstance(edges, list) or not isinstance(placements, list) or not isinstance(wrapper_metadata, list):
        raise TypeError("canonical edge debug bundle edges, placements, and wrapper_metadata must be arrays")

    edge_by_key: dict[str, dict[str, object]] = {}
    placement_required_keys: set[str] = set()
    for edge in edges:
        if not isinstance(edge, dict):
            raise TypeError("canonical edge debug bundle contains a non-object edge")
        edge_key = edge.get("edge_key")
        if not isinstance(edge_key, str) or not edge_key:
            raise ValueError("canonical edge debug bundle contains an empty edge key")
        if edge_key in edge_by_key:
            raise ValueError(f"duplicate edge key: {edge_key}")
        edge_by_key[edge_key] = edge
        kind = edge.get("kind")
        if not isinstance(kind, str) or not kind:
            raise ValueError(f"canonical edge debug bundle edge kind is invalid: {edge_key}")
        placement_required = edge.get("placement_required")
        wrapper_required = edge.get("wrapper_required", placement_required)
        if not isinstance(placement_required, bool) or not isinstance(wrapper_required, bool):
            raise TypeError(f"canonical edge debug bundle placement requirement is invalid: {edge_key}")
        if placement_required != wrapper_required:
            raise ValueError(f"canonical edge debug bundle placement/wrapper requirement mismatch: {edge_key}")
        if kind == "OPEN" and placement_required:
            raise ValueError(f"OPEN edge cannot require placement: {edge_key}")
        if placement_required:
            placement_required_keys.add(edge_key)
        if kind in {"DOOR", "LOCKED", "HATCH", "BREACH"}:
            room_ids = edge.get("room_ids")
            endpoint_count = (
                sum(1 for room_id in room_ids if isinstance(room_id, str) and room_id)
                if isinstance(room_ids, list)
                else 0
            )
            if endpoint_count != 2 and not bool(edge.get("exterior", False)):
                raise ValueError(f"portal endpoint reciprocity failed: {edge_key}")

    placement_by_edge: dict[str, dict[str, object]] = {}
    for placement in placements:
        if not isinstance(placement, dict):
            raise TypeError("canonical edge debug bundle contains a non-object placement")
        edge_key = placement.get("edge_key")
        if not isinstance(edge_key, str) or not edge_key:
            raise ValueError("canonical edge debug bundle placement has an empty edge key")
        if edge_key in placement_by_edge:
            raise ValueError(f"duplicate placement edge key: {edge_key}")
        edge = edge_by_key.get(edge_key)
        if edge is None:
            raise ValueError(f"placement references missing edge key: {edge_key}")
        if edge_key not in placement_required_keys:
            kind = edge.get("kind")
            raise ValueError(f"placement redirects to OPEN/unrequired edge: {edge_key} ({kind})")
        placement_id = placement.get("placement_id")
        expected_id = edge.get("placement_id", f"placement:{edge_key}")
        if not isinstance(placement_id, str) or not placement_id or placement_id != str(expected_id):
            raise ValueError(f"placement metadata binding mismatch: {edge_key}")
        if "kind" in placement and placement["kind"] != edge.get("kind"):
            raise ValueError(f"placement kind mismatch: {edge_key}")
        edge_kind = edge.get("kind")
        if edge_kind in {"DOOR", "LOCKED", "HATCH", "BREACH"} and placement.get("kind") == "SOLID":
            raise ValueError(f"portal edge has wall placement: {edge_key}")
        placement_by_edge[edge_key] = placement

    wrapper_by_edge: dict[str, dict[str, object]] = {}
    for wrapper in wrapper_metadata:
        if not isinstance(wrapper, dict):
            raise TypeError("canonical edge debug bundle contains non-object wrapper metadata")
        edge_key = wrapper.get("edge_key")
        if not isinstance(edge_key, str) or not edge_key:
            raise ValueError("canonical edge debug bundle wrapper metadata has an empty edge key")
        if edge_key in wrapper_by_edge:
            raise ValueError(f"duplicate wrapper metadata edge key: {edge_key}")
        if edge_key not in edge_by_key:
            raise ValueError(f"wrapper metadata references missing edge key: {edge_key}")
        if edge_key not in placement_required_keys:
            kind = edge_by_key[edge_key].get("kind")
            raise ValueError(f"wrapper metadata redirects to OPEN/unrequired edge: {edge_key} ({kind})")
        placement = placement_by_edge.get(edge_key)
        placement_id = wrapper.get("placement_id")
        if placement is None or not isinstance(placement_id, str) or not placement_id:
            raise ValueError(f"wrapper metadata has no matching placement: {edge_key}")
        if placement_id != placement.get("placement_id"):
            raise ValueError(f"wrapper/placement metadata binding mismatch: {edge_key}")
        wrapper_by_edge[edge_key] = wrapper

    missing_placements = sorted(placement_required_keys - placement_by_edge.keys())
    if missing_placements:
        raise ValueError("required edge has no placement: " + ", ".join(missing_placements))
    missing_wrappers = sorted(placement_required_keys - wrapper_by_edge.keys())
    if missing_wrappers:
        raise ValueError("required edge has no wrapper metadata: " + ", ".join(missing_wrappers))
    if set(placement_by_edge) != set(wrapper_by_edge):
        raise ValueError("placement and wrapper metadata edge bindings are not an exact set")

    validation = document["validation"]
    if not isinstance(validation, dict):
        raise TypeError("canonical edge debug bundle validation must be an object")
    for field in ("edge_keys_unique", "portal_endpoints_valid", "no_portal_wall_overlap", "canonical_validator"):
        if validation.get(field) is not True:
            raise ValueError(f"canonical edge debug bundle validation failed: {field}")

    if metadata is not None:
        expected = {
            "seed": metadata.seed,
            "rooms": metadata.room_count,
            "placements": metadata.placement_count,
            "walls": metadata.wall_count,
            "portals": metadata.portal_count,
        }
        if document.get("seed") != expected["seed"] or document.get("rooms") != expected["rooms"]:
            raise ValueError("canonical edge debug bundle metadata does not match capture marker")
        actual_walls = sum(1 for edge in edges if isinstance(edge, dict) and edge.get("kind") == "SOLID")
        actual_portals = sum(
            1
            for edge in edges
            if isinstance(edge, dict) and edge.get("kind") in {"DOOR", "LOCKED", "HATCH", "BREACH"}
        )
        if len(placements) != expected["placements"] or actual_walls != expected["walls"] or actual_portals != expected["portals"]:
            raise ValueError("canonical edge debug bundle counts do not match capture marker")
    return document


def _snapshot_leaf(path: Path) -> _PriorLeaf:
    _reject_static_symlink_components(path, f"output path {path}")
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return _PriorLeaf(False, None)
    if stat.S_ISLNK(mode):
        raise PublicationError(f"output leaf is symlinked: {path}")
    if not stat.S_ISREG(mode):
        raise PublicationError(f"output leaf is not a regular file: {path}")
    return _PriorLeaf(True, path.read_bytes())


def _ensure_private_output_parent(path: Path) -> None:
    """Create output parents privately and tighten already-existing leaves."""

    parent = path.parent
    missing: list[Path] = []
    cursor = parent
    while not cursor.exists():
        missing.append(cursor)
        next_cursor = cursor.parent
        if next_cursor == cursor:
            break
        cursor = next_cursor
    parent.mkdir(parents=True, exist_ok=True)
    # mkdir(mode=...) does not change an existing directory and is filtered by
    # umask. Explicitly chmod every output parent, including parents created by
    # an earlier publication, while leaving the pre-existing ancestor alone.
    for directory in [parent, *missing]:
        _reject_static_symlink_components(directory, f"output parent {directory}")
        os.chmod(directory, PRIVATE_DIRECTORY_MODE)


def _write_temp_sibling(path: Path, payload: bytes) -> Path:
    _reject_static_symlink_components(path, f"output path {path}")
    _ensure_private_output_parent(path)
    _reject_static_symlink_components(path.parent, f"output parent {path.parent}")
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    temporary = Path(name)
    try:
        os.fchmod(descriptor, PRIVATE_FILE_MODE)
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        if stat.S_IMODE(temporary.stat().st_mode) != PRIVATE_FILE_MODE:
            raise PublicationError(f"temporary output permissions are not private: {path}")
        if temporary.read_bytes() != payload:
            raise PublicationError(f"temporary output verification failed: {path}")
        return temporary
    except BaseException:
        if descriptor >= 0:
            os.close(descriptor)
        temporary.unlink(missing_ok=True)
        raise


def _verify_published(path: Path, payload: bytes) -> None:
    _regular_file(path, "published output")
    if stat.S_IMODE(path.stat().st_mode) != PRIVATE_FILE_MODE:
        raise PublicationError(f"published output permissions are not private: {path}")
    if path.read_bytes() != payload:
        raise PublicationError(f"published output verification failed: {path}")


def _remove_leaf(path: Path) -> None:
    if not os.path.lexists(path):
        return
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise PublicationError(f"cannot remove non-regular output leaf: {path}")
    path.unlink()


def _restore_leaf(path: Path, prior: _PriorLeaf) -> None:
    if prior.existed:
        temporary = _write_temp_sibling(path, prior.payload or b"")
        try:
            os.replace(temporary, path)
            temporary = None  # type: ignore[assignment]
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        _verify_published(path, prior.payload or b"")
    else:
        _remove_leaf(path)


def publish_artifacts(
    preview_path: Path,
    preview_bytes: bytes,
    proof_path: Path,
    proof_content: str | bytes,
    debug_path: Path | None = None,
    debug_bytes: bytes | None = None,
) -> None:
    if not preview_bytes:
        raise PublicationError("preview bytes are empty")
    proof_bytes = proof_content.encode("utf-8") if isinstance(proof_content, str) else bytes(proof_content)
    if not proof_bytes:
        raise PublicationError("proof content is empty")
    if (debug_path is None) != (debug_bytes is None):
        raise PublicationError("debug path and debug bytes must be supplied together")
    if debug_bytes is not None and not debug_bytes:
        raise PublicationError("debug bundle bytes are empty")

    targets: list[tuple[Path, bytes]] = [(preview_path, preview_bytes), (proof_path, proof_bytes)]
    if debug_path is not None and debug_bytes is not None:
        targets.append((debug_path, debug_bytes))
    prior = {path: _snapshot_leaf(path) for path, _payload in targets}
    temporary_paths: list[Path | None] = []
    try:
        for path, payload in targets:
            temporary_paths.append(_write_temp_sibling(path, payload))
        for index, (path, payload) in enumerate(targets):
            temporary = temporary_paths[index]
            if temporary is None:
                raise PublicationError(f"missing temporary output for {path}")
            os.replace(temporary, path)
            temporary_paths[index] = None
            _verify_published(path, payload)
    except BaseException as exc:
        for temporary in temporary_paths:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        try:
            for path, _payload in targets:
                _restore_leaf(path, prior[path])
        except Exception as rollback_exc:  # noqa: BLE001 - preserve the original publication failure during rollback
            raise PublicationError(f"publication failed and rollback failed: {rollback_exc}") from exc
        raise PublicationError(f"publication failed: {exc}") from exc


def build_proof(
    *,
    output_path: Path,
    dimensions: tuple[int, int],
    seed: int,
    room_count: int,
    staged_wrapper_count: int,
    staged_input_count: int,
    marker: str,
    placement_count: int = 0,
    wall_count: int = 0,
    portal_count: int = 0,
    debug_bundle: str = "edge_map.json",
) -> str:
    return "\n".join(
        (
            "# Focused-Nine Staged Procgen Derelict Preview",
            "",
            "- Source root: `assets/_staging/focused_nine` (staged-only).",
            f"- Runtime generator seed: `{seed}` (seed={seed}).",
            f"- Generated room count: `{room_count}` (room_count={room_count}, small derelict range 5-8).",
            f"- Canonical structural placement count: `{placement_count}` (placements={placement_count}).",
            f"- Canonical wall/portal edge counts: walls={wall_count}, portals={portal_count}.",
            f"- Generated staged wrapper count: `{staged_wrapper_count}` (staged_wrapper_count={staged_wrapper_count}).",
            f"- Staged focused-nine input count: `{staged_input_count}` (staged_input_count={staged_input_count}).",
            f"- Capture: `{output_path.name}`, {dimensions[0]}x{dimensions[1]}.",
            f"- Canonical debug bundle: `{debug_bundle}` (`edge_map.json`).",
            "- The disposable overlay copied regular staged GLBs to canonical production import paths.",
            "- Pressure-door intact/damaged/breached triplet was preserved byte-for-byte in the overlay.",
            "- Tree inspection found no fallback or live imported visual references.",
            "- The generated derelict graph contains an actual dock role; no lifeboat scene was instantiated.",
            "- No runtime promotion occurred.",
            f"- Acceptance marker: `{marker}`",
            "",
        )
    )


def _logical_path(project_root: Path, path: Path) -> str:
    try:
        return path.relative_to(project_root).as_posix()
    except ValueError:
        return path.name


def _capture_command(overlay: Path, output_dir: Path, staged_input_count: int) -> list[str]:
    output_argument = output_dir.relative_to(overlay).as_posix()
    return [
        str(GODOT),
        "--path",
        str(overlay),
        "--scene",
        CAPTURE_SCENE,
        "--",
        "--seed",
        "17",
        "--output-dir",
        output_argument,
        "--staged-input-count",
        str(staged_input_count),
    ]


def run(args: argparse.Namespace) -> RunResult:
    try:
        normalised = _normalise_args(args)
    except (OSError, RuntimeError, ValueError) as exc:
        return RunResult(1, str(exc) or "invalid preview arguments")

    try:
        before = snapshot_runtime_surfaces(normalised.project_root)
    except (OSError, RuntimeError, ValueError) as exc:
        return RunResult(1, f"cannot snapshot runtime surfaces before validation: {exc}")

    try:
        inputs = validate_inputs(normalised)
    except (OSError, RuntimeError, ValueError) as exc:
        return RunResult(1, str(exc) or "staged focused-nine preflight failed", dry_run=normalised.dry_run)

    if normalised.dry_run:
        return RunResult(0, "dry-run validation passed; no overlay or outputs written", dry_run=True)

    try:
        with tempfile.TemporaryDirectory(prefix="focused-nine-staged-derelict-") as temporary:
            overlay = Path(temporary) / "project"
            try:
                _build_overlay(normalised.project_root, inputs, overlay)
            except (OSError, RuntimeError, ValueError) as exc:
                return RunResult(1, f"cannot create external staged-only overlay: {exc}")
            output_dir = overlay / CAPTURE_OUTPUT_RELATIVE
            capture_result: tuple[bool, str, _CaptureMetadata | None]
            after: tuple[tuple[str, str, int | None, str | None], ...] | None = None
            try:
                prime_ok, prime_detail = _prime_overlay_imports(overlay)
                if not prime_ok:
                    capture_result = (False, prime_detail, None)
                else:
                    capture_result = _run_capture_process(
                        _capture_command(overlay, output_dir, len(inputs.paths)), cwd=overlay
                    )
            except (OSError, RuntimeError, ValueError) as exc:
                capture_result = (False, f"capture raised an exception: {exc}", None)
            finally:
                try:
                    after = snapshot_runtime_surfaces(normalised.project_root)
                except (OSError, RuntimeError, ValueError) as exc:
                    after = None
                    capture_result = (False, f"cannot snapshot runtime surfaces after capture: {exc}", None)
            if after is None:
                return RunResult(1, capture_result[1])
            if after != before:
                return RunResult(1, "runtime surface mismatch after staged derelict capture; publication blocked")
            ok, detail, metadata = capture_result
            if not ok or metadata is None:
                reason = detail or "staged derelict capture failed"
                if any(marker in reason for marker in DIAGNOSTIC_MARKERS):
                    reason = f"capture diagnostic blocker: {reason}"
                return RunResult(1, reason)
            if metadata.room_count < 5 or metadata.room_count > 8:
                return RunResult(1, f"capture generated room count outside small derelict range: {metadata.room_count}")
            if metadata.staged_wrapper_count <= 0:
                return RunResult(1, "capture tree inspection found no staged generated wrappers")
            if metadata.staged_input_count != len(inputs.paths):
                return RunResult(
                    1,
                    f"capture staged input count mismatch expected={len(inputs.paths)} got={metadata.staged_input_count}",
                )
            output_path = output_dir / CAPTURE_IMAGE_NAME
            try:
                dimensions = _validate_capture_image(output_path)
                preview_bytes = output_path.read_bytes()
            except (OSError, RuntimeError, ValueError) as exc:
                return RunResult(1, str(exc) or "capture image validation failed")
            try:
                _validate_debug_bundle(output_dir / DEBUG_BUNDLE_NAME, metadata)
                debug_bytes = (output_dir / DEBUG_BUNDLE_NAME).read_bytes()
            except (OSError, RuntimeError, TypeError, ValueError) as exc:
                return RunResult(1, str(exc) or "canonical debug bundle validation failed")
            published_debug = normalised.preview_dir / DEBUG_BUNDLE_NAME
            proof_content = build_proof(
                output_path=normalised.preview_dir / CAPTURE_IMAGE_NAME,
                dimensions=dimensions,
                seed=metadata.seed,
                room_count=metadata.room_count,
                staged_wrapper_count=metadata.staged_wrapper_count,
                staged_input_count=metadata.staged_input_count,
                marker=detail,
                placement_count=metadata.placement_count,
                wall_count=metadata.wall_count,
                portal_count=metadata.portal_count,
                debug_bundle=_logical_path(normalised.project_root, published_debug),
            )
            try:
                publish_artifacts(
                    normalised.preview_dir / CAPTURE_IMAGE_NAME,
                    preview_bytes,
                    normalised.proof,
                    proof_content,
                    debug_path=published_debug,
                    debug_bytes=debug_bytes,
                )
            except (OSError, RuntimeError, PublicationError, ValueError) as exc:
                return RunResult(1, str(exc) or "preview/proof publication failed")
    except (OSError, RuntimeError, ValueError) as exc:
        return RunResult(1, str(exc) or "staged derelict preview failed")

    published = normalised.preview_dir / CAPTURE_IMAGE_NAME
    return RunResult(
        0,
        f"{PREVIEW_MARKER_PREFIX}seed={metadata.seed} rooms={metadata.room_count} "
        f"placements={metadata.placement_count} walls={metadata.wall_count} portals={metadata.portal_count} "
        f"staged_wrapper_count={metadata.staged_wrapper_count} staged_input_count={metadata.staged_input_count} "
        f"debug={_logical_path(normalised.project_root, published_debug)} "
        f"png={_logical_path(normalised.project_root, published)}",
        published,
    )


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    result = run(args)
    if result.exit_code == 0:
        if result.dry_run:
            print("FOCUSED_NINE_STAGED_DERELICT_PREVIEW DRY-RUN PASS")
        else:
            print(result.reason)
    else:
        print(f"FOCUSED_NINE_STAGED_DERELICT_PREVIEW FAIL reason={result.reason}", file=sys.stderr)
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
