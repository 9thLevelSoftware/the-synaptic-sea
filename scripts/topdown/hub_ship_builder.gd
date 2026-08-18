extends Node2D
class_name HubShipBuilder
## Programmatically builds a hub ship layout on a TileMapLayer at 48px grid.
## Mirrors the 3D ship_generator.gd approach but in 2D tiles.

const TILE_SIZE := 48

# Tile source indices (matching winlu_atlas.tres order)
const SOURCE_FLOORS := 0   # A2 - floor autotiles
const SOURCE_WALLS := 1    # A4 - wall autotiles
const SOURCE_DETAIL_B := 2
const SOURCE_DETAIL_C := 3
const SOURCE_DETAIL_D := 4
const SOURCE_DETAIL_E := 5

# Tile atlas coordinates for common tiles (col:row in the source sheet)
const FLOOR_METAL := Vector2i(0, 0)       # Generic metal floor
const FLOOR_DARK := Vector2i(1, 0)        # Dark floor variant
const FLOOR_GRATE := Vector2i(2, 0)       # Grate floor
const WALL_TOP := Vector2i(0, 0)          # Top-facing wall
const WALL_BOTTOM := Vector2i(0, 1)       # Bottom-facing wall
const WALL_LEFT := Vector2i(1, 0)         # Left wall
const WALL_RIGHT := Vector2i(1, 1)        # Right wall
const WALL_CORNER_TL := Vector2i(2, 0)   # Top-left corner
const WALL_CORNER_TR := Vector2i(3, 0)   # Top-right corner
const WALL_CORNER_BL := Vector2i(2, 1)   # Bottom-left corner
const WALL_CORNER_BR := Vector2i(3, 1)   # Bottom-right corner

var tilemap: TileMapLayer


func _ready() -> void:
	_ensure_tilemap()
	_build_hub_layout()


func set_tilemap(tm: TileMapLayer) -> void:
	tilemap = tm
	_build_hub_layout()


func _ensure_tilemap() -> void:
	if tilemap != null:
		return
	tilemap = TileMapLayer.new()
	tilemap.name = "HubTileMap"
	# TileSet will be assigned by the scene or at runtime
	add_child(tilemap)


func _build_hub_layout() -> void:
	if tilemap == null or tilemap.tile_set == null:
		push_warning("HubShipBuilder: No TileMapLayer or TileSet assigned")
		return

	# Define rooms as rect2i (position, size) in grid coordinates
	var rooms := _define_ship_layout()

	# Clear existing tiles
	tilemap.clear()

	# Build each room
	for room in rooms:
		_build_room(room["rect"], room["type"], room.get("connections", []))


func _define_ship_layout() -> Array:
	## Classic hub ship layout: bridge -> corridor -> junction -> branches
	## All coordinates in grid cells (48px each)
	return [
		# Bridge (top)
		{"rect": Rect2i(0, 0, 8, 6), "type": "bridge"},
		# Main corridor (vertical)
		{"rect": Rect2i(3, 6, 2, 8), "type": "corridor"},
		# Junction room
		{"rect": Rect2i(0, 14, 8, 5), "type": "junction"},
		# Left branch: Medbay
		{"rect": Rect2i(-6, 14, 6, 5), "type": "medbay", "connections": [{"dir": "right", "pos": Vector2i(0, 15)}]},
		# Right branch: Storage
		{"rect": Rect2i(8, 14, 6, 5), "type": "storage", "connections": [{"dir": "left", "pos": Vector2i(8, 15)}]},
		# Down corridor to airlock
		{"rect": Rect2i(3, 19, 2, 5), "type": "corridor"},
		# Airlock (bottom)
		{"rect": Rect2i(0, 24, 8, 5), "type": "airlock"},
		# Side corridor to reactor
		{"rect": Rect2i(-6, 19, 6, 3), "type": "reactor"},
	]


