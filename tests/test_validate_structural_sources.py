from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

import pytest

import tools.validate_structural_sources as validator
from tools.structural_source_contract import (
    build_source_record,
    canonical_json,
    load_source_spec,
    source_output_paths,
)
from tools.validate_structural_sources import validate_report, validate_sources


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = PROJECT_ROOT / "tools" / "validate_structural_sources.py"


@pytest.fixture
def BASE_REPORT() -> dict:
    spec = load_source_spec(PROJECT_ROOT, "floor_1x1")
    return {
        "module_id": spec.module_id,
        "root_name": "ModuleRoot_floor_1x1",
        "root_identity": True,
        "helper_names": sorted(
            [
                "Origin",
                "Anchor_FloorCenter",
                "CollisionProxy",
                *(socket.anchor_name for socket in spec.sockets),
            ]
        ),
        "collision": {
            "proxy_shape": spec.collision_proxy_shape,
            "nav_blocker": spec.nav_blocker,
        },
        "socket_records": [
            {
                "name": socket.anchor_name,
                "location_z_up": list(socket.position_z_up),
                "socket_id": socket.socket_id,
                "kind": socket.kind,
                "compatible_kinds": list(socket.compatible_kinds),
                "position_contract_y_up": list(socket.position_y_up),
            }
            for socket in spec.sockets
        ],
    }


def test_missing_contract_socket_is_reported_deterministically(BASE_REPORT: dict) -> None:
    report = {**BASE_REPORT, "socket_records": BASE_REPORT["socket_records"][1:]}

    assert validate_report(load_source_spec(PROJECT_ROOT, "floor_1x1"), report) == [
        "missing socket record floor_edge_north_01: floor_1x1"
    ]


def test_non_identity_source_root_is_rejected(BASE_REPORT: dict) -> None:
    report = {**BASE_REPORT, "root_identity": False}

    assert validate_report(load_source_spec(PROJECT_ROOT, "floor_1x1"), report) == [
        "source root transform is not identity: floor_1x1"
    ]


def test_valid_report_passes_validation(BASE_REPORT: dict) -> None:
    assert validate_report(load_source_spec(PROJECT_ROOT, "floor_1x1"), BASE_REPORT) == []


