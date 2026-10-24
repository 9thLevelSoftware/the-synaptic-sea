#!/usr/bin/env python3
"""Host launcher for the procedural character kit (ADR-0070).

Runs the Blender build headless, validates the exported GLB against the kit
spec, and optionally renders the review previews. Blender is resolved from
``--blender``, ``$BLENDER``, or ``blender`` on PATH (the docs' macOS
``/opt/homebrew/bin/blender`` and the Windows console build both work when
passed explicitly).

    PYTHONPATH=. python3 tools/character_kit/build_kit.py --project-root . [--previews] [--blender <exe>]

Exit code 0 only when the build ran and the validator printed its PASS marker.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.character_kit import character_kit_spec as spec
from tools.character_kit import validate_character_glb


def resolve_blender(explicit: str | None) -> str | None:
    for candidate in (explicit, os.environ.get("BLENDER"), shutil.which("blender")):
        if candidate and Path(candidate).exists():
            return candidate
    return None


def run_blender(blender: str, script: Path, project_root: Path, extra: list[str]) -> int:
    command = [
        blender,
        "--background",
        "--factory-startup",
        "--python",
        str(script),
        "--",
        "--project-root",
        str(project_root),
        *extra,
    ]
    print("+", " ".join(command), flush=True)
    return subprocess.call(command, cwd=str(project_root))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--blender", default=None)
    parser.add_argument("--out", default=None, help="override runtime output dir (default spec RUNTIME_ROOT)")
    parser.add_argument("--previews", action="store_true", help="also render review previews with Cycles")
    parser.add_argument("--preview-dir", default=None)
    parser.add_argument("--samples", type=int, default=24)
    parser.add_argument("--skip-tools", action="store_true")
    parser.add_argument("--blend", default=None, help="save an editable .blend master beside the build (outside the repo)")
    args = parser.parse_args(argv)

    project_root = Path(args.project_root).resolve()
    blender = resolve_blender(args.blender)
    if blender is None:
        print("CHARACTER KIT BUILD FAIL reason=blender_not_found (pass --blender or set $BLENDER)")
        return 2

    tools_dir = project_root / "tools" / "character_kit"
    out_dir = Path(args.out) if args.out else spec.RUNTIME_ROOT
    extra = ["--out", str(out_dir)]
    if args.skip_tools:
        extra.append("--skip-tools")
    if args.blend:
        extra += ["--blend", args.blend]
    code = run_blender(blender, tools_dir / "build_survivor_kit.py", project_root, extra)
    if code != 0:
        print(f"CHARACTER KIT BUILD FAIL reason=blender_exit_{code}")
        return 1

    glb = (project_root / out_dir / spec.GLB_LEAF) if not Path(out_dir).is_absolute() else Path(out_dir) / spec.GLB_LEAF
    manifest = glb.with_name(spec.MANIFEST_LEAF)
    code = validate_character_glb.main([
        "--glb", str(glb), "--manifest", str(manifest),
        "--report", str(glb.with_suffix(".validation.json")),
        "--project-root", str(project_root),
    ])
    if code != 0:
        return 1

    if args.previews:
        preview_dir = args.preview_dir or str(spec.PREVIEW_ROOT)
        code = run_blender(
            blender,
            tools_dir / "render_character_previews.py",
            project_root,
            ["--glb", str(glb), "--out", preview_dir, "--samples", str(args.samples)],
        )
        if code != 0:
            print(f"CHARACTER KIT PREVIEW FAIL reason=blender_exit_{code}")
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
