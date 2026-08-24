class_name IsoMath
## Grid <-> screen math for the diamond-down isometric projection
## (matches TileSet.TILE_LAYOUT_DIAMOND_DOWN with 64x32 tiles).

const TILE_W := 64
const TILE_H := 32

static func grid_to_screen(x: int, y: int) -> Vector2:
	return Vector2((x - y) * TILE_W * 0.5, (x + y) * TILE_H * 0.5)

static func screen_to_grid(p: Vector2) -> Vector2i:
	var fx := p.x / (TILE_W * 0.5)
	var fy := p.y / (TILE_H * 0.5)
	return Vector2i(int(floor((fx + fy) * 0.5 + 0.5)), int(floor((fy - fx) * 0.5 + 0.5)))

## Diamond corner offsets relative to a tile's center.
static func corner_top() -> Vector2:
	return Vector2(0, -TILE_H * 0.5)

static func corner_right() -> Vector2:
	return Vector2(TILE_W * 0.5, 0)

static func corner_bottom() -> Vector2:
	return Vector2(0, TILE_H * 0.5)

static func corner_left() -> Vector2:
	return Vector2(-TILE_W * 0.5, 0)
