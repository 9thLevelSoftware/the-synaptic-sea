from __future__ import annotations

import binascii
import hashlib
import inspect
import json
import math
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
    marker = _locked_real_marker()
    assert review.check_capture_output(marker, "", 42, "normal")
    assert not review.check_capture_output(marker + "\nWARNING: injected", "", 42, "normal")
    assert not review.check_capture_output(marker, "ERROR: injected", 42, "normal")
    assert not review.check_capture_output("", "", 42, "normal")


def test_review_does_not_expose_arbitrary_capture_publisher() -> None:
    assert not hasattr(review, "publish_captures")
    assert not hasattr(review, "_publish_fixed_captures")
    assert not any("publish" in name.lower() for name, value in inspect.getmembers(review, callable))


def _canonical_contextual_visibility(
    *,
    passed: bool = True,
    reference_pixels: int = 100,
    changed_pixels: int = 50,
    max_delta: float = 0.25,
) -> dict:
    return {
        "pass": passed,
        "reference_pixels": reference_pixels,
        "changed_pixels": changed_pixels,
        "max_delta": max_delta,
    }


def _locked_real_marker(
    *,
    position: str = "19.742138317,18.236871003,19.242143317",
    target: str = "0.500000000,1.399999976,0.000005000",
    size: str = "1.500000000",
    pixels: str = "2304",
    luma: str = "1.000000000",
    contextual: str = "contextual_visibility=pass contextual_reference_pixels=100 contextual_changed_pixels=50 contextual_max_delta=0.250000000",
) -> str:
    return (
        "MESHY RUNTIME CAPTURE PASS seed=42 lighting=normal "
        f"camera_position={position} camera_target={target} camera_size={size} "
        f"staged_visibility=pass staged_opaque_pixels={pixels} staged_luma_range={luma} {contextual}"
    )


def test_staged_visibility_uses_exact_sampling_grid_bounds() -> None:
    assert review._validate_staged_visibility(
        {"pass": True, "opaque_pixels": 2304, "luma_range": 1.0}
    ) == {"pass": True, "opaque_pixels": 2304, "luma_range": 1.0}
    for opaque_pixels in (1, 2305):
        with pytest.raises(review.ReviewError, match="staged|pixel"):
            review._validate_staged_visibility(
                {"pass": True, "opaque_pixels": opaque_pixels, "luma_range": 1.0}
            )
    for luma_range in (0.003, -1.0, math.nan, math.inf, 1.000001):
        with pytest.raises(review.ReviewError, match="staged|pixel"):
            review._validate_staged_visibility(
                {"pass": True, "opaque_pixels": 100, "luma_range": luma_range}
            )


def test_capture_marker_requires_locked_camera_and_real_world_target() -> None:
    parsed = review.parse_capture_marker(_locked_real_marker(), 42, "normal")
    assert parsed["target"] == [0.5, 1.399999976, 0.000005]
    assert parsed["size"] == 1.5

    forged_markers = (
        _locked_real_marker(
            position="0.500000000,1.399999976,0.000005000",
        ),
        _locked_real_marker(
            position="1.500000000,2.399999976,1.000005000",
        ),
        _locked_real_marker(size="nan"),
        _locked_real_marker(size="1000000000.0"),
    )
    for marker in forged_markers:
        with pytest.raises(review.ReviewError, match="camera|transform|size"):
            review.parse_capture_marker(marker, 42, "normal")


