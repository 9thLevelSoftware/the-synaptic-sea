extends RefCounted
class_name DockEndpointAuthoring

## Deterministic compiler/validator for the one structural boarding endpoint
## every production ship layout exposes. Endpoints name already-compiled
## structural records; consumers never derive them from a room center.

const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")

const ENDPOINT_KEYS := [
    "endpoint_id", "port_id", "portal_id", "type", "size_class", "room_id",
    "deck", "edge_cell", "edge_direction", "structural_edge_key",
    "target_module_id", "structural_module_id", "local_position", "outward_normal",
    "threshold_nav_node_id", "interior_nav_node_id",
    "threshold_clearance_point_local", "interior_clearance_point_local",
    "join_piece_placement_ids", "join_collision_fingerprint",
]
const DIRECTIONS: Dictionary = {
    "north": Vector2i(0, -1),
    "east": Vector2i(1, 0),
    "south": Vector2i(0, 1),
    "west": Vector2i(-1, 0),
}
const OUTWARD_NORMALS: Dictionary = {
    "north": Vector3(0.0, 0.0, -1.0),
    "east": Vector3(1.0, 0.0, 0.0),
    "south": Vector3(0.0, 0.0, 1.0),
    "west": Vector3(-1.0, 0.0, 0.0),
}
const PORTAL_MODULE: String = "doorway_frame_open_1x1"
const CELL_SIZE: float = 4.0
const PLAYER_CLEARANCE_Y: float = 0.55
const PROJECTION_SCHEMA: String = "dock-collision-projection-v1"
const PROJECTION_NUMERIC_ENCODING: String = "ieee754-binary32-bits-v1"
const PROJECTION_CONTENT_ENCODING: String = "dock-collision-content-v1"
const PROJECTION_KEYS := ["schema_version", "numeric_encoding", "content_encoding", "modules"]
const PROJECTION_MODULE_KEYS := ["module_id", "contract_path", "contract_sha256",
    "wrapper_scene", "wrapper_sha256", "content_sha256", "boxes"]
const PROJECTION_BOX_KEYS := ["shape_path", "basis", "basis_f32_bits", "origin",
    "origin_f32_bits", "dimensions", "dimensions_f32_bits"]


