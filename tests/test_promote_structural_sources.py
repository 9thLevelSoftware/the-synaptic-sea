from __future__ import annotations

from pathlib import Path

from tools.promote_structural_sources import (
    should_skip_promotion,
)


def test_identical_hash_skips_promotion(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    runtime = tmp_path / "runtime.glb"
    staged.write_bytes(b"same GLB bytes")
    runtime.write_bytes(b"same GLB bytes")

    assert should_skip_promotion(staged, runtime, force=False) is True


def test_different_hash_does_not_skip(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    runtime = tmp_path / "runtime.glb"
    staged.write_bytes(b"new GLB bytes")
    runtime.write_bytes(b"old GLB bytes")

    assert should_skip_promotion(staged, runtime, force=False) is False


def test_force_overrides_hash_skip(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    runtime = tmp_path / "runtime.glb"
    staged.write_bytes(b"same GLB bytes")
    runtime.write_bytes(b"same GLB bytes")

    assert should_skip_promotion(staged, runtime, force=True) is False


def test_missing_runtime_does_not_skip(tmp_path: Path) -> None:
    staged = tmp_path / "staged.glb"
    runtime = tmp_path / "runtime.glb"
    staged.write_bytes(b"staged GLB bytes")

    assert should_skip_promotion(staged, runtime, force=False) is False