def _visible_png_bytes() -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)
        )

    dark = b"\x00\x00\x00\xff" * 800
    light = b"\xff\xff\xff\xff" * 800
    row = b"\x00" + dark + light
    rows = row * review.CAPTURE_SIZE[1]
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 1600, 900, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def test_binder_rejects_forged_runtime_document_before_promotion_ready(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir, contract = _bound_runtime_fixture(tmp_path)

    def fake_reimport(glb_path: Path, expected_triangles: int) -> SimpleNamespace:
        return SimpleNamespace(
            sha256=review.governance.file_sha256(glb_path),
            byte_size=glb_path.stat().st_size,
            triangle_count=expected_triangles,
        )

    monkeypatch.setattr(validate_module, "_reimport_with_blender", fake_reimport, raising=False)
    monkeypatch.setattr(validate_module, "_reimport_with_blender_process", fake_reimport, raising=False)
    inputs, _review, _generation, root = review._load_runtime_inputs(project_root, None, task_dir)
    png = _visible_png_bytes()
    preview = root / review.PREVIEW_ROOT_RELATIVE / contract.asset_id
    preview.mkdir(parents=True, mode=0o700)
    preview.chmod(0o700)
    capture_records = []
    for seed in SEEDS:
        for lighting in LIGHTING:
            name = review.capture_name(seed, lighting)
            path = tmp_path / name
            path.write_bytes(png)
            capture_records.append(
                {
                    "seed": seed,
                    "lighting": lighting,
                    "camera_transform": {
                        "projection": "orthogonal",
                        "position": [19.742138317, 18.236871003, 19.242143317],
                        "target": [0.5, 1.399999976, 0.000005],
                        "size": 1.5,
                    },
                    "staged_visibility": {
                        "pass": True,
                        "opaque_pixels": 2304,
                        "luma_range": 1.0,
                    },
                    "contextual_visibility": _canonical_contextual_visibility(),
                    "output_sha256": hashlib.sha256(png).hexdigest(),
                    "pass": True,
                    "reason": "pass",
                }
            )
            (preview / name).write_bytes(png)
            (preview / name).chmod(0o600)
    document = review.build_runtime_review_document(inputs, capture_records)
    document["captures"][0]["camera_transform"]["target"] = [0.0, 0.0, 0.0]
    document["captures"][1]["staged_visibility"]["opaque_pixels"] = 999999
    (preview / "runtime-review.json").write_bytes(canonical_json_bytes(document))
    (preview / "runtime-review.json").chmod(0o600)

    from tools import meshy_candidate_review as candidate_review

    with pytest.raises((review.ReviewError, candidate_review.ReviewError), match="camera|staged|visibility"):
        candidate_review.bind_promotion_evidence(root, task_dir)
    persisted_review = json.loads((task_dir / "review.json").read_text(encoding="utf-8"))
    assert persisted_review["state"] == "selected"


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

    separator = command.index("--")
    user_args = command[separator + 1 :]
    assert user_args[user_args.index("--lighting") + 1] == "normal"
    assert user_args[user_args.index("--asset-id") + 1] == "fixture_triangle"
    assert user_args[user_args.index("--category") + 1] == "gameplay_prop"
    assert "--asset-id" not in command[:separator]
    assert "shell=True" not in command


def test_runtime_command_keeps_user_args_intact_with_macos_renderer(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(
        review,
        "_godot_render_args",
        lambda: ("--display-driver", "macos", "--rendering-method", "gl_compatibility"),
    )
    command = review.build_godot_command(
        tmp_path / "overlay",
        42,
        "normal",
        tmp_path / "capture.png",
        asset_id="fixture_triangle",
        category="gameplay_prop",
    )
    user_args = command[command.index("--") + 1 :]
    assert user_args[user_args.index("--lighting") + 1] == "normal"
    assert user_args[user_args.index("--asset-id") + 1] == "fixture_triangle"
    assert user_args[user_args.index("--category") + 1] == "gameplay_prop"


def test_camera_marker_is_parsed_as_actual_finite_transform() -> None:
    marker = _locked_real_marker()

    parsed = review.parse_capture_marker(marker, 42, "normal")

    assert parsed == {
        "projection": "orthogonal",
        "position": [19.742138317, 18.236871003, 19.242143317],
        "target": [0.5, 1.399999976, 0.000005],
        "size": 1.5,
        "staged_visibility": {"pass": True, "opaque_pixels": 2304, "luma_range": 1.0},
        "contextual_visibility": _canonical_contextual_visibility(),
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


def test_capture_marker_requires_canonical_contextual_visibility_evidence() -> None:
    parsed = review.parse_capture_marker(_locked_real_marker(), 42, "normal")
    assert parsed["contextual_visibility"] == _canonical_contextual_visibility()

    invalid_context = (
        "",
        "contextual_visibility=fail contextual_reference_pixels=100 contextual_changed_pixels=50 contextual_max_delta=0.25",
        "contextual_visibility=pass contextual_reference_pixels=1 contextual_changed_pixels=1 contextual_max_delta=0.25",
        "contextual_visibility=pass contextual_reference_pixels=100 contextual_changed_pixels=101 contextual_max_delta=0.25",
        "contextual_visibility=pass contextual_reference_pixels=100 contextual_changed_pixels=49 contextual_max_delta=0.25",
        "contextual_visibility=pass contextual_reference_pixels=100 contextual_changed_pixels=50 contextual_max_delta=nan",
        "contextual_visibility=pass contextual_reference_pixels=nope contextual_changed_pixels=50 contextual_max_delta=0.25",
        "contextual_visibility=pass contextual_reference_pixels=100 contextual_changed_pixels=50 contextual_max_delta=0.25 contextual_max_delta=0.25",
    )
    for contextual in invalid_context:
        marker = _locked_real_marker(contextual=contextual).rstrip()
        with pytest.raises(review.ReviewError, match="contextual|visibility|canonical"):
            review.parse_capture_marker(marker, 42, "normal")


def _runtime_record(seed: int, lighting: str) -> dict:
    return {
        "seed": seed,
        "lighting": lighting,
        "camera_transform": {
            "projection": "orthogonal",
            "position": [19.742138317, 18.236871003, 19.242143317],
            "target": [0.5, 1.399999976, 0.000005],
            "size": 1.5,
        },
        "staged_visibility": {
            "pass": True,
            "opaque_pixels": 2304,
            "luma_range": 1.0,
        },
        "contextual_visibility": _canonical_contextual_visibility(),
        "output_sha256": "c" * 64,
        "pass": True,
        "reason": "pass",
    }


def _runtime_inputs() -> review.ValidatedTask:
    return review.ValidatedTask(
        asset_id="fixture_triangle",
        task_id="task-1",
        task_dir=Path("task-1"),
        cleaned_glb=Path("cleaned.glb"),
        validation_report=Path("blender-validation.json"),
        contract_hash="a" * 64,
        cleaned_glb_hash="b" * 64,
        blender_validation_hash="d" * 64,
        bounds_dimensions=(1.0, 1.0, 1.0),
    )


def test_runtime_record_and_document_reject_absent_or_forged_contextual_evidence() -> None:
    inputs = _runtime_inputs()
    captures = [
        _runtime_record(seed, lighting)
        for seed in SEEDS
        for lighting in LIGHTING
    ]
    document = review.build_runtime_review_document(inputs, captures)
    assert all("contextual_visibility" in item for item in document["captures"])

    absent = [dict(item) for item in captures]
    absent[0].pop("contextual_visibility")
    with pytest.raises(review.ReviewError, match="contextual|visibility|canonical"):
        review.build_runtime_review_document(inputs, absent)

    forged = [dict(item) for item in captures]
    forged[0]["contextual_visibility"] = _canonical_contextual_visibility(passed=False)
    with pytest.raises(review.ReviewError, match="contextual|visibility|canonical"):
        review.build_runtime_review_document(inputs, forged)

    forged_document = dict(document)
    forged_document["captures"] = [dict(item) for item in document["captures"]]
    forged_document["captures"][0]["contextual_visibility"] = _canonical_contextual_visibility(
        changed_pixels=49
    )
    with pytest.raises(review.ReviewError, match="contextual|visibility|canonical"):
        review._validate_runtime_document(forged_document, inputs)


def test_runtime_capture_source_contract_covers_mount_cutaway_and_exact_image_evidence() -> None:
    source = (ROOT / "scripts/validation/meshy_asset_review_capture.gd").read_text(
        encoding="utf-8"
    )
    assert 'text.begins_with("Vector3(")' in source
    assert 'text.begins_with("(")' in source
    assert "position.x + position.z" in source
    assert "_apply_local_cutaway" in source
    assert 'name.begins_with("Ceiling_")' in source
    assert 'name.begins_with("StructuralEdge_")' in source
    cutaway_source = source[
        source.index("func _apply_local_cutaway") : source.index("func _expand_visual_bounds")
    ]
    assert ".global_position" not in cutaway_source
    assert "parent_transform * wrapper.transform" in cutaway_source
    assert "Vector2(1.0, 1.0).normalized()" in source
    assert "max(visual_bounds.size.length() * 2.5, 4.0)" in source
    assert "contextual_visibility" in source
    assert "get_texture().get_image()" in source
    assert "image.save_png(output_path)" in source


def _bound_runtime_fixture(tmp_path: Path, category: str | None = None):
    from tests.test_meshy_blender_tools import _bound_fixture_task

    project_root, task_dir, contract = _bound_fixture_task(tmp_path, category=category)
    report = validate_cleaned_glb(task_dir / "cleaned.glb", contract, task_id=task_dir.name)
    report["blender_reimport_passed"] = True
    (task_dir / "blender-validation.json").write_bytes(canonical_json_bytes(report))
    return project_root, task_dir, contract


def _bound_dual_hash_runtime_fixture(tmp_path: Path):
    from tests.test_meshy_blender_tools import _dual_hash_bound_fixture_task

    project_root, task_dir, source_contract, task_contract = _dual_hash_bound_fixture_task(tmp_path)
    report = validate_cleaned_glb(task_dir / "cleaned.glb", source_contract, task_id=task_dir.name)
    report["blender_reimport_passed"] = True
    (task_dir / "blender-validation.json").write_bytes(canonical_json_bytes(report))
    return project_root, task_dir, source_contract, task_contract


def test_reverification_with_authenticated_caller_source_contract_succeeds(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir, source_contract, _task_contract = _bound_dual_hash_runtime_fixture(tmp_path)
    monkeypatch.setattr(
        validate_module,
        "_reimport_with_blender",
        lambda glb_path, expected_triangles: SimpleNamespace(
            sha256=review.governance.file_sha256(glb_path),
            byte_size=glb_path.stat().st_size,
            triangle_count=expected_triangles,
        ),
    )

    inputs, _review, generation, _root = review._load_runtime_inputs(
        project_root, tmp_path / "source-contract.json", task_dir
    )
    assert generation["contract_sha256"] == source_contract.sha256
    assert inputs.cleaned_glb == task_dir / "cleaned.glb"


def test_reverification_without_caller_source_contract_remains_fail_closed_for_dual_hash(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root, task_dir, _source_contract, _task_contract = _bound_dual_hash_runtime_fixture(tmp_path)
    monkeypatch.setattr(
        validate_module,
        "_reimport_with_blender",
        lambda *_args: pytest.fail("runtime must reject before Blender re-import"),
    )

    with pytest.raises(review.ReviewError, match="task-local contract"):
        review._load_runtime_inputs(project_root, None, task_dir)


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
