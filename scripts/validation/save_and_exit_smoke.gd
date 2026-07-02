extends SceneTree

## ADR-0043 Save & Exit smoke: drives the pause menu's new "Save & Exit"
## item end-to-end -- request_save() succeeds, world.json is fresh (not
## consumed/frozen), and return_to_title_requested fires.
##
## Pass marker:
##   SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false
var _return_signal_received: bool = false

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
	_validate()

func _validate() -> void:
	if playable.menu_coordinator == null or playable.save_load_service == null:
		_fail("menu_coordinator / save_load_service missing")
		return
	playable.save_load_service.delete_current_run()
	playable.return_to_title_requested.connect(_on_return_to_title)

	var coord = playable.menu_coordinator
	coord.open_records_menu()  # ensures we start from a known state
	coord.menu_state.close_all()
	coord.menu_state.open_menu("pause_menu")
	var items: Array = coord.menu_state.get_items("pause_menu")
	var target_index: int = -1
	for i in range(items.size()):
		if str((items[i] as Dictionary).get("id", "")) == "save_and_exit":
			target_index = i
			break
	if target_index < 0:
		_fail("save_and_exit item not found in pause_menu catalog")
		return
	coord.menu_state.set_focus_index(target_index)
	coord._confirm_current_item()

	if not playable.save_load_service.has_save():
		_fail("world save missing after Save & Exit")
		return
	if not _return_signal_received:
		_fail("return_to_title_requested did not fire after a successful Save & Exit")
		return

	finished = true
	print("SAVE AND EXIT PASS saved=true world_fresh=true return_signal=true")
	_cleanup_and_quit(0)

func _on_return_to_title() -> void:
	_return_signal_received = true

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
	push_error("SAVE AND EXIT FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if playable != null and is_instance_valid(playable) and playable.save_load_service != null:
		playable.save_load_service.delete_current_run()
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
