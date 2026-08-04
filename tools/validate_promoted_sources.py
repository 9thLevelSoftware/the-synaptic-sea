#!/usr/bin/env python3
"""Validate staged structural GLBs through a temporary Godot project overlay.

The validator never writes into the checkout.  It copies the project into a
private temporary directory, overlays the selected module's staged GLBs at the
canonical runtime path, then runs Godot's importer and the structural wrapper
smoke against that copy.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Sequence

try:
    from tools.structural_source_contract import STRUCTURAL_SOURCE_MODULE_IDS
except ModuleNotFoundError:
    # Allow ``python tools/validate_promoted_sources.py`` from a checkout.
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools.structural_source_contract import STRUCTURAL_SOURCE_MODULE_IDS


_STRUCTURAL_RUNTIME_ROOT = Path("assets/imported/structural/ship_structural_v0")
_STRUCTURAL_SMOKE_SCRIPT = Path("scripts/validation/structural_variant_wrapper_smoke.gd")
_DIAGNOSTIC_MARKERS = ("ERROR:", "WARNING:", "SCRIPT ERROR:")
_OVERLAY_IGNORED_NAMES = (
    ".git",
    ".godot",
    ".hermes",
    ".mypy_cache",
    ".omh",
    ".pytest_cache",
    ".ruff_cache",
    ".serena",
    ".superpowers",
    "__pycache__",
)


def validate_glb_magic(path: Path) -> list[str]:
    """Check GLB magic bytes and return deterministic diagnostics."""

    path = Path(path)
    try:
        with path.open("rb") as source:
            magic = source.read(4)
    except OSError as exc:
        return [f"cannot read GLB {path}: {exc}"]

    if magic != b"glTF":
        return [f"invalid GLB magic: {path}"]
    return []


def _validate_module_id(module_id: str) -> None:
    if module_id not in STRUCTURAL_SOURCE_MODULE_IDS:
        raise ValueError(f"unsupported structural source module: {module_id!r}")


def _staged_module_dir(staging_root: Path, module_id: str) -> Path:
    return Path(staging_root).expanduser().resolve() / module_id


def _find_staged_glbs(staging_root: Path, module_id: str) -> tuple[Path, ...]:
    module_dir = _staged_module_dir(staging_root, module_id)
    if not module_dir.is_dir():
        return ()
    return tuple(sorted((path for path in module_dir.glob("*.glb") if path.is_file()), key=str))


def _overlay_project(project_root: Path, overlay_root: Path) -> None:
    """Copy the project into an isolated directory, excluding editor caches."""

    ignore = shutil.ignore_patterns(*_OVERLAY_IGNORED_NAMES)
    shutil.copytree(project_root, overlay_root, symlinks=True, ignore=ignore)


def _copy_staged_glbs(
    overlay_root: Path, module_id: str, staged_glbs: Sequence[Path]
) -> None:
    destination_root = overlay_root / _STRUCTURAL_RUNTIME_ROOT / module_id
    destination_root.mkdir(parents=True, exist_ok=True)
    for source in staged_glbs:
        shutil.copy2(source, destination_root / source.name)


def _godot_diagnostics(output: str) -> list[str]:
    """Return output lines containing any gate-blocking Godot diagnostic marker."""

    return [
        line.strip()
        for line in output.splitlines()
        if any(marker in line for marker in _DIAGNOSTIC_MARKERS) and line.strip()
    ]


def _run_godot(command: Sequence[str], overlay_root: Path, label: str) -> list[str]:
    try:
        completed = subprocess.run(
            list(command),
            cwd=str(overlay_root),
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        return [f"cannot invoke Godot for {label}: {exc}"]

    stdout = getattr(completed, "stdout", "") or ""
    stderr = getattr(completed, "stderr", "") or ""
    diagnostics = _godot_diagnostics(f"{stdout}\n{stderr}")
    if completed.returncode != 0 and not diagnostics:
        diagnostics.append(f"Godot {label} failed: exit {completed.returncode}")
    return diagnostics


def validate_staged_module(
    project_root: Path,
    staging_root: Path,
    module_id: str,
    skip_godot: bool = False,
) -> list[str]:
    """Validate one module's staged GLBs and optional Godot smoke checks."""

    try:
        _validate_module_id(module_id)
    except ValueError as exc:
        return [str(exc)]

    project_root = Path(project_root).expanduser().resolve()
    staging_module = _staged_module_dir(Path(staging_root), module_id)
    staged_glbs = _find_staged_glbs(Path(staging_root), module_id)
    if not staged_glbs:
        return [
            f"missing staged GLB: {module_id} (staging directory or .glb files not found: "
            f"{staging_module})"
        ]

    errors: list[str] = []
    for staged_glb in staged_glbs:
        try:
            if staged_glb.stat().st_size == 0:
                errors.append(f"empty staged GLB: {staged_glb}")
                continue
        except OSError as exc:
            errors.append(f"cannot stat staged GLB {staged_glb}: {exc}")
            continue
        errors.extend(validate_glb_magic(staged_glb))

    if errors or skip_godot:
        return errors

    godot = os.environ.get("GODOT", "/opt/homebrew/bin/godot")
    with tempfile.TemporaryDirectory(prefix="structural-validation-") as temporary:
        overlay_root = Path(temporary) / "project"
        try:
            _overlay_project(project_root, overlay_root)
            _copy_staged_glbs(overlay_root, module_id, staged_glbs)
        except OSError as exc:
            return [f"cannot create validation overlay for {module_id}: {exc}"]

        import_command = [
            godot,
            "--headless",
            "--import",
            "--path",
            str(overlay_root),
        ]
        errors.extend(_run_godot(import_command, overlay_root, f"import {module_id}"))
        if errors:
            return errors

        smoke_command = [
            godot,
            "--headless",
            "--path",
            str(overlay_root),
            "--script",
            f"res://{_STRUCTURAL_SMOKE_SCRIPT.as_posix()}",
        ]
        errors.extend(_run_godot(smoke_command, overlay_root, f"structural smoke {module_id}"))

    return errors


