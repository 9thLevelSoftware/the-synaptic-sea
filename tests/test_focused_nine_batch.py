from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from tools import focused_nine_batch as batch


ASSETS = (
    "floor_1x1",
    "wall_straight_1x1",
    "doorway_frame_open_1x1",
    "pillar_support_1x1",
    "ramp_up_1x2",
    "ceiling_cap_1x1",
    "pressure_door_1x1",
    "hull_breach_seal_point",
    "fire_suppression_station",
)


def _args(project: Path, structural: Path, props: Path, report: Path, preview: Path) -> list[str]:
    return [
        "--project-root",
        str(project),
        "--structural-source-root",
        str(structural),
        "--props-source-root",
        str(props),
        "--report",
        str(report),
        "--preview-dir",
        str(preview),
    ]


def test_registry_is_exact_and_cli_rejects_duplicate_or_unknown_assets() -> None:
    assert batch.ORDERED_ASSET_IDS == ASSETS
    with pytest.raises(SystemExit):
        batch.parse_args(
            [
                *_args(Path("project"), Path("structural"), Path("props"), Path("report"), Path("preview")),
                "--asset",
                "floor_1x1",
                "--asset",
                "floor_1x1",
            ]
        )
    with pytest.raises(SystemExit):
        batch.parse_args(
            [
                *_args(Path("project"), Path("structural"), Path("props"), Path("report"), Path("preview")),
                "--asset",
                "not_registered",
            ]
        )


