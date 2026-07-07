extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const TopologyTemplateScript := preload("res://scripts/procgen/topology_template.gd")
const RoomAssignerScript := preload("res://scripts/procgen/room_assigner.gd")

func _initialize() -> void:
	var missing_footprints: Array[String] = _collect_missing_footprint_roles()
	if not missing_footprints.is_empty():
		push_error("ROOM ASSIGNER FAIL footprint vocabulary missing=%s" % str(missing_footprints))
		quit(1)
		return

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

	# --- Tranche 5 (2026-07-06 audit HIGH, room_assigner.gd:129): the archetype
	# JSON fields guaranteed_roles / max_duplicates were authored in all four
	# archetypes (derelict guarantees "dock") but never parsed — _pick_role read
	# only role_weights. Mirrors the derelict shape: dock is in a zone pool but
	# absent from role_weights, so unenforced assignment essentially never
	# places it; max_duplicates=1 must keep multi-pool roles unique.
	var constraint_template: TopologyTemplateScript = TopologyTemplateScript.from_dict({
		"id": "constraint_test",
		"description": "guaranteed_roles + max_duplicates enforcement",
		"zones": [
			{"id": "entry", "role_pool": ["airlock"], "count": 1,
			 "position_hint": "bow", "deck": 0, "layout": "single", "attach_to": ""},
			{"id": "spine", "role_pool": ["corridor", "main_spine"], "count": 2,
			 "position_hint": "center", "deck": 0, "layout": "linear", "attach_to": "entry"},
			{"id": "side", "role_pool": ["cargo", "engineering", "medical", "dock"], "count": 3,
			 "position_hint": "lateral", "deck": 0, "layout": "clustered", "attach_to": "spine"},
			{"id": "destination", "role_pool": ["reactor"], "count": 1,
			 "position_hint": "stern", "deck": 0, "layout": "single", "attach_to": "spine"},
		],
		"connections": [],
		"deck_config": {"max_decks": 1, "vertical_transition_probability": 0.0},
	})
	var constraint_archetype: Dictionary = {
		"guaranteed_roles": ["dock"],
		"max_duplicates": 1,
		"role_weights": {"cargo": 40, "engineering": 40, "corridor": 4, "main_spine": 4},
	}
	var constrained: Array[Dictionary] = assigner.assign(constraint_template, bp, constraint_archetype)

	var role_counts: Dictionary = {}
	for room in constrained:
		var r: String = str(room.get("role", ""))
		role_counts[r] = int(role_counts.get(r, 0)) + 1
	if int(role_counts.get("dock", 0)) < 1:
		push_error("ROOM ASSIGNER FAIL guaranteed_roles unenforced: 'dock' guaranteed by archetype but absent from plan (roles=%s)" % str(role_counts))
		quit(1)
		return
	# max_duplicates=1: every role picked from a multi-role pool appears at most once.
	for r in role_counts:
		if int(role_counts[r]) > 1:
			push_error("ROOM ASSIGNER FAIL max_duplicates=1 unenforced: role '%s' appears %d times (roles=%s)" % [str(r), int(role_counts[r]), str(role_counts)])
			quit(1)
			return
	# Entry/destination must survive enforcement untouched.
	if str(constrained[0].get("role", "")) != "airlock" or str(constrained[-1].get("role", "")) != "reactor":
		push_error("ROOM ASSIGNER FAIL enforcement disturbed entry/destination roles")
		quit(1)
		return
	# Room ids stay unique after any guarantee replacement re-indexing.
	var c_ids: Dictionary = {}
	for room in constrained:
		var cid: String = str(room["id"])
		if c_ids.has(cid):
			push_error("ROOM ASSIGNER FAIL duplicate room id after enforcement: %s" % cid)
			quit(1)
			return
		c_ids[cid] = true
	# Enforcement must stay deterministic per seed.
	var constrained_b: Array[Dictionary] = assigner.assign(constraint_template, bp, constraint_archetype)
	if str(constrained) != str(constrained_b):
		push_error("ROOM ASSIGNER FAIL enforcement broke per-seed determinism")
		quit(1)
		return

	print("ROOM ASSIGNER PASS rooms=%d first=airlock last=reactor keys=valid ids=unique deterministic=true guaranteed=enforced max_duplicates=enforced" % room_plan.size())
	quit(0)


func _collect_missing_footprint_roles() -> Array[String]:
	var missing: Array[String] = []
	_collect_template_role_pool_gaps("res://data/procgen/templates", missing)
	_collect_archetype_role_weight_gaps("res://data/procgen/archetypes", missing)
	return missing


func _collect_template_role_pool_gaps(dir_path: String, missing: Array[String]) -> void:
	for rel_path in _sorted_json_paths(dir_path):
		var doc: Dictionary = _load_json_dict(rel_path)
		var zones_raw: Variant = doc.get("zones", [])
		if not (zones_raw is Array):
			continue
		for zone_raw in zones_raw:
			if not (zone_raw is Dictionary):
				continue
			var zone: Dictionary = zone_raw
			var zone_id: String = str(zone.get("id", ""))
			var role_pool_raw: Variant = zone.get("role_pool", [])
			if not (role_pool_raw is Array):
				continue
			for role_raw in role_pool_raw:
				var role: String = str(role_raw)
				if not RoomAssignerScript.ROOM_FOOTPRINT_OPTIONS.has(role):
					missing.append("%s zone=%s role_pool=%s" % [rel_path, zone_id, role])


func _collect_archetype_role_weight_gaps(dir_path: String, missing: Array[String]) -> void:
	for rel_path in _sorted_json_paths(dir_path):
		var doc: Dictionary = _load_json_dict(rel_path)
		var role_weights: Dictionary = doc.get("role_weights", {})
		for role_variant in role_weights.keys():
			var role: String = str(role_variant)
			if not RoomAssignerScript.ROOM_FOOTPRINT_OPTIONS.has(role):
				missing.append("%s role_weights=%s" % [rel_path, role])


func _sorted_json_paths(dir_path: String) -> Array[String]:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_error("ROOM ASSIGNER FAIL cannot open directory %s" % dir_path)
		quit(1)
		return []
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			files.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	files.sort()
	return files


func _load_json_dict(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ROOM ASSIGNER FAIL cannot open %s" % path)
		quit(1)
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var parse_err: int = json.parse(text)
	if parse_err != OK:
		push_error("ROOM ASSIGNER FAIL invalid JSON %s line=%d error=%s" % [
			path,
			json.get_error_line(),
			json.get_error_message(),
		])
		quit(1)
		return {}
	if not (json.data is Dictionary):
		push_error("ROOM ASSIGNER FAIL JSON root is not an object: %s" % path)
		quit(1)
		return {}
	return json.data
