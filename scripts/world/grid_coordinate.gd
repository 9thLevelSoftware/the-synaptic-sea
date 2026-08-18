class_name GridCoordinate
## Shared world↔grid coordinate conversion at 48px resolution.
## Pure math — no scene dependencies. Used by threat AI, interactions, save format.

const TILE_SIZE: int = 48


## Convert a world position (Vector2) to grid coordinates (Vector2i).
static func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_pos.x / float(TILE_SIZE)),
		floori(world_pos.y / float(TILE_SIZE))
	)


## Convert grid coordinates (Vector2i) to the world position of that tile's top-left corner.
static func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * TILE_SIZE,
		grid_pos.y * TILE_SIZE
	)


## Convert grid coordinates to the world position of that tile's center.
static func grid_to_world_center(grid_pos: Vector2i) -> Vector2:
	return grid_to_world(grid_pos) + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)


## Manhattan distance between two grid positions.
static func grid_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Chebyshev distance (8-directional) between two grid positions.
static func grid_distance_chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
