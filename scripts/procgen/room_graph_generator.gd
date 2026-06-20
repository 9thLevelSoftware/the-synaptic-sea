extends RefCounted
class_name RoomGraphGenerator

# Preload the peer data classes and reference them as types via these
# constants. This matches the pattern used in the smokes (e.g.
# `var graph: RoomGraphScript = RoomGraphScript.new()`) and is the
# reliable way to make cross-file type annotations resolve in headless
# `--script` runs. Bare `ShipBlueprint` / `RoomGraph` references work
# in the editor because class_name globals are pre-registered, but in
# `godot --headless --script` mode the global registry may not be
# populated yet, leading to parse-time "Could not find type" errors.
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const RoomGraphScript := preload("res://scripts/procgen/room_graph.gd")

# Generates a procedural RoomGraph from a ShipBlueprint.
#
# The generator is the deterministic, RNG-driven bridge between a
# ShipBlueprint (size + condition + seed) and the structural RoomGraph
# that downstream placers (walls/floors, systems, encounters) consume.
# It carries no scene nodes — only the role/layout topology — so it can
# be unit-tested and round-tripped through to_dict/from_dict without
# touching the scene tree.
#
# Generation contract:
#   - Input:  ShipBlueprint with size / condition / seed_value
#   - Output: RoomGraph containing
#             * exactly 1 airlock
#             * 1 engineering (power/propulsion) for every size
#             * 1 life_support + 1 bridge for SMALL and MEDIUM ships
#               (LIFE_BOAT skips these — it has no crew quarters to
#               pressurise and no command deck)
#             * the remaining rooms filled with random optional roles
#               (corridor / cargo / crew_quarters / medical /
#               maintenance) until the blueprint's room_count is met
#             * every room reachable from the airlock via links
#
# Determinism: setting `blueprint.seed_value` to the same value before
# calling `generate()` always produces an identical graph (room count
# inside the configured range, role sequence, and link wiring). The
# smoke verifies this property.

# Rooms that must appear exactly once on every ship.
const REQUIRED_ROLES: Array[String] = ["airlock"]

# Map of ship-system → room role. The generator does not place systems
# (that's a later task); it only guarantees that the room role that
# would house each system is present when the system is required.
#
#   power        → engineering
#   life_support → life_support
#   propulsion   → engineering  (shares the engine room with power)
#   navigation   → bridge
#   scanners     → bridge       (shares the bridge with navigation)
const SYSTEM_ROLES: Dictionary = {
	"power": "engineering",
	"life_support": "life_support",
	"propulsion": "engineering",
	"navigation": "bridge",
	"scanners": "bridge",
}

