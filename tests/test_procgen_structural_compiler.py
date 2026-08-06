from __future__ import annotations

import json
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


def _run_validator_probe(tmp_path: Path, body: str) -> subprocess.CompletedProcess[str]:
    godot = shutil.which("godot") or "/opt/homebrew/bin/godot"
    if not Path(godot).exists():
        pytest.skip("Godot is required for behavioral validator probes")

    probe = tmp_path / "structural_plan_validator_probe.gd"
    script = textwrap.dedent(
        """
        extends SceneTree

        const Compiler = preload("res://scripts/procgen/structural_edge_compiler.gd")
        const Validator = preload("res://scripts/procgen/structural_plan_validator.gd")
        var failed := false


        func _fail(message: String) -> void:
            failed = true
            print("PROCGEN VALIDATOR FAIL: " + message)


        func _init() -> void:
        """
    )
    script += textwrap.indent(textwrap.dedent(body).strip(), "    ")
    script += '\n    if failed:\n        quit(1)\n        return\n    print("PROCGEN VALIDATOR PROBE PASS")\n    quit(0)\n'
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
            "Godot validator probe timed out after 60 seconds.\n"
            "command: %s\n"
            "stdout:\n%s\n"
            "stderr:\n%s" % (" ".join(command), stdout, stderr)
        )
        raise AssertionError("Godot validator probe timed out")


def _assert_validator_probe_failed(
    result: subprocess.CompletedProcess[str], expected: str
) -> None:
    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    diagnostics = [
        marker for marker in ("ERROR:", "WARNING:", "SCRIPT ERROR:") if marker in output
    ]
    assert not diagnostics, "Godot validator probe emitted diagnostics %s:\n%s" % (
        diagnostics,
        output,
    )
    assert result.returncode != 0, output
    assert expected in output, output


def _assert_validator_probe_passed(result: subprocess.CompletedProcess[str]) -> None:
    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    diagnostics = [
        marker for marker in ("ERROR:", "WARNING:", "SCRIPT ERROR:") if marker in output
    ]
    assert not diagnostics, "Godot validator probe emitted diagnostics %s:\n%s" % (
        diagnostics,
        output,
    )
    assert result.returncode == 0, output
    assert "PROCGEN VALIDATOR PROBE PASS" in output


def _run_layout_probe(tmp_path: Path, body: str) -> subprocess.CompletedProcess[str]:
    godot = shutil.which("godot") or "/opt/homebrew/bin/godot"
    if not Path(godot).exists():
        pytest.skip("Godot is required for explicit layout probes")

    probe = tmp_path / "explicit_layout_probe.gd"
    script = textwrap.dedent(
        """
        extends SceneTree

        const Blueprint = preload("res://scripts/procgen/ship_blueprint.gd")
        const LayoutGenerator = preload("res://scripts/procgen/ship_layout_generator.gd")
        const Compiler = preload("res://scripts/procgen/structural_edge_compiler.gd")
        const Validator = preload("res://scripts/procgen/structural_plan_validator.gd")
        var failed := false


        func _fail(message: String) -> void:
            failed = true
            print("PROCGEN LAYOUT FAIL: " + message)


        func _init() -> void:
        """
    )
    script += textwrap.indent(textwrap.dedent(body).strip(), "    ")
    script += '\n    if failed:\n        quit(1)\n        return\n    print("PROCGEN LAYOUT PROBE PASS")\n    quit(0)\n'
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
            "Godot explicit layout probe timed out after 60 seconds.\n"
            "command: %s\n"
            "stdout:\n%s\n"
            "stderr:\n%s" % (" ".join(command), stdout, stderr)
        )
        raise AssertionError("Godot explicit layout probe timed out")


def _assert_layout_probe_passed(result: subprocess.CompletedProcess[str]) -> None:
    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    diagnostics = [
        marker for marker in ("ERROR:", "WARNING:", "SCRIPT ERROR:") if marker in output
    ]
    assert not diagnostics, "Godot layout probe emitted diagnostics %s:\n%s" % (
        diagnostics,
        output,
    )
    assert result.returncode == 0, output
    assert "PROCGEN LAYOUT PROBE PASS" in output


def _validator_case_body(label: str, plan_expression: str, expected: str) -> str:
    return f"""
    var case_plan: Dictionary = {plan_expression}
    var verdict: Dictionary = Validator.new().validate(case_plan, topology)
    var errors: Array = verdict.get("errors", [])
    if bool(verdict.get("ok", false)):
        print("VALIDATOR ACCEPTED INVALID CASE {label}")
        quit(0)
        return
    print("VALIDATOR EXPECTED FAIL {label}: " + JSON.stringify(errors))
    if not JSON.stringify(errors).contains("{expected}"):
        print("VALIDATOR WRONG ERROR {label}: " + JSON.stringify(errors))
        quit(0)
        return
    quit(1)
    return
    """


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


def test_layout_generator_emits_explicit_cells_and_portal_intents():
    source = _read("scripts/procgen/ship_layout_generator.gd")
    assert '"cells"' in source
    assert '"footprint"' in source
    assert '"portals"' in source
    assert "edge_key" in source


def test_ship_generator_validates_structural_plan_before_loader():
    source = _read("scripts/procgen/ship_generator.gd")
    assert "StructuralEdgeCompilerScript" in source
    assert "StructuralPlanValidatorScript" in source
    assert "structural plan validation failed" in source
    compile_index = source.index("StructuralEdgeCompilerScript.new")
    loader_index = source.index('preload("res://scripts/procgen/generated_ship_loader.gd")')
    assert compile_index < loader_index
    assert 'layout["structural_plan"] = structural_plan' in source


def test_loader_uses_compiler_placements_not_role_module_lists():
    source = _read("scripts/procgen/generated_ship_loader.gd")
    assert '"structural_plan"' in source
    assert '"placements"' in source
    for metadata_key in (
        "structural_edge_key",
        "structural_kind",
        "structural_placement_id",
        "structural_room_ids",
    ):
        assert metadata_key in source

    start = source.index("func _instance_structural_wrappers(")
    end = source.index("func _parse_prefixed_int(", start)
    instance_body = source[start:end]
    assert "structural_placements" not in instance_body
    assert "_read_placement_position" not in instance_body
    assert 'record.get("position"' in instance_body
    assert 'record.get("yaw_degrees"' in instance_body


def test_loader_fails_closed_when_compiled_plan_is_missing_or_invalid():
    source = _read("scripts/procgen/generated_ship_loader.gd")
    assert "layout missing validated structural_plan" in source
    assert "compiled placement references unavailable wrapper" in source


