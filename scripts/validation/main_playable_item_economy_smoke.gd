extends SceneTree

## Live reachability proof: BOTH fire-fighting items are obtained ONLY by crafting them
## through the real craft path (no add_item of the finished item), then used through the real
## interact dispatcher — proving the breach-seal and fire-extinguish loops are reachable in
## actual play (previously the items existed only via test injection).
## Marker: MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

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

	# --- 2) Seal a breach through the REAL interact dispatcher (consumes the crafted sealant) -
	playable.force_hull_breach_for_validation("cargo", 0.7)
	var seal_points: Array = playable.get_breach_seal_points_for_validation()
	if seal_points.is_empty():
		_fail("no breach seal point for the forced breach"); return
	var sp = seal_points[0]
	playable.teleport_player_to_breach_seal_point_for_validation(sp)
	playable._on_player_interact_requested(playable.player)
	if not (sp.channeling or sp.sealed):
		_fail("interact did not start the seal channel (loop unreachable)"); return
	sp.advance_channel(10.0)
	var sealed: bool = playable.hull_integrity_state.get_breach_count() == 0 and inv.get_quantity("hull_sealant") < (sealant_before + 1)

	# --- 3) Craft fire_extinguisher via the REAL craft path (no add_item of the tool) --------
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

	# --- 4) Ignite a fire, then extinguish via the REAL dispatcher using the crafted tool ----
	# Keep suppression UNPOWERED so powered auto-suppression does not beat the manual path
	# (same isolation the M7-B fire-loop smoke uses).
	playable.set_manual_power_route_for_validation("stations", 0.0)
	playable.life_support_expanded_state.oxygen_percent = 100.0
	for sub in playable.ship_systems_manager.get_system("power").subcomponents:
		sub.health = 0.1
	var steps := 0
	while not playable.fire_suppression_state.is_burning("engineering") and steps < 600:
		playable.fire_suppression_state.tick(0.1, playable._build_fire_context())
		steps += 1
	if not playable.fire_suppression_state.is_burning("engineering"):
		_fail("engineering never ignited"); return
	playable._refresh_fire_zones()
	playable.get_extinguisher_state().charge = playable.get_extinguisher_state().max_charge
	var fps: Array = playable.get_fire_suppression_points_for_validation()
	var fp = null
	for p in fps:
		if str(p.compartment_id) == "engineering":
			fp = p
	if fp == null:
		_fail("no engineering fire suppression point"); return
	playable.teleport_player_to_fire_suppression_point_for_validation(fp)
	playable._on_player_interact_requested(playable.player)
	if not (fp.channeling or fp.extinguished):
		_fail("interact did not start the extinguish channel (loop unreachable)"); return
	fp.advance_channel(10.0)
	var extinguished: bool = not playable.fire_suppression_state.is_burning("engineering")

	if crafted_sealant and sealed and crafted_ext and extinguished:
		print("MAIN PLAYABLE ITEM ECONOMY PASS crafted_sealant=true sealed=true crafted_ext=true extinguished=true reachable=true")
		finished = true
		_cleanup_and_quit(0)
	else:
		_fail("crafted_sealant=%s sealed=%s crafted_ext=%s extinguished=%s" % [crafted_sealant, sealed, crafted_ext, extinguished])

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
