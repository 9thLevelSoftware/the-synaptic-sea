extends SceneTree

## Domain 3 flagship: full food production loop on the home ship
## (water_recycler: contaminated -> purified) + (hydroponics: plant -> harvest into
## inventory and spoilage-registered) AND spoilage age advancing on the away (derelict)
## branch via real _process.
##
## Marker:
##   MAIN PLAYABLE FOOD PRODUCTION PASS harvested=true recycled=true away_ticks=<n> spoiled_away=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable  ## PlayableGeneratedShip — untyped so smoke loads without strict class dep
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
	## Phase 0: power up the home ship's production band.
	var home_mgr = playable.get_ship_systems_manager()
	for sub: String in ["reactor_core", "power_distribution", "battery_cells"]:
		home_mgr.force_repair("power", sub)

	## Phase 1: water recycler — contaminated -> purified.
	## Advance via advance_production_for_validation (NOT _process) to avoid the
	## home-branch slice_complete gate that would stall after any player death.
	playable.inventory_state.add_item("contaminated_water", 4)
	if not playable.produce_at_station_for_validation("water_recycler", false):
		_fail("water_recycler load failed — station not built or contaminated_water not consumed")
		return
	for i: int in range(120):
		playable.advance_production_for_validation(1.0)
	var purified_before: int = playable.inventory_state.get_quantity("purified_water")
	var collect_ok: bool = playable.produce_at_station_for_validation("water_recycler", true)
	if not collect_ok:
		_fail("water_recycler collect returned false — model not in output_ready state after 120 advance ticks")
		return
	var recycled: bool = playable.inventory_state.get_quantity("purified_water") > purified_before

	## Phase 2: hydroponics — plant -> harvest.
	## Seed purified_water for irrigation cost before planting.
	playable.inventory_state.add_item("purified_water", 5)
	if not playable.produce_at_station_for_validation("hydroponics", false):
		_fail("hydroponics plant failed — station not built or water not consumed")
		return
	for i: int in range(200):
		playable.advance_production_for_validation(1.0)
	if not playable.produce_at_station_for_validation("hydroponics", true):
		_fail("hydroponics harvest failed — model not in HARVESTABLE state after 200 advance ticks")
		return
	var harvested: bool = playable.inventory_state.get_quantity("hydroponic_greens") >= 1
	if not harvested:
		_fail("hydroponic_greens quantity is 0 after successful harvest interact")
		return
	## Harvested food must be registered with spoilage_state so eat-time penalties apply.
	if playable.spoilage_state == null or not playable.spoilage_state.has_food("hydroponic_greens"):
		_fail("hydroponic_greens not registered in spoilage_state after harvest")
		return

	## Phase 3: away-branch spoilage advance.
	## The away branch does NOT gate on slice_complete, so _process is safe here.
	## We record elapsed_seconds before, run 30 simulated seconds on the derelict
	## path, then assert the age increased — proving _tick_food_runtime is wired
	## into the away branch of _process.
	var spoil_before: float = _spoil_age("hydroponic_greens")
	## Top off vitals to prevent player death in the short away window.
	if playable.vitals_state != null:
		playable.vitals_state.hunger = playable.vitals_state.max_hunger
		playable.vitals_state.thirst = playable.vitals_state.max_thirst
		playable.vitals_state.health = playable.vitals_state.max_health
	playable.away_from_start = true
	var n: int = 0
	for i: int in range(30):
		playable._process(1.0)
		n += 1
	var spoil_after: float = _spoil_age("hydroponic_greens")
	var spoiled_away: bool = spoil_after > spoil_before + 1.0

	if recycled and harvested and spoiled_away:
		finished = true
		print("MAIN PLAYABLE FOOD PRODUCTION PASS harvested=true recycled=true away_ticks=%d spoiled_away=true" % n)
		_cleanup_and_quit(0)
	else:
		_fail("recycled=%s harvested=%s spoiled_away=%s purified_delta=%d spoil_before=%.3f spoil_after=%.3f" % [
			str(recycled), str(harvested), str(spoiled_away),
			playable.inventory_state.get_quantity("purified_water") - purified_before,
			spoil_before, spoil_after
		])

## Read per-item age from spoilage_state.get_summary().
## Real summary shape: { "foods": { item_id: { "elapsed_seconds": float, ... } } }
func _spoil_age(item_id: String) -> float:
	var s = playable.spoilage_state
	if s == null:
		return 0.0
	var summary: Dictionary = s.get_summary()
	var foods: Variant = summary.get("foods", {})
	if typeof(foods) == TYPE_DICTIONARY:
		var foods_dict: Dictionary = foods as Dictionary
		if foods_dict.has(item_id):
			var entry: Variant = foods_dict[item_id]
			if typeof(entry) == TYPE_DICTIONARY:
				return float((entry as Dictionary).get("elapsed_seconds", 0.0))
	return 0.0

## Untyped recursive search so this smoke loads without a strict class dependency.
## Matches the pattern used by production_station_wiring_smoke.gd (Task 4).
func _find_playable(node: Node):
	for child: Node in node.get_children():
		if child.get("playable_started") != null and child.has_method("produce_at_station_for_validation"):
			return child
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE FOOD PRODUCTION FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