def test_loader_invokes_full_validator_before_wrapper_resource_lookup_and_preflights_all_records():
    source = _read("scripts/procgen/generated_ship_loader.gd")
    assert 'preload("res://scripts/procgen/structural_plan_validator.gd")' in source
    assert ".validate(structural_plan, layout)" in source
    validator_index = source.index("_validate_structural_plan_for_loading")
    module_lookup_index = source.index("_build_module_scene_map")
    assert validator_index < module_lookup_index
    assert "func _preflight_structural_wrappers(" in source
    preflight_start = source.index("func _preflight_structural_wrappers(")
    instance_start = source.index("func _instance_structural_wrappers(")
    preflight_body = source[preflight_start:instance_start]
    assert "record_variant is Dictionary" in preflight_body
    assert "placement_id" in preflight_body
    assert "room_ids" in preflight_body
    assert "PackedScene" in preflight_body
    assert "instantiate()" not in preflight_body
    assert "_preflight_structural_wrappers" in source[instance_start:]


def test_loader_playable_smoke_asserts_canonical_wrapper_tree_contract():
    source = _read("scripts/validation/procgen_loader_playable_contract_smoke.gd")
    assert "PROCGEN_STRUCTURAL_LOADER_PASS" in source
    assert "structural_placement_id" in source
    assert "structural_edge_key" in source
    assert "north" in source
    assert "z=-2" in source
    assert "_run_loader_preflight_regressions" in source
    assert "malformed-edge-position" in source
    assert "malformed-yaw" in source
    assert "mixed module" in source


def test_compiler_emits_floor_placements_from_canonical_occupancy():
    source = _read("scripts/procgen/structural_edge_compiler.gd")
    assert '"floor_placements"' in source
    assert "FLOOR_KIND" in source
    assert "floor_module_id" in source
    assert "floor_placements.append" in source


def test_task5_layout_fixtures_embed_migrated_structural_plans():
    fixture_paths = (
        "data/procgen/smoke/seed_000017/layout.json",
        "data/procgen/golden/coherent_ship_001/layout.json",
        "data/procgen/golden/coherent_ship_002/layout.json",
        "data/procgen/golden/coherent_ship_003/layout.json",
    )
    for relative_path in fixture_paths:
        document = json.loads(_read(relative_path))
        assert all("cells" in room for room in document["rooms"]), relative_path
        assert document.get("portals"), relative_path
        structural_plan = document.get("structural_plan")
        assert isinstance(structural_plan, dict), relative_path
        assert structural_plan.get("validated") is True, relative_path
        assert not structural_plan.get("errors"), relative_path
        occupancy = structural_plan.get("occupancy")
        floor_placements = structural_plan.get("floor_placements")
        assert isinstance(occupancy, dict) and occupancy, relative_path
        assert isinstance(floor_placements, list), relative_path
        assert len(floor_placements) == len(occupancy), relative_path


def test_layout_stress_smoke_has_seed_17_footprint_ownership_evidence():
    source = _read("scripts/validation/procgen_layout_stress_smoke.gd")
    assert "seed_val == 17" in source or "seed_val = 17" in source
    assert "ownership" in source
    assert "room_cell_coordinates" in source
    assert "floor_coordinates" in source
    assert "adjacency_intents" in source
    assert "structural_portal_placement_counts" in source
    assert "does not map to exactly one portal record" in source
    assert "does not map to exactly one portal edge placement" in source
    assert "structural_room_links" in source  # named in the guard comment as the dedup view
    assert "cells" in source
    assert "portal" in source


def test_generated_seed_17_emits_valid_explicit_footprints_and_portals(tmp_path: Path):
    result = _run_layout_probe(
        tmp_path,
        """
        var generator := LayoutGenerator.new()
        var blueprint := Blueprint.new(Blueprint.Size.MEDIUM, Blueprint.Condition.PRISTINE, 17)
        var layout: Dictionary = generator.generate(blueprint, {"template": "spine"})
        if layout.is_empty():
            _fail("seed 17 produced an empty layout")
        var ownership: Dictionary = {}
        for room_variant in layout.get("rooms", []):
            if not (room_variant is Dictionary):
                _fail("layout contains a non-Dictionary room")
                continue
            var room: Dictionary = room_variant
            var cells: Variant = room.get("cells", null)
            if not (cells is Array) or (cells as Array).is_empty():
                _fail("room %s has no explicit cells" % String(room.get("id", "?")))
                continue
            if not room.has("footprint"):
                _fail("room %s has no explicit footprint" % String(room.get("id", "?")))
            for cell_variant in cells:
                if not (cell_variant is Vector2i):
                    _fail("room %s emitted a non-Vector2i cell" % String(room.get("id", "?")))
                    continue
                var cell: Vector2i = cell_variant
                var key := "%d|%d|%d" % [int(room.get("deck", 0)), cell.x, cell.y]
                if ownership.has(key):
                    _fail("cell ownership collision at %s" % key)
                ownership[key] = String(room.get("id", ""))

        var structural_plan: Dictionary = Compiler.new().compile(layout)
        if not (structural_plan.get("errors", []) as Array).is_empty():
            _fail("compiler rejected generated layout: " + JSON.stringify(structural_plan["errors"]))
        var verdict: Dictionary = Validator.new().validate(structural_plan, layout)
        if not bool(verdict.get("ok", false)):
            _fail("validator rejected generated layout: " + JSON.stringify(verdict["errors"]))
        var floor_placements: Array = structural_plan.get("floor_placements", [])
        if floor_placements.size() != ownership.size():
            _fail("compiler floor placement count=%d does not match occupancy=%d" % [floor_placements.size(), ownership.size()])
        for floor_variant in floor_placements:
            if not (floor_variant is Dictionary) or String((floor_variant as Dictionary).get("kind", "")) != "FLOOR":
                _fail("compiler emitted a malformed floor placement: " + JSON.stringify(floor_variant))
                break
        var portal_count := 0
        for portal_variant in layout.get("portals", []):
            var portal: Dictionary = portal_variant
            var edge_key := String(portal.get("edge_key", ""))
            var matched := 0
            for edge_variant in structural_plan.get("edges", {}).values():
                var edge: Dictionary = edge_variant
                if String(edge.get("edge_key", "")) == edge_key and String(edge.get("kind", "")) != "SOLID":
                    matched += 1
            if matched != 1:
                _fail("portal %s matched %d non-solid edges" % [edge_key, matched])
            portal_count += 1
        if portal_count == 0:
            _fail("seed 17 emitted no explicit portal intents")
        """,
    )
    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    assert result.returncode == 0, output
    assert not any(marker in output for marker in ("ERROR:", "WARNING:", "SCRIPT ERROR:")), output
    assert "PROCGEN LAYOUT PROBE PASS" in output


