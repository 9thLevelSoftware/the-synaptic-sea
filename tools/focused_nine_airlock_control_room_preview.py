#!/usr/bin/env python3
"""Validate staged focused-nine inputs and run a disposable room preview.

The runner is a no-promotion airlock: every staged input is observed and
validated before a private overlay is created, Godot runs only against that
overlay, and the preview/proof pair is published as one transaction.  Runtime
surfaces are snapshotted before validation and immediately after every capture
attempt.

Security boundary: this is a trusted-workspace workflow.  The initial
path observations and no-follow checks do not pin a descriptor chain against a
same-user actor that concurrently renames or rebinds a workspace component.
That concurrent pre-check rebind limitation is intentionally out of scope;
temporary overlays, static symlink rejection, and atomic publication are
defense in depth rather than descriptor-level race immunity.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

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
SIPS = Path(os.environ.get("SIPS", "/usr/bin/sips"))
CAPTURE_TIMEOUT_SECONDS = 120.0
IMAGE_CHECK_TIMEOUT_SECONDS = 10.0
MAX_CAPTURED_OUTPUT_BYTES = 64 * 1024
CAPTURE_SCENE = "res://scenes/validation/focused_nine_airlock_control_room_harness.tscn"
CAPTURE_SCRIPT_RELATIVE = Path("scripts/validation/focused_nine_airlock_control_room_capture.gd")
CAPTURE_SCENE_RELATIVE = Path("scenes/validation/focused_nine_airlock_control_room_harness.tscn")
CAPTURE_OUTPUT_RELATIVE = Path("artifacts/validation-previews/focused-nine")
CAPTURE_IMAGE_NAME = "focused-nine-airlock-control-room.png"
CAPTURE_MARKER_PREFIX = "FOCUSED_NINE_AIRLOCK_ROOM_CAPTURE PASS output="
PREVIEW_MARKER_PREFIX = "FOCUSED_NINE_AIRLOCK_ROOM_PREVIEW PASS path="
DIAGNOSTIC_MARKERS = ("WARNING:", "ERROR:", "SCRIPT ERROR:")
PROP_SIDECAR_SUFFIXES = (".visual.json", ".sidecar.json")
PRESSURE_ROLES = ("intact", "damaged", "breached")


class CaptureTimeout(RuntimeError):
    """The capture process exceeded its bounded timeout."""

    def __init__(self, message: str, stdout: str = "", stderr: str = "") -> None:
        super().__init__(message)
        self.stdout = stdout
        self.stderr = stderr


class PublicationError(RuntimeError):
    """The preview/proof publication transaction could not complete."""


@dataclass(frozen=True)
class RunResult:
    exit_code: int
    reason: str = ""
    path: Path | None = None
    dry_run: bool = False

    @property
    def success(self) -> bool:
        return self.exit_code == 0

    @property
    def message(self) -> str:
        return self.reason


@dataclass(frozen=True)
class ValidatedInputs:
    paths: tuple[Path, ...]
    sidecars: tuple[tuple[Path, dict[str, Any]], ...] = ()


@dataclass(frozen=True)
class _PriorLeaf:
    existed: bool
    payload: bytes | None


def snapshot_runtime_surfaces(project_root: Path) -> tuple[tuple[str, str, int | None, str | None], ...]:
    """Delegate to the established protected-runtime snapshot helper."""

    return batch.snapshot_runtime_surfaces(project_root)


def _raw_path(value: Path | str, label: str) -> Path:
    path = Path(value).expanduser()
    if ".." in path.parts:
        raise ValueError(f"{label} must not contain traversal: {path}")
    return path if path.is_absolute() else Path.cwd() / path


def _absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(path)))


def _safe_system_alias(path: Path) -> bool:
    # macOS's /var -> /private/var is an OS-owned alias.  Do not extend this
    # exception to caller-created workspace symlinks (including /tmp aliases).
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
    try:
        resolved = lexical.resolve(strict=False)
    except (OSError, RuntimeError, ValueError) as exc:
        raise ValueError(f"cannot resolve project root: {lexical}") from exc
    if not resolved.is_dir():
        raise ValueError(f"project root is not a directory: {lexical}")
    return resolved


def _canonical_staging_root(project_root: Path, value: Path | str) -> Path:
    lexical = _raw_path(value, "staging root")
    _reject_static_symlink_components(lexical, "staging root")
    try:
        resolved = lexical.resolve(strict=False)
    except (OSError, RuntimeError, ValueError) as exc:
        raise ValueError(f"cannot resolve staging root: {lexical}") from exc
    expected = project_root / "assets/_staging/focused_nine"
    if resolved != expected:
        if resolved == project_root / "assets/imported" or project_root / "assets/imported" in resolved.parents:
            raise ValueError("staging root is a runtime alias under assets/imported")
        raise ValueError(
            "staging root must be physically exactly "
            "project/assets/_staging/focused_nine"
        )
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
    if preview_dir == proof or preview_dir in proof.parents:
        raise ValueError("preview-dir and proof must be separate output leaves")
    if proof.name == "" or preview_dir.name == "":
        raise ValueError("preview-dir and proof must not be empty")
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
    return path


def _prop_sidecar_path(staging_root: Path, asset_id: str) -> Path:
    directory = staging_root / "props"
    candidates = [directory / f"{asset_id}{suffix}" for suffix in PROP_SIDECAR_SUFFIXES]
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
        paths.append(staging_root / "props" / f"{asset_id}.glb")
        paths.append(_prop_sidecar_path(staging_root, asset_id))
    pressure_package = staging_root / "structural" / "pressure_door_1x1"
    paths.extend(
        pressure_package / name
        for name in (
            "pressure_door_1x1_damaged.glb",
            "pressure_door_1x1_breached.glb",
            "pressure_door_1x1.manifest.json",
            "pressure_door_1x1.input.json",
            "pressure_door_1x1.tscn",
        )
    )
    return tuple(paths)


def required_staged_paths(inputs: ValidatedInputs) -> tuple[Path, ...]:
    """Expose the exact regular files copied into the disposable overlay."""

    return inputs.paths


def _validate_pressure_package(project_root: Path, staging_root: Path) -> None:
    package = staging_root / "structural" / "pressure_door_1x1"
    # This existing validator owns the manifest/input/scene/contract schema.
    staged_structural._validate_staged_package(project_root, staging_root, package)
    for role in PRESSURE_ROLES:
        filename = "pressure_door_1x1.glb" if role == "intact" else f"pressure_door_1x1_{role}.glb"
        path = _regular_file(package / filename, f"pressure-door {role} GLB")
        staged_structural._validate_glb(path, role)


def validate_inputs(args: argparse.Namespace) -> ValidatedInputs:
    """Validate every staged package member before any overlay/copy occurs."""

    normalised = _normalise_args(args)
    paths = _required_paths(normalised.staging_root)
    for path in paths:
        try:
            _regular_file(path, "staged input")
        except ValueError as exc:
            if "missing staged input" in str(exc):
                raise ValueError(f"missing staged GLB or package input: {path}") from exc
            raise

    for asset_id in contract.STRUCTURAL_IDS:
        path = normalised.staging_root / "structural" / asset_id / f"{asset_id}.glb"
        staged_structural._validate_glb(path, "intact")
    for asset_id in contract.PROP_IDS:
        path = normalised.staging_root / "props" / f"{asset_id}.glb"
        staged_structural._validate_glb(path, "prop")

    _validate_pressure_package(normalised.project_root, normalised.staging_root)

    sidecars: list[tuple[Path, dict[str, Any]]] = []
    for asset_id in contract.PROP_IDS:
        glb = normalised.staging_root / "props" / f"{asset_id}.glb"
        sidecar_path = _prop_sidecar_path(normalised.staging_root, asset_id)
        try:
            document = json.loads(sidecar_path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise ValueError(f"prop sidecar validation failed for {asset_id}: invalid JSON") from exc
        errors = staged_props.validate_staged_sidecar(
            normalised.project_root, glb, document
        )
        if errors:
            raise ValueError(
                f"prop sidecar validation failed for {asset_id}: {'; '.join(errors)}"
            )
        sidecars.append((sidecar_path, document))
    return ValidatedInputs(paths=paths, sidecars=tuple(sidecars))


def _copy_regular(source: Path, destination: Path, label: str) -> None:
    _regular_file(source, label)
    _reject_static_symlink_components(destination, f"overlay destination {destination}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    _reject_static_symlink_components(destination.parent, f"overlay destination {destination}")
    shutil.copy2(source, destination, follow_symlinks=False)
    _regular_file(destination, f"overlay copy {destination}")


def _build_overlay(project_root: Path, inputs: ValidatedInputs, destination: Path) -> Path:
    """Create an overlay containing only Godot capture files and staged inputs."""

    if destination.exists() or destination.is_symlink():
        raise ValueError(f"overlay destination already exists: {destination}")
    _reject_static_symlink_components(destination, "overlay destination")
    destination.mkdir(parents=True)
    _copy_regular(project_root / "project.godot", destination / "project.godot", "project.godot")
    _copy_regular(
        project_root / CAPTURE_SCENE_RELATIVE,
        destination / CAPTURE_SCENE_RELATIVE,
        "capture scene",
    )
    _copy_regular(
        project_root / CAPTURE_SCRIPT_RELATIVE,
        destination / CAPTURE_SCRIPT_RELATIVE,
        "capture script",
    )
    for source in required_staged_paths(inputs):
        relative = source.relative_to(project_root)
        _copy_regular(source, destination / relative, "staged overlay input")
    return destination


@contextmanager
def disposable_overlay(project_root: Path, inputs: ValidatedInputs) -> Iterator[Path]:
    """Yield and always remove an external temporary capture overlay."""

    with tempfile.TemporaryDirectory(prefix="focused-nine-room-preview-") as temporary:
        destination = Path(temporary) / "project"
        yield _build_overlay(project_root, inputs, destination)


def _cap_text(value: object) -> str:
    if isinstance(value, bytes):
        text = value.decode("utf-8", errors="replace")
    else:
        text = str(value or "")
    encoded = text.encode("utf-8")
    if len(encoded) <= MAX_CAPTURED_OUTPUT_BYTES:
        return text
    marker = b"\n[output truncated]"
    if len(marker) >= MAX_CAPTURED_OUTPUT_BYTES:
        return marker[:MAX_CAPTURED_OUTPUT_BYTES].decode("utf-8", errors="ignore")
    return (
        encoded[: MAX_CAPTURED_OUTPUT_BYTES - len(marker)].decode("utf-8", errors="replace")
        + marker.decode()
    )


def _run_bounded_process(
    command: Sequence[str],
    *,
    timeout: float,
    label: str,
    cwd: Path | None = None,
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
        stdout = _cap_text(partial_stdout) + _cap_text(drained_stdout)
        stderr = _cap_text(partial_stderr) + _cap_text(drained_stderr)
        raise CaptureTimeout(f"{label} timed out after {timeout:g} seconds", stdout, stderr) from exc
    return subprocess.CompletedProcess(
        list(command),
        process.returncode,
        _cap_text(stdout),
        _cap_text(stderr),
    )


def _combined_output(result: subprocess.CompletedProcess[str]) -> str:
    output = "\n".join(
        part for part in (_cap_text(result.stdout), _cap_text(result.stderr)) if part
    )
    return _cap_text(output)


def _capture_output_path(overlay_root: Path, output_dir: Path, marker_path: str) -> Path:
    candidate = Path(marker_path.strip())
    if not candidate.is_absolute():
        candidate = overlay_root / candidate
    candidate = candidate.resolve(strict=False)
    expected_dir = output_dir.resolve(strict=False)
    if candidate != expected_dir / CAPTURE_IMAGE_NAME:
        raise ValueError("capture marker output is not the approved room image leaf")
    _reject_static_symlink_components(candidate, "capture image")
    return candidate


def _run_room_capture(
    overlay_root: Path,
    output_dir: Path,
    *,
    godot: Path = GODOT,
    wrapper: Path | None = None,
) -> tuple[bool, str, Path | None]:
    """Run Task 1's exact non-headless scene command in the private overlay."""

    if wrapper is None:
        output_argument = output_dir.relative_to(overlay_root).as_posix()
        command = [
            str(godot),
            "--path",
            str(overlay_root),
            "--scene",
            CAPTURE_SCENE,
            "--",
            "--output-dir",
            output_argument,
        ]
    else:
        command = [str(godot), str(wrapper)]
    try:
        result = _run_bounded_process(
            command,
            timeout=CAPTURE_TIMEOUT_SECONDS,
            label="room capture",
            cwd=overlay_root,
        )
    except CaptureTimeout as exc:
        return False, str(exc), None
    except OSError as exc:
        return False, f"cannot invoke Godot room capture: {exc}", None

    output = _combined_output(result)
    diagnostics = [line.strip() for line in output.splitlines() if any(marker in line for marker in DIAGNOSTIC_MARKERS)]
    if diagnostics:
        return False, "capture diagnostic blocker: " + diagnostics[0], None
    if result.returncode != 0:
        return False, f"room capture failed: exit {result.returncode}", None
    marker = next((line.strip() for line in output.splitlines() if line.strip().startswith(CAPTURE_MARKER_PREFIX)), None)
    if marker is None:
        return False, "room capture did not emit the required Task 1 pass marker", None
    try:
        return True, marker, _capture_output_path(
            overlay_root, output_dir, marker.removeprefix(CAPTURE_MARKER_PREFIX)
        )
    except ValueError as exc:
        return False, str(exc), None


