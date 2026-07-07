extends SceneTree

## Domain 3 Task 5: spoilage AND in-progress production advance on the AWAY (derelict)
## branch. Drives away_from_start = true and asserts a planted crop's growth advances and
## a tracked food's spoilage age advances while boarded.
## Marker: FOOD AWAY TICK PASS away_ticks=<n> crop_grew=true spoiled_away=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

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
	finished = true  # prevent re-entry across frames

	# Plant a crop directly on the model (testing the TICK path, not station interact).
	var crop: Dictionary = {
		"crop_id": "hydroponic_greens",
		"produce_item_id": "hydroponic_greens",
		"produce_quantity": 3,
		"growth_seconds": 600.0,
		"water_cost": 0.0,
		"power_cost": 0.0,
		"required_skill_level": 0
	}
	playable.hydroponics_state.plant(crop, 0, 99.0, 99.0)

	# Register a food for spoilage so it appears in spoilage_state.
	# _register_food_for_spoilage is idempotent; call with item in inventory.
	playable.inventory_state.add_item("cooked_meal", 1)
	playable._register_food_for_spoilage("cooked_meal")

	var growth_before: float = playable.hydroponics_state.progress_seconds
	var spoil_before: float = _spoil_age("cooked_meal")

	# Boost vitals before the away loop to prevent the player from starving
	# in the ~30-tick window (hunger_drain=0.5/s, thirst_drain=0.8/s — safe at 30s
	# with default max=100, but this guard future-proofs against any new hazard teeth
	# feeding in via _tick_survival_attrition on the away branch).
	if playable.vitals_state != null:
		playable.vitals_state.hunger = playable.vitals_state.max_hunger
		playable.vitals_state.thirst = playable.vitals_state.max_thirst
		playable.vitals_state.health = playable.vitals_state.max_health

	# Force the AWAY branch; drive 30 simulated seconds on the derelict path.
	playable.away_from_start = true
	var n: int = 0
	for i: int in range(30):
		playable._process(1.0)
		n += 1

	var crop_grew: bool = playable.hydroponics_state.progress_seconds > growth_before + 1.0
	var spoiled_away: bool = _spoil_age("cooked_meal") > spoil_before + 1.0

	if crop_grew and spoiled_away:
		print("FOOD AWAY TICK PASS away_ticks=%d crop_grew=true spoiled_away=true" % n)
		_cleanup_and_quit(0)
	else:
		_fail("crop_grew=%s spoiled_away=%s growth_before=%.3f growth_after=%.3f spoil_before=%.3f spoil_after=%.3f" % [
			str(crop_grew), str(spoiled_away),
			growth_before, playable.hydroponics_state.progress_seconds,
			spoil_before, _spoil_age("cooked_meal")
		])

## Read per-item elapsed_seconds from spoilage_state.get_summary().
## Real shape: summary["foods"][item_id]["elapsed_seconds"] (from food_state.gd get_summary()).
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

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child: Node in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("FOOD AWAY TICK FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
