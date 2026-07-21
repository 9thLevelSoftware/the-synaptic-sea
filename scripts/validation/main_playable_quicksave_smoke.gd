extends SceneTree

## F6 / request_quicksave live path: AutosavePolicy.try_quicksave + save_to_slot
## SLOT_KIND_QUICK writes a resumable quicksave row.
##
## Marker: MAIN PLAYABLE QUICKSAVE PASS slot=quicksave kind=quick cooldown=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 400

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
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable never ready")
		return
	if exercised:
		return
	exercised = true
	_validate(playable)

func _validate(playable) -> void:
	if playable.autosave_policy == null or playable.save_load_service == null:
		_fail("autosave_policy or save_load_service missing")
		return
	# Clear any prior quicksave so list_slots is clean.
	playable.save_load_service.delete_slot("quicksave")
	# First quicksave must succeed.
	if not playable.request_quicksave():
		_fail("first request_quicksave failed")
		return
	var rows: Array = playable.save_load_service.list_slots()
	var found: bool = false
	for row in rows:
		if row == null:
			continue
		if str(row.slot_id) == "quicksave" and str(row.slot_kind) == "quick":
			found = true
			break
	if not found:
		_fail("quicksave slot not listed after request_quicksave")
		return
	# Immediate second call must hit cooldown (try_quicksave returns false).
	if playable.request_quicksave():
		_fail("second request_quicksave should be cooldown-blocked")
		return
	print("MAIN PLAYABLE QUICKSAVE PASS slot=quicksave kind=quick cooldown=true")
	finished = true
	quit(0)

func _find_playable(node: Node):
	if node == null:
		return null
	if node.get_script() != null and String(node.get_script().resource_path).ends_with("playable_generated_ship.gd"):
		return node
	for child in node.get_children():
		var hit = _find_playable(child)
		if hit != null:
			return hit
	return null

func _fail(reason: String) -> void:
	push_error("MAIN PLAYABLE QUICKSAVE FAIL reason=%s" % reason)
	finished = true
	quit(1)
