from __future__ import annotations

import binascii
import hashlib
import json
import shutil
import struct
import sys
import zlib
from pathlib import Path

import pytest

from tools import meshy_runtime_review as review
from tools.meshy_asset_contract import canonical_json_bytes, load_contract


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_CONTRACT = ROOT / "tests/fixtures/meshy_blender/fixture_contract.json"
FIXTURE_GLB = ROOT / "tests/fixtures/meshy_blender/fixture_triangle.glb"
SEEDS = (42, 777)
LIGHTING = ("normal", "emergency", "dark")


def _task_dir(tmp_path: Path, *, report: object = None, glb: bool = True) -> Path:
    task = tmp_path / "task"
    task.mkdir(parents=True)
    if glb:
        shutil.copy2(FIXTURE_GLB, task / "cleaned.glb")
    if report is not None:
        (task / "blender-validation.json").write_bytes(canonical_json_bytes(report))
    return task


def _png_bytes() -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)

    rows = b"".join(b"\x00" + b"\x00\x00\x00\xff" * review.CAPTURE_SIZE[0] for _ in range(review.CAPTURE_SIZE[1]))
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1600, 900, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def _args(tmp_path: Path, task: Path):
    return review.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--contract",
            str(FIXTURE_CONTRACT),
            "--task-dir",
            str(task),
            "--preview-dir",
            str(tmp_path / "artifacts/validation-previews/meshy/fixture_triangle"),
        ]
    )


def test_review_requires_validated_task_dir(tmp_path: Path) -> None:
    task = _task_dir(tmp_path, report={"status": "FAIL"})

    with pytest.raises(ValueError, match="PASS|validation"):
        review.validate_task_dir(task, load_contract(FIXTURE_CONTRACT))

    missing = _task_dir(tmp_path / "missing", report=None)
    with pytest.raises(ValueError, match="blender-validation.json"):
        review.validate_task_dir(missing, load_contract(FIXTURE_CONTRACT))


def test_review_requires_cleaned_glb(tmp_path: Path) -> None:
    task = _task_dir(tmp_path, report={"status": "PASS"}, glb=False)

    with pytest.raises(ValueError, match="cleaned.glb"):
        review.validate_task_dir(task, load_contract(FIXTURE_CONTRACT))


def test_review_creates_overlay_not_live(tmp_path: Path) -> None:
    task = _task_dir(tmp_path, report={"status": "PASS"})
    contract = load_contract(FIXTURE_CONTRACT)
    inputs = review.validate_task_dir(task, contract)
    overlay_root = tmp_path / "overlay"
    overlay = review.build_review_overlay(tmp_path, inputs, overlay_root)

    assert overlay == overlay_root
    assert review.review_overlay_path(overlay, contract.asset_id) / "cleaned.glb" == inputs.cleaned_glb_overlay
    assert inputs.cleaned_glb_overlay.read_bytes() == (task / "cleaned.glb").read_bytes()
    assert not (tmp_path / "assets/imported/fixture_triangle.glb").exists()
    assert not (tmp_path / "scenes/wrappers/fixture_triangle.tscn").exists()
    assert "assets/_review/meshy/fixture_triangle" in inputs.cleaned_glb_overlay.as_posix()


def test_review_constructs_godot_command(tmp_path: Path) -> None:
    overlay = tmp_path / "overlay"
    output = tmp_path / "capture.png"

    for seed in SEEDS:
        for lighting in LIGHTING:
            assert review.build_godot_command(overlay, seed, lighting, output) == [
                str(review.GODOT),
                "--headless",
                "--path",
                str(overlay),
                "--script",
                "res://scripts/validation/meshy_asset_review_capture.gd",
                "--",
                "--seed",
                str(seed),
                "--lighting",
                lighting,
                "--output",
                str(output),
            ]


def test_review_bounds_godot_runtime() -> None:
    assert review.CAPTURE_TIMEOUT_SECONDS == 120
    assert review.CAPTURE_TIMEOUT_SECONDS > 0


def test_review_rejects_unexpected_diagnostics() -> None:
    marker = "MESHY RUNTIME CAPTURE PASS seed=42 lighting=normal"
    assert review.check_capture_output(marker, "")
    assert not review.check_capture_output(marker + "\nWARNING: injected", "")
    assert not review.check_capture_output(marker, "ERROR: injected")
    assert not review.check_capture_output("", "")


def test_review_publishes_captures_only_after_all_pass(tmp_path: Path) -> None:
    staged = tmp_path / "staged"
    staged.mkdir()
    paths = {}
    for seed in SEEDS:
        for lighting in LIGHTING:
            source = staged / (review.capture_name(seed, lighting))
            source.write_bytes(_png_bytes())
            paths[(seed, lighting)] = source

    output_dir = tmp_path / "published"
    report = {"kind": "meshy_runtime_review", "pass": True}
    incomplete = dict(paths)
    incomplete.pop((777, "dark"))
    with pytest.raises(ValueError, match="six|captures"):
        review.publish_captures(incomplete, output_dir, report)
    assert not output_dir.exists()

    review.publish_captures(paths, output_dir, report)
    assert sorted(path.name for path in output_dir.iterdir()) == sorted(
        [review.capture_name(seed, lighting) for seed in SEEDS for lighting in LIGHTING]
        + ["runtime-review.json"]
    )
    assert json.loads((output_dir / "runtime-review.json").read_text(encoding="utf-8")) == report


def test_review_leaves_live_surfaces_unchanged(tmp_path: Path) -> None:
    (tmp_path / "assets/imported").mkdir(parents=True)
    (tmp_path / "data/combat").mkdir(parents=True)
    (tmp_path / "data/props").mkdir(parents=True)
    (tmp_path / "scenes/wrappers").mkdir(parents=True)
    protected = tmp_path / "assets/imported/live.glb"
    protected.write_bytes(b"live")
    before = review.snapshot_runtime_surfaces(tmp_path)

    task = _task_dir(tmp_path, report={"status": "PASS"})
    inputs = review.validate_task_dir(task, load_contract(FIXTURE_CONTRACT))
    review.build_review_overlay(tmp_path, inputs, review.review_overlay_path(tmp_path, "fixture_triangle"))

    assert review.snapshot_runtime_surfaces(tmp_path) == before
    assert protected.read_bytes() == b"live"


def test_review_report_has_required_fields(tmp_path: Path) -> None:
    report = review.build_runtime_review_report(
        contract_hash="a" * 64,
        cleaned_glb_hash="b" * 64,
        seed=42,
        lighting="dark",
        camera_transform=review.DEFAULT_CAMERA_TRANSFORM,
        output_hash="c" * 64,
        passed=True,
    )

    assert {
        "contract_hash",
        "cleaned_glb_hash",
        "seed",
        "lighting",
        "camera_transform",
        "output_hash",
        "pass",
    } <= set(report)
    assert report["pass"] is True
    assert canonical_json_bytes(report).endswith(b"\n")


def test_cli_requires_all_args(tmp_path: Path) -> None:
    with pytest.raises(SystemExit):
        review.build_parser().parse_args([])
    with pytest.raises(SystemExit):
        review.parse_args(["--project-root", str(tmp_path)])