func _build_room(rect: Rect2i, room_type: String, connections: Array = []) -> void:
	# Fill floor
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var floor_tile := FLOOR_METAL
			match room_type:
				"bridge": floor_tile = FLOOR_DARK
				"medbay": floor_tile = FLOOR_GRATE
				"reactor": floor_tile = FLOOR_GRATE
				"airlock": floor_tile = FLOOR_DARK
			tilemap.set_cell(Vector2i(x, y), SOURCE_FLOORS, floor_tile)

	# Build walls (outline)
	# Top wall
	for x in range(rect.position.x - 1, rect.end.x + 1):
		tilemap.set_cell(Vector2i(x, rect.position.y - 1), SOURCE_WALLS, WALL_TOP)
	# Bottom wall
	for x in range(rect.position.x - 1, rect.end.x + 1):
		tilemap.set_cell(Vector2i(x, rect.end.y), SOURCE_WALLS, WALL_BOTTOM)
	# Left wall
	for y in range(rect.position.y, rect.end.y):
		tilemap.set_cell(Vector2i(rect.position.x - 1, y), SOURCE_WALLS, WALL_LEFT)
	# Right wall
	for y in range(rect.position.y, rect.end.y):
		tilemap.set_cell(Vector2i(rect.end.x, y), SOURCE_WALLS, WALL_RIGHT)

	# Corners
	tilemap.set_cell(Vector2i(rect.position.x - 1, rect.position.y - 1), SOURCE_WALLS, WALL_CORNER_TL)
	tilemap.set_cell(Vector2i(rect.end.x, rect.position.y - 1), SOURCE_WALLS, WALL_CORNER_TR)
	tilemap.set_cell(Vector2i(rect.position.x - 1, rect.end.y), SOURCE_WALLS, WALL_CORNER_BL)
	tilemap.set_cell(Vector2i(rect.end.x, rect.end.y), SOURCE_WALLS, WALL_CORNER_BR)

	# Punch doorways for connections
	for conn in connections:
		_punch_doorway(rect, conn)


func _punch_doorway(room_rect: Rect2i, connection: Dictionary) -> void:
	var dir: String = connection.get("dir", "right")
	var pos: Vector2i = connection.get("pos", Vector2i.ZERO)

	match dir:
		"left":
			# Remove left wall at door position
			tilemap.set_cell(Vector2i(room_rect.position.x - 1, pos.y), SOURCE_FLOORS, FLOOR_METAL)
			tilemap.set_cell(Vector2i(room_rect.position.x - 1, pos.y + 1), SOURCE_FLOORS, FLOOR_METAL)
		"right":
			tilemap.set_cell(Vector2i(room_rect.end.x, pos.y), SOURCE_FLOORS, FLOOR_METAL)
			tilemap.set_cell(Vector2i(room_rect.end.x, pos.y + 1), SOURCE_FLOORS, FLOOR_METAL)
		"up":
			tilemap.set_cell(Vector2i(pos.x, room_rect.position.y - 1), SOURCE_FLOORS, FLOOR_METAL)
			tilemap.set_cell(Vector2i(pos.x + 1, room_rect.position.y - 1), SOURCE_FLOORS, FLOOR_METAL)
		"down":
			tilemap.set_cell(Vector2i(pos.x, room_rect.end.y), SOURCE_FLOORS, FLOOR_METAL)
			tilemap.set_cell(Vector2i(pos.x + 1, room_rect.end.y), SOURCE_FLOORS, FLOOR_METAL)


func get_spawn_position(room_type: String = "bridge") -> Vector2:
	## Return world position for player spawn in a given room
	var rooms := _define_ship_layout()
	for room in rooms:
		if room["type"] == room_type:
			var rect: Rect2i = room["rect"]
			var center := rect.position + rect.size / 2
			return Vector2(center.x * TILE_SIZE, center.y * TILE_SIZE)
	return Vector2(3 * TILE_SIZE, 3 * TILE_SIZE)  # Default: bridge center
