extends SceneTree

## Main-scene smoke: board a derelict, search a loot container, items enter the bag
## and weight rises; leave + revisit keeps it looted and the bag intact; a disk
## save/load aboard preserves the bag; returning home leaves the home loop + tools intact.

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
	if finished:
		return
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
	# Make this ship travel-capable, then board a derelict.
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = playable.get_ship_systems_manager().get_system(sid)
		if sys != null:
			for sub in sys.subcomponents:
				playable.get_ship_systems_manager().force_repair(sid, sub.subcomponent_id)
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range"); return
	var marker_id: String = String(in_range[0].marker_id)
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("travel to derelict failed"); return

	if playable.loot_containers.is_empty():
		_fail("no loot containers built on board"); return
	var weight_before: float = playable.inventory_state.get_total_weight()
	var first_container = playable.loot_containers[0]
	var cid: String = String(first_container.container_id)
	playable.player.teleport_to(first_container.global_position)
	playable.player.request_interact()
	if not first_container.searched:
		_fail("normal interact did not search loot container"); return
	if playable.inventory_state.get_total_weight() <= weight_before:
		_fail("searching granted no weight"); return
	if not playable.loot_containers[0].searched:
		_fail("container not marked searched"); return
	var carried_weight: float = playable.inventory_state.get_total_weight()
	var items_snapshot: Dictionary = playable.inventory_state.items.duplicate(true)

	# Leave to home and revisit: container stays looted, bag unchanged.
	if not playable.travel_home(): _fail("travel_home failed"); return
	if not bool(playable.travel_to_marker_id(marker_id).get("success", false)):
		_fail("revisit travel failed"); return
	var still_looted: bool = false
	for lc in playable.loot_containers:
		if String(lc.container_id) == cid and lc.searched:
			still_looted = true
	if not still_looted:
		_fail("container respawned on revisit"); return
	if playable.inventory_state.items != items_snapshot:
		_fail("bag changed across revisit"); return

	# Disk save/load while aboard preserves the bag.
	if not playable.request_save(): _fail("save failed"); return
	if not playable.request_load(): _fail("load failed"); return
	if abs(playable.inventory_state.get_total_weight() - carried_weight) > 0.0001:
		_fail("bag weight not preserved across disk save/load"); return

	# Home loop + tool effect intact.
	if not playable.travel_home(): _fail("second travel_home failed"); return
	if playable.away_from_start:
		_fail("away_from_start still true at home"); return

	finished = true
	print("DERELICT LOOT PASS searched=true carried=true persists=true home_intact=true")
	_teardown_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("DERELICT LOOT FAIL reason=%s" % reason)
	_teardown_and_quit(1)

func _teardown_and_quit(code: int) -> void:
	_exit_code = code
	if main_node != null and is_instance_valid(main_node):
		main_node.free(); main_node = null
	call_deferred("_do_quit")

func _do_quit() -> void:
	quit(_exit_code)
