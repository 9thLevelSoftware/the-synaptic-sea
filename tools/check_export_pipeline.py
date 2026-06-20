#!/usr/bin/env python3
"""Static validation for the Sargasso release export pipeline."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path


REQUIRED_PRESETS = {
    "web": ("Web", "build/exports/web/index.html"),
    "linux": ("Linux", "build/exports/linux/sargasso-of-stars.x86_64"),
    "macos": ("macOS", "build/exports/macos/sargasso-of-stars.zip"),
    "windows": ("Windows Desktop", "build/exports/windows/sargasso-of-stars.exe"),
}


def fail(message: str) -> None:
    raise SystemExit(f"EXPORT PIPELINE CHECK FAIL: {message}")


def parse_presets(text: str) -> dict[str, dict[str, str]]:
    sections = re.split(r"(?m)^\[preset\.(\d+)\]\s*$", text)
    presets: dict[str, dict[str, str]] = {}
    # sections = preamble, index, body, index, body...
    for i in range(1, len(sections), 2):
        body = sections[i + 1]
        values: dict[str, str] = {}
        for key in ("name", "platform", "export_path"):
            match = re.search(rf'(?m)^{re.escape(key)}="([^"]*)"$', body)
            if match:
                values[key] = match.group(1)
        if "name" in values:
            presets[values["name"]] = values
    return presets


def main(argv: list[str]) -> int:
    root = Path(argv[1]).resolve() if len(argv) > 1 else Path.cwd().resolve()
    presets_path = root / "export_presets.cfg"
    if not presets_path.exists():
        fail("missing export_presets.cfg")
    presets = parse_presets(presets_path.read_text(encoding="utf-8"))
    for preset_name, (platform, export_path) in REQUIRED_PRESETS.items():
        preset = presets.get(preset_name)
        if preset is None:
            fail(f"missing preset {preset_name!r}")
        if preset.get("platform") != platform:
            fail(f"preset {preset_name!r} platform is {preset.get('platform')!r}, expected {platform!r}")
        if preset.get("export_path") != export_path:
            fail(f"preset {preset_name!r} export_path is {preset.get('export_path')!r}, expected {export_path!r}")

    build_script = root / "scripts/export/build_release.sh"
    if not build_script.exists():
        fail("missing scripts/export/build_release.sh")
    if not os.access(build_script, os.X_OK):
        fail("scripts/export/build_release.sh is not executable")
    script_text = build_script.read_text(encoding="utf-8")
    if "--export-release" not in script_text:
        fail("build script never calls Godot --export-release")
    for preset_name in REQUIRED_PRESETS:
        if preset_name not in script_text:
            fail(f"build script does not mention preset {preset_name!r}")
    for token in ("SARGASSO_VERSION", "BUILD_STAMP", "godot-4.6.2"):
        if token not in script_text:
            fail(f"build script missing {token}")

    docs_path = root / "docs/game/export_pipeline.md"
    if not docs_path.exists():
        fail("missing docs/game/export_pipeline.md")
    docs = docs_path.read_text(encoding="utf-8")
    for token in ("Godot 4.6.2", "HTML5", "Linux", "macOS", "Windows", "scripts/export/build_release.sh"):
        if token not in docs:
            fail(f"export pipeline docs missing {token!r}")

    print("EXPORT PIPELINE CHECK PASS presets=4 build_script=true docs=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
