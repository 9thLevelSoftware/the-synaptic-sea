extends SceneTree

const DockEndpointAuthoringScript := preload("res://scripts/procgen/dock_endpoint_authoring.gd")
const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const ModularSocketCatalogScript := preload("res://scripts/procgen/modular_socket_catalog.gd")
const DockingManagerScript := preload("res://scripts/systems/docking_manager.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const ENDPOINT_KEYS := [
    "endpoint_id", "port_id", "portal_id", "type", "size_class", "room_id",
    "deck", "edge_cell", "edge_direction", "structural_edge_key",
    "target_module_id", "structural_module_id", "local_position", "outward_normal",
    "threshold_nav_node_id", "interior_nav_node_id",
    "threshold_clearance_point_local", "interior_clearance_point_local",
    "join_piece_placement_ids", "join_collision_fingerprint",
]

func _initialize() -> void:
    var kit: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH))
    var projection: Dictionary = (kit as Dictionary).get(
        "dock_collision_projection_v1", {}) if kit is Dictionary else {}
    var lifeboat: Dictionary = LifeBoatBuilderScript.build_layout()
    var loader_negative_label: String = _loader_negative_label()
    if not loader_negative_label.is_empty():
        _run_public_loader_negative(
            loader_negative_label, lifeboat, kit as Dictionary)
        return
    if not _check_layout(lifeboat, "lifeboat"):
        return
    if not _check_half_span_fixtures():
        return
    if not _check_loader_endpoint_mutation_rejections(lifeboat, kit as Dictionary):
        return
    if not _check_loaded_structural_and_endpoint_identity(kit as Dictionary, lifeboat):
        return
    if not _check_compiler_roundtrip_and_authority(lifeboat, projection):
        return
    var spawn: Variant = lifeboat.get("initial_player_spawn_v1", null)
    if not spawn is Dictionary or (spawn as Dictionary).keys().size() != 5:
        _fail("fixed lifeboat initial spawn is missing or non-strict")
        return
    for key in ["spawn_id", "owner_ship_id", "room_id", "nav_node_id", "local_position"]:
        if not (spawn as Dictionary).has(key):
            _fail("initial spawn missing %s" % key)
            return
    if str((spawn as Dictionary).get("owner_ship_id", "")) != "lifeboat":
        _fail("initial spawn owner is not lifeboat")
        return

    var home_source: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/procgen/golden/coherent_ship_001/layout.json"))
    if not home_source is Dictionary:
        _fail("home source layout is not a Dictionary")
        return
    var home_documents: Dictionary = ShipGeneratorScript.new()._prepare_layout_documents(
        home_source as Dictionary)
    if not bool(home_documents.get("ok", false)):
        _fail("production home materialization failed: %s" % str(
            home_documents.get("reason", "")))
        return
    var home: Dictionary = home_documents.get("layout", {}) as Dictionary
    if not _check_layout(home, "home"):
        return

    var lifeboat_port: Dictionary = DockPortsScript.for_lifeboat(lifeboat)
    var home_port: Dictionary = DockPortsScript.for_derelict(home)
    if lifeboat_port.is_empty() or home_port.is_empty():
        _fail("registered port resolution failed")
        return
    if (lifeboat_port.get("facing", Vector3.ZERO) as Vector3).dot(
            home_port.get("facing", Vector3.ZERO) as Vector3) != 0.0:
        # Local authoring directions need not oppose until alignment, but the fixed
        # lifeboat must use a different exterior edge than its internal west seam.
        _fail("fixed lifeboat still authors its internal west seam")
        return
    if not _check_native_pair_selection(lifeboat):
        return
    if not _check_real_overlap_pair_fallback(lifeboat, projection):
        return
    print("R10A DOCK ENDPOINT CONTRACT PASS")
    quit(0)


func _check_half_span_fixtures() -> bool:
    var square := _fixture_layout([
        {"id": "square", "deck": 0, "role": "room", "room_role": "room",
            "cells": [[0, 0, 0]]},
    ])
    var square_plan: Dictionary = _validated_fixture_plan(square, "one-cell square")
    if square_plan.is_empty() or _module_count(square_plan, "wall_outer_corner") != 4 \
            or not _half_spans_are_bijective(square_plan):
        return _reject("one-cell square did not compile to four exact outer corners")

    var concave_l := _fixture_layout([
        {"id": "concave", "deck": 0, "role": "room", "room_role": "room",
            "cells": [[0, 0, 0], [1, 0, 0], [0, 1, 0]]},
    ])
    var l_plan: Dictionary = _validated_fixture_plan(concave_l, "concave L")
    if l_plan.is_empty() or _module_count(l_plan, "wall_inner_corner") < 1 \
            or not _half_spans_are_bijective(l_plan):
        return _reject("concave L did not retain an exact inner-corner junction")

    var true_t := _fixture_layout([
        {"id": "north", "deck": 0, "role": "room", "room_role": "room",
            "cells": [[0, 0, 0], [1, 0, 0]]},
        {"id": "southwest", "deck": 0, "role": "room", "room_role": "room",
            "cells": [[0, 1, 0]]},
    ])
    var t_plan: Dictionary = _validated_fixture_plan(true_t, "three-ray T")
    if t_plan.is_empty() or _module_count(t_plan, "wall_t_junction") < 1 \
            or not _half_spans_are_bijective(t_plan):
        return _reject("true three-ray topology did not retain an exact T junction")

    var portal := _portal_singleton_fixture()
    var portal_plan: Dictionary = _validated_fixture_plan(portal, "portal singleton")
    if portal_plan.is_empty() or not _half_spans_are_bijective(portal_plan):
        return _reject("portal singleton half-span coverage failed")
    var residuals: Array[Dictionary] = []
    for placement_variant in portal_plan.get("placements", []):
        var placement: Dictionary = placement_variant
        if str(placement.get("anchor_kind", "")) == "half_span":
            residuals.append(placement)
    if residuals.size() != 2:
        return _reject("portal singleton did not emit two aperture-adjacent residual halves")
    for residual in residuals:
        if residual.get("scale") != Vector3(0.5, 1.0, 1.0) \
                or (residual.get("covered_half_spans", []) as Array).size() != 1:
            return _reject("portal singleton residual is not a strict scaled half-span")
    if not _scaled_socket_positions_match_half_span(residuals[0]):
        return _reject("scaled residual socket positions do not reach its half-span endpoints")

    if not _half_span_tampering_rejects(square, square_plan):
        return _reject("independent validator accepted tampered half-span authority")
    return true


