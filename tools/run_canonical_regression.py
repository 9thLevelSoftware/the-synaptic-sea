#!/usr/bin/env python3
"""Run the sole regression bundle owned by docs/game/06_validation_plan.md."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess


_MARKER_TEXT_RE = re.compile(
    r"SYNAPTIC_SEA REGRESSION PASS commands=(?P<count>\d+) clean_output=true"
)
_CANONICAL_MARKER_LINE_RE = re.compile(
    r"^[ \t]*echo 'SYNAPTIC_SEA REGRESSION PASS commands=(?P<count>\d+) clean_output=true'$"
)


def extract_bundle(document: str) -> str:
    sections = re.findall(
        r"^## Regression bundle\s*\n(.*?)(?=^## |\Z)",
        document,
        flags=re.MULTILINE | re.DOTALL,
    )
    if len(sections) != 1:
        raise ValueError("expected exactly one Regression bundle section")
    blocks = re.findall(r"^```bash\n(.*?)^```\s*$", sections[0], re.MULTILINE | re.DOTALL)
    if len(blocks) != 1:
        raise ValueError("expected exactly one bash regression block")
    script = blocks[0]

    marker_texts = list(_MARKER_TEXT_RE.finditer(script))
    if len(marker_texts) != 1:
        raise ValueError("expected exactly one canonical regression marker")

    marker_line_index = -1
    marker_line_match = None
    for index, raw_line in enumerate(script.splitlines()):
        match = _CANONICAL_MARKER_LINE_RE.fullmatch(raw_line)
        if match is not None:
            if marker_line_index != -1:
                raise ValueError("expected exactly one canonical regression marker line")
            marker_line_index = index
            marker_line_match = match
    if marker_line_match is None:
        raise ValueError("expected exactly one canonical executable echo marker")
    if marker_line_match.group("count") != marker_texts[0].group("count"):
        raise ValueError("canonical regression marker text mismatch")

    for raw_line in script.splitlines()[marker_line_index + 1 :]:
        code = raw_line.strip()
        if code and not code.startswith("#"):
            raise ValueError("canonical regression marker must be the last executable line")

    actual = sum(line.lstrip().startswith("run_clean ") for line in script.splitlines())
    if actual < 1 or actual != int(marker_texts[0].group("count")):
        raise ValueError(
            f"regression count mismatch: registered={actual}, claimed={marker_texts[0].group('count')}"
        )
    return script if script.endswith("\n") else script + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    root = args.project_root.resolve(strict=True)
    try:
        script = extract_bundle((root / "docs/game/06_validation_plan.md").read_text())
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    if args.check:
        print("CANONICAL REGRESSION MANIFEST PASS")
        return 0
    env = dict(os.environ)
    env["ROOT"] = str(root)
    if not env.get("GODOT"):
        parser.error("GODOT must name the verified Godot 4.7.1 executable")
    return subprocess.run(["/bin/bash", "-s"], input=script, text=True, cwd=root, env=env).returncode


if __name__ == "__main__":
    raise SystemExit(main())
