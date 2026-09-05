extends SceneTree

## KitCatalog reachability proof: the live lifeboat's structural modules are driven
## by KitCatalog through StructuralPlacer, skinned by the run's deterministic biome.
## This is the difference from kit_catalog_smoke.gd (a pure-model test): here the LIVE
## coordinator builds the lifeboat (playable.lifeboat_ship.scene_root), and its actual
## instantiated module stems must match the kit selection for the run's resolved biome.
##
## Leak-free by design: it inspects the already-built lifeboat and compares kit data
## (no extra Node3D instantiation), so it is safe to gate in the regression bundle.
##
## Pass marker: MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=3 reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LifeBoatBuilderScript := preload("res://scripts/procgen/life_boat.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")
const TIMEOUT_FRAMES: int = 600
const BIOMES: Array[String] = ["abyssal_synaptic_sea", "breach_field", "dead_fleet"]

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var exercised: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if not playable.playable_started:
		return
	if exercised:
		return
	exercised = true
	_validate(playable)

func _validate(playable) -> void:
	var lifeboat = playable.lifeboat_ship
	if lifeboat == null or lifeboat.scene_root == null or not is_instance_valid(lifeboat.scene_root):
		_fail("no live lifeboat scene_root")
		return
	var biome: String = str(playable._resolve_current_loot_biome_id())
	if biome.is_empty():
		_fail("run biome resolved empty")
		return
	var live_result: Dictionary = _assert_compiled_lifeboat(lifeboat.scene_root, lifeboat.built_layout, biome)
	if not bool(live_result.get("ok", false)):
		return

	var baseline_occupancy: String = ""
	var baseline_portals: String = ""
	var fallback_biomes: Array[String] = []
	for candidate_biome in BIOMES:
		var layout: Dictionary = LifeBoatBuilderScript.build_layout(candidate_biome)
		var built: Node3D = LifeBoatBuilderScript.build(candidate_biome)
		if built == null:
			_fail("LifeBoatBuilder.build returned null for biome=%s" % candidate_biome)
			return
		var result: Dictionary = _assert_compiled_lifeboat(built, layout, candidate_biome)
		built.free()
		if not bool(result.get("ok", false)):
			return
		var plan: Dictionary = layout.get("structural_plan", {}) as Dictionary
		var occupancy: String = JSON.stringify(plan.get("occupancy", {}))
		var portals: String = JSON.stringify(layout.get("portals", []))
		if baseline_occupancy.is_empty():
			baseline_occupancy = occupancy
			baseline_portals = portals
		elif occupancy != baseline_occupancy or portals != baseline_portals:
			_fail("biome=%s changed compiled occupancy or portal positions" % candidate_biome)
			return
		if bool(result.get("fallback", false)):
			fallback_biomes.append(candidate_biome)

	finished = true
	print("MAIN PLAYABLE LIFEBOAT BIOME SKIN PASS biomes=%d live_match=true reachable=true" % BIOMES.size())
	print("MAIN PLAYABLE LIFEBOAT BIOME SKIN DETAILS fallback=%s fallback_biomes=%s" % [str(not fallback_biomes.is_empty()).to_lower(), ",".join(fallback_biomes)])
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)


func _assert_compiled_lifeboat(root: Node3D, layout: Dictionary, biome: String) -> Dictionary:
	var expected_kit: Dictionary = {
		"abyssal_synaptic_sea": "ship_structural_v0",
		"breach_field": "ship_structural_hazard",
		"dead_fleet": "ship_structural_industrial",
	}
	var kit_id: String = str(layout.get("kit_id", ""))
	if kit_id != str(expected_kit.get(biome, "")):
		_fail("biome=%s selected kit_id=%s" % [biome, kit_id])
		return {"ok": false}
	var rooms: Array = layout.get("rooms", []) as Array
	var plan: Dictionary = layout.get("structural_plan", {}) as Dictionary
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(plan, layout)
	if rooms.size() != LifeBoatBuilderScript.ROOMS.size() or not bool(verdict.get("ok", false)):
		_fail("biome=%s compiled lifeboat enclosure invalid: %s" % [biome, JSON.stringify(verdict.get("errors", []))])
		return {"ok": false}
	if (plan.get("floor_placements", []) as Array).size() != rooms.size() or (plan.get("ceiling_placements", []) as Array).size() != rooms.size():
		_fail("biome=%s changed compiled lifeboat occupancy" % biome)
		return {"ok": false}
	if not _room_transforms_match(root, rooms):
		_fail("biome=%s room cell transforms differ from compiled layout" % biome)
		return {"ok": false}
	var expected_records: Dictionary = {}
	for record_group in [plan.get("floor_placements", []), plan.get("placements", []), plan.get("ceiling_placements", [])]:
		for record_variant in (record_group as Array):
			if record_variant is Dictionary:
				var record: Dictionary = record_variant
				var placement_id: String = str(record.get("placement_id", ""))
				if placement_id.is_empty() or expected_records.has(placement_id):
					_fail("biome=%s duplicate or empty compiled placement id=%s" % [biome, placement_id])
					return {"ok": false}
				expected_records[placement_id] = record
	var resolved_map: Dictionary = LifeBoatBuilderScript._module_scene_map(kit_id)
	var fallback: bool = not _kit_declares_wrapper_map(kit_id)
	var default_map: Dictionary = LifeBoatBuilderScript._module_scene_map("ship_structural_v0")
	if fallback and JSON.stringify(resolved_map) != JSON.stringify(default_map):
		_fail("biome=%s declared wrapper fallback but resolved a non-v0 map" % biome)
		return {"ok": false}
	var collected: Dictionary = _live_records(root, root)
	var actual_records: Dictionary = collected.get("records", {}) as Dictionary
	var duplicates: Array = collected.get("duplicates", []) as Array
	if not duplicates.is_empty() or actual_records.size() != expected_records.size():
		_fail("biome=%s duplicate live placements=%s wrappers=%d compiled=%d" % [biome, JSON.stringify(duplicates), actual_records.size(), expected_records.size()])
		return {"ok": false}
	for placement_id in expected_records:
		if not actual_records.has(placement_id):
			_fail("biome=%s missing live wrapper placement=%s" % [biome, placement_id])
			return {"ok": false}
		var expected: Dictionary = expected_records[placement_id]
		var actual: Dictionary = actual_records[placement_id]
		var module_id: String = str(expected.get("module_id", ""))
		var expected_path: String = str(resolved_map.get(module_id, ""))
		if str(actual.get("module_id", "")) != module_id or str(actual.get("wrapper_path", "")) != expected_path \
				or str(actual.get("scene_file_path", "")) != expected_path:
			_fail("biome=%s compiled wrapper identity mismatch placement=%s" % [biome, placement_id])
			return {"ok": false}
		if not _vectors_match(actual.get("position", Vector3.ZERO), expected.get("position", Vector3.ZERO)) \
				or not _angles_match(float(actual.get("yaw", 0.0)), float(expected.get("yaw_degrees", 0.0))):
			_fail("biome=%s compiled wrapper transform mismatch placement=%s actual_pos=%s expected_pos=%s actual_yaw=%.3f expected_yaw=%.3f" % [biome, placement_id, str(actual.get("position", Vector3.ZERO)), str(expected.get("position", Vector3.ZERO)), float(actual.get("yaw", 0.0)), float(expected.get("yaw_degrees", 0.0))])
			return {"ok": false}
	return {"ok": true, "fallback": fallback}