static func author_layout(
        layout: Dictionary, fixed_lifeboat: bool = false,
        collision_projection: Dictionary = {}, counterpart_layout: Dictionary = {}) -> Dictionary:
    var projection_verdict: Dictionary = validate_collision_projection(collision_projection)
    if not bool(projection_verdict.get("ok", false)):
        return projection_verdict
    var existing: Variant = layout.get("boarding_endpoints_v1", null)
    if existing is Array and not (existing as Array).is_empty():
        return validate_layout(layout, collision_projection)

    # Discovery compilation is deliberately detached and never published. It only
    # supplies canonical boundary geometry for choosing an exterior candidate.
    var source: Dictionary = layout.duplicate(true)
    source.erase("structural_plan")
    source.erase("structural_plan_validated")
    source.erase("boarding_endpoints_v1")
    source.erase("initial_player_spawn_v1")
    source.erase("dock_navigation_nodes_v1")
    var plan: Dictionary = StructuralEdgeCompilerScript.new().compile(source)
    var edges_variant: Variant = plan.get("edges", null)
    var placements_variant: Variant = plan.get("placements", null)
    var floors_variant: Variant = plan.get("floor_placements", null)
    if not edges_variant is Dictionary or not placements_variant is Array \
            or not floors_variant is Array or not (plan.get("errors", []) as Array).is_empty():
        return {"ok": false, "reason": "discovery_structural_plan_invalid"}

    var room_roles: Dictionary = {}
    for room_variant in layout.get("rooms", []):
        if room_variant is Dictionary:
            var room: Dictionary = room_variant
            room_roles[str(room.get("id", ""))] = str(
                room.get("room_role", room.get("role", "")))
    var candidates: Array[Dictionary] = []
    for edge_variant in (edges_variant as Dictionary).values():
        if not edge_variant is Dictionary:
            continue
        var edge: Dictionary = edge_variant
        if not bool(edge.get("exterior", false)) \
                or str(edge.get("kind", "")) != "SOLID" \
                or not str(edge.get("other_room", "")).is_empty():
            continue
        var direction: String = str(edge.get("direction", ""))
        if not DIRECTIONS.has(direction):
            continue
        var room_id: String = str(edge.get("owner_room", ""))
        var role: String = str(room_roles.get(room_id, ""))
        if role != "dock" and role != "airlock":
            continue
        var role_rank: int = 0 if role == "dock" else 1
        var direction_rank: int = _direction_rank(direction, fixed_lifeboat)
        var candidate: Dictionary = edge.duplicate(true)
        candidate["_sort_key"] = "%d|%d|%s|%s" % [
            role_rank, direction_rank, room_id, str(edge.get("edge_key", ""))]
        candidates.append(candidate)
    if candidates.is_empty():
        return {"ok": false, "reason": "no_clear_exterior_edge"}
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return str(a.get("_sort_key", "")) < str(b.get("_sort_key", "")))
    var edge: Dictionary = {}
    var edge_placement: Dictionary = {}
    var floor_placement: Dictionary = {}
    var cell := Vector2i.ZERO
    var deck: int = 0
    var cell_key: String = ""
    var supporting_candidate_count: int = 0
    var supporting_rejections: Array[Dictionary] = []
    var pair_rejections: Array[Dictionary] = []
    var selected_support_verdict: Dictionary = {}
    var selected_pair_verdict: Dictionary = {}
    var selected_source: Dictionary = {}
    var selected_plan: Dictionary = {}
    for selected in candidates:
        var candidate_key: String = str(selected.get("edge_key", selected.get("key", "")))
        var candidate_edge: Dictionary = (edges_variant as Dictionary).get(candidate_key, {})
        if candidate_edge.is_empty():
            continue
        var candidate_placement: Dictionary = _edge_placement(placements_variant, candidate_key)
        if candidate_placement.is_empty():
            continue
        var candidate_cell: Vector2i = _as_cell(candidate_edge.get("cell", Vector2i.ZERO))
        var candidate_deck: int = int(candidate_edge.get("deck", 0))
        var candidate_cell_key: String = "%d|%d|%d" % [
            candidate_deck, candidate_cell.x, candidate_cell.y]
        var candidate_floor: Dictionary = _floor_placement(floors_variant, candidate_cell_key)
        if candidate_floor.is_empty():
            continue
        var direction: String = str(candidate_edge.get("direction", ""))
        var outward: Vector3 = OUTWARD_NORMALS[direction]
        var edge_position: Vector3 = _as_vector3(candidate_edge.get("position", []))
        var port_position: Vector3 = edge_position + outward * _portal_outward_extent(
            collision_projection, candidate_placement)
        var threshold_point: Vector3 = port_position - outward * 0.25 \
            + Vector3.UP * PLAYER_CLEARANCE_Y
        var interior_point: Vector3 = port_position - outward * 1.0 \
            + Vector3.UP * PLAYER_CLEARANCE_Y
        var portal_id: String = "boarding_portal:%s" % candidate_key
        var candidate_source: Dictionary = source.duplicate(true)
        var portals: Array = (candidate_source.get("portals", []) as Array).duplicate(true)
        var outside_cell: Vector2i = candidate_cell + (DIRECTIONS[direction] as Vector2i)
        portals.append({
            "id": portal_id,
            "from_room": str(candidate_edge.get("owner_room", "")),
            "to_room": "",
            "from_cell": [candidate_cell.x, candidate_cell.y, candidate_deck],
            "to_cell": [outside_cell.x, outside_cell.y, candidate_deck],
            "edge_direction": direction,
            "module_id": PORTAL_MODULE,
            "state": "DOOR",
            "exterior": true,
        })
        candidate_source["portals"] = portals
        var edge_placement_id: String = "edge:%s" % candidate_key
        var floor_placement_id: String = "floor:%s" % candidate_cell_key
        candidate_source["dock_navigation_nodes_v1"] = [
            {
                "node_id": "dock-threshold:%s" % candidate_key,
                "kind": "threshold",
                "portal_id": portal_id,
                "room_id": str(candidate_edge.get("owner_room", "")),
                "deck": candidate_deck,
                "cell": [candidate_cell.x, candidate_cell.y, candidate_deck],
                "structural_placement_id": edge_placement_id,
                "local_position": _vector_array(threshold_point),
            },
            {
                "node_id": "dock-interior:%s" % candidate_cell_key,
                "kind": "interior",
                "portal_id": portal_id,
                "room_id": str(candidate_edge.get("owner_room", "")),
                "deck": candidate_deck,
                "cell": [candidate_cell.x, candidate_cell.y, candidate_deck],
                "structural_placement_id": floor_placement_id,
                "local_position": _vector_array(interior_point),
            },
        ]
        var candidate_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(
            candidate_source)
        var plan_verdict: Dictionary = StructuralPlanValidatorScript.new().validate(
            candidate_plan, candidate_source)
        if not bool(plan_verdict.get("ok", false)):
            pair_rejections.append({"ok": false,
                "reason": "candidate_authoritative_compile_invalid",
                "edge_key": candidate_key,
                "errors": plan_verdict.get("errors", [])})
            continue
        var authoritative_edge: Dictionary = candidate_plan.get("edges", {}).get(
            candidate_key, {}) as Dictionary
        var authoritative_placement: Dictionary = _edge_placement(
            candidate_plan.get("placements", []), candidate_key)
        var authoritative_floor: Dictionary = _floor_placement(
            candidate_plan.get("floor_placements", []), candidate_cell_key)
        var support_verdict: Dictionary = _candidate_supporting_plane_verdict(
            candidate_plan, authoritative_edge, authoritative_placement,
            authoritative_floor, collision_projection)
        if not bool(support_verdict.get("ok", false)):
            support_verdict["edge_key"] = candidate_key
            support_verdict["direction"] = direction
            supporting_rejections.append(support_verdict)
            continue
        supporting_candidate_count += 1
        var pair_verdict: Dictionary = _candidate_pair_clear(
                candidate_plan, authoritative_edge, authoritative_placement,
                authoritative_floor,
                counterpart_layout, collision_projection)
        if not bool(pair_verdict.get("ok", false)):
            pair_rejections.append(pair_verdict)
            continue
        edge = authoritative_edge
        edge_placement = authoritative_placement
        floor_placement = authoritative_floor
        selected_source = candidate_source
        selected_plan = candidate_plan
        selected_support_verdict = support_verdict.duplicate(true)
        selected_pair_verdict = pair_verdict.duplicate(true)
        cell = candidate_cell
        deck = candidate_deck
        cell_key = candidate_cell_key
        break
    if edge.is_empty():
        var failure_reason: String = "no_supporting_exterior_edge"
        if supporting_candidate_count > 0:
            failure_reason = "no_compatible_exterior_edge" \
                if not counterpart_layout.is_empty() \
                else "no_authoritative_exterior_edge"
        return {"ok": false,
            "reason": failure_reason,
            "supporting_candidate_count": supporting_candidate_count,
            "supporting_rejections": supporting_rejections,
            "candidate_pair_rejections": pair_rejections}
    var edge_key: String = str(edge.get("edge_key", edge.get("key", "")))

    var portal_id: String = "boarding_portal:%s" % edge_key
    var direction: String = str(edge.get("direction", ""))
    var outward: Vector3 = OUTWARD_NORMALS[direction]
    var edge_position: Vector3 = _as_vector3(edge.get("position", Vector3.ZERO))
    # The registered threshold is the actual outer collision face. Mating the
    # two cell-center planes would overlap both frames and their adjacent walls.
    var port_position: Vector3 = edge_position + outward * _portal_outward_extent(
        collision_projection, edge_placement)
    var threshold_point: Vector3 = port_position - outward * 0.25 + Vector3.UP * PLAYER_CLEARANCE_Y
    var interior_point: Vector3 = port_position - outward * 1.0 + Vector3.UP * PLAYER_CLEARANCE_Y
    var edge_placement_id: String = str(edge_placement.get("placement_id", "edge:%s" % edge_key))
    var floor_placement_id: String = str(floor_placement.get("placement_id", "floor:%s" % cell_key))
    var endpoint: Dictionary = {
        "endpoint_id": "boarding:%s" % edge_key,
        "port_id": "airlock:%s" % edge_key,
        "portal_id": portal_id,
        "type": "airlock",
        "size_class": 1,
        "room_id": str(edge.get("owner_room", "")),
        "deck": deck,
        "edge_cell": [cell.x, cell.y, deck],
        "edge_direction": direction,
        "structural_edge_key": edge_key,
        "target_module_id": PORTAL_MODULE,
        "structural_module_id": PORTAL_MODULE,
        "local_position": _vector_array(port_position),
        "outward_normal": _vector_array(outward),
        "threshold_nav_node_id": "dock-threshold:%s" % edge_key,
        "interior_nav_node_id": "dock-interior:%s" % cell_key,
        "threshold_clearance_point_local": _vector_array(threshold_point),
        "interior_clearance_point_local": _vector_array(interior_point),
        "join_piece_placement_ids": [edge_placement_id, floor_placement_id],
        "join_collision_fingerprint": join_collision_fingerprint(
            edge_placement_id, floor_placement_id,
            str(floor_placement.get("module_id", "floor_1x1")), collision_projection),
    }
    selected_source["structural_plan"] = selected_plan
    selected_source["structural_plan_validated"] = true
    selected_source["boarding_endpoints_v1"] = [endpoint]
    if fixed_lifeboat:
        selected_source["initial_player_spawn_v1"] = {
            "spawn_id": "lifeboat-initial-airlock",
            "owner_ship_id": "lifeboat",
            "room_id": str(edge.get("owner_room", "airlock_01")),
            "nav_node_id": "dock-interior:%s" % cell_key,
            # The spawn is the measured authored interior anchor for this exact
            # exterior connector. The cell center can coincide with a canonical
            # corner wing and is therefore not a valid physical spawn authority.
            "local_position": _vector_array(interior_point),
        }
    var validation: Dictionary = validate_layout(selected_source, collision_projection)
    if bool(validation.get("ok", false)):
        layout["portals"] = selected_source["portals"].duplicate(true)
        layout["dock_navigation_nodes_v1"] = selected_source[
            "dock_navigation_nodes_v1"].duplicate(true)
        layout["structural_plan"] = selected_plan.duplicate(true)
        layout["structural_plan_validated"] = true
        layout["boarding_endpoints_v1"] = [endpoint.duplicate(true)]
        if fixed_lifeboat:
            layout["initial_player_spawn_v1"] = selected_source[
                "initial_player_spawn_v1"].duplicate(true)
        else:
            layout.erase("initial_player_spawn_v1")
        validation["candidate_count"] = candidates.size()
        validation["supporting_candidate_count"] = supporting_candidate_count
        validation["supporting_rejections"] = supporting_rejections
        validation["candidate_pair_rejections"] = pair_rejections
        validation["selected_support"] = selected_support_verdict
        validation["selected_pair"] = selected_pair_verdict
    return validation


