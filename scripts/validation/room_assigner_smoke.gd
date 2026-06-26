extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")
const RoomAssignerScript := preload("res://scripts/procgen/room_assigner.gd")

func _initialize() -> void:
	var template_data: Dictionary = {
		"id": "test",
		"description": "Test",
		"zones": [
			{"id": "entry", "role_pool": ["airlock"], "count": 1,
			 "position_hint": "bow", "deck": 0, "layout": "single", "attach_to": ""},
			{"id": "spine", "role_pool": ["corridor", "main_spine"], "count": [2, 3],
			 "position_hint": "center", "deck": 0, "layout": "linear", "attach_to": "entry"},
			{"id": "side", "role_pool": ["cargo", "engineering", "medical"], "count": [1, 2],
			 "position_hint": "lateral", "deck": 0, "layout": "clustered", "attach_to": "spine"},
			{"id": "destination", "role_pool": ["reactor"], "count": 1,
			 "position_hint": "stern", "deck": 0, "layout": "single", "attach_to": "spine"},
		],
		"connections": [
			{"from": "entry", "to": "spine[0]", "distribution": "adjacent"},
		],
		"deck_config": {"max_decks": 1, "vertical_transition_probability": 0.0},
	}
	var template: TopologyTemplateScript = TopologyTemplateScript.from_dict(template_data)

	var bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)

	var assigner: RoomAssignerScript = RoomAssignerScript.new()
	var room_plan: Array[Dictionary] = assigner.assign(template, bp, {})

	# Must have at least 5 rooms: 1 entry + 2-3 spine + 1-2 side + 1 dest
	if room_plan.size() < 5:
		push_error("ROOM ASSIGNER FAIL room_count=%d expected>=5" % room_plan.size())
		quit(1)
		return

	# First room must be the entry (airlock)
	if str(room_plan[0].get("role", "")) != "airlock":
		push_error("ROOM ASSIGNER FAIL first room role=%s expected=airlock" % str(room_plan[0].get("role", "")))
		quit(1)
		return

	# Last room must be the destination (reactor)
	if str(room_plan[-1].get("role", "")) != "reactor":
		push_error("ROOM ASSIGNER FAIL last room role=%s expected=reactor" % str(room_plan[-1].get("role", "")))
		quit(1)
		return

	# Every room must have required keys
	var required_keys: Array[String] = ["id", "role", "zone_id", "deck", "position_hint", "target_cells", "footprint"]
	for room in room_plan:
		for key in required_keys:
			if not room.has(key):
				push_error("ROOM ASSIGNER FAIL room %s missing key %s" % [str(room.get("id", "?")), key])
				quit(1)
				return

	# Room ids must be unique
	var seen_ids: Dictionary = {}
	for room in room_plan:
		var rid: String = str(room["id"])
		if seen_ids.has(rid):
			push_error("ROOM ASSIGNER FAIL duplicate room id=%s" % rid)
			quit(1)
			return
		seen_ids[rid] = true

	# Every room must have a positive footprint
	for room in room_plan:
		var fp: Vector2i = room["footprint"]
		if fp.x < 1 or fp.y < 1:
			push_error("ROOM ASSIGNER FAIL room %s footprint=%s" % [str(room["id"]), str(fp)])
			quit(1)
			return

	# Determinism: same seed = same plan
	var plan_a: Array[Dictionary] = assigner.assign(template, bp, {})
	var plan_b: Array[Dictionary] = assigner.assign(template, bp, {})
	if str(plan_a) != str(plan_b):
		push_error("ROOM ASSIGNER FAIL determinism mismatch")
		quit(1)
		return

	print("ROOM ASSIGNER PASS rooms=%d first=airlock last=reactor keys=valid ids=unique deterministic=true" % room_plan.size())
	quit(0)
