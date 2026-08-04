#!/usr/bin/env python3
"""Promote recovered structural Blender sources through a staged GLB pipeline.

The orchestrator deliberately keeps Blender and Godot subprocesses at the
edges of the pipeline.  Hashing, skip decisions, and copying are ordinary
Python operations so they can be tested without either editor installed.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from typing import Mapping, Sequence

try:
    from tools.backup_structural_sources import (
        BackupError,
        backup_sources,
    )
    from tools.structural_source_contract import (
        STRUCTURAL_SOURCE_MODULE_IDS,
        load_source_spec,
        source_output_paths,
    )
except ModuleNotFoundError:
    # Allow ``python tools/promote_structural_sources.py`` from a checkout.
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools.backup_structural_sources import (
        BackupError,
        backup_sources,
    )
    from tools.structural_source_contract import (
        STRUCTURAL_SOURCE_MODULE_IDS,
        load_source_spec,
        source_output_paths,
    )


_RUNTIME_ROOT = Path("assets/imported/structural/ship_structural_v0")
_VARIANT_SUFFIXES: tuple[tuple[str, str], ...] = (
    ("intact", ""),
    ("damaged", "_damaged"),
    ("breached", "_breached"),
)
_VARIANT_NAMES = frozenset(variant for variant, _ in _VARIANT_SUFFIXES)
_EXPORT_SCRIPT = Path(__file__).resolve().with_name("export_structural_glb.py")


class PromotionError(RuntimeError):
    """Raised after one or more modules fail without stopping other modules."""


def compute_glb_hash(path: Path) -> str:
    """Return the SHA-256 hex digest of a GLB file."""

    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def should_skip_promotion(staged: Path, runtime: Path, *, force: bool) -> bool:
    """Return whether identical staged/runtime GLBs may be left untouched."""

    if force or not Path(staged).is_file() or not Path(runtime).is_file():
        return False
    return compute_glb_hash(Path(staged)) == compute_glb_hash(Path(runtime))


def _validate_module_id(module_id: str) -> str:
    if module_id not in STRUCTURAL_SOURCE_MODULE_IDS:
        raise ValueError(f"unsupported structural source module: {module_id!r}")
    return module_id


def _variant_glb_path(directory: Path, module_id: str, variant: str) -> Path:
    if variant not in _VARIANT_NAMES:
        raise ValueError(f"unsupported structural source variant: {variant!r}")
    suffix = dict(_VARIANT_SUFFIXES)[variant]
    return directory / f"{module_id}{suffix}.glb"


def _runtime_glb_path(project_root: Path, module_id: str, variant: str) -> Path:
    _validate_module_id(module_id)
    return project_root / _RUNTIME_ROOT / module_id / _variant_glb_path(
        Path(), module_id, variant
    ).name


def _blender_executable() -> str:
    return os.environ.get("BLENDER", "blender")


def _clean_staging_glbs(staging_dir: Path) -> None:
    """Remove only prior GLB exports, preserving other staging metadata."""

    staging_dir.mkdir(parents=True, exist_ok=True)
    for path in staging_dir.glob("*.glb"):
        if path.is_file() or path.is_symlink():
            path.unlink()


def export_module_to_staging(
    project_root: Path,
    source_root: Path,
    staging_root: Path,
    module_id: str,
) -> dict[str, Path]:
    """Run Blender's exporter and return staged GLBs keyed by variant."""

    _validate_module_id(module_id)
    project_root = Path(project_root).expanduser().resolve()
    staging_dir = Path(staging_root).expanduser().resolve() / module_id
    blend_path, _record_path = source_output_paths(
        Path(source_root).expanduser(), module_id
    )
    blend_path = blend_path.expanduser().resolve()
    if not blend_path.is_file():
        raise FileNotFoundError(f"missing recovered Blender source: {blend_path}")

    # Export into a private child directory.  The existing final staging GLBs
    # are not touched until Blender has completed successfully and all output
    # files have been checked.
    staging_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".tmp_export-", dir=str(staging_dir)) as temporary:
        export_dir = Path(temporary)
        command = [
            _blender_executable(),
            "--background",
            "--factory-startup",
            "--python",
            str(_EXPORT_SCRIPT),
            "--",
            "--blend-path",
            str(blend_path),
            "--staging-dir",
            str(export_dir),
            "--module",
            module_id,
        ]
        try:
            completed = subprocess.run(
                command,
                cwd=str(project_root),
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as exc:
            raise PromotionError(f"cannot invoke Blender for {module_id}: {exc}") from exc

        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            suffix = f": {detail}" if detail else f": exit {completed.returncode}"
            raise PromotionError(f"Blender export failed for {module_id}{suffix}")

        exported: dict[str, Path] = {}
        for variant, _suffix in _VARIANT_SUFFIXES:
            path = _variant_glb_path(export_dir, module_id, variant)
            if path.is_file():
                if path.stat().st_size <= 0:
                    raise PromotionError(f"Blender exported an empty GLB: {path}")
                exported[variant] = path

        if not exported:
            raise PromotionError(f"Blender exported no GLBs for {module_id}")

        # Commit only validated outputs.  Metadata and non-GLB files in the
        # final staging directory remain untouched.
        _clean_staging_glbs(staging_dir)
        committed: dict[str, Path] = {}
        for variant, source in exported.items():
            destination = _variant_glb_path(staging_dir, module_id, variant)
            shutil.move(str(source), destination)
            committed[variant] = destination
        return committed


def _copy_atomic(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.promote.tmp")
    temporary.unlink(missing_ok=True)
    try:
        shutil.copy2(source, temporary)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def promote_module(
    project_root: Path,
    staging_root: Path,
    module_id: str,
    exported: Mapping[str, Path],
    *,
    dry_run: bool = False,
) -> list[str]:
    """Copy staged GLBs to runtime and return destination paths.

    Existing Godot ``.import`` files are not touched.  Copies use a temporary
    sibling followed by ``os.replace`` so an interrupted promotion cannot
    leave a partially-written runtime GLB.
    """

    _validate_module_id(module_id)
    project_root = Path(project_root).expanduser().resolve()
    staging_module = Path(staging_root).expanduser().resolve() / module_id
    promoted: list[str] = []

    for variant, source in sorted(
        exported.items(), key=lambda item: dict(_VARIANT_SUFFIXES).get(item[0], item[0])
    ):
        if variant not in _VARIANT_NAMES:
            raise ValueError(f"unsupported structural source variant: {variant!r}")
        source_path = Path(source).expanduser().resolve()
        if not source_path.is_file():
            raise FileNotFoundError(f"missing staged GLB for {module_id}/{variant}: {source}")
        expected_staged = _variant_glb_path(staging_module, module_id, variant)
        if source_path != expected_staged:
            raise ValueError(
                f"staged GLB is outside module staging directory: {source_path}"
            )
        destination = _runtime_glb_path(project_root, module_id, variant)
        if not dry_run:
            _copy_atomic(source_path, destination)
        promoted.append(str(destination))
    return promoted


def _run_godot_import_smoke(
    project_root: Path,
    module_id: str,
    exported: Mapping[str, Path],
) -> None:
    """Import staged GLBs in a temporary minimal Godot project overlay."""

    for source in exported.values():
        path = Path(source)
        with path.open("rb") as handle:
            magic = handle.read(5)
        if not (magic.startswith(b"glTF") or magic.startswith(b"\x00glTF")):
            raise PromotionError(f"invalid GLB magic for staged file: {path}")

    godot = os.environ.get("GODOT", "/opt/homebrew/bin/godot")
    with tempfile.TemporaryDirectory(prefix="structural-promotion-") as temporary:
        overlay = Path(temporary)
        (overlay / "project.godot").write_text(
            "config_version=5\n"
            "\n[application]\n"
            f'config/name="Structural promotion smoke {module_id}"\n',
            encoding="utf-8",
        )
        for variant, source in exported.items():
            destination = overlay / _RUNTIME_ROOT / module_id / _variant_glb_path(
                Path(), module_id, variant
            ).name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(Path(source), destination)

        command = [godot, "--headless", "--editor", "--path", str(overlay), "--quit"]
        try:
            completed = subprocess.run(
                command,
                cwd=str(project_root),
                capture_output=True,
                text=True,
                check=False,
            )
        except OSError as exc:
            raise PromotionError(f"cannot invoke Godot for {module_id}: {exc}") from exc
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            suffix = f": {detail}" if detail else f": exit {completed.returncode}"
            raise PromotionError(f"Godot import smoke failed for {module_id}{suffix}")


def _dry_run_module(
    project_root: Path,
    source_root: Path,
    staging_root: Path,
    module_id: str,
) -> None:
    """Validate one source and print the export plan without side effects."""

    blend_path, _record_path = source_output_paths(
        Path(source_root).expanduser(), module_id
    )
    blend_path = blend_path.expanduser().resolve()
    if not blend_path.is_file():
        raise FileNotFoundError(f"missing recovered Blender source: {blend_path}")
    load_source_spec(project_root, module_id)
    staging_dir = Path(staging_root).expanduser().resolve() / module_id
    planned_glbs = ",".join(
        str(_variant_glb_path(staging_dir, module_id, variant).name)
        for variant, _suffix in _VARIANT_SUFFIXES
    )
    print(
        "STRUCTURAL_PROMOTION_PLAN "
        f"module={module_id} blend={blend_path} "
        f"source_spec=loaded staging={staging_dir} glbs={planned_glbs}"
    )


def promote_all(
    project_root: Path,
    source_root: Path,
    staging_root: Path,
    module_ids: Sequence[str],
    *,
    dry_run: bool = False,
    force: bool = False,
    skip_godot: bool = False,
    backup: bool = False,
    backup_target: str | Path | None = None,
) -> list[str]:
    """Export, hash, validate, and promote every requested module.

    A failed module is reported and does not prevent later modules from being
    attempted.  After all modules have been processed, ``PromotionError`` is
    raised when any module failed so the CLI exits nonzero.
    """

    project_root = Path(project_root).expanduser().resolve()
    errors: list[str] = []
    all_promoted: list[str] = []

    if backup:
        if backup_target is None or not str(backup_target).strip():
            raise PromotionError("--backup requires --backup-target")
        try:
            backup_result = backup_sources(
                source_root,
                backup_target,
                dry_run=dry_run,
            )
        except (BackupError, OSError) as exc:
            raise PromotionError(f"source backup failed: {exc}") from exc
        print(
            "STRUCTURAL_BACKUP "
            f"target={getattr(backup_result, 'target', backup_target)} "
            f"would_sync={backup_result.would_sync} "
            f"uploaded={backup_result.uploaded}"
        )

    for module_id in module_ids:
        try:
            _validate_module_id(module_id)
            if dry_run:
                _dry_run_module(project_root, source_root, staging_root, module_id)
                continue
            exported = export_module_to_staging(
                project_root, source_root, staging_root, module_id
            )
            changed: dict[str, Path] = {}
            for variant, staged_path in sorted(
                exported.items(),
                key=lambda item: dict(_VARIANT_SUFFIXES).get(item[0], item[0]),
            ):
                # Hash each staged GLB before making the skip decision.  The
                # helper hashes again to keep its standalone contract simple.
                compute_glb_hash(Path(staged_path))
                runtime_path = _runtime_glb_path(project_root, module_id, variant)
                if should_skip_promotion(staged_path, runtime_path, force=force):
                    continue
                changed[variant] = Path(staged_path)

            if not changed:
                print(f"STRUCTURAL_PROMOTED_SKIP module={module_id} reason=hash_match")
                continue

            if not skip_godot:
                _run_godot_import_smoke(project_root, module_id, changed)
            promoted = promote_module(
                project_root,
                staging_root,
                module_id,
                changed,
                dry_run=dry_run,
            )
            all_promoted.extend(promoted)
            print(f"STRUCTURAL_PROMOTED module={module_id} glbs={len(promoted)}")
        except (OSError, PromotionError, ValueError) as exc:
            message = f"{module_id}: {exc}"
            errors.append(message)
            print(f"ERROR: {message}", file=sys.stderr)

    if errors:
        raise PromotionError("; ".join(errors))
    return all_promoted


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        required=True,
        type=Path,
        help="repository root containing runtime structural assets",
    )
    parser.add_argument(
        "--source-root",
        required=True,
        type=Path,
        help="directory containing recovered module .blend files",
    )
    parser.add_argument(
        "--staging-root",
        required=True,
        type=Path,
        help="directory receiving staged GLB exports",
    )
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument(
        "--module",
        action="append",
        metavar="MODULE_ID",
        help="promote one module; repeat for multiple modules",
    )
    selection.add_argument(
        "--all",
        action="store_true",
        help="promote all allowlisted structural source modules",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="show export plans without invoking Blender or changing files",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="promote even when staged and runtime GLBs have identical hashes",
    )
    parser.add_argument(
        "--skip-godot",
        action="store_true",
        help="skip the temporary Godot import smoke",
    )
    parser.add_argument(
        "--backup",
        action="store_true",
        help="sync source files to the backup target before promotion",
    )
    parser.add_argument(
        "--backup-target",
        help="local path, local:// URL, s3:// URL, or gs:// URL used with --backup",
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
    if args.backup and not args.backup_target:
        parser.error("--backup requires --backup-target")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        promoted = promote_all(
            args.project_root,
            args.source_root,
            args.staging_root,
            _selected_module_ids(args),
            dry_run=args.dry_run,
            force=args.force,
            skip_godot=args.skip_godot,
            backup=args.backup,
            backup_target=args.backup_target,
        )
    except PromotionError:
        return 1
    print(
        f"STRUCTURAL_PROMOTION_SUMMARY modules={len(_selected_module_ids(args))} "
        f"glbs={len(promoted)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
