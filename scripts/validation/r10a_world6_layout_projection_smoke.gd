extends SceneTree

## Frozen world-6 attachment projection coverage.
## Marker: R10-A WORLD6 LAYOUT PROJECTION PASS fixed=true fallback=true routes=true

const ProjectionScript := preload("res://scripts/systems/world_v6_layout_projection.gd")


func _initialize() -> void:
    if not _validate_fixed_authority():
        return
    if not _validate_candidate_resolution():
        return
    if not _validate_native_route_gate():
        return
    if not _validate_native_reference_outputs():
        return
    if not _validate_malformed_inputs():
        return
    if not _validate_fallback_replay():
        return
    print("R10-A WORLD6 LAYOUT PROJECTION PASS fixed=true fallback=true routes=true")
    quit(0)


func _validate_fixed_authority() -> bool:
    var home: Dictionary = ProjectionScript.project_fixed("home")
    if not bool(home.get("ok", false)):
        return _fail_bool("fixed home projection rejected")
    var home_projection: Dictionary = home.projection
    if home_projection != {
        "airlock": {
            "position": [2.0, 0.0, 2.0], "facing": [1.0, 0.0, 0.0],
            "type": "airlock", "size_class": 1, "condition": "intact",
        },
        "hangar": {
            "type": "hangar", "slot_count": 2, "slot_size_class": 2,
            "slot_anchors": [[20.0, 4.0, -4.0], [20.0, 4.0, -8.0]],
        },
    }:
        return _fail_bool("fixed home projection drifted: %s" % str(home_projection))

    var lifeboat: Dictionary = ProjectionScript.project_fixed("lifeboat")
    if not bool(lifeboat.get("ok", false)) or lifeboat.projection != {
        "airlock": {
            "position": [-2.0, 0.0, 0.0], "facing": [-1.0, 0.0, 0.0],
            "type": "airlock", "size_class": 1, "condition": "intact",
        },
        "hangar": {},
    }:
        return _fail_bool("fixed lifeboat projection drifted")
    var root_transform: Dictionary = ProjectionScript.compute_mobile_root_transform(
        home_projection.airlock, lifeboat.projection.airlock)
    if not bool(root_transform.get("ok", false)) or root_transform.transform != [
        1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 4.0, 0.0, 2.0,
    ]:
        return _fail_bool("historical docked lifeboat root drifted")
    for unsupported in ["", "derelict", "ship_start", "HOME"]:
        var rejected: Dictionary = ProjectionScript.project_fixed(unsupported)
        if bool(rejected.get("ok", false)) or rejected.get("reason", "") != "unsupported_fixed_owner":
            return _fail_bool("unsupported fixed owner accepted: %s" % unsupported)
    return true


func _validate_candidate_resolution() -> bool:
    var projection_a: Dictionary = _candidate_projection([4.0, 0.0, 2.0])
    var projection_b: Dictionary = projection_a.duplicate(true)
    var fallback: Dictionary = {
        "route": "fallback-gdscript-v6", "template_id": "compact",
        "projection": projection_a,
        "rooms": [{"id": "dock_01", "role": "dock", "deck": 0, "cells": [[1, 0]]}],
    }
    var native: Dictionary = {
        "route": "native-v2", "template_id": "native-v2",
        "projection": projection_b,
        "rooms": [{"id": "dock_01", "role": "dock", "deck": 0, "cells": [[1, 0]]}],
    }
    var witnesses: Dictionary = {
        "dock_edges": [{"port_type": "airlock", "slot_index": -1}],
        "room_cell_markers": [{"room_id": "dock_01", "cell": [1, 0]}],
    }
    var equivalent: Dictionary = ProjectionScript.resolve_authenticated_candidates(
        [fallback, native], witnesses, true)
    if not bool(equivalent.get("ok", false)) \
            or equivalent.get("origin_resolution", "") != "equivalent_projection" \
            or equivalent.get("admitted_routes", []) != ["fallback-gdscript-v6", "native-v2"]:
        return _fail_bool("identical multi-route candidates were not retained")

    var unavailable: Dictionary = ProjectionScript.resolve_authenticated_candidates(
        [fallback], witnesses, false)
    if bool(unavailable.get("ok", false)) \
            or unavailable.get("reason", "") != "legacy_generation_route_unavailable":
        return _fail_bool("incomplete candidate set selected fallback")

    var divergent: Dictionary = native.duplicate(true)
    divergent.projection.airlock.position = [8.0, 0.0, 2.0]
    var ambiguous: Dictionary = ProjectionScript.resolve_authenticated_candidates(
        [fallback, divergent], witnesses, true)
    if bool(ambiguous.get("ok", false)) \
            or ambiguous.get("reason", "") != "legacy_generation_route_ambiguous":
        return _fail_bool("differing surviving routes were not ambiguous")

    var none: Dictionary = ProjectionScript.resolve_authenticated_candidates(
        [fallback], {"room_cell_markers": [{"room_id": "missing", "cell": [9, 9]}]}, true)
    if bool(none.get("ok", false)) \
            or none.get("reason", "") != "legacy_layout_unreconstructable":
        return _fail_bool("zero surviving candidates used wrong rejection")
    return true


