extends RefCounted
class_name RoomGraphGenerator

# Preload the peer data classes for headless --script compatibility.
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")

# Generates a procedural RoomGraph from a ShipBlueprint.
#
# v2: weighted role selection, archetype awareness, derelict support.
#
# Two generation modes:
#   Ship mode (default): airlock + system rooms + optional fill.
#     Used for functional ships (freighters, cruisers).
#   Derelict mode (archetype.type == "derelict"): dock + generic
#     compartments. No system rooms. Used for dead shells the player
#     explores and scavenges.

const REQUIRED_ROLES: Array[String] = ["airlock"]

const SYSTEM_ROLES: Dictionary = {
	"power": "engineering",
	"life_support": "life_support",
	"propulsion": "engineering",
	"navigation": "bridge",
	"scanners": "bridge",
}

# Ship-mode optional roles.
const OPTIONAL_ROLES: Array[String] = [
	"corridor",
	"cargo",
	"crew_quarters",
	"medical",
	"maintenance",
]

# Derelict-mode roles. No systems — just structural space.
const DERELICT_OPTIONAL_ROLES: Array[String] = [
	"compartment",
	"corridor",
	"bay",
	"quarters",
	"hangar",
]

const DEFAULT_WEIGHTS: Dictionary = {
	"corridor": 3,
	"cargo": 2,
	"crew_quarters": 2,
	"maintenance": 2,
	"medical": 1,
}

const DEFAULT_DERELICT_WEIGHTS: Dictionary = {
	"compartment": 4,
	"corridor": 3,
	"bay": 2,
	"quarters": 2,
}

const DEFAULT_MAX_DUPLICATES: int = 2

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func generate(blueprint, archetype: Dictionary = {}) -> RoomGraphScript:
	assert(blueprint != null, "RoomGraphGenerator: blueprint must not be null")

	rng.seed = int(blueprint.seed_value)

	var graph: RoomGraphScript = RoomGraphScript.new()
	var target_count: int = _pick_room_count(blueprint)
	var is_derelict: bool = String(archetype.get("type", "")) == "derelict"

	if is_derelict:
		_generate_derelict(graph, blueprint, archetype, target_count)
	else:
		_generate_ship(graph, blueprint, archetype, target_count)

	_connect_rooms(graph)
	return graph


# --- Ship mode (functional ships) ---

func _generate_ship(graph: RoomGraphScript, blueprint, archetype: Dictionary, target_count: int) -> void:
	# Step 1: airlock.
	graph.add_room(_make_room_id("airlock", 1, graph), "airlock", 0)

	# Step 2: system rooms.
	_add_required_rooms(graph, blueprint)

	# Step 3: guaranteed roles.
	_add_guaranteed_roles(graph, archetype, target_count)

	# Step 4: weighted fill.
	_fill_optional_rooms_weighted(graph, target_count, archetype)


# --- Derelict mode (dead shells) ---

func _generate_derelict(graph: RoomGraphScript, blueprint, archetype: Dictionary, target_count: int) -> void:
	# Derelicts have no airlock or system rooms. The anchor room is
	# the dock — the one fixed point where the life boat attaches.
	graph.add_room(_make_room_id("dock", 1, graph), "dock", 0)

	# Guaranteed roles (dock is already added, so this is a no-op
	# unless the archetype guarantees other roles).
	_add_guaranteed_roles(graph, archetype, target_count)

	# Fill with derelict-specific roles.
	_fill_derelict_rooms(graph, target_count, archetype)


func _fill_derelict_rooms(graph: RoomGraphScript, target_count: int, archetype: Dictionary) -> void:
	var weights: Dictionary = _build_derelict_weights(archetype)
	var max_dup: int = int(archetype.get("max_duplicates", 3))
	if max_dup < 1:
		max_dup = 3

	while graph.rooms.size() < target_count:
		var role: String = _pick_weighted_role_from_pool(
			graph, weights, max_dup, DERELICT_OPTIONAL_ROLES)
		if role.is_empty():
			role = "compartment"  # fallback
		var idx: int = _next_index_for_role(graph, role)
		graph.add_room(_make_room_id(role, idx, graph), role, 0)
		if weights.has(role):
			weights[role] = max(1, int(weights[role]) / 2)


