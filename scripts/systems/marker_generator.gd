extends RefCounted
class_name MarkerGenerator

## Deterministic, infinite marker field. (world_seed, grid cell) -> a fixed set
## of ShipMarkers. Same inputs always yield identical markers.

const ShipMarkerScript := preload("res://scripts/systems/ship_marker.gd")

const CELL_SIZE := 100.0
const MARKERS_PER_CELL := 3
const SHIP_TYPES := ["shuttle", "freighter", "science_vessel", "derelict_hauler"]

## Stable spatial hash (NOT Godot's hash(), which we do not rely on for save
## reproducibility). The large primes decorrelate adjacent cells.
##
## This XOR is NOT collision-free for very distant cells, so two far-apart cells
## can share marker attributes/seeds. That is harmless: a marker's identity is
## its marker_id ("cell_x:cell_y:index"), not its seed, so dedup and travel stay
## correct. Collisions only ever recur outside normal play range.
static func cell_seed(world_seed: int, cell: Vector2i) -> int:
	return world_seed ^ (cell.x * 73856093) ^ (cell.y * 19349663)

func markers_for_cell(world_seed: int, cell: Vector2i) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = cell_seed(world_seed, cell)
	var base_x: float = float(cell.x) * CELL_SIZE
	var base_z: float = float(cell.y) * CELL_SIZE
	for i in range(MARKERS_PER_CELL):
		var m = ShipMarkerScript.new()
		m.marker_id = "%d:%d:%d" % [cell.x, cell.y, i]
		# Consume rng in a FIXED order so determinism holds.
		var lx: float = rng.randf() * CELL_SIZE
		var lz: float = rng.randf() * CELL_SIZE
		m.position = Vector3(base_x + lx, 0.0, base_z + lz)
		m.seed_value = rng.randi()
		m.size_class = _weighted_size(rng)
		m.condition = _weighted_condition(rng)
		m.ship_type = SHIP_TYPES[rng.randi() % SHIP_TYPES.size()]
		out.append(m)
	return out

func _weighted_size(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < 0.4:
		return 0  # LIFE_BOAT
	elif r < 0.8:
		return 1  # SMALL
	return 2      # MEDIUM

func _weighted_condition(rng: RandomNumberGenerator) -> int:
	var r: float = rng.randf()
	if r < 0.15:
		return 0  # PRISTINE
	elif r < 0.6:
		return 1  # DAMAGED
	return 2      # WRECKED