func _validate_native_route_gate() -> bool:
    var valid_facts: Dictionary = {
        "platform": "Windows",
        "binary_path": "res://addons/derelict/bin/win64/derelict_godot.dll",
        "binary_sha256": "3279db6338e7af6b54cb4e8c8886d39bdffec73549a25149a05a87d9ebdb8798",
        "class_registered": true,
        "generator_version": 2,
    }
    var accepted: Dictionary = ProjectionScript.authenticate_native_route_facts(valid_facts)
    if not bool(accepted.get("ok", false)):
        return _fail_bool("exact native-v2 facts rejected")
    var mismatch: Dictionary = valid_facts.duplicate(true)
    mismatch.binary_sha256 = "0279db6338e7af6b54cb4e8c8886d39bdffec73549a25149a05a87d9ebdb8798"
    var mismatch_result: Dictionary = ProjectionScript.authenticate_native_route_facts(mismatch)
    if bool(mismatch_result.get("ok", false)) \
            or mismatch_result.get("reason", "") != "legacy_generation_route_unavailable":
        return _fail_bool("native hash mismatch did not reject as unavailable")
    var wrong_version: Dictionary = valid_facts.duplicate(true)
    wrong_version.generator_version = 3
    var version_result: Dictionary = ProjectionScript.authenticate_native_route_facts(wrong_version)
    if bool(version_result.get("ok", false)) \
            or version_result.get("reason", "") != "legacy_generation_route_unavailable":
        return _fail_bool("native version mismatch did not reject as unavailable")
    var runtime_status: Dictionary = ProjectionScript.native_route_status()
    if OS.get_name() == "Windows":
        if not bool(runtime_status.get("ok", false)):
            return _fail_bool("checked-in Windows native-v2 route did not authenticate")
        var route_result: Dictionary = ProjectionScript.project_procedural(
            _blueprint(17, 1, 2), {})
        if bool(route_result.get("ok", false)) \
                or route_result.get("reason", "") != "legacy_generation_route_ambiguous":
            return _fail_bool("differing real fallback/native projections were not ambiguous")
    elif bool(runtime_status.get("ok", false)) \
            or runtime_status.get("reason", "") != "legacy_generation_route_unavailable":
        return _fail_bool("unsupported platform claimed native-v2 availability")
    return true


