extends SceneTree

const NavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
const REVISION := "layout-r17"
const FINGERPRINT := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const SHIP_ID := "ship/local"
const TARGET_EDGE := "0|v|1|0"
const TARGET_ID := "edge/0|v|1|0"
const PORTAL_EDGE := "0|h|1|2"
const PORTAL_ID := "portal/local-exit"

var _failed := false

func _init() -> void:
    _test_real_fixture_classification()
    _test_real_vertical_evaluation()
    _test_candidate_paths_and_immutability()
    _test_fail_closed_mutants()
    if _failed:
        quit(1)
        return
    print("STRUCTURAL REBUILD CANDIDATE NAV PASS")
    quit(0)


func _test_real_fixture_classification() -> void:
    _assert_fixture(
        "res://data/procgen/smoke/seed_000017/layout.json",
        84, 40, 0, 0,
        PackedStringArray(["0|h|3|5", "0|h|7|6", "0|v|3|4", "0|v|3|9"]))
    _assert_fixture(
        "res://data/procgen/golden/coherent_ship_001/layout.json",
        32, 40, 0, 1)
    _assert_fixture(
        "res://data/procgen/golden/coherent_ship_002/layout.json",
        42, 55, 1, 0)
    _assert_fixture(
        "res://data/procgen/golden/coherent_ship_003/layout.json",
        59, 70, 0, 2)


func _assert_fixture(
        path: String,
        internal_count: int,
        external_count: int,
        unresolved_count: int,
        vertical_count: int,
        expected_open_boundaries: PackedStringArray = PackedStringArray()) -> void:
    var layout: Dictionary = _load_json(path)
    if layout.is_empty():
        return
    var graph: RefCounted = NavGraphScript.new()
    graph.call("build_from_layout", layout)
    var classified: Dictionary = graph.call(
        "classify_structural_projection", layout["structural_plan"], layout)
    _expect(bool(classified.get("ok", false)), "%s classification rejected" % path)
    var counts := {"internal_pair": 0, "external_endpoint": 0, "unresolved": 0, "vertical_pair": 0}
    var open_boundaries := PackedStringArray()
    var plan_edges: Dictionary = (layout["structural_plan"] as Dictionary)["edges"]
    for row_variant in classified.get("rows", []):
        var row: Dictionary = row_variant
        var kind: String = str(row.get("classification", ""))
        counts[kind] = int(counts.get(kind, 0)) + 1
        if kind == "external_endpoint":
            var edge_id: String = str(row["topology_edge_id"])
            if plan_edges.has(edge_id) and str((plan_edges[edge_id] as Dictionary).get("kind", "SOLID")) != "SOLID":
                open_boundaries.append(edge_id)
    open_boundaries.sort()
    expected_open_boundaries.sort()
    _expect(int(counts["internal_pair"]) == internal_count, "%s internal classification drift %s" % [path, counts])
    _expect(int(counts["external_endpoint"]) == external_count, "%s external classification drift" % path)
    _expect(int(counts["unresolved"]) == unresolved_count, "%s unresolved classification drift %s" % [path, counts])
    _expect(int(counts["vertical_pair"]) == vertical_count, "%s vertical classification drift" % path)
    _expect(open_boundaries == expected_open_boundaries, "%s non-SOLID boundary identity drift" % path)
    if path.ends_with("coherent_ship_002/layout.json"):
        var unresolved_ids := PackedStringArray()
        for row_variant in classified["rows"]:
            var row: Dictionary = row_variant
            if str(row["classification"]) == "unresolved":
                unresolved_ids.append(str(row["topology_edge_id"]))
        _expect(unresolved_ids == PackedStringArray(["0|h|-1|2"]), "coherent 002 unresolved edge identity drift")