def test_dry_run_is_side_effect_free(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    project = tmp_path / "project"
    structural = tmp_path / "structural"
    props = tmp_path / "props"
    report = project / "assets/_staging/focused_nine/report.json"
    preview = project / "artifacts/validation-previews/focused-nine"
    project.mkdir()
    structural.mkdir()
    props.mkdir()
    before = batch.snapshot_runtime_surfaces(project)

    result = batch.main(
        [
            *_args(project, structural, props, report, preview),
            "--asset",
            "floor_1x1",
            "--dry-run",
        ]
    )

    assert result == 0
    assert batch.snapshot_runtime_surfaces(project) == before
    assert not report.exists()
    assert not (project / "assets/_staging/focused_nine").exists()


def test_failed_asset_preserves_previous_staging_and_reports_first_error(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = tmp_path / "project"
    structural = tmp_path / "structural"
    props = tmp_path / "props"
    report = project / "assets/_staging/focused_nine/report.json"
    preview = project / "artifacts/validation-previews/focused-nine"
    stage = project / "assets/_staging/focused_nine/props"
    stage.mkdir(parents=True)
    structural.mkdir()
    props.mkdir()
    existing = stage / "hull_breach_seal_point.glb"
    existing.write_bytes(b"previous")
    monkeypatch.setenv("FOCUSED_NINE_FORCE_EXPORT_FAILURE", "1")

    result = batch.main(
        [
            *_args(project, structural, props, report, preview),
            "--asset",
            "hull_breach_seal_point",
        ]
    )

    assert result == 1
    assert existing.read_bytes() == b"previous"
    document = json.loads(report.read_text(encoding="utf-8"))
    asset = next(item for item in document["assets"] if item["asset_id"] == "hull_breach_seal_point")
    assert asset["first_error"] == "forced export failure: hull_breach_seal_point"
    assert document["overall_pass"] is False
    assert document["preview"]["capture_status"] == "not_run"
    assert batch.validate_report(document) == []


def test_subset_output_keeps_registry_order_and_never_claims_nine_asset_pass(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = tmp_path / "project"
    structural = tmp_path / "structural"
    props = tmp_path / "props"
    report = project / "assets/_staging/focused_nine/report.json"
    preview = project / "artifacts/validation-previews/focused-nine"
    project.mkdir()
    structural.mkdir()
    props.mkdir()
    monkeypatch.setenv("FOCUSED_NINE_FORCE_EXPORT_FAILURE", "1")

    result = batch.main(
        [
            *_args(project, structural, props, report, preview),
            "--asset",
            "fire_suppression_station",
            "--asset",
            "floor_1x1",
        ]
    )

    assert result == 1
    document = json.loads(report.read_text(encoding="utf-8"))
    assert [asset["asset_id"] for asset in document["assets"]] == list(ASSETS)
    assert next(item for item in document["assets"] if item["asset_id"] == "floor_1x1")["first_error"] == (
        "forced export failure: floor_1x1"
    )
    assert "FOCUSED_NINE_BATCH PASS assets=9" not in document.get("status", "")


def test_capture_runs_exactly_one_bounded_non_headless_scene_command(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = tmp_path / "project"
    preview = project / "artifacts/validation-previews/focused-nine"
    project.mkdir()
    seen_command: list[str] = []
    seen_cwd: list[Path | None] = []
    seen_timeout: list[float | None] = []

    def fake_run(
        command: list[str], *, cwd: Path | None = None, timeout: float | None = None
    ) -> subprocess.CompletedProcess[str]:
        seen_command[:] = command
        seen_cwd.append(cwd)
        seen_timeout.append(timeout)
        preview.mkdir(parents=True)
        (preview / "focused-nine-comparison.png").write_bytes(b"preview")
        return subprocess.CompletedProcess(
            command,
            0,
            "FOCUSED_NINE_COMPARISON_CAPTURE PASS output=focused-nine-comparison.png",
            "",
        )

    monkeypatch.setattr(batch, "_run", fake_run)

    captured, blocker, output = batch._run_capture(project, preview)

    assert captured is True
    assert blocker is None
    assert "FOCUSED_NINE_COMPARISON_CAPTURE PASS" in output
    assert seen_command == [
        str(batch.GODOT),
        "--path",
        str(project),
        "--scene",
        batch._CAPTURE_SCENE,
        "--",
        "--output-dir",
        "res://artifacts/validation-previews/focused-nine",
        "--baseline-label",
        "Baseline",
        "--improved-label",
        "Improved",
    ]
    assert seen_cwd == [project]
    assert seen_timeout == [batch.CAPTURE_TIMEOUT_SECONDS]
    assert "--editor" not in seen_command
    assert "--headless" not in seen_command


@pytest.mark.parametrize(
    ("stdout", "create_preview", "expected_blocker"),
    (
        (
            "",
            True,
            "comparison capture blocker: missing FOCUSED_NINE_COMPARISON_CAPTURE PASS marker",
        ),
        (
            "FOCUSED_NINE_COMPARISON_CAPTURE PASS output=preview.png",
            False,
            "comparison capture blocker: stable preview was not published",
        ),
    ),
)
def test_capture_requires_marker_and_stable_preview(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    stdout: str,
    create_preview: bool,
    expected_blocker: str,
) -> None:
    project = tmp_path / "project"
    preview = project / "artifacts/validation-previews/focused-nine"
    project.mkdir()

    def fake_run(
        command: list[str], *, cwd: Path | None = None, timeout: float | None = None
    ) -> subprocess.CompletedProcess[str]:
        if create_preview:
            preview.mkdir(parents=True)
            (preview / "focused-nine-comparison.png").write_bytes(b"preview")
        return subprocess.CompletedProcess(command, 0, stdout, "")

    monkeypatch.setattr(batch, "_run", fake_run)

    captured, blocker, _output = batch._run_capture(project, preview)

    assert captured is False
    assert blocker == expected_blocker


def test_capture_timeout_returns_precise_blocker_and_cleans_only_capture_temporary_files(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = tmp_path / "project"
    preview = project / "artifacts/validation-previews/focused-nine"
    preview.mkdir(parents=True)
    temporary = preview / ".focused-nine-comparison-timeout.tmp"
    stable = preview / "focused-nine-comparison.png"
    unrelated = preview / "keep-me.txt"
    temporary.write_bytes(b"temporary")
    stable.write_bytes(b"stable")
    unrelated.write_bytes(b"unrelated")
    seen_timeout: list[float | None] = []

    def fake_run(
        command: list[str], *, cwd: Path | None = None, timeout: float | None = None
    ) -> subprocess.CompletedProcess[str]:
        seen_timeout.append(timeout)
        assert timeout is not None
        raise subprocess.TimeoutExpired(command, timeout, output="partial stdout", stderr="partial stderr")

    monkeypatch.setattr(batch, "_run", fake_run)

    captured, blocker, output = batch._run_capture(project, preview)

    assert captured is False
    assert blocker == "comparison capture blocker: timed out after 120 seconds"
    assert output == "partial stdout\npartial stderr"
    assert seen_timeout == [batch.CAPTURE_TIMEOUT_SECONDS]
    assert not temporary.exists()
    assert stable.read_bytes() == b"stable"
    assert unrelated.read_bytes() == b"unrelated"