# Roles that can fill the remaining slots once the required rooms are
# in place. Each is gameplay-meaningful and consumable by later
# placers. Chosen uniformly at random per slot.
const OPTIONAL_ROLES: Array[String] = [
	"corridor",
	"cargo",
	"crew_quarters",
	"medical",
	"maintenance",
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


# Builds a RoomGraph from the given blueprint.
#
# Steps:
#   1. Seed the RNG with blueprint.seed_value so generation is
#      deterministic.
#   2. Pick the actual room count from blueprint.room_count_range
#      (inclusive on both ends).
#   3. Add the airlock first so it ends up at index 0 — link chains
#      start there and downstream placers can rely on that.
#   4. Add the size-conditional required system rooms.
#   5. Fill any remaining slots with random optional roles.
#   6. Wire a linear chain airlock → … → last_room, then add a few
#      random extra edges to create branches.
func generate(blueprint) -> RoomGraphScript:
	assert(blueprint != null, "RoomGraphGenerator: blueprint must not be null")

	rng.seed = int(blueprint.seed_value)

	var graph: RoomGraphScript = RoomGraphScript.new()
	var target_count: int = _pick_room_count(blueprint)

	# Step 1: always-present airlock. We hard-code the role list (rather
	# than walking REQUIRED_ROLES) so the order is stable: airlock
	# first, then system rooms, then optional fill.
	graph.add_room(_make_room_id("airlock", 1, graph), "airlock", 0)

	# Step 2: size-conditional system rooms.
	_add_required_rooms(graph, blueprint)

	# Step 3: fill remaining slots with optional roles until we reach
	# the blueprint's room count. If the required rooms already meet or
	# exceed the target we add nothing more (small life boats end up
	# with exactly the required rooms).
	_fill_optional_rooms(graph, target_count)

	# Step 4: wire connectivity.
	_connect_rooms(graph)

	return graph


# Picks an integer in [range.x, range.y] inclusive using this
# generator's RNG. Centralised so the determinism contract is obvious
# in one place.
func _pick_room_count(blueprint) -> int:
	var lo: int = int(blueprint.room_count_range.x)
	var hi: int = int(blueprint.room_count_range.y)
	if hi < lo:
		hi = lo
	return rng.randi_range(lo, hi)


# Adds the system rooms required for the given blueprint. Engineering
# is always required (LIFE_BOATs still need a reactor); life_support
# and bridge are only required for SMALL and MEDIUM ships because a
# life boat has no crew quarters to pressurise and no command deck.
func _add_required_rooms(graph: RoomGraphScript, blueprint) -> void:
	# Engineering first so the engine room ends up early in the chain
	# (right after the airlock) and the linear spine goes
	# airlock → engineering → …
	_add_unique_role(graph, "engineering", 1)

	# Skip the support/command rooms for life boats. We compare against
	# the enum value from ShipBlueprint to avoid hard-coding numeric
	# constants here.
	if blueprint.size == ShipBlueprintScript.Size.LIFE_BOAT:
		return

	_add_unique_role(graph, "life_support", 1)
	_add_unique_role(graph, "bridge", 1)


# Adds a room with the given role if it isn't already in the graph.
# The `instance_index` argument disambiguates the room id (e.g.
# `engineering_01` vs `engineering_02`); we bump it if a collision
# occurs so we never overwrite a room or produce duplicate ids.
func _add_unique_role(graph: RoomGraphScript, role: String, instance_index: int) -> void:
	# If the role is already present, don't add a duplicate. The map
	# (e.g. power + propulsion → engineering) intentionally routes
	# multiple systems to the same room.
	for room in graph.rooms:
		if String(room["role"]) == role:
			return

	# Find a free id with the given prefix. Start at the requested
	# instance_index and walk upward.
	var idx: int = instance_index
	while graph.get_room(_make_room_id(role, idx, graph)).is_empty() == false:
		idx += 1
	graph.add_room(_make_room_id(role, idx, graph), role, 0)


# Fills the graph with random optional roles until it reaches
# `target_count` rooms, or until the optional pool is exhausted (which
# shouldn't happen for valid blueprint ranges, but is defended against
# so a degenerate input can't loop forever).
func _fill_optional_rooms(graph: RoomGraphScript, target_count: int) -> void:
	while graph.rooms.size() < target_count:
		var role: String = _pick_optional_role(graph)
		var idx: int = _next_index_for_role(graph, role)
		graph.add_room(_make_room_id(role, idx, graph), role, 0)


# Picks an optional role uniformly at random, avoiding producing a
# duplicate role+deck that would create two rooms with identical ids.
# If every optional role is already at the current id, the next id
# (e.g. `corridor_03`) is what we use — the room itself is still
# distinct, so this is fine.
func _pick_optional_role(_graph: RoomGraphScript) -> String:
	var i: int = rng.randi_range(0, OPTIONAL_ROLES.size() - 1)
	return OPTIONAL_ROLES[i]


# Returns the next numeric suffix to use for a room of `role`. The
# first instance of any role uses `_01`, the second `_02`, and so on.
func _next_index_for_role(graph: RoomGraphScript, role: String) -> int:
	var max_seen: int = 0
	for room in graph.rooms:
		if String(room["role"]) != role:
			continue
		var rid: String = String(room["id"])
		# Parse the trailing `_NN`. If parsing fails we treat it as 0
		# (i.e. don't claim a higher index); the next call will retry.
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


# Builds a stable room id from role + index. Collision-checking is
# done by the caller (`_add_unique_role` / `_fill_optional_rooms`)
# using `get_room`, so this helper is purely formatting.
func _make_room_id(role: String, idx: int, _graph: RoomGraphScript) -> String:
	return "%s_%02d" % [role, idx]


# Connects every room in the graph with a linear chain (0→1→2→…)
# and adds a handful of random extra edges to create branches. The
# extra edges are bounded so the graph stays sparse and walkable.
#
# The chain is always built first; the random edges are then added
# only if they would not duplicate an existing link. This guarantees
# the graph is connected even if RNG roll is unlucky.
func _connect_rooms(graph: RoomGraphScript) -> void:
	if graph.rooms.size() < 2:
		# 0 or 1 room — nothing to connect.
		return

	# Linear chain: room 0 → room 1 → room 2 → … → room N-1.
	# Start at index 0 (the airlock) so downstream placers can rely on
	# the airlock being the "root" of the chain.
	for i in range(graph.rooms.size() - 1):
		var from_id: String = String(graph.rooms[i]["id"])
		var to_id: String = String(graph.rooms[i + 1]["id"])
		graph.add_link(from_id, to_id, "door")

	# Random branches. Aim for roughly sqrt(N) extra edges on top of
	# the chain, capped at 3, so the layout stays sparse regardless
	# of ship size. Use the same RNG so determinism is preserved.
	var room_count: int = graph.rooms.size()
	var extra_target: int = int(round(sqrt(float(room_count))))
	if extra_target > 3:
		extra_target = 3
	if extra_target < 0:
		extra_target = 0

	var existing: Dictionary = _index_existing_links(graph)
	var attempts: int = 0
	var max_attempts: int = extra_target * 4 + 8
	var added: int = 0
	while added < extra_target and attempts < max_attempts:
		attempts += 1
		var a: int = rng.randi_range(0, room_count - 1)
		var b: int = rng.randi_range(0, room_count - 1)
		if a == b:
			continue
		# Cap any one room to ≤ 3 connections so the graph doesn't
		# sprout a star hub. If both candidates are already saturated
		# just skip and let the next roll try again.
		if _degree(graph, a) >= 3 or _degree(graph, b) >= 3:
			continue
		var key: String = _link_key(a, b)
		if existing.has(key):
			continue
		existing[key] = true
		var aid: String = String(graph.rooms[a]["id"])
		var bid: String = String(graph.rooms[b]["id"])
		graph.add_link(aid, bid, "door")
		added += 1


# Returns a Dictionary of undirected edge keys (sorted "a-b") for
# every link already in the graph, so the random-branch pass can
# check for duplicates in O(1).
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


# Undirected edge key from two room indices. Sorted so a→b and b→a
# produce the same key.
func _link_key(a: int, b: int) -> String:
	var lo: int = a
	var hi: int = b
	if lo > hi:
		var tmp: int = lo
		lo = hi
		hi = tmp
	return "%d-%d" % [lo, hi]


# Returns the index of the room with the given id, or -1 if not
# found. Used to translate link endpoints to indices so the duplicate
# check works on small integers.
func _index_of_room(graph: RoomGraphScript, room_id: String) -> int:
	for i in range(graph.rooms.size()):
		if String(graph.rooms[i]["id"]) == room_id:
			return i
	return -1


# Degree of the room at `idx` (number of links incident to it).
func _degree(graph: RoomGraphScript, idx: int) -> int:
	if idx < 0 or idx >= graph.rooms.size():
		return 0
	var rid: String = String(graph.rooms[idx]["id"])
	var deg: int = 0
	for link in graph.links:
		if String(link["from_room"]) == rid or String(link["to_room"]) == rid:
			deg += 1
	return deg
