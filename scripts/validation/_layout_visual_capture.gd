extends SceneTree

# Generates a top-down 2D visualization of each template's layout as PNG.
# Works in headless mode — draws directly to an Image.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")

const CELL_PX: int = 32
const PADDING: int = 64
const LABEL_HEIGHT: int = 24

# Role -> color mapping
const ROLE_COLORS: Dictionary = {
	"airlock":        Color(0.2, 0.8, 0.2),
	"dock":           Color(0.2, 0.8, 0.2),
	"corridor":       Color(0.55, 0.55, 0.55),
	"main_spine":     Color(0.7, 0.7, 0.5),
	"hub":            Color(0.9, 0.7, 0.3),
	"engineering":    Color(0.3, 0.5, 0.85),
	"cargo":          Color(0.65, 0.45, 0.2),
	"bay":            Color(0.65, 0.45, 0.2),
	"medical":        Color(0.9, 0.3, 0.3),
	"crew_quarters":  Color(0.5, 0.3, 0.7),
	"maintenance":    Color(0.4, 0.4, 0.4),
	"life_support":   Color(0.2, 0.7, 0.7),
	"reactor":        Color(0.95, 0.2, 0.2),
	"bridge":         Color(0.9, 0.85, 0.3),
	"ramp":           Color(0.6, 0.8, 0.4),
	"elevator":       Color(0.4, 0.6, 0.9),
	"storage":        Color(0.5, 0.5, 0.35),
	"mess_hall":      Color(0.85, 0.6, 0.3),
	"armory":         Color(0.7, 0.2, 0.2),
}
const DEFAULT_COLOR: Color = Color(0.5, 0.5, 0.5)


func _initialize() -> void:
	var gen: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var output_dir: String = ProjectSettings.globalize_path("res://screenshots/procgen_layouts")
	DirAccess.make_dir_recursive_absolute(output_dir)

	var templates: Array[String] = ["spine", "bifurcated", "stacked"]
	var seeds: Array[int] = [42, 999, 7777]

	for tpl in templates:
		for seed_val in seeds:
			var bp: ShipBlueprintScript = ShipBlueprintScript.new(
				ShipBlueprintScript.Size.MEDIUM,
				ShipBlueprintScript.Condition.PRISTINE,
				seed_val)
			var layout: Dictionary = gen.generate(bp, {"template": tpl})
			if layout.is_empty():
				push_error("CAPTURE FAIL %s seed=%d empty layout" % [tpl, seed_val])
				continue

			var image: Image = _render_layout(layout, tpl, seed_val)
			var filename: String = "%s/%s_seed_%d.png" % [output_dir, tpl, seed_val]
			var err: Error = image.save_png(filename)
			if err != OK:
				push_error("CAPTURE FAIL cannot save %s" % filename)
			else:
				print("Saved: %s (%dx%d)" % [filename, image.get_width(), image.get_height()])

	print("LAYOUT VISUAL CAPTURE PASS saved %d images to %s" % [templates.size() * seeds.size(), output_dir])
	quit(0)