func _test_real_vertical_evaluation() -> void:
    for fixture in [
        "res://data/procgen/smoke/seed_000017/layout.json",
        "res://data/procgen/golden/coherent_ship_001/layout.json",
        "res://data/procgen/golden/coherent_ship_003/layout.json",
    ]:
        var source_layout: Dictionary = _load_json(fixture)
        var layout: Dictionary = source_layout.duplicate(true)
        var plan: Dictionary = layout["structural_plan"]
        var graph: RefCounted = NavGraphScript.new()
        graph.call("build_from_layout", layout)
        var initial: Dictionary = graph.call("classify_structural_projection", plan, layout)
        var boundary_pair: Dictionary = {}
        var target_edge: String = ""
        for row_variant in initial["rows"]:
            var row: Dictionary = row_variant
            if str(row["classification"]) != "internal_pair":
                continue
            var edge_id: String = str(row["topology_edge_id"])
            var edge: Dictionary = (plan["edges"] as Dictionary)[edge_id]
            var kind: String = str(edge["kind"])
            if boundary_pair.is_empty() and kind in ["OPEN", "DOOR", "HATCH"]:
                boundary_pair = row
            elif target_edge.is_empty() and not str(edge["module_id"]).is_empty() \
                    and kind in ["OPEN", "DOOR", "HATCH", "LOCKED"]:
                target_edge = edge_id
        _expect(not boundary_pair.is_empty() and not target_edge.is_empty(), "%s lacks real vertical evaluation anchors" % fixture)
        if boundary_pair.is_empty() or target_edge.is_empty():
            continue
        var boundary_source: Dictionary = (plan["edges"] as Dictionary)[str(boundary_pair["topology_edge_id"])]
        var first_cell: Array = (boundary_source["source_cells"] as Array)[0].duplicate()
        var second_cell: Array = (boundary_source["source_cells"] as Array)[1].duplicate()
        var threshold: String = str(graph.call(
            "node_key_for_cell", first_cell, int(first_cell[2]), plan["occupancy"]))
        var interior: String = str(graph.call(
            "node_key_for_cell", second_cell, int(second_cell[2]), plan["occupancy"]))
        var external_edge_id: String = "test_external_%s" % fixture.get_file().get_basename()
        var outside_cell: Array = [9999, 9999, int(first_cell[2])]
        (plan["edges"] as Dictionary)[external_edge_id] = {
            "edge_key": external_edge_id,
            "key": external_edge_id,
            "source_cells": [first_cell, outside_cell],
            "deck": int(first_cell[2]),
            "direction": "west",
            "opposite_direction": "east",
            "owner_room": "test/local",
            "other_room": "",
            "exterior": true,
            "portal": false,
            "kind": "OPEN",
            "state": "OPEN",
            "module_id": "wall_straight_1x1",
        }
        graph.call("build_from_layout", layout)
        var classified: Dictionary = graph.call("classify_structural_projection", plan, layout)
        var portal_states: Array = _real_portal_states(plan, layout["portals"])
        var projection: Array[Dictionary] = _real_live_projection(
            classified["rows"], plan, portal_states, target_edge, external_edge_id)
        var request: Dictionary = _request(_layout_projection(
            plan, layout["vertical_connections"], layout["portals"]), portal_states, target_edge)
        request["actor_node_id"] = threshold
        var endpoints: Array[Dictionary] = [{
            "endpoint_id": "endpoint/%s" % external_edge_id,
            "port_id": "port/%s" % external_edge_id,
            "ship_id": SHIP_ID,
            "target_module_id": "edge/%s" % external_edge_id,
            "structural_edge_key": external_edge_id,
            "portal_id": "",
            "threshold_node_id": threshold,
            "interior_node_id": interior,
            "baseline_usable": true,
            "candidate_usable": true,
        }]
        var connections: Array[Dictionary] = []
        var result: Dictionary = graph.call(
            "evaluate_edge_replacement_paths", request, projection, endpoints, connections)
        _expect(bool(result.get("ok", false)), "%s real vertical evaluation rejected: %s" % [fixture, result])
        var vertical_ids := PackedStringArray()
        for row in projection:
            if str(row["classification"]) == "vertical_pair":
                vertical_ids.append(str(row["projection_edge_id"]))
        _expect(vertical_ids.size() == (layout["vertical_connections"] as Array).size(), "%s vertical rows not exhaustive" % fixture)
        if fixture.ends_with("seed_000017/layout.json"):
            var keyed_state: Dictionary = _portal_state_for_edge(portal_states, "0|h|5|6")
            _expect(str(keyed_state.get("portal_id", "")) == "dock_01_to_corridor_02",
                "real keyed portal ID did not bind to its runtime edge")
        if not (layout["vertical_connections"] as Array).is_empty():
            var omitted: Array[Dictionary] = projection.duplicate(true)
            for index in range(omitted.size() - 1, -1, -1):
                if str(omitted[index]["classification"]) == "vertical_pair":
                    omitted.remove_at(index)
                    break
            _expect_denial(graph, omitted, request, endpoints, connections,
                "invalid_candidate_projection", "%s omitted vertical" % fixture)
            var altered: Array[Dictionary] = projection.duplicate(true)
            for row in altered:
                if str(row["classification"]) == "vertical_pair":
                    row["node_b"] = threshold
                    break
            _expect_denial(graph, altered, request, endpoints, connections,
                "invalid_candidate_projection", "%s altered vertical" % fixture)
            var malformed_vertical: Dictionary = request.duplicate(true)
            var verticals: Array = malformed_vertical["layout_projection"]["vertical_connections"]
            verticals[0]["from_cell"] = [true, 0, 0]
            _expect_denial(graph, projection, malformed_vertical, endpoints, connections,
                "invalid_candidate_projection", "%s malformed vertical cell" % fixture)


