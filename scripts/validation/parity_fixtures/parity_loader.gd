extends SceneTree
## Captures GeneratedShipLoader parity fixtures for the Unity ShipSceneBuilder port: the `ship_loaded` summary,
## every public getter, and the runtime marker / portal / dressing / prop nodes the loader builds.
##
##   Godot_v4.7.1-stable_win64_console.exe --headless --path <this repo> \
##     --script res://scripts/validation/parity_fixtures/parity_loader.gd -- --out <unity repo>/fixtures/godot/loader
##
## Writes one `<case>.json` per (layout, is_away) plus `failures.json`. Augmented cases (dressing variants,
## placed props, atmosphere rooms, extra hazard zones) write their input documents under `inputs/` first and
## load them back from disk, so Godot and Unity consume byte-identical documents (unsorted keys preserved).

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const WriterScript := preload("res://scripts/validation/parity_fixtures/parity_writer.gd")

const KIT := "res://data/kits/ship_structural_v0.json"
const CASES: Array = [
	["coherent_ship_001", "res://data/procgen/golden/coherent_ship_001"],
	["coherent_ship_002", "res://data/procgen/golden/coherent_ship_002"],
	["coherent_ship_003", "res://data/procgen/golden/coherent_ship_003"],
	["seed_000017", "res://data/procgen/smoke/seed_000017"],
]
const DRESSING_VARIANTS: Array = [
	"burned_out", "breached", "flooded", "biomatter_crusted", "triage", "unstable",
	"collapsed", "refrigerated", "secure", "contaminated", "standard",
]

var _writer
var _world: Node3D
var _last_summary: Dictionary = {}
var _last_failure: String = ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	var out_dir: String = args[i + 1] if i >= 0 and i + 1 < args.size() else "user://parity_loader"
	_writer = WriterScript.new(out_dir)
	_world = Node3D.new()
	_world.name = "ParityWorld"
	get_root().add_child(_world)

	var ok := true
	for entry in CASES:
		var case_name: String = entry[0]
		var base: String = entry[1]
		for is_away in [false, true]:
			ok = _capture_case(
				"%s_%s" % [case_name, "away" if is_away else "home"],
				"%s/layout.json" % base, "%s/gameplay_slice.json" % base, is_away) and ok
	ok = _capture_augmented() and ok
	ok = _capture_failures() and ok
	if not _writer.errors.is_empty():
		for e in _writer.errors:
			push_error(str(e))
		ok = false
	print("PARITY LOADER %s files=%d out=%s" % ["PASS" if ok else "FAIL", _writer.files.size(), out_dir])
	quit(0 if ok else 1)


func _new_loader() -> Node3D:
	var loader: Node3D = LoaderScript.new()
	loader.name = "GeneratedShipLoader"
	_world.add_child(loader)
	_last_summary = {}
	_last_failure = ""
	loader.ship_loaded.connect(func(summary: Dictionary) -> void: _last_summary = summary)
	loader.load_failed.connect(func(reason: String) -> void: _last_failure = reason)
	return loader


func _free_loader(loader: Node3D) -> void:
	_world.remove_child(loader)
	loader.free()


func _relative(path: String) -> String:
	var root: String = ProjectSettings.globalize_path("res://")
	if path.begins_with(root):
		return path.substr(root.length())
	return path


func _write(rel: String, value: Variant) -> bool:
	var text: String = JSON.stringify(_writer.canonical(value), "\t", true, true)
	return _writer.write_text(rel, text)


func _capture_case(case_name: String, layout: String, slice: String, is_away: bool) -> bool:
	var loader := _new_loader()
	var loaded: bool = loader.load_from_paths(layout, KIT, slice, is_away)
	var record := _record(loader, case_name, loaded, is_away)
	record["inputs"] = {"layout": _relative(ProjectSettings.globalize_path(layout)), "kit": _relative(ProjectSettings.globalize_path(KIT)), "gameplay_slice": _relative(ProjectSettings.globalize_path(slice))}
	_free_loader(loader)
	if not loaded:
		push_error("parity_loader: %s failed to load: %s" % [case_name, _last_failure])
	return _write("%s.json" % case_name, record) and loaded


