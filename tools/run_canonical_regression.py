#!/usr/bin/env python3
"""Run the sole regression bundle owned by docs/game/06_validation_plan.md."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import subprocess


_COUNT_MARKER_RE = re.compile(
    r"SYNAPTIC_SEA REGRESSION PASS commands=(?P<count>\d+) clean_output=true\b"
)
_EXECUTABLE_COUNT_MARKER_RE = re.compile(
    r"""^echo\s+(?P<quote>['"])(?P<marker>SYNAPTIC_SEA REGRESSION PASS commands=\d+ clean_output=true)(?P=quote)$"""
)
_SHELL_FUNCTION_START_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\s*\(\)\s*\{\s*$")


def _strip_shell_comment(line: str) -> str:
    """Strip an unquoted shell comment without interpreting shell syntax."""
    quote = None
    escaped = False
    for index, character in enumerate(line):
        if escaped:
            escaped = False
            continue
        if quote == "'":
            if character == "'":
                quote = None
            continue
        if character == "\\":
            escaped = True
            continue
        if quote:
            if character == quote:
                quote = None
            continue
        if character in "'\"":
            quote = character
        elif character == "#" and (index == 0 or line[index - 1].isspace()):
            return line[:index].rstrip()
    return line.rstrip()


def _shell_control_depth(code: str, depth: int) -> int:
    """Track only obvious shell control blocks; this is not a shell parser."""
    if re.match(r"^(?:if|for|while|until|case|select)\b", code):
        if re.search(r"\b(?:then|do|in)\b", code):
            depth += 1
    if re.search(r"(?:^|[;\s])(?:fi|done|esac)(?:\s*;)?$", code):
        depth -= 1
    return max(depth, 0)


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
    claimed = list(_COUNT_MARKER_RE.finditer(script))
    if len(claimed) != 1:
        raise ValueError("expected exactly one regression count marker")

    executable_markers = 0
    control_depth = 0
    function_depth = 0
    for raw_line in script.splitlines():
        code = _strip_shell_comment(raw_line).strip()
        if function_depth:
            if code in ("}", "};"):
                function_depth -= 1
            continue
        if _SHELL_FUNCTION_START_RE.fullmatch(code):
            function_depth = 1
            continue
        if code and _EXECUTABLE_COUNT_MARKER_RE.fullmatch(code) and control_depth == 0:
            executable_markers += 1
        control_depth = _shell_control_depth(code, control_depth)
    if executable_markers != 1:
        raise ValueError("expected exactly one executable top-level echo count marker")

    actual = sum(line.lstrip().startswith("run_clean ") for line in script.splitlines())
    if actual < 1 or actual != int(claimed[0].group("count")):
        raise ValueError(f"regression count mismatch: registered={actual}, claimed={claimed[0].group('count')}")
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