func _fixture_layout(rooms: Array) -> Dictionary:
    return {
        "schema_version": "ship-layout-v1",
        "kit_id": "ship_structural_v0",
        "rooms": rooms,
        "portals": [],
        "vertical_connections": [],
        "critical_path": [],
    }


func _portal_singleton_fixture() -> Dictionary:
    var layout := _fixture_layout([
        {"id": "airlock", "deck": 0, "role": "airlock", "room_role": "airlock",
            "cells": [[0, 0, 0]]},
    ])
    layout["portals"] = [{
        "id": "singleton_portal", "from_room": "airlock", "to_room": "",
        "from_cell": [0, 0, 0], "to_cell": [0, -1, 0],
        "edge_direction": "north", "exterior": true, "state": "DOOR",
        "module_id": "doorway_frame_open_1x1",
    }]
    layout["dock_navigation_nodes_v1"] = [
        {"node_id": "singleton-threshold", "kind": "threshold",
            "portal_id": "singleton_portal", "room_id": "airlock", "deck": 0,
            "cell": [0, 0, 0], "structural_placement_id": "edge:0|h|-1|0",
            "local_position": [0.0, 0.0, -2.0]},
        {"node_id": "singleton-interior", "kind": "interior",
            "portal_id": "singleton_portal", "room_id": "airlock", "deck": 0,
            "cell": [0, 0, 0], "structural_placement_id": "floor:0|0|0",
            "local_position": [0.0, 0.0, 0.0]},
    ]
    return layout


func _validated_fixture_plan(layout: Dictionary, label: String) -> Dictionary:
    var plan: Dictionary = StructuralEdgeCompilerScript.new().compile(layout)
    var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(plan, layout)
    if not bool(verdict.get("ok", false)):
        _fail("%s structural validation failed: %s" % [label,
            JSON.stringify(verdict.get("errors", []))])
        return {}
    return plan


func _module_count(plan: Dictionary, module_id: String) -> int:
    var count: int = 0
    for placement_variant in plan.get("placements", []):
        if placement_variant is Dictionary and str((placement_variant as Dictionary).get(
                "module_id", "")) == module_id:
            count += 1
    return count


func _half_spans_are_bijective(plan: Dictionary) -> bool:
    var counts: Dictionary = {}
    for placement_variant in plan.get("placements", []):
        if not placement_variant is Dictionary:
            return false
        for span_variant in (placement_variant as Dictionary).get("covered_half_spans", []):
            var span_id: String = str(span_variant)
            counts[span_id] = int(counts.get(span_id, 0)) + 1
    for edge_variant in (plan.get("edges", {}) as Dictionary).values():
        if not edge_variant is Dictionary:
            return false
        var edge: Dictionary = edge_variant
        if str(edge.get("kind", "")) != "SOLID":
            continue
        var spans: Array = edge.get("half_span_ids", []) as Array
        var bindings: Dictionary = edge.get("half_span_placement_ids", {}) as Dictionary
        if spans.size() != 2 or bindings.size() != 2:
            return false
        for span_variant in spans:
            var span_id: String = str(span_variant)
            if int(counts.get(span_id, 0)) != 1 or str(bindings.get(span_id, "")).is_empty():
                return false
    return true


func _half_span_tampering_rejects(layout: Dictionary, plan: Dictionary) -> bool:
    var vertex_index: int = -1
    for index in range((plan.get("placements", []) as Array).size()):
        var placement: Dictionary = plan.placements[index]
        if str(placement.get("anchor_kind", "")) == "vertex" \
                and (placement.get("edge_keys", []) as Array).size() >= 2:
            vertex_index = index
            break
    if vertex_index < 0:
        return false
    var mutations: Array[Dictionary] = []
    var missing: Dictionary = plan.duplicate(true)
    missing.placements[vertex_index].covered_half_spans.remove_at(0)
    mutations.append(missing)
    var duplicate: Dictionary = plan.duplicate(true)
    var duplicate_span: String = str(duplicate.placements[vertex_index].covered_half_spans[0])
    duplicate.placements[(vertex_index + 1) % duplicate.placements.size()].covered_half_spans.append(duplicate_span)
    mutations.append(duplicate)
    var extra: Dictionary = plan.duplicate(true)
    extra.placements[vertex_index].covered_half_spans.append("0|h|999|999@a")
    mutations.append(extra)
    var scale: Dictionary = plan.duplicate(true)
    scale.placements[vertex_index].scale = Vector3(0.5, 1.0, 1.0)
    var scale_verdict: Dictionary = StructuralPlanValidatorScript.new().validate(
        scale, layout)
    var projection_rejection: bool = false
    for error_variant in scale_verdict.get("errors", []):
        projection_rejection = projection_rejection or str(error_variant).find(
            "projection") >= 0
    if bool(scale_verdict.get("ok", false)) or not projection_rejection:
        return false
    var secondary: Dictionary = plan.duplicate(true)
    secondary.placements[vertex_index].edge_keys[1] = "0|h|999|999"
    mutations.append(secondary)
    for mutation in mutations:
        if bool(StructuralPlanValidatorScript.new().validate(
                mutation, layout).get("ok", false)):
            return false
    return true


