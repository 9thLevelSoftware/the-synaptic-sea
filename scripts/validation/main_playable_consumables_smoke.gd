extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait_ready"
var expected_loaded_health: float = 0.0

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
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
	if phase == "wait_ready":
		_setup_and_use()
	elif phase == "wait_load":
		_verify_load()

func _setup_and_use() -> void:
	playable.inventory_state.add_item("bandage_kit", 2)
	playable.inventory_state.add_item("focus_ampoule", 1)
	playable.inventory_state.add_item("flare", 1)
	playable.assign_hotbar_slot_for_validation(0, "bandage_kit")
	playable.assign_hotbar_slot_for_validation(1, "focus_ampoule")

	var med := playable.use_hotbar_slot_for_validation(0)
	if not bool(med.get("ok", false)):
		_fail("bandage hotbar use failed")
		return
	var stim := playable.use_hotbar_slot_for_validation(1)
	if not bool(stim.get("ok", false)):
		_fail("stim hotbar use failed")
		return
	var utility := playable.use_inventory_item_for_validation("flare")
	if not bool(utility.get("ok", false)):
		_fail("flare use failed")
		return
	if not playable.status_effects_state.has_effect("stim_focus"):
		_fail("stim effect missing before save")
		return
	expected_loaded_health = playable.vitals_state.health
	if not playable.request_save():
		_fail("request_save failed")
		return
	playable.vitals_state.health = 5.0
	playable.status_effects_state.remove_effect("stim_focus", 9999)
	if not playable.request_load():
		_fail("request_load failed")
		return
	_verify_load()

func _verify_load() -> void:
	if absf(playable.vitals_state.health - expected_loaded_health) > 0.001:
		_fail("health did not restore after load")
		return
	if not playable.status_effects_state.has_effect("stim_focus"):
		_fail("stim effect missing after load")
		return
	if str(playable.consumable_state.hotbar_slots[0]) != "bandage_kit":
		_fail("hotbar slot did not restore")
		return
	var snapshot = playable._build_run_snapshot()
	if snapshot == null or snapshot.consumable_summary.is_empty() or snapshot.stimulant_summary.is_empty() or snapshot.ammo_summary.is_empty() or snapshot.utility_summary.is_empty():
		_fail("consumable summaries missing from snapshot")
		return
	finished = true
	print("MAIN PLAYABLE CONSUMABLES PASS save_load=true hotbar=true stim=true utility=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE CONSUMABLES FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