static func validate_layout(layout: Dictionary, collision_projection: Dictionary = {}) -> Dictionary:
    var projection_verdict: Dictionary = validate_collision_projection(collision_projection)
    if not bool(projection_verdict.get("ok", false)):
        return projection_verdict
    var endpoints_variant: Variant = layout.get("boarding_endpoints_v1", null)
    if not endpoints_variant is Array or (endpoints_variant as Array).size() != 1:
        return {"ok": false, "reason": "endpoint_count"}
    var endpoint_variant: Variant = (endpoints_variant as Array)[0]
    if not endpoint_variant is Dictionary:
        return {"ok": false, "reason": "endpoint_type"}
    var endpoint: Dictionary = endpoint_variant
    if endpoint.keys().size() != ENDPOINT_KEYS.size():
        return {"ok": false, "reason": "endpoint_keys"}
    for key in ENDPOINT_KEYS:
        if not endpoint.has(key):
            return {"ok": false, "reason": "endpoint_missing_%s" % key}
    var edge_key: String = str(endpoint.get("structural_edge_key", ""))
    var plan_variant: Variant = layout.get("structural_plan", null)
    if not plan_variant is Dictionary or not bool(layout.get(
            "structural_plan_validated", false)):
        return {"ok": false, "reason": "missing_structural_plan"}
    var plan: Dictionary = plan_variant
    var recompiled: Dictionary = StructuralEdgeCompilerScript.new().compile(layout)
    var plan_verdict: Dictionary = StructuralPlanValidatorScript.new().validate(
        recompiled, layout)
    if not bool(plan_verdict.get("ok", false)) or recompiled != plan:
        return {"ok": false, "reason": "structural_plan_roundtrip_mismatch"}
    var edge_variant: Variant = plan.get("edges", {}).get(edge_key, null)
    if not edge_variant is Dictionary:
        return {"ok": false, "reason": "endpoint_edge_missing"}
    var edge: Dictionary = edge_variant
    var direction: String = str(endpoint.get("edge_direction", ""))
    var deck_authority: Dictionary = _strict_integral_authority(
        endpoint.get("deck", null))
    var size_authority: Dictionary = _strict_integral_authority(
        endpoint.get("size_class", null))
    if not bool(deck_authority.get("ok", false)) \
            or not bool(size_authority.get("ok", false)) \
            or int(size_authority.get("value", -1)) != 1:
        return {"ok": false, "reason": "endpoint_scalar_authority"}
    var deck: int = int(deck_authority.get("value", -1))
    var cell_authority: Dictionary = _strict_deck_cell_authority(
        endpoint.get("edge_cell", null), deck)
    if not bool(cell_authority.get("ok", false)):
        return {"ok": false, "reason": "endpoint_cell_authority"}
    var cell: Vector2i = cell_authority.get("cell", Vector2i.ZERO) as Vector2i
    var room_id: String = str(endpoint.get("room_id", ""))
    var room: Dictionary = _room_by_id(layout, room_id)
    var room_role: String = str(room.get("room_role", room.get("role", "")))
    var cell_key: String = "%d|%d|%d" % [deck, cell.x, cell.y]
    var edge_placement: Dictionary = _edge_placement(plan.get("placements", []), edge_key)
    var floor_placement: Dictionary = _floor_placement(
        plan.get("floor_placements", []), cell_key)
    var portal_id: String = str(endpoint.get("portal_id", ""))
    if not bool(edge.get("exterior", false)) or not str(edge.get("other_room", "")).is_empty() \
            or str(edge.get("kind", "")) != "DOOR" \
            or str(edge.get("module_id", "")) != PORTAL_MODULE \
            or str(edge.get("portal_id", "")) != portal_id \
            or str(edge.get("owner_room", "")) != room_id \
            or int(edge.get("deck", -1)) != deck \
            or _as_cell(edge.get("cell", [])) != cell \
            or str(edge.get("direction", "")) != direction \
            or room.is_empty() or (room_role != "dock" and room_role != "airlock"):
        return {"ok": false, "reason": "endpoint_not_exterior_portal"}
    var exterior_portal: Dictionary = _exterior_portal_by_id(layout, portal_id)
    var outside_cell: Vector2i = cell + (DIRECTIONS.get(
        direction, Vector2i(99999, 99999)) as Vector2i)
    var portal_from_authority: Dictionary = _strict_deck_cell_authority(
        exterior_portal.get("from_cell", null), deck)
    var portal_to_authority: Dictionary = _strict_deck_cell_authority(
        exterior_portal.get("to_cell", null), deck)
    if exterior_portal.is_empty() or str(exterior_portal.get("from_room", "")) != room_id \
            or not str(exterior_portal.get("to_room", "missing")).is_empty() \
            or not bool(portal_from_authority.get("ok", false)) \
            or not bool(portal_to_authority.get("ok", false)) \
            or portal_from_authority.get("cell", Vector2i.ZERO) != cell \
            or portal_to_authority.get("cell", Vector2i.ZERO) != outside_cell \
            or str(exterior_portal.get("edge_direction", "")) != direction \
            or str(exterior_portal.get("module_id", "")) != PORTAL_MODULE \
            or str(exterior_portal.get("state", "")) != "DOOR":
        return {"ok": false, "reason": "endpoint_portal_authority"}
    var outward_authority: Dictionary = _strict_vector3_authority(
        endpoint.get("outward_normal", null))
    if not OUTWARD_NORMALS.has(direction) \
            or not bool(outward_authority.get("ok", false)) \
            or outward_authority.get("value", Vector3.INF) != OUTWARD_NORMALS[direction]:
        return {"ok": false, "reason": "endpoint_normal"}
    var position_authority: Dictionary = _strict_vector3_authority(
        endpoint.get("local_position", null))
    var expected_position: Vector3 = _as_vector3(edge.get("position", [])) \
        + (OUTWARD_NORMALS[direction] as Vector3) * _portal_outward_extent(
            collision_projection, edge_placement)
    if not expected_position.is_finite() \
            or not bool(position_authority.get("ok", false)) \
            or position_authority.get("value", Vector3.INF) != expected_position \
            or str(endpoint.get("endpoint_id", "")) != "boarding:%s" % edge_key \
            or str(endpoint.get("port_id", "")) != "airlock:%s" % edge_key \
            or str(endpoint.get("type", "")) != "airlock" \
            or str(endpoint.get("target_module_id", "")) != PORTAL_MODULE \
            or str(endpoint.get("structural_module_id", "")) != PORTAL_MODULE:
        return {"ok": false, "reason": "endpoint_position"}
    var join_ids: Variant = endpoint.get("join_piece_placement_ids", null)
    var expected_edge_placement_id: String = "edge:%s" % edge_key
    var expected_floor_placement_id: String = "floor:%s" % cell_key
    if edge_placement.is_empty() or floor_placement.is_empty() \
            or str(edge_placement.get("placement_id", "")) != expected_edge_placement_id \
            or str(edge_placement.get("module_id", "")) != PORTAL_MODULE \
            or str(floor_placement.get("placement_id", "")) != expected_floor_placement_id \
            or not ["floor_1x1", "corridor_floor_1x1"].has(str(
                floor_placement.get("module_id", ""))) \
            or str(floor_placement.get("room_id", "")) != room_id \
            or not join_ids is Array or join_ids != [
                expected_edge_placement_id, expected_floor_placement_id]:
        return {"ok": false, "reason": "endpoint_join_ids"}
    var expected_fingerprint: String = join_collision_fingerprint(
        expected_edge_placement_id, expected_floor_placement_id,
        str(floor_placement.get("module_id", "")), collision_projection)
    if str(endpoint.get("join_collision_fingerprint", "")) != expected_fingerprint:
        return {"ok": false, "reason": "endpoint_join_fingerprint"}
    var threshold_node: Dictionary = _compiled_navigation_node(
        plan, str(endpoint.get("threshold_nav_node_id", "")))
    var interior_node: Dictionary = _compiled_navigation_node(
        plan, str(endpoint.get("interior_nav_node_id", "")))
    var threshold_authority: Dictionary = _strict_vector3_authority(
        endpoint.get("threshold_clearance_point_local", null))
    var interior_authority: Dictionary = _strict_vector3_authority(
        endpoint.get("interior_clearance_point_local", null))
    if not bool(threshold_authority.get("ok", false)) \
            or not bool(interior_authority.get("ok", false)):
        return {"ok": false, "reason": "endpoint_clearance_authority"}
    var threshold_point: Vector3 = threshold_authority.get("value", Vector3.INF) as Vector3
    var interior_point: Vector3 = interior_authority.get("value", Vector3.INF) as Vector3
    var threshold_position_authority: Dictionary = _strict_vector3_authority(
        threshold_node.get("local_position", null))
    var interior_position_authority: Dictionary = _strict_vector3_authority(
        interior_node.get("local_position", null))
    var threshold_deck_authority: Dictionary = _strict_integral_authority(
        threshold_node.get("deck", null))
    var interior_deck_authority: Dictionary = _strict_integral_authority(
        interior_node.get("deck", null))
    var threshold_cell_authority: Dictionary = _strict_deck_cell_authority(
        threshold_node.get("cell", null), deck)
    var interior_cell_authority: Dictionary = _strict_deck_cell_authority(
        interior_node.get("cell", null), deck)
    var outward: Vector3 = OUTWARD_NORMALS[direction]
    if threshold_node.is_empty() or interior_node.is_empty() \
            or threshold_node == interior_node \
            or str(threshold_node.get("kind", "")) != "threshold" \
            or str(interior_node.get("kind", "")) != "interior" \
            or str(threshold_node.get("portal_id", "")) != portal_id \
            or str(interior_node.get("portal_id", "")) != portal_id \
            or str(threshold_node.get("room_id", "")) != room_id \
            or str(interior_node.get("room_id", "")) != room_id \
            or not bool(threshold_deck_authority.get("ok", false)) \
            or not bool(interior_deck_authority.get("ok", false)) \
            or int(threshold_deck_authority.get("value", -1)) != deck \
            or int(interior_deck_authority.get("value", -1)) != deck \
            or not bool(threshold_cell_authority.get("ok", false)) \
            or not bool(interior_cell_authority.get("ok", false)) \
            or threshold_cell_authority.get("cell", Vector2i.ZERO) != cell \
            or interior_cell_authority.get("cell", Vector2i.ZERO) != cell \
            or str(threshold_node.get("structural_placement_id", "")) \
                != expected_edge_placement_id \
            or str(interior_node.get("structural_placement_id", "")) \
                != expected_floor_placement_id \
            or not bool(threshold_position_authority.get("ok", false)) \
            or not bool(interior_position_authority.get("ok", false)) \
            or threshold_position_authority.get("value", Vector3.INF) != threshold_point \
            or interior_position_authority.get("value", Vector3.INF) != interior_point \
            or not threshold_point.is_finite() or not interior_point.is_finite() \
            or (threshold_point - expected_position).dot(outward) >= 0.0 \
            or (interior_point - threshold_point).dot(outward) >= 0.0 \
            or threshold_point.distance_to(interior_point) < 0.7:
        return {"ok": false, "reason": "endpoint_clearance_points"}
    var requires_initial_spawn: bool = str(layout.get(
        "program_id", "")) == "life_boat_fixed"
    if requires_initial_spawn and not layout.has("initial_player_spawn_v1"):
        return {"ok": false, "reason": "spawn_authority"}
    if layout.has("initial_player_spawn_v1"):
        var spawn_variant: Variant = layout.get("initial_player_spawn_v1", null)
        if not spawn_variant is Dictionary:
            return {"ok": false, "reason": "spawn_authority"}
        var spawn: Dictionary = spawn_variant
        var spawn_keys: Array = ["spawn_id", "owner_ship_id", "room_id",
            "nav_node_id", "local_position"]
        var spawn_fields_valid: bool = spawn.size() == spawn_keys.size()
        for field in spawn_keys:
            spawn_fields_valid = spawn_fields_valid and spawn.has(field)
        var spawn_position_authority: Dictionary = _strict_vector3_authority(
            spawn.get("local_position", null))
        if not spawn_fields_valid \
                or str(spawn.get("spawn_id", "")) != "lifeboat-initial-airlock" \
                or str(spawn.get("owner_ship_id", "")) != "lifeboat" \
                or str(spawn.get("room_id", "")) != room_id \
                or str(spawn.get("nav_node_id", "")) != str(
                    endpoint.get("interior_nav_node_id", "")) \
                or not bool(spawn_position_authority.get("ok", false)) \
                or spawn_position_authority.get("value", Vector3.INF) != interior_point:
            return {"ok": false, "reason": "spawn_authority"}
    return {"ok": true, "reason": "ok", "endpoint": endpoint}