func _scaled_socket_positions_match_half_span(placement: Dictionary) -> bool:
    var catalog = ModularSocketCatalogScript.new()
    if not catalog.load_kit("ship_structural_v0"):
        return false
    var sockets: Array = catalog.sockets_of("wall_straight_1x1")
    if sockets.size() < 2:
        return false
    var position: Vector3 = _as_vector3(placement.get("position", []))
    var yaw: float = float(placement.get("yaw_degrees", 0.0))
    var scale: Vector3 = _as_vector3(placement.get("scale", []))
    var first: Vector3 = catalog.world_socket_position(
        position, yaw, catalog.socket_local_position(sockets[0]), scale)
    var second: Vector3 = catalog.world_socket_position(
        position, yaw, catalog.socket_local_position(sockets[1]), scale)
    if not is_equal_approx(first.distance_to(second), 2.0):
        return false
    var anchor: Array = placement.get("anchor_vertex", []) as Array
    if anchor.size() != 3:
        return false
    var vertex := Vector3(float(anchor[0]) * 4.0 - 2.0,
        float(anchor[2]) * 4.0, float(anchor[1]) * 4.0 - 2.0)
    var edge_key: String = str(placement.get("edge_key", ""))
    var edge: Dictionary = (StructuralEdgeCompilerScript.new().compile(
        _portal_singleton_fixture()).get("edges", {}) as Dictionary).get(edge_key, {})
    var edge_center: Vector3 = _as_vector3(edge.get("position", []))
    return (first == vertex and second == edge_center) \
        or (second == vertex and first == edge_center)


func _check_loaded_structural_and_endpoint_identity(
        kit: Dictionary, lifeboat: Dictionary) -> bool:
    var square := _fixture_layout([
        {"id": "square", "deck": 0, "role": "room", "room_role": "room",
            "cells": [[0, 0, 0]]},
    ])
    square["prototype"] = {"start_room": "square", "goal_room": "square"}
    var plan: Dictionary = _validated_fixture_plan(square, "loaded one-cell square")
    if plan.is_empty():
        return false
    square["structural_plan"] = plan
    square["structural_plan_validated"] = true
    var gameplay: Dictionary = {
        "start_room": "square",
        "goal_room": "square",
        "objectives": [{"id": "square:reach", "sequence": 1,
            "room_id": "square", "approach_cell": [0, 0, 0], "kind": "single"}],
    }
    var loader = GeneratedShipLoaderScript.new()
    loader.name = "R10HalfSpanIdentityLoader"
    get_root().add_child(loader)
    if not loader.load_from_documents(square, kit, gameplay, false):
        loader.free()
        return _reject("production loader rejected the vertex identity fixture")
    var vertex_record: Dictionary = {}
    for placement_variant in plan.get("placements", []):
        if placement_variant is Dictionary \
                and str((placement_variant as Dictionary).get("anchor_kind", "")) == "vertex" \
                and ((placement_variant as Dictionary).get("edge_keys", []) as Array).size() >= 2:
            vertex_record = placement_variant as Dictionary
            break
    if vertex_record.is_empty():
        loader.free()
        return _reject("loaded identity fixture has no multi-edge vertex placement")
    var placement_id: String = str(vertex_record.get("placement_id", ""))
    var module_key: String = "edge/%s" % placement_id
    var wrapper: Node3D = _find_wrapper_by_placement(loader.structural_root, placement_id)
    var wrapper_count: int = _count_wrappers_by_module_key(
        loader.structural_root, module_key)
    if wrapper == null or wrapper_count != 1 \
            or str(wrapper.get_meta("module_key", "")) != module_key \
            or wrapper.get_meta("structural_edge_keys", []) != vertex_record.get("edge_keys", []) \
            or wrapper.get_meta("structural_half_spans", []) \
                != vertex_record.get("covered_half_spans", []) \
            or wrapper.scale != _as_vector3(vertex_record.get("scale", Vector3.ONE)):
        loader.free()
        return _reject("multi-edge placement did not materialize as one exact wrapper identity")
    var bound_spans: int = 0
    for edge_key_variant in vertex_record.get("edge_keys", []):
        var edge: Dictionary = (plan.get("edges", {}) as Dictionary).get(
            str(edge_key_variant), {}) as Dictionary
        for bound_placement_variant in (edge.get(
                "half_span_placement_ids", {}) as Dictionary).values():
            if str(bound_placement_variant) == placement_id:
                bound_spans += 1
    if bound_spans != (vertex_record.get("covered_half_spans", []) as Array).size():
        loader.free()
        return _reject("secondary edge bindings did not resolve to the physical vertex wrapper")
    var target: Dictionary = loader.inspect_rebuild_target(module_key)
    var descriptor: Dictionary = target.get("original_descriptor", {}) as Dictionary
    var edge_binding: Dictionary = descriptor.get("edge_binding", {}) as Dictionary
    if not bool(target.get("ok", false)) \
            or str(descriptor.get("placement_id", "")) != placement_id \
            or edge_binding.get("edge_keys", []) != vertex_record.get("edge_keys", []) \
            or edge_binding.get("covered_half_spans", []) \
                != vertex_record.get("covered_half_spans", []):
        loader.free()
        return _reject("controller target lost multi-edge placement authority")
    var integrity_map: RefCounted = loader.get_module_integrity_map()
    if not bool(integrity_map.call("has_module", module_key)) \
            or str(integrity_map.call("apply_damage", module_key, 0.3,
                str(vertex_record.get("module_id", "")))) != "damaged" \
            or not loader.apply_module_integrity_state(module_key) \
            or str(wrapper.get_meta("integrity_state", "")) != "damaged":
        loader.free()
        return _reject("physical vertex controller target did not update its one wrapper")
    loader.free()

    # A complete production endpoint document, rather than the compiler-only
    # singleton portal fixture, must cross the loader publication boundary.
    var portal: Dictionary = lifeboat.duplicate(true)
    var portal_gameplay: Dictionary = {
        "start_room": "airlock_01",
        "goal_room": "airlock_01",
        "objectives": [{"id": "airlock:reach", "sequence": 1,
            "room_id": "airlock_01", "approach_cell": [0, 0, 0], "kind": "single"}],
    }
    var portal_loader = GeneratedShipLoaderScript.new()
    portal_loader.name = "R10ScaledResidualLoader"
    var loaded_events: Array[Dictionary] = []
    portal_loader.ship_loaded.connect(func(summary: Dictionary) -> void:
        loaded_events.append(summary.duplicate(true)))
    get_root().add_child(portal_loader)
    if not portal_loader.load_from_documents(
            portal, kit, portal_gameplay, false):
        portal_loader.free()
        return _reject("production loader rejected the fixed endpoint fixture")
    var published_layout: Dictionary = portal_loader.get_layout_copy()
    if not portal_loader.has_loaded_ship() or loaded_events.size() != 1 \
            or published_layout.get("boarding_endpoints_v1", null) \
                != portal.get("boarding_endpoints_v1", null) \
            or published_layout.get("initial_player_spawn_v1", null) \
                != portal.get("initial_player_spawn_v1", null):
        portal_loader.free()
        return _reject("production loader published incomplete endpoint authority")
    portal_loader.free()
    return true


