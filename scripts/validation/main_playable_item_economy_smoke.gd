extends SceneTree

## Live reachability proof: BOTH fire-fighting items are obtained ONLY by crafting them
## through the real craft path (no add_item of the finished item), then used through the real
## interact dispatcher — proving the breach-seal and fire-extinguish loops are reachable in
## actual play (previously the items existed only via test injection).
## Marker: MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const HullIntegrityStateScript := preload("res://scripts/systems/hull_integrity_state.gd")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var bridge_login_requests: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	var inv = playable.inventory_state
	if inv == null or playable.crafting_state == null or playable.material_state == null:
		_fail("inventory/crafting models missing"); return
	playable.away_from_start = false
	if is_instance_valid(playable.threat_manager):
		playable.threat_manager.threats.clear()

	# --- 1) Craft hull_sealant via the REAL craft path (no add_item of hull_sealant) ---------
	inv.add_item("sealant", 2)
	inv.add_item("adhesive_paste", 1)
	playable.crafting_state.get_or_create_station("workbench").set_power(true)
	var sealant_before: int = inv.get_quantity("hull_sealant")
	if not playable.crafting_state.begin_craft("craft_hull_sealant", inv, playable.material_state, 5):
		_fail("begin_craft craft_hull_sealant failed (ingredients/recipe?)"); return
	playable.advance_crafting_for_validation(120.0)
	var crafted_sealant: bool = inv.get_quantity("hull_sealant") > sealant_before
	if not crafted_sealant:
		_fail("hull_sealant not produced by craft"); return

	# --- 2) Craft and use an extinguisher through the REAL dispatcher ------------------------
	inv.add_item("scrap_metal", 2)
	inv.add_item("power_cell", 1)
	inv.add_item("reactive_gel", 1)
	playable.crafting_state.get_or_create_station("fabricator").set_power(true)
	var ext_before: int = inv.get_quantity("fire_extinguisher")
	if not playable.crafting_state.begin_craft("craft_fire_extinguisher", inv, playable.material_state, 5):
		_fail("begin_craft craft_fire_extinguisher failed"); return
	playable.advance_crafting_for_validation(120.0)
	var crafted_ext: bool = inv.get_quantity("fire_extinguisher") > ext_before
	if not crafted_ext:
		_fail("fire_extinguisher not produced by craft"); return
	playable.set_manual_power_route_for_validation("stations", 0.0)
	var extinguish_count: int = 0
	while true:
		var fp = _first_burning_fire_point()
		if fp == null:
			break
		if extinguish_count >= 16:
			_fail("too many active fires while preparing breach reachability"); return
		playable.get_extinguisher_state().charge = playable.get_extinguisher_state().max_charge
		playable.teleport_player_to_fire_suppression_point_for_validation(fp)
		playable._on_player_interact_requested(playable.player)
		if not fp.channeling:
			_fail("interact did not start the extinguish channel (loop unreachable)"); return
		fp.advance_channel(10.0)
		extinguish_count += 1
	var extinguished: bool = extinguish_count > 0 and playable._active_fire_state().get_burning_compartments().is_empty()
	if not extinguished:
		_fail("crafted extinguisher did not clear the active fire set"); return

	# --- 3) Seal a breach through the REAL interact dispatcher (consumes the crafted sealant) -
	if not playable.force_hull_breach_for_validation("cargo", 0.7):
		_fail("could not force cargo breach"); return
	var sp = _seal_point_for("cargo")
	if sp == null:
		_fail("no cargo seal point for the forced breach"); return
	var bridge = _bridge_terminal_near(sp.global_position)
	if bridge == null:
		_fail("no co-located bridge terminal for priority proof"); return
	bridge_login_requests = 0
	bridge.login_requested.connect(func(_ship_id): bridge_login_requests += 1)
	if not bool((playable._active_hull().compartments["cargo"] as Dictionary).get("breach_open", false)):
		_fail("cargo seal point was not backed by an open breach"); return
	playable.teleport_player_to_breach_seal_point_for_validation(sp)
	playable._on_player_interact_requested(playable.player)
	if not sp.channeling:
		_fail("interact did not start the cargo seal channel (loop unreachable)"); return


	# Runtime web damage is a production hull mutator. It must project a newly-opened
	# compartment without replacing the in-progress cargo channel.
	var runtime_cid: String = _first_closed_compartment_except("cargo")
	if runtime_cid.is_empty():
		_fail("no closed compartment available for runtime breach projection"); return
	playable.hull_web_state.configure({
		"attached_to_web": true, "seed_coverage": 1.0, "growth_rate": 0.0,
		"damage_rate": 1.0, "recession_rate": 0.0, "contact_boost": 0.0,
	})
	playable._tick_present_ships(1.0)
	var runtime_sp = _seal_point_for(runtime_cid)
	if runtime_sp == null:
		_fail("runtime-induced breach did not create a seal point"); return
	playable._sync_breach_seal_points()
	if _seal_point_for("cargo") != sp or not sp.channeling:
		_fail("repeated breach sync replaced an active cargo channel"); return
	# Same compartment IDs on a different hull must not retain an old model binding.
	var foreign_hull = HullIntegrityStateScript.new()
	foreign_hull.configure({"compartments": [{
		"compartment_id": "cargo", "health": 0.2, "breach_open": true, "isolation_rating": 0.5,
	}]})
	sp.hull_state = foreign_hull
	playable._sync_breach_seal_points()
	var rebound = _seal_point_for("cargo")
	if rebound == null or rebound == sp or rebound.hull_state != playable._active_hull():
		_fail("same-id foreign hull binding was retained"); return
	sp = rebound
	playable.teleport_player_to_breach_seal_point_for_validation(sp)
	playable._on_player_interact_requested(playable.player)
	if not sp.channeling:
		_fail("replacement cargo point did not start via real dispatcher"); return
	sp.advance_channel(10.0)
	var sealed: bool = not bool((playable._active_hull().compartments["cargo"] as Dictionary).get("breach_open", false)) \
		and _seal_point_for("cargo") == null and inv.get_quantity("hull_sealant") < (sealant_before + 1)
	# Once the live breach is sealed, the same shared anchor reaches the terminal before
	# generic repair soft-denials, preserving its prior navigation priority.
	playable._on_player_interact_requested(playable.player)
	if bridge_login_requests != 1:
		_fail("bridge terminal was not reachable after sealing cargo breach"); return

	# The fire loop above intentionally runs first: an active fire correctly has emergency
	# precedence over a co-located breach interaction in the live dispatcher.


	if crafted_sealant and sealed and crafted_ext and extinguished:
		print("MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true")
		finished = true
		_cleanup_and_quit(0)
	else:
		_fail("crafted_sealant=%s sealed=%s crafted_ext=%s extinguished=%s" % [crafted_sealant, sealed, crafted_ext, extinguished])

func _bridge_terminal_near(world_position: Vector3):
	for candidate in playable.bridge_terminals:
		if is_instance_valid(candidate) and candidate.global_position.distance_to(world_position) <= candidate.interaction_radius:
			return candidate
	return null

func _first_burning_fire_point():
	var active_fire = playable._active_fire_state()
	if active_fire == null:
		return null
	for candidate in playable.get_fire_suppression_points_for_validation():
		if is_instance_valid(candidate) and active_fire.is_burning(candidate.compartment_id):
			return candidate
	return null

func _seal_point_for(compartment_id: String):
	for candidate in playable.get_breach_seal_points_for_validation():
		if is_instance_valid(candidate) and str(candidate.compartment_id) == compartment_id:
			return candidate
	return null

func _first_closed_compartment_except(excluded_compartment_id: String) -> String:
	var hull = playable._active_hull()
	if hull == null:
		return ""
	for raw_cid in hull.compartments.keys():
		var cid: String = str(raw_cid)
		if cid != excluded_compartment_id and not bool((hull.compartments[cid] as Dictionary).get("breach_open", false)):
			return cid
	return ""

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f = _find_playable(child)
		if is_instance_valid(f):
			return f
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE ITEM ECONOMY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
