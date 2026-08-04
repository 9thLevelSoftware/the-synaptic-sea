#!/usr/bin/env python3
"""Atomically stage and validate the focused-nine comparison batch.

The batch is deliberately a no-promotion workflow.  Blender edits only the
approved external source roots, candidate GLBs and staged metadata are built in
an isolated temporary staging workspace, and one asset is published only after
its recipe, export, evidence, and wrapper/sidecar gates pass.  Runtime surfaces
are never copied to or written by this module.

Trusted-workspace boundary: Blender and Godot use path-based APIs.  After the
initial path observations, same-user concurrent rename or rebind of the source,
project, and output paths is outside this workflow's boundary; the containment,
no-follow validators, temporary workspaces, and atomic renames are defense in
depth and are not claimed to provide descriptor-level race immunity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Iterable, Sequence
from pathlib import Path
from typing import Any

try:
    from tools import focused_nine_contract as contract
    from tools import focused_nine_evidence as evidence
    from tools import focused_nine_staged_props as staged_props
    from tools import focused_nine_staged_structural as staged_structural
    from tools.focused_nine_blender_recipes import source_blend_path
except ModuleNotFoundError:  # pragma: no cover - direct script execution
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools import focused_nine_contract as contract
    from tools import focused_nine_evidence as evidence
    from tools import focused_nine_staged_props as staged_props
    from tools import focused_nine_staged_structural as staged_structural
    from tools.focused_nine_blender_recipes import source_blend_path


ORDERED_ASSET_IDS: tuple[str, ...] = contract.STRUCTURAL_IDS + contract.PROP_IDS
BLENDER = Path(os.environ.get("BLENDER", "/opt/homebrew/bin/blender"))
GODOT = Path(os.environ.get("GODOT", "/opt/homebrew/bin/godot"))
RECIPE_SCRIPT = Path(__file__).with_name("focused_nine_blender_recipes.py")
EXPORT_SCRIPT = Path(__file__).with_name("export_structural_glb.py")
PRESSURE_PACKAGE = Path("assets/_staging/focused_nine/structural/pressure_door_1x1")
PROOF_RELATIVE = Path("docs/superpowers/proofs/focused-nine-comparison.md")
_CAPTURE_SCENE = "res://scenes/validation/focused_nine_comparison_harness.tscn"
_CAPTURE_SCRIPT = "res://scripts/validation/focused_nine_comparison_capture.gd"
CAPTURE_TIMEOUT_SECONDS = 120


# Re-exporting this pure validator keeps the batch's report gate obvious to
# callers and makes the CLI contract easy to test without Blender.
validate_report = contract.validate_report


def _absolute(path: Path) -> Path:
    return Path(os.path.abspath(os.fspath(Path(path).expanduser())))


def _contained(root: Path, candidate: Path) -> bool:
    root = root.resolve(strict=False)
    candidate = candidate.resolve(strict=False)
    return candidate == root or root in candidate.parents


def _stage_root(project_root: Path) -> Path:
    return project_root / "assets/_staging/focused_nine"


def _canonical_res_path(project_root: Path, path: Path) -> str:
    root = project_root.resolve(strict=False)
    candidate = path.resolve(strict=False)
    try:
        return f"res://{candidate.relative_to(root).as_posix()}"
    except ValueError:
        # The report contract intentionally permits only project-relative
        # source references.  The actual external source path is retained in
        # the improved evidence map and the proof document.
        return f"res://assets/_staging/focused_nine/source_refs/{path.stem}.blend"


def _source_reference(asset_id: str) -> str:
    return f"res://assets/_staging/focused_nine/source_refs/{asset_id}.blend"


def _iter_surface_entries(root: Path) -> Iterable[tuple[str, str, int | None, str | None]]:
    """Yield a deterministic, no-follow manifest for one runtime surface."""

    if not os.path.lexists(root):
        yield ("", "missing", None, None)
        return
    try:
        mode = root.lstat().st_mode
    except OSError as exc:
        yield ("", "error", None, str(exc))
        return
    if stat.S_ISLNK(mode):
        yield ("", "symlink", None, os.readlink(root))
        return
    if stat.S_ISREG(mode):
        yield ("", "file", root.stat().st_size, hashlib.sha256(root.read_bytes()).hexdigest())
        return
    if not stat.S_ISDIR(mode):
        yield ("", "other", None, stat.filemode(mode))
        return

    for current, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
        current_path = Path(current)
        dirnames[:] = sorted(dirnames)
        filenames[:] = sorted(filenames)
        for name in tuple(dirnames):
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                yield (relative, "symlink", None, os.readlink(path))
                dirnames.remove(name)
            else:
                yield (relative, "directory", None, None)
        for name in filenames:
            path = current_path / name
            relative = path.relative_to(root).as_posix()
            try:
                entry_mode = path.lstat().st_mode
                if stat.S_ISLNK(entry_mode):
                    yield (relative, "symlink", None, os.readlink(path))
                elif stat.S_ISREG(entry_mode):
                    yield (
                        relative,
                        "file",
                        path.stat().st_size,
                        hashlib.sha256(path.read_bytes()).hexdigest(),
                    )
                else:
                    yield (relative, "other", None, stat.filemode(entry_mode))
            except OSError as exc:
                yield (relative, "error", None, str(exc))


def snapshot_runtime_surfaces(project_root: Path) -> tuple[tuple[str, str, int | None, str | None], ...]:
    """Return a stable content snapshot of the protected live runtime paths."""

    root = project_root.resolve(strict=False)
    result: list[tuple[str, str, int | None, str | None]] = []
    for surface in contract.runtime_mutation_paths(root):
        try:
            label = surface.relative_to(root).as_posix()
        except ValueError:
            label = surface.as_posix()
        for relative, kind, size, digest in _iter_surface_entries(surface):
            result.append((f"{label}/{relative}" if relative else label, kind, size, digest))
    return tuple(sorted(result))


def _canonical_json(document: object) -> bytes:
    return (
        json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
        + "\n"
    ).encode("utf-8")


def _atomic_write_bytes(path: Path, payload: bytes) -> None:
    """Publish bytes with a same-directory temporary file and replace."""

    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "wb") as handle:
            descriptor = -1
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        if descriptor >= 0:
            os.close(descriptor)
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def _validate_output_paths(project_root: Path, report: Path, preview_dir: Path) -> tuple[Path, Path, Path]:
    root = project_root.resolve(strict=False)
    report_abs = _absolute(report)
    preview_abs = _absolute(preview_dir)
    stage = _stage_root(root)
    approved_preview = root / "artifacts/validation-previews/focused-nine"
    if not _contained(root, report_abs) or not _contained(stage, report_abs):
        raise ValueError("report must be under assets/_staging/focused_nine in the project")
    if not _contained(root, preview_abs) or not _contained(approved_preview, preview_abs):
        raise ValueError("preview-dir must be under artifacts/validation-previews/focused-nine")
    return root, report_abs, preview_abs


def _requested_assets(values: Sequence[str] | None) -> tuple[str, ...]:
    if not values:
        return ORDERED_ASSET_IDS
    unknown = sorted(set(values) - set(ORDERED_ASSET_IDS))
    if unknown:
        raise ValueError(f"unknown focused-nine asset id: {unknown[0]!r}")
    duplicates = sorted({asset_id for asset_id in values if values.count(asset_id) > 1})
    if duplicates:
        raise ValueError(f"duplicate focused-nine asset id: {duplicates[0]!r}")
    requested = set(values)
    return tuple(asset_id for asset_id in ORDERED_ASSET_IDS if asset_id in requested)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--structural-source-root", type=Path, required=True)
    parser.add_argument("--props-source-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--preview-dir", type=Path, required=True)
    parser.add_argument("--asset", dest="assets", action="append", metavar="ID")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.assets = _requested_assets(args.assets)
        _validate_output_paths(args.project_root, args.report, args.preview_dir)
    except ValueError as exc:
        parser.error(str(exc))
    return args


def _run(
    command: Sequence[str], *, cwd: Path | None = None, timeout: float | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(command),
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout,
    )


def _failure_output(result: subprocess.CompletedProcess[str]) -> str:
    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    for line in lines:
        if line.startswith(("ERROR:", "Traceback", "Exception", "Error:")):
            return line
    return lines[0] if lines else f"exit {result.returncode}"


def _copy_source_with_blender(seed: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    expression = (
        "import bpy; "
        f"result=bpy.ops.wm.open_mainfile(filepath={str(seed)!r}); "
        "assert 'FINISHED' in result, 'source seed open failed'; "
        f"result=bpy.ops.wm.save_as_mainfile(filepath={str(destination)!r}); "
        "assert 'FINISHED' in result, 'source seed save failed'"
    )
    result = _run([str(BLENDER), "--background", "--factory-startup", "--python-expr", expression])
    if result.returncode != 0 or not destination.is_file():
        raise RuntimeError(
            f"required source blend missing and could not be created: {destination}: {_failure_output(result)}"
        )


def _create_empty_source_with_blender(destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    expression = (
        "import bpy; "
        "bpy.ops.wm.read_factory_settings(use_empty=True); "
        f"result=bpy.ops.wm.save_as_mainfile(filepath={str(destination)!r}); "
        "assert 'FINISHED' in result, 'empty source save failed'"
    )
    result = _run([str(BLENDER), "--background", "--factory-startup", "--python-expr", expression])
    if result.returncode != 0 or not destination.is_file():
        raise RuntimeError(
            f"required source blend missing and could not be created: {destination}: {_failure_output(result)}"
        )


def _choose_seed(root: Path, destination: Path, preferred: Sequence[Path] = ()) -> Path:
    for candidate in preferred:
        if candidate.is_file() and candidate.resolve() != destination.resolve():
            return candidate
    candidates = sorted(path for path in root.rglob("*.blend") if path.is_file() and path.resolve() != destination.resolve())
    if candidates:
        return candidates[0]
    raise FileNotFoundError(f"no valid Blender source seed exists for {destination}")


def _ensure_source(args: argparse.Namespace, asset_id: str) -> Path:
    source = source_blend_path(args.structural_source_root, args.props_source_root, asset_id).resolve(strict=False)
    if source.is_file():
        return source
    # A fresh empty source is deliberate: copying another focused source can
    # carry a namespaced helper collection with a different module_id and is
    # therefore not a valid seed for this asset.
    _create_empty_source_with_blender(source)
    return source


def _run_recipe(args: argparse.Namespace, asset_id: str) -> None:
    result = _run(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python",
            str(RECIPE_SCRIPT),
            "--",
            "--project-root",
            str(args.project_root),
            "--structural-source-root",
            str(args.structural_source_root),
            "--props-source-root",
            str(args.props_source_root),
            "--asset-id",
            asset_id,
            "--overwrite-generated-only",
        ]
    )
    if result.returncode != 0:
        raise RuntimeError(f"focused-nine recipe failed for {asset_id}: {_failure_output(result)}")


def _run_structural_export(source: Path, asset_id: str, destination: Path) -> tuple[Path, ...]:
    destination.mkdir(parents=True, exist_ok=True)
    result = _run(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python",
            str(EXPORT_SCRIPT),
            "--",
            "--blend-path",
            str(source),
            "--staging-dir",
            str(destination),
            "--module",
            asset_id,
        ]
    )
    if result.returncode != 0:
        raise RuntimeError(f"focused-nine export failed for {asset_id}: {_failure_output(result)}")
    paths = tuple(sorted(destination.glob(f"{asset_id}*.glb")))
    expected_roles = contract.VARIANT_ROLES.get(asset_id, ("intact",))
    expected = tuple(destination / (f"{asset_id}.glb" if role == "intact" else f"{asset_id}_{role}.glb") for role in expected_roles)
    if set(paths) != set(expected) or len(paths) != len(expected):
        raise RuntimeError(f"focused-nine export produced incomplete roles for {asset_id}")
    return expected


def _props_export_expression(source: Path, collection_name: str, output: Path) -> str:
    return (
        "import bpy; "
        f"result=bpy.ops.wm.open_mainfile(filepath={str(source)!r}); "
        "assert 'FINISHED' in result, 'prop source open failed'; "
        f"collection=bpy.data.collections.get({collection_name!r}); "
        "assert collection is not None, 'generated prop collection missing'; "
        "bpy.ops.object.select_all(action='DESELECT'); "
        "objects=[obj for obj in collection.objects if obj.type == 'MESH']; "
        "assert objects, 'generated prop collection has no mesh'; "
        "[obj.select_set(True) for obj in objects]; "
        "bpy.context.view_layer.objects.active=objects[0]; "
        f"result=bpy.ops.export_scene.gltf(filepath={str(output)!r}, export_format='GLB', export_apply=True, use_selection=True); "
        "assert 'CANCELLED' not in result, 'prop GLB export cancelled'"
    )


def _run_prop_export(source: Path, asset_id: str, destination: Path) -> tuple[Path, ...]:
    destination.mkdir(parents=True, exist_ok=True)
    output = destination / f".{asset_id}.tmp.glb"
    result = _run(
        [
            str(BLENDER),
            "--background",
            "--factory-startup",
            "--python-expr",
            _props_export_expression(source, f"FocusedNine_{asset_id}_Generated", output),
        ]
    )
    if result.returncode != 0 or not output.is_file() or output.stat().st_size <= 0:
        raise RuntimeError(f"focused-nine prop export failed for {asset_id}: {_failure_output(result)}")
    final = destination / f"{asset_id}.glb"
    os.replace(output, final)
    return (final,)


def _gate_prop_sidecar(project_root: Path, glb_path: Path, asset_id: str, output: Path) -> dict[str, Any]:
    """Run Task 5's strict validator in a canonical disposable project."""

    with tempfile.TemporaryDirectory(prefix="focused-nine-sidecar-gate-") as temporary:
        gate_project = Path(temporary)
        gate_glb = gate_project / "assets/_staging/focused_nine/props" / f"{asset_id}.glb"
        gate_glb.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(glb_path, gate_glb)
        sidecar = staged_props.build_staged_sidecar(gate_project, gate_glb, asset_id)
        errors = staged_props.validate_staged_sidecar(gate_project, gate_glb, sidecar)
        if errors:
            raise ValueError(f"staged prop sidecar validation failed for {asset_id}: {'; '.join(errors)}")
    _atomic_write_bytes(output, _canonical_json(sidecar))
    return sidecar


