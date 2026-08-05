from __future__ import annotations

from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _read(relative_path: str) -> str:
    return (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")


def test_edge_key_is_identical_from_both_adjacent_cells():
    source = _read("scripts/procgen/structural_edge_plan.gd")
    assert "static func edge_key(deck: int, cell: Vector2i, direction: String) -> String:" in source
    assert '"north": "south"' in source
    assert '"south": "north"' in source


def test_direction_pose_table_matches_wrapper_axis_contract():
    source = _read("scripts/procgen/structural_edge_plan.gd")
    assert '"south": 0.0' in source
    assert '"west": 90.0' in source
    assert '"north": 180.0' in source
    assert '"east": 270.0' in source