func _record(loader: Node3D, case_name: String, loaded: bool, is_away: bool) -> Dictionary:
	var summary := _last_summary.duplicate(true)
	for key in ["layout_path", "kit_path", "gameplay_slice_path"]:
		if summary.has(key):
			summary[key] = _relative(str(summary[key]))
	var rooms := {}
	for room_variant in (loader.layout_doc.get("rooms", []) as Array):
		var rid: String = str((room_variant as Dictionary).get("id", ""))
		var center: Vector3 = loader.get_room_center(rid)
		rooms[rid] = {
			"center": center if center != Vector3.INF else null,
			"role": loader.get_room_role(rid),
			"deck": loader.get_room_deck(rid),
		}
	var start: Transform3D = loader.get_start_transform()
	var record := {
		"case": case_name,
		"is_away": is_away,
		"loaded": loaded,
		"load_failed_reason": _last_failure,
		"summary": summary,
		"has_loaded_ship": loader.has_loaded_ship(),
		"start_transform_origin": start.origin,
		"goal_position": loader.get_goal_position(),
		"objective_specs": loader.get_objective_specs_copy(),
		"loot_container_specs": loader.get_loot_container_specs_copy(),
		"placed_prop_specs": loader.get_placed_prop_specs_copy(),
		"placed_prop_errors": loader.get_placed_prop_errors(),
		"authored_portal_specs": loader.get_authored_portal_specs_copy(),
		"rooms": rooms,
		"unknown_room": {"role": loader.get_room_role("no_such_room"), "deck": loader.get_room_deck("no_such_room")},
		"critical_path": loader.get_critical_path(),
		"room_links": loader.get_room_links(),
		"encounter_markers": loader.get_encounter_markers(),
		"blocked_links": loader.get_blocked_links(),
		"landmark_specs": loader.get_landmark_specs(),
		"breach_zone_markers": loader.get_breach_zone_markers(),
		"breach_zone_specs": loader.get_breach_zone_specs(),
		"fire_zone_markers": loader.get_fire_zone_markers(),
		"fire_zone_specs": loader.get_fire_zone_specs(),
		"arc_zone_markers": loader.get_arc_zone_markers(),
		"arc_zone_specs": loader.get_arc_zone_specs(),
		"radiation_zone_markers": loader.get_radiation_zone_markers(),
		"radiation_zone_specs": loader.get_radiation_zone_specs(),
		"radiation_zone_segments": loader.get_radiation_zone_segments(),
		"authored_atmosphere_specs": loader.authored_atmosphere_specs.duplicate(true),
		"room_variant_descriptors": loader.get_room_variant_descriptors(),
		"count_collision_shapes": loader.count_collision_shapes(),
		"probes": _probes(loader),
		"nodes": _nodes(loader),
	}
	return record


func _probes(loader: Node3D) -> Array:
	var points: Array = []
	for marker in loader.get_radiation_zone_markers():
		points.append(marker)
		points.append(marker + Vector3(0.9, 0.3, 0.0))
		points.append(marker + Vector3(0.0, 0.0, 1.6))
	for spec_variant in loader.authored_atmosphere_specs:
		var p: Vector3 = (spec_variant as Dictionary).get("position", Vector3.ZERO)
		points.append(p + Vector3(0.0, 1.0, 0.0))
		points.append(p + Vector3(1.9, 2.4, -1.9))
		points.append(p + Vector3(0.0, -0.1, 0.0))
	points.append(Vector3(1000.0, 0.0, 1000.0))
	var out: Array = []
	for point in points:
		out.append({
			"point": point,
			"radiation_zone_at": loader.get_radiation_zone_at(point),
			"authored_atmosphere_at": loader.get_authored_atmosphere_at(point),
			"drain_multiplier": loader.get_authored_atmosphere_drain_multiplier_at(point),
		})
	return out


func _xform(node: Node3D) -> Dictionary:
	var t: Transform3D = node.transform
	return {"name": str(node.name), "position": t.origin, "basis": [t.basis.x, t.basis.y, t.basis.z]}


