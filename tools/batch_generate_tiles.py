#!/usr/bin/env python3
"""Batch-generate textured tiles for all structural kit modules."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT_DIR = Path("assets/tiles/synaptic_sea")
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
DEFAULT_SEED = 42

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

try:
    from tools.comfyui_tile_workflow import generate_tile
except ModuleNotFoundError as exc:
    if exc.name == "tools.comfyui_tile_workflow":
        generate_tile = None
        WORKFLOW_IMPORT_ERROR = exc
    else:
        raise


def resolve_output_dir(output: str) -> Path:
    """Resolve relative output paths from the project root."""

    output_dir = Path(output)
    return output_dir if output_dir.is_absolute() else PROJECT_ROOT / output_dir


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default=str(DEFAULT_OUTPUT_DIR),
        help=f"directory for generated tiles (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=DEFAULT_SEED,
        help=f"seed for the first module; each subsequent module increments it (default: {DEFAULT_SEED})",
    )
    args = parser.parse_args(argv)

    if generate_tile is None:
        print(
            "ERROR: tools.comfyui_tile_workflow.generate_tile is unavailable. "
            "Create tools/comfyui_tile_workflow.py before running the batch generator.",
            file=sys.stderr,
        )
        return 1

    output_dir = resolve_output_dir(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    successes = 0
    failures = 0
    total = len(MODULE_IDS)
    for index, module_id in enumerate(MODULE_IDS, start=1):
        seed = args.seed + index - 1
        print(f"[{index}/{total}] {module_id} (seed={seed})")
        try:
            result = generate_tile(module_id, output_dir, seed)
        except Exception as exc:
            failures += 1
            print(f"  FAIL: {exc}", file=sys.stderr)
        else:
            successes += 1
            if result is not None:
                print(f"  OK: {result}")
            else:
                print("  OK")

    print(f"\nSummary: {successes} successes, {failures} failures")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
