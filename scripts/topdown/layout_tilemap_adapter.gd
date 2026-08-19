extends RefCounted
class_name LayoutTilemapAdapter
## Converts a procgen layout Dictionary into TileMapLayer cells.
## Uses DithArt Sci-Fi tileset with documented tile IDs from Tiled example.

const TILE_SIZE := 48
const DithartMapperScript = preload("res://scripts/topdown/dithart_tile_mapper.gd")


func build(tilemap: TileMapLayer, layout: Dictionary) -> Dictionary:
	tilemap.clear()

	var rooms: Array = layout.get("rooms", [])
	var room_links: Array = layout.get("room_links", [])

	var floor_cells: Dictionary = {}  # Vector2i -> true
	var room_centers: Dictionary = {} # room_id -> Vector2

	# Step 1: Fill floors
	for room in rooms:
		var room_id: String = str(room.get("id", ""))
		var role: String = str(room.get("room_role", ""))
		var cells: Array = room.get("cells", [])
		var floor_tile: Vector2i = DithartMapperScript.floor_for_role(role)

		var center_sum := Vector2.ZERO
		var cell_count := 0

		for cell in cells:
			if cell is Array and cell.size() >= 2:
				var gx := int(cell[0])
				var gz := int(cell[1])
				var grid_pos := Vector2i(gx, gz)
				tilemap.set_cell(grid_pos, 0, floor_tile)
				floor_cells[grid_pos] = true
				center_sum += Vector2(gx, gz)
				cell_count += 1

		if cell_count > 0:
			room_centers[room_id] = (center_sum / cell_count) * TILE_SIZE + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)

	# Step 2: Build walls around all floor cells
	for floor_pos in floor_cells.keys():
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var neighbor := Vector2i(floor_pos.x + dx, floor_pos.y + dy)
				if not floor_cells.has(neighbor):
					var wall_tile := DithartMapperScript.wall_for_position(neighbor, floor_cells)
					tilemap.set_cell(neighbor, 0, wall_tile)

	# Step 3: Punch doorways at room links
	for link in room_links:
		var from_cell: Array = link.get("from_cell", [])
		var to_cell: Array = link.get("to_cell", [])
		if from_cell.size() >= 2 and to_cell.size() >= 2:
			var from_pos := Vector2i(int(from_cell[0]), int(from_cell[1]))
			var to_pos := Vector2i(int(to_cell[0]), int(to_cell[1]))
			if not floor_cells.has(from_pos):
				tilemap.set_cell(from_pos, 0, DithartMapperScript.FLOOR_MAIN)
				floor_cells[from_pos] = true
			if not floor_cells.has(to_pos):
				tilemap.set_cell(to_pos, 0, DithartMapperScript.FLOOR_MAIN)
				floor_cells[to_pos] = true

	return {
		"room_centers": room_centers,
		"floor_cells": floor_cells.keys(),
	}
