extends Node3D
class_name DerelictBuilderPreview

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const FireStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
const ArcStateScript := preload("res://scripts/systems/electrical_arc_state.gd")
const RadiationStateScript := preload("res://scripts/systems/radiation_state.gd")
const OxygenStateScript := preload("res://scripts/systems/oxygen_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const LootContainerScript := preload("res://scripts/tools/loot_container.gd")

const RESULT_MARKER := "DERELICT_BUILDER_PREVIEW_RESULT"
const REQUIRED_CHECKS: Array[String] = [
	"structural_collision", "navigation", "objectives", "props", "loot", "vertical_links",
	"fire", "arc", "electrical", "radiation", "breach", "atmosphere", "portal_interaction",
]

var loader
var manifest_path := ""
var result_path := ""
var _ship_summary: Dictionary = {}
var _source_hash := ""
var _kit_id := ""


func _ready() -> void:
	manifest_path = _argument("--manifest")
	if manifest_path.is_empty():
		manifest_path = OS.get_environment("DERELICT_BUILDER_MANIFEST")
	if manifest_path.is_empty():
		_finish(false, ["missing --manifest argument"])
		return
	manifest_path = _absolute_path(manifest_path, ProjectSettings.globalize_path("res://"))
	result_path = manifest_path.get_base_dir().path_join("preview_result.json")
	var manifest := _json_file(manifest_path)
	if manifest.is_empty():
		_finish(false, ["manifest is missing or invalid JSON"])
		return
	result_path = _absolute_path(str(manifest.get("result_path", result_path)), manifest_path.get_base_dir())
	_source_hash = str(manifest.get("source_hash", ""))
	_kit_id = str(manifest.get("kit_id", ""))
	var errors := _validate_manifest(manifest)
	if not errors.is_empty():
		_finish(false, errors)
		return
	var base := manifest_path.get_base_dir()
	var layout_path := _absolute_path(str(manifest.get("layout_path", "")), base)
	var gameplay_path := _absolute_path(str(manifest.get("gameplay_slice_path", "")), base)
	var kit_path := _absolute_path(str(manifest.get("kit_path", "")), base)
	loader = LoaderScript.new()
	loader.name = "GeneratedShipLoader"
	loader.ship_loaded.connect(func(summary: Dictionary) -> void: _ship_summary = summary.duplicate(true))
	add_child(loader)
	if not loader.load_from_paths(layout_path, kit_path, gameplay_path, true):
		_finish(false, ["GeneratedShipLoader rejected the bundle"])
		return
	# Navigation maps synchronize asynchronously after regions and links enter
	# the tree. Do not let an unsynchronized map return empty/default points that
	# could make a path check pass accidentally.
	if not await _wait_for_navigation_sync():
		_finish(false, ["navigation map did not synchronize"])
		return
	var acceptance := _exercise_runtime(_json_file(layout_path), _json_file(gameplay_path))
	_finish(bool(acceptance.get("ok", false)), acceptance.get("errors", []), acceptance.get("checks", {}))


func _validate_manifest(manifest: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if str(manifest.get("document_kind", "")) != "derelict_builder_bundle":
		errors.append("manifest document_kind must be derelict_builder_bundle")
	if str(manifest.get("validation_result", "")) != "passed":
		errors.append("bundle does not record a passed validation")
	var base := manifest_path.get_base_dir()
	for key in ["source_path", "layout_path", "gameplay_slice_path", "kit_path"]:
		var resolved := _absolute_path(str(manifest.get(key, "")), base)
		if resolved.is_empty() or not FileAccess.file_exists(resolved):
			errors.append("missing %s: %s" % [key, resolved])
	if errors.is_empty():
		_validate_hash(errors, _absolute_path(str(manifest.get("source_path", "")), base), str(manifest.get("source_hash", "")), "source")
		_validate_hash(errors, _absolute_path(str(manifest.get("layout_path", "")), base), str(manifest.get("layout_hash", "")), "layout")
		_validate_hash(errors, _absolute_path(str(manifest.get("gameplay_slice_path", "")), base), str(manifest.get("gameplay_slice_hash", "")), "gameplay slice")
		var layout := _json_file(_absolute_path(str(manifest.get("layout_path", "")), base))
		var gameplay := _json_file(_absolute_path(str(manifest.get("gameplay_slice_path", "")), base))
		if str(layout.get("schema_version", "")) != str(manifest.get("layout_schema", "")):
			errors.append("layout schema does not match manifest")
		if str(gameplay.get("schema_version", "")) != str(manifest.get("gameplay_schema", "")):
			errors.append("gameplay schema does not match manifest")
		if str(layout.get("kit_id", "")) != str(manifest.get("kit_id", "")):
			errors.append("layout kit_id does not match manifest")
	return errors


func _validate_hash(errors: Array[String], path: String, expected: String, label: String) -> void:
	if expected.is_empty():
		errors.append("manifest has no %s hash" % label)
		return
	var content := FileAccess.get_file_as_string(path)
	if _sha256(content) != expected:
		errors.append("%s hash does not match manifest" % label)


func _exercise_runtime(layout: Dictionary, gameplay: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var checks := {
		"structural_collision": loader.count_collision_shapes() > 0,
		"navigation": _navigation_path_exists(loader.get_goal_position()),
		"objectives": _exercise_objectives(),
		"loot": _exercise_loot(gameplay),
		"props": loader.get_placed_prop_specs_copy().size() == _array(gameplay.get("placed_props", [])).size(),
		"vertical_links": int(_ship_summary.get("vertical_link_count", -1)) == _array(layout.get("vertical_connections", [])).size(),
	}
	var fire_specs: Array = loader.get_fire_zone_specs()
	var fire_state = FireStateScript.new()
	if not fire_specs.is_empty():
		var fire_room := str(fire_specs[0].get("compartment_id", fire_specs[0].get("from_room", "authored_fire")))
		fire_state.configure({"compartments": [fire_room]})
		checks["fire"] = fire_state.ignite(fire_room, 1.0) and fire_state.is_burning(fire_room)
	else:
		checks["fire"] = true

	var arc_specs: Array = loader.get_arc_zone_specs()
	var arc_state = ArcStateScript.new()
	arc_state.configure({"zone_ids": _zone_ids(arc_specs), "arcing_first": true})
	var arc_ready: bool = arc_specs.is_empty() or arc_state.is_passability_blocked()
	checks["arc"] = arc_ready
	# Retain the legacy key for existing automation while exposing the authored
	# hazard name used by the builder and the human-readable success marker.
	checks["electrical"] = arc_ready

	var radiation_specs: Array = loader.get_radiation_zone_specs()
	var radiation_state = RadiationStateScript.new()
	radiation_state.configure({"in_radiation_zone": not radiation_specs.is_empty()})
	radiation_state.tick(1.0)
	checks["radiation"] = radiation_specs.is_empty() or radiation_state.radiation > 0.0

	var breach_specs: Array = loader.get_breach_zone_specs()
	var oxygen_state = OxygenStateScript.new()
	oxygen_state.configure({"zone_ids": _zone_ids(breach_specs), "drain_rate": 6.0})
	if not breach_specs.is_empty():
		oxygen_state.tick(1.0, {"player_in_breach_zone": true})
	checks["breach"] = breach_specs.is_empty() or (
		breach_specs.size() == loader.get_breach_zone_markers().size()
		and oxygen_state.oxygen < oxygen_state.max_oxygen
	)

	checks["atmosphere"] = _exercise_atmosphere(layout)

	checks["portal_interaction"] = _exercise_portals(layout)
	for key in REQUIRED_CHECKS:
		if not bool(checks[key]):
			errors.append("runtime acceptance failed: %s" % key)
	return {"ok": errors.is_empty(), "errors": errors, "checks": checks}


func _navigation_path_exists(local_target: Vector3) -> bool:
	if loader.structural_root == null:
		return false
	var region := loader.structural_root.find_child("GameplayNavigationRegion", true, false) as NavigationRegion3D
	if region == null:
		return false
	var navigation_map: RID = region.get_navigation_map()
	if not navigation_map.is_valid() or NavigationServer3D.map_get_iteration_id(navigation_map) <= 0:
		return false
	var start_world: Vector3 = loader.to_global(loader.get_start_transform().origin)
	var target_world: Vector3 = loader.to_global(local_target)
	var start_on_map := NavigationServer3D.map_get_closest_point(navigation_map, start_world)
	var target_on_map := NavigationServer3D.map_get_closest_point(navigation_map, target_world)
	var path := NavigationServer3D.map_get_path(navigation_map, start_on_map, target_on_map, true)
	if path.size() >= 2:
		return true
	# A one-room document may intentionally use the same start and goal. Only
	# that authored coincidence may accept a zero-length navigation path.
	return start_world.distance_to(target_world) <= 0.05 and start_on_map.distance_to(target_on_map) <= 0.05


func _wait_for_navigation_sync() -> bool:
	if loader.structural_root == null:
		return false
	var region := loader.structural_root.find_child("GameplayNavigationRegion", true, false) as NavigationRegion3D
	if region == null:
		return false
	var navigation_map: RID = region.get_navigation_map()
	var vertices := region.navigation_mesh.get_vertices() if region.navigation_mesh != null else PackedVector3Array()
	if not navigation_map.is_valid() or vertices.is_empty():
		return false
	# The preview runs and exits much faster than a normal gameplay scene. Give
	# the active map one forced warm-up, then only poll for real server progress.
	var probe_world: Vector3 = region.to_global(vertices[0])
	await get_tree().physics_frame
	NavigationServer3D.map_force_update(navigation_map)
	for _frame in range(120):
		if NavigationServer3D.map_get_iteration_id(navigation_map) > 0 \
				and NavigationServer3D.map_get_closest_point(navigation_map, probe_world).distance_to(probe_world) <= 1.0:
			return true
		await get_tree().physics_frame
	return false


func _exercise_objectives() -> bool:
	var specs: Array = loader.get_objective_specs_copy()
	var volumes: Array = loader.objective_volumes
	if specs.is_empty() or volumes.size() != specs.size():
		return false
	for volume_variant in volumes:
		if not (volume_variant is GameplayObjectiveVolume):
			return false
		var volume := volume_variant as GameplayObjectiveVolume
		if not _navigation_path_exists(loader.to_local(volume.global_position)):
			return false
		volume.complete()
		if not volume.completed:
			return false
	return true


func _exercise_loot(gameplay: Dictionary) -> bool:
	var specs: Array = loader.get_loot_container_specs_copy()
	if specs.is_empty() or specs.size() != _array(gameplay.get("loot_containers", [])).size():
		return false
	for spec_variant in specs:
		if not (spec_variant is Dictionary):
			return false
		var spec: Dictionary = spec_variant
		var expected_contents: Array = LootContainerScript.normalized_contents(spec) if spec.has("contents") else []
		var inventory = InventoryStateScript.new()
		var container = LootContainerScript.new()
		var player := Node3D.new()
		add_child(container)
		add_child(player)
		container.configure(
			str(spec.get("id", "preview_loot")), str(spec.get("loot_table", "")),
			"derelict_builder_preview", inventory, {}, Vector3.ZERO, 1.8, spec
		)
		container.set_validation_player_in_range(player)
		var interacted: bool = container.try_interact(player)
		var accepted: bool = interacted and container.searched
		for stack_variant in expected_contents:
			if not (stack_variant is Dictionary):
				accepted = false
				continue
			var stack: Dictionary = stack_variant
			var item_id := str(stack.get("item_id", ""))
			var quantity := int(stack.get("qty", stack.get("quantity", 0)))
			if item_id.is_empty() or quantity <= 0 or inventory.get_quantity(item_id) != quantity:
				accepted = false
		container.queue_free()
		player.queue_free()
		if not accepted:
			return false
	return true


func _exercise_portals(layout: Dictionary) -> bool:
	var nodes: Array[Area3D] = loader.get_authored_portal_nodes()
	if nodes.size() != _structural_portal_count(layout):
		return false
	for portal in nodes:
		if portal == null or not portal.has_method("try_interact"):
			return false
		portal.set_validation_player_in_range(true)
		var shape: CollisionShape3D = portal.get_blocker_collision_shape()
		if shape == null:
			return false
		match str(portal.portal_kind):
			"LOCKED":
				var denied: Dictionary = portal.try_interact({})
				var flag := str(portal.required_flag())
				var flags := {}
				flags[flag] = true
				var opened: Dictionary = portal.try_interact(flags)
				if str(denied.get("reason", "")) != "locked" or not bool(opened.get("open", false)) or not shape.disabled:
					return false
			"BREACH":
				if not shape.disabled or not bool(portal.try_interact({}).get("unsafe", false)):
					return false
			_:
				var before := shape.disabled
				var opened: Dictionary = portal.try_interact({})
				if bool(opened.get("ok", false)) and not portal.is_exterior:
					if shape.disabled == before:
						return false
	return true


func _exercise_atmosphere(layout: Dictionary) -> bool:
	var authored := false
	for room_variant in _array(layout.get("rooms", [])):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		if not _room_has_authored_atmosphere(room):
			continue
		authored = true
		var center: Vector3 = loader.get_room_center(str(room.get("id", "")))
		var atmosphere: Dictionary = loader.get_authored_atmosphere_at(center)
		if atmosphere.is_empty():
			return false
		var multiplier: float = float(loader.get_authored_atmosphere_drain_multiplier_at(center))
		var oxygen = OxygenStateScript.new()
		oxygen.configure({"max_oxygen": 100.0, "drain_rate": 8.0})
		var before: float = oxygen.oxygen
		oxygen.tick(1.0, {
			"field_atmosphere": true,
			"field_atmosphere_multiplier": multiplier,
		})
		var should_drain := bool(atmosphere.get("depressurized", false)) or bool(atmosphere.get("vented", false)) or int(atmosphere.get("oxygen_bp", 10000)) < 10000
		if should_drain != (oxygen.oxygen < before):
			return false
	return true if authored else not _has_authored_atmosphere(layout)


func _room_has_authored_atmosphere(room: Dictionary) -> bool:
	return room.has("atmosphere_bp") or room.has("oxygen_bp") or room.has("depressurized") or room.has("vented") or room.has("radiation_bp") or room.has("temperature_c")


func _structural_portal_count(layout: Dictionary) -> int:
	var plan: Variant = layout.get("structural_plan", {})
	if not (plan is Dictionary):
		return _array(layout.get("portals", layout.get("connections", []))).size()
	var edges: Variant = (plan as Dictionary).get("edges", {})
	if not (edges is Dictionary):
		return _array(layout.get("portals", layout.get("connections", []))).size()
	var count := 0
	for raw in (edges as Dictionary).values():
		if raw is Dictionary and bool((raw as Dictionary).get("portal", false)):
			count += 1
	return count


func _finish(ok: bool, errors: Array, checks: Dictionary = {}) -> void:
	var result := {
		"ok": ok,
		"manifest_path": manifest_path,
		"source_hash": _source_hash,
		"kit_id": _kit_id,
		"errors": errors,
		"checks": checks,
		"completed_at_utc": Time.get_datetime_string_from_system(true, true),
	}
	if not result_path.is_empty():
		var file := FileAccess.open(result_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "\t") + "\n")
			file.close()
	print("%s %s" % [RESULT_MARKER, JSON.stringify(result)])
	if ok:
		var marker_parts: Array[String] = []
		for key in REQUIRED_CHECKS:
			marker_parts.append("%s=%s" % [key, "true" if bool(checks.get(key, false)) else "false"])
		print("DERELICT BUILDER PREVIEW PASS %s" % " ".join(marker_parts))
	if not ok:
		push_error("DERELICT BUILDER PREVIEW FAIL %s" % "; ".join(errors))
	if DisplayServer.get_name() == "headless" or not ok:
		get_tree().quit(0 if ok else 1)


func _argument(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return ""


func _absolute_path(path: String, base: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	return base.path_join(path).simplify_path()


func _json_file(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _sha256(content: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(content.to_utf8_buffer())
	return context.finish().hex_encode()


func _array(value: Variant) -> Array:
	return value if value is Array else []


func _zone_ids(specs: Array) -> Array[String]:
	var ids: Array[String] = []
	for index in range(specs.size()):
		if specs[index] is Dictionary:
			ids.append(str(specs[index].get("zone_id", specs[index].get("id", "zone_%d" % index))))
	return ids


func _has_authored_atmosphere(layout: Dictionary) -> bool:
	for room_variant in _array(layout.get("rooms", [])):
		if room_variant is Dictionary and _room_has_authored_atmosphere(room_variant as Dictionary):
			return true
	return false