def _metrics_from_evidence(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "sha256": record["sha256"],
        "byte_size": record["byte_size"],
        "mesh_count": record["mesh_count"],
        "triangle_count": record["triangle_count"],
        "material_names": list(record["material_names"]),
        "bounds": {
            "local_min_m": list(record["local_min_m"]),
            "local_max_m": list(record["local_max_m"]),
        },
    }


def _empty_metrics() -> dict[str, Any]:
    return {
        "sha256": "0" * 64,
        "byte_size": 0,
        "mesh_count": 0,
        "triangle_count": 0,
        "material_names": ["unavailable"],
        "bounds": {"local_min_m": [0.0, 0.0, 0.0], "local_max_m": [0.0, 0.0, 0.0]},
    }


def _asset_record(
    project_root: Path,
    args: argparse.Namespace,
    asset_id: str,
    source: Path | None,
    staged_paths: Sequence[Path],
    metrics: dict[str, Any],
    validations: Sequence[str],
    passed: bool,
    first_error: str | None,
    role_metrics: dict[str, Any] | None = None,
) -> dict[str, Any]:
    kind = "structural" if asset_id in contract.STRUCTURAL_IDS else "prop"
    # Use the contract helper for exact role spelling, never a filesystem glob.
    staged_glbs = [
        f"res://{contract.asset_stage_glb(project_root, asset_id, role).relative_to(project_root.resolve()).as_posix()}"
        for role in contract.VARIANT_ROLES.get(asset_id, ("intact",))
    ]
    if kind == "prop":
        staged_glbs = [
            f"res://{contract.asset_stage_glb(project_root, asset_id).relative_to(project_root.resolve()).as_posix()}"
        ]
    return {
        "asset_id": asset_id,
        "kind": "prop" if kind == "prop" else "structural",
        "source_path": _source_reference(asset_id) if source is None else _source_reference(asset_id),
        "staged_glbs": staged_glbs,
        "metrics": metrics,
        "validation": list(validations),
        "pass": passed,
        "first_error": first_error,
    }


