extends SceneTree

# Authored hazard overlay + explicit loot contents (PR 13).
# Force the away branch, inject variant rooms PLUS mapped fire/breach zones,
# vented_compartments, a room-link fire, an invalid unmapped zone, and
# hazard_source=runtime.
# Asserts:
#   - seed still runs (variant engineering fire + bridge breach present)
#   - overlay ignites hydroponics, breaches cargo, vents cargo
#   - link-shaped zones resolve through room roles; invalid explicit roles do not ignite
#   - hazard_source is ignored (runtime stamp still overlays)
#   - fire-zone visuals pin hydroponics to the room-link marker, not index 0
#   - mapped hydroponics marker is reserved when that fire is absent
#   - loot specs copy contents; try_interact grants those stacks (no table roll)
#   - explicit empty contents does not fall through to a table roll
#   - authored unique items carry unique_id and cannot be granted twice
# Marker: AUTHORED HAZARD OVERLAY PASS variant_fire=true authored_fire=true variant_breach=true authored_breach=true vented=true unmapped_visual=true hazard_source_ignored=true contents_copied=true contents_granted=true marker_matched=true contents_empty=true unique_gated=true mapped_reserved=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const LootContainerScript := preload("res://scripts/tools/loot_container.gd")
const TIMEOUT_FRAMES: int = 300
const SENTINEL_HYDRO: Vector3 = Vector3(77.0, 4.0, -19.0)
const SENTINEL_VISUAL: Vector3 = Vector3(-55.0, 4.0, 31.0)

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _validate() -> void:
	finished = true
	playable.away_from_start = true
	if playable.current_ship == null:
		_fail("no current_ship on away branch")
		return

	var layout: Dictionary = playable.current_ship.built_layout
	if layout.is_empty():
		layout = {}
	var rooms: Variant = layout.get("rooms", [])
	if not (rooms is Array):
		rooms = []
		layout["rooms"] = rooms
	if not _layout_has_role(rooms as Array, "engineering"):
		(rooms as Array).append({"id": "eng_test", "room_role": "engineering", "variant": "burned_out"})
	else:
		_set_room_variant_by_role(rooms as Array, "engineering", "burned_out")
	if not _layout_has_role(rooms as Array, "bridge"):
		(rooms as Array).append({"id": "brg_test", "room_role": "bridge", "variant": "breached"})
	else:
		_set_room_variant_by_role(rooms as Array, "bridge", "breached")

	(rooms as Array).append({"id": "hydro_link_test", "room_role": "hydroponics", "variant": "standard"})

	# Overlay records. hazard_source is a tooling stamp — seed + overlay must
	# still run. The hydroponics fire uses the normal room-link shape with no
	# compartment_id; the explicitly unmapped airlock record remains visual-only.
	layout["hazard_source"] = "runtime"
	layout["fire_zones"] = [
		{
			"id": "hydro_authored_fire",
			"from_room": "airlock_01",
			"to_room": "hydro_link_test",
			"kind": "timed_fire",
			"hazard_source": "runtime",
		},
		{
			"id": "unmapped_role_fire",
			"compartment_id": "airlock",
			"kind": "timed_fire",
		},
	]
	layout["breach_zones"] = [
		{
			"id": "cargo_authored_breach",
			"compartment_id": "cargo",
			"kind": "hull_breach",
		},
	]
	layout["vented_compartments"] = ["cargo"]
	playable.current_ship.built_layout = layout

	var hull_config: Dictionary = _load_json_dict("res://data/ship_systems/hull_compartments.json")
	var hull = playable.current_ship.get_hull()
	hull.configure(hull_config)
	# Default cargo is pre-breached; close it so the authored overlay is observable.
	if hull.compartments.has("cargo"):
		var cargo_row: Dictionary = hull.compartments["cargo"]
		cargo_row["breach_open"] = false
		cargo_row["health"] = 1.0
		hull.compartments["cargo"] = cargo_row
	var fs = playable.current_ship.get_fire()
	# Seed path configures from tuning (and folds vents). Do not configure again
	# after ignite — reset flags and let _seed_derelict_fire do it.
	playable.current_ship.fire_seeded = false
	playable.current_ship.breach_seeded = false
	playable._seed_derelict_breaches()
	playable._seed_derelict_fire()

	var burning: Array = fs.get_burning_compartments() if fs != null else []
	var variant_fire: bool = "engineering" in burning
	var authored_fire: bool = "hydroponics" in burning
	var cargo_burning: bool = "cargo" in burning
	var airlock_burning: bool = "airlock" in burning
	var unmapped_visual: bool = not cargo_burning and not airlock_burning
	var variant_breach: bool = hull.compartments.has("bridge") \
		and bool((hull.compartments["bridge"] as Dictionary).get("breach_open", false))
	var authored_breach: bool = hull.compartments.has("cargo") \
		and bool((hull.compartments["cargo"] as Dictionary).get("breach_open", false))
	var vented: bool = fs != null and fs.is_vented("cargo")
	# Overlay still applied with hazard_source=runtime (not gated on "authored").
	var hazard_source_ignored: bool = authored_fire and authored_breach and vented

	var root: Node = playable.current_ship.scene_root
	var marker_matched: bool = false
	var mapped_reserved: bool = false
	if root != null and is_instance_valid(root):
		var declared_markers: Array[Vector3] = [SENTINEL_HYDRO, SENTINEL_VISUAL]
		root.fire_zone_markers = declared_markers
		root.fire_zone_specs = [
			{"zone_id": "hydro_authored_fire", "from_room": "airlock_01", "to_room": "hydro_link_test", "kind": "timed_fire"},
			{"zone_id": "unmapped_role_fire", "compartment_id": "airlock", "kind": "timed_fire"},
		]
		playable._build_fire_zones()
		var hydro_zone = playable.fire_zone_nodes.get("hydroponics", null)
		if hydro_zone is Node3D and (hydro_zone as Node3D).position.distance_to(SENTINEL_HYDRO) < 0.01:
			var eng_zone = playable.fire_zone_nodes.get("engineering", null)
			var eng_wrong: bool = eng_zone is Node3D \
				and (eng_zone as Node3D).position.distance_to(SENTINEL_HYDRO) < 0.01
			marker_matched = not eng_wrong
		if fs != null:
			fs.extinguish("hydroponics")
		playable._build_fire_zones()
		var eng_after = playable.fire_zone_nodes.get("engineering", null)
		var hydro_gone: bool = not playable.fire_zone_nodes.has("hydroponics")
		var eng_not_hydro: bool = eng_after is Node3D \
			and (eng_after as Node3D).position.distance_to(SENTINEL_HYDRO) >= 0.01
		mapped_reserved = hydro_gone and eng_not_hydro

	var loader := GeneratedShipLoaderScript.new()
	loader.layout_doc = {
		"rooms": [{"id": "airlock_01", "deck": 0}],
		"structural_plan": {
			"floor_placements": [{
				"cell_key": "0|0|0",
				"room_id": "airlock_01",
				"position": [0.0, 0.0, 0.0],
			}],
		},
	}
	var copied_specs: Array = loader._build_loot_container_specs(loader.layout_doc, {
		"loot_containers": [{
			"id": "authored_crate",
			"kind": "generic_crate",
			"room_id": "airlock_01",
			"approach_cell": [0, 0, 0],
			"loot_table": "generic_crate",
			"contents": [{"item_id": "data_core", "qty": 3}],
		}],
	})
	loader.queue_free()
	var contents_copied: bool = false
	if not copied_specs.is_empty() and copied_specs[0] is Dictionary:
		var copied: Dictionary = copied_specs[0]
		var raw: Variant = copied.get("contents", [])
		contents_copied = raw is Array and (raw as Array).size() == 1 \
			and str(((raw as Array)[0] as Dictionary).get("item_id", "")) == "data_core" \
			and int(((raw as Array)[0] as Dictionary).get("qty", 0)) == 3

	var before_core: int = int(playable.inventory_state.get_quantity("data_core"))
	var lc = LootContainerScript.new()
	lc.configure(
		"authored_crate",
		"generic_crate",
		"overlay-smoke:authored_crate",
		playable.inventory_state,
		playable._loot_tables,
		Vector3.ZERO,
		1.8,
		{"contents": [{"item_id": "data_core", "qty": 3}]}
	)
	lc.set_validation_player_in_range(playable.player)
	var searched: bool = lc.try_interact(playable.player)
	var after_core: int = int(playable.inventory_state.get_quantity("data_core"))
	var contents_granted: bool = searched and lc.searched and after_core == before_core + 3
	lc.queue_free()

	var empty_ctx: Dictionary = playable._build_loot_context({"kind": "generic_crate", "contents": []})
	var empty_key: bool = empty_ctx.has("contents")
	var table_ids: Array = ["scrap_metal", "wiring_spool", "power_cell", "frayed_cable_coil", "cracked_pressure_valve", "contaminated_water"]
	var before_table: Dictionary = {}
	for table_id in table_ids:
		before_table[str(table_id)] = int(playable.inventory_state.get_quantity(str(table_id)))
	var empty_lc = LootContainerScript.new()
	empty_lc.configure(
		"empty_authored_crate",
		"generic_crate",
		"overlay-smoke:empty_authored_crate",
		playable.inventory_state,
		playable._loot_tables,
		Vector3.ZERO,
		1.8,
		empty_ctx
	)
	var empty_capture: Dictionary = {"granted": [{"sentinel": true}]}
	empty_lc.container_searched.connect(func(_cid, granted):
		empty_capture["granted"] = granted
	)
	empty_lc.set_validation_player_in_range(playable.player)
	empty_lc.try_interact(playable.player)
	var empty_granted: Array = empty_capture.get("granted", [])
	var table_unchanged: bool = true
	for table_id in table_ids:
		if int(playable.inventory_state.get_quantity(str(table_id))) != int(before_table[str(table_id)]):
			table_unchanged = false
			break
	var contents_empty: bool = empty_key and empty_lc.searched and empty_granted.is_empty() and table_unchanged
	empty_lc.queue_free()

	var unique_ctx: Dictionary = playable._build_loot_context({
		"kind": "generic_crate",
		"contents": [{"item_id": "captains_black_box", "qty": 1}],
	})
	var unique_lc = LootContainerScript.new()
	unique_lc.configure(
		"unique_crate_a",
		"generic_crate",
		"overlay-smoke:unique_crate_a",
		playable.inventory_state,
		playable._loot_tables,
		Vector3.ZERO,
		1.8,
		unique_ctx
	)
	var unique_capture: Dictionary = {"granted": []}
	unique_lc.container_searched.connect(func(_cid, granted):
		unique_capture["granted"] = granted
	)
	unique_lc.set_validation_player_in_range(playable.player)
	unique_lc.try_interact(playable.player)
	var unique_grants: Array = unique_capture.get("granted", [])
	playable._on_loot_container_searched("unique_crate_a", unique_grants, null)
	var unique_meta: bool = not unique_grants.is_empty() \
		and str((unique_grants[0] as Dictionary).get("unique_id", "")) == "captains_black_box" \
		and playable.unique_item_state != null \
		and playable.unique_item_state.is_claimed("captains_black_box")
	playable.inventory_state.remove_item("captains_black_box", 1)
	var unique_lc2 = LootContainerScript.new()
	unique_lc2.configure(
		"unique_crate_b",
		"generic_crate",
		"overlay-smoke:unique_crate_b",
		playable.inventory_state,
		playable._loot_tables,
		Vector3.ZERO,
		1.8,
		unique_ctx
	)
	unique_lc2.set_validation_player_in_range(playable.player)
	unique_lc2.try_interact(playable.player)
	var unique_gated: bool = unique_meta \
		and int(playable.inventory_state.get_quantity("captains_black_box")) == 0 \
		and unique_lc2.searched
	unique_lc.queue_free()
	unique_lc2.queue_free()

	if variant_fire and authored_fire and variant_breach and authored_breach and vented \
			and unmapped_visual and hazard_source_ignored and contents_copied \
			and contents_granted and marker_matched and contents_empty \
			and unique_gated and mapped_reserved:
		print("AUTHORED HAZARD OVERLAY PASS variant_fire=true authored_fire=true variant_breach=true authored_breach=true vented=true unmapped_visual=true hazard_source_ignored=true contents_copied=true contents_granted=true marker_matched=true contents_empty=true unique_gated=true mapped_reserved=true")
		_cleanup_and_quit(0)
	else:
		_fail("variant_fire=%s authored_fire=%s variant_breach=%s authored_breach=%s vented=%s unmapped_visual=%s hazard_source_ignored=%s contents_copied=%s contents_granted=%s marker_matched=%s contents_empty=%s unique_gated=%s mapped_reserved=%s burning=%s" % [
			str(variant_fire), str(authored_fire), str(variant_breach), str(authored_breach),
			str(vented), str(unmapped_visual), str(hazard_source_ignored), str(contents_copied),
			str(contents_granted), str(marker_matched), str(contents_empty), str(unique_gated),
			str(mapped_reserved), str(burning)])

func _layout_has_role(rooms: Array, role: String) -> bool:
	for room in rooms:
		if room is Dictionary and str((room as Dictionary).get("room_role", (room as Dictionary).get("role", ""))) == role:
			return true
	return false

func _set_room_variant_by_role(rooms: Array, role: String, variant: String) -> void:
	for room in rooms:
		if room is Dictionary and str((room as Dictionary).get("room_role", (room as Dictionary).get("role", ""))) == role:
			(room as Dictionary)["variant"] = variant
			return

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(msg: String) -> void:
	push_error("AUTHORED HAZARD OVERLAY FAIL " + msg)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null:
		main_node.queue_free()
	quit(code)

func _load_json_dict(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
