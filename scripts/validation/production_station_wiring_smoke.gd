extends SceneTree

## Domain 3 Task 4: the coordinator builds real hydroponics + water_recycler production
## stations on the home ship and drives them through the REAL interact seam, depositing
## produce into the player inventory and registering it for spoilage.
## Marker: PRODUCTION WIRING PASS hydro=true recycler=true spoilage_registered=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished: return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()

func _validate() -> void:
	# Give the player the inputs and ensure the sustenance power band is up.
	var home_mgr = playable.get_ship_systems_manager()
	for sub in ["reactor_core", "power_distribution", "battery_cells"]:
		home_mgr.force_repair("power", sub)
	playable.inventory_state.add_item("contaminated_water", 4)
	playable.inventory_state.add_item("purified_water", 5)

	# --- Recycler: load -> advance -> collect ---
	# Use advance_production_for_validation (not _process) so slice_complete=true after
	# the inevitable player-death mid-loop does not block ticking via the _process guard.
	if not playable.produce_at_station_for_validation("water_recycler", false):
		_fail("recycler load failed"); return
	for i in range(120):
		playable.advance_production_for_validation(1.0)
	if not playable.produce_at_station_for_validation("water_recycler", true):
		_fail("recycler collect failed"); return
	var recycler_ok: bool = playable.inventory_state.get_quantity("purified_water") >= 5

	# --- Hydroponics: plant -> advance -> harvest ---
	if not playable.produce_at_station_for_validation("hydroponics", false):
		_fail("hydroponics plant failed"); return
	for i in range(200):
		playable.advance_production_for_validation(1.0)
	if not playable.produce_at_station_for_validation("hydroponics", true):
		_fail("hydroponics harvest failed"); return
	var hydro_ok: bool = playable.inventory_state.get_quantity("hydroponic_greens") >= 1
	var spoilage_ok: bool = playable.spoilage_state != null and playable.spoilage_state.has_food("hydroponic_greens")

	if recycler_ok and hydro_ok and spoilage_ok:
		finished = true
		print("PRODUCTION WIRING PASS hydro=true recycler=true spoilage_registered=true")
		_cleanup_and_quit(0)
	else:
		_fail("recycler_ok=%s hydro_ok=%s spoilage_ok=%s" % [str(recycler_ok), str(hydro_ok), str(spoilage_ok)])

func _find_playable(node):
	for child in node.get_children():
		if child.get("playable_started") != null and child.has_method("produce_at_station_for_validation"):
			return child
		var f = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished: return
	finished = true
	push_error("PRODUCTION WIRING FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
