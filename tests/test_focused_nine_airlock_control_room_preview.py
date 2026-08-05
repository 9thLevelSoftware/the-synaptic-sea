from __future__ import annotations

import argparse
import base64
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

from tools import focused_nine_airlock_control_room_preview as preview

PROJECT_ROOT = Path(__file__).resolve().parents[1]
STAGING_RELATIVE = Path("assets/_staging/focused_nine")
STRUCTURAL_RELATIVE = Path("assets/_staging/focused_nine/structural")
PROPS_RELATIVE = Path("assets/_staging/focused_nine/props")
PREVIEW_RELATIVE = Path("artifacts/validation-previews/focused-nine")
PROOF_RELATIVE = Path("docs/superpowers/proofs/focused-nine-airlock-control-room.md")



def _args(project: Path, *, dry_run: bool = False) -> list[str]:
    values = [
        "--project-root",
        str(project),
        "--staging-root",
        str(project / STAGING_RELATIVE),
        "--preview-dir",
        str(project / PREVIEW_RELATIVE),
        "--proof",
        str(project / PROOF_RELATIVE),
    ]
    if dry_run:
        values.append("--dry-run")
    return values



def _copy_regular(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)



def _project_fixture(tmp_path: Path) -> Path:
    project = tmp_path / "project"
    project.mkdir()
    shutil.copytree(
        PROJECT_ROOT / STAGING_RELATIVE,
        project / STAGING_RELATIVE,
        copy_function=shutil.copy2,
    )
    _copy_regular(PROJECT_ROOT / "project.godot", project / "project.godot")
    _copy_regular(PROJECT_ROOT / "icon.svg", project / "icon.svg")
    _copy_regular(
        PROJECT_ROOT / "scripts/validation/focused_nine_airlock_control_room_capture.gd",
        project / "scripts/validation/focused_nine_airlock_control_room_capture.gd",
    )
    _copy_regular(
        PROJECT_ROOT / "scenes/validation/focused_nine_airlock_control_room_harness.tscn",
        project / "scenes/validation/focused_nine_airlock_control_room_harness.tscn",
    )
    _copy_regular(
        PROJECT_ROOT
        / "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json",
        project
        / "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json",
    )
    return project



def _namespace_args(project: Path, *, dry_run: bool = False) -> argparse.Namespace:
    return preview.parse_args(_args(project, dry_run=dry_run))



def _stub_capture(monkeypatch: pytest.MonkeyPatch, *, output: Path | None = None) -> None:
    monkeypatch.setattr(preview, "_build_overlay", lambda *args: args[-1])
    monkeypatch.setattr(
        preview,
        "_run_room_capture",
        lambda *_args: (True, "FOCUSED_NINE_AIRLOCK_ROOM_CAPTURE PASS output=room.png", output),
    )
    monkeypatch.setattr(preview, "_validate_capture_image", lambda _path: (1600, 900))