def _validate_capture_image(path: Path) -> tuple[int, int]:
    _regular_file(path, "capture image")
    if path.stat().st_size <= 0:
        raise ValueError("capture image is empty")
    try:
        result = _run_bounded_process(
            [str(SIPS), "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
            timeout=IMAGE_CHECK_TIMEOUT_SECONDS,
            label="capture image dimension check",
        )
    except (CaptureTimeout, OSError) as exc:
        raise ValueError(f"cannot inspect capture image dimensions: {exc}") from exc
    output = _combined_output(result)
    if result.returncode != 0:
        raise ValueError(f"capture image dimension check failed: {output or result.returncode}")
    width_match = re.search(r"pixelWidth:\s*(\d+)", output)
    height_match = re.search(r"pixelHeight:\s*(\d+)", output)
    if width_match is None or height_match is None:
        raise ValueError("capture image dimension check returned no dimensions")
    dimensions = (int(width_match.group(1)), int(height_match.group(1)))
    if dimensions != (1600, 900):
        raise ValueError(f"capture image must be exactly 1600x900, got {dimensions[0]}x{dimensions[1]}")
    return dimensions


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


def _write_temp_sibling(path: Path, payload: bytes) -> Path:
    _reject_static_symlink_components(path, f"output path {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    _reject_static_symlink_components(path.parent, f"output parent {path.parent}")
    descriptor, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    temporary = Path(name)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
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
    if path.read_bytes() != payload:
        raise PublicationError(f"published output verification failed: {path}")


def _remove_leaf(path: Path) -> None:
    if not os.path.lexists(path):
        return
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        raise PublicationError(f"cannot remove symlinked output leaf: {path}")
    if not stat.S_ISREG(mode):
        raise PublicationError(f"cannot remove non-file output leaf: {path}")
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
) -> None:
    """Atomically publish preview and proof, restoring exact prior leaves on error."""

    if not preview_bytes:
        raise PublicationError("preview bytes are empty")
    proof_bytes = proof_content.encode("utf-8") if isinstance(proof_content, str) else bytes(proof_content)
    if not proof_bytes:
        raise PublicationError("proof content is empty")
    preview_path = Path(preview_path)
    proof_path = Path(proof_path)
    prior_preview = _snapshot_leaf(preview_path)
    prior_proof = _snapshot_leaf(proof_path)
    temporary_preview: Path | None = None
    temporary_proof: Path | None = None
    try:
        temporary_preview = _write_temp_sibling(preview_path, preview_bytes)
        temporary_proof = _write_temp_sibling(proof_path, proof_bytes)
        os.replace(temporary_preview, preview_path)
        temporary_preview = None
        _verify_published(preview_path, preview_bytes)
        os.replace(temporary_proof, proof_path)
        temporary_proof = None
        _verify_published(proof_path, proof_bytes)
    except BaseException as exc:
        for temporary in (temporary_preview, temporary_proof):
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        try:
            _restore_leaf(preview_path, prior_preview)
            _restore_leaf(proof_path, prior_proof)
        except BaseException as rollback_exc:
            raise PublicationError(f"publication failed and rollback failed: {rollback_exc}") from exc
        if isinstance(exc, PublicationError):
            raise
        raise PublicationError(f"publication failed: {exc}") from exc


def build_proof(
    *,
    output_path: Path,
    dimensions: tuple[int, int],
    marker: str,
) -> str:
    """Build proof text in memory; callers decide whether to publish it."""

    return "\n".join(
        (
            "# Focused-Nine Airlock/Control Room Preview",
            "",
            "- Source root: `assets/_staging/focused_nine` (staged-only).",
            "- Composition: deterministic 3x3 airlock/control-room layout.",
            f"- Capture: `{output_path.name}`, {dimensions[0]}x{dimensions[1]}.",
            "- Pressure-door package and staged visual-prop sidecars passed their existing validators.",
            "- No runtime promotion occurred.",
            f"- Runner marker: `{marker}`",
            "",
        )
    )


def _logical_path(project_root: Path, path: Path) -> str:
    try:
        return path.relative_to(project_root).as_posix()
    except ValueError:
        return path.name


def run(args: argparse.Namespace) -> RunResult:
    """Run all gates and publish both outputs only after every gate passes."""

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
        return RunResult(1, str(exc) or "staged input validation failed", dry_run=normalised.dry_run)

    if normalised.dry_run:
        return RunResult(0, "dry-run validation passed; no outputs written", dry_run=True)

    output_path: Path | None = None
    dimensions: tuple[int, int] | None = None
    marker = ""
    try:
        with tempfile.TemporaryDirectory(prefix="focused-nine-room-preview-") as temporary:
            overlay = Path(temporary) / "project"
            try:
                _build_overlay(normalised.project_root, inputs, overlay)
            except (OSError, RuntimeError, ValueError) as exc:
                return RunResult(1, f"cannot create isolated preview overlay: {exc}")
            capture_output_dir = overlay / CAPTURE_OUTPUT_RELATIVE
            capture_result: tuple[bool, str, Path | None]
            after: tuple[tuple[str, str, int | None, str | None], ...] | None = None
            try:
                try:
                    capture_result = _run_room_capture(overlay, capture_output_dir)
                except (OSError, RuntimeError, ValueError) as exc:
                    capture_result = (False, f"room capture raised an exception: {exc}", None)
            finally:
                try:
                    after = snapshot_runtime_surfaces(normalised.project_root)
                except (OSError, RuntimeError, ValueError) as exc:
                    after = None
                    capture_result = (False, f"cannot snapshot runtime surfaces after capture: {exc}", None)
            if after is None:
                return RunResult(1, capture_result[1])
            if after != before:
                return RunResult(1, "runtime surface mismatch after room capture; publication blocked")
            ok, detail, output_path = capture_result
            if not ok:
                reason = detail or "room capture failed"
                if any(marker in reason for marker in DIAGNOSTIC_MARKERS):
                    reason = f"capture diagnostic blocker: {reason}"
                return RunResult(1, reason)
            marker = detail
            if output_path is None:
                return RunResult(1, "room capture returned no image path")
            try:
                dimensions = _validate_capture_image(output_path)
                preview_bytes = output_path.read_bytes()
            except (OSError, RuntimeError, ValueError) as exc:
                return RunResult(1, str(exc) or "capture image validation failed")
            proof_content = build_proof(
                output_path=normalised.preview_dir / CAPTURE_IMAGE_NAME,
                dimensions=dimensions,
                marker=marker,
            )
            try:
                publish_artifacts(
                    normalised.preview_dir / CAPTURE_IMAGE_NAME,
                    preview_bytes,
                    normalised.proof,
                    proof_content,
                )
            except (OSError, RuntimeError, PublicationError, ValueError) as exc:
                return RunResult(1, str(exc) or "preview/proof publication failed")
    except (OSError, RuntimeError, ValueError) as exc:
        return RunResult(1, str(exc) or "room preview failed")

    return RunResult(
        0,
        f"{PREVIEW_MARKER_PREFIX}{_logical_path(normalised.project_root, normalised.preview_dir / CAPTURE_IMAGE_NAME)}",
        normalised.preview_dir / CAPTURE_IMAGE_NAME,
    )


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = parse_args(argv)
    except SystemExit:
        raise
    result = run(args)
    if result.exit_code == 0:
        if result.dry_run:
            print("FOCUSED_NINE_AIRLOCK_ROOM_PREVIEW DRY-RUN PASS")
        else:
            print(result.reason)
    else:
        print(f"FOCUSED_NINE_AIRLOCK_ROOM_PREVIEW FAIL reason={result.reason}", file=sys.stderr)
    return result.exit_code


if __name__ == "__main__":
    raise SystemExit(main())
