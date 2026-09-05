extends RefCounted
class_name FirstRunContract

## Data contract for the cold-player's first away derelict beat.
## The helper is pure at validation time: callers provide the generated layout
## and gameplay slice dictionaries, while seed selection remains deterministic.

const CONTRACT_PATH: String = "res://data/procgen/slice/first_run_contract.json"
const RoomVariantSelectorScript: GDScript = preload("res://scripts/procgen/room_variant_selector.gd")
const ShipNavGraphScript: GDScript = preload("res://scripts/systems/ship_nav_graph.gd")
const ThreatPathfinderScript: GDScript = preload("res://scripts/systems/threat_pathfinder.gd")

const FLOOR_Y_OFFSET: float = 0.12

var contract: Dictionary = {}


func load_contract(path: String = CONTRACT_PATH) -> bool:
	contract = {}
	if not FileAccess.file_exists(path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return false
	var data: Dictionary = parsed
	if str(data.get("version", "")) != "first-run-contract-1":
		return false
	if str(data.get("biome_id", "")).is_empty() or str(data.get("difficulty_id", "")).is_empty():
		return false
	if not (data.get("preferred_seeds", []) is Array) or (data.get("preferred_seeds", []) as Array).is_empty():
		return false
	if typeof(data.get("require_standing_route", null)) != TYPE_BOOL \
			or not bool(data.get("require_standing_route", false)):
		return false
	contract = data.duplicate(true)
	return true


func validate(layout: Dictionary, gameplay_slice: Dictionary = {}) -> bool:
	return validation_failure_reason(layout, gameplay_slice).is_empty()


## Returns the first unsatisfied predicate in contract order. This keeps seed
## selection boolean while allowing validation to prove that an otherwise
## qualified native candidate was rejected specifically for standing access.
func validation_failure_reason(layout: Dictionary, gameplay_slice: Dictionary = {}) -> String:
	if contract.is_empty() and not load_contract():
		return "contract"
	if layout.is_empty() or gameplay_slice.is_empty():
		return "candidate"
	if not layout.has("biome_id") or str(layout.get("biome_id", "")) != str(contract.get("biome_id", "")):
		return "biome"
	if not layout.has("difficulty_id") or str(layout.get("difficulty_id", "")) != str(contract.get("difficulty_id", "")):
		return "difficulty"
	var loot: Variant = gameplay_slice.get("loot_containers", [])
	if not (loot is Array) or (loot as Array).size() < int(contract.get("require_min_loot_containers", 0)):
		return "loot"
	var encounters: Variant = layout.get("encounters", [])
	if not (encounters is Array) or (encounters as Array).size() < int(contract.get("require_min_encounters", 0)):
		return "encounters"
	var required_hazards: Variant = contract.get("require_any", [])
	if not (required_hazards is Array) or not _has_any_required_hazard(layout, gameplay_slice, required_hazards as Array):
		return "hazards"
	if not _has_standing_route(layout, gameplay_slice):
		return "standing_route"
	return ""


## Returns the first preferred seed whose generated payload is accepted by the
## contract. A Dictionary maps seed -> {"layout": Dictionary,
## "gameplay_slice": Dictionary}; a Callable may be supplied when generation
## must happen lazily. Invalid candidates are simply skipped.
## Returns -1 when no preferred seed validates. Callers must fail closed rather
## than materializing a candidate the contract rejected.
func pick_seed(candidates: Variant = null) -> int:
	if contract.is_empty() and not load_contract():
		return -1
	var preferred: Array = contract.get("preferred_seeds", []) as Array
	if preferred.is_empty():
		return -1
	for seed_variant in preferred:
		var seed_value: int = int(seed_variant)
		var candidate: Variant = null
		if candidates is Callable:
			var provider: Callable = candidates
			if provider.is_valid():
				candidate = provider.call(seed_value)
		elif candidates is Dictionary:
			candidate = (candidates as Dictionary).get(seed_value, {})
		if not (candidate is Dictionary):
			continue
		var candidate_dict: Dictionary = candidate
		if validate(candidate_dict.get("layout", {}), candidate_dict.get("gameplay_slice", {})):
			return seed_value
	return -1


func _has_standing_route(layout: Dictionary, gameplay_slice: Dictionary) -> bool:
	var graph = ShipNavGraphScript.new()
	if graph.build_from_layout(layout) <= 0:
		return false
	var prototype_variant: Variant = layout.get("prototype", {})
	if not (prototype_variant is Dictionary):
		return false
	var prototype: Dictionary = prototype_variant
	var start_room: String = str(gameplay_slice.get("start_room", prototype.get("start_room", "")))
	var goal_room: String = str(gameplay_slice.get("goal_room", prototype.get("goal_room", "")))
	if start_room.is_empty() or goal_room.is_empty():
		return false
	var start_position: Vector3 = _room_center(layout, start_room)
	var goal_position: Vector3 = _room_center(layout, goal_room)
	if start_position == Vector3.INF or goal_position == Vector3.INF:
		return false
	var start_node: String = _nearest_node_in_room(graph, start_position, start_room)
	var goal_node: String = _nearest_node_in_room(graph, goal_position, goal_room)
	if start_node.is_empty() or goal_node.is_empty():
		return false
	if start_node == goal_node:
		return true
	return not ThreatPathfinderScript.find_path(
		graph, graph.get_node_pos(start_node), graph.get_node_pos(goal_node)).is_empty()


func _room_center(layout: Dictionary, room_id: String) -> Vector3:
	var plan_variant: Variant = layout.get("structural_plan", {})
	if not (plan_variant is Dictionary):
		return Vector3.INF
	var floors_variant: Variant = (plan_variant as Dictionary).get("floor_placements", [])
	if not (floors_variant is Array):
		return Vector3.INF
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for floor_variant in floors_variant as Array:
		if not (floor_variant is Dictionary):
			continue
		var floor: Dictionary = floor_variant
		if str(floor.get("room_id", "")) != room_id:
			continue
		var position: Vector3 = _placement_position(floor)
		if position == Vector3.INF:
			continue
		total += position + Vector3(0.0, FLOOR_Y_OFFSET, 0.0)
		count += 1
	if count == 0:
		return Vector3.INF
	return total / float(count)


func _placement_position(placement: Dictionary) -> Vector3:
	var raw: Variant = placement.get("position", placement.get("world_position", null))
	if raw is Vector3:
		return raw as Vector3
	if raw is String:
		var text: String = str(raw).strip_edges()
		if text.begins_with("(") and text.ends_with(")"):
			text = text.substr(1, text.length() - 2)
		var parts: PackedStringArray = text.split(",")
		if parts.size() == 3 and parts[0].strip_edges().is_valid_float() \
				and parts[1].strip_edges().is_valid_float() \
				and parts[2].strip_edges().is_valid_float():
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
		return Vector3.INF
	if raw is Array and (raw as Array).size() >= 3:
		var values: Array = raw as Array
		for index in range(3):
			var value_type: int = typeof(values[index])
			if value_type != TYPE_INT and value_type != TYPE_FLOAT \
					and (value_type != TYPE_STRING or not str(values[index]).is_valid_float()):
				return Vector3.INF
		return Vector3(float(values[0]), float(values[1]), float(values[2]))
	return Vector3.INF


func _nearest_node_in_room(graph, world_position: Vector3, room_id: String) -> String:
	var best: String = ""
	var best_distance: float = INF
	for key_variant in graph.nodes:
		var node_id: String = str(key_variant)
		if graph.get_node_room(node_id) != room_id:
			continue
		var distance: float = graph.get_node_pos(node_id).distance_squared_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = node_id
	return best


func _has_any_required_hazard(layout: Dictionary, gameplay_slice: Dictionary, required: Array) -> bool:
	var available: Dictionary = {}
	_collect_hazard_array(layout.get("fire_zones", []), "fire_zone", available)
	_collect_hazard_array(layout.get("breach_zones", []), "breach_zone", available)
	_collect_hazard_array(gameplay_slice.get("fire_zones", []), "fire_zone", available)
	_collect_hazard_array(gameplay_slice.get("breach_zones", []), "breach_zone", available)
	# The live derelict path seeds hazards from room variants after loading. Count
	# those same authoritative variant effects here so seed validation exercises
	# the production generation contract rather than a smoke-only annotation.
	var rooms: Variant = layout.get("rooms", [])
	if rooms is Array:
		var selector = RoomVariantSelectorScript.new()
		const HAZARD_ROLES: Array[String] = [
			"bridge", "cockpit", "engineering", "reactor", "engine_bay",
			"hydroponics", "cargo", "storage",
		]
		for room_variant in rooms as Array:
			if not (room_variant is Dictionary):
				continue
			var room: Dictionary = room_variant
			var role: String = str(room.get("room_role", room.get("role", "")))
			if role not in HAZARD_ROLES:
				continue
			var variant: String = str(room.get("variant", "standard"))
			var hazard: Variant = (selector.effects_for(variant).get("sim", {}) as Dictionary).get("hazard", {})
			if hazard is Dictionary:
				var kind: String = str((hazard as Dictionary).get("kind", ""))
				if kind == "fire":
					available["fire_zone"] = true
				elif kind == "breach":
					available["breach_zone"] = true
	for required_variant in required:
		if available.has(str(required_variant)):
			return true
	return false


func _collect_hazard_array(value: Variant, key: String, available: Dictionary) -> void:
	if value is Array and not (value as Array).is_empty():
		available[key] = true
