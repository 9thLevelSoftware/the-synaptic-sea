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
