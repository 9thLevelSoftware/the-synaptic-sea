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
var variant_selector: RefCounted = null  # set by assign() if RoomVariantSelector is passed


func assign(template: RefCounted, blueprint: RefCounted, archetype: Dictionary) -> Array[Dictionary]:
	return assign_with_selector(template, blueprint, archetype, null)


# Same as assign() but additionally accepts a RoomVariantSelector
# (or any RefCounted with a `pick(role, room_index, seed, biome)`
# method). When supplied, every room dict gets a `variant` key
# written from the deterministic variant pick. When null, the room
# dict still gets `variant = "standard"` so downstream consumers
# can rely on the key existing.
func assign_with_selector(
		template: RefCounted,
		blueprint: RefCounted,
		archetype: Dictionary,
		selector,
		biome: String = "") -> Array[Dictionary]:
	variant_selector = selector

	rng.seed = int(blueprint.seed_value)

	var room_plan: Array[Dictionary] = []
	var role_counter: Dictionary = {}  # role -> next index
	var zone_pools: Dictionary = {}  # zone_id -> Array[String] role pool

	# Process zones in template order. The template zone ordering defines
	# the room ordering: entry first, destination last.
	for zone in template.zones:
		var zone_id: String = str(zone.get("id", ""))
		var role_pool_raw: Variant = zone.get("role_pool", [])
		var role_pool: Array[String] = []
		if role_pool_raw is Array:
			for entry in role_pool_raw:
				role_pool.append(str(entry))
		zone_pools[zone_id] = role_pool

		var count: int = _resolve_count(zone.get("count", 1))
		var deck: int = int(zone.get("deck", 0))
		var position_hint: String = str(zone.get("position_hint", "center"))

		for i in range(count):
			var role: String = _pick_role(role_pool, archetype, role_counter)
			var idx: int = _next_index(role, role_counter)
			var room_id: String = "%s_%02d" % [role, idx]
			var footprint: Vector2i = _pick_footprint(role, blueprint)
			var variant: String = _pick_variant(role, room_plan.size(), blueprint, biome)

			room_plan.append({
				"id": room_id,
				"role": role,
				"variant": variant,
				"zone_id": zone_id,
				"deck": deck,
				"position_hint": position_hint,
				"target_cells": footprint.x * footprint.y,
				"footprint": footprint,
			})

	# Tranche 5 (2026-07-06 audit HIGH): archetype guaranteed_roles were
	# authored in every archetype JSON (derelict guarantees "dock") but never
	# enforced. Deterministic post-pass — no RNG, so per-seed replay is stable.
	_enforce_guaranteed_roles(room_plan, archetype, zone_pools, blueprint, biome)

	return room_plan


# Ensures every archetype guaranteed_role appears at least once, replacing the
# most-duplicated non-guaranteed room whose zone role_pool permits the missing
# role. Entry (first) and destination (last) rooms are never replaced.
# Candidate choice uses no RNG (duplicate count descending, later plan index
# breaking ties); the replacement's footprint/variant re-rolls draw from the
# seeded rng, so per-seed replay stays byte-identical. When no eligible room
# exists the guarantee is skipped with a warning — generation never fails.
func _enforce_guaranteed_roles(room_plan: Array[Dictionary], archetype: Dictionary,
		zone_pools: Dictionary, blueprint: RefCounted, biome: String) -> void:
	var guaranteed_raw: Variant = archetype.get("guaranteed_roles", [])
	if not (guaranteed_raw is Array) or (guaranteed_raw as Array).is_empty():
		return
	var guaranteed: Array[String] = []
	for entry in (guaranteed_raw as Array):
		guaranteed.append(str(entry))

	var replaced_any: bool = false
	for wanted in guaranteed:
		var present: bool = false
		for room in room_plan:
			if str(room.get("role", "")) == wanted:
				present = true
				break
		if present:
			continue

		var role_counts: Dictionary = {}
		for room in room_plan:
			var r: String = str(room.get("role", ""))
			role_counts[r] = int(role_counts.get(r, 0)) + 1

		var best_index: int = -1
		var best_count: int = 0
		for i in range(1, room_plan.size() - 1):  # never the entry or destination
			var room: Dictionary = room_plan[i]
			var role: String = str(room.get("role", ""))
			if role in guaranteed:
				continue
			var pool: Array = zone_pools.get(str(room.get("zone_id", "")), [])
			if not (wanted in pool):
				continue
			var count: int = int(role_counts.get(role, 0))
			if count >= best_count:  # >= so later plan index wins ties
				best_count = count
				best_index = i
		if best_index < 0:
			push_warning("RoomAssigner: guaranteed role '%s' has no eligible zone in this template; guarantee skipped" % wanted)
			continue

		var target: Dictionary = room_plan[best_index]
		target["role"] = wanted
		target["footprint"] = _pick_footprint(wanted, blueprint)
		target["target_cells"] = int(target["footprint"].x) * int(target["footprint"].y)
		target["variant"] = _pick_variant(wanted, best_index, blueprint, biome)
		replaced_any = true

	if replaced_any:
		# Re-derive ids so role indices stay contiguous and unique in plan order.
		var counter: Dictionary = {}
		for room in room_plan:
			var role: String = str(room.get("role", ""))
			room["id"] = "%s_%02d" % [role, _next_index(role, counter)]


# Picks a variant string via the supplied selector (if any). Falls
# back to "standard" so the room dict always has a `variant` key.
func _pick_variant(role: String, room_index: int, blueprint: RefCounted, biome: String) -> String:
	if variant_selector == null:
		return "standard"
	if not variant_selector.has_method("pick"):
		return "standard"
	return str(variant_selector.pick(role, int(room_index), int(blueprint.seed_value), biome))


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
		# Single-role zones are authored intent (the zone demands that role);
		# max_duplicates applies only where alternatives exist.
		return pool[0]

	# Tranche 5 (2026-07-06 audit HIGH): archetype max_duplicates was authored
	# in every archetype JSON but never enforced. Roles already at the cap are
	# excluded from the weighted pick; if EVERY pool role is capped, fall back
	# to the least-used pool role — generation never fails.
	var max_dup: int = int(archetype.get("max_duplicates", 0))  # 0 = unlimited

	var weights: Dictionary = archetype.get("role_weights", {})
	var candidates: Array[String] = []
	var candidate_weights: Array[int] = []
	var total: int = 0

	for role in pool:
		if max_dup > 0 and int(role_counter.get(role, 0)) >= max_dup:
			continue
		var w: int = int(weights.get(role, 1))
		if w <= 0:
			w = 1
		candidates.append(role)
		candidate_weights.append(w)
		total += w

	if candidates.is_empty():
		var least_used: String = pool[0]
		var least_count: int = int(role_counter.get(pool[0], 0))
		for role in pool:
			var used: int = int(role_counter.get(role, 0))
			if used < least_count:
				least_count = used
				least_used = role
		return least_used

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