func _find_wrapper_by_placement(node: Node, placement_id: String) -> Node3D:
    if node is Node3D and str(node.get_meta(
            "structural_placement_id", "")) == placement_id:
        return node as Node3D
    for child in node.get_children():
        var found: Node3D = _find_wrapper_by_placement(child, placement_id)
        if found != null:
            return found
    return null


func _count_wrappers_by_module_key(node: Node, module_key: String) -> int:
    var count: int = 1 if node is Node3D and str(node.get_meta(
        "module_key", "")) == module_key else 0
    for child in node.get_children():
        count += _count_wrappers_by_module_key(child, module_key)
    return count


func _check_compiler_roundtrip_and_authority(
        lifeboat: Dictionary, projection: Dictionary) -> bool:
    var endpoint: Dictionary = lifeboat.boarding_endpoints_v1[0]
    var exterior_portals: Array[Dictionary] = []
    for portal_variant in lifeboat.get("portals", []):
        if portal_variant is Dictionary and bool((portal_variant as Dictionary).get(
                "exterior", false)):
            exterior_portals.append(portal_variant as Dictionary)
    if exterior_portals.size() != 1:
        return _reject("fixed lifeboat did not author exactly one explicit exterior portal")
    var exterior: Dictionary = exterior_portals[0]
    if str(exterior.get("id", "")) != str(endpoint.get("portal_id", "")) \
            or not str(exterior.get("to_room", "missing")).is_empty():
        return _reject("explicit exterior portal identity/form does not match endpoint")
    var recompiled: Dictionary = StructuralEdgeCompilerScript.new().compile(lifeboat)
    var plan_verdict: Dictionary = StructuralPlanValidatorScript.new().validate(
        recompiled, lifeboat)
    if not bool(plan_verdict.get("ok", false)) \
            or JSON.stringify(recompiled) != JSON.stringify(lifeboat.structural_plan):
        return _reject("explicit exterior portal did not round-trip through compiler")
    var ordinary_one_sided: Dictionary = lifeboat.duplicate(true)
    ordinary_one_sided.portals = ordinary_one_sided.portals.duplicate(true)
    for index in range(ordinary_one_sided.portals.size()):
        if str(ordinary_one_sided.portals[index].get("id", "")) == str(
                endpoint.get("portal_id", "")):
            ordinary_one_sided.portals[index].erase("exterior")
    var ordinary_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(
        ordinary_one_sided)
    if bool(StructuralPlanValidatorScript.new().validate(
            ordinary_plan, ordinary_one_sided).get("ok", false)):
        return _reject("ordinary one-sided portal did not fail closed")

    var mutations: Array[Dictionary] = []
    for field in ["endpoint_id", "port_id", "portal_id", "room_id",
            "structural_edge_key", "target_module_id", "structural_module_id",
            "threshold_nav_node_id", "interior_nav_node_id"]:
        var changed: Dictionary = lifeboat.duplicate(true)
        changed.boarding_endpoints_v1[0][field] = "spoofed"
        mutations.append({"label": "spoofed_%s" % field, "layout": changed})
    for field in ["deck", "edge_cell", "edge_direction", "local_position",
            "outward_normal"]:
        var changed: Dictionary = lifeboat.duplicate(true)
        changed.boarding_endpoints_v1[0][field] = 99 if field == "deck" else []
        mutations.append({"label": "wrong_%s" % field, "layout": changed})
    var unrelated_floor: Dictionary = lifeboat.duplicate(true)
    var unrelated_floor_id: String = ""
    for floor_variant in unrelated_floor.structural_plan.floor_placements:
        if str((floor_variant as Dictionary).get("placement_id", "")) != str(
                endpoint.join_piece_placement_ids[1]):
            unrelated_floor_id = str((floor_variant as Dictionary).get("placement_id", ""))
            break
    unrelated_floor.boarding_endpoints_v1[0].join_piece_placement_ids[1] = unrelated_floor_id
    unrelated_floor.boarding_endpoints_v1[0].join_collision_fingerprint = \
        DockEndpointAuthoringScript.join_collision_fingerprint(
            str(endpoint.join_piece_placement_ids[0]), unrelated_floor_id,
            "floor_1x1", projection)
    mutations.append({"label": "unrelated_floor_with_matching_fingerprint",
        "layout": unrelated_floor})
    var malformed_clearance: Dictionary = lifeboat.duplicate(true)
    malformed_clearance.boarding_endpoints_v1[0].interior_clearance_point_local = [NAN, 0.55, 0.0]
    mutations.append({"label": "nonfinite_clearance", "layout": malformed_clearance})
    var wrong_side: Dictionary = lifeboat.duplicate(true)
    wrong_side.boarding_endpoints_v1[0].interior_clearance_point_local = \
        wrong_side.boarding_endpoints_v1[0].threshold_clearance_point_local.duplicate()
    mutations.append({"label": "unseparated_clearance", "layout": wrong_side})
    for mutation in mutations:
        if bool(DockEndpointAuthoringScript.validate_layout(
                mutation.layout, projection).get("ok", false)):
            return _reject("authority mutation passed: %s" % str(mutation.label))

    var strict_mutations: Array[Dictionary] = []
    for value in [[0, 0, 99], [0.5, 0, 0], [false, 0, 0], ["0", 0, 0],
            [0, 0], [0, 0, 0, 0]]:
        var changed_cell: Dictionary = lifeboat.duplicate(true)
        changed_cell.boarding_endpoints_v1[0].edge_cell = value
        strict_mutations.append({"label": "strict_edge_cell_%s" % str(value),
            "layout": changed_cell, "reason": "endpoint_cell_authority"})
    for field in ["deck", "size_class"]:
        for value in [0.5, false, "0"]:
            var changed_scalar: Dictionary = lifeboat.duplicate(true)
            changed_scalar.boarding_endpoints_v1[0][field] = value
            strict_mutations.append({"label": "strict_%s_%s" % [field, str(value)],
                "layout": changed_scalar, "reason": "endpoint_scalar_authority"})
    for field in ["local_position", "outward_normal",
            "threshold_clearance_point_local", "interior_clearance_point_local"]:
        for value in [["0", 0.55, 0], [false, 0.55, 0], [0, 0.55, 0, 0]]:
            var changed_vector: Dictionary = lifeboat.duplicate(true)
            changed_vector.boarding_endpoints_v1[0][field] = value
            strict_mutations.append({"label": "strict_%s_%s" % [field, str(value)],
                "layout": changed_vector, "reason": (
                    "endpoint_normal" if field == "outward_normal" else
                    "endpoint_position" if field == "local_position" else
                    "endpoint_clearance_authority")})
    for value in [["0", 0.55, 0], [false, 0.55, 0], [0, 0.55, 0, 0]]:
        var changed_spawn: Dictionary = lifeboat.duplicate(true)
        changed_spawn.initial_player_spawn_v1.local_position = value
        strict_mutations.append({"label": "strict_spawn_position_%s" % str(value),
            "layout": changed_spawn, "reason": "spawn_authority"})
    for mutation in strict_mutations:
        var mutation_verdict: Dictionary = DockEndpointAuthoringScript.validate_layout(
            mutation.layout, projection)
        if bool(mutation_verdict.get("ok", false)) \
                or str(mutation_verdict.get("reason", "")) != str(mutation.reason):
            return _reject("strict authority mutation passed: %s" % str(mutation.label))

    var unauthorized: Dictionary = lifeboat.duplicate(true)
    unauthorized.erase("boarding_endpoints_v1")
    unauthorized.erase("initial_player_spawn_v1")
    unauthorized.portals = unauthorized.portals.filter(func(p: Variant) -> bool:
        return not (p is Dictionary and bool((p as Dictionary).get("exterior", false))))
    for room_variant in unauthorized.rooms:
        (room_variant as Dictionary)["role"] = "generic"
        (room_variant as Dictionary)["room_role"] = "generic"
    unauthorized["structural_plan"] = StructuralEdgeCompilerScript.new().compile(unauthorized)
    if bool(DockEndpointAuthoringScript.author_layout(
            unauthorized, true, projection).get("ok", false)):
        return _reject("layout without dock/airlock room authored an endpoint")
    return true

