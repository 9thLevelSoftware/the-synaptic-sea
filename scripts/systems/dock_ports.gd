extends RefCounted
class_name DockPorts

## Derives dock-port descriptors {position: Vector3 (local), facing: Vector3}
## from a ship layout dict. The lifeboat docks at its airlock (-X side); the
## derelict exposes its guaranteed `dock` room opening (+X side outward).

const HALF_CELL: float = 2.0   # CELL_SIZE (4.0) / 2
const AIRLOCK_SIZE_CLASS: int = 1

static func for_lifeboat(layout: Dictionary) -> Dictionary:
	var center: Vector3 = _room_floor_center(layout, "airlock", "airlock")
	if center == Vector3.INF:
		return {}
	# Airlock opening faces the dock (-X, away from the +X cockpit); nudge to the edge.
	return {
		"position": center + Vector3(-HALF_CELL, 0.0, 0.0),
		"facing": Vector3(-1.0, 0.0, 0.0),
		"type": "airlock",
		"size_class": AIRLOCK_SIZE_CLASS,
		"condition": "intact",
	}

static func for_derelict(layout: Dictionary, seed_value: int = 0, condition_class: int = 0) -> Dictionary:
	var center: Vector3 = _room_floor_center(layout, "dock", "dock")
	# Fall back to the airlock room when no dock room exists (e.g. the home ship uses
	# its airlock as the docking attachment point rather than a dedicated dock room).
	if center == Vector3.INF:
		center = _room_floor_center(layout, "airlock", "airlock")
	if center == Vector3.INF:
		return {}
	return {
		"position": center,
		"facing": Vector3(1.0, 0.0, 0.0),
		"type": "airlock",
		"size_class": AIRLOCK_SIZE_CLASS,
		"condition": condition_from_seed(seed_value, condition_class),
	}

## Ship-local floor center of the `bridge` room, or Vector3.INF if none.
static func bridge_center(layout: Dictionary) -> Vector3:
	return _room_floor_center(layout, "bridge", "bridge")

## True iff both ports are non-empty, the same type, and the same size class.
## Missing size_class on either port fails closed (no asymmetric sentinels).
static func ports_compatible(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if not a.has("size_class") or not b.has("size_class"):
		return false
	if str(a.get("type", "")) != str(b.get("type", "")):
		return false
	return int(a["size_class"]) == int(b["size_class"])

## Deterministic port condition from the derelict's condition tier + seed.
## Pristine/light tiers are always intact; wreck tier always broken; the middle
## tiers (1,2) are split by the derelict's seed — same (seed, class) -> same result,
## worse condition -> higher break chance. (Matches the spec: condition + seed.)
static func condition_from_seed(seed_value: int, condition_class: int) -> String:
	if condition_class <= 0:
		return "intact"
	if condition_class >= 3:
		return "broken"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var broken_chance: float = 0.25 * float(condition_class)   # class1=0.25, class2=0.50
	return "broken" if rng.randf() < broken_chance else "intact"

## Average world_position of floor placements in the first room whose room_role
## == role_match OR whose id begins with id_prefix. Returns Vector3.INF if none.
static func _room_floor_center(layout: Dictionary, role_match: String, id_prefix: String) -> Vector3:
	const FLOOR_MODULES := ["floor_1x1", "corridor_floor_1x1"]
	for room_v in layout.get("rooms", []):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		var role := str(room.get("room_role", ""))
		var rid := str(room.get("id", ""))
		if role != role_match and not rid.begins_with(id_prefix):
			continue
		var sum := Vector3.ZERO
		var count := 0
		for p_v in room.get("structural_placements", []):
			if typeof(p_v) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_v
			var module := str(p.get("module_id", p.get("module", "")))
			if module not in FLOOR_MODULES:
				continue
			var pos = p.get("world_position", p.get("position", null))
			if typeof(pos) != TYPE_ARRAY or (pos as Array).size() < 3:
				continue
			sum += Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
			count += 1
		if count > 0:
			return sum / float(count)
	return Vector3.INF
