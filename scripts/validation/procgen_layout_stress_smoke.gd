extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const StructuralEdgePlanScript := preload("res://scripts/procgen/structural_edge_plan.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")

const CARDINAL_DIRS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]

var seed17_room_count: int = 0
var seed17_occupied_cell_count: int = 0
var seed17_portal_count: int = 0
var seed17_compiler_error_count: int = 0

func _initialize() -> void:
	if not _check_connector_growth_geometry_probes():
		quit(1)
		return
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var templates: Array[String] = ["spine", "bifurcated", "stacked"]
	var total: int = 0
	var passed: int = 0
	var min_rooms: int = 999
	var max_rooms: int = 0

	# Generate 20 ships: ~7 per template
	for seed_val in range(1, 21):
		for template_id in templates:
			total += 1
			var bp: ShipBlueprintScript = ShipBlueprintScript.new(
				ShipBlueprintScript.Size.MEDIUM,
				ShipBlueprintScript.Condition.PRISTINE,
				seed_val)
			var layout: Dictionary = generator.generate(bp, {"template": template_id})

			if layout.is_empty():
				push_error("STRESS FAIL %s seed=%d empty" % [template_id, seed_val])
				quit(1)
				return

			var rooms: Array = layout.get("rooms", [])
			if rooms.size() < 3:
				push_error("STRESS FAIL %s seed=%d only %d rooms" % [template_id, seed_val, rooms.size()])
				quit(1)
				return

			if seed_val == 17 and not _check_seed_17_structural_contract(layout, template_id):
				quit(1)
				return

			# Check no zero-placement rooms
			for room in rooms:
				if room.get("structural_placements", []).is_empty():
					push_error("STRESS FAIL %s seed=%d room %s no placements" % [
						template_id, seed_val, str(room.get("id", "?"))])
					quit(1)
					return

			if rooms.size() < min_rooms:
				min_rooms = rooms.size()
			if rooms.size() > max_rooms:
				max_rooms = rooms.size()

			passed += 1

	# Golden comparison: same seed = same layout
	var golden_bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 12345)

	for template_id in templates:
		var a: String = JSON.stringify(generator.generate(golden_bp, {"template": template_id}))
		var b: String = JSON.stringify(generator.generate(golden_bp, {"template": template_id}))
		if a != b:
			push_error("STRESS FAIL golden comparison mismatch template=%s" % template_id)
			quit(1)
			return

	print("PROCGEN LAYOUT STRESS PASS total=%d/%d rooms=[%d,%d] golden=deterministic" % [
		passed, total, min_rooms, max_rooms])
	print("PROCGEN LAYOUT STRESS SEED17 PASS rooms=%d occupied_cells=%d portals=%d compiler_errors=%d" % [
		seed17_room_count, seed17_occupied_cell_count, seed17_portal_count, seed17_compiler_error_count])
	quit(0)


