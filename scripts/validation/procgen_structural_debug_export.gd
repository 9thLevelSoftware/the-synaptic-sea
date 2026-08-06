extends SceneTree

## Deterministic canonical structural debug exporter.
##
## Usage:
##   godot --headless --path <project> --script \
##     res://scripts/validation/procgen_structural_debug_export.gd -- \
##     --seed 17 --output-dir /tmp/procgen-seed-17
##
## The exporter consumes the production layout generator, compiles the canonical
## structural plan, validates it before writing anything, then writes sorted
## JSON records and a top-down edge-state image. It never serializes raw Godot
## Dictionary iteration order or opaque Vector2i/Vector3 values.

const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript: GDScript = preload("res://scripts/procgen/ship_layout_generator.gd")
const StructuralEdgeCompilerScript: GDScript = preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript: GDScript = preload("res://scripts/procgen/structural_plan_validator.gd")
const StructuralEdgePlanScript: GDScript = preload("res://scripts/procgen/structural_edge_plan.gd")

const MIN_DERELICT_ROOMS: int = 5
const MAX_DERELICT_ROOMS: int = 8
const DERELICT_TEMPLATE: String = "derelict_a"
const CELL_PIXELS: int = 32
const IMAGE_PADDING: int = 24
const LEGEND_HEIGHT: int = 24

const EDGE_COLORS: Dictionary = {
	"SOLID": Color(0.46, 0.50, 0.56, 1.0),
	"OPEN": Color(0.15, 0.82, 0.42, 1.0),
	"DOOR": Color(0.18, 0.55, 0.96, 1.0),
	"LOCKED": Color(0.94, 0.22, 0.28, 1.0),
	"HATCH": Color(0.98, 0.62, 0.12, 1.0),
	"BREACH": Color(0.70, 0.34, 0.94, 1.0),
}


func _initialize() -> void:
	var command_args: PackedStringArray = OS.get_cmdline_user_args()
	# Godot normally exposes script arguments after `--`; also accept direct
	# `--seed/--output-dir` invocation so this remains a conventional CLI.
	if command_args.is_empty():
		var fallback_args: Array[String] = []
		for raw_argument in OS.get_cmdline_args():
			var raw_text: String = str(raw_argument)
			if not fallback_args.is_empty() or raw_text in ["--seed", "--output-dir"]:
				fallback_args.append(raw_text)
		command_args = PackedStringArray(fallback_args)
	var options: Dictionary = _parse_cli(command_args)
	if not bool(options.get("ok", false)):
		print("PROCGEN STRUCTURAL DEBUG EXPORT FAIL %s" % str(options.get("error", "invalid arguments")))
		quit(1)
		return

	var seed_value: int = int(options["seed"])
	var output_dir: String = _absolute_path(str(options["output_dir"]))
	var result: Dictionary = _export_seed(seed_value, output_dir, bool(options.get("reverse_input", false)))
	if not bool(result.get("ok", false)):
		print("PROCGEN STRUCTURAL DEBUG EXPORT FAIL seed=%d reason=%s" % [seed_value, str(result.get("error", "unknown error"))])
		quit(1)
		return

	print("PROCGEN STRUCTURAL DEBUG EXPORT PASS seed=%d rooms=%d placements=%d portals=%d output=%s" % [
		seed_value,
		int(result.get("rooms", 0)),
		int(result.get("placements", 0)),
		int(result.get("portals", 0)),
		output_dir,
	])
	quit(0)


func _parse_cli(args: PackedStringArray) -> Dictionary:
	var seed_seen: bool = false
	var output_seen: bool = false
	var seed_value: int = 0
	var output_dir: String = ""
	var reverse_input: bool = false
	var index: int = 0
	while index < args.size():
		var argument: String = str(args[index])
		if argument == "--reverse-input":
			reverse_input = true
			index += 1
			continue
		if argument == "--seed":
			if index + 1 >= args.size() or not str(args[index + 1]).is_valid_int():
				return {"ok": false, "error": "--seed requires an integer"}
			seed_value = int(args[index + 1])
			seed_seen = true
			index += 2
			continue
		if argument == "--output-dir":
			if index + 1 >= args.size() or str(args[index + 1]).is_empty():
				return {"ok": false, "error": "--output-dir requires a directory"}
			output_dir = str(args[index + 1])
			output_seen = true
			index += 2
			continue
		return {"ok": false, "error": "unknown argument: %s" % argument}
	if not seed_seen or not output_seen:
		return {"ok": false, "error": "usage requires --seed <int> --output-dir <path>"}
	return {"ok": true, "seed": seed_value, "output_dir": output_dir, "reverse_input": reverse_input}


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path(path)


