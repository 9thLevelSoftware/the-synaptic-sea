class_name PlaceholderTiles
## Programmatically generated placeholder isometric TileSet: flat colored
## diamonds for floor variants and decal overlays. Art never blocks the
## pipeline; the real game swaps in a drawn TileSet with the same atlas
## coordinates.

const FLOOR_COLORS := {
	1: Color(0.42, 0.44, 0.50),  # Deck
	2: Color(0.30, 0.35, 0.42),  # Grated
	3: Color(0.42, 0.33, 0.25),  # DamagedDeck
}
const DECAL_COLORS := {
	1: Color(0.12, 0.10, 0.08, 0.55),  # scorch light
	2: Color(0.05, 0.04, 0.03, 0.75),  # scorch heavy
	3: Color(0.45, 0.05, 0.05, 0.55),  # blood
	4: Color(0.35, 0.35, 0.38, 0.45),  # debris scatter
}

static func build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_size = Vector2i(IsoMath.TILE_W, IsoMath.TILE_H)

	# Source 0: floors (atlas x = floor tile id).
	var floor_img := Image.create(IsoMath.TILE_W * 4, IsoMath.TILE_H, false, Image.FORMAT_RGBA8)
	for id in FLOOR_COLORS:
		_paint_diamond(floor_img, id * IsoMath.TILE_W, FLOOR_COLORS[id], true)
	var floor_src := TileSetAtlasSource.new()
	floor_src.texture = ImageTexture.create_from_image(floor_img)
	floor_src.texture_region_size = Vector2i(IsoMath.TILE_W, IsoMath.TILE_H)
	for id in FLOOR_COLORS:
		floor_src.create_tile(Vector2i(id, 0))
	ts.add_source(floor_src, 0)

	# Source 1: decals (atlas x = decal id).
	var decal_img := Image.create(IsoMath.TILE_W * 5, IsoMath.TILE_H, false, Image.FORMAT_RGBA8)
	for id in DECAL_COLORS:
		_paint_diamond(decal_img, id * IsoMath.TILE_W, DECAL_COLORS[id], false)
	var decal_src := TileSetAtlasSource.new()
	decal_src.texture = ImageTexture.create_from_image(decal_img)
	decal_src.texture_region_size = Vector2i(IsoMath.TILE_W, IsoMath.TILE_H)
	for id in DECAL_COLORS:
		decal_src.create_tile(Vector2i(id, 0))
	ts.add_source(decal_src, 1)
	return ts

## Fill an isometric diamond into `img` at horizontal pixel offset `ox`.
static func _paint_diamond(img: Image, ox: int, color: Color, with_border: bool) -> void:
	var w := IsoMath.TILE_W
	var h := IsoMath.TILE_H
	var border := color.darkened(0.35)
	for py in h:
		# Diamond half-width at this row.
		var t: float = abs((py + 0.5) / h - 0.5) * 2.0  # 0 center, 1 edge
		var half := int((1.0 - t) * w * 0.5)
		for px in range(w / 2 - half, w / 2 + half):
			var edge: bool = px <= w / 2 - half + 1 or px >= w / 2 + half - 2 or py <= 1 or py >= h - 2
			img.set_pixel(ox + px, py, border if (with_border and edge) else color)