static func _room_by_id(layout: Dictionary, room_id: String) -> Dictionary:
    var found: Dictionary = {}
    for room_variant in layout.get("rooms", []):
        if room_variant is Dictionary and str((room_variant as Dictionary).get(
                "id", "")) == room_id:
            if not found.is_empty():
                return {}
            found = room_variant as Dictionary
    return found


static func _exterior_portal_by_id(layout: Dictionary, portal_id: String) -> Dictionary:
    var found: Dictionary = {}
    var exterior_count: int = 0
    for portal_variant in layout.get("portals", []):
        if not portal_variant is Dictionary:
            continue
        var portal: Dictionary = portal_variant
        if bool(portal.get("exterior", false)):
            exterior_count += 1
            if str(portal.get("id", "")) == portal_id:
                found = portal
    return found if exterior_count == 1 else {}


static func _compiled_navigation_node(plan: Dictionary, node_id: String) -> Dictionary:
    var found: Dictionary = {}
    for node_variant in plan.get("dock_navigation_nodes", []):
        if node_variant is Dictionary and str((node_variant as Dictionary).get(
                "node_id", "")) == node_id:
            if not found.is_empty():
                return {}
            found = node_variant as Dictionary
    return found


static func endpoint(layout: Dictionary, collision_projection: Dictionary = {}) -> Dictionary:
    var verdict: Dictionary = validate_layout(layout, collision_projection)
    return (verdict.get("endpoint", {}) as Dictionary).duplicate(true) \
        if bool(verdict.get("ok", false)) else {}