func _canonicalize_layout_input(source_layout: Dictionary, reverse_input: bool) -> Dictionary:
	var layout: Dictionary = source_layout.duplicate(true)
	if reverse_input:
		for field in ["rooms", "portals", "adjacency_intents", "room_links", "structural_room_links"]:
			_reverse_array_field(layout, field)
		var reversed_rooms: Variant = layout.get("rooms", null)
		if reversed_rooms is Array:
			for room_variant in reversed_rooms:
				if room_variant is Dictionary:
					_reverse_array_value(room_variant as Dictionary, "cells")

	var rooms: Array = []
	var raw_rooms: Variant = layout.get("rooms", [])
	if raw_rooms is Array:
		for room_variant in raw_rooms:
			if room_variant is Dictionary:
				var room: Dictionary = (room_variant as Dictionary).duplicate(true)
				room["cells"] = _sorted_cells(room.get("cells", []))
				rooms.append(room)
		rooms.sort_custom(Callable(self, "_record_precedes"))
		layout["rooms"] = rooms

	var portals: Array = []
	var raw_portals: Variant = layout.get("portals", [])
	if raw_portals is Array:
		for portal_variant in raw_portals:
			if portal_variant is Dictionary:
				portals.append(_canonicalize_portal_record(portal_variant as Dictionary))
		portals.sort_custom(Callable(self, "_record_precedes"))
		layout["portals"] = portals
	return layout


func _reverse_array_field(container: Dictionary, field: String) -> void:
	var raw_value: Variant = container.get(field, null)
	if raw_value is Array:
		var reversed: Array = []
		for index in range((raw_value as Array).size() - 1, -1, -1):
			reversed.append((raw_value as Array)[index])
		container[field] = reversed


func _reverse_array_value(container: Dictionary, field: String) -> void:
	var raw_value: Variant = container.get(field, null)
	if raw_value is Array:
		var reversed: Array = []
		for index in range((raw_value as Array).size() - 1, -1, -1):
			reversed.append((raw_value as Array)[index])
		container[field] = reversed


func _canonicalize_portal_record(source: Dictionary) -> Dictionary:
	var portal: Dictionary = source.duplicate(true)
	var from_room: String = str(portal.get("from_room", portal.get("room_a", "")))
	var to_room: String = str(portal.get("to_room", portal.get("room_b", "")))
	if not from_room.is_empty() and not to_room.is_empty() and from_room > to_room:
		if portal.has("from_room") or portal.has("to_room"):
			portal["from_room"] = to_room
			portal["to_room"] = from_room
		if portal.has("room_a") or portal.has("room_b"):
			portal["room_a"] = to_room
			portal["room_b"] = from_room
		_swap_field_pair(portal, "from_cell", "to_cell")
		_swap_field_pair(portal, "from_direction", "to_direction")
		var source_cells: Variant = portal.get("source_cells", null)
		if source_cells is Array and (source_cells as Array).size() == 2:
			portal["source_cells"] = [(source_cells as Array)[1], (source_cells as Array)[0]]
		if portal.has("from_cell"):
			portal["cell"] = portal["from_cell"]
		elif portal.get("source_cells", null) is Array and (portal["source_cells"] as Array).size() == 2:
			portal["cell"] = (portal["source_cells"] as Array)[0]
		if portal.has("direction") and portal.has("opposite_direction"):
			var direction: Variant = portal["direction"]
			portal["direction"] = portal["opposite_direction"]
			portal["opposite_direction"] = direction
		elif portal.has("normal_direction") and portal.has("opposite_direction"):
			var normal_direction: Variant = portal["normal_direction"]
			portal["normal_direction"] = portal["opposite_direction"]
			portal["opposite_direction"] = normal_direction
	return portal