def test_layout_generator_rejects_stale_portal_cells_and_coordinate_mismatch(tmp_path: Path):
    result = _run_layout_probe(
        tmp_path,
        """
        var generator := LayoutGenerator.new()
        var placed_rooms: Dictionary = {
            "A": {"deck": 0, "cells": [Vector2i(0, 0)]},
            "B": {"deck": 0, "cells": [Vector2i(1, 0)]},
        }
        var cases: Array = [
            {
                "label": "stale-source",
                "adjacency": {"from_room": "A", "to_room": "B", "from_cell": Vector2i(99, 99), "to_cell": Vector2i(1, 0)},
            },
            {
                "label": "stale-target",
                "adjacency": {"from_room": "A", "to_room": "B", "from_cell": Vector2i(0, 0), "to_cell": Vector2i(99, 99)},
            },
            {
                "label": "non-cardinal",
                "adjacency": {"from_room": "A", "to_room": "B", "from_cell": Vector2i(0, 0), "to_cell": Vector2i(2, 0)},
            },
            {
                "label": "declared-direction-mismatch",
                "adjacency": {"from_room": "A", "to_room": "B", "from_cell": Vector2i(0, 0), "to_cell": Vector2i(1, 0), "direction": "north"},
            },
            {
                "label": "declared-edge-mismatch",
                "adjacency": {"from_room": "A", "to_room": "B", "from_cell": Vector2i(0, 0), "to_cell": Vector2i(1, 0), "edge_key": "0|v|100|100"},
            },
        ]
        for case_variant in cases:
            var test_case: Dictionary = case_variant
            var result_case: Dictionary = generator._build_explicit_portals([test_case["adjacency"]], placed_rooms)
            if bool(result_case.get("ok", true)):
                _fail("invalid %s adjacency was accepted" % String(test_case["label"]))
            if not (result_case.get("portals", []) as Array).is_empty():
                _fail("invalid %s adjacency emitted a portal" % String(test_case["label"]))

        var stamped_layout: Dictionary = {"rooms": []}
        var stale_grid: Dictionary = {"rooms": placed_rooms, "adjacencies": [cases[0]["adjacency"]]}
        if generator._stamp_explicit_structural_layout(stamped_layout, stale_grid):
            _fail("stale adjacency was accepted by the structural layout stamp")
        if stamped_layout.has("portals") and not (stamped_layout["portals"] as Array).is_empty():
            _fail("failed structural layout stamp emitted stale portal records")
        """,
    )
    _assert_layout_probe_passed(result)


def test_layout_generator_preserves_portal_intent_type_alias_and_required_false(tmp_path: Path):
    result = _run_layout_probe(
        tmp_path,
        """
        var generator := LayoutGenerator.new()
        var placed_rooms: Dictionary = {
            "A": {"deck": 0, "cells": [Vector2i(0, 0)]},
            "B": {"deck": 0, "cells": [Vector2i(1, 0)]},
        }
        var type_result: Dictionary = generator._build_explicit_portals([{
            "from_room": "A",
            "to_room": "B",
            "from_cell": Vector2i(0, 0),
            "to_cell": Vector2i(1, 0),
            "type": "locked",
            "required": false,
        }], placed_rooms)
        if not bool(type_result.get("ok", false)) or (type_result["portals"] as Array).size() != 1:
            _fail("locked intent did not produce one portal record")
        else:
            var type_portal: Dictionary = type_result["portals"][0]
            if String(type_portal.get("type", "")) != "locked":
                _fail("type intent was flattened: " + JSON.stringify(type_portal))
            if String(type_portal.get("portal_type", "")) != "locked":
                _fail("portal_type alias was not preserved: " + JSON.stringify(type_portal))
            if bool(type_portal.get("required", true)):
                _fail("required=false was coerced to true: " + JSON.stringify(type_portal))

        var alias_result: Dictionary = generator._build_explicit_portals([{
            "from_room": "A",
            "to_room": "B",
            "from_cell": Vector2i(0, 0),
            "to_cell": Vector2i(1, 0),
            "portal_type": "hatch",
            "required": false,
        }], placed_rooms)
        if not bool(alias_result.get("ok", false)) or (alias_result["portals"] as Array).size() != 1:
            _fail("portal_type alias did not produce one portal record")
        else:
            var alias_portal: Dictionary = alias_result["portals"][0]
            if String(alias_portal.get("type", "")) != "hatch" or String(alias_portal.get("portal_type", "")) != "hatch":
                _fail("portal_type intent was not preserved: " + JSON.stringify(alias_portal))
            if bool(alias_portal.get("required", true)):
                _fail("portal_type required=false was coerced to true: " + JSON.stringify(alias_portal))
        """,
    )
    _assert_layout_probe_passed(result)


def test_layout_generator_deduplicates_physical_portal_but_exposes_missing_portal(tmp_path: Path):
    result = _run_layout_probe(
        tmp_path,
        """
        var generator := LayoutGenerator.new()
        var placed_rooms: Dictionary = {
            "A": {"deck": 0, "cells": [Vector2i(0, 0)]},
            "B": {"deck": 0, "cells": [Vector2i(1, 0)]},
        }
        var duplicate_result: Dictionary = generator._build_explicit_portals([
            {"from_room": "A", "to_room": "B", "from_cell": Vector2i(0, 0), "to_cell": Vector2i(1, 0)},
            {"from_room": "B", "to_room": "A", "from_cell": Vector2i(1, 0), "to_cell": Vector2i(0, 0)},
        ], placed_rooms)
        if not bool(duplicate_result.get("ok", false)):
            _fail("duplicate physical adjacency was rejected: " + JSON.stringify(duplicate_result.get("errors", [])))
        elif (duplicate_result.get("portals", []) as Array).size() != 1:
            _fail("duplicate physical adjacency emitted more than one portal")

        var missing_result: Dictionary = generator._build_explicit_portals([], placed_rooms)
        if not bool(missing_result.get("ok", false)):
            _fail("missing portal intent was treated as an invalid layout")
        elif not (missing_result.get("portals", []) as Array).is_empty():
            _fail("missing portal intent fabricated a portal")
        """,
    )
    _assert_layout_probe_passed(result)


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


def test_validator_declares_canonical_contract_and_all_validation_gates():
    source = _read("scripts/procgen/structural_plan_validator.gd")
    assert "func validate(plan: Dictionary, topology: Dictionary) -> Dictionary:" in source
    assert "func _validate_unique_edge_placements(plan: Dictionary, errors: Array[String]) -> void" in source
    assert "func _validate_portal_endpoints(plan: Dictionary, errors: Array[String]) -> void" in source
    assert "func _validate_placement_grid_pose(plan: Dictionary, errors: Array[String]) -> void" in source
    assert "func _validate_footprint_overlap(plan: Dictionary, errors: Array[String]) -> void" in source
    assert "func _validate_walkable_reachability(plan: Dictionary, topology: Dictionary, errors: Array[String]) -> void" in source
    assert "duplicate edge placement" in source
    assert "exactly one" in source
    assert "portal endpoints are not reciprocal" in source
    assert "opposed portal normals" in source
    assert "flood_fill" in source
    assert "topology reachability" in source


