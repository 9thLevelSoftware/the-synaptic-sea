extends SceneTree

# Authored hazard overlay + explicit loot contents (PR 13).
# Force the away branch, inject variant rooms PLUS mapped fire/breach zones,
# vented_compartments, a visual-only unmapped zone, and hazard_source=runtime.
# Asserts:
#   - seed still runs (variant engineering fire + bridge breach present)
#   - overlay ignites hydroponics, breaches cargo, vents cargo
#   - unmapped/no-cid zones do not ignite
#   - hazard_source is ignored (runtime stamp still overlays)
#   - fire-zone visuals pin hydroponics to the cid-tagged marker, not index 0
#   - loot specs copy contents; try_interact grants those stacks (no table roll)
# Marker: AUTHORED HAZARD OVERLAY PASS variant_fire=true authored_fire=true variant_breach=true authored_breach=true vented=true unmapped_visual=true hazard_source_ignored=true contents_copied=true contents_granted=true marker_matched=true

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

	# Overlay records. hazard_source is a tooling stamp — seed + overlay must
	# still run. Visual-only zone has no compartment_id (and an unmapped role).
	layout["hazard_source"] = "runtime"
	layout["fire_zones"] = [
		{
			"id": "hydro_authored_fire",
			"from_room": "airlock_01",
			"to_room": "airlock_01",
			"compartment_id": "hydroponics",
			"kind": "timed_fire",
			"hazard_source": "runtime",
		},
		{
			"id": "visual_only_fire",
			"from_room": "cargo_01",
			"to_room": "cargo_01",
			"kind": "timed_fire",
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
	if root != null and is_instance_valid(root):
		var declared_markers: Array[Vector3] = [SENTINEL_HYDRO, SENTINEL_VISUAL]
		root.fire_zone_markers = declared_markers
		root.fire_zone_specs = [
			{"zone_id": "hydro_authored_fire", "compartment_id": "hydroponics", "kind": "timed_fire"},
			{"zone_id": "visual_only_fire", "kind": "timed_fire"},
		]
		playable._build_fire_zones()
		var hydro_zone = playable.fire_zone_nodes.get("hydroponics", null)
		if hydro_zone is Node3D and (hydro_zone as Node3D).position.distance_to(SENTINEL_HYDRO) < 0.01:
			var eng_zone = playable.fire_zone_nodes.get("engineering", null)
			var eng_wrong: bool = eng_zone is Node3D \
				and (eng_zone as Node3D).position.distance_to(SENTINEL_HYDRO) < 0.01
			marker_matched = not eng_wrong

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

	if variant_fire and authored_fire and variant_breach and authored_breach and vented \
			and unmapped_visual and hazard_source_ignored and contents_copied \
			and contents_granted and marker_matched:
		print("AUTHORED HAZARD OVERLAY PASS variant_fire=true authored_fire=true variant_breach=true authored_breach=true vented=true unmapped_visual=true hazard_source_ignored=true contents_copied=true contents_granted=true marker_matched=true")
		_cleanup_and_quit(0)
	else:
		_fail("variant_fire=%s authored_fire=%s variant_breach=%s authored_breach=%s vented=%s unmapped_visual=%s hazard_source_ignored=%s contents_copied=%s contents_granted=%s marker_matched=%s burning=%s" % [
			str(variant_fire), str(authored_fire), str(variant_breach), str(authored_breach),
			str(vented), str(unmapped_visual), str(hazard_source_ignored), str(contents_copied),
			str(contents_granted), str(marker_matched), str(burning)])

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