func _swap_field_pair(container: Dictionary, first_field: String, second_field: String) -> void:
	if not container.has(first_field) and not container.has(second_field):
		return
	var first: Variant = container.get(first_field, null)
	container[first_field] = container.get(second_field, null)
	container[second_field] = first


func _sorted_cells(raw_cells: Variant) -> Array:
	var cells: Array = []
	if raw_cells is Array:
		for cell in raw_cells:
			cells.append(cell)
	cells.sort_custom(Callable(self, "_cell_precedes"))
	return cells


func _cell_precedes(first: Variant, second: Variant) -> bool:
	return _cell_sort_key(first) < _cell_sort_key(second)


func _cell_sort_key(value: Variant) -> String:
	if value is Vector2i:
		var cell: Vector2i = value
		return "%d|%d" % [cell.x, cell.y]
	return JSON.stringify(_canonical_value(value), "", false)


func _export_seed(seed_value: int, output_dir: String, reverse_input: bool = false) -> Dictionary:
	if not DirAccess.make_dir_recursive_absolute(output_dir) == OK:
		return {"ok": false, "error": "cannot create output directory: %s" % output_dir}

	var blueprint = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.SMALL,
		ShipBlueprintScript.Condition.WRECKED,
		seed_value)
	blueprint.room_count_range = Vector2i(MIN_DERELICT_ROOMS, MAX_DERELICT_ROOMS)
	var layout_generator = ShipLayoutGeneratorScript.new()
	var generated_layout: Dictionary = layout_generator.generate_with_options(
		blueprint,
		_derelict_archetype(),
		"",
		"",
		true,
	)
	if generated_layout.is_empty():
		return {"ok": false, "error": "production layout generation returned an empty layout"}

	# The compiler accepts solved room/input arrays, so normalize those arrays
	# before compiling. This makes a debug export independent of whether an
	# upstream caller enumerated equivalent rooms, cells, or portal intents in
	# forward or reverse order. `--reverse-input` intentionally exercises the
	# same boundary for the behavioral regression.
	var layout: Dictionary = _canonicalize_layout_input(generated_layout, reverse_input)
	var room_count: int = (layout.get("rooms", []) as Array).size()
	if room_count < MIN_DERELICT_ROOMS or room_count > MAX_DERELICT_ROOMS:
		return {"ok": false, "error": "room count %d is outside [%d,%d]" % [room_count, MIN_DERELICT_ROOMS, MAX_DERELICT_ROOMS]}

	var compiler = StructuralEdgeCompilerScript.new()
	var structural_plan: Dictionary = compiler.compile(layout)
	var compiler_errors: Array = structural_plan.get("errors", []) if structural_plan.get("errors", []) is Array else []
	if not compiler_errors.is_empty():
		return {"ok": false, "error": "compiler errors: %s" % JSON.stringify(_sorted_strings(compiler_errors))}
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
	if not bool(verdict.get("ok", false)):
		return {"ok": false, "error": "validation errors: %s" % JSON.stringify(_sorted_strings(verdict.get("errors", [])))}

	var topology_document: Dictionary = _topology_document(layout, seed_value)
	var occupancy_document: Dictionary = {
		"schema_version": "1.0.0",
		"document_kind": "procgen_structural_occupancy",
		"seed": seed_value,
		"occupancy": _sorted_occupancy(structural_plan.get("occupancy", {})),
	}
	var edge_document: Dictionary = {
		"schema_version": "1.0.0",
		"document_kind": "procgen_structural_edge_map",
		"seed": seed_value,
		"edges": _sorted_records(structural_plan.get("edges", {})),
	}
	var placement_document: Dictionary = {
		"schema_version": "1.0.0",
		"document_kind": "procgen_structural_placements",
		"seed": seed_value,
		"placements": _sorted_records(structural_plan.get("placements", [])),
		"floor_placements": _sorted_records(structural_plan.get("floor_placements", [])),
	}
	var validation_document: Dictionary = {
		"schema_version": "1.0.0",
		"document_kind": "procgen_structural_validation",
		"seed": seed_value,
		"ok": bool(verdict.get("ok", false)),
		"errors": _sorted_strings(verdict.get("errors", [])),
		"compiler_errors": _sorted_strings(compiler_errors),
		"stats": verdict.get("stats", {}),
	}

	var writes: Array[Dictionary] = [
		{"name": "topology.json", "value": topology_document},
		{"name": "occupancy.json", "value": occupancy_document},
		{"name": "edge_map.json", "value": edge_document},
		{"name": "placements.json", "value": placement_document},
		{"name": "validation.json", "value": validation_document},
	]
	for write_spec in writes:
		if not _write_json(output_dir.path_join(str(write_spec["name"])), write_spec["value"]):
			return {"ok": false, "error": "cannot write %s" % str(write_spec["name"])}

	var image: Image = _render_topdown(structural_plan)
	if image.save_png(output_dir.path_join("topdown_layout.png")) != OK:
		return {"ok": false, "error": "cannot write topdown_layout.png"}

	var stats: Dictionary = verdict.get("stats", {})
	return {
		"ok": true,
		"rooms": room_count,
		"placements": int(stats.get("placement_count", (structural_plan.get("placements", []) as Array).size())),
		"portals": int(stats.get("portal_count", 0)),
	}