func _validate_native_reference_outputs() -> bool:
    if OS.get_name() != "Windows":
        return true
    var cases: Array[Dictionary] = [
        {
            "blueprint": _blueprint(17, 1, 2),
            "projection": {
                "airlock": {
                    "position": [26.0, 0.0, 34.0], "facing": [1.0, 0.0, 0.0],
                    "type": "airlock", "size_class": 1, "condition": "broken",
                },
                "hangar": {},
            },
        },
        {
            "blueprint": _blueprint(104729, 2, 1, "dead_fleet", "normal"),
            "projection": {
                "airlock": {
                    "position": [46.0, 0.0, 42.0], "facing": [1.0, 0.0, 0.0],
                    "type": "airlock", "size_class": 1, "condition": "intact",
                },
                "hangar": {
                    "type": "hangar", "slot_count": 4, "slot_size_class": 2,
                    "slot_anchors": [
                        [68.0, 0.0, 20.0], [76.0, 0.0, 20.0],
                        [72.0, 0.0, 24.0], [68.0, 0.0, 28.0],
                    ],
                },
            },
        },
        {
            "blueprint": _blueprint(-73, 0, 0, "breach_field", "hard"),
            "projection": {
                "airlock": {
                    "position": [38.0, 0.0, 26.0], "facing": [1.0, 0.0, 0.0],
                    "type": "airlock", "size_class": 1, "condition": "intact",
                },
                "hangar": {
                    "type": "hangar", "slot_count": 4, "slot_size_class": 2,
                    "slot_anchors": [
                        [12.0, 0.0, 16.0], [20.0, 0.0, 16.0],
                        [16.0, 0.0, 20.0], [12.0, 0.0, 24.0],
                    ],
                },
            },
        },
    ]
    for case_v in cases:
        var case: Dictionary = case_v
        var result: Dictionary = ProjectionScript.project_native_candidate(case.blueprint)
        if not bool(result.get("ok", false)) \
                or result.candidate.projection != case.projection:
            return _fail_bool("native-v2 projection differs from pinned capture")
    return true


func _validate_malformed_inputs() -> bool:
    var valid_blueprint: Dictionary = _blueprint(17, 1, 2, "breach_field", "hard")
    var source_text: String = JSON.stringify(valid_blueprint, "", true, true)
    var witnesses: Dictionary = {}
    var witness_text: String = JSON.stringify(witnesses, "", true, true)
    ProjectionScript.project_fallback_candidate(valid_blueprint, witnesses)
    if JSON.stringify(valid_blueprint, "", true, true) != source_text \
            or JSON.stringify(witnesses, "", true, true) != witness_text:
        return _fail_bool("projection mutated source inputs")

    var malformed: Array = [
        {},
        {"size": 1, "condition": 2, "seed_value": INF,
            "room_count_range": {"min": 4, "max": 8}},
        {"size": 1.5, "condition": 2, "seed_value": 17,
            "room_count_range": {"min": 4, "max": 8}},
        {"size": 1, "condition": 2, "seed_value": 17,
            "room_count_range": {"min": 9, "max": 4}},
        {"size": 1, "condition": 2, "seed_value": 17,
            "room_count_range": {"min": 4, "max": 8},
            "generation_context_v1": {"biome": "", "difficulty": "hard"}},
    ]
    for blueprint_v in malformed:
        var result: Dictionary = ProjectionScript.project_fallback_candidate(blueprint_v, {})
        if bool(result.get("ok", false)) or result.get("reason", "") != "invalid_legacy_blueprint":
            return _fail_bool("malformed blueprint accepted: %s" % str(blueprint_v))

    var candidate: Dictionary = {
        "route": "fallback-gdscript-v6",
        "template_id": "compact",
        "projection": _candidate_projection([4.0, 0.0, 2.0]),
        "rooms": [{"id": "dock_01", "role": "dock", "deck": 0, "cells": [[1, 0]]}],
    }
    for invalid_witness in [
        {"route": "fallback"},
        {"dock_edges": [{"port_type": "airlock", "slot_index": 0}]},
        {"hangar_summary": {"slot_count": 2, "slot_size_class": 2, "slots": [""]}},
        {"room_cell_markers": [{"room_id": "dock_01", "cell": [INF, 0]}]},
    ]:
        var result: Dictionary = ProjectionScript.resolve_authenticated_candidates(
            [candidate], invalid_witness, true)
        if bool(result.get("ok", false)) or result.get("reason", "") != "invalid_legacy_layout_witnesses":
            return _fail_bool("malformed witness accepted: %s" % str(invalid_witness))
    var nonfinite_candidate: Dictionary = candidate.duplicate(true)
    nonfinite_candidate.projection.airlock.position = [INF, 0.0, 0.0]
    var nonfinite_result: Dictionary = ProjectionScript.resolve_authenticated_candidates(
        [nonfinite_candidate], {}, true)
    if bool(nonfinite_result.get("ok", false)) \
            or nonfinite_result.get("reason", "") != "invalid_legacy_layout_candidate":
        return _fail_bool("nonfinite candidate projection accepted")
    var unknown_route: Dictionary = candidate.duplicate(true)
    unknown_route.route = "guessed-route"
    var route_result: Dictionary = ProjectionScript.resolve_authenticated_candidates(
        [unknown_route], {}, true)
    if bool(route_result.get("ok", false)) \
            or route_result.get("reason", "") != "invalid_legacy_layout_candidate":
        return _fail_bool("unknown historical candidate route accepted")
    var malformed_airlock: Dictionary = candidate.projection.airlock.duplicate(true)
    malformed_airlock.position = [0.0, NAN, 0.0]
    var transform_result: Dictionary = ProjectionScript.compute_mobile_root_transform(
        malformed_airlock, candidate.projection.airlock)
    if bool(transform_result.get("ok", false)) \
            or transform_result.get("reason", "") != "invalid_legacy_airlock":
        return _fail_bool("nonfinite dock transform input accepted")
    return true


