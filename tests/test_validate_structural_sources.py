from __future__ import annotations

import argparse
from pathlib import Path

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