func _test_candidate_paths_and_immutability() -> void:
    var setup: Dictionary = _make_setup()
    var graph: RefCounted = setup["graph"]
    var request: Dictionary = setup["request"]
    var projection: Array[Dictionary] = setup["projection"]
    var endpoints: Array[Dictionary] = setup["endpoints"]
    var connections: Array[Dictionary] = setup["connections"]
    var receiver_before: String = _graph_snapshot(graph)
    var request_before: String = var_to_str(request)
    var projection_before: String = var_to_str(projection)
    var endpoints_before: String = var_to_str(endpoints)
    var connections_before: String = var_to_str(connections)
    var success: Dictionary = graph.call(
        "evaluate_edge_replacement_paths", request, projection, endpoints, connections)
    _expect(bool(success.get("ok", false)), "valid target overlay rejected: %s" % success.get("reason", ""))
    _expect(success.get("scene_authorized", true) == false, "pure result claimed scene authorization")
    _expect(str((success["overlay"] as Dictionary).get("edge_key", "")) == TARGET_EDGE, "target overlay identity lost")
    _expect((success["actor_exit"] as Dictionary)["node_path"] == PackedStringArray([
        "0:0:0", "1:0:0", "2:0:0", "2:0:1"]), "deterministic cheapest route drifted")
    _expect(is_equal_approx(float((success["actor_exit"] as Dictionary)["cost"]), 3.0), "hazard costs were not retained")
    _expect((success["local_connection_paths"] as Array).size() == 2, "both distinct local connection sides were not checked")
    var local_sides := PackedStringArray()
    var used_endpoints := PackedStringArray()
    for path_variant in success["local_connection_paths"]:
        var path_row: Dictionary = path_variant
        var remote: Dictionary = path_row["remote_identity"]
        local_sides.append(str(path_row["local_side"]))
        used_endpoints.append(str(path_row["endpoint_id"]))
        _expect(str(remote["ship_id"]).begins_with("foreign/"), "remote identity was rewritten")
        _expect(not graph.call("has_node", str(remote["endpoint_id"])), "foreign endpoint was resolved as a local node")
    local_sides.sort()
    used_endpoints.sort()
    _expect(local_sides == PackedStringArray(["host", "mobile"]), "host/mobile local-side coverage drifted")
    _expect(used_endpoints == PackedStringArray(["endpoint/local-exit", "endpoint/local-exit-2"]),
        "active connections did not retain distinct physical endpoints")
    _expect(receiver_before == _graph_snapshot(graph), "receiver graph mutated")
    _expect(request_before == var_to_str(request), "request mutated")
    _expect(projection_before == var_to_str(projection), "projection mutated")
    _expect(endpoints_before == var_to_str(endpoints), "endpoints mutated")
    _expect(connections_before == var_to_str(connections), "connections mutated")
    ((success["actor_exit"] as Dictionary)["node_path"] as PackedStringArray).append("returned-only")
    ((success["overlay"] as Dictionary)["node_pair"] as PackedStringArray).append("returned-only")
    (((success["local_connection_paths"] as Array)[0] as Dictionary)["node_path"] as PackedStringArray).append("returned-only")
    ((success["local_connection_paths"] as Array)[0] as Dictionary)["remote_identity"]["ship_id"] = "mutated-return"
    _expect(receiver_before == _graph_snapshot(graph), "returned collections alias receiver graph")
    _expect(request_before == var_to_str(request), "returned collections alias request")
    _expect(projection_before == var_to_str(projection), "returned collections alias projection")
    _expect(endpoints_before == var_to_str(endpoints), "returned collections alias endpoints")
    _expect(connections_before == var_to_str(connections), "returned collections alias connections")

    var alternate: Array[Dictionary] = projection.duplicate(true)
    _row_for(alternate, TARGET_EDGE)["base_clear_excluding_target"] = false
    var alternate_result: Dictionary = graph.call(
        "evaluate_edge_replacement_paths", request, alternate, endpoints, connections)
    _expect(bool(alternate_result.get("ok", false)), "blocked cheapest route did not find alternate")
    var actor_path: PackedStringArray = (alternate_result["actor_exit"] as Dictionary)["node_path"]
    _expect(not actor_path.has("1:0:0"), "blocked target route remained in returned path")

    var no_alternate: Array[Dictionary] = alternate.duplicate(true)
    _row_for(no_alternate, "0|v|0|1")["base_clear_excluding_target"] = false
    var blocked: Dictionary = graph.call(
        "evaluate_edge_replacement_paths", request, no_alternate, endpoints, connections)
    _expect(str(blocked.get("reason", "")) == "egress_blocked", "independent blocker did not survive target overlay")

    var closed: Dictionary = _mutate_portal(setup, false, true, false)
    _expect(str(closed.get("reason", "")) == "egress_blocked", "closed unlocked portal was treated as open: %s" % closed)
    var closed_normal: Dictionary = _mutate_portal(setup, false, false, false)
    _expect(str(closed_normal.get("reason", "")) == "egress_blocked", "closed normal portal was treated as open: %s" % closed_normal)
    var opened: Dictionary = _mutate_portal(setup, true, true, false)
    _expect(bool(opened.get("ok", false)), "explicitly opened portal stayed blocked")
    var unsafe_opening: Dictionary = _mutate_portal(setup, false, false, true)
    _expect(bool(unsafe_opening.get("ok", false)), "closed unsafe portal did not remain physically passable")

    var portal_target_request: Dictionary = _request_for_edge(setup, PORTAL_EDGE)
    var portal_target_projection: Array[Dictionary] = projection.duplicate(true)
    _row_for(portal_target_projection, TARGET_EDGE)["baseline_topology_usable"] = true
    _row_for(portal_target_projection, PORTAL_EDGE)["baseline_topology_usable"] = false
    var portal_target_result: Dictionary = graph.call(
        "evaluate_edge_replacement_paths", portal_target_request, portal_target_projection, endpoints, connections)
    _expect(bool(portal_target_result.get("ok", false)), "retained open target portal could not be restored")
    _expect(str((portal_target_result["overlay"] as Dictionary)["retained_portal_state"]["portal_id"]) == PORTAL_ID,
        "target portal retained state was not copied into overlay")


