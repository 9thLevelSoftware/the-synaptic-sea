extends SceneTree

## Main-scene integration: the opening loop. The lifeboat boots with propulsion offline
## (nav_linkage broken); loot the guaranteed starting parts; channel a timed repair of
## nav_linkage; propulsion comes online; a previously-blocked jump now succeeds; the repair
## survives a disk save/load; the home objective loop is intact.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var _exit_code: int = 0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished: return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES: _fail("no PlayableGeneratedShip")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES: _fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	var mgr = playable.get_ship_systems_manager()
	# Opening: propulsion offline because nav_linkage was curated broken.
	if mgr.is_operational("propulsion"):
		_fail("lifeboat propulsion should be offline at boot"); return
	# Make power+navigation operational (the existing objective loop does this for the player).
	for sid in ["power", "navigation"]:
		for sub in mgr.get_system(sid).subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)
	var opening: bool = not mgr.is_operational("propulsion")  # still offline (nav_linkage broken)

	# A repair point for nav_linkage must exist on the lifeboat.
	var has_point: bool = false
	for rp in playable.repair_points:
		if rp.system_id == "propulsion" and rp.subcomponent_id == "nav_linkage":
			has_point = true
	if not has_point:
		_fail("no repair point for propulsion/nav_linkage on the lifeboat"); return

	# Loot the guaranteed starting parts (circuit_board needed for nav_linkage).
	if playable.loot_containers.is_empty():
		_fail("no starting loot containers (loot not lifted to lifeboat)"); return
	for lc in playable.loot_containers:
		playable.search_loot_container_for_validation(String(lc.container_id))
	if playable.inventory_state.get_quantity("circuit_board") < 1:
		_fail("starting loot did not guarantee a circuit_board"); return

	# Capture the circuit_board count before repair.
	var circuit_boards_before: int = playable.inventory_state.get_quantity("circuit_board")

	# Start the timed channel and prove it is NOT instant.
	if not playable.repair_subcomponent_for_validation("propulsion", "nav_linkage"):
		_fail("could not start nav_linkage repair channel"); return
	playable.advance_repair_channels_for_validation(0.01)  # tiny tick
	var mid_not_done: bool = not mgr.get_system("propulsion").get_subcomponent("nav_linkage").is_functional()
	# Drive the channel to completion deterministically.
	playable.advance_repair_channels_for_validation(999.0)
	var channeled: bool = mid_not_done and mgr.get_system("propulsion").get_subcomponent("nav_linkage").is_functional()
	if not channeled:
		_fail("timed channel did not complete the repair (mid_not_done=%s)" % str(mid_not_done)); return
	# One circuit_board consumed.
	if playable.inventory_state.get_quantity("circuit_board") != circuit_boards_before - 1:
		_fail("repair did not consume exactly one circuit_board"); return
	# Propulsion now operational; a jump that was blocked now succeeds.
	if not mgr.is_operational("propulsion"):
		_fail("propulsion not operational after repair"); return
	var world = playable.get_synapse_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range"); return
	var marker_id: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("travel still blocked after repairing propulsion"); return

	# Persistence: the repaired nav_linkage survives a disk save/load.
	if not playable.travel_home():
		_fail("travel_home failed"); return
	if not playable.request_save():
		_fail("save failed"); return
	if not playable.request_load():
		_fail("load failed"); return
	# Home loot-search state must persist (else the guaranteed starter parts re-loot →
	# duplication). All home containers were searched above; they must stay searched.
	if playable.loot_containers.is_empty():
		_fail("home loot containers missing after reload"); return
	for lc2 in playable.loot_containers:
		if not lc2.searched:
			_fail("home loot-search state did not persist across save/load (re-lootable starter parts)"); return
	var mgr2 = playable.get_ship_systems_manager()
	var persists: bool = mgr2.get_system("propulsion").get_subcomponent("nav_linkage").is_functional()
	if not persists:
		_fail("repaired nav_linkage did not persist across save/load"); return

	# Home loop intact: still on the lifeboat, away_from_start false.
	var home_intact: bool = not playable.away_from_start

	if not (opening and channeled and persists and home_intact):
		_fail("opening=%s channeled=%s persists=%s home_intact=%s" % [
			str(opening), str(channeled), str(persists), str(home_intact)]); return

	finished = true
	print("REPAIR LOOP PASS opening=true channeled=true persists=true home_intact=true")
	_teardown_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null: return found
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("REPAIR LOOP FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free(); main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
