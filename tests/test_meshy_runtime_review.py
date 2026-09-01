from __future__ import annotations

import binascii
import hashlib
import json
import shutil
import struct
import sys
import zlib
from pathlib import Path
from types import SimpleNamespace

import pytest

from tools import meshy_runtime_review as review
from tools import meshy_blender_validate as validate_module
from tools.meshy_asset_contract import canonical_json_bytes, load_contract
from tools.meshy_blender_validate import validate_cleaned_glb


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
        if report == {"status": "PASS"} and glb:
            contract = load_contract(FIXTURE_CONTRACT)
            canonical_report = validate_cleaned_glb(task / "cleaned.glb", contract, task_id=task.name)
            canonical_report["blender_reimport_passed"] = True
            report = canonical_report
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
                *review._godot_render_args(),
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
    marker = (
        "MESHY RUNTIME CAPTURE PASS seed=42 lighting=normal "
        "camera_position=12.5,8.25,-4.0 camera_target=1.0,2.0,3.0 "
        "camera_size=7.5 staged_visibility=pass staged_opaque_pixels=100 "
        "staged_luma_range=1.0 output=/private/tmp/capture.png"
    )
    assert review.check_capture_output(marker, "", 42, "normal")
    assert not review.check_capture_output(marker + "\nWARNING: injected", "", 42, "normal")
    assert not review.check_capture_output(marker, "ERROR: injected", 42, "normal")
    assert not review.check_capture_output("", "", 42, "normal")


def test_review_does_not_expose_arbitrary_capture_publisher() -> None:
    assert not hasattr(review, "publish_captures")


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


def test_runtime_command_binds_asset_and_category_as_user_args(tmp_path: Path) -> None:
    command = review.build_godot_command(
        tmp_path / "overlay",
        42,
        "normal",
        tmp_path / "capture.png",
        asset_id="fixture_triangle",
        category="gameplay_prop",
    )

    assert command[command.index("--asset-id") + 1] == "fixture_triangle"
    assert command[command.index("--category") + 1] == "gameplay_prop"
    assert "shell=True" not in command


def test_camera_marker_is_parsed_as_actual_finite_transform() -> None:
    marker = (
        "MESHY RUNTIME CAPTURE PASS seed=42 lighting=normal "
        "camera_position=12.5,8.25,-4.0 camera_target=1.0,2.0,3.0 "
        "camera_size=7.5 staged_visibility=pass staged_opaque_pixels=100 "
        "staged_luma_range=1.0 output=/private/tmp/capture.png"
    )

    parsed = review.parse_capture_marker(marker, 42, "normal")

    assert parsed == {
        "projection": "orthogonal",
        "position": [12.5, 8.25, -4.0],
        "target": [1.0, 2.0, 3.0],
        "size": 7.5,
        "staged_visibility": {"pass": True, "opaque_pixels": 100, "luma_range": 1.0},
    }


@pytest.mark.parametrize(
    "evidence",
    [
        "",
        "staged_visibility=fail staged_opaque_pixels=0 staged_luma_range=0.0",
        "staged_visibility=pass staged_opaque_pixels=1 staged_luma_range=1.0",
        "staged_visibility=pass staged_opaque_pixels=100 staged_luma_range=0.0",
    ],
)
def test_capture_rejects_missing_or_false_staged_visibility_evidence(evidence: str) -> None:
    marker = (
        "MESHY RUNTIME CAPTURE PASS seed=42 lighting=normal "
        "camera_position=12.5,8.25,-4.0 camera_target=1.0,2.0,3.0 "
        "camera_size=7.5 " + evidence
    ).rstrip()
    with pytest.raises(review.ReviewError, match="staged|visibility|canonical"):
        review.parse_capture_marker(marker, 42, "normal")


def _bound_runtime_fixture(tmp_path: Path):
    from tests.test_meshy_blender_tools import _bound_fixture_task

    project_root, task_dir, contract = _bound_fixture_task(tmp_path)
    report = validate_cleaned_glb(task_dir / "cleaned.glb", contract, task_id=task_dir.name)
    report["blender_reimport_passed"] = True
    (task_dir / "blender-validation.json").write_bytes(canonical_json_bytes(report))
    return project_root, task_dir, contract


def test_reverification_without_caller_contract_rejects_forged_generation_hash(
    tmp_path: Path,
) -> None:
    project_root, task_dir, contract = _bound_runtime_fixture(tmp_path)
    forged_hash = "f" * 64
    generation_path = task_dir / "generation.json"
    generation = json.loads(generation_path.read_text(encoding="utf-8"))
    generation["contract_sha256"] = forged_hash
    generation_path.write_bytes(canonical_json_bytes(generation))
    journal_path = task_dir.parent / "_batches" / (generation["batch_id"] + ".json")
    journal = json.loads(journal_path.read_text(encoding="utf-8"))
    journal["approval"]["contract_sha256"] = forged_hash
    journal_path.write_bytes(canonical_json_bytes(journal))
    r4_path = task_dir / "blender-validation.json"
    r4 = json.loads(r4_path.read_text(encoding="utf-8"))
    r4["contract_sha256"] = forged_hash
    r4_path.write_bytes(canonical_json_bytes(r4))

    with pytest.raises(review.ReviewError, match="contract"):
        review._load_runtime_inputs(project_root, None, task_dir)

    assert json.loads((task_dir / "contract.json").read_text(encoding="utf-8")) == contract.document


def test_reverification_recomputes_forged_r4_semantics_from_cleaned_glb(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir, contract = _bound_runtime_fixture(tmp_path)
    r4_path = task_dir / "blender-validation.json"
    forged = json.loads(r4_path.read_text(encoding="utf-8"))
    forged["triangle_count"] = 999
    r4_path.write_bytes(canonical_json_bytes(forged))
    cleaned_before = (task_dir / "cleaned.glb").read_bytes()

    def fake_reimport(glb_path: Path, expected_triangles: int) -> SimpleNamespace:
        return SimpleNamespace(
            sha256=review.governance.file_sha256(glb_path),
            byte_size=glb_path.stat().st_size,
            triangle_count=expected_triangles,
        )

    monkeypatch.setattr(
        validate_module, "_reimport_with_blender_process", fake_reimport, raising=False
    )
    with pytest.raises(review.ReviewError, match="semantic|match|triangle|re-import"):
        review._load_runtime_inputs(project_root, None, task_dir)
    assert (task_dir / "cleaned.glb").read_bytes() == cleaned_before


def test_preview_directory_must_be_fixed_to_asset_leaf(tmp_path: Path) -> None:
    task = _task_dir(tmp_path, report={"status": "PASS"})
    with pytest.raises(SystemExit):
        review.parse_args(
            [
                "--project-root",
                str(tmp_path),
                "--contract",
                str(FIXTURE_CONTRACT),
                "--task-dir",
                str(task),
                "--preview-dir",
                str(tmp_path / "artifacts/validation-previews/meshy/other"),
            ]
        )