def _publish_structural_asset(private: Path, final: Path) -> None:
    final.parent.mkdir(parents=True, exist_ok=True)
    backup: Path | None = None
    if final.exists() or final.is_symlink():
        backup = final.with_name(f".{final.name}.previous-{next(tempfile._get_candidate_names())}")
        os.replace(final, backup)
    try:
        os.replace(private, final)
    except BaseException:
        if backup is not None and not final.exists():
            os.replace(backup, final)
        raise
    if backup is not None:
        shutil.rmtree(backup, ignore_errors=True)


def _publish_prop_asset(private_glb: Path, private_sidecar: Path, final_glb: Path, final_sidecar: Path) -> None:
    final_glb.parent.mkdir(parents=True, exist_ok=True)
    previous: list[tuple[Path, Path]] = []
    try:
        for source, target in ((private_glb, final_glb), (private_sidecar, final_sidecar)):
            if target.exists() or target.is_symlink():
                backup = target.with_name(f".{target.name}.previous-{next(tempfile._get_candidate_names())}")
                os.replace(target, backup)
                previous.append((target, backup))
            os.replace(source, target)
    except BaseException:
        for target, backup in reversed(previous):
            if target.exists():
                target.unlink()
            os.replace(backup, target)
        raise
    for _target, backup in previous:
        backup.unlink(missing_ok=True)