def test_source_record_with_wrong_hash_is_rejected(
    BASE_REPORT: dict, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    spec = load_source_spec(PROJECT_ROOT, "floor_1x1")
    blend_path, record_path = source_output_paths(tmp_path, spec.module_id)
    blend_path.parent.mkdir(parents=True)
    blend_path.write_bytes(b"blend fixture")

    source_record = build_source_record(spec, blend_path)
    source_record["source_glb"]["sha256"] = "wrong-hash"
    record_path.write_bytes(canonical_json(source_record))

    monkeypatch.setattr(validator, "_run_inspector", lambda *args: (BASE_REPORT, None))
    args = argparse.Namespace(
        all=False,
        blender="blender",
        module=[spec.module_id],
        project_root=PROJECT_ROOT,
        source_root=tmp_path,
    )

    assert validate_sources(args) == [
        "source record source_glb.sha256 does not match contract: floor_1x1"
    ]


def test_extra_helper_is_reported(BASE_REPORT: dict) -> None:
    report = {**BASE_REPORT, "helper_names": [*BASE_REPORT["helper_names"], "ExtraHelper"]}

    assert validate_report(load_source_spec(PROJECT_ROOT, "floor_1x1"), report) == [
        "unexpected source helper ExtraHelper: floor_1x1"
    ]


def test_wrong_collision_shape_is_reported(BASE_REPORT: dict) -> None:
    report = {**BASE_REPORT, "collision": {**BASE_REPORT["collision"], "proxy_shape": "sphere"}}

    assert validate_report(load_source_spec(PROJECT_ROOT, "floor_1x1"), report) == [
        "collision proxy shape does not match contract: floor_1x1"
    ]


def test_report_errors_are_lexicographically_sorted(BASE_REPORT: dict) -> None:
    report = {
        **BASE_REPORT,
        "module_id": "wrong-module",
        "root_name": "wrong-root",
        "root_identity": False,
        "helper_names": ["Origin", "ExtraHelper"],
        "collision": {**BASE_REPORT["collision"], "proxy_shape": "sphere"},
    }

    errors = validate_report(load_source_spec(PROJECT_ROOT, "floor_1x1"), report)

    assert errors == sorted(errors)


CANDIDATE_CONTRACT_RELATIVE = Path(
    "data/placement/contracts/structural/ship_structural_v0/pressure_door_1x1_contract.json"
)
CANDIDATE_GLB_RELATIVE = Path(
    "assets/_staging/focused_nine/structural/pressure_door_1x1/pressure_door_1x1.glb"
)


def _write_candidate_project(tmp_path: Path) -> Path:
    contract_path = tmp_path / CANDIDATE_CONTRACT_RELATIVE
    contract_path.parent.mkdir(parents=True)
    contract_path.write_bytes((PROJECT_ROOT / CANDIDATE_CONTRACT_RELATIVE).read_bytes())
    glb_path = tmp_path / CANDIDATE_GLB_RELATIVE
    glb_path.parent.mkdir(parents=True)
    glb_path.write_bytes(
        (PROJECT_ROOT / "assets/imported/structural/ship_structural_v0/doorway_frame_open_1x1/doorway_frame_open_1x1.glb").read_bytes()
    )
    return glb_path


def _candidate_report(project_root: Path) -> dict[str, object]:
    spec = validator.load_candidate_source_spec(
        project_root, "pressure_door_1x1", CANDIDATE_GLB_RELATIVE
    )
    return {
        "module_id": spec.module_id,
        "root_name": "ModuleRoot_pressure_door_1x1",
        "root_identity": True,
        "helper_names": sorted(
            [
                "Origin",
                "Anchor_FloorCenter",
                "CollisionProxy",
                *(socket.anchor_name for socket in spec.sockets),
            ]
        ),
        "collision": {
            "proxy_shape": spec.collision_proxy_shape,
            "nav_blocker": spec.nav_blocker,
        },
        "socket_records": [
            {
                "name": socket.anchor_name,
                "location_z_up": list(socket.position_z_up),
                "socket_id": socket.socket_id,
                "kind": socket.kind,
                "compatible_kinds": list(socket.compatible_kinds),
                "position_contract_y_up": list(socket.position_y_up),
            }
            for socket in spec.sockets
        ],
    }


def _write_candidate_outputs(
    tmp_path: Path, *, with_blend: bool = True
) -> tuple[Path, Path, dict[str, object]]:
    _write_candidate_project(tmp_path)
    source_root = tmp_path / "recovered"
    source_dir = source_root / "pressure_door_1x1"
    source_dir.mkdir(parents=True)
    blend_path = source_dir / "pressure_door_1x1.blend"
    if with_blend:
        blend_path.write_bytes(b"blend fixture")
    spec = validator.load_candidate_source_spec(
        tmp_path, "pressure_door_1x1", CANDIDATE_GLB_RELATIVE
    )
    record_path = source_dir / "pressure_door_1x1.source.json"
    record = build_source_record(spec, blend_path)
    record_path.write_bytes(canonical_json(record))
    return source_root, record_path, record


def _candidate_cli_args(tmp_path: Path, source_root: Path) -> list[str]:
    return [
        sys.executable,
        str(SCRIPT),
        "--project-root",
        str(tmp_path),
        "--source-root",
        str(source_root),
        "--candidate-source-glb",
        "pressure_door_1x1=" + str(CANDIDATE_GLB_RELATIVE),
        "--blender",
        "missing-blender-for-source-only-validation",
    ]


def test_default_all_keeps_exactly_fifteen_live_modules(tmp_path: Path) -> None:
    args = validator.parse_args(
        ["--project-root", str(PROJECT_ROOT), "--source-root", str(tmp_path), "--all"]
    )

    assert validator._selected_module_ids(args) == (
        "floor_1x1",
        "floor_2x1",
        "corridor_floor_1x1",
        "corridor_floor_1x2",
        "wall_straight_1x1",
        "doorway_frame_open_1x1",
        "pillar_support_1x1",
        "ramp_up_1x2",
        "bulkhead_portal_2x1",
        "ceiling_cap_1x1",
        "doorway_frame_blocked_1x1",
        "wall_end_cap",
        "wall_inner_corner",
        "wall_outer_corner",
        "wall_t_junction",
    )
    assert "pressure_door_1x1" not in validator._selected_module_ids(args)


def test_candidate_cli_accepts_project_relative_assignment(tmp_path: Path) -> None:
    args = validator.parse_args(
        [
            "--project-root",
            str(PROJECT_ROOT),
            "--source-root",
            str(tmp_path),
            "--candidate-source-glb",
            "pressure_door_1x1=" + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    assert args.candidate_source_glb == [
        "pressure_door_1x1=" + str(CANDIDATE_GLB_RELATIVE)
    ]
    assert validator._selected_module_ids(args) == ("pressure_door_1x1",)


@pytest.mark.parametrize(
    "assignment,expected_error",
    [
        ("pressure_door_1x1", "module_id=relative/path.glb"),
        ("pressure_door_1x1=assets/a.glb=extra", "module_id=relative/path.glb"),
        ("pressure_door_1x1=assets/a/../pressure_door_1x1.glb", "must not contain traversal"),
    ],
)
def test_candidate_cli_rejects_malformed_or_traversal_assignment(
    tmp_path: Path,
    assignment: str,
    expected_error: str,
    capsys: pytest.CaptureFixture[str],
) -> None:
    with pytest.raises(SystemExit) as raised:
        validator.parse_args(
            [
                "--project-root",
                str(PROJECT_ROOT),
                "--source-root",
                str(tmp_path),
                "--candidate-source-glb",
                assignment,
            ]
        )

    assert raised.value.code == 2
    assert expected_error in capsys.readouterr().err


def test_candidate_cli_rejects_duplicate_module_assignment(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    assignment = "pressure_door_1x1=" + str(CANDIDATE_GLB_RELATIVE)

    with pytest.raises(SystemExit) as raised:
        validator.parse_args(
            [
                "--project-root",
                str(PROJECT_ROOT),
                "--source-root",
                str(tmp_path),
                "--candidate-source-glb",
                assignment,
                "--candidate-source-glb",
                assignment,
            ]
        )

    assert raised.value.code == 2
    assert "duplicate candidate module assignment" in capsys.readouterr().err


def test_candidate_source_record_and_report_validate_without_live_selection(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _write_candidate_project(tmp_path)
    source_root = tmp_path / "recovered"
    source_dir = source_root / "pressure_door_1x1"
    source_dir.mkdir(parents=True)
    blend_path = source_dir / "pressure_door_1x1.blend"
    blend_path.write_bytes(b"blend fixture")
    spec = validator.load_candidate_source_spec(
        tmp_path, "pressure_door_1x1", CANDIDATE_GLB_RELATIVE
    )
    (source_dir / "pressure_door_1x1.source.json").write_bytes(
        canonical_json(build_source_record(spec, blend_path))
    )
    monkeypatch.setattr(
        validator, "_run_inspector", lambda *args: (_candidate_report(tmp_path), None)
    )
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb",
            "pressure_door_1x1=" + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    assert validate_sources(args) == []


def test_candidate_source_record_hash_mismatch_is_rejected(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _write_candidate_project(tmp_path)
    source_root = tmp_path / "recovered"
    source_dir = source_root / "pressure_door_1x1"
    source_dir.mkdir(parents=True)
    blend_path = source_dir / "pressure_door_1x1.blend"
    blend_path.write_bytes(b"blend fixture")
    spec = validator.load_candidate_source_spec(
        tmp_path, "pressure_door_1x1", CANDIDATE_GLB_RELATIVE
    )
    source_record = build_source_record(spec, blend_path)
    source_record["source_glb"]["sha256"] = "wrong-hash"
    (source_dir / "pressure_door_1x1.source.json").write_bytes(
        canonical_json(source_record)
    )
    monkeypatch.setattr(
        validator, "_run_inspector", lambda *args: (_candidate_report(tmp_path), None)
    )
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb",
            "pressure_door_1x1=" + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    assert validate_sources(args) == [
        "source record source_glb.sha256 does not match contract: pressure_door_1x1"
    ]


def test_candidate_requires_a_real_expected_blend_before_sidecar_passes(
    tmp_path: Path,
) -> None:
    source_root, record_path, _record = _write_candidate_outputs(
        tmp_path, with_blend=False
    )
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb",
            "pressure_door_1x1=" + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    expected_blend = record_path.parent / "pressure_door_1x1.blend"
    assert validate_sources(args) == [f"missing candidate Blender source: {expected_blend}"]


@pytest.mark.parametrize(
    "field, value, expected",
    [
        (
            "kit_id",
            "wrong-kit",
            "source record kit_id does not match contract: pressure_door_1x1",
        ),
        (
            "coordinate_conversion",
            "wrong-conversion",
            "source record coordinate_conversion does not match contract: pressure_door_1x1",
        ),
        (
            "placement_origin",
            "wrong-origin",
            "source record placement_origin does not match contract: pressure_door_1x1",
        ),
        (
            "blend_path",
            "/outside/pressure_door_1x1.blend",
            "source record blend_path does not match expected source: pressure_door_1x1",
        ),
    ],
)
def test_candidate_validates_source_record_identity_and_placement_fields(
    tmp_path: Path, field: str, value: object, expected: str
) -> None:
    source_root, record_path, record = _write_candidate_outputs(tmp_path)
    record[field] = value
    record_path.write_bytes(canonical_json(record))
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb",
            "pressure_door_1x1=" + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    assert validate_sources(args) == [expected]


def test_candidate_validates_complete_socket_identity_and_metadata(
    tmp_path: Path,
) -> None:
    source_root, record_path, record = _write_candidate_outputs(tmp_path)
    sockets = record["sockets"]
    assert isinstance(sockets, list)
    sockets[0]["kind"] = "wrong-kind"
    record_path.write_bytes(canonical_json(record))
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb="
            + "pressure_door_1x1="
            + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    errors = validate_sources(args)

    assert len(errors) == 1
    assert "source record socket metadata does not match" in errors[0]


def test_candidate_rejects_symlinked_blend_leaf(tmp_path: Path) -> None:
    source_root, _record_path, _record = _write_candidate_outputs(tmp_path)
    blend_path = source_root / "pressure_door_1x1" / "pressure_door_1x1.blend"
    external_blend = tmp_path / "outside.blend"
    external_blend.write_bytes(blend_path.read_bytes())
    blend_path.unlink()
    try:
        blend_path.symlink_to(external_blend)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb="
            + "pressure_door_1x1="
            + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    errors = validate_sources(args)

    assert errors == [
        f"candidate Blender source must be a regular non-symlink file: {blend_path}"
    ]


def test_candidate_rejects_symlinked_source_record_leaf(
    tmp_path: Path,
) -> None:
    source_root, record_path, record = _write_candidate_outputs(tmp_path)
    external_record = tmp_path / "outside.source.json"
    external_record.write_bytes(canonical_json(record))
    record_path.unlink()
    try:
        record_path.symlink_to(external_record)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb="
            + "pressure_door_1x1="
            + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    errors = validate_sources(args)

    assert len(errors) == 1
    assert "candidate source record must be a regular non-symlink file" in errors[0]


def test_candidate_source_record_symlink_loop_is_a_deterministic_error(
    tmp_path: Path,
) -> None:
    source_root, record_path, _record = _write_candidate_outputs(tmp_path)
    record_path.unlink()
    try:
        record_path.symlink_to(record_path.name)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb="
            + "pressure_door_1x1="
            + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    errors = validate_sources(args)

    assert len(errors) == 1
    assert "candidate source record must be a regular non-symlink file" in errors[0]


def test_candidate_source_module_symlink_loop_is_a_deterministic_validation_error(
    tmp_path: Path,
) -> None:
    _write_candidate_project(tmp_path)
    source_root = tmp_path / "recovered"
    source_root.mkdir()
    module_root = source_root / "pressure_door_1x1"
    try:
        module_root.symlink_to(module_root.name, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")
    args = validator.parse_args(
        [
            "--project-root",
            str(tmp_path),
            "--source-root",
            str(source_root),
            "--candidate-source-glb="
            + "pressure_door_1x1="
            + str(CANDIDATE_GLB_RELATIVE),
        ]
    )

    errors = validate_sources(args)

    assert len(errors) == 1
    assert "cannot resolve candidate source output path" in errors[0]


def test_candidate_cli_happy_path_emits_pass_without_running_blender(
    tmp_path: Path,
) -> None:
    source_root, _record_path, _record = _write_candidate_outputs(tmp_path)

    result = subprocess.run(
        _candidate_cli_args(tmp_path, source_root),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0
    assert result.stdout == "STRUCTURAL_SOURCE_VALIDATION PASS modules=1\n"
    assert result.stderr == ""


def test_candidate_cli_rejects_symlinked_record_without_traceback(
    tmp_path: Path,
) -> None:
    source_root, record_path, record = _write_candidate_outputs(tmp_path)
    external_record = tmp_path / "outside.source.json"
    external_record.write_bytes(canonical_json(record))
    record_path.unlink()
    try:
        record_path.symlink_to(external_record)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")

    result = subprocess.run(
        _candidate_cli_args(tmp_path, source_root),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "candidate source record must be a regular non-symlink file" in result.stderr
    assert "Traceback" not in result.stderr


def test_candidate_cli_rejects_source_module_loop_without_traceback(
    tmp_path: Path,
) -> None:
    _write_candidate_project(tmp_path)
    source_root = tmp_path / "recovered"
    source_root.mkdir()
    module_root = source_root / "pressure_door_1x1"
    try:
        module_root.symlink_to(module_root.name, target_is_directory=True)
    except OSError as exc:
        pytest.skip(f"symlinks unavailable: {exc}")

    result = subprocess.run(
        _candidate_cli_args(tmp_path, source_root),
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 1
    assert "cannot resolve candidate source output path" in result.stderr
    assert "Traceback" not in result.stderr