func _reject(reason: String) -> bool:
    _fail(reason)
    return false

func _check_layout(layout: Dictionary, label: String) -> bool:
    var kit: Variant = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH))
    var projection: Dictionary = (kit as Dictionary).get(
        "dock_collision_projection_v1", {}) if kit is Dictionary else {}
    var verdict: Dictionary = DockEndpointAuthoringScript.validate_layout(layout, projection)
    if not bool(verdict.get("ok", false)):
        _fail("%s endpoint validation failed: %s" % [label, str(verdict.get("reason", ""))])
        return false
    var endpoints: Variant = layout.get("boarding_endpoints_v1", null)
    if not endpoints is Array or (endpoints as Array).size() != 1:
        _fail("%s must have exactly one endpoint" % label)
        return false
    var endpoint: Dictionary = (endpoints as Array)[0]
    if endpoint.keys().size() != ENDPOINT_KEYS.size():
        _fail("%s endpoint is not strict" % label)
        return false
    for key in ENDPOINT_KEYS:
        if not endpoint.has(key):
            _fail("%s endpoint missing %s" % [label, key])
            return false
    if endpoint.get("threshold_clearance_point_local") == endpoint.get("interior_clearance_point_local"):
        _fail("%s clearance anchors are not distinct" % label)
        return false
    return true