static func join_collision_fingerprint(
        edge_placement_id: String, floor_placement_id: String,
        floor_module_id: String, collision_projection: Dictionary) -> String:
    var records: Array = [
        [edge_placement_id, PORTAL_MODULE],
        [floor_placement_id, floor_module_id],
    ]
    var canonical: String = "dock-join-collision-v2\n"
    for record_variant in records:
        var record: Array = record_variant
        var module: Dictionary = _projection_module(collision_projection, str(record[1]))
        if module.is_empty():
            return ""
        canonical += "placement=%s\nmodule=%s\ncontent=%s\n" % [
            str(record[0]), str(record[1]), str(module.get("content_sha256", ""))]
    return canonical.sha256_text()


static func _placement_module(plan_variant: Variant, placement_id: String) -> String:
    if not plan_variant is Dictionary:
        return ""
    for group in ["placements", "floor_placements"]:
        for placement_variant in (plan_variant as Dictionary).get(group, []):
            if placement_variant is Dictionary and str((placement_variant as Dictionary).get(
                    "placement_id", "")) == placement_id:
                return str((placement_variant as Dictionary).get("module_id", ""))
    return ""


static func _direction_rank(direction: String, fixed_lifeboat: bool) -> int:
    var order: Array = ["north", "south", "west", "east"] \
        if fixed_lifeboat else ["west", "east", "north", "south"]
    return order.find(direction)


static func _as_vector3(value: Variant) -> Vector3:
    if value is Vector3:
        return value
    if value is Array and (value as Array).size() == 3:
        return Vector3(float((value as Array)[0]), float((value as Array)[1]),
            float((value as Array)[2]))
    return Vector3.INF


## External endpoint authority must preserve its authored numeric types and all
## three coordinates. These helpers are intentionally separate from the
## compiler's permissive internal conversion helpers below.
static func _strict_integral_authority(value: Variant) -> Dictionary:
    if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
        return {"ok": false}
    var numeric: float = float(value)
    if not is_finite(numeric) or numeric != floor(numeric) \
            or numeric < -2147483648.0 or numeric > 2147483647.0:
        return {"ok": false}
    return {"ok": true, "value": int(numeric)}


static func _strict_deck_cell_authority(
        value: Variant, expected_deck: int) -> Dictionary:
    if value is Vector3i:
        var typed: Vector3i = value as Vector3i
        if typed.z != expected_deck:
            return {"ok": false}
        return {"ok": true, "cell": Vector2i(typed.x, typed.y)}
    if not value is Array or (value as Array).size() != 3:
        return {"ok": false}
    var parts: Array = value as Array
    var x_result: Dictionary = _strict_integral_authority(parts[0])
    var y_result: Dictionary = _strict_integral_authority(parts[1])
    var deck_result: Dictionary = _strict_integral_authority(parts[2])
    if not bool(x_result.get("ok", false)) or not bool(y_result.get("ok", false)) \
            or not bool(deck_result.get("ok", false)) \
            or int(deck_result.get("value", expected_deck + 1)) != expected_deck:
        return {"ok": false}
    return {"ok": true, "cell": Vector2i(
        int(x_result.get("value", 0)), int(y_result.get("value", 0)))}


static func _strict_vector3_authority(value: Variant) -> Dictionary:
    if value is Vector3:
        var typed: Vector3 = value as Vector3
        return {"ok": typed.is_finite(), "value": typed}
    if value is Vector3i:
        var typed_integer: Vector3i = value as Vector3i
        return {"ok": true, "value": Vector3(
            float(typed_integer.x), float(typed_integer.y), float(typed_integer.z))}
    if not value is Array or (value as Array).size() != 3:
        return {"ok": false}
    var parts: Array = value as Array
    for part in parts:
        if typeof(part) != TYPE_INT and typeof(part) != TYPE_FLOAT:
            return {"ok": false}
        if not is_finite(float(part)):
            return {"ok": false}
    return {"ok": true, "value": Vector3(
        float(parts[0]), float(parts[1]), float(parts[2]))}


static func _vector_array(value: Vector3) -> Array:
    return [value.x, value.y, value.z]


static func validate_collision_projection(projection: Dictionary) -> Dictionary:
    if str(projection.get("schema_version", "")) != PROJECTION_SCHEMA \
            or str(projection.get("numeric_encoding", "")) != PROJECTION_NUMERIC_ENCODING \
            or str(projection.get("content_encoding", "")) != PROJECTION_CONTENT_ENCODING \
            or not _has_exact_keys(projection, PROJECTION_KEYS) \
            or not projection.get("modules", null) is Dictionary:
        return {"ok": false, "reason": "collision_projection_missing_or_invalid"}
    var modules: Dictionary = projection.get("modules", {}) as Dictionary
    if modules.is_empty():
        return {"ok": false, "reason": "collision_projection_missing_or_invalid"}
    for module_key in modules:
        if not module_key is String or not modules[module_key] is Dictionary:
            return {"ok": false, "reason": "collision_projection_module_invalid"}
        var module: Dictionary = modules[module_key]
        if not _has_exact_keys(module, PROJECTION_MODULE_KEYS) \
                or str(module.get("module_id", "")) != str(module_key) \
                or not str(module.get("contract_path", "")).begins_with("res://") \
                or not str(module.get("wrapper_scene", "")).begins_with("res://") \
                or str(module.get("contract_sha256", "")).length() != 64 \
                or str(module.get("wrapper_sha256", "")).length() != 64 \
                or str(module.get("content_sha256", "")).length() != 64 \
                or not module.get("boxes", null) is Array \
                or (module.get("boxes", []) as Array).is_empty():
            return {"ok": false, "reason": "collision_projection_module_invalid"}
        var paths: Dictionary = {}
        var previous_path: String = ""
        var content: String = "%s\n" % PROJECTION_CONTENT_ENCODING
        for box_variant in module.get("boxes", []):
            if not box_variant is Dictionary:
                return {"ok": false, "reason": "collision_projection_box_invalid"}
            var box: Dictionary = box_variant
            var shape_path: String = str(box.get("shape_path", ""))
            if not _has_exact_keys(box, PROJECTION_BOX_KEYS) \
                    or shape_path.is_empty() or paths.has(shape_path) \
                    or (not previous_path.is_empty() and shape_path <= previous_path) \
                    or shape_path.contains("\n") or shape_path.contains("\r") \
                    or shape_path.contains("="):
                return {"ok": false, "reason": "collision_projection_box_path"}
            paths[shape_path] = true
            previous_path = shape_path
            if not _projection_box_transform(box).is_finite() \
                    or not _projection_dimensions(box).is_finite() \
                    or _projection_dimensions(box).x <= 0.0 \
                    or _projection_dimensions(box).y <= 0.0 \
                    or _projection_dimensions(box).z <= 0.0:
                return {"ok": false, "reason": "collision_projection_box_invalid"}
            var field_values: Array = [
                ["basis", box.get("basis", null), box.get("basis_f32_bits", null), 9],
                ["origin", box.get("origin", null), box.get("origin_f32_bits", null), 3],
                ["dimensions", box.get("dimensions", null),
                    box.get("dimensions_f32_bits", null), 3],
            ]
            content += "path=%s\n" % shape_path
            for field_variant in field_values:
                var field: Array = field_variant
                var values_variant: Variant = field[1]
                var bits_variant: Variant = field[2]
                var expected_count: int = int(field[3])
                if not _numeric_bits_match(
                        values_variant, bits_variant, expected_count):
                    return {"ok": false,
                        "reason": "collision_projection_numeric_bits_mismatch",
                        "module_id": str(module_key), "shape_path": shape_path,
                        "field": str(field[0])}
                content += "%s=%s\n" % [str(field[0]), ",".join(bits_variant as Array)]
        if content.sha256_text() != str(module.get("content_sha256", "")):
            return {"ok": false, "reason": "collision_projection_content_fingerprint",
                "module_id": str(module_key)}
    return {"ok": true, "reason": "ok"}


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
    if value.size() != expected.size():
        return false
    for key in expected:
        if not value.has(key):
            return false
    return true


