extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var phase: int = 0
var expected: Dictionary = {}

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
			_send_action(KEY_ENTER)
			expected = ui.get_settings_summary().duplicate(true)
			expected["text_scale"] = 2.0
			expected["hold_to_tap"] = true
			expected["colorblind_mode"] = "deuteranopia"
			expected["glyph_scheme"] = "keyboard"
			if not playable.apply_ui_settings_summary_for_validation(expected):
				_fail("apply settings summary failed")
				return
			if not playable.request_save():
				_fail("request_save failed")
				return
			phase = 1
		1:
			var reset_summary: Dictionary = ui.get_settings_summary().duplicate(true)
			reset_summary["text_scale"] = 1.0
			reset_summary["hold_to_tap"] = false
			reset_summary["colorblind_mode"] = "none"
			reset_summary["glyph_scheme"] = "auto"
			if not playable.apply_ui_settings_summary_for_validation(reset_summary):
				_fail("reset settings summary failed")
				return
			if not playable.request_load():
				_fail("request_load failed")
				return
			phase = 2
		2:
			var loaded: Dictionary = ui.get_settings_summary()
			for key in ["text_scale", "hold_to_tap", "colorblind_mode", "glyph_scheme"]:
				if str(loaded.get(key)) != str(expected.get(key)):
					_fail("loaded %s=%s expected %s" % [key, str(loaded.get(key)), str(expected.get(key))])
					return
			finished = true
			print("UI SHELL SAVE LOAD PASS restored=true text_scale=%s hold_to_tap=%s colorblind=%s glyph=%s" % [str(loaded.get("text_scale")), str(loaded.get("hold_to_tap")), str(loaded.get("colorblind_mode")), str(loaded.get("glyph_scheme"))])
			quit(0)

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
	push_error("UI SHELL SAVE LOAD FAIL reason=%s" % reason)
	quit(1)