func _test_fail_closed_mutants() -> void:
    var setup: Dictionary = _make_setup()
    var graph: RefCounted = setup["graph"]
    var request: Dictionary = setup["request"]
    var projection: Array[Dictionary] = setup["projection"]
    var endpoints: Array[Dictionary] = setup["endpoints"]
    var connections: Array[Dictionary] = setup["connections"]

    _expect_malformed_target_plan(setup, "extra source cell", "source_cells", [[1, 0, 0], [2, 0, 0], [3, 0, 0]])
    _expect_malformed_target_plan(setup, "string coordinate", "source_cells", [["1", 0, 0], [2, 0, 0]])
    _expect_malformed_target_plan(setup, "boolean coordinate", "source_cells", [[true, 0, 0], [2, 0, 0]])
    _expect_malformed_target_plan(setup, "fractional coordinate", "source_cells", [[1.5, 0, 0], [2, 0, 0]])
    _expect_malformed_target_plan(setup, "non-finite coordinate", "source_cells", [[INF, 0, 0], [2, 0, 0]])
    _expect_malformed_target_plan(setup, "coerced exterior", "exterior", "false")
    _expect_malformed_target_plan(setup, "coerced portal", "portal", 0)
    _expect_malformed_target_plan(setup, "kind state contradiction", "state", "SOLID")
    _expect_malformed_target_plan(setup, "normalized lowercase kind", "kind", "open")
    var non_dictionary_edge: Dictionary = request.duplicate(true)
    _request_plan(non_dictionary_edge)["edges"][TARGET_EDGE] = "not-an-edge"
    _expect_denial(graph, projection, non_dictionary_edge, endpoints, connections,
        "invalid_candidate_projection", "non-dictionary plan edge")
    var missing_portal_field: Dictionary = request.duplicate(true)
    (_request_plan(missing_portal_field)["edges"][TARGET_EDGE] as Dictionary).erase("portal")
    _expect_denial(graph, projection, missing_portal_field, endpoints, connections,
        "invalid_candidate_projection", "missing plan portal field")
    var typed_portal_field: Dictionary = request.duplicate(true)
    _request_plan(typed_portal_field)["edges"][TARGET_EDGE]["portal"] = "false"
    _expect_denial(graph, projection, typed_portal_field, endpoints, connections,
        "invalid_candidate_projection", "typed plan portal field")

    _expect_denial(graph, _without_last(projection), request, endpoints, connections, "invalid_candidate_projection", "partial projection")
    var duplicate: Array[Dictionary] = projection.duplicate(true)
    duplicate[1]["projection_edge_id"] = duplicate[0]["projection_edge_id"]
    _expect_denial(graph, duplicate, request, endpoints, connections, "invalid_candidate_projection", "duplicate projection ID")
    var duplicate_pair: Array[Dictionary] = projection.duplicate(true)
    duplicate_pair[1]["node_a"] = duplicate[0]["node_a"]
    duplicate_pair[1]["node_b"] = duplicate[0]["node_b"]
    _expect_denial(graph, duplicate_pair, request, endpoints, connections, "invalid_candidate_projection", "duplicate node pair")

    var stale: Dictionary = request.duplicate(true)
    stale["layout_revision"] = "layout-r18"
    _expect_denial(graph, projection, stale, endpoints, connections, "stale_layout", "stale layout")
    var live_target: Dictionary = request.duplicate(true)
    live_target["target_live_state"] = "damaged"
    _expect_denial(graph, projection, live_target, endpoints, connections, "target_not_destroyed", "non-destroyed target")
    var extra_request_key: Dictionary = request.duplicate(true)
    extra_request_key["scene_authorized"] = true
    _expect_denial(graph, projection, extra_request_key, endpoints, connections, "invalid_candidate_projection", "extra request authority")
    var forged: Dictionary = request.duplicate(true)
    forged["target_module_id"] = "%s/fake" % TARGET_ID
    forged["original_descriptor"] = (request["original_descriptor"] as Dictionary).duplicate(true)
    forged["original_descriptor"]["module_id"] = forged["target_module_id"]
    _expect_denial(graph, projection, forged, endpoints, connections, "target_topology_mismatch", "prefix-shaped target")
    var wrong_cells: Dictionary = request.duplicate(true)
    wrong_cells["original_descriptor"] = (request["original_descriptor"] as Dictionary).duplicate(true)
    wrong_cells["original_descriptor"]["edge_binding"]["source_cells"] = [[0, 0, 0], [0, 1, 0]]
    _expect_denial(graph, projection, wrong_cells, endpoints, connections, "target_topology_mismatch", "mismatched source cells")

    var portal_mismatch: Array[Dictionary] = projection.duplicate(true)
    _row_for(portal_mismatch, PORTAL_EDGE)["portal_is_open"] = false
    _expect_denial(graph, portal_mismatch, request, endpoints, connections, "portal_state_mismatch", "portal row mismatch")
    var extra_portal: Dictionary = request.duplicate(true)
    extra_portal["portal_states"] = (request["portal_states"] as Array).duplicate(true)
    extra_portal["portal_states"].append({
        "portal_id": "portal/forged", "edge_key": "forged-edge", "portal_kind": "DOOR",
        "is_open": true, "is_unlocked": true, "is_unsafe": false,
    })
    _expect_denial(graph, projection, extra_portal, endpoints, connections, "portal_state_mismatch", "unused portal state")
    var wrong_portal_kind: Dictionary = request.duplicate(true)
    wrong_portal_kind["portal_states"] = (request["portal_states"] as Array).duplicate(true)
    wrong_portal_kind["portal_states"][0]["portal_kind"] = "HATCH"
    _expect_denial(graph, projection, wrong_portal_kind, endpoints, connections, "portal_state_mismatch", "portal kind mismatch")
    var empty_layout_portals: Dictionary = request.duplicate(true)
    empty_layout_portals["layout_projection"]["portals"] = []
    _expect_denial(graph, projection, empty_layout_portals, endpoints, connections, "portal_state_mismatch", "removed authored portal")
    var altered_layout_portal: Dictionary = request.duplicate(true)
    altered_layout_portal["layout_projection"]["portals"][0]["id"] = "portal/altered"
    _expect_denial(graph, projection, altered_layout_portal, endpoints, connections, "portal_state_mismatch", "altered authored portal ID")
    var forged_layout_portal: Dictionary = request.duplicate(true)
    forged_layout_portal["layout_projection"]["portals"].append({
        "id": "portal/forged-layout", "edge_key": "edge/not-authored",
    })
    _expect_denial(graph, projection, forged_layout_portal, endpoints, connections, "portal_state_mismatch", "forged authored portal edge")
    var foreign_endpoint: Array[Dictionary] = endpoints.duplicate(true)
    foreign_endpoint[0]["ship_id"] = "foreign/ship"
    _expect_denial(graph, projection, request, foreign_endpoint, connections, "missing_registered_exit", "foreign endpoint row")
    var duplicate_boundary: Array[Dictionary] = endpoints.duplicate(true)
    var alias_endpoint: Dictionary = endpoints[0].duplicate(true)
    alias_endpoint["endpoint_id"] = "endpoint/alias"
    alias_endpoint["port_id"] = "port/alias"
    duplicate_boundary.append(alias_endpoint)
    _expect_denial(graph, projection, request, duplicate_boundary, connections, "missing_registered_exit", "aliased physical boundary")
    var missing_connection_id: Array[Dictionary] = connections.duplicate(true)
    missing_connection_id[0]["connection_id"] = ""
    _expect_denial(graph, projection, request, endpoints, missing_connection_id, "active_connection_identity_missing", "missing connection identity")
    var missing_remote: Array[Dictionary] = connections.duplicate(true)
    missing_remote[0]["mobile"]["endpoint_id"] = ""
    _expect_denial(graph, projection, request, endpoints, missing_remote, "active_connection_identity_missing", "missing remote identity")
    var reused_local_endpoint: Array[Dictionary] = connections.duplicate(true)
    reused_local_endpoint[1]["mobile"]["endpoint_id"] = "endpoint/local-exit"
    _expect_denial(graph, projection, request, endpoints, reused_local_endpoint, "active_connection_identity_missing", "reused local connection endpoint")
    var unusable_endpoints: Array[Dictionary] = endpoints.duplicate(true)
    unusable_endpoints[0]["candidate_usable"] = false
    _expect_denial(graph, projection, request, unusable_endpoints, connections, "missing_registered_exit", "inconsistent candidate endpoint")
    var baseline_disconnected: Array[Dictionary] = projection.duplicate(true)
    _row_for(baseline_disconnected, PORTAL_EDGE)["base_clear_excluding_target"] = false
    _row_for(baseline_disconnected, "0|v|1|1")["base_clear_excluding_target"] = false
    _expect_denial(graph, baseline_disconnected, request, endpoints, connections, "invalid_candidate_projection", "disconnected baseline endpoint")
    _expect_denial(graph, projection, request, [], [], "missing_registered_exit", "boundary without registered endpoint")

    var external_target: Dictionary = _request_for_edge(setup, "0|v|2|1")
    _expect_denial(graph, projection, external_target, endpoints, connections, "unsupported_external_target", "external target")
    for layer in ["floor", "ceiling"]:
        var unsupported: Dictionary = request.duplicate(true)
        unsupported["original_descriptor"] = (request["original_descriptor"] as Dictionary).duplicate(true)
        unsupported["original_descriptor"]["layout_layer"] = layer
        _expect_denial(graph, projection, unsupported, endpoints, connections, "unsupported_candidate_layer", "%s target" % layer)

    var duplicate_plan_request: Dictionary = request.duplicate(true)
    var duplicate_plan: Dictionary = _request_plan(duplicate_plan_request)
    var duplicate_edge: Dictionary = (duplicate_plan["edges"]["0|v|0|0"] as Dictionary).duplicate(true)
    duplicate_edge["edge_key"] = "duplicate/authored"
    duplicate_edge["key"] = "duplicate/authored"
    duplicate_plan["edges"]["duplicate/authored"] = duplicate_edge
    var duplicate_classification: Dictionary = graph.call(
        "classify_structural_projection", duplicate_plan, duplicate_plan_request["layout_projection"])
    var actual_duplicate_projection: Array[Dictionary] = _live_projection(
        duplicate_classification["rows"], duplicate_plan, duplicate_plan_request["portal_states"])
    _expect_denial(graph, actual_duplicate_projection, duplicate_plan_request, endpoints, connections, "invalid_candidate_projection", "duplicate authored node pair")

    var unresolved_setup: Dictionary = _make_setup()
    var unresolved_request: Dictionary = unresolved_setup["request"]
    var unresolved_plan: Dictionary = _request_plan(unresolved_request)
    (unresolved_plan["occupancy"] as Dictionary).erase("0|1|0")
    var unresolved_graph: RefCounted = NavGraphScript.new()
    unresolved_graph.call("build_from_layout", {"structural_plan": unresolved_plan})
    var classified: Dictionary = unresolved_graph.call(
        "classify_structural_projection", unresolved_plan, unresolved_request["layout_projection"])
    var unresolved_projection: Array[Dictionary] = _live_projection(
        classified["rows"], unresolved_plan, unresolved_request["portal_states"])
    unresolved_request["actor_node_id"] = "0:0:0"
    _expect_denial(unresolved_graph, unresolved_projection, unresolved_request, [], [], "invalid_candidate_projection", "unresolved internal edge")

    var solid_request: Dictionary = request.duplicate(true)
    solid_request["original_descriptor"] = (request["original_descriptor"] as Dictionary).duplicate(true)
    solid_request["original_descriptor"]["edge_binding"] = (solid_request["original_descriptor"]["edge_binding"] as Dictionary).duplicate(true)
    solid_request["original_descriptor"]["edge_binding"]["topology_kind"] = "SOLID"
    solid_request["original_descriptor"]["edge_binding"]["topology_state"] = "SOLID"
    var solid_plan: Dictionary = _request_plan(solid_request)
    solid_plan["edges"][TARGET_EDGE]["kind"] = "SOLID"
    solid_plan["edges"][TARGET_EDGE]["state"] = "SOLID"
    var solid_projection: Array[Dictionary] = _reclassify_projection(graph, solid_request, projection)
    var solid_block: Array[Dictionary] = solid_projection.duplicate(true)
    _row_for(solid_block, "0|v|0|1")["base_clear_excluding_target"] = false
    _expect_denial(graph, solid_block, solid_request, endpoints, connections, "egress_blocked", "authored SOLID target closure")