static func _numeric_bits_match(
        values_variant: Variant, bits_variant: Variant,
        expected_count: int) -> bool:
    if not values_variant is Array or not bits_variant is Array \
            or (values_variant as Array).size() != expected_count \
            or (bits_variant as Array).size() != expected_count:
        return false
    for index in range(expected_count):
        var value_variant: Variant = (values_variant as Array)[index]
        var bit_string: String = str((bits_variant as Array)[index])
        if not (value_variant is float or value_variant is int) \
                or not is_finite(float(value_variant)) \
                or bit_string.length() != 8 \
                or _f32_bits(float(value_variant)) != bit_string:
            return false
    return true


static func _f32_bits(value: float) -> String:
    var bytes := PackedByteArray()
    bytes.resize(4)
    bytes.encode_float(0, value)
    return "%08x" % bytes.decode_u32(0)


static func _projection_module(projection: Dictionary, module_id: String) -> Dictionary:
    var modules_variant: Variant = projection.get("modules", null)
    if not modules_variant is Dictionary:
        return {}
    var module_variant: Variant = (modules_variant as Dictionary).get(module_id, null)
    return module_variant as Dictionary if module_variant is Dictionary else {}


static func _projection_box_transform(box: Dictionary) -> Transform3D:
    var basis_values: Variant = box.get("basis", null)
    var origin: Vector3 = _as_vector3(box.get("origin", []))
    if not basis_values is Array or (basis_values as Array).size() != 9:
        return Transform3D(Basis.IDENTITY, Vector3.INF)
    var values: Array = basis_values as Array
    var basis := Basis(
        Vector3(float(values[0]), float(values[1]), float(values[2])),
        Vector3(float(values[3]), float(values[4]), float(values[5])),
        Vector3(float(values[6]), float(values[7]), float(values[8])))
    return Transform3D(basis, origin)


static func _projection_dimensions(box: Dictionary) -> Vector3:
    return _as_vector3(box.get("dimensions", []))


static func _placement_transform(record: Dictionary) -> Transform3D:
    var yaw: float = fposmod(float(record.get("yaw_degrees", 0.0)), 360.0)
    var basis := Basis.IDENTITY
    if yaw == 0.0:
        basis = Basis.IDENTITY
    elif yaw == 90.0:
        basis = Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP, Vector3(1.0, 0.0, 0.0))
    elif yaw == 180.0:
        basis = Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP, Vector3(0.0, 0.0, -1.0))
    elif yaw == 270.0:
        basis = Basis(Vector3(0.0, 0.0, 1.0), Vector3.UP, Vector3(-1.0, 0.0, 0.0))
    else:
        return Transform3D(Basis.IDENTITY, Vector3.INF)
    var placement_scale: Vector3 = _as_vector3(record.get("scale", Vector3.ONE))
    if not placement_scale.is_finite() or placement_scale.x <= 0.0 \
            or placement_scale.y <= 0.0 or placement_scale.z <= 0.0:
        return Transform3D(Basis.IDENTITY, Vector3.INF)
    basis = basis * Basis.from_scale(placement_scale)
    return Transform3D(basis, _as_vector3(record.get("position", [])))


static func _portal_outward_extent(
        collision_projection: Dictionary, edge_placement: Dictionary) -> float:
    var module: Dictionary = _projection_module(collision_projection, PORTAL_MODULE)
    var placement: Transform3D = _placement_transform(edge_placement)
    if module.is_empty() or not placement.is_finite():
        return INF
    var edge_position: Vector3 = _as_vector3(edge_placement.get("position", []))
    var direction: String = str(edge_placement.get("direction", ""))
    var outward: Vector3 = OUTWARD_NORMALS.get(direction, Vector3.ZERO) as Vector3
    var extent: float = -INF
    for box_variant in module.get("boxes", []):
        var box: Dictionary = box_variant
        var size: Vector3 = _projection_dimensions(box)
        var bounds: AABB = placement * _projection_box_transform(box) * AABB(-size * 0.5, size)
        for corner in _aabb_corners(bounds):
            extent = maxf(extent, (corner - edge_position).dot(outward))
    return extent