func _derelict_archetype() -> Dictionary:
	return {
		"name": "Derelict",
		"type": "derelict",
		"template": DERELICT_TEMPLATE,
		"guaranteed_roles": [],
		"role_weights": {},
		"max_duplicates": 3,
	}


func _topology_document(layout: Dictionary, seed_value: int) -> Dictionary:
	var topology: Dictionary = layout.duplicate(true)
	topology["schema_version"] = "1.0.0"
	topology["document_kind"] = "procgen_structural_topology"
	topology["seed"] = seed_value
	# These fields are collections, not ordered paths. Sort every collection
	# emitted by the layout serializer so equivalent reversed input cannot leak
	# into topology.json. Ordered fields such as critical_path remain untouched.
	for field in [
		"rooms",
		"portals",
		"adjacency_intents",
		"room_links",
		"structural_room_links",
		"arc_zones",
		"blocked_links",
		"breach_zones",
		"encounters",
		"fire_zones",
		"landmarks",
		"vertical_connections",
	]:
		if topology.get(field, null) is Array:
			topology[field] = _sorted_records(topology[field])
	return _canonical_value(topology)


func _write_json(path: String, value: Variant) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_canonical_value(value), "", false) + "\n")
	file.close()
	return true


func _sorted_occupancy(raw_occupancy: Variant) -> Array:
	var records: Array = []
	if raw_occupancy is Dictionary:
		var keys: Array[String] = []
		for key_variant in raw_occupancy.keys():
			keys.append(str(key_variant))
		keys.sort()
		for key in keys:
			var record_variant: Variant = raw_occupancy[key]
			if not (record_variant is Dictionary):
				continue
			var record: Dictionary = record_variant.duplicate(true)
			record["cell_key"] = key
			records.append(record)
	elif raw_occupancy is Array:
		for record_variant in raw_occupancy:
			if record_variant is Dictionary:
				records.append((record_variant as Dictionary).duplicate(true))
	return _sorted_records(records)


func _sorted_records(raw_records: Variant) -> Array:
	var records: Array = []
	if raw_records is Dictionary:
		var keys: Array[String] = []
		for key_variant in raw_records.keys():
			keys.append(str(key_variant))
		keys.sort()
		for key in keys:
			var record_variant: Variant = raw_records[key]
			if record_variant is Dictionary:
				var record: Dictionary = (record_variant as Dictionary).duplicate(true)
				if not record.has("edge_key") and key.find("|") >= 0:
					record["edge_key"] = key
				records.append(record)
	elif raw_records is Array:
		for record_variant in raw_records:
			if record_variant is Dictionary:
				records.append((record_variant as Dictionary).duplicate(true))
	records.sort_custom(Callable(self, "_record_precedes"))
	return records


func _record_precedes(first: Variant, second: Variant) -> bool:
	return _record_sort_key(first) < _record_sort_key(second)


func _record_sort_key(value: Variant) -> String:
	if not (value is Dictionary):
		return str(value)
	var record: Dictionary = value
	var primary: String = ""
	for field in ["placement_id", "edge_key", "cell_key", "id", "key", "room_id"]:
		if record.has(field):
			primary = "%s|%s" % [field, str(record[field])]
			break
	# The primary identity keeps related records grouped; the complete canonical
	# record is a deterministic tie-breaker for records sharing that identity.
	return primary + "|" + JSON.stringify(_canonical_value(record), "", false)


