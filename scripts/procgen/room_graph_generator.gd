extends RefCounted
class_name RoomGraphGenerator

# Preload the peer data classes. See the original implementation for
# why preloaded script constants are used instead of bare class_name
# references in headless --script mode.
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")

# Generates a procedural RoomGraph from a ShipBlueprint.
#
# v2 changes from v1:
#   - Weighted role selection: optional roles are picked from a
#     weighted pool (archetype-supplied or default) instead of
#     uniformly at random. This produces sensible role distributions
#     (freighters get cargo, life boats get maintenance).
#   - Role diversity cap: max N rooms of any single optional role
#     (default 2, archetype-overridable via max_duplicates).
#   - Guaranteed roles: archetypes can declare roles that must appear
#     at least once (e.g. freighters always get cargo).
#   - Archetype awareness: generate() accepts an optional archetype
#     Dictionary (loaded from JSON) that supplies role_weights,
#     guaranteed_roles, and max_duplicates.

const REQUIRED_ROLES: Array[String] = ["airlock"]

const SYSTEM_ROLES: Dictionary = {
	"power": "engineering",
	"life_support": "life_support",
	"propulsion": "engineering",
	"navigation": "bridge",
	"scanners": "bridge",
}

const OPTIONAL_ROLES: Array[String] = [
	"corridor",
	"cargo",
	"crew_quarters",
	"medical",
	"maintenance",
]

# Default weights when no archetype supplies role_weights.
const DEFAULT_WEIGHTS: Dictionary = {
	"corridor": 3,
	"cargo": 2,
	"crew_quarters": 2,
	"maintenance": 2,
	"medical": 1,
}

# Default max rooms of any single optional role.
const DEFAULT_MAX_DUPLICATES: int = 2

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


# Builds a RoomGraph from the given blueprint.
#
# `archetype` is an optional Dictionary loaded from an archetype JSON.
# When present and containing role_weights / guaranteed_roles /
# max_duplicates, those override the defaults. When absent (null), the
# generator falls back to DEFAULT_WEIGHTS and DEFAULT_MAX_DUPLICATES.
func generate(blueprint, archetype: Dictionary = {}) -> RoomGraphScript:
	assert(blueprint != null, "RoomGraphGenerator: blueprint must not be null")

	rng.seed = int(blueprint.seed_value)

	var graph: RoomGraphScript = RoomGraphScript.new()
	var target_count: int = _pick_room_count(blueprint)

	# Step 1: always-present airlock.
	graph.add_room(_make_room_id("airlock", 1, graph), "airlock", 0)

	# Step 2: size-conditional system rooms.
	_add_required_rooms(graph, blueprint)

	# Step 3: guaranteed roles from archetype.
	_add_guaranteed_roles(graph, archetype, target_count)

	# Step 4: fill remaining slots with weighted optional roles.
	_fill_optional_rooms_weighted(graph, target_count, archetype)

	# Step 5: wire connectivity.
	_connect_rooms(graph)

	return graph


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


# Adds guaranteed roles from the archetype (if any). Each guaranteed
# role gets exactly one room if it isn't already present.
func _add_guaranteed_roles(graph: RoomGraphScript, archetype: Dictionary, target_count: int) -> void:
	if archetype.is_empty():
		return
	var guaranteed: Array = archetype.get("guaranteed_roles", [])
	for role_entry in guaranteed:
		var role: String = String(role_entry)
		if graph.rooms.size() >= target_count:
			break
		# Skip if already present (e.g. system rooms).
		var already: bool = false
		for room in graph.rooms:
			if String(room["role"]) == role:
				already = true
				break
		if already:
			continue
		var idx: int = _next_index_for_role(graph, role)
		graph.add_room(_make_room_id(role, idx, graph), role, 0)


# Fills remaining slots with weighted optional role selection.
# The weights are drawn from the archetype's role_weights (if present)
# or DEFAULT_WEIGHTS. Each time a role is picked, its weight is halved
# (floored at 1) so subsequent picks of the same role become less
# likely. A per-role cap (max_duplicates) prevents any single optional
# role from dominating the ship.
func _fill_optional_rooms_weighted(graph: RoomGraphScript, target_count: int, archetype: Dictionary) -> void:
	var weights: Dictionary = _build_weights(archetype)
	var max_dup: int = int(archetype.get("max_duplicates", DEFAULT_MAX_DUPLICATES))
	if max_dup < 1:
		max_dup = DEFAULT_MAX_DUPLICATES

	while graph.rooms.size() < target_count:
		var role: String = _pick_weighted_role(graph, weights, max_dup)
		if role.is_empty():
			# Pool exhausted — every role is at cap. Fill with
			# corridors as the universal connector.
			role = "corridor"
			var already: bool = false
			for room in graph.rooms:
				if String(room["role"]) == role:
					already = true
					break
			if already and _count_role(graph, role) >= max_dup + 2:
				# Last resort: break the cap to fill the slot.
				pass
		var idx: int = _next_index_for_role(graph, role)
		graph.add_room(_make_room_id(role, idx, graph), role, 0)

		# Halve the weight so repeated picks become less likely.
		if weights.has(role):
			weights[role] = max(1, int(weights[role]) / 2)


# Builds the weight table from archetype or defaults. Returns a
# Dictionary of role -> weight for all OPTIONAL_ROLES.
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


# Picks a role from the weighted pool, respecting the per-role
# duplicate cap. Returns the chosen role string, or "" if every
# role is at cap.
func _pick_weighted_role(graph: RoomGraphScript, weights: Dictionary, max_dup: int) -> String:
	# Build candidate list: roles under cap with weight > 0.
	var candidates: Array[String] = []
	var candidate_weights: Array[int] = []
	var total_weight: int = 0

	for role in OPTIONAL_ROLES:
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

	# Weighted random pick.
	var roll: int = rng.randi_range(1, total_weight)
	var cumulative: int = 0
	for i in range(candidates.size()):
		cumulative += candidate_weights[i]
		if roll <= cumulative:
			return candidates[i]

	# Fallback (shouldn't happen).
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


# Connects rooms with a linear chain plus random branches.
# The chain ensures connectivity; branches add variety.
# v2: increased branch count for larger ships and capped
# per-room degree at 3 so layouts stay walkable.
func _connect_rooms(graph: RoomGraphScript) -> void:
	if graph.rooms.size() < 2:
		return

	# Linear chain: room 0 -> room 1 -> ... -> room N-1.
	for i in range(graph.rooms.size() - 1):
		var from_id: String = String(graph.rooms[i]["id"])
		var to_id: String = String(graph.rooms[i + 1]["id"])
		graph.add_link(from_id, to_id, "door")

	# Random branches. Scale with ship size: sqrt(N)/2, capped at 4.
	var room_count: int = graph.rooms.size()
	var extra_target: int = int(round(sqrt(float(room_count)) / 2.0))
	if extra_target > 4:
		extra_target = 4
	if extra_target < 0:
		extra_target = 0

	var existing: Dictionary = _index_existing_links(graph)
	var attempts: int = 0
	var max_attempts: int = extra_target * 6 + 10
	var added: int = 0
	while added < extra_target and attempts < max_attempts:
		attempts += 1
		var a: int = rng.randi_range(0, room_count - 1)
		var b: int = rng.randi_range(0, room_count - 1)
		if a == b:
			continue
		if _degree(graph, a) >= 3 or _degree(graph, b) >= 3:
			continue
		# Skip adjacent rooms (already linked by chain).
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