func _render_layout(layout: Dictionary, template_id: String, seed_val: int) -> Image:
	var rooms: Array = layout.get("rooms", [])
	var room_links: Array = layout.get("room_links", [])
	var cp: Array = layout.get("critical_path", [])

	# Collect all cells with their room info
	var all_cells: Array[Dictionary] = []  # {cell: Vector2i, deck: int, role: String, room_id: String}
	var room_role_map: Dictionary = {}

	for room in rooms:
		var rid: String = str(room.get("id", ""))
		var role: String = str(room.get("room_role", ""))
		var deck: int = int(room.get("deck", 0))
		room_role_map[rid] = role

		for placement in room.get("structural_placements", []):
			var name: String = str(placement.get("name", ""))
			if not name.begins_with("floor_cell"):
				continue
			var wp: Array = placement.get("world_position", [0, 0, 0])
			var cx: int = int(round(float(wp[0]) / 4.0))
			var cz: int = int(round(float(wp[2]) / 4.0))
			all_cells.append({"cell": Vector2i(cx, cz), "deck": deck, "role": role, "room_id": rid})

	if all_cells.is_empty():
		return Image.create(200, 100, false, Image.FORMAT_RGBA8)

	# Find bounds
	var min_x: int = 99999
	var max_x: int = -99999
	var min_z: int = 99999
	var max_z: int = -99999
	var max_deck: int = 0
	for entry in all_cells:
		var c: Vector2i = entry["cell"]
		var d: int = entry["deck"]
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.y)
		max_z = maxi(max_z, c.y)
		max_deck = maxi(max_deck, d)

	var grid_w: int = max_x - min_x + 1
	var grid_h: int = max_z - min_z + 1

	# If multi-deck, draw decks side by side
	var deck_count: int = max_deck + 1
	var total_grid_w: int = grid_w * deck_count + (deck_count - 1) * 2  # 2 cell gap between decks

	var img_w: int = total_grid_w * CELL_PX + PADDING * 2
	var img_h: int = grid_h * CELL_PX + PADDING * 2 + LABEL_HEIGHT * 3  # room for title + legend
	img_w = maxi(img_w, 400)
	img_h = maxi(img_h, 300)

	var image: Image = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.12, 0.15))

	# Draw title bar
	_draw_filled_rect(image, Vector2i(0, 0), Vector2i(img_w, LABEL_HEIGHT + 8), Color(0.18, 0.18, 0.22))

	# Draw cells per deck
	for deck in range(deck_count):
		var deck_offset_x: int = PADDING + deck * (grid_w * CELL_PX + 2 * CELL_PX)
		var deck_offset_y: int = PADDING + LABEL_HEIGHT + 8

		# Deck label background
		_draw_filled_rect(image,
			Vector2i(deck_offset_x, deck_offset_y - LABEL_HEIGHT),
			Vector2i(grid_w * CELL_PX, LABEL_HEIGHT),
			Color(0.22, 0.22, 0.28))

		for entry in all_cells:
			if entry["deck"] != deck:
				continue
			var c: Vector2i = entry["cell"]
			var role: String = entry["role"]
			var rid: String = entry["room_id"]

			var px: int = deck_offset_x + (c.x - min_x) * CELL_PX
			var py: int = deck_offset_y + (c.y - min_z) * CELL_PX

			var color: Color = ROLE_COLORS.get(role, DEFAULT_COLOR)

			# Slightly darken alternating rooms for visibility
			if rid.hash() % 2 == 0:
				color = color.darkened(0.15)

			# Draw cell fill
			_draw_filled_rect(image, Vector2i(px + 1, py + 1), Vector2i(CELL_PX - 2, CELL_PX - 2), color)

			# Highlight critical path rooms
			if rid in cp:
				_draw_rect_outline(image, Vector2i(px, py), Vector2i(CELL_PX, CELL_PX), Color(1.0, 1.0, 0.3), 2)

	# Draw portal/doorway connections
	for link in room_links:
		var from_room: String = str(link.get("from_room", ""))
		var to_room: String = str(link.get("to_room", ""))
		var from_cell: Array = link.get("from_cell", [0, 0, 0])
		var to_cell: Array = link.get("to_cell", [0, 0, 0])

		var from_deck: int = 0
		var to_deck: int = 0
		for room in rooms:
			if str(room.get("id", "")) == from_room:
				from_deck = int(room.get("deck", 0))
			if str(room.get("id", "")) == to_room:
				to_deck = int(room.get("deck", 0))

		if from_deck != to_deck:
			continue  # Cross-deck links drawn separately

		var deck_off_x: int = PADDING + from_deck * (grid_w * CELL_PX + 2 * CELL_PX)
		var deck_off_y: int = PADDING + LABEL_HEIGHT + 8

		var fx: int = deck_off_x + (int(from_cell[0]) - min_x) * CELL_PX + CELL_PX / 2
		var fy: int = deck_off_y + (int(from_cell[1]) - min_z) * CELL_PX + CELL_PX / 2
		var tx: int = deck_off_x + (int(to_cell[0]) - min_x) * CELL_PX + CELL_PX / 2
		var ty: int = deck_off_y + (int(to_cell[1]) - min_z) * CELL_PX + CELL_PX / 2

		_draw_line(image, Vector2i(fx, fy), Vector2i(tx, ty), Color(1.0, 1.0, 1.0, 0.5), 2)

	# Draw legend at bottom
	var legend_y: int = img_h - LABEL_HEIGHT * 2
	var legend_x: int = PADDING
	var used_roles: Dictionary = {}
	for entry in all_cells:
		used_roles[entry["role"]] = true

	for role in used_roles.keys():
		var color: Color = ROLE_COLORS.get(role, DEFAULT_COLOR)
		_draw_filled_rect(image, Vector2i(legend_x, legend_y), Vector2i(12, 12), color)
		# Can't draw text in headless, so just show color blocks
		legend_x += 18

	return image


func _draw_filled_rect(image: Image, pos: Vector2i, size: Vector2i, color: Color) -> void:
	for x in range(maxi(pos.x, 0), mini(pos.x + size.x, image.get_width())):
		for y in range(maxi(pos.y, 0), mini(pos.y + size.y, image.get_height())):
			image.set_pixel(x, y, color)


func _draw_rect_outline(image: Image, pos: Vector2i, size: Vector2i, color: Color, thickness: int = 1) -> void:
	for t in range(thickness):
		# Top and bottom
		for x in range(maxi(pos.x + t, 0), mini(pos.x + size.x - t, image.get_width())):
			if pos.y + t >= 0 and pos.y + t < image.get_height():
				image.set_pixel(x, pos.y + t, color)
			if pos.y + size.y - 1 - t >= 0 and pos.y + size.y - 1 - t < image.get_height():
				image.set_pixel(x, pos.y + size.y - 1 - t, color)
		# Left and right
		for y in range(maxi(pos.y + t, 0), mini(pos.y + size.y - t, image.get_height())):
			if pos.x + t >= 0 and pos.x + t < image.get_width():
				image.set_pixel(pos.x + t, y, color)
			if pos.x + size.x - 1 - t >= 0 and pos.x + size.x - 1 - t < image.get_width():
				image.set_pixel(pos.x + size.x - 1 - t, y, color)


func _draw_line(image: Image, from: Vector2i, to: Vector2i, color: Color, thickness: int = 1) -> void:
	var dx: int = absi(to.x - from.x)
	var dy: int = absi(to.y - from.y)
	var sx: int = 1 if from.x < to.x else -1
	var sy: int = 1 if from.y < to.y else -1
	var err: int = dx - dy
	var x: int = from.x
	var y: int = from.y

	while true:
		for tx in range(-thickness / 2, thickness / 2 + 1):
			for ty in range(-thickness / 2, thickness / 2 + 1):
				var px: int = x + tx
				var py: int = y + ty
				if px >= 0 and px < image.get_width() and py >= 0 and py < image.get_height():
					image.set_pixel(px, py, color)

		if x == to.x and y == to.y:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