func _sorted_strings(raw_values: Variant) -> Array:
	var values: Array[String] = []
	if raw_values is Array:
		for value in raw_values:
			values.append(str(value))
	values.sort()
	return values


func _canonical_value(value: Variant) -> Variant:
	if value is Vector2i:
		return [int((value as Vector2i).x), int((value as Vector2i).y)]
	if value is Vector3:
		var vector: Vector3 = value
		return [float(vector.x), float(vector.y), float(vector.z)]
	if value is Dictionary:
		var source: Dictionary = value
		var keys: Array[String] = []
		for key_variant in source.keys():
			keys.append(str(key_variant))
		keys.sort()
		var ordered: Dictionary = {}
		for key in keys:
			ordered[key] = _canonical_value(source[key])
		return ordered
	if value is Array:
		var array_value: Array = []
		for item in value:
			array_value.append(_canonical_value(item))
		return array_value
	return value


func _render_topdown(plan: Dictionary) -> Image:
	var occupancy: Array = _sorted_occupancy(plan.get("occupancy", {}))
	var min_x: int = 0
	var max_x: int = 0
	var min_z: int = 0
	var max_z: int = 0
	var first_cell: bool = true
	for record_variant in occupancy:
		if not (record_variant is Dictionary):
			continue
		var record: Dictionary = record_variant
		var cell_result: Dictionary = _read_cell(record.get("cell", null))
		if not bool(cell_result.get("ok", false)):
			continue
		var cell: Vector2i = cell_result["cell"]
		if first_cell:
			min_x = cell.x
			max_x = cell.x
			min_z = cell.y
			max_z = cell.y
			first_cell = false
		else:
			min_x = mini(min_x, cell.x)
			max_x = maxi(max_x, cell.x)
			min_z = mini(min_z, cell.y)
			max_z = maxi(max_z, cell.y)
	if first_cell:
		return Image.create(128, 128, false, Image.FORMAT_RGBA8)

	var grid_width: int = max_x - min_x + 1
	var grid_height: int = max_z - min_z + 1
	var image: Image = Image.create(
		grid_width * CELL_PIXELS + IMAGE_PADDING * 2,
		grid_height * CELL_PIXELS + IMAGE_PADDING * 2 + LEGEND_HEIGHT,
		false,
		Image.FORMAT_RGBA8,
	)
	image.fill(Color(0.035, 0.045, 0.065, 1.0))

	for record_variant in occupancy:
		if not (record_variant is Dictionary):
			continue
		var record: Dictionary = record_variant
		var cell_result: Dictionary = _read_cell(record.get("cell", null))
		if not bool(cell_result.get("ok", false)):
			continue
		var cell: Vector2i = cell_result["cell"]
		var top_left: Vector2i = _cell_top_left(cell, min_x, min_z)
		_draw_filled_rect(image, top_left + Vector2i(2, 2), Vector2i(CELL_PIXELS - 4, CELL_PIXELS - 4), Color(0.12, 0.15, 0.20, 1.0))

	var edges: Array = _sorted_records(plan.get("edges", {}))
	for edge_variant in edges:
		if not (edge_variant is Dictionary):
			continue
		var edge: Dictionary = edge_variant
		var cell_result: Dictionary = _read_cell(edge.get("cell", null))
		var direction: String = str(edge.get("direction", ""))
		if not bool(cell_result.get("ok", false)) or not StructuralEdgePlanScript.DIRECTIONS.has(direction):
			continue
		var cell: Vector2i = cell_result["cell"]
		var segment: Dictionary = _edge_segment(cell, direction, min_x, min_z)
		var kind: String = str(edge.get("kind", edge.get("state", "SOLID"))).to_upper()
		var color: Color = EDGE_COLORS.get(kind, Color.WHITE)
		_draw_line(image, segment["from"], segment["to"], color, 3)
		if _is_portal_edge(edge, kind):
			_draw_normal_arrow(image, segment["center"], direction, color)

	# Always include all canonical edge-state swatches, even when a particular
	# seed has no locked/hatch/breach edge. This keeps the PNG color contract
	# machine-checkable and makes exports comparable across seeds.
	var legend_x: int = IMAGE_PADDING
	var legend_y: int = image.get_height() - LEGEND_HEIGHT + 4
	for state in ["SOLID", "OPEN", "DOOR", "LOCKED", "HATCH", "BREACH"]:
		_draw_filled_rect(image, Vector2i(legend_x, legend_y), Vector2i(20, 16), EDGE_COLORS[state])
		legend_x += 24
	return image


