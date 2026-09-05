#!/usr/bin/env python3
"""Run the sole regression bundle owned by docs/game/06_validation_plan.md."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess


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
    claimed = re.findall(r"SYNAPTIC_SEA REGRESSION PASS commands=(\d+) clean_output=true", script)
    if len(claimed) != 1:
        raise ValueError("expected exactly one regression count marker")
    actual = sum(line.lstrip().startswith("run_clean ") for line in script.splitlines())
    if actual < 1 or actual != int(claimed[0]):
        raise ValueError(f"regression count mismatch: registered={actual}, claimed={claimed[0]}")
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
