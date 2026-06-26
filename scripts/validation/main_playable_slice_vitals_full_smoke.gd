extends SceneTree

## Main-scene smoke for survival vitals HUD integration (REQ-SV-007).
## Proves the coordinator builds the bottom-left PlayerVitalsPanel under hud_layer
## and feeds live survival vitals into it each frame.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const SETTLE_FRAMES: int = 6

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
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
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > READY_TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	match phase:
		"waiting_ready":
			_setup()
		"settle":
			_check()

func _setup() -> void:
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
	var model = playable.get("vitals_model")
	if model == null:
		_fail("vitals_model is null")
		return
	# Survival vitals models must exist.
	if playable.get("vitals_state") == null:
		_fail("vitals_state is null")
		return
	if playable.get("sanity_state") == null:
		_fail("sanity_state is null")
		return
	if playable.get("radiation_state") == null:
		_fail("radiation_state is null")
		return
	if playable.get("body_temperature_state") == null:
		_fail("body_temperature_state is null")
		return
	if playable.get("status_effects_state") == null:
		_fail("status_effects_state is null")
		return
	phase = "settle"
	phase_frames = 0

func _check() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	var lines: PackedStringArray = playable.get_player_vitals_lines()
	var joined: String = "\n".join(lines)
	for token in ["Health:", "Stamina:", "Hunger:", "Thirst:", "Sanity:", "Radiation:", "Temp:"]:
		if not joined.contains(token):
			_fail("missing vital line '%s', got %s" % [token, joined])
			return
	# Force a non-default state and tick so cascades appear.
	playable.vitals_state.hunger = 20.0
	playable.vitals_state.thirst = 15.0
	playable.vitals_state.tick(0.1, {})
	playable.sanity_state.sanity = 35.0
	playable.sanity_state.in_safe_zone = false
	playable.sanity_state.tick(0.1)
	playable.radiation_state.radiation = 60.0
	playable.radiation_state.in_radiation_zone = true
	playable.radiation_state.tick(0.1)
	playable.body_temperature_state.temperature = 35.0
	playable.body_temperature_state.in_extreme_zone = true
	playable.body_temperature_state.tick(1.0)
	playable.status_effects_state.add_effect("radiation_sickness", 10.0, 1)
	playable.status_effects_state.tick(0.1)
	# Refresh the HUD model manually.
	playable._refresh_player_vitals(0.1)
	lines = playable.get_player_vitals_lines()
	joined = "\n".join(lines)
	for token in ["HUNGER LOW", "THIRST LOW", "PERCEPTION PRESSURE", "RADIATION SICKNESS", "DANGER", "Status:"]:
		if not joined.contains(token):
			_fail("missing cascade/status token '%s', got %s" % [token, joined])
			return
	finished = true
	print("MAIN PLAYABLE VITALS FULL PASS panel=true health=true stamina=true hunger=true thirst=true sanity=true radiation=true temperature=true status=true")
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
	push_error("MAIN PLAYABLE VITALS FULL FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