func _expect_malformed_target_plan(
        setup: Dictionary,
        label: String,
        field: String,
        value: Variant) -> void:
    var request: Dictionary = (setup["request"] as Dictionary).duplicate(true)
    var plan: Dictionary = _request_plan(request)
    var edge: Dictionary = plan["edges"][TARGET_EDGE]
    edge[field] = value
    request["original_descriptor"] = _descriptor_for(plan, TARGET_EDGE)
    var graph: RefCounted = setup["graph"]
    var classified: Dictionary = graph.call(
        "classify_structural_projection", plan, request["layout_projection"])
    var projection: Array[Dictionary] = _live_projection(
        classified["rows"], plan, request["portal_states"])
    _expect_denial(
        graph, projection, request, setup["endpoints"], setup["connections"],
        "invalid_candidate_projection", label)


func _make_setup() -> Dictionary:
    var plan: Dictionary = _synthetic_plan()
    var graph: RefCounted = NavGraphScript.new()
    var layout_projection: Dictionary = _layout_projection(plan, [], _synthetic_portals())
    graph.call("build_from_layout", layout_projection)
    var portal_states: Array = [_portal_state(true, true, false)]
    var classified: Dictionary = graph.call("classify_structural_projection", plan, layout_projection)
    var projection: Array[Dictionary] = _live_projection(classified["rows"], plan, portal_states)
    var request: Dictionary = _request(layout_projection, portal_states)
    var endpoints: Array[Dictionary] = [
        {
            "endpoint_id": "endpoint/local-exit",
            "port_id": "port/local-exit",
            "ship_id": SHIP_ID,
            "target_module_id": "edge/0|v|2|1",
            "structural_edge_key": "0|v|2|1",
            "portal_id": "",
            "threshold_node_id": "2:0:1",
            "interior_node_id": "2:0:0",
            "baseline_usable": true,
            "candidate_usable": true,
        },
        {
            "endpoint_id": "endpoint/local-exit-2",
            "port_id": "port/local-exit-2",
            "ship_id": SHIP_ID,
            "target_module_id": "edge/0|v|3|1",
            "structural_edge_key": "0|v|3|1",
            "portal_id": "",
            "threshold_node_id": "3:0:1",
            "interior_node_id": "2:0:1",
            "baseline_usable": true,
            "candidate_usable": true,
        },
    ]
    var connections: Array[Dictionary] = [
        {
            "connection_id": "connection/host-local",
            "host": {"ship_id": SHIP_ID, "endpoint_id": "endpoint/local-exit"},
            "mobile": {"ship_id": "foreign/mobile", "endpoint_id": "foreign-node-never-local"},
        },
        {
            "connection_id": "connection/mobile-local",
            "host": {"ship_id": "foreign/host", "endpoint_id": "another-foreign-node"},
            "mobile": {"ship_id": SHIP_ID, "endpoint_id": "endpoint/local-exit-2"},
        },
    ]
    return {
        "graph": graph,
        "request": request,
        "projection": projection,
        "endpoints": endpoints,
        "connections": connections,
    }


