extends SceneTree

## Main-scene smoke for the player-vitals HUD panel (Phase 7 sub-project C):
## proves the coordinator builds the bottom-left PlayerVitalsPanel under hud_layer
## and feeds live state into it each frame — oxygen/breach, the worn-suit O2
## contribution, the Heavy-Load encumbrance penalty, and active repair progress +
## the repair_blocked reason.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const SETTLE_FRAMES: int = 6

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false
var repair_point                       # the RepairPoint we drive directly

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
		"settle_breach":
			_check_breach()
		"settle_suit":
			_check_suit()
		"settle_heavy":
			_check_heavy()
		"settle_repair":
			_check_repair()
		"settle_blocked":
			_check_blocked()

func _setup() -> void:
	# Structural assertions on the panel itself.
	var hud_layer = playable.get("hud_layer")
	if hud_layer == null or not (hud_layer is CanvasLayer):
		_fail("hud_layer missing or not a CanvasLayer")
		return
	var panel = playable.get("vitals_panel")
	if panel == null or not (panel is Control):
		_fail("vitals_panel missing or not a Control")
		return
	if panel.get_parent() != hud_layer:
		_fail("vitals_panel is not parented under hud_layer")
		return
	if not is_equal_approx(panel.anchor_top, 1.0) or not is_equal_approx(panel.anchor_left, 0.0):
		_fail("vitals_panel is not anchored bottom-left (top=%s left=%s)" % [str(panel.anchor_top), str(panel.anchor_left)])
		return
	# Source models must exist.
	if playable.get("oxygen_state") == null or playable.get("inventory_state") == null or playable.get("equipment_state") == null:
		_fail("a source model (oxygen/inventory/equipment) is null")
		return
	if playable.repair_points == null or playable.repair_points.is_empty():
		_fail("no repair_points to drive")
		return
	# Put the player in the breach zone so the live scenario is faithful.
	playable.teleport_player_to_breach_zone_for_validation()
	# Deterministic baseline: clear worn equipment (the coordinator clears slots
	# this way on reload) so the suit assertion measures the hardsuit alone.
	playable.equipment_state.slots.clear()
	phase = "settle_breach"
	phase_frames = 0

func _check_breach() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	var lines: PackedStringArray = playable.get_player_vitals_lines()
	if not _line_with(lines, "Oxygen:", "(BREACH)"):
		_fail("expected an Oxygen line with (BREACH), got %s" % str(lines))
		return
	# Equip the hardsuit on the coordinator's own EquipmentState.
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
	if not _has(playable.get_player_vitals_lines(), "Suit: -25% O2 drain"):
		_fail("expected 'Suit: -25%% O2 drain', got %s" % str(playable.get_player_vitals_lines()))
		return
	# Over-encumber deterministically: 20 x scrap_metal (5.0 each = 100) vs 50 capacity.
	playable.inventory_state.add_item("scrap_metal", 20)
	phase = "settle_heavy"
	phase_frames = 0

func _check_heavy() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	if not _line_with(playable.get_player_vitals_lines(), "Load:", "HEAVY"):
		_fail("expected a Load line containing HEAVY, got %s" % str(playable.get_player_vitals_lines()))
		return
	# Drive an active repair channel directly on a repair point.
	repair_point = playable.repair_points[0]
	repair_point.channeling = true
	repair_point.progress = 0.47
	phase = "settle_repair"
	phase_frames = 0

func _check_repair() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	if not _has(playable.get_player_vitals_lines(), "Repairing 47%"):
		_fail("expected 'Repairing 47%%', got %s" % str(playable.get_player_vitals_lines()))
		return
	# End the channel and emit a blocked rejection through the real signal path.
	repair_point.channeling = false
	repair_point.progress = 0.0
	repair_point.emit_signal("repair_blocked", repair_point.system_id, repair_point.subcomponent_id, "missing_parts")
	phase = "settle_blocked"
	phase_frames = 0

func _check_blocked() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	if not _has(playable.get_player_vitals_lines(), "Repair blocked: missing parts"):
		_fail("expected 'Repair blocked: missing parts', got %s" % str(playable.get_player_vitals_lines()))
		return
	finished = true
	print("MAIN PLAYABLE VITALS HUD PASS panel=true breach=true suit=true heavy=true repair=true")
	_cleanup_and_quit(0)

func _has(lines: PackedStringArray, needle: String) -> bool:
	for line in lines:
		if String(line) == needle:
			return true
	return false

func _line_with(lines: PackedStringArray, prefix: String, contains: String) -> bool:
	for line in lines:
		var s: String = String(line)
		if s.begins_with(prefix) and s.contains(contains):
			return true
	return false

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
	push_error("MAIN PLAYABLE VITALS HUD FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