func _check_seed_17_structural_contract(layout: Dictionary, label: String) -> bool:
	var ownership: Dictionary = {}
	seed17_room_count = (layout.get("rooms", []) as Array).size()
	for room_variant in layout.get("rooms", []):
		if not (room_variant is Dictionary):
			push_error("STRESS FAIL %s seed=17 room record is not a Dictionary" % label)
			return false
		var room: Dictionary = room_variant
		var cells: Variant = room.get("cells", null)
		if not (cells is Array) or (cells as Array).is_empty():
			push_error("STRESS FAIL %s seed=17 room %s has empty cells" % [label, str(room.get("id", "?"))])
			return false
		if not room.has("footprint"):
			push_error("STRESS FAIL %s seed=17 room %s has no footprint" % [label, str(room.get("id", "?"))])
			return false
		var geometry: Dictionary = _validate_room_cell_geometry(cells, room.get("footprint", null))
		if not bool(geometry.get("ok", false)):
			push_error("STRESS FAIL %s seed=17 room %s invalid cell geometry: %s" % [
				label, str(room.get("id", "?")), str(geometry.get("reason", "unknown"))])
			return false
		var room_cell_coordinates: Dictionary = {}
		for cell_variant in cells:
			if not (cell_variant is Vector2i):
				push_error("STRESS FAIL %s seed=17 room %s has non-integer cell" % [label, str(room.get("id", "?"))])
				return false
			var cell: Vector2i = cell_variant
			var key := StructuralEdgePlanScript.cell_key(int(room.get("deck", 0)), cell)
			if room_cell_coordinates.has(key):
				push_error("STRESS FAIL %s seed=17 room %s duplicate cell %s" % [label, str(room.get("id", "?")), key])
				return false
			room_cell_coordinates[key] = true
			if ownership.has(key):
				push_error("STRESS FAIL %s seed=17 ownership collision at %s" % [label, key])
				return false
			ownership[key] = str(room.get("id", ""))

		var floor_coordinates: Dictionary = {}
		var floor_placement_count: int = 0
		for placement_variant in room.get("structural_placements", []):
			if not (placement_variant is Dictionary):
				continue
			var placement: Dictionary = placement_variant
			if not str(placement.get("name", "")).begins_with("floor_cell"):
				continue
			floor_placement_count += 1
			var world_position: Variant = placement.get("world_position", null)
			if not (world_position is Array) or (world_position as Array).size() != 3:
				push_error("STRESS FAIL %s seed=17 room %s floor has invalid world_position" % [label, str(room.get("id", "?"))])
				return false
			var position: Array = world_position
			var deck: int = int(room.get("deck", 0))
			var x_float: float = float(position[0]) / 4.0
			var z_float: float = float(position[2]) / 4.0
			if not is_equal_approx(x_float, round(x_float)) or not is_equal_approx(z_float, round(z_float)):
				push_error("STRESS FAIL %s seed=17 room %s floor is off integer grid" % [label, str(room.get("id", "?"))])
				return false
			if not is_equal_approx(float(position[1]), float(deck) * 4.0):
				push_error("STRESS FAIL %s seed=17 room %s floor deck mismatch" % [label, str(room.get("id", "?"))])
				return false
			var floor_cell: Vector2i = Vector2i(int(round(x_float)), int(round(z_float)))
			var floor_key: String = StructuralEdgePlanScript.cell_key(deck, floor_cell)
			if floor_coordinates.has(floor_key):
				push_error("STRESS FAIL %s seed=17 room %s duplicate floor coordinate %s" % [label, str(room.get("id", "?")), floor_key])
				return false
			floor_coordinates[floor_key] = true
		if floor_placement_count != floor_coordinates.size() or floor_coordinates.size() != room_cell_coordinates.size():
			push_error("STRESS FAIL %s seed=17 room %s floor/cell set cardinality mismatch" % [label, str(room.get("id", "?"))])
			return false
		for cell_key_variant in room_cell_coordinates.keys():
			var cell_key: String = str(cell_key_variant)
			if not floor_coordinates.has(cell_key):
				push_error("STRESS FAIL %s seed=17 room %s floor missing coordinate %s" % [label, str(room.get("id", "?")), cell_key])
				return false
		for floor_key_variant in floor_coordinates.keys():
			var floor_key: String = str(floor_key_variant)
			if not room_cell_coordinates.has(floor_key):
				push_error("STRESS FAIL %s seed=17 room %s emitted unowned floor %s" % [label, str(room.get("id", "?")), floor_key])
				return false
	if label == "bifurcated" and not _check_seed_17_bifurcated_connector_growth(layout):
		return false
	seed17_occupied_cell_count = ownership.size()

	var structural_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(layout)
	seed17_compiler_error_count = (structural_plan.get("errors", []) as Array).size()
	if not (structural_plan.get("errors", []) as Array).is_empty():
		push_error("STRESS FAIL %s seed=17 compiler errors=%s" % [label, JSON.stringify(structural_plan["errors"])])
		return false
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
	if not bool(verdict.get("ok", false)):
		push_error("STRESS FAIL %s seed=17 structural validation errors=%s" % [label, JSON.stringify(verdict["errors"])])
		return false
	var portal_record_counts: Dictionary = {}
	seed17_portal_count = (layout.get("portals", []) as Array).size()
	for portal_variant in layout.get("portals", []):
		if not (portal_variant is Dictionary):
			push_error("STRESS FAIL %s seed=17 portal record is not a Dictionary" % label)
			return false
		var portal: Dictionary = portal_variant
		var portal_edge_key: String = str(portal.get("edge_key", ""))
		if portal_edge_key.is_empty():
			push_error("STRESS FAIL %s seed=17 portal has no edge_key" % label)
			return false
		portal_record_counts[portal_edge_key] = int(portal_record_counts.get(portal_edge_key, 0)) + 1

	var structural_portal_placement_counts: Dictionary = {}
	for placement_variant in structural_plan.get("placements", []):
		if not (placement_variant is Dictionary):
			continue
		var placement: Dictionary = placement_variant
		var placement_kind: String = str(placement.get("kind", ""))
		if placement_kind in ["DOOR", "LOCKED", "HATCH", "BREACH"]:
			var placement_edge_key: String = str(placement.get("edge_key", ""))
			structural_portal_placement_counts[placement_edge_key] = int(
				structural_portal_placement_counts.get(placement_edge_key, 0)) + 1

	# Derive required intents from the pre-dedup source adjacency records, not
	# structural_room_links (which is deliberately a one-record-per-edge view).
	var original_intents: Variant = layout.get("adjacency_intents", null)
	if not (original_intents is Array):
		push_error("STRESS FAIL %s seed=17 missing original adjacency intents" % label)
		return false
	var room_decks: Dictionary = {}
	for room_variant in layout.get("rooms", []):
		if room_variant is Dictionary:
			var room: Dictionary = room_variant
			room_decks[str(room.get("id", ""))] = int(room.get("deck", 0))
	for adjacency_variant in original_intents:
		if not (adjacency_variant is Dictionary):
			push_error("STRESS FAIL %s seed=17 original adjacency is not a Dictionary" % label)
			return false
		var adjacency: Dictionary = adjacency_variant
		if not bool(adjacency.get("required", true)):
			continue
		var from_room: String = str(adjacency.get("from_room", ""))
		var to_room: String = str(adjacency.get("to_room", ""))
		if not room_decks.has(from_room) or not room_decks.has(to_room):
			push_error("STRESS FAIL %s seed=17 required adjacency references an unknown room" % label)
			return false
		var from_deck: int = int(room_decks[from_room])
		var to_deck: int = int(room_decks[to_room])
		if from_deck != to_deck:
			# Cross-deck links are validated as logical connectivity elsewhere;
			# they have no same-deck portal edge.
			continue
		var from_cell_result: Dictionary = _integer_cell(adjacency.get("from_cell", null))
		var to_cell_result: Dictionary = _integer_cell(adjacency.get("to_cell", null))
		if not bool(from_cell_result.get("ok", false)) or not bool(to_cell_result.get("ok", false)):
			push_error("STRESS FAIL %s seed=17 required adjacency has invalid endpoint cells" % label)
			return false
		var from_cell: Vector2i = from_cell_result["cell"]
		var to_cell: Vector2i = to_cell_result["cell"]
		var direction: String = _direction_between(from_cell, to_cell)
		if direction.is_empty():
			push_error("STRESS FAIL %s seed=17 required adjacency is not cardinal" % label)
			return false
		var required_edge_key: String = StructuralEdgePlanScript.edge_key(from_deck, from_cell, direction)
		if int(portal_record_counts.get(required_edge_key, 0)) != 1:
			push_error("STRESS FAIL %s seed=17 required adjacency %s does not map to exactly one portal record" % [label, required_edge_key])
			return false
		if int(structural_portal_placement_counts.get(required_edge_key, 0)) != 1:
			push_error("STRESS FAIL %s seed=17 required adjacency %s does not map to exactly one portal edge placement" % [label, required_edge_key])
			return false
	for portal_edge_key_variant in portal_record_counts.keys():
		var portal_edge_key: String = str(portal_edge_key_variant)
		if int(portal_record_counts.get(portal_edge_key, 0)) != 1:
			push_error("STRESS FAIL %s seed=17 portal %s is duplicated" % [label, portal_edge_key])
			return false
		if int(structural_portal_placement_counts.get(portal_edge_key, 0)) != 1:
			push_error("STRESS FAIL %s seed=17 portal %s is missing its unique edge placement" % [label, portal_edge_key])
			return false
	return true