func _synthetic_plan() -> Dictionary:
    var occupancy: Dictionary = {}
    for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]:
        occupancy["0|%d|%d" % [cell.x, cell.y]] = {
            "cell": [cell.x, cell.y], "cell_key": "0|%d|%d" % [cell.x, cell.y],
            "deck": 0, "position": [cell.x * 4.0, 0.0, cell.y * 4.0], "room_id": "room/local",
        }
    var edges: Dictionary = {}
    _add_edge(edges, "0|v|0|0", [0, 0, 0], [1, 0, 0], "OPEN")
    _add_edge(edges, TARGET_EDGE, [1, 0, 0], [2, 0, 0], "OPEN")
    _add_edge(edges, "0|h|0|0", [0, 0, 0], [0, 1, 0], "OPEN")
    _add_edge(edges, "0|v|0|1", [0, 1, 0], [1, 1, 0], "OPEN")
    _add_edge(edges, "0|v|1|1", [1, 1, 0], [2, 1, 0], "OPEN")
    _add_edge(edges, PORTAL_EDGE, [2, 0, 0], [2, 1, 0], "DOOR", true)
    _add_edge(edges, "0|v|2|1", [2, 1, 0], [2, 2, 0], "OPEN", false, true)
    _add_edge(edges, "0|v|2|1|to|3", [2, 1, 0], [3, 1, 0], "OPEN")
    _add_edge(edges, "0|v|3|1", [3, 1, 0], [4, 1, 0], "OPEN", false, true)
    return {"occupancy": occupancy, "edges": edges, "vertical_connections": []}


