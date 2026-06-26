extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")

func _initialize() -> void:
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()

	# --- Case 1: spine template ---
	var bp1: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)
	var layout1: Dictionary = generator.generate(bp1, {"template": "spine"})
	if layout1.is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL spine returned empty")
		quit(1)
		return
	if not _validate_layout(layout1, "spine"):
		return

	# --- Case 2: bifurcated template ---
	var layout2: Dictionary = generator.generate(bp1, {"template": "bifurcated"})
	if layout2.is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL bifurcated returned empty")
		quit(1)
		return
	if not _validate_layout(layout2, "bifurcated"):
		return

	# --- Case 3: stacked template ---
	var layout3: Dictionary = generator.generate(bp1, {"template": "stacked"})
	if layout3.is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL stacked returned empty")
		quit(1)
		return
	if not _validate_layout(layout3, "stacked"):
		return

	# --- Case 4: determinism ---
	var layout_a: Dictionary = generator.generate(bp1, {"template": "spine"})
	var layout_b: Dictionary = generator.generate(bp1, {"template": "spine"})
	if str(layout_a) != str(layout_b):
		push_error("SHIP LAYOUT GENERATOR FAIL determinism mismatch")
		quit(1)
		return

	# --- Case 5: different seeds produce different layouts ---
	var bp2: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 999)
	var layout_c: Dictionary = generator.generate(bp2, {"template": "spine"})
	if str(layout_a) == str(layout_c):
		push_error("SHIP LAYOUT GENERATOR FAIL different seed same layout")
		quit(1)
		return

	print("SHIP LAYOUT GENERATOR PASS spine=true bifurcated=true stacked=true deterministic=true varied=true")
	quit(0)


func _validate_layout(layout: Dictionary, template_label: String) -> bool:
	var required_keys: Array[String] = [
		"schema_version", "document_kind", "rooms", "room_links",
		"critical_path", "prototype",
	]
	for key in required_keys:
		if not layout.has(key):
			push_error("SHIP LAYOUT GENERATOR FAIL %s missing key: %s" % [template_label, key])
			quit(1)
			return false

	var rooms: Array = layout.get("rooms", [])
	if rooms.size() < 3:
		push_error("SHIP LAYOUT GENERATOR FAIL %s only %d rooms" % [template_label, rooms.size()])
		quit(1)
		return false

	# First room must be entry (airlock/dock)
	var first_role: String = str(rooms[0].get("room_role", ""))
	if first_role != "airlock" and first_role != "dock":
		push_error("SHIP LAYOUT GENERATOR FAIL %s first room_role=%s" % [template_label, first_role])
		quit(1)
		return false

	# All rooms must have structural_placements
	for room in rooms:
		var placements: Array = room.get("structural_placements", [])
		if placements.is_empty():
			push_error("SHIP LAYOUT GENERATOR FAIL %s room %s has no placements" % [template_label, str(room.get("id", ""))])
			quit(1)
			return false

	# Critical path must start at prototype.start_room and end at prototype.goal_room
	var proto: Dictionary = layout.get("prototype", {})
	var cp: Array = layout.get("critical_path", [])
	if cp.is_empty():
		push_error("SHIP LAYOUT GENERATOR FAIL %s empty critical_path" % template_label)
		quit(1)
		return false
	if str(cp[0]) != str(proto.get("start_room", "")):
		push_error("SHIP LAYOUT GENERATOR FAIL %s critical_path[0] != start_room" % template_label)
		quit(1)
		return false
	if str(cp[-1]) != str(proto.get("goal_room", "")):
		push_error("SHIP LAYOUT GENERATOR FAIL %s critical_path[-1] != goal_room" % template_label)
		quit(1)
		return false

	return true
