extends SceneTree

## ADR-0053 / REQ-ENC-001..004 RED gate.
## Fails closed on floor-only rooms, gapped placement, unused sockets,
## missing ceilings/corners, mis-authored floor axes, and hub layouts
## without a structural_plan.
##
## RED marker:  SOCKETED ENCLOSURE FAIL ...
## GREEN marker: SOCKETED ENCLOSURE PASS no_floor_only=true no_room_gap=true sockets_consumed=true watertight=true corners_used=true floor_socket_axes=true hub_plan=true
##
## Not in the regression bundle until GREEN. Exit code is not the contract.

const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")

const FLOOR_CONTRACT := "res://data/placement/contracts/structural/ship_structural_v0/floor_1x1_contract.json"
const WALL_CONTRACT := "res://data/placement/contracts/structural/ship_structural_v0/wall_straight_1x1_contract.json"
const CEILING_CONTRACT := "res://data/placement/contracts/structural/ship_structural_v0/ceiling_cap_1x1_contract.json"
const COMPILER_SOURCE := "res://scripts/procgen/structural_edge_compiler.gd"
const LIFEBOAT_SOURCE := "res://scripts/procgen/life_boat.gd"
const CELL_LAYOUT_SOURCE := "res://scripts/procgen/cell_layout_engine.gd"
const GENERATOR_SOURCE := "res://scripts/procgen/ship_layout_generator.gd"
const LIVE_ROOM_GAP_SOURCES: Array[String] = [
	LIFEBOAT_SOURCE,
	CELL_LAYOUT_SOURCE,
	GENERATOR_SOURCE,
]

const CORNER_MODULE_IDS: Array[String] = [
	"wall_inner_corner",
	"wall_outer_corner",
	"wall_t_junction",
]
const CEILING_MODULE_STEMS: Array[String] = [
	"ceiling_cap_1x1",
	"ceiling",
]


func _initialize() -> void:
	var issues: Array[String] = []
	_check_floor_socket_axes(issues)
	_check_socket_kinds(issues)
	_check_compiler_consumes_sockets(issues)
	_check_room_gap(issues)
	_check_hub_layout(issues)
	_check_generated_layout(issues)
	_check_lifeboat_build_caller(issues)

	if not issues.is_empty():
		push_error("SOCKETED ENCLOSURE FAIL count=%d %s" % [issues.size(), _join_issues(issues)])
		quit(1)
		return

	print(
		"SOCKETED ENCLOSURE PASS no_floor_only=true no_room_gap=true sockets_consumed=true watertight=true corners_used=true floor_socket_axes=true hub_plan=true"
	)
	quit(0)


func _check_floor_socket_axes(issues: Array[String]) -> void:
	var contract: Dictionary = _load_json(FLOOR_CONTRACT)
	if contract.is_empty():
		issues.append("floor_socket_axes:missing_contract")
		return
	var sockets: Array = _sockets_of(contract)
	var expected: Dictionary = {
		"floor_edge_north_01": [0.0, 0.0, -2.0],
		"floor_edge_south_01": [0.0, 0.0, 2.0],
		"floor_edge_east_01": [2.0, 0.0, 0.0],
		"floor_edge_west_01": [-2.0, 0.0, 0.0],
	}
	var found: Dictionary = {}
	for socket_variant in sockets:
		if typeof(socket_variant) != TYPE_DICTIONARY:
			continue
		var socket: Dictionary = socket_variant
		var sid: String = str(socket.get("id", ""))
		if expected.has(sid):
			found[sid] = _vec3(socket.get("position_m", []))
	for sid in expected.keys():
		if not found.has(sid):
			issues.append("floor_socket_axes:missing_%s" % sid)
			continue
		var got: Vector3 = found[sid]
		var want: Array = expected[sid]
		if not _approx3(got, Vector3(want[0], want[1], want[2])):
			issues.append("floor_socket_axes:%s=%s" % [sid, str(got)])
	var kinds: Array = _compatible_kinds_for(sockets, "floor_edge_north_01")
	if not kinds.has("wall_base"):
		issues.append("floor_socket_axes:floor_edge_missing_wall_base")