func _add_edge(
        edges: Dictionary,
        edge_key: String,
        a: Array,
        b: Array,
        kind: String,
        portal: bool = false,
        exterior: bool = false) -> void:
    edges[edge_key] = {
        "edge_key": edge_key,
        "key": edge_key,
        "source_cells": [a, b],
        "deck": 0,
        "direction": "east",
        "opposite_direction": "west",
        "owner_room": "room/local",
        "other_room": "" if exterior else "room/local",
        "exterior": exterior,
        "portal": portal,
        "kind": kind,
        "state": kind,
        "module_id": "doorway_frame_open_1x1" if portal else "wall_straight_1x1",
    }


func _request(
        layout_projection: Dictionary,
        portal_states: Array,
        target_edge: String = TARGET_EDGE) -> Dictionary:
    return {
        "ship_id": SHIP_ID,
        "layout_revision": REVISION,
        "layout_fingerprint": FINGERPRINT,
        "actor_node_id": "0:0:0",
        "target_module_id": "edge/%s" % target_edge,
        "target_live_state": "destroyed",
        "original_descriptor": _descriptor_for(layout_projection["structural_plan"], target_edge),
        "layout_projection": layout_projection,
        "portal_states": portal_states,
    }


func _layout_projection(plan: Dictionary, vertical_connections: Array, portals: Array) -> Dictionary:
    return {
        "structural_plan": plan,
        "vertical_connections": vertical_connections,
        "portals": portals,
    }


func _request_plan(request: Dictionary) -> Dictionary:
    return (request["layout_projection"] as Dictionary)["structural_plan"] as Dictionary


func _synthetic_portals() -> Array:
    return [{
        "id": PORTAL_ID,
        "edge_key": PORTAL_EDGE,
        "state": "DOOR",
        "from_cell": [2, 0, 0],
        "to_cell": [2, 1, 0],
    }]


func _descriptor_for(plan: Dictionary, edge_key: String) -> Dictionary:
    var edge: Dictionary = (plan["edges"] as Dictionary)[edge_key]
    return {
        "module_id": "edge/%s" % edge_key,
        "structural_module_id": str(edge["module_id"]),
        "layout_layer": "edge",
        "layout_revision": REVISION,
        "layout_fingerprint": FINGERPRINT,
        "edge_binding": {
            "edge_key": edge["edge_key"],
            "source_cells": (edge["source_cells"] as Array).duplicate(true),
            "direction": edge["direction"],
            "opposite_direction": edge["opposite_direction"],
            "owner_room": edge["owner_room"],
            "other_room": edge["other_room"],
            "exterior": edge["exterior"],
            "portal": edge["portal"],
            "topology_kind": edge["kind"],
            "topology_state": edge["state"],
        },
    }


func _request_for_edge(setup: Dictionary, edge_key: String) -> Dictionary:
    var request: Dictionary = (setup["request"] as Dictionary).duplicate(true)
    request["target_module_id"] = "edge/%s" % edge_key
    request["original_descriptor"] = _descriptor_for(_request_plan(request), edge_key)
    return request


func _portal_state(open: bool, unlocked: bool, unsafe: bool) -> Dictionary:
    return {
        "portal_id": PORTAL_ID,
        "edge_key": PORTAL_EDGE,
        "portal_kind": "DOOR",
        "is_open": open,
        "is_unlocked": unlocked,
        "is_unsafe": unsafe,
    }


func _real_portal_states(plan: Dictionary, portals: Array) -> Array:
    var states: Array = []
    var authored_by_edge: Dictionary = {}
    for portal_variant in portals:
        var portal: Dictionary = portal_variant
        var edge_key: String = str(portal.get("edge_key", ""))
        if not edge_key.is_empty():
            authored_by_edge[edge_key] = str(portal["id"])
    var edge_ids: Array = (plan["edges"] as Dictionary).keys()
    edge_ids.sort()
    for edge_id_variant in edge_ids:
        var edge_id: String = str(edge_id_variant)
        var edge: Dictionary = plan["edges"][edge_id_variant]
        if not bool(edge["portal"]):
            continue
        var kind: String = str(edge["kind"])
        states.append({
            "portal_id": str(authored_by_edge.get(edge_id, "edge:%s" % edge_id)),
            "edge_key": edge_id,
            "portal_kind": kind,
            "is_open": true,
            "is_unlocked": true,
            "is_unsafe": kind == "BREACH",
        })
    return states


func _portal_state_for_edge(portal_states: Array, edge_key: String) -> Dictionary:
    for state_variant in portal_states:
        var state: Dictionary = state_variant
        if str(state["edge_key"]) == edge_key:
            return state
    return {}


func _real_live_projection(
        classified_rows: Array,
        plan: Dictionary,
        portal_states: Array,
        target_edge: String,
        registered_external: String) -> Array[Dictionary]:
    var output: Array[Dictionary] = []
    var states_by_edge: Dictionary = {}
    for state_variant in portal_states:
        var state: Dictionary = state_variant
        states_by_edge[str(state["edge_key"])] = state
    for classified_variant in classified_rows:
        var row: Dictionary = (classified_variant as Dictionary).duplicate(true)
        var edge_id: String = str(row["topology_edge_id"])
        var classification: String = str(row["classification"])
        var edge: Dictionary = (plan["edges"] as Dictionary).get(edge_id, {})
        var kind: String = str(edge.get("kind", "OPEN"))
        var baseline: bool = classification == "vertical_pair" \
            or (classification == "internal_pair" and kind in ["OPEN", "DOOR", "HATCH"]) \
            or (classification == "external_endpoint" and edge_id == registered_external)
        if edge_id == target_edge:
            baseline = false
        row["baseline_topology_usable"] = baseline
        row["base_clear_excluding_target"] = true
        row["traversal_cost"] = 1.25 if classification == "vertical_pair" else 1.0
        row["blocker_revision"] = "real-fixture-blockers"
        row["portal_id"] = ""
        row["portal_is_open"] = false
        row["portal_is_unlocked"] = false
        row["portal_is_unsafe"] = false
        if states_by_edge.has(edge_id):
            var state: Dictionary = states_by_edge[edge_id]
            row["portal_id"] = state["portal_id"]
            row["portal_is_open"] = state["is_open"]
            row["portal_is_unlocked"] = state["is_unlocked"]
            row["portal_is_unsafe"] = state["is_unsafe"]
        output.append(row)
    return output