func _as_vector3(value: Variant) -> Vector3:
    if value is Vector3:
        return value as Vector3
    if value is Array and (value as Array).size() >= 3:
        var parts: Array = value as Array
        return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
    return Vector3.INF


func _check_native_pair_selection(lifeboat: Dictionary) -> bool:
    if not ClassDB.class_exists("DerelictGenerator"):
        _fail("native generator unavailable for deterministic pair selection")
        return false
    var native = ClassDB.instantiate("DerelictGenerator")
    var params: Dictionary = {
        "archetype_id": "shuttle",
        "intactness_override": 2000,
    }
    var layout_variant: Variant = JSON.parse_string(str(
        native.export_layout_json(42, params, "ship_structural_v0")))
    if not layout_variant is Dictionary:
        _fail("native seed42 layout export invalid")
        return false
    var raw: Dictionary = (layout_variant as Dictionary).duplicate(true)
    if not ShipGeneratorScript.stamp_native_component_slot_contracts(raw):
        _fail("native seed42 component-slot stamp failed")
        return false
    var kit_variant: Variant = JSON.parse_string(
        FileAccess.get_file_as_string(KIT_PATH))
    var projection: Dictionary = (kit_variant as Dictionary).get(
        "dock_collision_projection_v1", {}) if kit_variant is Dictionary else {}
    var old_layout: Dictionary = raw.duplicate(true)
    var old_result: Dictionary = DockEndpointAuthoringScript.author_layout(
        old_layout, false, projection)
    var paired_layout: Dictionary = raw.duplicate(true)
    var paired_result: Dictionary = DockEndpointAuthoringScript.author_layout(
        paired_layout, false, projection, lifeboat)
    if not bool(old_result.get("ok", false)) \
            or not bool(paired_result.get("ok", false)):
        var discovery_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(raw)
        var baseline_edge: Dictionary = discovery_plan.get("edges", {}).get(
            "0|v|3|3", {}) as Dictionary
        var baseline_room: Dictionary = {}
        for room_variant in raw.get("rooms", []):
            if room_variant is Dictionary and str((room_variant as Dictionary).get(
                    "id", "")) == str(baseline_edge.get("owner_room", "")):
                baseline_room = room_variant as Dictionary
                break
        _fail("native seed42 authoring failed old=%s paired=%s baseline_edge=%s baseline_room=%s" % [
            JSON.stringify(old_result), JSON.stringify(paired_result),
            JSON.stringify(baseline_edge), JSON.stringify(baseline_room)])
        return false
    var old_endpoint: Dictionary = old_layout.boarding_endpoints_v1[0]
    var paired_endpoint: Dictionary = paired_layout.boarding_endpoints_v1[0]
    if str(old_endpoint.get("structural_edge_key", "")) != "0|h|7|8" \
            or str(paired_endpoint.get("structural_edge_key", "")) != "0|h|7|8" \
            or int(paired_result.get("candidate_count", 0)) != 4 \
            or int(paired_result.get("supporting_candidate_count", 0)) != 1 \
            or not (paired_result.get("candidate_pair_rejections", []) as Array).is_empty():
        _fail("native seed42 first supporting candidate order changed")
        return false
    var selected_pair: Dictionary = paired_result.get("selected_pair", {}) as Dictionary
    if not bool(selected_pair.get("ok", false)) \
            or str(selected_pair.get("reason", "")) != "ok" \
            or str(selected_pair.get("edge_key", "")) != "0|h|7|8":
        _fail("native seed42 selected pair was not independently geometry-valid")
        return false
    var host_port: Dictionary = DockPortsScript.for_derelict(paired_layout)
    var mobile_port: Dictionary = DockPortsScript.for_lifeboat(lifeboat)
    var preflight: Dictionary = DockingManagerScript.preflight_registered_pair(
        paired_layout, lifeboat, Transform3D.IDENTITY, host_port, mobile_port)
    if not bool(preflight.get("ok", false)) \
            or int(preflight.get("cross_hull_overlap_count", -1)) != 0 \
            or not bool(preflight.get("open_capsule_clear", false)):
        _fail("native seed42 first candidate failed live-equivalent pair preflight: %s" %
            JSON.stringify(preflight))
        return false
    return true


