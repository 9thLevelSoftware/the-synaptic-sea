extends RefCounted
class_name SynapseSeaWorld

## The infinite Synapse Sea: a world_seed, the player's position, and the set of
## markers already materialized into ships. Markers themselves are not stored —
## they are regenerated deterministically from world_seed on each query.

const MarkerGeneratorScript := preload("res://scripts/systems/marker_generator.gd")

var world_seed: int = 0
var player_position: Vector3 = Vector3.ZERO
var generated_marker_ids: Dictionary = {}   # marker_id -> true
var _generator

func _init(p_world_seed: int = 0, p_player_position: Vector3 = Vector3.ZERO) -> void:
	world_seed = p_world_seed
	player_position = p_player_position
	_generator = MarkerGeneratorScript.new()

## Distinct markers within `radius` of player_position, sorted ascending by
## distance. Regenerates every cell overlapping the radius bounding box.
func markers_in_range(radius: float) -> Array:
	assert(radius >= 0.0, "SynapseSeaWorld.markers_in_range: radius must be non-negative")
	var out: Array = []
	var seen: Dictionary = {}
	var cs: float = MarkerGeneratorScript.CELL_SIZE
	var min_x: int = int(floor((player_position.x - radius) / cs))
	var max_x: int = int(floor((player_position.x + radius) / cs))
	var min_y: int = int(floor((player_position.z - radius) / cs))
	var max_y: int = int(floor((player_position.z + radius) / cs))
	for cx in range(min_x, max_x + 1):
		for cy in range(min_y, max_y + 1):
			for m in _generator.markers_for_cell(world_seed, Vector2i(cx, cy)):
				if seen.has(m.marker_id):
					continue
				if m.position.distance_to(player_position) <= radius:
					seen[m.marker_id] = true
					out.append(m)
	out.sort_custom(_closer_to_player)
	return out

func _closer_to_player(a, b) -> bool:
	return a.position.distance_to(player_position) < b.position.distance_to(player_position)

func mark_generated(marker_id: String) -> void:
	generated_marker_ids[marker_id] = true

func is_generated(marker_id: String) -> bool:
	return generated_marker_ids.has(marker_id)

## Reverses mark_generated — used to roll back a travel that materialized a target
## but was then rejected (e.g. an incompatible dock port) so the world does not
## retain a generated mark for a derelict the player never actually traveled to.
func unmark_generated(marker_id: String) -> void:
	generated_marker_ids.erase(marker_id)

func set_player_position(pos: Vector3) -> void:
	player_position = pos

func get_summary() -> Dictionary:
	return {
		"world_seed": world_seed,
		"player_position": [player_position.x, player_position.y, player_position.z],
		"generated_marker_ids": generated_marker_ids.keys(),
	}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	world_seed = int(summary.get("world_seed", world_seed))
	var p: Variant = summary.get("player_position", null)
	if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 3:
		player_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	generated_marker_ids.clear()
	var ids: Variant = summary.get("generated_marker_ids", [])
	if typeof(ids) == TYPE_ARRAY:
		for mid in (ids as Array):
			generated_marker_ids[str(mid)] = true
	return true
