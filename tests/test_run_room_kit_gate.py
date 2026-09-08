from __future__ import annotations

from pathlib import Path
import subprocess
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "tools/run_room_kit_gate.py"


@pytest.mark.parametrize(
    "program,marker,timeout,expected",
    [
        ('print("REAL")', "REAL", 10, 0),
        ('print("unrelated REAL text")', "REAL", 10, 1),
        ('print("REAL_IMPOSTOR")', "REAL", 10, 1),
        ('print("REALISTIC")', "REAL", 10, 1),
        ('print("xREAL")', "REAL", 10, 1),
        ('print("REAL rows=16")', "REAL", 10, 0),
        ('print("REAL[42]")', "REAL[42]", 10, 0),
        ('print("REAL4")', "REAL[42]", 10, 1),
        ('print("REAL")', "", 10, 1),
        ('print("SCRIPT ERROR: deliberate runner test"); print("REAL")', "REAL", 10, 1),
        ('print("ERROR: deliberate runner test"); print("REAL")', "REAL", 10, 1),
        ('print("WARNING: deliberate runner test"); print("REAL")', "REAL", 10, 1),
        ('print("wrong marker")', "REAL", 10, 1),
        ('raise SystemExit(5)', "REAL", 10, 1),
        ('import time; time.sleep(10)', "", 1, 1),
    ],
)
def test_runner(tmp_path, program, marker, timeout, expected) -> None:
    log = tmp_path / "output.txt"
    result = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--log",
            str(log),
            "--marker",
            marker,
            "--timeout",
            str(timeout),
            "--",
            sys.executable,
            "-c",
            program,
        ],
        text=True,
        capture_output=True,
        timeout=15,
        cwd=ROOT,
    )

    assert result.returncode == expected, result.stdout + result.stderr
    assert log.is_file()
    assert ("GATE_PASS" if expected == 0 else "GATE_FAIL") in result.stdout
    if program.startswith('print(') and expected:
        assert log.read_text(encoding="utf-8")



def test_runner_preserves_raw_output_on_nonzero_child(tmp_path) -> None:
    log = tmp_path / "raw.txt"
    result = subprocess.run(
        [
            sys.executable,
            str(RUNNER),
            "--log",
            str(log),
            "--marker",
            "REAL",
            "--",
            sys.executable,
            "-c",
            'import sys; print("raw diagnostic"); sys.exit(7)',
        ],
        text=True,
        capture_output=True,
        timeout=15,
        cwd=ROOT,
    )

    assert result.returncode == 1
    assert "raw diagnostic" in log.read_text(encoding="utf-8")
