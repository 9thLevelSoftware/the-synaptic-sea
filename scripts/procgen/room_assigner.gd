extends RefCounted
class_name RoomAssigner

# Fills template zones with concrete rooms. Each zone produces 1..N rooms
# based on its count field. Roles are picked from the zone's role_pool
# using archetype weights when available. Each room gets a footprint
# based on the ROOM_FOOTPRINT_OPTIONS table and the blueprint size.

const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")

# Footprint options per role: array of Vector2i choices.
# Larger blueprints (MEDIUM) pick from the full range; SMALL picks from
# smaller options.
const ROOM_FOOTPRINT_OPTIONS: Dictionary = {
	"airlock":        [Vector2i(2, 2), Vector2i(3, 2)],
	"dock":           [Vector2i(2, 2), Vector2i(3, 2)],
	"corridor":       [Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 1), Vector2i(5, 1)],
	"engineering":    [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)],
	"bridge":         [Vector2i(3, 2), Vector2i(3, 3)],
	"cargo":          [Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 3)],
	"bay":            [Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 3)],
	"hangar":         [Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 3)],
	"medical":        [Vector2i(2, 2), Vector2i(2, 1)],
	"crew_quarters":  [Vector2i(2, 2), Vector2i(2, 1)],
	"mess_hall":      [Vector2i(2, 2), Vector2i(3, 2)],
	"armory":         [Vector2i(1, 2), Vector2i(2, 2)],
	"maintenance":    [Vector2i(1, 2), Vector2i(2, 2)],
	"life_support":   [Vector2i(2, 2)],
	"reactor":        [Vector2i(3, 3), Vector2i(2, 3), Vector2i(3, 2)],
	"main_spine":     [Vector2i(3, 3), Vector2i(2, 2)],
	"hub":            [Vector2i(3, 3), Vector2i(2, 2)],
	"ramp":           [Vector2i(1, 1)],
	"elevator":       [Vector2i(1, 1)],
	"storage":        [Vector2i(1, 2), Vector2i(2, 2)],
}

const DEFAULT_FOOTPRINT: Vector2i = Vector2i(2, 2)

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func assign(template: RefCounted, blueprint: RefCounted, archetype: Dictionary) -> Array[Dictionary]:
	rng.seed = int(blueprint.seed_value)

	var room_plan: Array[Dictionary] = []
	var role_counter: Dictionary = {}  # role -> next index

	# Process zones in template order. The template zone ordering defines
	# the room ordering: entry first, destination last.
	for zone in template.zones:
		var zone_id: String = str(zone.get("id", ""))
		var role_pool_raw: Variant = zone.get("role_pool", [])
		var role_pool: Array[String] = []
		if role_pool_raw is Array:
			for entry in role_pool_raw:
				role_pool.append(str(entry))

		var count: int = _resolve_count(zone.get("count", 1))
		var deck: int = int(zone.get("deck", 0))
		var position_hint: String = str(zone.get("position_hint", "center"))

		for i in range(count):
			var role: String = _pick_role(role_pool, archetype, role_counter)
			var idx: int = _next_index(role, role_counter)
			var room_id: String = "%s_%02d" % [role, idx]
			var footprint: Vector2i = _pick_footprint(role, blueprint)

			room_plan.append({
				"id": room_id,
				"role": role,
				"zone_id": zone_id,
				"deck": deck,
				"position_hint": position_hint,
				"target_cells": footprint.x * footprint.y,
				"footprint": footprint,
			})

	return room_plan


func _resolve_count(count_value: Variant) -> int:
	if count_value is Array:
		var arr: Array = count_value
		if arr.size() >= 2:
			var lo: int = int(arr[0])
			var hi: int = int(arr[1])
			if hi < lo:
				hi = lo
			return rng.randi_range(lo, hi)
	return int(count_value)


func _pick_role(pool: Array[String], archetype: Dictionary, role_counter: Dictionary) -> String:
	if pool.is_empty():
		return "corridor"
	if pool.size() == 1:
		return pool[0]

	var weights: Dictionary = archetype.get("role_weights", {})
	var candidates: Array[String] = []
	var candidate_weights: Array[int] = []
	var total: int = 0

	for role in pool:
		var w: int = int(weights.get(role, 1))
		if w <= 0:
			w = 1
		candidates.append(role)
		candidate_weights.append(w)
		total += w

	var roll: int = rng.randi_range(1, total)
	var cumulative: int = 0
	for i in range(candidates.size()):
		cumulative += candidate_weights[i]
		if roll <= cumulative:
			return candidates[i]

	return candidates[0]


func _next_index(role: String, role_counter: Dictionary) -> int:
	if not role_counter.has(role):
		role_counter[role] = 1
	else:
		role_counter[role] = int(role_counter[role]) + 1
	return int(role_counter[role])


func _pick_footprint(role: String, blueprint: RefCounted) -> Vector2i:
	if not ROOM_FOOTPRINT_OPTIONS.has(role):
		return DEFAULT_FOOTPRINT

	var options: Array = ROOM_FOOTPRINT_OPTIONS[role]
	if options.is_empty():
		return DEFAULT_FOOTPRINT

	# For SMALL blueprints, prefer smaller footprints (first half of options).
	# For MEDIUM, pick from the full range.
	var max_idx: int = options.size() - 1
	if int(blueprint.size) <= 1 and options.size() > 1:  # LIFE_BOAT or SMALL
		max_idx = int(ceil(float(options.size()) / 2.0)) - 1

	var idx: int = rng.randi_range(0, max_idx)
	return options[idx]
