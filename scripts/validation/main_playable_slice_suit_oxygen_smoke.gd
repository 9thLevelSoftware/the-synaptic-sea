extends SceneTree

## Main-scene smoke for the live suit->oxygen wiring (Phase 7 sub-project B):
## proves _refresh_oxygen_state folds EquipmentState.get_oxygen_drain_multiplier()
## into OxygenState every frame. The breach is open at slice start, so the drain
## multiplier in get_oxygen_summary() reflects inventory(tool) * equipment(worn),
## independent of player position (the multiplier is gated by breach state only).

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const SETTLE_FRAMES: int = 5

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false
var base_mult: float = 1.0

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
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_setup()
		"settle_base":
			_capture_base()
		"settle_suit":
			_check_suit()
		"settle_pump":
			_check_combined()

func _setup() -> void:
	if playable.get("oxygen_state") == null:
		_fail("oxygen_state null")
		return
	if playable.get("equipment_state") == null:
		_fail("equipment_state null")
		return
	if playable.get("inventory_state") == null:
		_fail("inventory_state null")
		return
	var initial: Dictionary = playable.get_oxygen_summary()
	if not bool(initial.get("breach_open", false)):
		_fail("breach should be open at slice start")
		return
	if bool(initial.get("breach_sealed", true)):
		_fail("breach should not be sealed at slice start")
		return
	# Deterministic baseline: remove any worn equipment so the multiplier reflects
	# inventory-only (the coordinator itself clears slots this way on reload).
	playable.equipment_state.slots.clear()
	phase = "settle_base"
	phase_frames = 0

func _capture_base() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	base_mult = float(playable.get_oxygen_summary().get("drain_multiplier", -1.0))
	if base_mult <= 0.0:
		_fail("baseline drain_multiplier should be >0, got %s" % str(base_mult))
		return
	# Equip the suit on the same EquipmentState the coordinator owns.
	var res: Dictionary = playable.equipment_state.equip("hardsuit")
	if not bool(res.get("ok", false)):
		_fail("equipping hardsuit failed")
		return
	phase = "settle_suit"
	phase_frames = 0

func _check_suit() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	var s: Dictionary = playable.get_oxygen_summary()
	var suit_mult: float = float(s.get("drain_multiplier", -1.0))
	if absf(suit_mult - base_mult * 0.75) > 0.001:
		_fail("after equipping suit drain_multiplier should be base*0.75=%s, got %s" % [str(base_mult * 0.75), str(suit_mult)])
		return
	if absf(float(s.get("equipment_drain_multiplier", -1.0)) - 0.75) > 0.001:
		_fail("equipment_drain_multiplier should be 0.75, got %s" % str(s.get("equipment_drain_multiplier", -1.0)))
		return
	# Add the pump so the inventory component is deterministically 0.5.
	playable.inventory_state.add_tool("portable_oxygen_pump")
	if not playable.inventory_state.has_tool("portable_oxygen_pump"):
		_fail("pump not present after add_tool")
		return
	phase = "settle_pump"
	phase_frames = 0

func _check_combined() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	var c: Dictionary = playable.get_oxygen_summary()
	var combined: float = float(c.get("drain_multiplier", -1.0))
	if absf(combined - 0.375) > 0.001:
		_fail("suit+pump combined drain_multiplier should be 0.375, got %s" % str(combined))
		return
	finished = true
	print("SUIT OXYGEN SLICE SMOKE PASS suit_mult=0.75 combined_mult=0.375")
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
	push_error("SUIT OXYGEN SLICE SMOKE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