func _check_loader_endpoint_mutation_rejections(
        lifeboat: Dictionary, kit: Dictionary) -> bool:
    for mutation in _loader_authority_mutations(lifeboat, kit):
        var loader = GeneratedShipLoaderScript.new()
        loader.layout_doc = (mutation.get("layout", {}) as Dictionary).duplicate(true)
        loader.kit_doc = (mutation.get("kit", kit) as Dictionary).duplicate(true)
        var module_to_scene: Dictionary = loader._build_module_scene_map(
            loader.kit_doc, KIT_PATH)
        var verdict: Dictionary = loader._validate_loading_authority(module_to_scene)
        if bool(verdict.get("ok", false)):
            loader.free()
            return _reject("loader authority gate accepted mutation: %s" % str(
                mutation.label))
        loader.free()
    return true


func _loader_authority_mutations(
        lifeboat: Dictionary, kit: Dictionary) -> Array[Dictionary]:
    var mutations: Array[Dictionary] = []
    var spoofed_endpoint: Dictionary = lifeboat.duplicate(true)
    spoofed_endpoint.boarding_endpoints_v1[0].endpoint_id = "spoofed"
    mutations.append({"label": "spoofed_endpoint", "layout": spoofed_endpoint})
    var missing_endpoint: Dictionary = lifeboat.duplicate(true)
    missing_endpoint.erase("boarding_endpoints_v1")
    mutations.append({"label": "missing_endpoint_for_exterior_portal",
        "layout": missing_endpoint})
    var missing_authority: Dictionary = lifeboat.duplicate(true)
    missing_authority.erase("boarding_endpoints_v1")
    missing_authority.erase("initial_player_spawn_v1")
    mutations.append({"label": "missing_endpoint_and_spawn_for_fixed_lifeboat",
        "layout": missing_authority})
    var spoofed_spawn: Dictionary = lifeboat.duplicate(true)
    spoofed_spawn.initial_player_spawn_v1.nav_node_id = "spoofed"
    mutations.append({"label": "spoofed_spawn", "layout": spoofed_spawn})
    var missing_fixed_spawn: Dictionary = lifeboat.duplicate(true)
    missing_fixed_spawn.erase("initial_player_spawn_v1")
    mutations.append({"label": "missing_fixed_spawn", "layout": missing_fixed_spawn})
    var wrong_cell_deck: Dictionary = lifeboat.duplicate(true)
    wrong_cell_deck.boarding_endpoints_v1[0].edge_cell = [0, 0, 99]
    mutations.append({"label": "wrong_edge_cell_deck", "layout": wrong_cell_deck})
    for entry_variant in [
        ["edge_cell_fraction", "edge_cell", [0.5, 0, 0]],
        ["edge_cell_bool", "edge_cell", [false, 0, 0]],
        ["edge_cell_string", "edge_cell", ["0", 0, 0]],
        ["edge_cell_missing", "edge_cell", [0, 0]],
        ["edge_cell_extra", "edge_cell", [0, 0, 0, 0]],
        ["deck_fraction", "deck", 0.5],
        ["deck_bool", "deck", false],
        ["deck_string", "deck", "0"],
        ["size_fraction", "size_class", 1.5],
        ["size_bool", "size_class", true],
        ["size_string", "size_class", "1"],
        ["position_string", "local_position", ["0", 0.55, 0]],
        ["position_bool", "local_position", [false, 0.55, 0]],
        ["position_extra", "local_position", [0, 0.55, 0, 0]],
    ]:
        var entry: Array = entry_variant as Array
        var changed_endpoint: Dictionary = lifeboat.duplicate(true)
        changed_endpoint.boarding_endpoints_v1[0][str(entry[1])] = entry[2]
        mutations.append({"label": str(entry[0]), "layout": changed_endpoint})
    var spawn_string: Dictionary = lifeboat.duplicate(true)
    spawn_string.initial_player_spawn_v1.local_position = ["0", 0.55, 0]
    mutations.append({"label": "spawn_position_string", "layout": spawn_string})
    var stale_kit: Dictionary = kit.duplicate(true)
    var wrong_wrapper: String = ""
    for module_variant in stale_kit.get("modules", []):
        if module_variant is Dictionary and str((module_variant as Dictionary).get(
                "module_id", "")) == "wall_straight_1x1":
            wrong_wrapper = str((module_variant as Dictionary).get(
                "godot_wrapper_scene", ""))
            break
    for module_variant in stale_kit.get("modules", []):
        if module_variant is Dictionary and str((module_variant as Dictionary).get(
                "module_id", "")) == "doorway_frame_open_1x1":
            (module_variant as Dictionary)["godot_wrapper_scene"] = wrong_wrapper
            break
    var stale_projection: Dictionary = stale_kit.get(
        "dock_collision_projection_v1", {}) as Dictionary
    ((stale_projection.get("modules", {}) as Dictionary).get(
        "doorway_frame_open_1x1", {}) as Dictionary)["wrapper_scene"] = wrong_wrapper
    mutations.append({"label": "stale_live_wrapper", "layout": lifeboat,
        "kit": stale_kit})
    return mutations


func _loader_negative_label() -> String:
    for argument in OS.get_cmdline_user_args():
        var value: String = str(argument)
        if value.begins_with("--loader-negative="):
            return value.trim_prefix("--loader-negative=")
    return ""


