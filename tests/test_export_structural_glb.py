from __future__ import annotations

from pathlib import Path
import subprocess
import sys


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT_ROOT / "tools" / "export_structural_glb.py"


def _run_export_cli(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--", *args],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


def test_export_cli_requires_blend_path_and_staging_dir() -> None:
    result = _run_export_cli()

    assert result.returncode != 0
    assert "--blend-path" in result.stderr
    assert "--staging-dir" in result.stderr


def test_export_cli_rejects_nonexistent_blend_file(tmp_path: Path) -> None:
    result = _run_export_cli(
        "--blend-path",
        str(tmp_path / "missing.blend"),
        "--staging-dir",
        str(tmp_path / "staging"),
    )

    assert result.returncode != 0
    assert "blend" in result.stderr.lower()
    assert "exist" in result.stderr.lower()