# ADR-0053 / REQ-ENC-001 permit connector-grown rooms whose occupied cells do
# not fill their axis-aligned bounding rectangle. Footprint is therefore the
# exact positive bounding box, while cells remain the structural authority.
func _validate_room_cell_geometry(cells_variant: Variant, footprint_variant: Variant) -> Dictionary:
	if not (cells_variant is Array) or (cells_variant as Array).is_empty():
		return {"ok": false, "reason": "empty cells"}
	if not (footprint_variant is Vector2i):
		return {"ok": false, "reason": "footprint is not Vector2i"}
	var footprint: Vector2i = footprint_variant
	if footprint.x <= 0 or footprint.y <= 0:
		return {"ok": false, "reason": "footprint is not positive"}
	var cells: Array = cells_variant
	var owned: Dictionary = {}
	var min_x: int = 2147483647
	var min_y: int = 2147483647
	var max_x: int = -2147483648
	var max_y: int = -2147483648
	for cell_variant in cells:
		if not (cell_variant is Vector2i):
			return {"ok": false, "reason": "non-integer cell"}
		var cell: Vector2i = cell_variant
		if owned.has(cell):
			return {"ok": false, "reason": "duplicate cell"}
		owned[cell] = true
		min_x = mini(min_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_x = maxi(max_x, cell.x)
		max_y = maxi(max_y, cell.y)
	var derived_footprint: Vector2i = Vector2i(max_x - min_x + 1, max_y - min_y + 1)
	if footprint != derived_footprint:
		return {"ok": false, "reason": "footprint is not exact derived bbox"}
	var reachable: Dictionary = {}
	var frontier: Array[Vector2i] = [cells[0]]
	reachable[cells[0]] = true
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for direction in CARDINAL_DIRS:
			var neighbor: Vector2i = current + direction
			if owned.has(neighbor) and not reachable.has(neighbor):
				reachable[neighbor] = true
				frontier.append(neighbor)
	if reachable.size() != owned.size():
		return {"ok": false, "reason": "cells are not 4-connected"}
	return {"ok": true, "origin": Vector2i(min_x, min_y), "footprint": derived_footprint}


func _check_connector_growth_geometry_probes() -> bool:
	var irregular_cells: Array[Vector2i] = [
		Vector2i(5, 1), Vector2i(5, 3), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3),
	]
	if not bool(_validate_room_cell_geometry(irregular_cells, Vector2i(2, 3)).get("ok", false)):
		push_error("STRESS FAIL connector-growth irregular 5-cell geometry rejected")
		return false
	if bool(_validate_room_cell_geometry([Vector2i(0, 0), Vector2i(0, 0)], Vector2i(1, 1)).get("ok", false)):
		push_error("STRESS FAIL connector-growth duplicate-cell probe accepted")
		return false
	if bool(_validate_room_cell_geometry([Vector2i(0, 0), Vector2i(2, 0)], Vector2i(3, 1)).get("ok", false)):
		push_error("STRESS FAIL connector-growth disconnected-cell probe accepted")
		return false
	if bool(_validate_room_cell_geometry([Vector2i(0, 0)], Vector2i(-1, 1)).get("ok", false)):
		push_error("STRESS FAIL connector-growth negative-bbox probe accepted")
		return false
	return true


