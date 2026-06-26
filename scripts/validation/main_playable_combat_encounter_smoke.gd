extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var exercised: bool = false

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
	var playable = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if exercised:
		return
	exercised = true
	_run_validation(playable)

func _run_validation(playable) -> void:
	playable.inventory_state.add_item("flare_pistol", 1)
	playable.inventory_state.add_item("flare_round", 2)
	var equip_result: Dictionary = playable.equipment_state.equip("flare_pistol")
	if not bool(equip_result.get("ok", false)):
		_fail("failed to equip flare_pistol")
		return
	playable._on_inventory_transfer_completed()
	playable.threat_manager.inject_validation_encounter(["stalker"], (playable.player as Node3D).global_position)
	playable._tick_threat_runtime(0.25)
	if playable.threat_manager.get_active_threat_count() != 1:
		_fail("expected one active threat")
		return
	var attack_result: Dictionary = playable._attack_with_equipped_weapon()
	if not bool(attack_result.get("ok", false)):
		_fail("weapon attack failed: %s" % JSON.stringify(attack_result))
		return
	if int(playable.inventory_state.get_quantity("flare_round")) != 1:
		_fail("ammo did not decrement")
		return
	if playable.current_ship == null or playable.current_ship.combat_summary.is_empty():
		_fail("combat summary was not captured")
		return
	if not playable.request_save():
		_fail("request_save returned false")
		return
	playable.inventory_state.remove_item("flare_round", 1)
	playable.threat_manager.configure_for_layout({}, [], Vector3.ZERO)
	if not playable.request_load():
		_fail("request_load returned false")
		return
	if int(playable.inventory_state.get_quantity("flare_round")) != 1:
		_fail("load did not restore ammo")
		return
	if playable.threat_manager.get_active_threat_count() != 1:
		_fail("load did not restore threat state")
		return
	if playable.hotbar_panel == null or not String(playable.hotbar_panel.label.text).contains("Flare Pistol"):
		_fail("hotbar missing equipped weapon label")
		return
	finished = true
	print("MAIN PLAYABLE COMBAT ENCOUNTER PASS ammo=%d threats=%d hotbar=%s" % [
		int(playable.inventory_state.get_quantity("flare_round")),
		playable.threat_manager.get_active_threat_count(),
		String(playable.hotbar_panel.label.text),
	])
	quit(0)

func _find_playable(node: Node):
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE COMBAT ENCOUNTER FAIL reason=%s" % reason)
	quit(1)