func _live_projection(classified_rows: Array, plan: Dictionary, portal_states: Array) -> Array[Dictionary]:
    var output: Array[Dictionary] = []
    for classified_variant in classified_rows:
        var row: Dictionary = (classified_variant as Dictionary).duplicate(true)
        var edge_key: String = str(row["topology_edge_id"])
        var edge: Dictionary = (plan["edges"] as Dictionary).get(edge_key, {})
        var kind: String = str(edge.get("kind", "OPEN"))
        row["baseline_topology_usable"] = edge_key != TARGET_EDGE and kind in ["OPEN", "DOOR", "HATCH"]
        row["base_clear_excluding_target"] = true
        row["traversal_cost"] = 2.0 if edge_key in ["0|h|0|0", "0|v|0|1", "0|v|1|1"] else 1.0
        row["blocker_revision"] = "blockers-r1"
        row["portal_id"] = PORTAL_ID if bool(edge.get("portal", false)) else ""
        row["portal_is_open"] = false
        row["portal_is_unlocked"] = false
        row["portal_is_unsafe"] = false
        if row["portal_id"] == PORTAL_ID:
            for state_variant in portal_states:
                var state: Dictionary = state_variant
                if str(state["portal_id"]) == PORTAL_ID:
                    row["portal_is_open"] = state["is_open"]
                    row["portal_is_unlocked"] = state["is_unlocked"]
                    row["portal_is_unsafe"] = state["is_unsafe"]
        output.append(row)
    return output


func _reclassify_projection(graph: RefCounted, request: Dictionary, original: Array[Dictionary]) -> Array[Dictionary]:
    var plan: Dictionary = _request_plan(request)
    var classified: Dictionary = graph.call(
        "classify_structural_projection", plan, request["layout_projection"])
    var output: Array[Dictionary] = _live_projection(
        classified["rows"], plan, request["portal_states"])
    for row in output:
        var prior: Dictionary = _row_for(original, str(row["topology_edge_id"]))
        if not prior.is_empty():
            for key in ["base_clear_excluding_target", "traversal_cost", "blocker_revision"]:
                row[key] = prior[key]
    return output


func _mutate_portal(setup: Dictionary, open: bool, unlocked: bool, unsafe: bool) -> Dictionary:
    var state: Dictionary = _portal_state(open, unlocked, unsafe)
    var request: Dictionary = (setup["request"] as Dictionary).duplicate(true)
    request["portal_states"] = [state]
    var projection: Array[Dictionary] = (setup["projection"] as Array[Dictionary]).duplicate(true)
    var row: Dictionary = _row_for(projection, PORTAL_EDGE)
    row["portal_is_open"] = open
    row["portal_is_unlocked"] = unlocked
    row["portal_is_unsafe"] = unsafe
    _row_for(projection, "0|v|1|1")["base_clear_excluding_target"] = false
    var endpoints: Array[Dictionary] = (setup["endpoints"] as Array[Dictionary]).duplicate(true)
    if not open and not unsafe:
        for endpoint in endpoints:
            endpoint["baseline_usable"] = false
            endpoint["candidate_usable"] = false
    return (setup["graph"] as RefCounted).call(
        "evaluate_edge_replacement_paths", request, projection, endpoints, setup["connections"])


func _row_for(rows: Array[Dictionary], topology_id: String) -> Dictionary:
    for row in rows:
        if str(row.get("topology_edge_id", "")) == topology_id:
            return row
    return {}


func _without_last(rows: Array[Dictionary]) -> Array[Dictionary]:
    var output: Array[Dictionary] = rows.duplicate(true)
    output.pop_back()
    return output


func _expect_denial(
        graph: RefCounted,
        projection: Array[Dictionary],
        request: Dictionary,
        endpoints: Array[Dictionary],
        connections: Array[Dictionary],
        reason: String,
        label: String) -> void:
    var result: Dictionary = graph.call(
        "evaluate_edge_replacement_paths", request, projection, endpoints, connections)
    _expect(not bool(result.get("ok", false)) and str(result.get("reason", "")) == reason,
        "%s did not deny %s: %s" % [label, reason, result])
    _expect(result.get("scene_authorized", true) == false, "%s denial claimed scene authorization" % label)


func _graph_snapshot(graph: RefCounted) -> String:
    return var_to_str({
        "nodes": graph.get("nodes"),
        "edges": graph.get("edges"),
        "base_edges": graph.get("_base_edges"),
        "dirty": graph.get("dirty"),
        "cell_size": graph.get("cell_size"),
        "deck_height": graph.get("deck_height"),
    })


func _load_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        _expect(false, "fixture missing: %s" % path)
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not (parsed is Dictionary):
        _expect(false, "fixture invalid: %s" % path)
        return {}
    return parsed


func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    _failed = true
    push_error("P17 candidate nav: %s" % message)