def _copy_pressure_package(private_root: Path, project_root: Path) -> None:
    source = project_root / PRESSURE_PACKAGE
    target = private_root / "structural/pressure_door_1x1"
    if not source.is_dir():
        raise FileNotFoundError(f"pressure-door staged wrapper package is missing: {source}")
    target.mkdir(parents=True, exist_ok=True)
    for filename in ("pressure_door_1x1.manifest.json", "pressure_door_1x1.input.json", "pressure_door_1x1.tscn"):
        shutil.copy2(source / filename, target / filename)


def _process_asset(args: argparse.Namespace, asset_id: str, private_root: Path) -> tuple[dict[str, Any], Path | None, dict[str, Any]]:
    if os.environ.get("FOCUSED_NINE_FORCE_EXPORT_FAILURE") == "1":
        error = f"forced export failure: {asset_id}"
        return (_asset_record(args.project_root, args, asset_id, None, (), _empty_metrics(), [error], False, error), None, {})

    source = _ensure_source(args, asset_id)
    _run_recipe(args, asset_id)
    kind = "structural" if asset_id in contract.STRUCTURAL_IDS else "prop"
    role_metrics: dict[str, Any] = {}
    if kind == "structural":
        destination = private_root / "structural" / asset_id
        staged = _run_structural_export(source, asset_id, destination)
    else:
        destination = private_root / "props"
        staged = _run_prop_export(source, asset_id, destination)
        sidecar_path = destination / f"{asset_id}.sidecar.json"
        sidecar = _gate_prop_sidecar(args.project_root, staged[0], asset_id, sidecar_path)
        role_metrics["sidecar"] = sidecar

    evidence_records: dict[str, dict[str, Any]] = {}
    for path in staged:
        record = evidence.inspect_staged_glb(path, BLENDER)
        errors = evidence.validate_evidence(
            record,
            *evidence.DEFAULT_TRIANGLE_BUDGETS["structural" if kind == "structural" else "prop"],
        )
        if errors:
            raise ValueError(f"evidence validation failed for {asset_id}: {'; '.join(errors)}")
        role = "intact" if path.name == f"{asset_id}.glb" else path.stem.removeprefix(f"{asset_id}_")
        evidence_records[role] = record
    if kind == "structural" and asset_id == "pressure_door_1x1":
        _copy_pressure_package(private_root, args.project_root)
    intact = evidence_records["intact"]
    for role, record in evidence_records.items():
        role_metrics[role] = _metrics_from_evidence(record)
    return (
        _asset_record(args.project_root, args, asset_id, source, staged, _metrics_from_evidence(intact), (), True, None, role_metrics),
        source,
        role_metrics,
    )


