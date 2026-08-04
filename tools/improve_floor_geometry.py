#!/usr/bin/env python3
"""Compatibility entrypoint for the focused-nine floor recipe.

Older automation passed ``--source-root`` and ``--module`` to this file.  Keep
that command shape, but delegate all Blender work to the safe generated-only
focused-nine driver.  The compatibility layer has no scene mutation logic.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Sequence

try:
    from tools.focused_nine_blender_recipes import main as focused_nine_main
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools.focused_nine_blender_recipes import main as focused_nine_main


def _argv_from_blender(
    argv: Sequence[str] | None, parser: argparse.ArgumentParser
) -> list[str]:
    if argv is not None:
        return list(argv)
    raw = list(sys.argv[1:])
    if "--" not in raw:
        parser.error("Blender invocation requires '--' before compatibility arguments")
    return raw[raw.index("--") + 1 :]


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--module", default="floor_1x1")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args(_argv_from_blender(argv, parser))
    if args.module != "floor_1x1":
        parser.error("compatibility driver only delegates floor_1x1")
    if not args.overwrite:
        parser.error("--overwrite is required by the compatibility driver")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    delegated = [
        "--project-root",
        str(args.project_root),
        "--structural-source-root",
        str(args.source_root),
        "--props-source-root",
        str(args.source_root.parent / "props"),
        "--asset-id",
        "floor_1x1",
        "--overwrite-generated-only",
    ]
    return focused_nine_main(delegated)


if __name__ == "__main__":
    raise SystemExit(main())