static func _candidate_supporting_plane_verdict(
        plan: Dictionary, edge: Dictionary, edge_placement: Dictionary,
        floor_placement: Dictionary, collision_projection: Dictionary) -> Dictionary:
    var outward: Vector3 = OUTWARD_NORMALS.get(str(edge.get("direction", "")), Vector3.ZERO)
    var edge_position: Vector3 = _as_vector3(edge.get("position", []))
    var extent: float = _portal_outward_extent(collision_projection, edge_placement)
    if outward == Vector3.ZERO or not is_finite(extent):
        return {"ok": false, "reason": "support_geometry_invalid"}
    var plane_distance: float = edge_position.dot(outward) + extent
    var tangent := Vector3(-outward.z, 0.0, outward.x)
    var aperture_min_t: float = INF
    var aperture_max_t: float = -INF
    var aperture_min_y: float = INF
    var aperture_max_y: float = -INF
    var doorway_module: Dictionary = _projection_module(collision_projection, PORTAL_MODULE)
    var doorway_placement: Transform3D = _placement_transform(edge_placement)
    for box_variant in doorway_module.get("boxes", []):
        var box: Dictionary = box_variant
        var size: Vector3 = _projection_dimensions(box)
        var bounds: AABB = doorway_placement * _projection_box_transform(box) \
            * AABB(-size * 0.5, size)
        for corner in _aabb_corners(bounds):
            aperture_min_t = minf(aperture_min_t, corner.dot(tangent))
            aperture_max_t = maxf(aperture_max_t, corner.dot(tangent))
            aperture_min_y = minf(aperture_min_y, corner.y)
            aperture_max_y = maxf(aperture_max_y, corner.y)
    var join_ids: Dictionary = {
        str(edge_placement.get("placement_id", edge_placement.get("id", ""))): true,
        str(floor_placement.get("placement_id", floor_placement.get("id", ""))): true,
    }
    for group in ["floor_placements", "placements", "ceiling_placements"]:
        for placement_variant in plan.get(group, []):
            if not placement_variant is Dictionary:
                return {"ok": false, "reason": "support_record_invalid",
                    "group": group}
            var record: Dictionary = placement_variant
            var placement_id: String = str(record.get("placement_id", record.get("id", "")))
            if join_ids.has(placement_id):
                continue
            var module: Dictionary = _projection_module(
                collision_projection, str(record.get("module_id", "")))
            var placement: Transform3D = _placement_transform(record)
            if module.is_empty() or not placement.is_finite():
                return {"ok": false, "reason": "support_projection_invalid",
                    "placement_id": placement_id,
                    "module_id": str(record.get("module_id", ""))}
            for box_variant in module.get("boxes", []):
                var box: Dictionary = box_variant
                var size: Vector3 = _projection_dimensions(box)
                var bounds: AABB = placement * _projection_box_transform(box) \
                    * AABB(-size * 0.5, size)
                var min_t: float = INF
                var max_t: float = -INF
                var max_outward: float = -INF
                for corner in _aabb_corners(bounds):
                    min_t = minf(min_t, corner.dot(tangent))
                    max_t = maxf(max_t, corner.dot(tangent))
                    max_outward = maxf(max_outward, corner.dot(outward))
                var tangent_overlap: bool = minf(max_t, aperture_max_t) \
                    > maxf(min_t, aperture_min_t)
                var up_overlap: bool = minf(bounds.end.y, aperture_max_y) \
                    > maxf(bounds.position.y, aperture_min_y)
                if tangent_overlap and up_overlap and max_outward > plane_distance:
                    return {"ok": false, "reason": "support_shape_outward",
                        "placement_id": placement_id,
                        "module_id": str(record.get("module_id", "")),
                        "shape_path": str(box.get("shape_path", "")),
                        "max_outward": max_outward,
                        "plane_distance": plane_distance,
                        "tangent_overlap": tangent_overlap,
                        "up_overlap": up_overlap}
    return {"ok": true, "reason": "ok"}


## Checks a prospective host endpoint against the complete authenticated
## counterpart hull before mutating the host plan. This prevents deterministic
## candidate ordering from publishing a locally valid endpoint that can never
## pass the registered-pair transaction.
static func _candidate_pair_clear(
        plan: Dictionary, edge: Dictionary, edge_placement: Dictionary,
        floor_placement: Dictionary, counterpart_layout: Dictionary,
        collision_projection: Dictionary) -> Dictionary:
    if counterpart_layout.is_empty():
        return {"ok": true, "reason": "no_counterpart"}
    var counterpart_verdict: Dictionary = validate_layout(
        counterpart_layout, collision_projection)
    if not bool(counterpart_verdict.get("ok", false)):
        return {"ok": false, "reason": "counterpart_endpoint_invalid",
            "detail": str(counterpart_verdict.get("reason", ""))}
    var direction: String = str(edge.get("direction", ""))
    var host_outward: Vector3 = OUTWARD_NORMALS.get(direction, Vector3.ZERO)
    var edge_position: Vector3 = _as_vector3(edge.get("position", []))
    var host_extent: float = _portal_outward_extent(
        collision_projection, edge_placement)
    var counterpart_endpoint: Dictionary = counterpart_verdict.get(
        "endpoint", {}) as Dictionary
    var counterpart_position: Vector3 = _as_vector3(
        counterpart_endpoint.get("local_position", []))
    var counterpart_outward: Vector3 = _as_vector3(
        counterpart_endpoint.get("outward_normal", []))
    var alignment_basis_variant: Variant = _exact_cardinal_alignment_basis(
        counterpart_outward, -host_outward)
    if host_outward == Vector3.ZERO or not edge_position.is_finite() \
            or not is_finite(host_extent) or not counterpart_position.is_finite() \
            or not alignment_basis_variant is Basis:
        return {"ok": false, "reason": "candidate_pair_transform_invalid"}
    var host_position: Vector3 = edge_position + host_outward * host_extent
    var alignment_basis: Basis = alignment_basis_variant as Basis
    var counterpart_transform := Transform3D(
        alignment_basis, host_position - alignment_basis * counterpart_position)
    var host_join_ids: Dictionary = {
        str(edge_placement.get("placement_id", edge_placement.get("id", ""))): true,
        str(floor_placement.get("placement_id", floor_placement.get("id", ""))): true,
    }
    var counterpart_join_ids: Dictionary = {}
    for placement_id in counterpart_endpoint.get("join_piece_placement_ids", []):
        counterpart_join_ids[str(placement_id)] = true
    var candidate_id: String = str(edge_placement.get(
        "placement_id", edge_placement.get("id", "")))
    var host_boxes: Dictionary = _projected_plan_boxes(
        plan, Transform3D.IDENTITY, collision_projection, host_join_ids,
        candidate_id, PORTAL_MODULE)
    var counterpart_plan_variant: Variant = counterpart_layout.get(
        "structural_plan", null)
    if not counterpart_plan_variant is Dictionary:
        return {"ok": false, "reason": "counterpart_plan_missing"}
    var counterpart_boxes: Dictionary = _projected_plan_boxes(
        counterpart_plan_variant as Dictionary, counterpart_transform,
        collision_projection, counterpart_join_ids)
    if not bool(host_boxes.get("ok", false)):
        return host_boxes
    if not bool(counterpart_boxes.get("ok", false)):
        return counterpart_boxes
    var collision_verdict: Dictionary = validate_projected_cross_hull_boxes(
        host_boxes.get("boxes", []), counterpart_boxes.get("boxes", []))
    if not bool(collision_verdict.get("ok", false)):
        var rejection: Dictionary = collision_verdict.duplicate(true)
        if str(rejection.get("reason", "")) == "cross_hull_overlap":
            rejection["reason"] = "candidate_cross_hull_overlap"
        rejection.merge({
            "edge_key": str(edge.get("edge_key", edge.get("key", ""))),
            "direction": direction,
            "host_position": _vector_array(host_position),
            "host_outward": _vector_array(host_outward),
            "host_outer_extent": host_extent,
            "counterpart_endpoint_id": str(counterpart_endpoint.get("endpoint_id", "")),
            "counterpart_local_position": _vector_array(counterpart_position),
            "counterpart_outward": _vector_array(counterpart_outward),
            "counterpart_transform_origin": _vector_array(counterpart_transform.origin),
        })
        return rejection
    return {"ok": true, "reason": "ok", "edge_key": str(
        edge.get("edge_key", edge.get("key", ""))), "direction": direction,
        "host_position": _vector_array(host_position),
        "host_outward": _vector_array(host_outward),
        "host_outer_extent": host_extent,
        "counterpart_endpoint_id": str(counterpart_endpoint.get("endpoint_id", "")),
        "counterpart_local_position": _vector_array(counterpart_position),
        "counterpart_outward": _vector_array(counterpart_outward),
        "counterpart_transform_origin": _vector_array(counterpart_transform.origin)}