def test_validator_accepts_a_valid_compiler_plan(tmp_path: Path):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [
                {"id": "A", "deck": 0, "cells": [[0, 0]]},
                {"id": "B", "deck": 0, "cells": [[1, 0]]},
            ],
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "door",
                "required": true,
                "edge_key": "0|v|0|0",
            }],
        }
        var plan: Dictionary = Compiler.new().compile(topology)
        var validator := Validator.new()
        var verdict: Dictionary = validator.validate(plan, topology)
        if not bool(verdict.get("ok", false)):
            _fail("valid compiler plan was rejected: " + JSON.stringify(verdict.get("errors", [])))
        if int(verdict.get("stats", {}).get("placement_count", -1)) != plan["placements"].size():
            _fail("validator stats did not count canonical placements")

        var wire_plan_variant: Variant = JSON.parse_string(JSON.stringify(plan))
        var wire_topology_variant: Variant = JSON.parse_string(JSON.stringify(topology))
        if not (wire_plan_variant is Dictionary) or not (wire_topology_variant is Dictionary):
            _fail("serialized canonical validator fixture did not remain dictionaries")
        var wire_verdict: Dictionary = validator.validate(wire_plan_variant, wire_topology_variant)
        if not bool(wire_verdict.get("ok", false)):
            _fail("validator rejected serialized compiler plan: " + JSON.stringify(wire_verdict.get("errors", [])))
        """,
    )
    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    assert result.returncode == 0, output
    assert not any(marker in output for marker in ("ERROR:", "WARNING:", "SCRIPT ERROR:")), output
    assert "PROCGEN VALIDATOR PROBE PASS" in output


def test_validator_rejects_duplicate_edge_placement_as_nonzero_probe(tmp_path: Path):
    body = """
    var topology: Dictionary = {
        "rooms": [
            {"id": "A", "deck": 0, "cells": [[0, 0]]},
            {"id": "B", "deck": 0, "cells": [[1, 0]]},
        ],
        "portals": [{
            "from_room": "A",
            "to_room": "B",
            "type": "door",
            "required": true,
            "edge_key": "0|v|0|0",
        }],
    }
    var plan: Dictionary = Compiler.new().compile(topology)
    var placements: Array = plan["placements"].duplicate(true)
    placements.append((placements[0] as Dictionary).duplicate(true))
    plan["placements"] = placements
    """ + _validator_case_body("duplicate-edge", "plan", "duplicate edge placement")
    result = _run_validator_probe(tmp_path, body)
    _assert_validator_probe_failed(result, "duplicate edge placement")


def test_validator_rejects_misplaced_north_edge_as_nonzero_probe(tmp_path: Path):
    body = """
    var topology: Dictionary = {
        "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
        "portals": [],
    }
    var plan: Dictionary = Compiler.new().compile(topology)
    for placement_variant in plan["placements"]:
        var placement: Dictionary = placement_variant
        if String(placement.get("direction", "")) == "north":
            placement["position"] = Vector3(0.0, 0.0, 2.0)
    """ + _validator_case_body("misplaced-north-edge", "plan", "canonical cell edge")
    result = _run_validator_probe(tmp_path, body)
    _assert_validator_probe_failed(result, "canonical cell edge")


def test_validator_rejects_required_portal_blocked_by_solid_as_nonzero_probe(tmp_path: Path):
    body = """
    var topology: Dictionary = {
        "rooms": [
            {"id": "A", "deck": 0, "cells": [[0, 0]]},
            {"id": "B", "deck": 0, "cells": [[1, 0]]},
        ],
        "portals": [{
            "from_room": "A",
            "to_room": "B",
            "type": "door",
            "required": true,
            "edge_key": "0|v|0|0",
        }],
    }
    var plan: Dictionary = Compiler.new().compile(topology)
    var blocked_edge: Dictionary = plan["edges"]["0|v|0|0"]
    blocked_edge["kind"] = "SOLID"
    blocked_edge["state"] = "SOLID"
    plan["edges"]["0|v|0|0"] = blocked_edge
    for placement_variant in plan["placements"]:
        var placement: Dictionary = placement_variant
        if String(placement.get("edge_key", "")) == "0|v|0|0":
            placement["kind"] = "SOLID"
            placement["state"] = "SOLID"
    """ + _validator_case_body("blocked-required-portal", "plan", "topology-connected")
    result = _run_validator_probe(tmp_path, body)
    _assert_validator_probe_failed(result, "topology-connected")


def test_validator_rejects_strict_portal_and_reachability_contracts_with_distinct_errors(
    tmp_path: Path,
):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [
                {"id": "A", "deck": 0, "cells": [[0, 0]]},
                {"id": "B", "deck": 0, "cells": [[1, 0]]},
            ],
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "door",
                "required": true,
                "edge_key": "0|v|0|0",
            }],
        }
        var base_plan: Dictionary = Compiler.new().compile(topology)
        var validator := Validator.new()
        var valid_verdict: Dictionary = validator.validate(base_plan, topology)
        if not bool(valid_verdict.get("ok", false)):
            _fail("valid compiler plan was rejected: " + JSON.stringify(valid_verdict.get("errors", [])))

        var explicit_exterior_case: Dictionary = base_plan.duplicate(true)
        var explicit_exterior_edge: Dictionary = explicit_exterior_case["edges"]["0|v|0|0"]
        explicit_exterior_edge["kind"] = "BREACH"
        explicit_exterior_edge["state"] = "BREACH"
        explicit_exterior_edge["room_ids"] = ["A", ""]
        explicit_exterior_edge["owner_room"] = "A"
        explicit_exterior_edge["other_room"] = ""
        explicit_exterior_edge["module_id"] = ""
        explicit_exterior_edge["exterior"] = true
        explicit_exterior_case["edges"]["0|v|0|0"] = explicit_exterior_edge
        var exterior_placements: Array = []
        for placement_variant in explicit_exterior_case["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement.get("edge_key", "")) != "0|v|0|0":
                exterior_placements.append(placement)
        explicit_exterior_case["placements"] = exterior_placements
        var explicit_exterior_verdict: Dictionary = validator.validate(explicit_exterior_case, topology)
        if not bool(explicit_exterior_verdict.get("ok", false)):
            _fail(
                "explicit exterior breach was rejected: "
                + JSON.stringify(explicit_exterior_verdict.get("errors", []))
            )
        else:
            print("VALIDATOR EXPECTED PASS explicit-exterior-breach")

        var cases: Array = []

        var endpoint_case: Dictionary = base_plan.duplicate(true)
        var endpoint_edge: Dictionary = endpoint_case["edges"]["0|v|0|0"]
        endpoint_edge["room_ids"] = ["A", "A"]
        endpoint_case["edges"]["0|v|0|0"] = endpoint_edge
        cases.append({
            "label": "nonreciprocal-endpoints",
            "plan": endpoint_case,
            "error": "portal endpoints are not reciprocal",
        })

        var normals_case: Dictionary = base_plan.duplicate(true)
        var normals_edge: Dictionary = normals_case["edges"]["0|v|0|0"]
        normals_edge["opposite_direction"] = "east"
        normals_case["edges"]["0|v|0|0"] = normals_edge
        cases.append({
            "label": "nonreciprocal-normals",
            "plan": normals_case,
            "error": "opposed portal normals are invalid",
        })

        var yaw_case: Dictionary = base_plan.duplicate(true)
        for placement_variant in yaw_case["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement.get("edge_key", "")) == "0|v|0|0":
                placement["yaw_degrees"] = 45.0
        cases.append({
            "label": "invalid-yaw",
            "plan": yaw_case,
            "error": "placement yaw is outside canonical pose",
        })

        var overlap_case: Dictionary = base_plan.duplicate(true)
        var overlap_records: Array = []
        var base_occupancy: Dictionary = overlap_case["occupancy"]
        for record_variant in base_occupancy.values():
            overlap_records.append(record_variant)
        var duplicate_record: Dictionary = (overlap_records[0] as Dictionary).duplicate(true)
        duplicate_record["room_id"] = "overlap-room"
        overlap_records.append(duplicate_record)
        overlap_case["occupancy"] = overlap_records
        cases.append({
            "label": "occupied-cell-overlap",
            "plan": overlap_case,
            "error": "occupied-cell overlap",
        })

        var topology_case: Dictionary = base_plan.duplicate(true)
        var topology_edge: Dictionary = topology_case["edges"]["0|v|0|0"]
        topology_edge["kind"] = "LOCKED"
        topology_edge["state"] = "LOCKED"
        topology_case["edges"]["0|v|0|0"] = topology_edge
        cases.append({
            "label": "topology-flood-fill-mismatch",
            "plan": topology_case,
            "error": "topology reachability mismatch",
        })

        for portal_kind in ["HATCH", "BREACH"]:
            var one_sided_case: Dictionary = base_plan.duplicate(true)
            var one_sided_edge: Dictionary = one_sided_case["edges"]["0|v|0|0"]
            one_sided_edge["kind"] = portal_kind
            one_sided_edge["state"] = portal_kind
            one_sided_edge["room_ids"] = ["A", ""]
            one_sided_edge["owner_room"] = "A"
            one_sided_edge["other_room"] = ""
            one_sided_edge["exterior"] = false
            one_sided_case["edges"]["0|v|0|0"] = one_sided_edge
            cases.append({
                "label": "non-exterior-one-sided-" + portal_kind.to_lower(),
                "plan": one_sided_case,
                "error": "one-sided %s portal must explicitly set exterior=true" % portal_kind,
            })

        var malformed_source_case: Dictionary = base_plan.duplicate(true)
        var malformed_source_edge: Dictionary = malformed_source_case["edges"]["0|v|0|0"]
        malformed_source_edge["source_cells"] = [Vector2i(0, 0), [1.5, 0]]
        malformed_source_case["edges"]["0|v|0|0"] = malformed_source_edge
        cases.append({
            "label": "malformed-source-cell",
            "plan": malformed_source_case,
            "error": "portal source_cells are invalid",
        })

        var nonadjacent_source_case: Dictionary = base_plan.duplicate(true)
        var nonadjacent_source_edge: Dictionary = nonadjacent_source_case["edges"]["0|v|0|0"]
        nonadjacent_source_edge["source_cells"] = [Vector2i(0, 0), Vector2i(2, 0)]
        nonadjacent_source_case["edges"]["0|v|0|0"] = nonadjacent_source_edge
        cases.append({
            "label": "nonadjacent-source-cells",
            "plan": nonadjacent_source_case,
            "error": "portal source_cells are not adjacent across declared edge",
        })

        var missing_source_case: Dictionary = base_plan.duplicate(true)
        var missing_source_edge: Dictionary = missing_source_case["edges"]["0|v|0|0"]
        missing_source_edge.erase("source_cells")
        missing_source_case["edges"]["0|v|0|0"] = missing_source_edge
        cases.append({
            "label": "missing-source-cells",
            "plan": missing_source_case,
            "error": "portal source_cells must be an Array of exactly two cells",
        })

        for case_variant in cases:
            var test_case: Dictionary = case_variant
            var verdict: Dictionary = validator.validate(test_case["plan"], topology)
            var error_text: String = JSON.stringify(verdict.get("errors", []))
            if bool(verdict.get("ok", false)):
                _fail("validator accepted invalid case %s" % String(test_case["label"]))
            elif not error_text.contains(String(test_case["error"])):
                _fail(
                    "validator returned wrong error for %s: %s" % [
                        String(test_case["label"]),
                        error_text,
                    ]
                )
            else:
                print("VALIDATOR EXPECTED FAIL %s: %s" % [String(test_case["label"]), error_text])
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_rejects_adjacent_source_cells_with_mismatched_declared_edge(
    tmp_path: Path,
):
    body = """
    var topology: Dictionary = {
        "rooms": [
            {"id": "A", "deck": 0, "cells": [[0, 0]]},
            {"id": "B", "deck": 0, "cells": [[1, 0]]},
        ],
        "portals": [{
            "from_room": "A",
            "to_room": "B",
            "type": "door",
            "required": true,
            "edge_key": "0|v|0|0",
        }],
    }
    var plan: Dictionary = Compiler.new().compile(topology)
    var mismatched_source_cells: Array = [Vector2i(100, 100), Vector2i(101, 100)]
    var edge: Dictionary = plan["edges"]["0|v|0|0"]
    edge["source_cells"] = mismatched_source_cells
    plan["edges"]["0|v|0|0"] = edge
    for placement_variant in plan["placements"]:
        var placement: Dictionary = placement_variant
        if String(placement.get("edge_key", "")) == "0|v|0|0":
            placement["source_cells"] = mismatched_source_cells
    """ + _validator_case_body(
        "mismatched-source-edge",
        "plan",
        "portal source_cells do not match declared edge_key",
    )
    result = _run_validator_probe(tmp_path, body)
    _assert_validator_probe_failed(
        result,
        "portal source_cells do not match declared edge_key",
    )


def test_validator_accepts_valid_explicit_exterior_hatch_runtime(tmp_path: Path):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
            "portals": [{
                "from_room": "A",
                "to_room": "",
                "type": "hatch",
                "required": true,
                "edge_key": "0|v|0|0",
            }],
        }
        var plan: Dictionary = Compiler.new().compile(topology)
        if not plan["errors"].is_empty():
            _fail("valid explicit exterior hatch produced compiler errors: " + JSON.stringify(plan["errors"]))
        var edge: Dictionary = plan["edges"]["0|v|0|0"]
        if String(edge.get("kind", "")) != "HATCH" or not bool(edge.get("exterior", false)):
            _fail("explicit exterior hatch was not retained as exterior HATCH")
        var verdict: Dictionary = Validator.new().validate(plan, topology)
        if not bool(verdict.get("ok", false)):
            _fail("valid explicit exterior hatch was rejected: " + JSON.stringify(verdict.get("errors", [])))
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_rejects_non_dictionary_edge_record_without_script_error(tmp_path: Path):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [
                {"id": "A", "deck": 0, "cells": [[0, 0]]},
                {"id": "B", "deck": 0, "cells": [[1, 0]]},
            ],
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "door",
                "required": true,
                "edge_key": "0|v|0|0",
            }],
        }
        var plan: Dictionary = Compiler.new().compile(topology)
        plan["edges"]["0|v|0|0"] = "malformed edge record"
        var verdict: Dictionary = Validator.new().validate(plan, topology)
        var error_text: String = JSON.stringify(verdict.get("errors", []))
        if bool(verdict.get("ok", false)):
            _fail("validator accepted a non-Dictionary edge record")
        elif not error_text.contains("edge record is not a Dictionary"):
            _fail("validator returned the wrong malformed-edge error: " + error_text)
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_derives_door_materialization_requirement_from_kind(tmp_path: Path):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [
                {"id": "A", "deck": 0, "cells": [[0, 0]]},
                {"id": "B", "deck": 0, "cells": [[1, 0]]},
            ],
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "door",
                "required": true,
                "edge_key": "0|v|0|0",
            }],
        }
        var plan: Dictionary = Compiler.new().compile(topology)
        var door_edge: Dictionary = plan["edges"]["0|v|0|0"]
        door_edge.erase("placement_required")
        door_edge.erase("wrapper_required")
        plan["edges"]["0|v|0|0"] = door_edge
        var kept_placements: Array = []
        for placement_variant in plan["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement.get("edge_key", "")) != "0|v|0|0":
                kept_placements.append(placement)
        plan["placements"] = kept_placements
        var verdict: Dictionary = Validator.new().validate(plan, topology)
        var error_text: String = JSON.stringify(verdict.get("errors", []))
        if bool(verdict.get("ok", false)):
            _fail("DOOR became optional when placement_required/wrapper_required were omitted")
        elif not error_text.contains("requires exactly one non-OPEN placement"):
            _fail("validator returned the wrong missing-DOOR-placement error: " + error_text)
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_rejects_malformed_and_missing_occupancy_without_script_error(
    tmp_path: Path,
):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [
                {"id": "A", "deck": 0, "cells": [[0, 0]]},
                {"id": "B", "deck": 0, "cells": [[1, 0]]},
            ],
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "door",
                "required": true,
                "edge_key": "0|v|0|0",
            }],
        }
        var base_plan: Dictionary = Compiler.new().compile(topology)
        var cases: Array = []
        var missing_plan: Dictionary = base_plan.duplicate(true)
        missing_plan.erase("occupancy")
        cases.append({"label": "missing", "plan": missing_plan, "error": "occupancy"})
        var empty_dictionary_plan: Dictionary = base_plan.duplicate(true)
        empty_dictionary_plan["occupancy"] = {}
        cases.append({"label": "empty-dictionary", "plan": empty_dictionary_plan, "error": "occupancy"})
        var empty_array_plan: Dictionary = base_plan.duplicate(true)
        empty_array_plan["occupancy"] = []
        cases.append({"label": "empty-array", "plan": empty_array_plan, "error": "occupancy"})
        var malformed_record_plan: Dictionary = base_plan.duplicate(true)
        malformed_record_plan["occupancy"]["0|0|0"] = "malformed occupancy record"
        cases.append({
            "label": "malformed-record",
            "plan": malformed_record_plan,
            "error": "occupancy record is not a Dictionary",
        })
        var malformed_fields_plan: Dictionary = base_plan.duplicate(true)
        malformed_fields_plan["occupancy"]["0|0|0"] = {
            "deck": 0,
            "cell": [0.5, 0],
            "room_id": "A",
        }
        cases.append({
            "label": "malformed-fields",
            "plan": malformed_fields_plan,
            "error": "occupancy record is malformed",
        })

        for case_variant in cases:
            var test_case: Dictionary = case_variant
            var verdict: Dictionary = Validator.new().validate(test_case["plan"], topology)
            var error_text: String = JSON.stringify(verdict.get("errors", []))
            if bool(verdict.get("ok", false)):
                _fail("validator accepted invalid occupancy case " + String(test_case["label"]))
            elif not error_text.contains(String(test_case["error"])):
                _fail(
                    "validator returned the wrong occupancy error for %s: %s" % [
                        String(test_case["label"]),
                        error_text,
                    ]
                )
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_requires_module_ids_for_materialized_states_and_allows_breach_exception(
    tmp_path: Path,
):
    result = _run_validator_probe(
        tmp_path,
        """
        var compiler := Compiler.new()
        var room_pair: Array = [
            {"id": "A", "deck": 0, "cells": [[0, 0]]},
            {"id": "B", "deck": 0, "cells": [[1, 0]]},
        ]
        var plan_cases: Array = [
            {
                "label": "SOLID",
                "plan": compiler.compile({
                    "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
                    "portals": [],
                }),
                "edge_key": "0|v|0|0",
            },
            {
                "label": "DOOR",
                "plan": compiler.compile({
                    "rooms": room_pair,
                    "portals": [{"from_room": "A", "to_room": "B", "type": "door", "edge_key": "0|v|0|0"}],
                }),
                "edge_key": "0|v|0|0",
            },
            {
                "label": "LOCKED",
                "plan": compiler.compile({
                    "rooms": room_pair,
                    "portals": [{"from_room": "A", "to_room": "B", "type": "locked", "edge_key": "0|v|0|0"}],
                }),
                "edge_key": "0|v|0|0",
            },
            {
                "label": "HATCH",
                "plan": compiler.compile({
                    "rooms": room_pair,
                    "portals": [{"from_room": "A", "to_room": "B", "type": "hatch", "edge_key": "0|v|0|0"}],
                }),
                "edge_key": "0|v|0|0",
            },
            {
                "label": "BREACH",
                "plan": compiler.compile({
                    "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
                    "portals": [{"from_room": "A", "to_room": "", "type": "breach", "edge_key": "0|v|0|0"}],
                }),
                "edge_key": "0|v|0|0",
            },
        ]
        var pair_topology: Dictionary = {
            "rooms": room_pair,
            "portals": [{
                "from_room": "A",
                "to_room": "B",
                "type": "door",
                "edge_key": "0|v|0|0",
            }],
        }
        var validator := Validator.new()
        for case_variant in plan_cases:
            var test_case: Dictionary = case_variant
            var label: String = String(test_case["label"])
            var base_plan: Dictionary = test_case["plan"]
            var edge_key: String = String(test_case["edge_key"])
            if not base_plan["errors"].is_empty():
                _fail("compiler emitted errors for valid %s: " % label + JSON.stringify(base_plan["errors"]))
                continue
            var validation_topology: Dictionary = {}
            if label == "DOOR" or label == "LOCKED" or label == "HATCH":
                validation_topology = pair_topology.duplicate(true)
                var topology_portal: Dictionary = validation_topology["portals"][0]
                topology_portal["type"] = label.to_lower()
                validation_topology["portals"][0] = topology_portal
            var base_verdict: Dictionary = validator.validate(base_plan, validation_topology)
            if label == "BREACH":
                if not bool(base_verdict.get("ok", false)):
                    _fail("valid BREACH compiler plan was rejected: " + JSON.stringify(base_verdict.get("errors", [])))
                var breach_edge: Dictionary = base_plan["edges"][edge_key]
                if not String(breach_edge.get("module_id", "")).is_empty():
                    _fail("BREACH unexpectedly requires an edge module_id")
                for placement_variant in base_plan["placements"]:
                    var breach_placement: Dictionary = placement_variant
                    if String(breach_placement.get("edge_key", "")) == edge_key:
                        _fail("BREACH unexpectedly emitted a wrapper placement")
                continue
            if not bool(base_verdict.get("ok", false)):
                _fail("valid %s compiler plan was rejected: " % label + JSON.stringify(base_verdict.get("errors", [])))

            var missing_edge_plan: Dictionary = base_plan.duplicate(true)
            var edge: Dictionary = missing_edge_plan["edges"][edge_key]
            edge["module_id"] = ""
            missing_edge_plan["edges"][edge_key] = edge
            var missing_edge_verdict: Dictionary = validator.validate(missing_edge_plan, validation_topology)
            var edge_error_text: String = JSON.stringify(missing_edge_verdict.get("errors", []))
            if bool(missing_edge_verdict.get("ok", false)) or not edge_error_text.contains("materialized edge module_id is missing"):
                _fail("missing %s edge module_id was not rejected: " % label + edge_error_text)

            var missing_placement_plan: Dictionary = base_plan.duplicate(true)
            var updated_placements: Array = []
            var found_placement := false
            for placement_variant in missing_placement_plan["placements"]:
                var placement: Dictionary = placement_variant
                if String(placement.get("edge_key", "")) == edge_key:
                    placement["module_id"] = ""
                    found_placement = true
                updated_placements.append(placement)
            if not found_placement:
                _fail("valid %s compiler plan did not emit a materialized placement" % label)
            missing_placement_plan["placements"] = updated_placements
            var missing_placement_verdict: Dictionary = validator.validate(missing_placement_plan, validation_topology)
            var placement_error_text: String = JSON.stringify(missing_placement_verdict.get("errors", []))
            if bool(missing_placement_verdict.get("ok", false)) or not placement_error_text.contains("materialized placement module_id is missing"):
                _fail("missing %s placement module_id was not rejected: " % label + placement_error_text)
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_declares_strict_semantic_state_and_reconciliation_gates():
    source = _read("scripts/procgen/structural_plan_validator.gd")
    for state in ("SOLID", "OPEN", "DOOR", "LOCKED", "HATCH", "BREACH"):
        assert '"%s"' % state in source
    assert "kind/state mismatch" in source
    assert "unknown semantic state" in source
    assert "canonical edges" in source
    assert "cell-key/body drift" in source
    assert "unknown room_id" in source


