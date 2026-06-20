extends SceneTree

# A11Y-P1-002 idempotency probe. Calls ensure_default_input_actions() twice
# and asserts the registered keycode set is unchanged (no duplicates, no
# new actions) on the second call. This is the "fresh project" path the
# card lists as an acceptance criterion.

const PlayableScene := preload("res://scenes/main.tscn")

func _initialize() -> void:
	var main_node = PlayableScene.instantiate()
	get_root().add_child(main_node)
	# Wait one frame so PlayableGeneratedShip._ready() runs and calls
	# ensure_default_input_actions() once.
	await process_frame
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		push_error("IDEMPOTENCY FAIL playable not found")
		quit(1)
		return
	# Snapshot all keycodes after the first registration.
	var first: Dictionary = _snapshot(playable)
	# Call again — this simulates the "fresh project" path where
	# ensure_default_input_actions() runs twice in a session.
	playable.ensure_default_input_actions()
	var second: Dictionary = _snapshot(playable)
	var mismatch: Array = []
	for action_name in first:
		var a: Array = first[action_name]
		var b: Array = second.get(action_name, [])
		if a.size() != b.size():
			mismatch.append([action_name, "size", a.size(), b.size()])
			continue
		for kc in a:
			if not b.has(kc):
				mismatch.append([action_name, "missing", kc, b])
	for action_name in second:
		if not first.has(action_name):
			mismatch.append([action_name, "new", "-", second[action_name]])
	if mismatch.size() > 0:
		push_error("IDEMPOTENCY FAIL first=%s second=%s mismatch=%s" % [str(first), str(second), str(mismatch)])
		quit(1)
		return
	print("IDEMPOTENCY PASS actions=%d no_duplicates_after_second_call=true" % first.size())
	main_node.queue_free()
	quit(0)

func _snapshot(playable: PlayableGeneratedShip) -> Dictionary:
	var actions: Array = ["move_forward", "move_back", "move_left", "move_right", "interact", "save_run", "load_run"]
	var out: Dictionary = {}
	for a in actions:
		out[a] = playable.get_input_action_keycodes_for_validation(a)
	return out

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null