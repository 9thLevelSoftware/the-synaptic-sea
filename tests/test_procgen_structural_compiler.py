from __future__ import annotations

import re
import shutil
import subprocess
import textwrap
from pathlib import Path

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _read(relative_path: str) -> str:
    return (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")


def _run_godot_probe(tmp_path: Path, body: str) -> subprocess.CompletedProcess[str]:
    godot = shutil.which("godot") or "/opt/homebrew/bin/godot"
    if not Path(godot).exists():
        pytest.skip("Godot is required for behavioral compiler probes")

    probe = tmp_path / "structural_edge_compiler_probe.gd"
    script = textwrap.dedent(
        """
        extends SceneTree

        const Compiler = preload("res://scripts/procgen/structural_edge_compiler.gd")
        var failed := false


        func _fail(message: String) -> void:
            failed = true
            print("PROCGEN COMPILER FAIL: " + message)


        func _init() -> void:
        """
    )
    script += textwrap.indent(textwrap.dedent(body).strip(), "    ")
    script += '\n    if failed:\n        quit(1)\n        return\n    print("PROCGEN COMPILER PROBE PASS")\n    quit(0)\n'
    probe.write_text(script, encoding="utf-8")
    command = [godot, "--headless", "--path", str(PROJECT_ROOT), "--script", str(probe)]
    try:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode(errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode(errors="replace")
        pytest.fail(
            "Godot compiler probe timed out after 60 seconds.\n"
            "command: %s\n"
            "stdout:\n%s\n"
            "stderr:\n%s" % (" ".join(command), stdout, stderr)
        )
        raise AssertionError("Godot compiler probe timed out")


def _assert_probe_passed(result: subprocess.CompletedProcess[str]) -> None:
    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    diagnostics = [
        marker for marker in ("ERROR:", "WARNING:", "SCRIPT ERROR:") if marker in output
    ]
    assert not diagnostics, "Godot probe emitted diagnostics %s:\n%s" % (
        diagnostics,
        output,
    )
    assert result.returncode == 0, output
    assert "PROCGEN COMPILER PROBE PASS" in output


@pytest.mark.parametrize("diagnostic", ("ERROR:", "WARNING:", "SCRIPT ERROR:"))
def test_assert_probe_passed_rejects_godot_diagnostics(diagnostic: str):
    result = subprocess.CompletedProcess(
        args=["godot"],
        returncode=0,
        stdout="PROCGEN COMPILER PROBE PASS\n%s simulated diagnostic" % diagnostic,
        stderr="",
    )
    with pytest.raises(AssertionError):
        _assert_probe_passed(result)


def test_run_godot_probe_times_out_with_partial_output_context(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    fake_godot = tmp_path / "godot"
    fake_godot.write_text("", encoding="utf-8")
    monkeypatch.setattr(shutil, "which", lambda _name: str(fake_godot))
    captured: dict[str, object] = {}

    def fake_run(command: list[str], **kwargs: object) -> None:
        captured.update(kwargs)
        raise subprocess.TimeoutExpired(
            cmd=command,
            timeout=60,
            output="partial stdout",
            stderr="partial stderr",
        )

    monkeypatch.setattr(subprocess, "run", fake_run)
    with pytest.raises(
        pytest.fail.Exception, match="timed out after 60 seconds"
    ) as failure:
        _run_godot_probe(tmp_path, '_fail("probe body")')

    assert captured["timeout"] == 60
    assert "partial stdout" in str(failure.value)
    assert "partial stderr" in str(failure.value)


def test_edge_key_is_identical_from_both_adjacent_cells():
    source = _read("scripts/procgen/structural_edge_plan.gd")
    assert (
        "static func edge_key(deck: int, cell: Vector2i, direction: String) -> String:"
        in source
    )
    assert '"north": "south"' in source
    assert '"south": "north"' in source


def test_direction_pose_table_matches_wrapper_axis_contract():
    source = _read("scripts/procgen/structural_edge_plan.gd")
    assert '"south": 0.0' in source
    assert '"west": 90.0' in source
    assert '"north": 180.0' in source
    assert '"east": 270.0' in source


def test_compiler_has_single_edge_authority_and_no_floor_driven_walls():
    source = _read("scripts/procgen/structural_edge_compiler.gd")
    assert "func compile(layout: Dictionary) -> Dictionary:" in source
    assert re.search(
        r"^[ \t]*(?!#).*StructuralEdgePlanScript\.edge_key\(",
        source,
        re.MULTILINE,
    )
    assert "emitted_edge_keys" in source
    assert "wall_straight_1x1" in source


def test_compiler_declares_wall_portal_open_and_breach_edge_states():
    source = _read("scripts/procgen/structural_edge_compiler.gd")
    for state in ('"SOLID"', '"OPEN"', '"DOOR"', '"LOCKED"', '"HATCH"', '"BREACH"'):
        assert state in source


def test_compiler_emits_one_door_for_adjacent_rooms_and_no_internal_wall(
    tmp_path: Path,
):
    result = _run_godot_probe(
        tmp_path,
        """
        var compiler := Compiler.new()
        var shared_key := "0|v|0|0"
        var door_plan: Dictionary = compiler.compile({
            "rooms": [
                {"id": "A", "deck": 0, "cells": [[0, 0]]},
                {"id": "B", "deck": 0, "cells": [[1, 0]]},
            ],
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "door",
                "edge_key": shared_key,
            }],
        })
        var door_edges: Dictionary = door_plan["edges"]
        if not door_edges.has(shared_key):
            _fail("adjacent room edge was not compiled")
        var shared_edge: Dictionary = door_edges[shared_key]
        if String(shared_edge["kind"]) != "DOOR":
            _fail("shared edge did not retain DOOR state")

        var shared_placements := 0
        for placement_variant in door_plan["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement["edge_key"]) != shared_key:
                continue
            shared_placements += 1
            if String(placement["kind"]) != "DOOR":
                _fail("shared edge received a second non-door placement")
            if not (placement["position"] as Vector3).is_equal_approx(Vector3(2.0, 0.0, 0.0)):
                _fail("east portal position drifted from the canonical edge")
            if not is_equal_approx(float(placement["yaw_degrees"]), 270.0):
                _fail("east portal yaw drifted from the canonical pose table")
        if shared_placements != 1:
            _fail("shared edge emitted %d placements instead of one" % shared_placements)

        var same_room_plan: Dictionary = compiler.compile({
            "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0], [1, 0]]}],
            "portals": [],
        })
        var internal_key := shared_key
        var internal_edge: Dictionary = same_room_plan["edges"][internal_key]
        if String(internal_edge["kind"]) != "OPEN":
            _fail("same-room boundary was compiled as a physical wall")
        for placement_variant in same_room_plan["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement["edge_key"]) == internal_key:
                _fail("same-room boundary received a physical placement")
        if not same_room_plan["errors"].is_empty():
            _fail("valid adjacent footprint produced compiler errors")
        """,
    )
    _assert_probe_passed(result)


def test_compiler_emits_one_locked_portal_with_blocked_wrapper_module(tmp_path: Path):
    result = _run_godot_probe(
        tmp_path,
        """
        var compiler := Compiler.new()
        var locked_key := "0|v|0|0"
        var plan: Dictionary = compiler.compile({
            "rooms": [
                {"id": "A", "deck": 0, "cells": [[0, 0]]},
                {"id": "B", "deck": 0, "cells": [[1, 0]]},
            ],
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "locked",
                "edge_key": locked_key,
            }],
        })
        if not plan["errors"].is_empty():
            _fail("explicit LOCKED portal produced compiler errors")
        var locked_edge: Dictionary = plan["edges"][locked_key]
        if String(locked_edge["kind"]) != "LOCKED":
            _fail("explicit LOCKED portal did not retain LOCKED state")
        if String(locked_edge["module_id"]) != "doorway_frame_blocked_1x1":
            _fail("LOCKED portal selected an invalid wrapper module")
        if not bool(locked_edge.get("placement_required", false)):
            _fail("LOCKED portal did not require a wrapper placement")
        if not bool(locked_edge.get("wrapper_required", false)):
            _fail("LOCKED portal did not require a wrapper")

        var locked_placements := 0
        for placement_variant in plan["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement["edge_key"]) != locked_key:
                continue
            locked_placements += 1
            if String(placement["kind"]) != "LOCKED":
                _fail("LOCKED edge received a non-LOCKED placement")
            if String(placement["module_id"]) != "doorway_frame_blocked_1x1":
                _fail("LOCKED placement lost its blocked wrapper module")
        if locked_placements != 1:
            _fail("LOCKED edge emitted %d placements instead of one" % locked_placements)
        """,
    )
    _assert_probe_passed(result)


def test_compiler_rejects_non_integer_grid_coordinates_and_decks(tmp_path: Path):
    result = _run_godot_probe(
        tmp_path,
        """
        var compiler := Compiler.new()
        var invalid_cases: Array = [
            {
                "label": "fractional array coordinate",
                "layout": {"rooms": [{"id": "fractional-array", "deck": 0, "cells": [[0.5, 0]]}]},
            },
            {
                "label": "fractional dictionary coordinate",
                "layout": {"rooms": [{"id": "fractional-dictionary", "deck": 0, "cells": [{"x": 0, "y": 1.0}]}]},
            },
            {
                "label": "Vector2 coordinate",
                "layout": {"rooms": [{"id": "vector2", "deck": 0, "cells": [Vector2(0.0, 0.0)]}]},
            },
            {
                "label": "short array coordinate",
                "layout": {"rooms": [{"id": "short-array", "deck": 0, "cells": [[0]]}]},
            },
            {
                "label": "fractional deck",
                "layout": {"rooms": [{"id": "fractional-deck", "deck": 1.5, "cells": [[0, 0]]}]},
            },
        ]
        for test_case_variant in invalid_cases:
            var test_case: Dictionary = test_case_variant
            var plan: Dictionary = compiler.compile(test_case["layout"])
            if not plan["occupancy"].is_empty():
                _fail("%s was coerced into occupied grid cells" % test_case["label"])
            if plan["errors"].is_empty():
                _fail("%s was accepted without a validation error" % test_case["label"])

        var valid_plan: Dictionary = compiler.compile({
            "rooms": [{"id": "valid", "deck": 2, "cells": [Vector2i(-3, 4), [5, -6]]}],
            "portals": [],
        })
        if valid_plan["occupancy"].size() != 2 or not valid_plan["errors"].is_empty():
            _fail("strict validation rejected valid integer-grid coordinates")
        """,
    )
    _assert_probe_passed(result)


def test_compiler_rejects_malformed_explicit_portal_geometry(tmp_path: Path):
    result = _run_godot_probe(
        tmp_path,
        """
        var compiler := Compiler.new()
        var shared_key := "0|v|0|0"
        var plan: Dictionary = compiler.compile({
            "rooms": [
                {"id": "A", "deck": 0, "cells": [[0, 0]]},
                {"id": "B", "deck": 0, "cells": [[1, 0]]},
            ],
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "door",
                "edge_key": {"cell": [0, 0], "direction": "diagonal"},
            }],
        })
        if plan["errors"].is_empty():
            _fail("malformed explicit portal geometry was accepted")
        var shared_edge: Dictionary = plan["edges"][shared_key]
        if String(shared_edge["kind"]) != "SOLID":
            _fail("malformed explicit portal geometry became an unconstrained portal")
        for placement_variant in plan["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement["edge_key"]) == shared_key and String(placement["kind"]) != "SOLID":
                _fail("malformed explicit portal geometry emitted a portal placement")
        """,
    )
    _assert_probe_passed(result)


def test_compiler_rejects_missing_portal_endpoint_except_exterior_breach_or_hatch(
    tmp_path: Path,
):
    result = _run_godot_probe(
        tmp_path,
        """
        var compiler := Compiler.new()
        var shared_key := "0|v|0|0"
        var invalid_endpoint_cases: Array = [
            {
                "label": "door missing destination",
                "portal": {"from_room": "A", "type": "door", "edge_key": shared_key},
            },
            {
                "label": "door missing source",
                "portal": {"from_room": "", "to_room": "B", "type": "door", "edge_key": shared_key},
            },
            {
                "label": "open missing destination",
                "portal": {"from_room": "A", "to_room": "", "type": "open", "edge_key": shared_key},
            },
        ]
        for test_case_variant in invalid_endpoint_cases:
            var test_case: Dictionary = test_case_variant
            var plan: Dictionary = compiler.compile({
                "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
                "portals": [test_case["portal"]],
            })
            if plan["errors"].is_empty():
                _fail("%s was accepted without a missing-endpoint error" % test_case["label"])
            var shared_edge: Dictionary = plan["edges"][shared_key]
            if String(shared_edge["kind"]) != "SOLID":
                _fail("%s was promoted to a portal state" % test_case["label"])

        for exterior_kind in ["breach", "hatch"]:
            var exterior_portal: Dictionary = {
                "from_room": "A",
                "type": exterior_kind,
                "edge_key": shared_key,
            }
            var exterior_plan: Dictionary = compiler.compile({
                "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
                "portals": [exterior_portal],
            })
            if not exterior_plan["errors"].is_empty():
                _fail("explicit exterior %s was rejected" % exterior_kind)
            var exterior_edge: Dictionary = exterior_plan["edges"][shared_key]
            if String(exterior_edge["kind"]).to_lower() != exterior_kind:
                _fail("explicit exterior %s lost its portal state" % exterior_kind)
            if not bool(exterior_edge.get("exterior", false)):
                _fail("explicit exterior %s was not marked exterior" % exterior_kind)
        """,
    )
    _assert_probe_passed(result)


def test_compiler_treats_breach_as_non_wrapper_exterior_state(tmp_path: Path):
    result = _run_godot_probe(
        tmp_path,
        """
        var compiler := Compiler.new()
        var breach_key := "0|v|0|0"
        var plan: Dictionary = compiler.compile({
            "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
            "portals": [{
                "from_room": "A",
                "to_room": "",
                "type": "breach",
                "edge_key": breach_key,
            }],
        })
        if not plan["errors"].is_empty():
            _fail("valid exterior breach produced compiler errors")
        var breach_edge: Dictionary = plan["edges"][breach_key]
        if String(breach_edge["kind"]) != "BREACH":
            _fail("exterior breach did not retain BREACH state")
        if String(breach_edge["module_id"]) != "":
            _fail("BREACH unexpectedly selected a wrapper module")
        if not bool(breach_edge.get("exterior", false)):
            _fail("BREACH edge was not marked exterior")
        if bool(breach_edge.get("placement_required", true)):
            _fail("BREACH edge still requires a wrapper placement")
        for placement_variant in plan["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement["edge_key"]) == breach_key:
                _fail("BREACH emitted a wrapper placement")
        """,
    )
    _assert_probe_passed(result)