def _stub_validation(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(preview, "validate_inputs", lambda _args: preview.ValidatedInputs(()))
    monkeypatch.setattr(preview, "snapshot_runtime_surfaces", lambda _root: ("stable",))



def test_parse_args_rejects_runtime_or_symlinked_staging_roots(tmp_path: Path) -> None:
    project = tmp_path / "project"
    project.mkdir()
    runtime_root = project / "assets/imported"
    with pytest.raises(SystemExit):
        preview.parse_args(
            [
                "--project-root",
                str(project),
                "--staging-root",
                str(runtime_root),
                "--preview-dir",
                str(project / PREVIEW_RELATIVE),
                "--proof",
                str(project / PROOF_RELATIVE),
            ]
        )

    outside = tmp_path / "outside"
    outside.mkdir()
    alias = project / "staging-alias"
    alias.symlink_to(outside, target_is_directory=True)
    with pytest.raises(SystemExit):
        preview.parse_args(
            [
                "--project-root",
                str(project),
                "--staging-root",
                str(alias),
                "--preview-dir",
                str(project / PREVIEW_RELATIVE),
                "--proof",
                str(project / PROOF_RELATIVE),
            ]
        )

    with pytest.raises(SystemExit):
        preview.parse_args(_args(project / ".." / "project"))



def test_parse_args_accepts_only_the_mac_var_system_alias(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    var_alias = Path("/var")
    resolved_var = var_alias.resolve()
    if resolved_var == var_alias:
        pytest.skip("/var is not a symlink on this platform")
    try:
        relative = project.resolve().relative_to(resolved_var)
    except ValueError:
        pytest.skip("fixture is not below the macOS /var alias")
        return
    lexical_project = var_alias / relative

    parsed = preview.parse_args(_args(lexical_project))

    assert parsed.project_root == project.resolve()
    assert parsed.staging_root == (project / STAGING_RELATIVE).resolve()



def test_validate_inputs_rejects_missing_glb_before_overlay_copy(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = _project_fixture(tmp_path)
    missing = project / STRUCTURAL_RELATIVE / "floor_1x1/floor_1x1.glb"
    missing.unlink()
    args = _namespace_args(project)
    copied = False

    def should_not_copy(*_args: object) -> None:
        nonlocal copied
        copied = True
        raise AssertionError("overlay copy must not start before all staged inputs validate")

    monkeypatch.setattr(preview, "_build_overlay", should_not_copy)
    result = preview.run(args)

    assert result.exit_code == 1
    assert "missing staged GLB" in result.reason
    assert copied is False



def test_validate_inputs_rejects_missing_prop_visual_sidecar(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    (project / PROPS_RELATIVE / "hull_breach_seal_point.sidecar.json").unlink()

    with pytest.raises(ValueError, match="missing prop visual sidecar"):
        preview.validate_inputs(_namespace_args(project))



def test_validate_inputs_rejects_symlinked_props_directory(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    props = project / PROPS_RELATIVE
    outside = tmp_path / "outside-props"
    props.rename(outside)
    props.symlink_to(outside, target_is_directory=True)

    with pytest.raises(ValueError, match="symlink"):
        preview.validate_inputs(_namespace_args(project))



def test_validate_inputs_rejects_missing_pressure_door_package_member(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    package = project / STRUCTURAL_RELATIVE / "pressure_door_1x1"
    (package / "pressure_door_1x1.manifest.json").unlink()

    with pytest.raises(ValueError, match="manifest"):
        preview.validate_inputs(_namespace_args(project))



@pytest.mark.parametrize(
    "relative",
    [
        "props/hull_breach_seal_point.sidecar.json",
        "structural/floor_1x1/floor_1x1.glb",
        "structural/pressure_door_1x1/pressure_door_1x1.manifest.json",
    ],
)
def test_validate_inputs_rejects_symlinked_staged_inputs(tmp_path: Path, relative: str) -> None:
    project = _project_fixture(tmp_path)
    target = project / STAGING_RELATIVE / relative
    outside = tmp_path / f"outside-{Path(relative).name}"
    shutil.copy2(target, outside)
    target.unlink()
    target.symlink_to(outside)

    with pytest.raises(ValueError, match="symlink"):
        preview.validate_inputs(_namespace_args(project))



def test_prop_sidecar_validator_failure_is_a_preflight_failure(tmp_path: Path) -> None:
    project = _project_fixture(tmp_path)
    sidecar = project / PROPS_RELATIVE / "hull_breach_seal_point.sidecar.json"
    document = json.loads(sidecar.read_text(encoding="utf-8"))
    document["binding"] = {"namespace": "wrong", "ids": ["wrong"]}
    sidecar.write_text(json.dumps(document), encoding="utf-8")

    with pytest.raises(ValueError, match="sidecar validation"):
        preview.validate_inputs(_namespace_args(project))



def test_capture_diagnostics_block_publication_and_preserve_existing_preview(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = _project_fixture(tmp_path)
    args = _namespace_args(project)
    preview_path = project / PREVIEW_RELATIVE / "focused-nine-airlock-control-room.png"
    proof_path = project / PROOF_RELATIVE
    preview_path.parent.mkdir(parents=True)
    proof_path.parent.mkdir(parents=True)
    preview_path.write_bytes(b"previous")
    proof_path.write_bytes(b"previous proof")
    _stub_validation(monkeypatch)
    monkeypatch.setattr(preview, "_build_overlay", lambda *args: args[-1])
    monkeypatch.setattr(
        preview,
        "_run_room_capture",
        lambda *_args: (False, "ERROR: injected", None),
    )

    result = preview.run(args)

    assert result.exit_code == 1
    assert "diagnostic" in result.reason.lower()
    assert preview_path.read_bytes() == b"previous"
    assert proof_path.read_bytes() == b"previous proof"



def test_capture_pass_marker_with_warning_is_rejected_even_when_exit_zero(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    overlay = tmp_path / "overlay"
    overlay.mkdir()
    wrapper = tmp_path / "godot-output-wrapper.py"
    wrapper.write_text(
        "import sys\n"
        "print('FOCUSED_NINE_AIRLOCK_ROOM_CAPTURE PASS output=room.png')\n"
        "print('WARNING: injected')\n",
        encoding="utf-8",
    )

    ok, detail, output = preview._run_room_capture(
        overlay,
        overlay / "artifacts/validation-previews/focused-nine",
        godot=sys.executable,
        wrapper=wrapper,
    )

    assert ok is False
    assert "WARNING:" in detail
    assert output is None



def test_bounded_capture_timeout_kills_process_group(tmp_path: Path) -> None:
    wrapper = tmp_path / "sleep-wrapper.py"
    wrapper.write_text("import time\ntime.sleep(30)\n", encoding="utf-8")
    started = time.monotonic()

    with pytest.raises(preview.CaptureTimeout):
        preview._run_bounded_process(
            [sys.executable, str(wrapper)], timeout=0.1, label="test capture"
        )

    assert time.monotonic() - started < 3



def test_wrong_png_dimensions_block_publication(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    image = tmp_path / "capture.png"
    image.write_bytes(b"\x89PNG\r\n\x1a\nnot-empty")
    monkeypatch.setattr(
        preview,
        "_run_bounded_process",
        lambda *_args, **_kwargs: subprocess.CompletedProcess(
            [], 0, "pixelWidth: 1024\npixelHeight: 768\n", ""
        ),
    )

    with pytest.raises(ValueError, match="1600x900"):
        preview._validate_capture_image(image)


def test_jpeg_renamed_png_is_rejected_even_when_sips_reports_target_dimensions(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    image = tmp_path / "capture.png"
    image.write_bytes(
        base64.b64decode(
            "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoM"
            "DAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsN"
            "FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/"
            "wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QA"
            "tRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2Jyg"
            "gkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGipc3R1dnd4eXqD"
            "hIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uH"
            "i4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8Q"
            "AtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYn"
            "LRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6"
            "goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4"
            "uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD9U6KKKAP/2Q=="
        )
    )
    assert image.read_bytes().startswith(b"\xff\xd8\xff")
    monkeypatch.setattr(
        preview,
        "_run_bounded_process",
        lambda *_args, **_kwargs: subprocess.CompletedProcess(
            [], 0, "pixelWidth: 1600\npixelHeight: 900\n", ""
        ),
    )

    with pytest.raises(ValueError, match="PNG"):
        preview._validate_capture_image(image)


def test_build_proof_maps_absolute_capture_marker_to_logical_output_path(tmp_path: Path) -> None:
    external_marker_path = Path(
        "/private/tmp/focused-nine-room-preview-abc/project/"
        "artifacts/validation-previews/focused-nine/focused-nine-airlock-control-room.png"
    )
    proof = preview.build_proof(
        output_path=tmp_path / "published" / "focused-nine-airlock-control-room.png",
        dimensions=(1600, 900),
        marker=f"{preview.CAPTURE_MARKER_PREFIX}{external_marker_path}",
    )

    assert (
        f"{preview.CAPTURE_MARKER_PREFIX}res://"
        "artifacts/validation-previews/focused-nine/focused-nine-airlock-control-room.png"
    ) in proof
    assert str(external_marker_path) not in proof
    assert str(tmp_path) not in proof


def test_build_proof_redacts_unknown_absolute_marker_path(tmp_path: Path) -> None:
    proof = preview.build_proof(
        output_path=tmp_path / "published" / "focused-nine-airlock-control-room.png",
        dimensions=(1600, 900),
        marker=f"{preview.CAPTURE_MARKER_PREFIX}/private/unexpected/secret.png",
    )

    assert f"{preview.CAPTURE_MARKER_PREFIX}<redacted>" in proof
    assert "/private/unexpected/secret.png" not in proof
    assert str(tmp_path) not in proof



def test_runtime_snapshot_mismatch_blocks_publication(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = _project_fixture(tmp_path)
    args = _namespace_args(project)
    snapshots = iter([("before",), ("after",)])
    monkeypatch.setattr(preview, "snapshot_runtime_surfaces", lambda _root: next(snapshots))
    monkeypatch.setattr(preview, "validate_inputs", lambda _args: preview.ValidatedInputs(()))
    _stub_capture(monkeypatch, output=project / "capture.png")

    result = preview.run(args)

    assert result.exit_code == 1
    assert "runtime surface mismatch" in result.reason
    assert not (project / PREVIEW_RELATIVE / "focused-nine-airlock-control-room.png").exists()



def test_dry_run_makes_no_output(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = _project_fixture(tmp_path)
    args = _namespace_args(project, dry_run=True)
    _stub_validation(monkeypatch)
    monkeypatch.setattr(
        preview,
        "_build_overlay",
        lambda *_args: (_ for _ in ()).throw(AssertionError("dry run must not build overlay")),
    )

    result = preview.run(args)

    assert result.exit_code == 0
    assert result.dry_run is True
    assert not (project / PREVIEW_RELATIVE).exists()
    assert not (project / PROOF_RELATIVE).exists()



def test_successful_publication_writes_both_outputs_from_verified_bytes(tmp_path: Path) -> None:
    preview_path = tmp_path / "preview" / "room.png"
    proof_path = tmp_path / "proof" / "room.md"

    preview.publish_artifacts(preview_path, b"new-preview", proof_path, "new-proof\n")

    assert preview_path.read_bytes() == b"new-preview"
    assert proof_path.read_bytes() == b"new-proof\n"



@pytest.mark.parametrize(
    ("old_preview", "old_proof"),
    [
        (b"old-preview", b"old-proof"),
        (b"", None),
        (None, b"old-proof"),
    ],
)
def test_late_publication_failure_restores_exact_old_preview_and_proof(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    old_preview: bytes | None,
    old_proof: bytes | None,
) -> None:
    preview_path = tmp_path / "preview" / "room.png"
    proof_path = tmp_path / "proof" / "room.md"
    preview_path.parent.mkdir()
    proof_path.parent.mkdir()
    if old_preview is not None:
        preview_path.write_bytes(old_preview)
    if old_proof is not None:
        proof_path.write_bytes(old_proof)
    real_replace = preview.os.replace
    replacements = 0

    def fail_proof_replace(source: str, destination: str) -> None:
        nonlocal replacements
        if Path(destination) == proof_path and replacements == 1:
            replacements += 1
            raise OSError("injected late proof replacement failure")
        replacements += 1
        real_replace(source, destination)

    monkeypatch.setattr(preview.os, "replace", fail_proof_replace)

    with pytest.raises(preview.PublicationError, match="proof"):
        preview.publish_artifacts(
            preview_path,
            b"new-preview",
            proof_path,
            "new-proof\n",
        )

    assert preview_path.exists() is (old_preview is not None)
    assert proof_path.exists() is (old_proof is not None)
    if old_preview is not None:
        assert preview_path.read_bytes() == old_preview
    if old_proof is not None:
        assert proof_path.read_bytes() == old_proof


@pytest.mark.parametrize("bootstrap_state", ["missing", "symlinked"])
def test_missing_or_symlinked_bootstrap_asset_blocks_before_capture(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, bootstrap_state: str
) -> None:
    project = _project_fixture(tmp_path)
    icon = project / "icon.svg"
    if bootstrap_state == "missing":
        icon.unlink()
    else:
        outside = tmp_path / "outside-icon.svg"
        shutil.copy2(icon, outside)
        icon.unlink()
        icon.symlink_to(outside)

    _stub_validation(monkeypatch)
    captured = False

    def should_not_capture(*_args: object, **_kwargs: object) -> tuple[bool, str, None]:
        nonlocal captured
        captured = True
        return False, "capture must not start", None

    monkeypatch.setattr(preview, "_run_room_capture", should_not_capture)

    result = preview.run(_namespace_args(project))

    assert result.exit_code == 1
    assert "bootstrap" in result.reason
    assert captured is False



def test_overlay_is_external_and_contains_only_regular_capture_inputs(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = _project_fixture(tmp_path)
    inputs = preview.validate_inputs(_namespace_args(project))
    with preview.disposable_overlay(project, inputs) as overlay:
        assert overlay != project
        assert not str(overlay).startswith(str(project))
        assert (overlay / "project.godot").is_file()
        assert (overlay / "icon.svg").is_file()
        assert not (overlay / "icon.svg").is_symlink()
        assert (overlay / "icon.svg").read_bytes() == (project / "icon.svg").read_bytes()
        assert (overlay / "scenes/validation/focused_nine_airlock_control_room_harness.tscn").is_file()
        assert (overlay / "scripts/validation/focused_nine_airlock_control_room_capture.gd").is_file()
        for path in preview.required_staged_paths(inputs):
            copied = overlay / path.relative_to(project)
            assert copied.is_file()
            assert not copied.is_symlink()
    assert not overlay.exists()
