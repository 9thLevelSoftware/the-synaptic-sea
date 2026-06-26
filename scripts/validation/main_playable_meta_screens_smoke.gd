extends SceneTree

## Bucket 3 reachability proof: the ten menu/meta-UI screens are mounted by the LIVE
## coordinator's MenuCoordinator and reachable through its real Records submenu seam —
## not freshly-built instances. Each screen is opened via the coordinator, becomes the
## active meta screen, and reports live content driven by a coordinator-owned dependency
## (achievement_state, audio_manager, skill_tree_state, player_progression,
## hub_upgrade_state, meta_progression_state, localization_catalog, build_metadata_state,
## save_load_menu). This is the difference from the per-screen component smokes, which
## construct each panel in isolation.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

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
	_validate(playable)

func _validate(playable) -> void:
	var ui = playable.get_menu_coordinator_for_validation()
	if ui == null:
		_fail("menu coordinator missing")
		return

	# The coordinator must own the meta-screen registry (not the smoke).
	var ids: Array = ui.get_meta_screen_ids()
	if ids.size() != 10:
		_fail("expected 10 meta screens, got %d" % ids.size())
		return

	# Open the Records submenu through the real seam, then each screen in turn.
	ui.open_records_menu()
	if ui.get_current_menu() != "records_menu":
		_fail("records_menu did not open: %s" % ui.get_current_menu())
		return

	var visited: int = 0
	for screen_id in ids:
		ui.open_meta_screen(str(screen_id))
		if ui.get_active_meta_screen() != str(screen_id):
			_fail("screen did not become active: %s (got %s)" % [str(screen_id), ui.get_active_meta_screen()])
			return
		var panel = ui.get_meta_screen_panel(str(screen_id))
		if panel == null or not is_instance_valid(panel):
			_fail("screen panel not mounted: %s" % str(screen_id))
			return
		if not bool(panel.visible):
			_fail("active screen not visible: %s" % str(screen_id))
			return
		if not ui.meta_screen_is_populated(str(screen_id)):
			_fail("screen not populated by a live dependency: %s" % str(screen_id))
			return
		visited += 1

	if visited != 10:
		_fail("visited %d of 10 screens" % visited)
		return

	# The save-slot presenter is bound to the live save service (returns an Array).
	var slm = ui.get_save_load_menu()
	if slm == null or typeof(slm.refresh()) != TYPE_ARRAY:
		_fail("save_load_menu not bound to the live save service")
		return

	# Closing the Records submenu tears the displayed screen down.
	ui.open_main_menu()
	if not ui.get_active_meta_screen().is_empty():
		_fail("active meta screen not cleared on leaving records")
		return

	finished = true
	print("MAIN PLAYABLE META SCREENS PASS screens=%d reachable=true" % visited)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

func _find_playable(node: Node):
	if not is_instance_valid(node):
		return null
	if node.get_script() == load("res://scripts/procgen/playable_generated_ship.gd"):
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
	push_error("MAIN PLAYABLE META SCREENS FAIL reason=%s" % reason)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
