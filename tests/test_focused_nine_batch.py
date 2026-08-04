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


def test_validation_structural_source_root_defaults_to_generation_root(tmp_path: Path) -> None:
    project = tmp_path / "project"
    structural = tmp_path / "parallel-structural"
    props = tmp_path / "props"
    project.mkdir()
    structural.mkdir()
    props.mkdir()
    args = batch.parse_args(
        _args(
            project,
            structural,
            props,
            project / "assets/_staging/focused_nine/report.json",
            project / "artifacts/validation-previews/focused-nine",
        )
    )

    assert args.validation_structural_source_root == structural


def test_parallel_source_root_creates_fresh_source_and_reports_logical_reference(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = tmp_path / "project"
    parallel_root = tmp_path / "meshes/source/ship_structural_v0_focused_nine"
    original_root = tmp_path / "meshes/source/ship_structural_v0"
    props = tmp_path / "props"
    project.mkdir()
    parallel_root.mkdir(parents=True)
    original_root.mkdir(parents=True)
    props.mkdir()
    args = type(
        "Args",
        (),
        {
            "project_root": project,
            "structural_source_root": parallel_root,
            "validation_structural_source_root": original_root,
            "props_source_root": props,
        },
    )()
    created: list[Path] = []

    def create_empty(destination: Path) -> None:
        created.append(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(b"fresh empty source")

    monkeypatch.setattr(batch, "_create_empty_source_with_blender", create_empty)

    source = batch._ensure_source(args, "floor_1x1")
    record = batch._asset_record(
        project,
        args,
        "floor_1x1",
        source,
        (),
        _valid_metrics(),
        (),
        True,
        None,
    )

    expected = parallel_root / "floor_1x1/floor_1x1.blend"
    assert created == [expected.resolve()]
    assert source == expected.resolve()
    assert expected.read_bytes() == b"fresh empty source"
    assert not (original_root / "floor_1x1/floor_1x1.blend").exists()
    assert record["source_path"] == "res://assets/_staging/focused_nine/source_refs/floor_1x1.blend"
    assert str(parallel_root) not in json.dumps(record)
    assert str(original_root) not in json.dumps(record)


def test_live_structural_validator_uses_optional_validation_root_only(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = tmp_path / "project"
    parallel_root = tmp_path / "parallel"
    original_root = tmp_path / "original"
    project.mkdir()
    parallel_root.mkdir()
    original_root.mkdir()
    args = type(
        "Args",
        (),
        {
            "project_root": project,
            "structural_source_root": parallel_root,
            "validation_structural_source_root": original_root,
        },
    )()
    commands: list[list[str]] = []

    def fake_run(
        command: list[str], *, cwd: Path | None = None, timeout: float | None = None
    ) -> subprocess.CompletedProcess[str]:
        del cwd, timeout
        commands.append(command)
        return subprocess.CompletedProcess(command, 0, "", "")

    monkeypatch.setattr(batch, "_run", fake_run)

    assert batch._run_live_validators(args) == ([], [])
    structural_command = commands[0]
    assert structural_command[structural_command.index("--source-root") + 1] == str(original_root)
    assert str(parallel_root) not in structural_command


def test_validation_structural_source_root_rejects_runtime_alias_before_work(
    tmp_path: Path,
) -> None:
    project = tmp_path / "project"
    project.mkdir()
    runtime_alias = project / "assets/imported"
    runtime_alias.mkdir(parents=True)
    structural = tmp_path / "parallel"
    props = tmp_path / "props"
    structural.mkdir()
    props.mkdir()
    report = project / "assets/_staging/focused_nine/report.json"
    preview = project / "artifacts/validation-previews/focused-nine"

    with pytest.raises(SystemExit):
        batch.parse_args(
            [
                *_args(project, structural, props, report, preview),
                "--validation-structural-source-root",
                str(runtime_alias),
            ]
        )

    assert not report.exists()
    assert not (project / "assets/_staging/focused_nine").exists()


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


def test_private_batch_workspace_is_staged_for_evidence_and_cleaned_on_gate_error(
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
    stage = project / "assets/_staging/focused_nine"
    observed: list[Path] = []

    monkeypatch.setattr(batch, "_ensure_source", lambda args, asset_id: structural / f"{asset_id}.blend")
    monkeypatch.setattr(batch, "_run_recipe", lambda args, asset_id: None)

    def fake_export(source: Path, asset_id: str, destination: Path) -> tuple[Path, ...]:
        output = destination / f"{asset_id}.glb"
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(b"candidate")
        return (output,)

    def fake_inspect(path: Path, blender: Path) -> dict[str, object]:
        observed.append(path)
        path.resolve().relative_to(stage.resolve())
        return _valid_metrics()

    monkeypatch.setattr(batch, "_run_structural_export", fake_export)
    monkeypatch.setattr(batch.evidence, "inspect_staged_glb", fake_inspect)
    monkeypatch.setattr(
        batch.evidence,
        "validate_evidence",
        lambda record, minimum, maximum: ["injected evidence gate failure"],
    )

    assert batch.main([*_args(project, structural, props, report, preview), "--asset", "floor_1x1"]) == 1

    assert len(observed) == 1
    assert observed[0].resolve().is_relative_to(stage.resolve())
    assert not batch.contract.asset_stage_glb(project, "floor_1x1").exists()
    assert not list(stage.glob("focused-nine-batch-*"))


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


def _valid_metrics(seed: str = "a") -> dict[str, object]:
    return {
        "sha256": seed * 64,
        "byte_size": 123,
        "mesh_count": 2,
        "triangle_count": 456,
        "material_names": ["MAT_Test"],
        "bounds": {"local_min_m": [0.0, 0.0, 0.0], "local_max_m": [1.0, 1.0, 1.0]},
    }


def test_full_success_emits_each_staged_marker_once_before_report_and_pass(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    project = tmp_path / "project"
    structural = tmp_path / "structural"
    props = tmp_path / "props"
    report = project / "assets/_staging/focused_nine/report.json"
    preview = project / "artifacts/validation-previews/focused-nine"
    project.mkdir()
    structural.mkdir()
    props.mkdir()

    def fake_process(args: object, asset_id: str, private_root: Path) -> tuple[dict, Path, dict]:
        metrics = _valid_metrics("b" if asset_id in batch.contract.PROP_IDS else "a")
        roles = {
            role: {
                **metrics,
                "path": f"res://{batch.contract.asset_stage_glb(project, asset_id, role).relative_to(project).as_posix()}",
                "validation": "PASS",
            }
            for role in batch.contract.VARIANT_ROLES.get(asset_id, ("intact",))
        }
        record = batch._asset_record(
            project,
            args,
            asset_id,
            project / "source" / f"{asset_id}.blend",
            (),
            metrics,
            (),
            True,
            None,
            roles,
        )
        return record, project / "source" / f"{asset_id}.blend", roles

    def fake_capture(project_root: Path, preview_dir: Path) -> tuple[bool, None, str]:
        preview_dir.mkdir(parents=True)
        (preview_dir / "focused-nine-comparison.png").write_bytes(b"preview")
        return True, None, "FOCUSED_NINE_COMPARISON_CAPTURE PASS output=preview.png"

    def fake_publish_structural(private: Path, final: Path) -> None:
        final.mkdir(parents=True, exist_ok=True)
        if final.name == "pressure_door_1x1":
            for role in batch.contract.VARIANT_ROLES["pressure_door_1x1"]:
                batch.contract.asset_stage_glb(project, "pressure_door_1x1", role).write_bytes(b"pressure")
            for filename in (
                "pressure_door_1x1.manifest.json",
                "pressure_door_1x1.input.json",
                "pressure_door_1x1.tscn",
            ):
                (final / filename).write_text("fixture", encoding="utf-8")

    def fake_publish_prop(private_glb: Path, private_sidecar: Path, final_glb: Path, final_sidecar: Path) -> None:
        final_glb.parent.mkdir(parents=True, exist_ok=True)
        final_glb.write_bytes(b"prop")
        final_sidecar.write_bytes(b"sidecar")

    monkeypatch.setattr(batch, "_process_asset", fake_process)
    monkeypatch.setattr(batch, "_publish_structural_asset", fake_publish_structural)
    monkeypatch.setattr(batch, "_publish_prop_asset", fake_publish_prop)
    monkeypatch.setattr(batch, "_run_pressure_overlay", lambda project_root, private_root: [])
    monkeypatch.setattr(batch, "_run_capture", fake_capture)
    monkeypatch.setattr(batch, "_run_live_validators", lambda args: ([], []))

    assert batch.main(_args(project, structural, props, report, preview)) == 0

    lines = capsys.readouterr().out.splitlines()
    staged = [line for line in lines if line.startswith("FOCUSED_NINE_STAGED asset=")]
    assert staged == [f"FOCUSED_NINE_STAGED asset={asset_id}" for asset_id in ASSETS]
    assert all(lines.count(line) == 1 for line in staged)
    report_line = f"FOCUSED_NINE_REPORT path={report}"
    pass_line = "FOCUSED_NINE_BATCH PASS assets=9"
    assert lines.index(staged[-1]) < lines.index(report_line) < lines.index(pass_line)
    document = json.loads(report.read_text(encoding="utf-8"))
    assert document["improved"]["source_origin"] == "focused-nine-generated-source-root"
    assert document["improved"]["source_reference_root"] == (
        "res://assets/_staging/focused_nine/source_refs"
    )
    assert document["improved"]["no_original_source_replacement"] is True
    assert document["baseline"]["no_original_source_replacement"] is True


@pytest.mark.parametrize("diagnostic", ["WARNING: benign-looking warning", "ERROR: hidden error", "SCRIPT ERROR: hidden script error"])
def test_capture_rejects_gate_blocking_diagnostics_even_with_pass_marker_and_preview(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, diagnostic: str
) -> None:
    project = tmp_path / "project"
    preview = project / "artifacts/validation-previews/focused-nine"
    project.mkdir()

    def fake_run(
        command: list[str], *, cwd: Path | None = None, timeout: float | None = None
    ) -> subprocess.CompletedProcess[str]:
        preview.mkdir(parents=True)
        (preview / "focused-nine-comparison.png").write_bytes(b"preview")
        return subprocess.CompletedProcess(
            command,
            0,
            f"{diagnostic}\nFOCUSED_NINE_COMPARISON_CAPTURE PASS output=preview.png",
            "",
        )

    monkeypatch.setattr(batch, "_run", fake_run)

    captured, blocker, _output = batch._run_capture(project, preview)

    assert captured is False
    assert blocker == "comparison capture blocker: Godot emitted diagnostics"


def test_proof_contains_asset_validation_and_complete_role_metrics(
    tmp_path: Path,
) -> None:
    project = tmp_path / "project"
    project.mkdir()
    report = project / "assets/_staging/focused_nine/report.json"
    preview = project / "artifacts/validation-previews/focused-nine"
    source_paths: dict[str, str] = {}
    records: list[dict] = []
    role_metrics: dict[str, dict[str, dict[str, object]]] = {}

    for index, asset_id in enumerate(ASSETS):
        metrics = _valid_metrics(chr(ord("a") + index))
        record = batch._asset_record(
            project,
            object(),
            asset_id,
            project / "source" / f"{asset_id}.blend",
            (),
            metrics,
            (),
            True,
            None,
        )
        records.append(record)
        source_paths[asset_id] = f"/sources/{asset_id}.blend"
        role_metrics[asset_id] = {}
        for role_index, role in enumerate(batch.contract.VARIANT_ROLES.get(asset_id, ("intact",))):
            role_metrics[asset_id][role] = {
                **_valid_metrics(chr(ord("a") + index + role_index)),
                "path": record["staged_glbs"][role_index],
                "validation": "PASS",
            }

    batch._write_proof(project, records, source_paths, report, preview, role_metrics)

    proof = (project / batch.PROOF_RELATIVE).read_text(encoding="utf-8")
    for asset_id in ASSETS:
        assert f"### `{asset_id}`" in proof
        assert "Validation result: `PASS`" in proof
    for role in ("intact", "damaged", "breached"):
        assert f"| `{role}` | `PASS` |" in proof
    assert "| `path` |" not in proof
    assert proof.count("SHA-256") >= 9
    assert "FOCUSED_NINE_BATCH PASS assets=9" in proof
    assert "No original source replacement occurred." in proof


def test_proof_refuses_to_write_before_all_assets_pass(tmp_path: Path) -> None:
    project = tmp_path / "project"
    project.mkdir()
    proof = project / batch.PROOF_RELATIVE
    failed = {
        "asset_id": "floor_1x1",
        "pass": False,
        "validation": ["blocked"],
        "first_error": "blocked",
    }

    with pytest.raises(ValueError, match="cannot write proof before all assets pass"):
        batch._write_proof(project, [failed], {}, project / "report.json", project / "preview", {})

    assert not proof.exists()


def test_prop_pair_publication_rolls_back_new_glb_when_sidecar_replace_fails(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    private_glb = tmp_path / "private.glb"
    private_sidecar = tmp_path / "private.sidecar.json"
    final_glb = tmp_path / "stage" / "asset.glb"
    final_sidecar = tmp_path / "stage" / "asset.sidecar.json"
    private_glb.write_bytes(b"new glb")
    private_sidecar.write_bytes(b"new sidecar")

    real_replace = batch.os.replace

    def fail_sidecar(source: str | bytes, destination: str | bytes, *args: object, **kwargs: object) -> None:
        if Path(source) == private_sidecar:
            raise OSError("injected sidecar publication failure")
        real_replace(source, destination, *args, **kwargs)

    monkeypatch.setattr(batch.os, "replace", fail_sidecar)

    with pytest.raises(OSError, match="injected sidecar publication failure"):
        batch._publish_prop_asset(private_glb, private_sidecar, final_glb, final_sidecar)

    assert not final_glb.exists()
    assert not final_sidecar.exists()
    assert private_sidecar.exists()
    assert not list(final_glb.parent.glob(".*previous-*"))


def test_prop_pair_publication_restores_both_prior_targets_without_touching_unrelated_state(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    private_glb = tmp_path / "private.glb"
    private_sidecar = tmp_path / "private.sidecar.json"
    final_glb = tmp_path / "stage" / "asset.glb"
    final_sidecar = tmp_path / "stage" / "asset.sidecar.json"
    unrelated = tmp_path / "stage" / "keep.txt"
    prior_glb = tmp_path / "prior.glb"
    final_glb.parent.mkdir()
    private_glb.write_bytes(b"new glb")
    private_sidecar.write_bytes(b"new sidecar")
    prior_glb.write_bytes(b"old glb")
    final_glb.symlink_to(prior_glb)
    final_sidecar.write_bytes(b"old sidecar")
    unrelated.write_bytes(b"unrelated")

    real_replace = batch.os.replace

    def fail_sidecar(source: str | bytes, destination: str | bytes, *args: object, **kwargs: object) -> None:
        if Path(source) == private_sidecar:
            raise OSError("injected sidecar publication failure")
        real_replace(source, destination, *args, **kwargs)

    monkeypatch.setattr(batch.os, "replace", fail_sidecar)

    with pytest.raises(OSError, match="injected sidecar publication failure"):
        batch._publish_prop_asset(private_glb, private_sidecar, final_glb, final_sidecar)

    assert final_glb.is_symlink()
    assert final_glb.readlink() == prior_glb
    assert prior_glb.read_bytes() == b"old glb"
    assert final_sidecar.read_bytes() == b"old sidecar"
    assert unrelated.read_bytes() == b"unrelated"
    assert not list(final_glb.parent.glob(".*previous-*"))


def test_proof_uses_logical_source_reference_instead_of_external_absolute_path(tmp_path: Path) -> None:
    project = tmp_path / "project"
    project.mkdir()
    report = project / "assets/_staging/focused_nine/report.json"
    preview = project / "artifacts/validation-previews/focused-nine"
    source_paths: dict[str, str] = {}
    records: list[dict] = []
    role_metrics: dict[str, dict[str, dict[str, object]]] = {}

    for index, asset_id in enumerate(ASSETS):
        metrics = _valid_metrics(chr(ord("a") + index))
        record = batch._asset_record(project, object(), asset_id, None, (), metrics, (), True, None)
        records.append(record)
        source_paths[asset_id] = f"/external/untrusted/{asset_id}.blend"
        role_metrics[asset_id] = {
            role: {
                **_valid_metrics(chr(ord("a") + index + role_index)),
                "path": record["staged_glbs"][role_index],
                "validation": "PASS",
            }
            for role_index, role in enumerate(batch.contract.VARIANT_ROLES.get(asset_id, ("intact",)))
        }

    batch._write_proof(project, records, source_paths, report, preview, role_metrics)

    proof = (project / batch.PROOF_RELATIVE).read_text(encoding="utf-8")
    assert "/external/untrusted/" not in proof
    assert f"Source: `res://assets/_staging/focused_nine/source_refs/{ASSETS[0]}.blend`" in proof


def test_ensure_source_rejects_runtime_alias_before_creating_blend(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project = tmp_path / "project"
    malicious_root = project / "assets/imported"
    props_root = tmp_path / "props"
    project.mkdir()
    malicious_root.mkdir(parents=True)
    props_root.mkdir()
    args = type("Args", (), {
        "project_root": project,
        "structural_source_root": malicious_root,
        "props_source_root": props_root,
    })()
    created = False

    def fail_if_called(destination: Path) -> None:
        nonlocal created
        created = True

    monkeypatch.setattr(batch, "_create_empty_source_with_blender", fail_if_called)

    with pytest.raises(ValueError, match="runtime surface"):
        batch._ensure_source(args, "floor_1x1")

    assert created is False
    assert not (malicious_root / "floor_1x1/floor_1x1.blend").exists()


@pytest.mark.parametrize("scope", ["stage", "preview"])
def test_output_path_rejects_static_symlink_alias_before_writing(
    tmp_path: Path, scope: str
) -> None:
    project = tmp_path / "project"
    project.mkdir()
    outside = tmp_path / "outside"
    outside.mkdir()
    stage = project / "assets/_staging/focused_nine"
    preview = project / "artifacts/validation-previews/focused-nine"
    if scope == "stage":
        stage.parent.mkdir(parents=True)
        stage.symlink_to(outside, target_is_directory=True)
    else:
        preview.parent.mkdir(parents=True)
        preview.symlink_to(outside, target_is_directory=True)

    report = stage / "report.json"
    with pytest.raises(ValueError, match="symlink"):
        batch._validate_output_paths(project, report, preview)

    assert not (outside / "report.json").exists()
    assert not (outside / "focused-nine-comparison.png").exists()


def test_recipe_timeout_is_bounded_and_reported_deterministically(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    args = type("Args", (), {
        "project_root": tmp_path / "project",
        "structural_source_root": tmp_path / "structural",
        "props_source_root": tmp_path / "props",
    })()
    command = ["blender", "--background"]

    def timeout_run(*_args: object, **_kwargs: object) -> subprocess.CompletedProcess[str]:
        raise subprocess.TimeoutExpired(command, batch.RECIPE_TIMEOUT_SECONDS, output="partial")

    monkeypatch.setattr(batch, "_run", timeout_run)

    with pytest.raises(RuntimeError, match="timed out after"):
        batch._run_recipe(args, "floor_1x1")


def test_structural_publication_rolls_back_after_replace_failure_without_old_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    private = tmp_path / "private" / "floor_1x1"
    final = tmp_path / "stage" / "floor_1x1"
    private.mkdir(parents=True)
    (private / "floor_1x1.glb").write_bytes(b"new")
    real_replace = batch.os.replace

    def replace_then_fail(source: str | bytes, destination: str | bytes, *args: object, **kwargs: object) -> None:
        if Path(source) == private:
            real_replace(source, destination, *args, **kwargs)
            raise OSError("injected structural publication failure")
        real_replace(source, destination, *args, **kwargs)

    monkeypatch.setattr(batch.os, "replace", replace_then_fail)

    with pytest.raises(OSError, match="injected structural publication failure"):
        batch._publish_structural_asset(private, final)

    assert not final.exists()
    assert not final.is_symlink()
    assert not list(final.parent.glob(".*previous*"))


def test_structural_publication_rolls_back_after_replace_failure_with_old_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    private = tmp_path / "private" / "floor_1x1"
    final = tmp_path / "stage" / "floor_1x1"
    private.mkdir(parents=True)
    final.mkdir(parents=True)
    (private / "floor_1x1.glb").write_bytes(b"new")
    (final / "floor_1x1.glb").write_bytes(b"old")
    real_replace = batch.os.replace

    def replace_then_fail(source: str | bytes, destination: str | bytes, *args: object, **kwargs: object) -> None:
        if Path(source) == private:
            real_replace(source, destination, *args, **kwargs)
            raise OSError("injected structural publication failure")
        real_replace(source, destination, *args, **kwargs)

    monkeypatch.setattr(batch.os, "replace", replace_then_fail)

    with pytest.raises(OSError, match="injected structural publication failure"):
        batch._publish_structural_asset(private, final)

    assert (final / "floor_1x1.glb").read_bytes() == b"old"
    assert not list(final.parent.glob(".*previous*"))


def test_structural_publication_recovers_exact_local_backup_before_replacing(
    tmp_path: Path,
) -> None:
    private = tmp_path / "private" / "floor_1x1"
    final = tmp_path / "stage" / "floor_1x1"
    backup = final.with_name(f".{final.name}.previous")
    private.mkdir(parents=True)
    backup.mkdir(parents=True)
    (backup / "floor_1x1.glb").write_bytes(b"old")
    (private / "floor_1x1.glb").write_bytes(b"new")

    batch._publish_structural_asset(private, final)

    assert (final / "floor_1x1.glb").read_bytes() == b"new"
    assert not backup.exists()


@pytest.mark.parametrize("requested", [ASSETS, ("pressure_door_1x1",)])
def test_pressure_overlay_failure_publishes_no_candidate_and_reports_blocker(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    requested: tuple[str, ...],
) -> None:
    project = tmp_path / "project"
    structural = tmp_path / "structural"
    props = tmp_path / "props"
    report = project / "assets/_staging/focused_nine/report.json"
    preview = project / "artifacts/validation-previews/focused-nine"
    project.mkdir()
    structural.mkdir()
    props.mkdir()
    stage = project / "assets/_staging/focused_nine"
    prior = stage / "structural/floor_1x1/floor_1x1.glb"
    prior.parent.mkdir(parents=True)
    prior.write_bytes(b"prior")

    def fake_process(args: object, asset_id: str, private_root: Path) -> tuple[dict, Path, dict]:
        record = batch._asset_record(project, args, asset_id, None, (), _valid_metrics(), (), True, None)
        return record, project / "sources" / f"{asset_id}.blend", {}

    def fake_publish(private: Path, final: Path) -> None:
        final.mkdir(parents=True, exist_ok=True)
        batch.contract.asset_stage_glb(project, "pressure_door_1x1").write_bytes(b"candidate")

    monkeypatch.setattr(batch, "_process_asset", fake_process)
    monkeypatch.setattr(batch, "_publish_structural_asset", fake_publish)
    monkeypatch.setattr(batch, "_publish_prop_asset", lambda *args: None)
    monkeypatch.setattr(
        batch,
        "_run_pressure_overlay",
        lambda project_root, private_root: ["injected wrapper failure"],
    )
    monkeypatch.setattr(batch, "_run_live_validators", lambda args: ([], []))

    result = batch.main([*_args(project, structural, props, report, preview), *sum((["--asset", asset] for asset in requested), [])])

    assert result == 1
    assert prior.read_bytes() == b"prior"
    candidate = stage / "structural/pressure_door_1x1/pressure_door_1x1.glb"
    assert not candidate.exists()
    document = json.loads(report.read_text(encoding="utf-8"))
    assert document["overall_pass"] is False
    pressure = next(item for item in document["assets"] if item["asset_id"] == "pressure_door_1x1")
    assert pressure["pass"] is False
    assert "injected wrapper failure" in pressure["first_error"]
