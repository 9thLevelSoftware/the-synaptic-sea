#!/usr/bin/env python3
"""Batch-render all structural kit modules with Blender."""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Sequence


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BLENDER_BINARY = Path("/opt/homebrew/bin/blender")
OUTPUT_DIR = Path("/tmp/tile_renders")
TIMEOUT_SECONDS = 60
RENDER_PASSES = ("beauty", "depth", "normal")
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


def expected_output_paths(module_id: str) -> tuple[Path, ...]:
    """Return the three files expected from one module render."""

    return tuple(OUTPUT_DIR / f"{module_id}_{render_pass}.png" for render_pass in RENDER_PASSES)


def blender_command(module_id: str) -> list[str]:
    """Build the exact headless Blender command for one module."""

    return [
        str(BLENDER_BINARY),
        "--background",
        "--python",
        "tools/render_module_passes.py",
        "--",
        "--module",
        module_id,
    ]


def render_module(module_id: str, index: int, total: int, dry_run: bool = False) -> bool:
    """Render one module and verify that all expected pass files exist."""

    command = blender_command(module_id)
    outputs = expected_output_paths(module_id)
    print(f"[{index}/{total}] {module_id}")
    print(f"  command: {shlex.join(command)}")
    print("  expected:")
    for output_path in outputs:
        print(f"    {output_path}")

    if dry_run:
        return True

    try:
        result = subprocess.run(command, cwd=PROJECT_ROOT, timeout=TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        print(f"  FAIL: Blender timed out after {TIMEOUT_SECONDS}s", file=sys.stderr)
        return False
    except OSError as exc:
        print(f"  FAIL: could not start Blender: {exc}", file=sys.stderr)
        return False

    if result.returncode != 0:
        print(f"  FAIL: Blender exited with status {result.returncode}", file=sys.stderr)
        return False

    missing = [path for path in outputs if not path.is_file()]
    if missing:
        print("  FAIL: missing expected output files:", file=sys.stderr)
        for path in missing:
            print(f"    {path}", file=sys.stderr)
        return False

    print("  OK: all expected output files exist")
    return True


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print each Blender command and expected output without running Blender",
    )
    args = parser.parse_args(argv)

    successes = 0
    failures = 0
    total = len(MODULE_IDS)
    for index, module_id in enumerate(MODULE_IDS, start=1):
        if render_module(module_id, index, total, dry_run=args.dry_run):
            successes += 1
        else:
            failures += 1

    label = "DRY-RUN " if args.dry_run else ""
    print(f"\n{label}Summary: {successes} successes, {failures} failures")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