func _nodes(loader: Node3D) -> Dictionary:
	var out := {}
	var landmarks: Array = []
	for n in loader.get_landmark_nodes():
		landmarks.append(_xform(n))
	out["landmarks"] = landmarks
	var blocked: Array = []
	for n in loader.get_blocked_route_nodes():
		blocked.append(_xform(n))
	out["blocked_routes"] = blocked
	var vertical: Array = []
	for n in loader.get_visible_vertical_transition_nodes():
		vertical.append(_xform(n))
	out["vertical_transitions"] = vertical

	var props: Array = []
	for n in loader.get_placed_prop_nodes():
		var info := _xform(n)
		info["placed_prop_id"] = str(n.get_meta("placed_prop_id", ""))
		info["gameplay_prop_id"] = str(n.get_meta("gameplay_prop_id", ""))
		info["authored_position"] = n.get_meta("authored_position", Vector3.ZERO)
		var child_names: Array = []
		for c in n.get_children():
			child_names.append(str(c.name))
		info["children"] = child_names
		props.append(info)
	out["placed_props"] = props

	var portals: Array = []
	for n in loader.get_authored_portal_nodes():
		var info := _xform(n)
		info["portal_id"] = n.portal_id
		info["portal_kind"] = n.portal_kind
		info["is_open"] = n.is_open
		info["is_unlocked"] = n.is_unlocked
		info["is_unsafe"] = n.is_unsafe
		info["is_exterior"] = n.is_exterior
		info["required_flag"] = n.required_flag()
		info["structural_blocker"] = str(n._structural_blocker.name) if is_instance_valid(n._structural_blocker) else ""
		info["structural_blocker_visible"] = n.is_structural_blocker_visible()
		info["structural_blocker_enabled_shapes"] = n.get_structural_blocker_collision_enabled_count()
		info["visual_visible"] = n._visual.visible if is_instance_valid(n._visual) else false
		var shape: CollisionShape3D = n.get_blocker_collision_shape()
		info["blocker_disabled"] = shape.disabled if shape != null else null
		portals.append(info)
	out["authored_portals"] = portals

	var volumes: Array = []
	for v in loader.objective_volumes:
		var info := _xform(v)
		info["objective_id"] = v.objective_id
		info["sequence"] = v.sequence
		info["objective_type"] = v.objective_type
		info["room_id"] = v.room_id
		volumes.append(info)
	out["objective_volumes"] = volumes

	var triggers: Array = []
	var dressing: Array = []
	var module_keys: Array = []
	var integrity: Dictionary = {}
	var vertical_links: Array = []
	if loader.structural_root != null:
		for child in loader.structural_root.get_children():
			var cname: String = str(child.name)
			if child.has_meta("module_key"):
				var key: String = str(child.get_meta("module_key"))
				module_keys.append(key)
				var state: String = str(child.get_meta("integrity_state", "intact"))
				if state != "intact":
					integrity[key] = state
			elif child is Area3D and (cname.begins_with("RadiationZone_") or cname.begins_with("AuthoredAtmosphere_")):
				var info := _xform(child)
				for c in child.get_children():
					if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
						info["size"] = ((c as CollisionShape3D).shape as BoxShape3D).size
				if child.has_meta("atmosphere"):
					info["atmosphere"] = child.get_meta("atmosphere")
				triggers.append(info)
			elif child is NavigationLink3D:
				var link := child as NavigationLink3D
				vertical_links.append({"name": cname, "start": link.start_position, "end": link.end_position})
			elif cname == "DressingVisuals":
				for d in child.get_children():
					dressing.append(_dressing_info(d))
	out["trigger_volumes"] = triggers
	out["dressing"] = dressing
	out["module_keys"] = module_keys
	out["integrity_states"] = integrity
	out["vertical_links"] = vertical_links
	var atmosphere := {}
	for child in loader.get_children():
		if child is DirectionalLight3D:
			atmosphere["key_light_energy"] = (child as DirectionalLight3D).light_energy
		elif child is OmniLight3D and str(child.name) == "SliceAtmosphereEmergencyAccent":
			atmosphere["accent_energy"] = (child as OmniLight3D).light_energy
		elif child is WorldEnvironment:
			var env: Environment = (child as WorldEnvironment).environment
			atmosphere["fog_enabled"] = env.fog_enabled
			atmosphere["fog_density"] = env.fog_density
	out["atmosphere"] = atmosphere
	return out


func _dressing_info(d: Node) -> Dictionary:
	var info := _xform(d as Node3D)
	info["class"] = d.get_class()
	for key in ["dressing", "prop_density", "fog_density", "tint", "dressing_kind", "slot_kind", "slot_index", "slot_cell", "collision_policy"]:
		if d.has_meta(key):
			info[key] = d.get_meta(key)
	if d is OmniLight3D:
		var light := d as OmniLight3D
		info["light_energy"] = light.light_energy
		info["omni_range"] = light.omni_range
		info["light_color"] = [light.light_color.r, light.light_color.g, light.light_color.b, light.light_color.a]
	elif d is MeshInstance3D:
		var mi := d as MeshInstance3D
		if mi.mesh is SphereMesh:
			info["sphere_radius"] = (mi.mesh as SphereMesh).radius
			info["sphere_height"] = (mi.mesh as SphereMesh).height
		var mat := mi.material_override as StandardMaterial3D
		if mat != null:
			info["albedo"] = [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, mat.albedo_color.a]
	else:
		for c in d.get_children():
			if c is MeshInstance3D:
				info["mesh_child"] = _xform(c as Node3D)
				info["mesh_class"] = (c as MeshInstance3D).mesh.get_class()
	return info