func _check_socket_kinds(issues: Array[String]) -> void:
	var wall: Dictionary = _load_json(WALL_CONTRACT)
	if wall.is_empty():
		issues.append("sockets_unused:missing_wall_contract")
	else:
		var wall_kinds: Array[String] = _all_kinds(_sockets_of(wall))
		if not wall_kinds.has("wall_base"):
			issues.append("sockets_unused:wall_missing_wall_base")
	var ceiling: Dictionary = _load_json(CEILING_CONTRACT)
	if ceiling.is_empty():
		issues.append("no_ceilings:missing_ceiling_contract")
		return
	var ceiling_kinds: Array[String] = _all_kinds(_sockets_of(ceiling))
	if not ceiling_kinds.has("ceiling_edge") and not ceiling_kinds.has("ceiling_bottom"):
		issues.append("no_ceilings:ceiling_sockets_not_enclosure")


func _check_compiler_consumes_sockets(issues: Array[String]) -> void:
	var src: String = FileAccess.get_file_as_string(COMPILER_SOURCE)
	if src.is_empty():
		issues.append("sockets_unused:compiler_unreadable")
		return
	if src.find("compatible_kinds") < 0:
		issues.append("sockets_unused:compiler_ignores_compatible_kinds")
	if src.find("socket_bindings") < 0:
		issues.append("sockets_unused:compiler_no_socket_bindings")


func _check_room_gap(issues: Array[String]) -> void:
	for path in LIVE_ROOM_GAP_SOURCES:
		var src: String = FileAccess.get_file_as_string(path)
		if src.is_empty():
			issues.append("room_gap:unreadable=%s" % path.get_file())
			continue
		if src.find("ROOM_GAP") >= 0:
			issues.append("room_gap:live_path=%s" % path.get_file())


func _check_hub_layout(issues: Array[String]) -> void:
	var layout: Dictionary = LifeBoatBuilderScript.build_layout()
	if str(layout.get("schema_version", "")) != "1.2.0":
		issues.append("hub_plan_missing:schema=%s" % str(layout.get("schema_version", "")))
	var plan_variant: Variant = layout.get("structural_plan", null)
	if typeof(plan_variant) != TYPE_DICTIONARY or (plan_variant as Dictionary).is_empty():
		issues.append("hub_plan_missing:no_structural_plan")
	var rooms: Array = layout.get("rooms", [])
	if rooms.is_empty():
		issues.append("floor_only:hub_no_rooms")
		return
	var floor_only_rooms: int = 0
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		if _room_is_floor_only(room):
			floor_only_rooms += 1
	if floor_only_rooms > 0:
		issues.append("floor_only:hub_rooms=%d" % floor_only_rooms)
	var portals: Array = layout.get("portals", [])
	var room_portals_empty: bool = true
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room_portals: Array = (room_variant as Dictionary).get("portals", [])
		if not room_portals.is_empty():
			room_portals_empty = false
	if portals.is_empty() and room_portals_empty:
		issues.append("floor_only:hub_empty_portals")
	if typeof(plan_variant) == TYPE_DICTIONARY:
		_audit_structural_plan(plan_variant as Dictionary, "hub", issues)


func _check_generated_layout(issues: Array[String]) -> void:
	var generator: RefCounted = ShipLayoutGeneratorScript.new()
	var blueprint: RefCounted = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.WRECKED,
		42)
	var layout: Dictionary = generator.generate(blueprint, {"name": "derelict", "type": "derelict"})
	if layout.is_empty():
		issues.append("watertight:generated_layout_empty")
		return
	var plan_variant: Variant = layout.get("structural_plan", null)
	if typeof(plan_variant) != TYPE_DICTIONARY:
		issues.append("watertight:generated_missing_structural_plan")
		return
	_audit_structural_plan(plan_variant as Dictionary, "generated", issues)
	var rooms: Array = layout.get("rooms", [])
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		if _room_is_floor_only(room_variant):
			issues.append("floor_only:generated_room=%s" % str((room_variant as Dictionary).get("id", "")))
			break


func _check_lifeboat_build_caller(issues: Array[String]) -> void:
	var src: String = FileAccess.get_file_as_string(LIFEBOAT_SOURCE)
	if src.is_empty():
		issues.append("room_gap:lifeboat_unreadable")
		return
	if src.find("place_structure") >= 0:
		issues.append("room_gap:lifeboat_calls_structural_placer")