static func _projected_plan_boxes(
        plan: Dictionary, root_transform: Transform3D,
        collision_projection: Dictionary, join_ids: Dictionary,
        override_placement_id: String = "", override_module_id: String = "") -> Dictionary:
    var boxes: Array[Dictionary] = []
    for group in ["floor_placements", "placements", "ceiling_placements"]:
        var records_variant: Variant = plan.get(group, null)
        if not records_variant is Array:
            return {"ok": false, "reason": "candidate_plan_group_invalid",
                "group": group}
        for record_variant in records_variant:
            if not record_variant is Dictionary:
                return {"ok": false, "reason": "candidate_plan_record_invalid"}
            var record: Dictionary = record_variant
            var placement_id: String = str(record.get(
                "placement_id", record.get("id", "")))
            var module_id: String = override_module_id \
                if placement_id == override_placement_id \
                else str(record.get("module_id", ""))
            if module_id.is_empty():
                continue
            var module: Dictionary = _projection_module(
                collision_projection, module_id)
            var placement: Transform3D = _placement_transform(record)
            if module.is_empty() or not placement.is_finite():
                return {"ok": false, "reason": "candidate_collision_record_invalid",
                    "placement_id": placement_id, "module_id": module_id}
            for box_variant in module.get("boxes", []):
                if not box_variant is Dictionary:
                    return {"ok": false, "reason": "collision_projection_box_invalid"}
                var box: Dictionary = box_variant
                var dimensions: Vector3 = _projection_dimensions(box)
                var shape_transform: Transform3D = _projection_box_transform(box)
                if not dimensions.is_finite() or not shape_transform.is_finite():
                    return {"ok": false, "reason": "collision_projection_box_invalid"}
                boxes.append({
                    "placement_id": placement_id,
                    "shape_path": str(box.get("shape_path", "")),
                    "join": join_ids.has(placement_id),
                    "aabb": root_transform * placement * shape_transform \
                        * AABB(-dimensions * 0.5, dimensions),
                })
    return {"ok": true, "reason": "ok", "boxes": boxes}


static func _exact_cardinal_alignment_basis(from: Vector3, to: Vector3) -> Variant:
    var from_index: int = _cardinal_index(from)
    var to_index: int = _cardinal_index(to)
    if from_index < 0 or to_index < 0:
        return null
    match posmod(to_index - from_index, 4):
        1:
            return Basis(Vector3(0.0, 0.0, -1.0), Vector3.UP,
                Vector3(1.0, 0.0, 0.0))
        2:
            return Basis(Vector3(-1.0, 0.0, 0.0), Vector3.UP,
                Vector3(0.0, 0.0, -1.0))
        3:
            return Basis(Vector3(0.0, 0.0, 1.0), Vector3.UP,
                Vector3(-1.0, 0.0, 0.0))
        _:
            return Basis.IDENTITY


static func _cardinal_index(value: Vector3) -> int:
    if value == Vector3(0.0, 0.0, 1.0):
        return 0
    if value == Vector3(1.0, 0.0, 0.0):
        return 1
    if value == Vector3(0.0, 0.0, -1.0):
        return 2
    if value == Vector3(-1.0, 0.0, 0.0):
        return 3
    return -1


static func _positive_intersection(a: AABB, b: AABB) -> AABB:
    var minimum := Vector3(maxf(a.position.x, b.position.x),
        maxf(a.position.y, b.position.y), maxf(a.position.z, b.position.z))
    var maximum := Vector3(minf(a.end.x, b.end.x),
        minf(a.end.y, b.end.y), minf(a.end.z, b.end.z))
    if maximum.x <= minimum.x or maximum.y <= minimum.y \
            or maximum.z <= minimum.z:
        return AABB()
    return AABB(minimum, maximum - minimum)


## Shared pure static collision transaction used by both endpoint selection and
## DockingManager publication. Every positive-volume cross-hull intersection
## rejects. Join labels authenticate placement identity and grant no exception.
static func validate_projected_cross_hull_boxes(
        host_boxes: Array, mobile_boxes: Array) -> Dictionary:
    var overlaps: Array[Dictionary] = []
    for host_box_variant in host_boxes:
        if not host_box_variant is Dictionary:
            return {"ok": false, "reason": "malformed_collision_record"}
        var host_box: Dictionary = host_box_variant
        for mobile_box_variant in mobile_boxes:
            if not mobile_box_variant is Dictionary:
                return {"ok": false, "reason": "malformed_collision_record"}
            var mobile_box: Dictionary = mobile_box_variant
            var intersection: AABB = _positive_intersection(
                host_box.get("aabb", AABB()) as AABB,
                mobile_box.get("aabb", AABB()) as AABB)
            if intersection.size == Vector3.ZERO:
                continue
            overlaps.append({
                "host": _box_identity(host_box),
                "mobile": _box_identity(mobile_box),
                "host_join": bool(host_box.get("join", false)),
                "mobile_join": bool(mobile_box.get("join", false)),
                "intersection_position": _vector_array(intersection.position),
                "intersection_size": _vector_array(intersection.size),
            })
    if not overlaps.is_empty():
        return {"ok": false, "reason": "cross_hull_overlap",
            "overlap_count": overlaps.size(), "overlaps": overlaps}
    return {"ok": true, "reason": "ok", "cross_hull_overlap_count": 0}


static func _box_identity(box: Dictionary) -> String:
    return "%s/%s" % [str(box.get("placement_id", "")), str(
        box.get("shape_path", box.get("shape_name", "")))]


static func _edge_placement(placements_variant: Variant, edge_key: String) -> Dictionary:
    if not placements_variant is Array:
        return {}
    for placement_variant in placements_variant:
        if placement_variant is Dictionary and str((placement_variant as Dictionary).get(
                "edge_key", (placement_variant as Dictionary).get("key", ""))) == edge_key:
            return placement_variant as Dictionary
    return {}


static func _floor_placement(floors_variant: Variant, cell_key: String) -> Dictionary:
    if not floors_variant is Array:
        return {}
    for floor_variant in floors_variant:
        if floor_variant is Dictionary and str((floor_variant as Dictionary).get(
                "cell_key", "")) == cell_key:
            return floor_variant as Dictionary
    return {}


static func _aabb_corners(bounds: AABB) -> Array[Vector3]:
    var result: Array[Vector3] = []
    for x in [bounds.position.x, bounds.end.x]:
        for y in [bounds.position.y, bounds.end.y]:
            for z in [bounds.position.z, bounds.end.z]:
                result.append(Vector3(x, y, z))
    return result


static func _as_cell(value: Variant) -> Vector2i:
    if value is Vector2i:
        return value
    if value is Array and (value as Array).size() >= 2:
        return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
    return Vector2i(2147483647, 2147483647)