func _validate_fallback_replay() -> bool:
    # Literal expectations are captured from c51bcac historical sources, not
    # from the projector. They cover context-free legacy selection and the
    # production extended pool with distinct sizes, conditions, and seeds.
    var cases: Array[Dictionary] = [
        {
            "blueprint": _blueprint(17, 1, 2),
            "template_id": "bifurcated",
            "projection": {
                "airlock": {
                    "position": [2.0, 0.0, 2.0], "facing": [1.0, 0.0, 0.0],
                    "type": "airlock", "size_class": 1, "condition": "broken",
                },
                "hangar": {},
            },
        },
        {
            "blueprint": _blueprint(104729, 2, 1, "dead_fleet", "normal"),
            "template_id": "hangar_wing",
            "projection": {
                "airlock": {
                    "position": [4.0, 0.0, 2.0], "facing": [1.0, 0.0, 0.0],
                    "type": "airlock", "size_class": 1, "condition": "intact",
                },
                "hangar": {
                    "type": "hangar", "slot_count": 3, "slot_size_class": 2,
                    "slot_anchors": [
                        [12.0, 0.0, 0.0], [12.0, 0.0, 8.0], [16.0, 0.0, 4.0],
                    ],
                },
            },
        },
        {
            "blueprint": _blueprint(-73, 0, 0, "breach_field", "hard"),
            "template_id": "compact",
            "projection": {
                "airlock": {
                    "position": [2.0, 0.0, 2.0], "facing": [1.0, 0.0, 0.0],
                    "type": "airlock", "size_class": 1, "condition": "intact",
                },
                "hangar": {
                    "type": "hangar", "slot_count": 2, "slot_size_class": 2,
                    "slot_anchors": [[8.0, 0.0, 4.0], [12.0, 0.0, 4.0]],
                },
            },
        },
    ]
    # The expected rows are filled by the independent pinned-reference capture
    # before GREEN qualification. Empty placeholders deliberately keep RED.
    var mismatch_found: bool = false
    for case_v in cases:
        var case: Dictionary = case_v
        var result: Dictionary = ProjectionScript.project_fallback_candidate(
            case.blueprint, {})
        if not bool(result.get("ok", false)):
            return _fail_bool("valid fallback projection rejected")
        var candidate: Dictionary = result.candidate
        if candidate.get("template_id", "") != case.template_id \
                or candidate.projection != case.projection:
            mismatch_found = true
    if mismatch_found:
        return _fail_bool("fallback projection differs from pinned capture")
    return true


func _blueprint(
        seed_value: int, size: int, condition: int,
        biome: String = "", difficulty: String = "") -> Dictionary:
    var ranges: Array = [[2, 4], [4, 8], [8, 12]]
    var value: Dictionary = {
        "size": size, "condition": condition, "seed_value": seed_value,
        "room_count_range": {"min": ranges[size][0], "max": ranges[size][1]},
    }
    if not biome.is_empty() or not difficulty.is_empty():
        value["generation_context_v1"] = {"biome": biome, "difficulty": difficulty}
    return value


func _candidate_projection(airlock_position: Array) -> Dictionary:
    return {
        "airlock": {
            "position": airlock_position.duplicate(), "facing": [1.0, 0.0, 0.0],
            "type": "airlock", "size_class": 1, "condition": "intact",
        },
        "hangar": {},
    }


func _fail_bool(message: String) -> bool:
    push_error("R10-A WORLD6 LAYOUT PROJECTION FAIL: %s" % message)
    quit(1)
    return false