func _build_derelict_weights(archetype: Dictionary) -> Dictionary:
	var weights: Dictionary = {}
	var source: Dictionary = archetype.get("role_weights", DEFAULT_DERELICT_WEIGHTS)
	for role in DERELICT_OPTIONAL_ROLES:
		if source.has(role):
			weights[role] = int(source[role])
		elif DEFAULT_DERELICT_WEIGHTS.has(role):
			weights[role] = int(DEFAULT_DERELICT_WEIGHTS[role])
		else:
			weights[role] = 1
	return weights


# --- Shared helpers ---

func _pick_room_count(blueprint) -> int:
	var lo: int = int(blueprint.room_count_range.x)
	var hi: int = int(blueprint.room_count_range.y)
	if hi < lo:
		hi = lo
	return rng.randi_range(lo, hi)


func _add_required_rooms(graph: RoomGraphScript, blueprint) -> void:
	_add_unique_role(graph, "engineering", 1)
	if blueprint.size == ShipBlueprintScript.Size.LIFE_BOAT:
		return
	_add_unique_role(graph, "life_support", 1)
	_add_unique_role(graph, "bridge", 1)


func _add_unique_role(graph: RoomGraphScript, role: String, instance_index: int) -> void:
	for room in graph.rooms:
		if String(room["role"]) == role:
			return
	var idx: int = instance_index
	while graph.get_room(_make_room_id(role, idx, graph)).is_empty() == false:
		idx += 1
	graph.add_room(_make_room_id(role, idx, graph), role, 0)


func _add_guaranteed_roles(graph: RoomGraphScript, archetype: Dictionary, target_count: int) -> void:
	if archetype.is_empty():
		return
	var guaranteed: Array = archetype.get("guaranteed_roles", [])
	for role_entry in guaranteed:
		var role: String = String(role_entry)
		if graph.rooms.size() >= target_count:
			break
		var already: bool = false
		for room in graph.rooms:
			if String(room["role"]) == role:
				already = true
				break
		if already:
			continue
		var idx: int = _next_index_for_role(graph, role)
		graph.add_room(_make_room_id(role, idx, graph), role, 0)


func _fill_optional_rooms_weighted(graph: RoomGraphScript, target_count: int, archetype: Dictionary) -> void:
	var weights: Dictionary = _build_weights(archetype)
	var max_dup: int = int(archetype.get("max_duplicates", DEFAULT_MAX_DUPLICATES))
	if max_dup < 1:
		max_dup = DEFAULT_MAX_DUPLICATES

	while graph.rooms.size() < target_count:
		var role: String = _pick_weighted_role_from_pool(
			graph, weights, max_dup, OPTIONAL_ROLES)
		if role.is_empty():
			role = "corridor"
		var idx: int = _next_index_for_role(graph, role)
		graph.add_room(_make_room_id(role, idx, graph), role, 0)
		if weights.has(role):
			weights[role] = max(1, int(weights[role]) / 2)


func _build_weights(archetype: Dictionary) -> Dictionary:
	var weights: Dictionary = {}
	var source: Dictionary = archetype.get("role_weights", DEFAULT_WEIGHTS)
	for role in OPTIONAL_ROLES:
		if source.has(role):
			weights[role] = int(source[role])
		elif DEFAULT_WEIGHTS.has(role):
			weights[role] = int(DEFAULT_WEIGHTS[role])
		else:
			weights[role] = 1
	return weights


