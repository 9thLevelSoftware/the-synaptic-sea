extends RefCounted
class_name ShipBlueprint

# Data class describing a procedurally generated ship layout seed. The
# blueprint is the single source of truth that downstream generators
# (room graph, system placement, encounter rolls) consume; it carries no
# scene nodes and only stores the inputs needed to deterministically
# reproduce a ship.

enum Size {
	LIFE_BOAT,
	SMALL,
	MEDIUM,
}

enum Condition {
	PRISTINE,
	DAMAGED,
	WRECKED,
}

# Defaults match a medium, pristine ship with an arbitrary seed so the
# constructor stays safe even when called without arguments.
var size: int = Size.MEDIUM
var condition: int = Condition.PRISTINE
var seed_value: int = 0

# room_count_range is a Vector2i(min, max) — both bounds inclusive. It
# is recomputed from `size` in _init() but exposed as a writable field so
# callers can override it for special cases (debug, fixture loads).
var room_count_range: Vector2i = Vector2i(8, 12)


func _init(
		p_size: int = Size.MEDIUM,
		p_condition: int = Condition.PRISTINE,
		p_seed: int = 0) -> void:
	size = p_size
	condition = p_condition
	seed_value = p_seed
	room_count_range = _get_room_count_range()


# Returns the inclusive [min, max] room count range for the current
# `size` value. Centralised so the loader and the smoke agree.
static func _get_room_count_range_for(p_size: int) -> Vector2i:
	match p_size:
		Size.LIFE_BOAT:
			return Vector2i(2, 4)
		Size.SMALL:
			return Vector2i(4, 8)
		Size.MEDIUM:
			return Vector2i(8, 12)
		_:
			return Vector2i(8, 12)


# Instance accessor — recomputed each call so callers that mutate `size`
# always see the matching range without having to remember to call a
# setter.
func _get_room_count_range() -> Vector2i:
	return _get_room_count_range_for(size)


# Probability in [0.0, 1.0] that a given ship system comes online in this
# blueprint. Wrecked ships have barely-working systems; pristine ones
# are almost fully operational.
func get_system_online_chance() -> float:
	match condition:
		Condition.PRISTINE:
			return 0.9
		Condition.DAMAGED:
			return 0.5
		Condition.WRECKED:
			return 0.2
		_:
			return 0.5


# Serialises the blueprint to a plain Dictionary so it can be persisted
# to JSON alongside layout / kit / gameplay fixtures.
func to_dict() -> Dictionary:
	return {
		"size": size,
		"condition": condition,
		"seed_value": seed_value,
		"room_count_range": {
			"min": room_count_range.x,
			"max": room_count_range.y,
		},
	}


# Rebuilds a blueprint from a Dictionary produced by `to_dict()`. Any
# missing or malformed field falls back to the default value so a
# partially-corrupt fixture never crashes the loader.
static func from_dict(data: Dictionary) -> RefCounted:
	# Self-reference to our own class_name isn't safe inside the script
	# during initial compile, so we instantiate via load() with a cached
	# reference. The result is a ShipBlueprint instance.
	var script: GDScript = load("res://scripts/procgen/ship_blueprint.gd")
	var bp = script.new()
	if data.has("size"):
		bp.size = int(data["size"])
	if data.has("condition"):
		bp.condition = int(data["condition"])
	if data.has("seed_value"):
		bp.seed_value = int(data["seed_value"])
	if data.has("room_count_range") and data["room_count_range"] is Dictionary:
		var r: Dictionary = data["room_count_range"]
		var derived: Vector2i = bp._get_room_count_range()
		var rmin: int = int(r.get("min", derived.x))
		var rmax: int = int(r.get("max", derived.y))
		bp.room_count_range = Vector2i(rmin, rmax)
	else:
		# Re-derive from size so the public field stays consistent.
		bp.room_count_range = bp._get_room_count_range()
	return bp