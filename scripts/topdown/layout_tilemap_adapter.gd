extends RefCounted
class_name LayoutTilemapAdapter
## Converts a procgen layout Dictionary (from ShipLayoutGenerator) into
## TileMapLayer cells using the Winlu 48px tileset.
## 
## Input: layout dict with rooms[] (each has cells[], room_role, id)
## Output: populated TileMapLayer

const TILE_SIZE := 48

# Tile source indices (matching hub_scene_coordinator)
const SOURCE_FLOORS := 0   # A2 - floor autotiles
const SOURCE_WALLS := 1    # A4 - wall autotiles

# Tile atlas coordinates
const FLOOR_METAL := Vector2i(0, 0)
const FLOOR_DARK := Vector2i(1, 0)
const FLOOR_GRATE := Vector2i(2, 0)
const WALL_TOP := Vector2i(0, 0)
const WALL_BOTTOM := Vector2i(0, 1)
const WALL_LEFT := Vector2i(1, 0)
const WALL_RIGHT := Vector2i(1, 1)

# Room role → floor tile mapping
const ROLE_FLOOR_MAP := {
	"airlock": FLOOR_DARK,
	"bridge": FLOOR_DARK,
	"corridor": FLOOR_METAL,
	"main_spine": FLOOR_METAL,
	"ramp": FLOOR_METAL,
	"cargo": FLOOR_METAL,
	"medical": FLOOR_GRATE,
	"reactor": FLOOR_GRATE,
	"maintenance": FLOOR_METAL,
	"storage": FLOOR_METAL,
	"crew_quarters": FLOOR_METAL,
}


func build(tilemap: TileMapLayer, layout: Dictionary) -> Dictionary:
	## Build tilemap from layout dict. Returns info dict with start_pos, room_centers.
	tilemap.clear()

	var rooms: Array = layout.get("rooms", [])
	var room_links: Array = layout.get("room_links", [])
	var blocked_links: Array = layout.get("blocked_links", [])

	# Track all floor cells for wall generation
	var floor_cells: Dictionary = {}  # Vector2i -> true
	var room_centers: Dictionary = {} # room_id -> Vector2

	# Step 1: Fill floors for each room
	for room in rooms:
		var room_id: String = str(room.get("id", ""))
		var role: String = str(room.get("room_role", ""))
		var cells: Array = room.get("cells", [])
		var floor_tile: Vector2i = ROLE_FLOOR_MAP.get(role, FLOOR_METAL)

		var center_sum := Vector2.ZERO
		var cell_count := 0

		for cell in cells:
			if cell is Array and cell.size() >= 2:
				var gx := int(cell[0])
				var gz := int(cell[1])  # z in 3D = y in 2D
				var grid_pos := Vector2i(gx, gz)
				tilemap.set_cell(grid_pos, SOURCE_FLOORS, floor_tile)
				floor_cells[grid_pos] = true
				center_sum += Vector2(gx, gz)
				cell_count += 1

		if cell_count > 0:
			room_centers[room_id] = (center_sum / cell_count) * TILE_SIZE + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)

	# Step 2: Build walls around all floor cells
	var wall_cells: Dictionary = {}  # Vector2i -> wall type
	for floor_pos in floor_cells.keys():
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var neighbor := Vector2i(floor_pos.x + dx, floor_pos.y + dy)
				if not floor_cells.has(neighbor) and not wall_cells.has(neighbor):
					# This is a wall position
					var wall_type := _determine_wall_type(neighbor, floor_cells)
					wall_cells[neighbor] = wall_type

	# Place walls
	for wall_pos in wall_cells:
		tilemap.set_cell(wall_pos, SOURCE_WALLS, wall_cells[wall_pos])

	# Step 3: Punch doorways at room links
	for link in room_links:
		var from_cell: Array = link.get("from_cell", [])
		var to_cell: Array = link.get("to_cell", [])
		if from_cell.size() >= 2 and to_cell.size() >= 2:
			# The doorway is between from_cell and to_cell
			# Clear the wall between them (if any)
			var mid_x := (int(from_cell[0]) + int(to_cell[0])) / 2
			var mid_z := (int(from_cell[1]) + int(to_cell[1])) / 2
			# If they're adjacent, the wall is at one of the cells
			# Just make sure both cells are floor
			var from_pos := Vector2i(int(from_cell[0]), int(from_cell[1]))
			var to_pos := Vector2i(int(to_cell[0]), int(to_cell[1]))
			# Ensure both are walkable
			if not floor_cells.has(from_pos):
				tilemap.set_cell(from_pos, SOURCE_FLOORS, FLOOR_METAL)
				floor_cells[from_pos] = true
			if not floor_cells.has(to_pos):
				tilemap.set_cell(to_pos, SOURCE_FLOORS, FLOOR_METAL)
				floor_cells[to_pos] = true
			# Remove wall between them if adjacent
			if from_pos.distance_to(to_pos) <= 1.5:
				# They're adjacent — clear any wall cell between them
				var wall_between := Vector2i(
					(from_pos.x + to_pos.x) / 2,
					(from_pos.y + to_pos.y) / 2
				)
				if wall_cells.has(wall_between):
					tilemap.set_cell(wall_between, SOURCE_FLOORS, FLOOR_METAL)
					floor_cells[wall_between] = true

	# Step 4: Mark blocked links (don't punch those doorways)
	for blocked in blocked_links:
		var from_cell: Array = blocked.get("from_cell", [])
		var to_cell: Array = blocked.get("to_cell", [])
		if from_cell.size() >= 2 and to_cell.size() >= 2:
			var from_pos := Vector2i(int(from_cell[0]), int(from_cell[1]))
			var to_pos := Vector2i(int(to_cell[0]), int(to_cell[1]))
			# Place a wall between them (blocked doorway)
			if from_pos.distance_to(to_pos) <= 1.5:
				var wall_pos := Vector2i(
					(from_pos.x + to_pos.x) / 2,
					(from_pos.y + to_pos.y) / 2
				)
				tilemap.set_cell(wall_pos, SOURCE_WALLS, WALL_TOP)

	# Return info for the coordinator
	return {
		"room_centers": room_centers,
		"floor_cells": floor_cells.keys(),
	}


func _determine_wall_type(pos: Vector2i, floor_cells: Dictionary) -> Vector2i:
	## Determine which wall tile to use based on which neighbors are floors.
	var has_floor_above := floor_cells.has(Vector2i(pos.x, pos.y - 1))
	var has_floor_below := floor_cells.has(Vector2i(pos.x, pos.y + 1))
	var has_floor_left := floor_cells.has(Vector2i(pos.x - 1, pos.y))
	var has_floor_right := floor_cells.has(Vector2i(pos.x + 1, pos.y))

	if has_floor_above and has_floor_below:
		return WALL_LEFT  # Vertical wall
	if has_floor_left and has_floor_right:
		return WALL_TOP  # Horizontal wall
	if has_floor_above:
		return WALL_TOP
	if has_floor_below:
		return WALL_BOTTOM
	if has_floor_left:
		return WALL_LEFT
	if has_floor_right:
		return WALL_RIGHT
	return WALL_TOP  # Default
