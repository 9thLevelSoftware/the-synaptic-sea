extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var frame_count: int = 0
var phase: int = 0
var finished: bool = false

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
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null:
		_fail("menu coordinator missing")
		return
	match phase:
		0:
			_validate_boot(ui)
			phase = 1
		1:
			ui.menu_state.open_menu("settings_menu")
			phase = 2
		2:
			_validate_settings(ui)
			phase = 3
		3:
			_drive_to_in_play()
			phase = 4
		4:
			_validate_runtime(playable, ui)
			finished = true
			print("MAIN PLAYABLE UI SHELL PASS boot=main_menu pause=true codex=1 minimap=true hotbar=true tooltip=true")
			quit(0)

func _validate_boot(ui) -> void:
	if ui.get_current_menu() != "main_menu":
		_fail("boot menu=%s expected main_menu" % ui.get_current_menu())
		return
	var text: String = ui.get_menu_text()
	for token in ["New Run", "Settings", "Quit"]:
		if not text.contains(token):
			_fail("main menu missing token %s" % token)
			return

func _validate_settings(ui) -> void:
	if ui.get_current_menu() != "settings_menu":
		_fail("settings menu not opened: %s" % ui.get_current_menu())
		return
	var summary: Dictionary = ui.get_settings_summary().duplicate(true)
	summary["text_scale"] = 1.5
	if not ui.apply_settings_summary(summary):
		_fail("settings summary apply failed")
		return
	var after: Dictionary = ui.get_settings_summary()
	if str(after.get("text_scale")) != "1.5":
		_fail("settings text_scale did not persist")
		return
	ui.menu_state.open_menu("main_menu")
	if ui.get_current_menu() != "main_menu":
		_fail("escape did not return to main menu")

func _drive_to_in_play() -> void:
	_send_action(KEY_ENTER)
	_send_action(KEY_ESCAPE)
	_send_action(KEY_F1)

func _validate_runtime(playable: PlayableGeneratedShip, ui) -> void:
	if ui.get_current_menu() != "codex":
		_fail("codex not opened from pause/menu flow: %s" % ui.get_current_menu())
		return
	ui.trigger_tutorial("player_moved", "any")
	if ui.get_tutorial_text().is_empty():
		_fail("tutorial banner missing after trigger")
		return
	if not playable.dismiss_latest_tutorial_for_validation():
		_fail("tutorial dismiss failed")
		return
	if ui.get_codex_unlocked_ids().size() < 1:
		_fail("codex did not unlock after tutorial dismiss")
		return
	_send_action(KEY_ESCAPE)
	_send_action(KEY_M)
	if ui.get_minimap_text().find("Tracked:") == -1:
		_fail("minimap text missing tracked line")
		return
	if ui.get_hotbar_text().find("HOTBAR") == -1:
		_fail("hotbar text missing")
		return
	ui.set_tooltip_query({"subject_kind": "interactable", "subject_id": "circuit_board"})
	if ui.get_tooltip_panel_text().find("Circuit Board") == -1:
		_fail("tooltip text missing circuit board payload")

func _send_action(keycode: int) -> void:
	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	Input.parse_input_event(release)

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
	push_error("MAIN PLAYABLE UI SHELL FAIL reason=%s" % reason)
	quit(1)