func _read_cell(value: Variant) -> Dictionary:
	if value is Vector2i:
		return {"ok": true, "cell": value}
	if value is Array and (value as Array).size() >= 2:
		var values: Array = value
		if typeof(values[0]) == TYPE_INT and typeof(values[1]) == TYPE_INT:
			return {"ok": true, "cell": Vector2i(int(values[0]), int(values[1]))}
	return {"ok": false}


func _cell_top_left(cell: Vector2i, min_x: int, min_z: int) -> Vector2i:
	return Vector2i(
		IMAGE_PADDING + (cell.x - min_x) * CELL_PIXELS,
		IMAGE_PADDING + (cell.y - min_z) * CELL_PIXELS,
	)


func _edge_segment(cell: Vector2i, direction: String, min_x: int, min_z: int) -> Dictionary:
	var top_left: Vector2i = _cell_top_left(cell, min_x, min_z)
	var from: Vector2i = top_left
	var to: Vector2i = top_left + Vector2i(CELL_PIXELS, 0)
	match direction:
		"north":
			from = top_left
			to = top_left + Vector2i(CELL_PIXELS, 0)
		"east":
			from = top_left + Vector2i(CELL_PIXELS, 0)
			to = top_left + Vector2i(CELL_PIXELS, CELL_PIXELS)
		"south":
			from = top_left + Vector2i(0, CELL_PIXELS)
			to = top_left + Vector2i(CELL_PIXELS, CELL_PIXELS)
		"west":
			from = top_left
			to = top_left + Vector2i(0, CELL_PIXELS)
	return {"from": from, "to": to, "center": (from + to) / 2}


func _is_portal_edge(edge: Dictionary, kind: String) -> bool:
	return kind in ["DOOR", "LOCKED", "HATCH", "BREACH"] or (kind == "OPEN" and bool(edge.get("portal", false)))


func _draw_normal_arrow(image: Image, center: Vector2i, direction: String, color: Color) -> void:
	var normal: Vector2i = Vector2i.ZERO
	match direction:
		"north": normal = Vector2i(0, -1)
		"east": normal = Vector2i(1, 0)
		"south": normal = Vector2i(0, 1)
		"west": normal = Vector2i(-1, 0)
	var tip: Vector2i = center + normal * 11
	var tail: Vector2i = center - normal * 5
	_draw_line(image, tail, tip, color, 2)
	var perpendicular: Vector2i = Vector2i(-normal.y, normal.x)
	_draw_line(image, tip, tip - normal * 5 + perpendicular * 4, color, 2)
	_draw_line(image, tip, tip - normal * 5 - perpendicular * 4, color, 2)


func _draw_filled_rect(image: Image, position: Vector2i, size: Vector2i, color: Color) -> void:
	for x in range(maxi(position.x, 0), mini(position.x + size.x, image.get_width())):
		for y in range(maxi(position.y, 0), mini(position.y + size.y, image.get_height())):
			image.set_pixel(x, y, color)


func _draw_line(image: Image, from: Vector2i, to: Vector2i, color: Color, thickness: int = 1) -> void:
	var dx: int = absi(to.x - from.x)
	var dy: int = absi(to.y - from.y)
	var sx: int = 1 if from.x < to.x else -1
	var sy: int = 1 if from.y < to.y else -1
	var error: int = dx - dy
	var x: int = from.x
	var y: int = from.y
	while true:
		for offset_x in range(-thickness / 2, thickness / 2 + 1):
			for offset_y in range(-thickness / 2, thickness / 2 + 1):
				var pixel_x: int = x + offset_x
				var pixel_y: int = y + offset_y
				if pixel_x >= 0 and pixel_x < image.get_width() and pixel_y >= 0 and pixel_y < image.get_height():
					image.set_pixel(pixel_x, pixel_y, color)
		if x == to.x and y == to.y:
			break
		var double_error: int = 2 * error
		if double_error > -dy:
			error -= dy
			x += sx
		if double_error < dx:
			error += dx
			y += sy
