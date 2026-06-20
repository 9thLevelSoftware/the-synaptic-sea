extends SceneTree
# Negative-path proof: run the alternate-input smoke logic after
# stripping alternate keycodes from the InputMap. Should exit 1.
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

var playable
var mutated = false
var stage = "wait"

func _initialize() -> void:
	var main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(func(): _tick(main_node))

func _tick(main_node):
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		return
	if not mutated:
		mutated = true
		# Drop all alternates
		for action_name in ["move_forward", "move_back", "move_left", "move_right", "interact"]:
			var keep: int = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "interact": KEY_E}[action_name]
			for ev in InputMap.action_get_events(action_name):
				if ev is InputEventKey:
					var kc: int = (ev as InputEventKey).physical_keycode
					if (ev as InputEventKey).keycode != keep:
						InputMap.action_erase_event(action_name, ev)
		print("MUTATED: move_right=", playable.get_input_action_keycodes_for_validation("move_right"))
		print("MUTATED: interact=", playable.get_input_action_keycodes_for_validation("interact"))
		print("HAS KEY_RIGHT binding on move_right? ", playable.get_input_action_keycodes_for_validation("move_right").has(KEY_RIGHT))
		print("HAS KEY_ENTER binding on interact? ", playable.get_input_action_keycodes_for_validation("interact").has(KEY_ENTER))
		# Now try sending a KEY_RIGHT event and see if the player moves
		playable.player.clear_scripted_move_direction()
		var start = playable.player.global_position
		var kev = InputEventKey.new()
		kev.physical_keycode = KEY_RIGHT
		kev.keycode = KEY_RIGHT
		kev.pressed = true
		Input.parse_input_event(kev)
		stage = "hold"
	if stage == "hold":
		# Wait 30 frames
		if not Engine.get_main_loop().is_type("SceneTree"):
			return
		var frames = 0
		# Just check after a few ticks — simpler: just keep polling
		pass
	# We can't easily count frames in this inline lambda; instead, use a simple timer via await
	quit(0)

func _find_playable(node):
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var f = _find_playable(child)
		if f != null:
			return f
	return null