def validate_all(
    project_root: Path,
    staging_root: Path,
    module_ids: Sequence[str],
    skip_godot: bool = False,
) -> list[str]:
    """Validate every requested module and return all diagnostics."""

    errors: list[str] = []
    for module_id in module_ids:
        errors.extend(
            f"{module_id}: {error}"
            for error in validate_staged_module(
                project_root,
                staging_root,
                module_id,
                skip_godot=skip_godot,
            )
        )
    return errors


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        required=True,
        type=Path,
        help="Godot project root to copy into the validation overlay",
    )
    parser.add_argument(
        "--staging-root",
        required=True,
        type=Path,
        help="directory containing staged module GLBs",
    )
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument(
        "--module",
        action="append",
        metavar="MODULE_ID",
        help="validate one module; repeat for multiple modules",
    )
    selection.add_argument(
        "--all",
        action="store_true",
        help="validate all allowlisted structural source modules",
    )
    parser.add_argument(
        "--skip-godot",
        action="store_true",
        help="validate staged GLBs without running Godot",
    )
    return parser


def _selected_module_ids(args: argparse.Namespace) -> tuple[str, ...]:
    if args.all:
        return STRUCTURAL_SOURCE_MODULE_IDS
    return tuple(args.module)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = build_parser()
    args = parser.parse_args(argv)
    invalid = [
        module_id
        for module_id in _selected_module_ids(args)
        if module_id not in STRUCTURAL_SOURCE_MODULE_IDS
    ]
    if invalid:
        parser.error(
            "unsupported structural source module(s): "
            + ", ".join(repr(module_id) for module_id in invalid)
        )
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    module_ids = _selected_module_ids(args)
    errors = validate_all(
        args.project_root,
        args.staging_root,
        module_ids,
        skip_godot=args.skip_godot,
    )
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"STRUCTURAL_VALIDATION_PASS modules={len(module_ids)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
