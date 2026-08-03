from __future__ import annotations

from pathlib import Path

import pytest

from tools.structural_source_contract import load_source_spec
from tools.validate_structural_sources import validate_report


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
