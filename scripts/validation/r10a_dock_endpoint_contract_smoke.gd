extends SceneTree

const DockEndpointAuthoringScript := preload("res://scripts/procgen/dock_endpoint_authoring.gd")
const DockPortsScript := preload("res://scripts/systems/dock_ports.gd")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
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
    var lifeboat: Dictionary = LifeBoatBuilderScript.build_layout()
    if not _check_layout(lifeboat, "lifeboat"):
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

    var home: Variant = JSON.parse_string(FileAccess.get_file_as_string(
        "res://data/procgen/golden/coherent_ship_001/layout.json"))
    if not home is Dictionary or not _check_layout(home as Dictionary, "home"):
        return

    var lifeboat_port: Dictionary = DockPortsScript.for_lifeboat(lifeboat)
    var home_port: Dictionary = DockPortsScript.for_derelict(home as Dictionary)
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
    print("R10A DOCK ENDPOINT CONTRACT PASS")
    quit(0)

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
        _fail("native seed42 authoring failed")
        return false
    var old_endpoint: Dictionary = old_layout.boarding_endpoints_v1[0]
    var paired_endpoint: Dictionary = paired_layout.boarding_endpoints_v1[0]
    if str(old_endpoint.get("structural_edge_key", "")) != "0|h|7|8" \
            or str(paired_endpoint.get("structural_edge_key", "")) != "0|v|3|3":
        _fail("native seed42 deterministic candidate order changed")
        return false
    var rejections: Array = paired_result.get("candidate_pair_rejections", [])
    if rejections.size() != 1:
        _fail("native seed42 expected exactly one rejected pair")
        return false
    var rejected: Dictionary = rejections[0]
    if str(rejected.get("reason", "")) != "candidate_non_join_hull_overlap" \
            or int(rejected.get("overlap_count", -1)) != 2 \
            or str(rejected.get("edge_key", "")) != "0|h|7|8":
        _fail("native seed42 rejected-pair geometry changed")
        return false
    for overlap_variant in rejected.get("overlaps", []):
        var mobile_identity: String = str(
            (overlap_variant as Dictionary).get("mobile", ""))
        if mobile_identity != "edge:0|h|-1|-1/CollisionRoot/CollisionShape3D_WingEast":
            _fail("native seed42 rejection no longer names the measured WingEast")
            return false
    var corner_record: Dictionary = {}
    for record_variant in lifeboat.structural_plan.placements:
        if record_variant is Dictionary and str((record_variant as Dictionary).get(
                "placement_id", "")) == "edge:0|h|-1|-1":
            corner_record = record_variant
            break
    if str(corner_record.get("module_id", "")) != "wall_outer_corner":
        _fail("lifeboat measured WingEast no longer belongs to wall_outer_corner")
        return false
    return true

func _fail(reason: String) -> void:
    push_error("R10A DOCK ENDPOINT CONTRACT FAIL reason=%s" % reason)
    quit(1)
