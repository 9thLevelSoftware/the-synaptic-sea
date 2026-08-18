class_name CellOccupancy
## Lightweight grid occupancy index for top-down pathfinding and spatial queries.
## Threat AI uses this instead of direct 3D space queries.
## Pure data — no scene dependencies.

var _occupied: Dictionary = {}  # Vector2i -> true
var _entities: Dictionary = {}  # Vector2i -> Array[StringName]


## Mark a cell as occupied by an entity (by id).
func occupy(grid_pos: Vector2i, entity_id: StringName = &"") -> void:
	_occupied[grid_pos] = true
	if not entity_id.is_empty():
		if not _entities.has(grid_pos):
			_entities[grid_pos] = []
		if not _entities[grid_pos].has(entity_id):
			_entities[grid_pos].append(entity_id)


## Release a cell (entity leaves).
func release(grid_pos: Vector2i, entity_id: StringName = &"") -> void:
	if entity_id.is_empty():
		_occupied.erase(grid_pos)
		_entities.erase(grid_pos)
		return
	if _entities.has(grid_pos):
		_entities[grid_pos].erase(entity_id)
		if _entities[grid_pos].is_empty():
			_occupied.erase(grid_pos)
			_entities.erase(grid_pos)


## Check if a cell is occupied.
func is_occupied(grid_pos: Vector2i) -> bool:
	return _occupied.has(grid_pos)


## Get all entity ids at a cell.
func entities_at(grid_pos: Vector2i) -> Array:
	return _entities.get(grid_pos, [])


## Clear all occupancy data.
func clear() -> void:
	_occupied.clear()
	_entities.clear()


## Get all occupied cells (for debug/visualization).
func get_occupied_cells() -> Array:
	return _occupied.keys()


## Check if a cell is walkable (not occupied).
func is_walkable(grid_pos: Vector2i) -> bool:
	return not is_occupied(grid_pos)


## Get cardinal + diagonal neighbors of a cell that are walkable.
func get_walkable_neighbors(grid_pos: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var neighbor := Vector2i(grid_pos.x + dx, grid_pos.y + dy)
			if is_walkable(neighbor):
				result.append(neighbor)
	return result
