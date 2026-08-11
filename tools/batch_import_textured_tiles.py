#!/usr/bin/env python3
"""Batch-import generated tile textures onto structural module GLBs.

A seamless tile is preferred when both variants exist.  Otherwise the first
regular PNG whose filename contains the module ID is used.  Modules without a
matching texture are reported as skipped rather than treated as failures; this
lets the wrapper run while tile generation is still incomplete.

Usage::

    python3 tools/batch_import_textured_tiles.py --dry-run
    python3 tools/batch_import_textured_tiles.py \
        --tile-dir assets/tiles/synaptic_sea \
        --module-dir assets/imported/structural/ship_structural_v0

By default exports are written beside each source module as
``{module}_textured.glb``.  ``--output-dir`` changes this to
``{output-dir}/{module}/{module}_textured.glb``.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
from typing import Sequence


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TILE_DIR = Path("assets/tiles/synaptic_sea")
DEFAULT_MODULE_DIR = Path("assets/imported/structural/ship_structural_v0")
DEFAULT_APPLY_SCRIPT = Path("tools/apply_tile_texture.py")
DEFAULT_BLENDER = os.environ.get("BLENDER") or shutil.which("blender") or "/opt/homebrew/bin/blender"
MODULE_IDS = (
    "floor_1x1",
    "floor_2x1",
    "corridor_floor_1x1",
    "corridor_floor_1x2",
    "wall_straight_1x1",
    "wall_end_cap",
    "wall_inner_corner",
    "wall_outer_corner",
    "wall_t_junction",
    "doorway_frame_open_1x1",
    "doorway_frame_blocked_1x1",
    "bulkhead_portal_2x1",
    "ceiling_cap_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
)


def resolve_project_path(value: str | Path) -> Path:
    """Resolve project-relative paths while preserving absolute paths."""

    path = Path(value).expanduser()
    return path if path.is_absolute() else PROJECT_ROOT / path


def source_glb(module_dir: Path, module_id: str) -> Path:
    """Return the canonical source GLB for a module ID."""

    return module_dir / module_id / f"{module_id}.glb"


def find_texture(tile_dir: Path, module_id: str) -> Path | None:
    """Find the best available seamless or regular PNG for one module."""

    module_token = module_id.lower()

    def belongs_to_module(path: Path) -> bool:
        """Match the module token without confusing floor/corridor variants."""

        stem = path.stem.lower()
        accepted_prefixes = (f"{module_token}_", f"synaptic_tile_{module_token}_")
        return stem == module_token or stem.startswith(accepted_prefixes)

    candidates = [
        path
        for path in tile_dir.iterdir()
        if path.is_file()
        and path.suffix.lower() == ".png"
        and belongs_to_module(path)
        and not path.stem.lower().endswith(("_edge_mask", "_test_grid"))
    ]
    if not candidates:
        return None

    def sort_key(path: Path) -> tuple[int, str]:
        stem = path.stem.lower()
        if stem.endswith("_seamless"):
            return (0, path.name.lower())
        if stem == module_token:
            return (1, path.name.lower())
        return (2, path.name.lower())

    return sorted(candidates, key=sort_key)[0]


def output_glb(module_dir: Path, output_dir: Path | None, module_id: str) -> Path:
    """Return the destination path for one textured module."""

    if output_dir is None:
        return module_dir / module_id / f"{module_id}_textured.glb"
    return output_dir / module_id / f"{module_id}_textured.glb"


def blender_command(
    blender: str,
    apply_script: Path,
    module_path: Path,
    texture_path: Path,
    output_path: Path,
) -> list[str]:
    """Build the headless Blender command for one texture import."""

    return [
        blender,
        "--background",
        "--python",
        str(apply_script),
        "--",
        "--module",
        str(module_path),
        "--texture",
        str(texture_path),
        "--output",
        str(output_path),
    ]


def run_module(
    *,
    index: int,
    total: int,
    module_id: str,
    tile_dir: Path,
    module_dir: Path,
    output_dir: Path | None,
    blender: str,
    apply_script: Path,
    timeout: int,
    dry_run: bool,
) -> str:
    """Run or preview one module and return processed/skipped/failed."""

    texture_path = find_texture(tile_dir, module_id)
    if texture_path is None:
        print(f"[{index}/{total}] {module_id}: SKIP (no tile PNG)")
        return "skipped"

    module_path = source_glb(module_dir, module_id)
    if not module_path.is_file():
        print(f"[{index}/{total}] {module_id}: FAIL (missing {module_path})", file=sys.stderr)
        return "failed"

    output_path = output_glb(module_dir, output_dir, module_id)
    command = blender_command(blender, apply_script, module_path, texture_path, output_path)
    print(f"[{index}/{total}] {module_id}")
    print(f"  texture: {texture_path}")
    print(f"  command: {shlex.join(command)}")

    if dry_run:
        print(f"  output:  {output_path}")
        return "processed"

    output_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(command, cwd=PROJECT_ROOT, timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"  FAIL: Blender timed out after {timeout}s", file=sys.stderr)
        return "failed"
    except OSError as exc:
        print(f"  FAIL: could not start Blender: {exc}", file=sys.stderr)
        return "failed"

    if result.returncode != 0:
        print(f"  FAIL: Blender exited with status {result.returncode}", file=sys.stderr)
        return "failed"
    if not output_path.is_file() or output_path.stat().st_size <= 0:
        print(f"  FAIL: expected output is missing or empty: {output_path}", file=sys.stderr)
        return "failed"

    print(f"  OK: {output_path} ({output_path.stat().st_size:,} bytes)")
    return "processed"


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--module",
        dest="modules",
        action="append",
        help="process only this module ID; repeat for multiple modules (default: all)",
    )
    parser.add_argument("--tile-dir", default=str(DEFAULT_TILE_DIR), help="directory containing tile PNGs")
    parser.add_argument(
        "--module-dir",
        default=str(DEFAULT_MODULE_DIR),
        help="directory containing module-ID subdirectories",
    )
    parser.add_argument(
        "--output-dir",
        help="optional root for outputs; defaults to each source module directory",
    )
    parser.add_argument(
        "--blender",
        default=DEFAULT_BLENDER,
        help=f"Blender executable (default: {DEFAULT_BLENDER})",
    )
    parser.add_argument(
        "--apply-script",
        default=str(DEFAULT_APPLY_SCRIPT),
        help=f"texture application script (default: {DEFAULT_APPLY_SCRIPT})",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=300,
        help="per-module Blender timeout in seconds (default: 300)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print matching textures and Blender commands without running Blender",
    )
    args = parser.parse_args(argv)

    if args.timeout <= 0:
        parser.error("--timeout must be greater than zero")

    tile_dir = resolve_project_path(args.tile_dir)
    module_dir = resolve_project_path(args.module_dir)
    output_dir = resolve_project_path(args.output_dir) if args.output_dir else None
    apply_script = resolve_project_path(args.apply_script)
    modules = args.modules or list(MODULE_IDS)

    if not tile_dir.is_dir():
        print(f"ERROR: tile directory does not exist: {tile_dir}", file=sys.stderr)
        return 2
    if not apply_script.is_file():
        print(f"ERROR: apply script does not exist: {apply_script}", file=sys.stderr)
        return 2
    if not module_dir.is_dir():
        print(f"ERROR: module directory does not exist: {module_dir}", file=sys.stderr)
        return 2

    counts = {"processed": 0, "skipped": 0, "failed": 0}
    total = len(modules)
    for index, module_id in enumerate(modules, start=1):
        status = run_module(
            index=index,
            total=total,
            module_id=module_id,
            tile_dir=tile_dir,
            module_dir=module_dir,
            output_dir=output_dir,
            blender=args.blender,
            apply_script=apply_script,
            timeout=args.timeout,
            dry_run=args.dry_run,
        )
        counts[status] += 1

    label = "DRY-RUN " if args.dry_run else ""
    print(
        f"\n{label}Summary: {counts['processed']} processed, "
        f"{counts['skipped']} skipped, {counts['failed']} failures"
    )
    return 0 if counts["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
