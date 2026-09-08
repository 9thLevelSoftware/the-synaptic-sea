#!/usr/bin/env python3
"""Run one room-kit diagnostic command with fail-closed log checks."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
from typing import Sequence


_BAD_DIAGNOSTICS = re.compile(r"(?im)^\s*(?:SCRIPT ERROR:|ERROR:|WARNING:)|GATE_TIMEOUT")


def _terminate_process_group(process: subprocess.Popen[str]) -> None:
    """Stop the child and any descendants without masking its primary status."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except (ProcessLookupError, PermissionError):
        pass
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        process.wait()


def _as_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode(errors="replace")
    return value


def _run(command: Sequence[str], timeout: int) -> tuple[str, int]:
    try:
        process = subprocess.Popen(
            list(command),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            start_new_session=True,
        )
    except OSError as exc:
        return f"GATE_EXEC_ERROR: {exc}\n", 127

    try:
        output, _ = process.communicate(timeout=timeout)
        return _as_text(output), process.returncode
    except subprocess.TimeoutExpired as exc:
        _terminate_process_group(process)
        output, _ = process.communicate()
        if not output:
            output = exc.stdout
        return _as_text(output) + "\nGATE_TIMEOUT\n", 124


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--marker", default="")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)

    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("command required")
    if args.log.exists() and args.log.is_symlink():
        parser.error("log path must not be a symlink")

    text, code = _run(command, args.timeout)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.log.write_text(text, encoding="utf-8")

    diagnostic = _BAD_DIAGNOSTICS.search(text)
    marker_ok = bool(args.marker) and args.marker in text
    good = code == 0 and diagnostic is None and marker_ok
    print(("GATE_PASS " if good else "GATE_FAIL ") + str(args.log))
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