def test_validator_rejects_bogus_absent_and_mismatched_semantic_states(
    tmp_path: Path,
):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
            "portals": [],
        }
        var base_plan: Dictionary = Compiler.new().compile(topology)
        var validator := Validator.new()
        var edge_key := "0|v|0|0"
        var cases: Array = []

        var bogus_case: Dictionary = base_plan.duplicate(true)
        var bogus_edge: Dictionary = bogus_case["edges"][edge_key]
        bogus_edge["kind"] = "BOGUS"
        bogus_edge["state"] = "BOGUS"
        bogus_case["edges"][edge_key] = bogus_edge
        cases.append({"label": "BOGUS", "plan": bogus_case, "error": "unknown semantic state"})

        var absent_case: Dictionary = base_plan.duplicate(true)
        var absent_edge: Dictionary = absent_case["edges"][edge_key]
        absent_edge.erase("kind")
        absent_edge.erase("state")
        absent_case["edges"][edge_key] = absent_edge
        cases.append({"label": "absent-kind", "plan": absent_case, "error": "semantic state is missing"})

        var mismatch_case: Dictionary = base_plan.duplicate(true)
        var mismatch_edge: Dictionary = mismatch_case["edges"][edge_key]
        mismatch_edge["state"] = "OPEN"
        mismatch_case["edges"][edge_key] = mismatch_edge
        cases.append({"label": "kind-state-mismatch", "plan": mismatch_case, "error": "kind/state mismatch"})

        for case_variant in cases:
            var test_case: Dictionary = case_variant
            var verdict: Dictionary = validator.validate(test_case["plan"], topology)
            var error_text := JSON.stringify(verdict.get("errors", []))
            if bool(verdict.get("ok", false)):
                _fail("validator accepted semantic-state case " + String(test_case["label"]))
            elif not error_text.contains(String(test_case["error"])):
                _fail("validator returned wrong semantic-state error: " + error_text)
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_rejects_orphan_placement_with_otherwise_valid_canonical_pose(
    tmp_path: Path,
):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
            "portals": [],
        }
        var plan: Dictionary = Compiler.new().compile(topology)
        var orphan: Dictionary = (plan["placements"][0] as Dictionary).duplicate(true)
        orphan["edge_key"] = "0|v|100|100"
        orphan["key"] = "0|v|100|100"
        orphan["cell"] = Vector2i(100, 100)
        orphan["source_cells"] = [Vector2i(100, 100), Vector2i(101, 100)]
        orphan["direction"] = "east"
        orphan["opposite_direction"] = "west"
        orphan["position"] = Vector3(402.0, 0.0, 400.0)
        orphan["yaw_degrees"] = 270.0
        plan["placements"].append(orphan)
        var verdict: Dictionary = Validator.new().validate(plan, topology)
        var error_text := JSON.stringify(verdict.get("errors", []))
        if bool(verdict.get("ok", false)):
            _fail("validator accepted orphan placement with a valid pose")
        elif not error_text.contains("placement edge_key is not present in canonical edges"):
            _fail("validator returned wrong orphan-placement error: " + error_text)
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_reconciles_occupancy_keys_bodies_and_room_registry(
    tmp_path: Path,
):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
            "portals": [],
        }
        var base_plan: Dictionary = Compiler.new().compile(topology)
        var validator := Validator.new()
        var cases: Array = []

        var map_key_case: Dictionary = base_plan.duplicate(true)
        var map_record: Dictionary = map_key_case["occupancy"]["0|0|0"]
        map_key_case["occupancy"].erase("0|0|0")
        map_key_case["occupancy"]["0|99|0"] = map_record
        cases.append({"label": "garbage-key", "plan": map_key_case, "error": "cell-key/body drift"})

        var moved_case: Dictionary = base_plan.duplicate(true)
        var moved_record: Dictionary = moved_case["occupancy"]["0|0|0"]
        moved_record["cell"] = Vector2i(4, 4)
        moved_case["occupancy"]["0|0|0"] = moved_record
        cases.append({"label": "moved-cell", "plan": moved_case, "error": "cell-key/body drift"})

        var unknown_room_case: Dictionary = base_plan.duplicate(true)
        var unknown_room_record: Dictionary = unknown_room_case["occupancy"]["0|0|0"]
        unknown_room_record["room_id"] = "ghost-room"
        unknown_room_case["occupancy"]["0|0|0"] = unknown_room_record
        cases.append({"label": "unknown-room", "plan": unknown_room_case, "error": "unknown room_id"})

        for case_variant in cases:
            var test_case: Dictionary = case_variant
            var verdict: Dictionary = validator.validate(test_case["plan"], topology)
            var error_text := JSON.stringify(verdict.get("errors", []))
            if bool(verdict.get("ok", false)):
                _fail("validator accepted occupancy case " + String(test_case["label"]))
            elif not error_text.contains(String(test_case["error"])):
                _fail("validator returned wrong occupancy reconciliation error: " + error_text)
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_rejects_source_cells_and_edge_endpoints_that_leave_occupancy(
    tmp_path: Path,
):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
            "portals": [],
        }
        var base_plan: Dictionary = Compiler.new().compile(topology)
        var validator := Validator.new()
        var edge_key := "0|v|0|0"
        var cases: Array = []

        var source_case: Dictionary = base_plan.duplicate(true)
        var source_edge: Dictionary = source_case["edges"][edge_key]
        source_edge["source_cells"] = [Vector2i(99, 99), Vector2i(100, 99)]
        source_case["edges"][edge_key] = source_edge
        cases.append({"label": "source-cells", "plan": source_case, "error": "source_cells do not match declared edge_key"})

        var endpoint_case: Dictionary = base_plan.duplicate(true)
        var endpoint_edge: Dictionary = endpoint_case["edges"][edge_key]
        endpoint_edge["room_ids"] = ["A", "ghost-room"]
        endpoint_edge["owner_room"] = "A"
        endpoint_edge["other_room"] = "ghost-room"
        endpoint_case["edges"][edge_key] = endpoint_edge
        cases.append({"label": "edge-endpoint", "plan": endpoint_case, "error": "edge endpoint"})

        for case_variant in cases:
            var test_case: Dictionary = case_variant
            var verdict: Dictionary = validator.validate(test_case["plan"], topology)
            var error_text := JSON.stringify(verdict.get("errors", []))
            if bool(verdict.get("ok", false)):
                _fail("validator accepted inconsistent source/endpoints " + String(test_case["label"]))
            elif not error_text.contains(String(test_case["error"])):
                _fail("validator returned wrong source/endpoint error: " + error_text)
        """,
    )
    _assert_validator_probe_passed(result)


def test_validator_rejects_final_edge_map_and_placement_reconciliation_false_accepts(
    tmp_path: Path,
):
    result = _run_validator_probe(
        tmp_path,
        """
        var topology: Dictionary = {
            "rooms": [{"id": "A", "deck": 0, "cells": [[0, 0]]}],
            "portals": [],
        }
        var base_plan: Dictionary = Compiler.new().compile(topology)
        var validator := Validator.new()
        var edge_key := ""
        for placement_variant in base_plan["placements"]:
            edge_key = String((placement_variant as Dictionary).get("edge_key", ""))
            if not edge_key.is_empty():
                break
        if edge_key.is_empty():
            _fail("compiler fixture did not emit a canonical placement edge")

        var multicell_topology: Dictionary = {
            "rooms": [{"id": "multi", "deck": 0, "cells": [[0, 0], [1, 0]]}],
            "portals": [],
        }
        var multicell_plan: Dictionary = Compiler.new().compile(multicell_topology)
        var multicell_verdict: Dictionary = validator.validate(multicell_plan, multicell_topology)
        if not bool(multicell_verdict.get("ok", false)):
            _fail("valid multi-cell compiler plan was rejected: " + JSON.stringify(multicell_verdict.get("errors", [])))

        var cardinal_cases: Array = [
            {"direction": "north", "edge_key": "0|h|-1|0"},
            {"direction": "east", "edge_key": "0|v|0|0"},
            {"direction": "south", "edge_key": "0|h|0|0"},
            {"direction": "west", "edge_key": "0|v|0|-1"},
        ]
        for cardinal_variant in cardinal_cases:
            var cardinal_case: Dictionary = cardinal_variant
            var cardinal_topology: Dictionary = {
                "rooms": [{"id": "cardinal", "deck": 0, "cells": [[0, 0]]}],
                "portals": [{
                    "from_room": "cardinal",
                    "to_room": "",
                    "type": "hatch",
                    "required": true,
                    "edge_key": String(cardinal_case["edge_key"]),
                }],
            }
            var cardinal_plan: Dictionary = Compiler.new().compile(cardinal_topology)
            var cardinal_verdict: Dictionary = validator.validate(cardinal_plan, cardinal_topology)
            if not cardinal_plan["errors"].is_empty() or not bool(cardinal_verdict.get("ok", false)):
                _fail(
                    "valid cardinal compiler plan was rejected for %s: %s" % [
                        String(cardinal_case["direction"]),
                        JSON.stringify(cardinal_verdict.get("errors", [])),
                    ]
                )

        var cases: Array = []

        var empty_edges_case: Dictionary = base_plan.duplicate(true)
        empty_edges_case["edges"] = {}
        empty_edges_case["placements"] = []
        cases.append({
            "label": "empty-canonical-edges",
            "plan": empty_edges_case,
            "error": "canonical edge map must be non-empty",
        })

        var kind_state_case: Dictionary = base_plan.duplicate(true)
        for placement_variant in kind_state_case["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement.get("edge_key", "")) == edge_key:
                placement["kind"] = "DOOR"
                placement["state"] = "DOOR"
                break
        cases.append({
            "label": "placement-kind-state-mismatch",
            "plan": kind_state_case,
            "error": "placement kind/state does not match canonical edge",
        })

        var module_case: Dictionary = base_plan.duplicate(true)
        for placement_variant in module_case["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement.get("edge_key", "")) == edge_key:
                placement["module_id"] = "doorway_frame_open_1x1"
                break
        cases.append({
            "label": "placement-module-mismatch",
            "plan": module_case,
            "error": "placement module_id does not match canonical edge",
        })

        var missing_edge_key_case: Dictionary = base_plan.duplicate(true)
        for placement_variant in missing_edge_key_case["placements"]:
            var placement: Dictionary = placement_variant
            if String(placement.get("edge_key", "")) == edge_key:
                placement.erase("edge_key")
                break
        cases.append({
            "label": "placement-missing-edge-key",
            "plan": missing_edge_key_case,
            "error": "placement edge_key is required; legacy key fallback is forbidden",
        })

        for case_variant in cases:
            var test_case: Dictionary = case_variant
            var verdict: Dictionary = validator.validate(test_case["plan"], topology)
            var error_text: String = JSON.stringify(verdict.get("errors", []))
            if bool(verdict.get("ok", false)):
                _fail("validator accepted final reconciliation case " + String(test_case["label"]))
            elif not error_text.contains(String(test_case["error"])):
                _fail(
                    "validator returned wrong final reconciliation error for %s: %s" % [
                        String(test_case["label"]),
                        error_text,
                    ]
                )
        """,
    )
    _assert_validator_probe_passed(result)
