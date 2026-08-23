extends RefCounted
class_name DithartTileMapper
## Maps structural roles to DithArt Sci-Fi tileset atlas coordinates.
## Based on Tiled example: free_scifi_tileset_example.tmx
## Grid: 8 cols x 15 rows, 48px tiles. Tiled IDs 1-indexed → atlas 0-indexed.

const TILE_SIZE := 48

# === FLOOR TILES ===
const FLOOR_MAIN := Vector2i(0, 14)       # Tiled 113 — dark floor
const FLOOR_VARIANT := Vector2i(1, 14)    # Tiled 114 — lighter floor
const FLOOR_ACCENT1 := Vector2i(0, 5)     # Tiled 41 — very dark floor
const FLOOR_ACCENT2 := Vector2i(7, 5)     # Tiled 48 — dark corridor floor

# === WALL TILES ===
const WALL_H_TOP := Vector2i(2, 5)        # Tiled 43 — horizontal wall top
const WALL_H_MID := Vector2i(0, 0)        # Tiled 1  — horizontal wall mid
const WALL_H_BOT := Vector2i(4, 3)        # Tiled 29 — horizontal wall bottom
const WALL_V_LEFT := Vector2i(4, 2)       # Tiled 21 — vertical wall left
const WALL_V_RIGHT := Vector2i(0, 2)      # Tiled 17 — vertical wall right
const WALL_V_TOP := Vector2i(7, 1)        # Tiled 16 — vertical wall top end
const WALL_V_BOT := Vector2i(7, 2)        # Tiled 24 — vertical wall bottom end
const WALL_CORNER_TL := Vector2i(3, 3)    # Tiled 28 — top-left corner
const WALL_CORNER_TR := Vector2i(1, 3)    # Tiled 26 — top-right corner
const WALL_CORNER_BL := Vector2i(0, 3)    # Tiled 25 — bottom-left corner
const WALL_CORNER_BR := Vector2i(1, 1)    # Tiled 10 — bottom-right corner
const WALL_JUNCTION := Vector2i(6, 3)     # Tiled 31 — wall junction
const WALL_INTERIOR := Vector2i(0, 1)     # Tiled 9  — wall interior fill
const WALL_PILLAR := Vector2i(0, 10)      # Tiled 81 — pillar
const WALL_PANEL := Vector2i(0, 11)       # Tiled 89 — wall panel

# === OBJECTS ===
const OBJ_CONSOLE := Vector2i(5, 4)       # Tiled 38 — console screen
const OBJ_CONSOLE2 := Vector2i(5, 5)      # Tiled 46 — console variant


static func floor_for_role(role: String) -> Vector2i:
	match role:
		"bridge", "airlock": return FLOOR_ACCENT1
		"corridor", "main_spine", "ramp": return FLOOR_ACCENT2
		"medical", "reactor": return FLOOR_VARIANT
		_: return FLOOR_MAIN


static func wall_for_position(grid_pos: Vector2i, floor_cells: Dictionary) -> Vector2i:
	var has_n := floor_cells.has(Vector2i(grid_pos.x, grid_pos.y - 1))
	var has_s := floor_cells.has(Vector2i(grid_pos.x, grid_pos.y + 1))
	var has_e := floor_cells.has(Vector2i(grid_pos.x + 1, grid_pos.y))
	var has_w := floor_cells.has(Vector2i(grid_pos.x - 1, grid_pos.y))

	# Corners (two adjacent floors forming an L)
	if has_s and has_e and not has_n and not has_w:
		return WALL_CORNER_TL
	if has_s and has_w and not has_n and not has_e:
		return WALL_CORNER_TR
	if has_n and has_e and not has_s and not has_w:
		return WALL_CORNER_BL
	if has_n and has_w and not has_s and not has_e:
		return WALL_CORNER_BR

	# Horizontal walls
	if has_n and has_s:
		return WALL_H_MID
	if has_s and not has_n:
		return WALL_H_TOP
	if has_n and not has_s:
		return WALL_H_BOT

	# Vertical walls
	if has_e and has_w:
		return WALL_V_LEFT
	if has_e and not has_w:
		return WALL_V_LEFT
	if has_w and not has_e:
		return WALL_V_RIGHT

	return WALL_INTERIOR