func _pick_weighted_role_from_pool(
		graph: RoomGraphScript,
		weights: Dictionary,
		max_dup: int,
		pool: Array[String]) -> String:
	var candidates: Array[String] = []
	var candidate_weights: Array[int] = []
	var total_weight: int = 0

	for role in pool:
		if _count_role(graph, role) >= max_dup:
			continue
		var w: int = int(weights.get(role, 1))
		if w <= 0:
			continue
		candidates.append(role)
		candidate_weights.append(w)
		total_weight += w

	if candidates.is_empty():
		return ""

	var roll: int = rng.randi_range(1, total_weight)
	var cumulative: int = 0
	for i in range(candidates.size()):
		cumulative += candidate_weights[i]
		if roll <= cumulative:
			return candidates[i]

	return candidates[0]


func _count_role(graph: RoomGraphScript, role: String) -> int:
	var count: int = 0
	for room in graph.rooms:
		if String(room["role"]) == role:
			count += 1
	return count


func _next_index_for_role(graph: RoomGraphScript, role: String) -> int:
	var max_seen: int = 0
	for room in graph.rooms:
		if String(room["role"]) != role:
			continue
		var rid: String = String(room["id"])
		var sep: int = rid.rfind("_")
		if sep < 0 or sep == rid.length() - 1:
			continue
		var tail: String = rid.substr(sep + 1)
		if not tail.is_valid_int():
			continue
		var n: int = int(tail)
		if n > max_seen:
			max_seen = n
	return max_seen + 1


func _make_room_id(role: String, idx: int, _graph: RoomGraphScript) -> String:
	return "%s_%02d" % [role, idx]


# --- Connectivity ---

func _connect_rooms(graph: RoomGraphScript) -> void:
	if graph.rooms.size() < 2:
		return

	# Linear chain ensures connectivity.
	for i in range(graph.rooms.size() - 1):
		var from_id: String = String(graph.rooms[i]["id"])
		var to_id: String = String(graph.rooms[i + 1]["id"])
		graph.add_link(from_id, to_id, "door")

	# Random branches for variety. Scale with ship size.
	# v3: more branches for better 2D spread.
	var room_count: int = graph.rooms.size()
	var extra_target: int = int(round(sqrt(float(room_count))))
	if extra_target > 6:
		extra_target = 6
	if extra_target < 0:
		extra_target = 0

	var existing: Dictionary = _index_existing_links(graph)
	var attempts: int = 0
	var max_attempts: int = extra_target * 8 + 15
	var added: int = 0
	while added < extra_target and attempts < max_attempts:
		attempts += 1
		var a: int = rng.randi_range(0, room_count - 1)
		var b: int = rng.randi_range(0, room_count - 1)
		if a == b:
			continue
		if _degree(graph, a) >= 3 or _degree(graph, b) >= 3:
			continue
		if abs(a - b) == 1:
			continue
		var key: String = _link_key(a, b)
		if existing.has(key):
			continue
		existing[key] = true
		var aid: String = String(graph.rooms[a]["id"])
		var bid: String = String(graph.rooms[b]["id"])
		graph.add_link(aid, bid, "door")
		added += 1


func _index_existing_links(graph: RoomGraphScript) -> Dictionary:
	var index: Dictionary = {}
	for link in graph.links:
		var from_id: String = String(link["from_room"])
		var to_id: String = String(link["to_room"])
		var fi: int = _index_of_room(graph, from_id)
		var ti: int = _index_of_room(graph, to_id)
		if fi < 0 or ti < 0:
			continue
		index[_link_key(fi, ti)] = true
	return index


func _link_key(a: int, b: int) -> String:
	var lo: int = a
	var hi: int = b
	if lo > hi:
		var tmp: int = lo
		lo = hi
		hi = tmp
	return "%d-%d" % [lo, hi]


func _index_of_room(graph: RoomGraphScript, room_id: String) -> int:
	for i in range(graph.rooms.size()):
		if String(graph.rooms[i]["id"]) == room_id:
			return i
	return -1


func _degree(graph: RoomGraphScript, idx: int) -> int:
	if idx < 0 or idx >= graph.rooms.size():
		return 0
	var rid: String = String(graph.rooms[idx]["id"])
	var deg: int = 0
	for link in graph.links:
		if String(link["from_room"]) == rid or String(link["to_room"]) == rid:
			deg += 1
	return deg