func _audit_structural_plan(plan: Dictionary, label: String, issues: Array[String]) -> void:
	var floors: Array = plan.get("floor_placements", []) as Array
	var edges: Array = plan.get("placements", []) as Array
	var occupancy: Dictionary = plan.get("occupancy", {}) as Dictionary
	if floors.is_empty() and occupancy.is_empty():
		issues.append("floor_only:%s_no_floors" % label)
	var ceilings: Array = plan.get("ceiling_placements", []) as Array
	if ceilings.is_empty():
		var implied_ceilings: int = 0
		for record_variant in edges:
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			if _is_ceiling_module(str((record_variant as Dictionary).get("module_id", ""))):
				implied_ceilings += 1
		if implied_ceilings <= 0:
			issues.append("no_ceilings:%s" % label)
	var bindings: Variant = plan.get("socket_bindings", null)
	var bound_count: int = 0
	if typeof(bindings) == TYPE_ARRAY:
		bound_count = (bindings as Array).size()
	elif typeof(bindings) == TYPE_DICTIONARY:
		bound_count = (bindings as Dictionary).size()
	if bound_count <= 0:
		var placement_bound: int = 0
		for record_variant in edges:
			if typeof(record_variant) != TYPE_DICTIONARY:
				continue
			if (record_variant as Dictionary).has("socket_bindings"):
				placement_bound += 1
		if placement_bound <= 0:
			issues.append("sockets_unused:%s_no_bindings" % label)
	var corner_count: int = 0
	for record_variant in edges:
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var module_id: String = str((record_variant as Dictionary).get("module_id", ""))
		for stem in CORNER_MODULE_IDS:
			if module_id.find(stem) >= 0:
				corner_count += 1
				break
	if corner_count <= 0:
		issues.append("no_corners:%s" % label)
	if occupancy.size() > 0 and floors.size() > 0 and occupancy.size() != floors.size():
		issues.append("watertight:%s_floor_occupancy_mismatch" % label)


func _room_is_floor_only(room: Dictionary) -> bool:
	var placements: Array = room.get("structural_placements", []) as Array
	if placements.is_empty():
		return true
	var non_floor: int = 0
	for placement_variant in placements:
		if typeof(placement_variant) != TYPE_DICTIONARY:
			continue
		var module_id: String = str(
			(placement_variant as Dictionary).get(
				"module_id",
				(placement_variant as Dictionary).get("module", "")))
		if module_id.find("wall") >= 0 or module_id.find("door") >= 0 or module_id.find("portal") >= 0:
			non_floor += 1
		if _is_ceiling_module(module_id):
			non_floor += 1
	return non_floor <= 0


func _is_ceiling_module(module_id: String) -> bool:
	for stem in CEILING_MODULE_STEMS:
		if module_id.find(stem) >= 0:
			return true
	return false


func _sockets_of(contract: Dictionary) -> Array:
	var sockets_variant: Variant = contract.get("sockets", null)
	if typeof(sockets_variant) == TYPE_ARRAY and not (sockets_variant as Array).is_empty():
		return sockets_variant
	var asset_variant: Variant = contract.get("asset", null)
	if typeof(asset_variant) == TYPE_DICTIONARY:
		var nested: Variant = (asset_variant as Dictionary).get("sockets", [])
		if typeof(nested) == TYPE_ARRAY:
			return nested
	return []


func _compatible_kinds_for(sockets: Array, socket_id: String) -> Array:
	for socket_variant in sockets:
		if typeof(socket_variant) != TYPE_DICTIONARY:
			continue
		var socket: Dictionary = socket_variant
		if str(socket.get("id", "")) != socket_id:
			continue
		var kinds_variant: Variant = socket.get("compatible_kinds", [])
		if typeof(kinds_variant) != TYPE_ARRAY:
			return []
		return kinds_variant
	return []


func _all_kinds(sockets: Array) -> Array[String]:
	var kinds: Array[String] = []
	for socket_variant in sockets:
		if typeof(socket_variant) != TYPE_DICTIONARY:
			continue
		var kind: String = str((socket_variant as Dictionary).get("kind", ""))
		if not kind.is_empty() and not kinds.has(kind):
			kinds.append(kind)
	return kinds


func _vec3(raw: Variant) -> Vector3:
	if typeof(raw) != TYPE_ARRAY:
		return Vector3.INF
	var arr: Array = raw
	if arr.size() < 3:
		return Vector3.INF
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _approx3(got: Vector3, want: Vector3) -> bool:
	return got.distance_to(want) <= 0.001


func _join_issues(issues: Array[String]) -> String:
	var out: String = ""
	for i in range(issues.size()):
		if i > 0:
			out += "|"
		out += issues[i]
	return out


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}