# --- augmented documents -------------------------------------------------------------

func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary


func _write_input(rel: String, doc: Dictionary) -> String:
	# sort_keys=false keeps the source key order (dictionary iteration order is load-bearing).
	_writer.write_text(rel, JSON.stringify(doc, "\t", false, true))
	return _writer.abs_path(rel)


func _floor_cells(layout: Dictionary, room_id: String) -> Array:
	var out: Array = []
	for f in (layout["structural_plan"]["floor_placements"] as Array):
		var fd: Dictionary = f
		if str(fd.get("room_id", "")) == room_id:
			var parts: PackedStringArray = str(fd.get("cell_key", "")).split("|")
			out.append([int(parts[1]), int(parts[2]), int(parts[0])])
	return out


func _augment_seed17() -> Array:
	var layout := _read("res://data/procgen/smoke/seed_000017/layout.json")
	var gameplay := _read("res://data/procgen/smoke/seed_000017/gameplay_slice.json")
	layout["seed_value"] = 17017
	layout["biome_id"] = "breach_field"
	var rooms: Array = layout["rooms"]
	for index in range(rooms.size()):
		(rooms[index] as Dictionary)["variant"] = DRESSING_VARIANTS[index % DRESSING_VARIANTS.size()]
	# Authored atmosphere rooms (oxygen / temperature / vented / radiation keys).
	(rooms[1] as Dictionary)["oxygen_bp"] = 4000
	(rooms[1] as Dictionary)["temperature_c"] = -12.5
	(rooms[2] as Dictionary)["vented"] = true
	(rooms[4] as Dictionary)["radiation_bp"] = 300
	(rooms[4] as Dictionary)["atmosphere_bp"] = 9000
	# Hazard zones: one resolved through cells, one through the room-center fallback.
	var link0: Dictionary = (layout["room_links"] as Array)[0]
	var link1: Dictionary = (layout["room_links"] as Array)[1]
	layout["radiation_zones"] = [
		{"id": "rad_cells", "from_room": link0["from_room"], "to_room": link0["to_room"], "from_cell": link0["from_cell"], "to_cell": link0["to_cell"], "severity": 2},
		{"id": "rad_rooms", "from_room": link1["from_room"], "to_room": link1["to_room"]},
	]
	layout["breach_zones"] = [{"id": "breach_cells", "from_room": link1["from_room"], "to_room": link1["to_room"], "from_cell": link1["from_cell"], "to_cell": link1["to_cell"]}]
	layout["fire_zones"] = [{"zone_id": "fire_explicit", "id": "fire_alias", "from_room": link0["from_room"], "to_room": link0["to_room"]}]
	layout["arc_zones"] = [{"id": "arc_one", "from_room": link1["from_room"], "to_room": link1["to_room"], "from_cell": [99, 99, 0], "to_cell": link1["to_cell"]}]
	layout["landmarks"] = [{"id": "lm_a", "position": [8.0, 0.0, 20.0]}, {"id": "lm_bad", "position": [1, "x", 2]}]
	layout["blocked_links"] = [{"id": "bl_a", "from_room": link0["from_room"], "to_room": link0["to_room"], "from_cell": link0["from_cell"], "to_cell": link0["to_cell"]}]
	var plan: Dictionary = layout["structural_plan"]
	var first_edge: Dictionary = (plan["placements"] as Array)[0]
	var first_floor: Dictionary = (plan["floor_placements"] as Array)[2]
	layout["module_damage"] = [
		{"module_key": "edge/%s" % str(first_edge.get("edge_key", "")), "state": "breached"},
		{"placement_id": str(first_floor.get("placement_id", "")), "state": "damaged"},
	]
	# Placed props: catalog primitive, imported dressing binding, unknown id, and the rotation fallbacks.
	var room_a: String = str((rooms[0] as Dictionary)["id"])
	var room_b: String = str((rooms[4] as Dictionary)["id"])
	var room_c: String = str((rooms[6] as Dictionary)["id"])
	var cells_a := _floor_cells(layout, room_a)
	var cells_b := _floor_cells(layout, room_b)
	var cells_c := _floor_cells(layout, room_c)
	gameplay["placed_props"] = [
		{"id": "pp_crate", "visual_id": "loot_crate", "room_id": room_a, "cell": cells_a[0], "quarter_turn": 1},
		{"id": "pp_dressing", "prop_id": "generic_crate", "room_id": room_b, "cell": cells_b[0], "yaw_degrees": 180.0},
		{"id": "pp_unknown", "visual_id": "no_such_prop", "room_id": room_b, "cell": cells_b[1] if cells_b.size() > 1 else cells_b[0]},
		{"id": "pp_rotation", "asset_id": "workbench", "room_id": room_c, "approach_cell": cells_c[0], "rotation": 7},
		{"id": "pp_cylinder", "proto": " extinguisher_station ", "room_id": room_c, "cell": cells_c[cells_c.size() - 1], "yaw_degrees": -90.0, "extra": {"note": "kept"}},
		{"id": "pp_no_cell", "visual_id": "loot_crate", "room_id": room_c},
	]
	# Loot container with an authored slot and explicit contents.
	var loot: Array = gameplay.get("loot_containers", [])
	if not loot.is_empty():
		(loot[0] as Dictionary)["slot_kind"] = "wall"
		(loot[0] as Dictionary)["slot_index"] = 0
		(loot[0] as Dictionary)["contents"] = [{"item_id": "scrap_metal", "count": 3}]
	var layout_path := _write_input("inputs/seed_000017_augmented.layout.json", layout)
	var gameplay_path := _write_input("inputs/seed_000017_augmented.gameplay_slice.json", gameplay)
	return [layout_path, gameplay_path]