func _kit_declares_wrapper_map(kit_id: String) -> bool:
	var path: String = "res://data/kits/%s.json" % kit_id
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return false
	var modules: Variant = (parsed as Dictionary).get("modules", [])
	if not (modules is Array) or (modules as Array).is_empty():
		return false
	for module_variant in modules as Array:
		if module_variant is Dictionary and not str((module_variant as Dictionary).get("module_id", "")).is_empty() \
				and not str((module_variant as Dictionary).get("godot_wrapper_scene", "")).is_empty():
			return true
	return false


func _room_transforms_match(root: Node3D, rooms: Array) -> bool:
	var expected: Dictionary = {}
	for room_variant in rooms:
		if room_variant is Dictionary:
			var room: Dictionary = room_variant
			expected[str(room.get("id", ""))] = room.get("world_origin", [])
	var structure: Node = root.get_child(0) if root.get_child_count() > 0 else null
	if structure == null:
		return false
	for room_node in structure.get_children():
		var room_id: String = str(room_node.name)
		if not expected.has(room_id):
			continue
		if not _vectors_match((room_node as Node3D).position, expected[room_id]):
			return false
		expected.erase(room_id)
	return expected.is_empty()


func _live_records(node: Node, lifeboat_root: Node3D) -> Dictionary:
	var records: Dictionary = {}
	var duplicates: Array = []
	_collect_live_records(node, lifeboat_root, records, duplicates)
	return {"records": records, "duplicates": duplicates}


func _collect_live_records(node: Node, lifeboat_root: Node3D, records: Dictionary, duplicates: Array) -> void:
	if node.has_meta("structural_placement_id"):
		var placement_id: String = str(node.get_meta("structural_placement_id"))
		if records.has(placement_id):
			duplicates.append(placement_id)
		else:
			var wrapper: Node3D = node as Node3D
			records[placement_id] = {
				"module_id": str(node.get_meta("structural_module_id", "")),
				"wrapper_path": str(node.get_meta("structural_wrapper_path", "")),
				"scene_file_path": str(node.scene_file_path),
				"position": _local_position_in_lifeboat(wrapper, lifeboat_root),
				"yaw": _local_yaw_in_lifeboat(wrapper, lifeboat_root),
			}
	for child in node.get_children():
		_collect_live_records(child, lifeboat_root, records, duplicates)


func _local_position_in_lifeboat(node: Node3D, lifeboat_root: Node3D) -> Vector3:
	var transform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null and parent != lifeboat_root:
		if parent is Node3D:
			transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return transform.origin


func _local_yaw_in_lifeboat(node: Node3D, lifeboat_root: Node3D) -> float:
	var transform: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != null and parent != lifeboat_root:
		if parent is Node3D:
			transform = (parent as Node3D).transform * transform
		parent = parent.get_parent()
	return rad_to_deg(transform.basis.get_euler().y)


func _angles_match(actual: float, expected: float) -> bool:
	return absf(wrapf(actual - expected, -180.0, 180.0)) <= 0.001


func _vectors_match(actual: Variant, expected: Variant) -> bool:
	return _as_vector3(actual).distance_to(_as_vector3(expected)) <= 0.001


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		var array: Array = value as Array
		return Vector3(float(array[0]), float(array[1]), float(array[2]))
	return Vector3.ZERO


func _find_playable(node: Node):
	if not is_instance_valid(node):
		return null
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE LIFEBOAT BIOME SKIN FAIL reason=%s" % reason)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