func _check_seed_17_bifurcated_connector_growth(layout: Dictionary) -> bool:
	var expected_cells: Dictionary = {
		Vector2i(5, 1): true, Vector2i(5, 3): true, Vector2i(6, 1): true,
		Vector2i(6, 2): true, Vector2i(6, 3): true,
	}
	for room_variant in layout.get("rooms", []):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		if str(room.get("id", "")) != "corridor_04":
			continue
		var cells: Array = room.get("cells", [])
		if cells.size() != 5 or room.get("footprint", Vector2i.ZERO) != Vector2i(2, 3):
			push_error("STRESS FAIL bifurcated seed=17 corridor_04 lost the deterministic irregular 5-cell bbox")
			return false
		for cell_variant in cells:
			if not (cell_variant is Vector2i) or not expected_cells.has(cell_variant):
				push_error("STRESS FAIL bifurcated seed=17 corridor_04 cell set changed")
				return false
		# The hole is deliberately not owned by corridor_04. Global ownership is
		# checked above; another room may legally share this bounding-box area.
		if expected_cells.has(Vector2i(5, 2)):
			push_error("STRESS FAIL bifurcated seed=17 connector-growth proof defines its hole as occupied")
			return false
		for cell_variant in cells:
			if cell_variant == Vector2i(5, 2):
				push_error("STRESS FAIL bifurcated seed=17 corridor_04 connector-growth hole was filled")
				return false
		var actual_footprint: Vector2i = room.get("footprint", Vector2i.ZERO)
		if (room.get("cells", []) as Array).size() == actual_footprint.x * actual_footprint.y:
			push_error("STRESS FAIL bifurcated seed=17 corridor_04 no longer proves a non-rectangular connector-grown cell set")
			return false
		return true
	push_error("STRESS FAIL bifurcated seed=17 corridor_04 missing connector-growth proof room")
	return false


func _integer_cell(raw_cell: Variant) -> Dictionary:
	if raw_cell is Vector2i:
		return {"ok": true, "cell": raw_cell}
	if raw_cell is Array and (raw_cell as Array).size() == 2:
		var values: Array = raw_cell
		if typeof(values[0]) == TYPE_INT and typeof(values[1]) == TYPE_INT:
			return {"ok": true, "cell": Vector2i(int(values[0]), int(values[1]))}
	return {"ok": false, "cell": Vector2i.ZERO}


func _direction_between(from_cell: Vector2i, to_cell: Vector2i) -> String:
	var delta: Vector2i = to_cell - from_cell
	for direction_variant in StructuralEdgePlanScript.DIRECTIONS.keys():
		var direction: String = str(direction_variant)
		if StructuralEdgePlanScript.DIRECTIONS[direction] == delta:
			return direction
	return ""