func _capture_augmented() -> bool:
	var paths := _augment_seed17()
	var ok := true
	for is_away in [false, true]:
		var case_name := "seed_000017_augmented_%s" % ("away" if is_away else "home")
		var loader := _new_loader()
		var loaded: bool = loader.load_from_paths(paths[0], KIT, paths[1], is_away)
		var record := _record(loader, case_name, loaded, is_away)
		record["inputs"] = {"layout": "fixtures/godot/loader/inputs/seed_000017_augmented.layout.json", "kit": "data/kits/ship_structural_v0.json", "gameplay_slice": "fixtures/godot/loader/inputs/seed_000017_augmented.gameplay_slice.json"}
		for key in ["layout_path", "gameplay_slice_path"]:
			var summary: Dictionary = record["summary"]
			if summary.has(key):
				summary[key] = str(record["inputs"]["layout" if key == "layout_path" else "gameplay_slice"])
		_free_loader(loader)
		if not loaded:
			push_error("parity_loader: %s failed: %s" % [case_name, _last_failure])
		ok = _write("%s.json" % case_name, record) and loaded and ok
	return ok


func _capture_failures() -> bool:
	var layout := _read("res://data/procgen/golden/coherent_ship_001/layout.json")
	var gameplay := _read("res://data/procgen/golden/coherent_ship_001/gameplay_slice.json")
	var kit := _read(KIT)
	var cases: Array = []

	var no_rooms := layout.duplicate(true)
	no_rooms["rooms"] = {}
	cases.append(["layout_missing_rooms", no_rooms, gameplay, kit])

	var no_prototype := layout.duplicate(true)
	no_prototype["prototype"] = []
	cases.append(["layout_missing_prototype", no_prototype, gameplay, kit])

	var no_objectives := gameplay.duplicate(true)
	no_objectives["objectives"] = []
	cases.append(["no_objectives", layout, no_objectives, kit])

	var bad_sequence := gameplay.duplicate(true)
	((bad_sequence["objectives"] as Array)[1] as Dictionary)["sequence"] = 7
	cases.append(["objective_sequence_mismatch", layout, bad_sequence, kit])

	var bad_start := gameplay.duplicate(true)
	bad_start["start_room"] = "no_such_room"
	cases.append(["unknown_start_room", layout, bad_start, kit])

	var no_goal := gameplay.duplicate(true)
	no_goal["goal_room"] = ""
	var no_goal_layout := layout.duplicate(true)
	(no_goal_layout["prototype"] as Dictionary).erase("goal_room")
	cases.append(["missing_goal_room", no_goal_layout, no_goal, kit])

	var empty_kit := kit.duplicate(true)
	empty_kit["modules"] = []
	cases.append(["kit_without_modules", layout, gameplay, empty_kit])

	var unknown_module := layout.duplicate(true)
	((unknown_module["structural_plan"]["floor_placements"] as Array)[3] as Dictionary)["module_id"] = "no_such_module"
	cases.append(["unknown_structural_module", unknown_module, gameplay, kit])

	var records: Array = []
	for c in cases:
		var loader := _new_loader()
		var loaded: bool = loader.load_from_documents(c[1], c[3], c[2], false, {})
		records.append({
			"case": c[0],
			"loaded": loaded,
			"reason": _last_failure,
			"summary_emitted": not _last_summary.is_empty(),
			"child_count": loader.get_child_count(),
		})
		_free_loader(loader)
	return _write("failures.json", {"cases": records})