func _run_public_loader_negative(
        label: String, lifeboat: Dictionary, kit: Dictionary) -> void:
    var selected: Dictionary = {}
    for mutation in _loader_authority_mutations(lifeboat, kit):
        if str(mutation.get("label", "")) == label:
            selected = mutation
            break
    if selected.is_empty():
        _fail("unknown loader negative label: %s" % label)
        return
    var gameplay: Dictionary = {
        "start_room": "airlock_01",
        "goal_room": "airlock_01",
        "objectives": [{"id": "airlock:reach", "sequence": 1,
            "room_id": "airlock_01", "approach_cell": [0, 0, 0], "kind": "single"}],
    }
    var loader = GeneratedShipLoaderScript.new()
    var loaded_events: Array[Dictionary] = []
    var failed_events: Array[String] = []
    loader.ship_loaded.connect(func(summary: Dictionary) -> void:
        loaded_events.append(summary.duplicate(true)))
    loader.load_failed.connect(func(reason: String) -> void:
        failed_events.append(reason))
    get_root().add_child(loader)
    var candidate_layout: Dictionary = (selected.get(
        "layout", {}) as Dictionary).duplicate(true)
    var candidate_kit: Dictionary = (selected.get(
        "kit", kit) as Dictionary).duplicate(true)
    var layout_before: Dictionary = candidate_layout.duplicate(true)
    var kit_before: Dictionary = candidate_kit.duplicate(true)
    var accepted: bool = loader.load_from_documents(
        candidate_layout, candidate_kit, gameplay, false)
    var rejected_without_publication: bool = not accepted \
        and loaded_events.is_empty() \
        and failed_events.size() == 1 \
        and not loader.has_loaded_ship() \
        and loader.get_layout_copy().is_empty() \
        and loader.get_child_count() == 0 \
        and candidate_layout == layout_before \
        and candidate_kit == kit_before
    loader.free()
    if not rejected_without_publication:
        _fail("public loader mutation did not fail atomically: %s" % label)
        return
    print("R10A LOADER NEGATIVE PASS label=%s" % label)
    quit(0)


func _check_real_overlap_pair_fallback(
        lifeboat: Dictionary, projection: Dictionary) -> bool:
    # The remote obstacle is real compiler-authored hull geometry placed where
    # the lifeboat intersects only when it uses the host's first (north) dock
    # candidate. The next (south) candidate stays clear. Keeping the obstacle
    # in a non-dock room prevents the fixture from adding candidate edges.
    var source := _fixture_layout([
        {"id": "dock", "deck": 0, "role": "dock", "room_role": "dock",
            "cells": [[0, 0, 0]]},
        {"id": "remote_obstacle", "deck": 0, "role": "room", "room_role": "room",
            "cells": [[-2, -2, 0]]},
    ])
    var paired: Dictionary = source.duplicate(true)
    var paired_result: Dictionary = DockEndpointAuthoringScript.author_layout(
        paired, false, projection, lifeboat)
    if not bool(paired_result.get("ok", false)):
        return _reject("real-overlap fixture did not author a fallback endpoint")
    var fallback_endpoint: Dictionary = paired.boarding_endpoints_v1[0]
    if str(fallback_endpoint.get("structural_edge_key", "")) != "0|h|0|0" \
            or int(paired_result.get("candidate_count", 0)) != 4 \
            or int(paired_result.get("supporting_candidate_count", 0)) != 2 \
            or not (paired_result.get("supporting_rejections", []) as Array).is_empty():
        return _reject("real-overlap fixture candidate ordering changed")
    var rejections: Array = paired_result.get("candidate_pair_rejections", []) as Array
    if rejections.size() != 1 or not rejections[0] is Dictionary:
        return _reject("real-overlap fixture did not record exactly one pair rejection")
    var rejection: Dictionary = rejections[0] as Dictionary
    var overlaps: Array = rejection.get("overlaps", []) as Array
    if str(rejection.get("reason", "")) != "candidate_cross_hull_overlap" \
            or str(rejection.get("edge_key", "")) != "0|h|-1|0" \
            or int(rejection.get("overlap_count", 0)) != overlaps.size() \
            or overlaps.is_empty():
        return _reject("real-overlap fixture rejected for the wrong reason")
    for overlap_variant in overlaps:
        if not overlap_variant is Dictionary:
            return _reject("real-overlap fixture emitted a malformed intersection")
        var size: Vector3 = _as_vector3((overlap_variant as Dictionary).get(
            "intersection_size", []))
        if not size.is_finite() or size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
            return _reject("real-overlap fixture did not prove positive volume")
    var lifeboat_port: Dictionary = DockPortsScript.for_lifeboat(lifeboat)
    var fallback_preflight: Dictionary = DockingManagerScript.preflight_registered_pair(
        paired, lifeboat, Transform3D.IDENTITY,
        DockPortsScript.for_derelict(paired), lifeboat_port)
    if not bool(fallback_preflight.get("ok", false)) \
            or int(fallback_preflight.get("cross_hull_overlap_count", -1)) != 0 \
            or not bool(fallback_preflight.get("open_capsule_clear", false)):
        return _reject("live preflight rejected the fixture's next clear candidate")
    return true

func _fail(reason: String) -> void:
    push_error("R10A DOCK ENDPOINT CONTRACT FAIL reason=%s" % reason)
    quit(1)