def _run_pressure_overlay(project_root: Path, private_root: Path) -> list[str]:
    return staged_structural.validate_pressure_door_overlay(project_root, private_root, GODOT)


def _preview_relative(project_root: Path, preview_dir: Path) -> str:
    stable = preview_dir / "focused-nine-comparison.png"
    return _canonical_res_path(project_root, stable)


def _capture_output(result: subprocess.CompletedProcess[str] | subprocess.TimeoutExpired) -> str:
    parts: list[str] = []
    for part in (getattr(result, "stdout", None), getattr(result, "stderr", None)):
        if isinstance(part, bytes):
            part = part.decode(errors="replace")
        if part:
            parts.append(str(part))
    return "\n".join(parts).strip()


def _cleanup_capture_temporary_files(preview_dir: Path) -> None:
    """Remove only regular capture temporary leaves after an interrupted run."""

    try:
        if preview_dir.is_symlink() or not preview_dir.is_dir():
            return
        for path in preview_dir.iterdir():
            if not path.name.startswith(".focused-nine-comparison") or path.is_symlink():
                continue
            try:
                if stat.S_ISREG(path.lstat().st_mode):
                    path.unlink()
            except OSError:
                continue
    except OSError:
        return


def _run_capture(project_root: Path, preview_dir: Path) -> tuple[bool, str | None, str]:
    try:
        output_relative = preview_dir.resolve().relative_to(project_root.resolve()).as_posix()
    except ValueError:
        return False, "capture output is outside the project", ""
    try:
        result = _run(
            [
                str(GODOT),
                "--path",
                str(project_root),
                "--scene",
                _CAPTURE_SCENE,
                "--",
                "--output-dir",
                f"res://{output_relative}",
                "--baseline-label",
                "Baseline",
                "--improved-label",
                "Improved",
            ],
            cwd=project_root,
            timeout=CAPTURE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as exc:
        _cleanup_capture_temporary_files(preview_dir)
        return (
            False,
            f"comparison capture blocker: timed out after {CAPTURE_TIMEOUT_SECONDS} seconds",
            _capture_output(exc),
        )
    output = _capture_output(result)
    marker = "FOCUSED_NINE_COMPARISON_CAPTURE PASS output="
    if result.returncode != 0:
        detail = next((line.strip() for line in output.splitlines() if line.strip()), f"exit {result.returncode}")
        return False, f"comparison capture blocker: {detail}", output
    if marker not in output:
        return False, "comparison capture blocker: missing FOCUSED_NINE_COMPARISON_CAPTURE PASS marker", output
    stable = preview_dir / "focused-nine-comparison.png"
    if not stable.is_file() or stable.stat().st_size <= 0:
        return False, "comparison capture blocker: stable preview was not published", output
    return True, None, output


def _run_live_validators(args: argparse.Namespace) -> tuple[list[str], list[str]]:
    structural = _run(
        [
            sys.executable,
            str(Path(__file__).with_name("validate_structural_sources.py")),
            "--project-root",
            str(args.project_root),
            "--source-root",
            str(args.structural_source_root),
            "--all",
            "--blender",
            str(BLENDER),
        ],
        cwd=args.project_root,
    )
    props = _run(
        [
            sys.executable,
            str(Path(__file__).with_name("validate_prop_visual_bindings.py")),
            "--project-root",
            str(args.project_root),
            "--check-index",
        ],
        cwd=args.project_root,
    )
    return (
        [] if structural.returncode == 0 else [f"live structural source validator: {_failure_output(structural)}"],
        [] if props.returncode == 0 else [f"live prop index validator: {_failure_output(props)}"],
    )


def _build_report(
    project_root: Path,
    report_path: Path,
    preview_dir: Path,
    records: list[dict[str, Any]],
    source_paths: dict[str, str],
    role_metrics: dict[str, dict[str, Any]],
    *,
    runtime_unchanged: bool,
    capture_attempted: bool = False,
    capture_blocker: str | None = None,
    validator_errors: Sequence[str] = (),
) -> dict[str, Any]:
    blockers = list(validator_errors)
    if capture_blocker:
        blockers.append(capture_blocker)
    if not runtime_unchanged:
        blockers.append("runtime mutation surface content changed")
    if blockers:
        blocker = blockers[0]
        for asset in records:
            if asset["pass"]:
                asset["pass"] = False
                asset["validation"] = [blocker]
                asset["first_error"] = blocker
    overall = bool(records) and all(asset["pass"] for asset in records) and not blockers
    report = {
        "schema_version": "1.0.0",
        "document_kind": "focused_nine_comparison",
        "assets": records,
        "baseline": {
            "label": "current-runtime",
            "asset_count": len(records),
            "runtime_surfaces_unchanged": runtime_unchanged,
            "no_runtime_promotion": True,
        },
        "improved": {
            "label": "focused-nine-staged",
            "asset_count": len(records),
            "source_paths": source_paths,
            "asset_role_metrics": role_metrics,
            "no_runtime_promotion": True,
        },
        "preview": {
            "path": _preview_relative(project_root, preview_dir),
            "capture_status": (
                "pass"
                if capture_attempted and capture_blocker is None and not validator_errors
                else "blocked"
                if capture_blocker or validator_errors
                else "not_run"
            ),
            "capture_blocker": capture_blocker,
            "validator_errors": list(validator_errors),
            "no_runtime_promotion": True,
        },
        "overall_pass": overall,
    }
    errors = validate_report(report)
    if errors:
        raise ValueError("focused-nine report schema failed: " + "; ".join(errors))
    return report


def _write_proof(project_root: Path, records: Sequence[dict[str, Any]], source_paths: dict[str, str], report_path: Path, preview_dir: Path) -> None:
    lines = [
        "# Focused-nine comparison evidence",
        "",
        "The focused-nine comparison batch passed its staging, evidence, pressure-door overlay, live-validator, and windowed-capture gates.",
        "",
        "**No runtime promotion occurred.** Runtime imported assets, generated catalogs, kit data, and live wrapper surfaces were not modified.",
        "",
        f"- Report: `{report_path.relative_to(project_root).as_posix()}`",
        f"- Preview: `{(preview_dir / 'focused-nine-comparison.png').relative_to(project_root).as_posix()}`",
        "",
        "| Asset | Source | Staged GLBs | SHA-256 | Bytes | Triangles | Meshes | Materials |",
        "| --- | --- | --- | --- | ---: | ---: | ---: | --- |",
    ]
    for asset in records:
        metrics = asset["metrics"]
        lines.append(
            f"| `{asset['asset_id']}` | `{source_paths[asset['asset_id']]}` | "
            f"{', '.join(f'`{path}`' for path in asset['staged_glbs'])} | "
            f"`{metrics['sha256']}` | {metrics['byte_size']} | {metrics['triangle_count']} | "
            f"{metrics['mesh_count']} | {', '.join(metrics['material_names'])} |"
        )
    lines.extend(("", "Acceptance marker: `FOCUSED_NINE_BATCH PASS assets=9`", ""))
    _atomic_write_bytes(project_root / PROOF_RELATIVE, "\n".join(lines).encode("utf-8"))


def main(argv: Sequence[str] | None = None) -> int:
    try:
        args = parse_args(argv)
        project_root, report_path, preview_dir = _validate_output_paths(
            args.project_root, args.report, args.preview_dir
        )
        before_runtime = snapshot_runtime_surfaces(project_root)
        if args.dry_run:
            print("FOCUSED_NINE_BATCH DRY_RUN assets=" + str(len(args.assets)))
            return 0

        stage_root = _stage_root(project_root)
        stage_root.mkdir(parents=True, exist_ok=True)
        records: list[dict[str, Any]] = []
        source_paths: dict[str, str] = {}
        role_metrics: dict[str, dict[str, Any]] = {}
        published_assets: list[tuple[str, Path]] = []

        for asset_id in args.assets:
            with tempfile.TemporaryDirectory(prefix=f".focused-nine-{asset_id}-", dir=str(stage_root)) as temporary:
                private_root = Path(temporary)
                try:
                    record, source, roles = _process_asset(args, asset_id, private_root)
                    records.append(record)
                    if source is not None:
                        source_paths[asset_id] = str(source)
                    role_metrics[asset_id] = roles
                    if record["pass"]:
                        if asset_id in contract.STRUCTURAL_IDS:
                            private_asset = private_root / "structural" / asset_id
                            _publish_structural_asset(private_asset, contract.asset_stage_dir(project_root, asset_id))
                        else:
                            _publish_prop_asset(
                                private_root / "props" / f"{asset_id}.glb",
                                private_root / "props" / f"{asset_id}.sidecar.json",
                                contract.asset_stage_glb(project_root, asset_id),
                                contract.asset_stage_glb(project_root, asset_id).with_name(f"{asset_id}.sidecar.json"),
                            )
                        published_assets.append((asset_id, contract.asset_stage_dir(project_root, asset_id)))
                    else:
                        continue
                except BaseException as exc:
                    message = str(exc) or f"{type(exc).__name__}"
                    records.append(
                        _asset_record(project_root, args, asset_id, None, (), _empty_metrics(), [message], False, message)
                    )

        report_records: dict[str, dict[str, Any]] = {record["asset_id"]: record for record in records}
        for asset_id in ORDERED_ASSET_IDS:
            if asset_id not in report_records:
                error = f"asset not requested by subset CLI: {asset_id}"
                report_records[asset_id] = _asset_record(
                    project_root,
                    args,
                    asset_id,
                    None,
                    (),
                    _empty_metrics(),
                    [error],
                    False,
                    error,
                )
        records = [report_records[asset_id] for asset_id in ORDERED_ASSET_IDS]

        full_batch = args.assets == ORDERED_ASSET_IDS
        capture_blocker: str | None = None
        validator_errors: list[str] = []
        if full_batch and all(record["pass"] for record in records) and len(records) == 9:
            # Wrapper validation consumes the temporary staged package.  Rebuild
            # a disposable root from the published candidate only for this gate.
            with tempfile.TemporaryDirectory(prefix="focused-nine-pressure-gate-", dir=str(stage_root)) as temporary:
                gate_root = Path(temporary)
                gate_pressure = gate_root / "structural/pressure_door_1x1"
                gate_pressure.mkdir(parents=True, exist_ok=True)
                for path in (contract.asset_stage_glb(project_root, "pressure_door_1x1", role) for role in ("intact", "damaged", "breached")):
                    shutil.copy2(path, gate_pressure / path.name)
                _copy_pressure_package(gate_root, project_root)
                overlay_errors = _run_pressure_overlay(project_root, gate_root)
                if overlay_errors:
                    capture_blocker = "pressure-door overlay blocker: " + "; ".join(overlay_errors)
            if capture_blocker is None:
                captured, capture_blocker, _capture_output = _run_capture(project_root, preview_dir)
                if not captured and capture_blocker is None:
                    capture_blocker = "comparison capture blocker: capture did not complete"
        if full_batch:
            structural_errors, prop_errors = _run_live_validators(args)
            validator_errors.extend(structural_errors)
            validator_errors.extend(prop_errors)

        after_runtime = snapshot_runtime_surfaces(project_root)
        runtime_unchanged = before_runtime == after_runtime
        report = _build_report(
            project_root,
            report_path,
            preview_dir,
            records,
            source_paths,
            role_metrics,
            runtime_unchanged=runtime_unchanged,
            capture_attempted=full_batch and all(record["pass"] for record in records) and len(records) == 9,
            capture_blocker=capture_blocker,
            validator_errors=validator_errors,
        )
        _atomic_write_bytes(report_path, _canonical_json(report))

        if report["overall_pass"] and full_batch:
            _write_proof(project_root, records, source_paths, report_path, preview_dir)
            print(f"FOCUSED_NINE_REPORT path={report_path}")
            print("FOCUSED_NINE_BATCH PASS assets=9")
            return 0
        print(f"FOCUSED_NINE_REPORT path={report_path}")
        for record in records:
            if record["pass"]:
                print(f"FOCUSED_NINE_STAGED asset={record['asset_id']}")
        return 1
    except (OSError, RuntimeError, TypeError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
