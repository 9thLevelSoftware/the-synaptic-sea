extends SceneTree

## Save/load smoke for survival vitals persistence (REQ-SV-008).
## Proves that RunSnapshot carries and restores vitals, sanity, radiation,
## temperature, and status effects summaries.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const READY_TIMEOUT_FRAMES: int = 300
const SETTLE_FRAMES: int = 6

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var phase: String = "waiting_ready"
var phase_frames: int = 0
var finished: bool = false
var saved_snapshot

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
			_settle()
		"assert":
			_assert()

func _setup() -> void:
	# Isolate this save/load smoke from the live combat runtime. The full
	# main scene now boots with threat markers, and ThreatManager can damage
	# vitals before the snapshot assertion if those threats remain active.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	# Set non-default vitals state; zero drain rates so background ticks
	# do not drift values during the settle frames.
	playable.vitals_state.configure({
		"health": 72.0, "stamina": 55.0, "hunger": 25.0, "thirst": 18.0,
		"health_drain_rate": 0.0, "stamina_drain_rate": 0.0,
		"hunger_drain_rate": 0.0, "thirst_drain_rate": 0.0,
	})
	playable.sanity_state.configure({
		"sanity": 38.0, "drain_rate": 0.0, "recovery_rate": 0.0,
	})
	playable.sanity_state.in_safe_zone = false
	playable.radiation_state.configure({
		"radiation": 65.0, "accumulation_rate": 0.0, "decay_rate": 0.0, "health_drain_rate": 0.0,
	})
	playable.radiation_state.in_radiation_zone = true
	playable.body_temperature_state.configure({
		"temperature": 35.0, "drain_rate": 0.0, "recovery_rate": 0.0,
	})
	playable.body_temperature_state.in_extreme_zone = true
	playable.status_effects_state.configure({})
	playable.status_effects_state.add_effect("radiation_sickness", 8.5, 2)
	phase = "settle"
	phase_frames = 0

func _settle() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	# Build snapshot and verify fields exist.
	var snapshot = playable._build_run_snapshot()
	if snapshot == null:
		_fail("_build_run_snapshot returned null")
		return
	if snapshot.vitals_summary.is_empty():
		_fail("vitals_summary is empty")
		return
	if snapshot.sanity_summary.is_empty():
		_fail("sanity_summary is empty")
		return
	if snapshot.radiation_summary.is_empty():
		_fail("radiation_summary is empty")
		return
	if snapshot.temperature_summary.is_empty():
		_fail("temperature_summary is empty")
		return
	if snapshot.status_effects_summary.is_empty():
		_fail("status_effects_summary is empty")
		return
	# Verify specific values.
	if absf(float(snapshot.vitals_summary.get("health", 0.0)) - 72.0) > 0.1:
		_fail("vitals_summary health mismatch")
		return
	if absf(float(snapshot.sanity_summary.get("sanity", 0.0)) - 38.0) > 0.1:
		_fail("sanity_summary sanity mismatch")
		return
	if absf(float(snapshot.radiation_summary.get("radiation", 0.0)) - 65.0) > 0.1:
		_fail("radiation_summary radiation mismatch")
		return
	if absf(float(snapshot.temperature_summary.get("temperature", 0.0)) - 35.0) > 0.1:
		_fail("temperature_summary temperature mismatch")
		return
	var effects: Array = snapshot.status_effects_summary.get("effects", [])
	if effects.is_empty():
		_fail("status_effects_summary effects empty")
		return
	# Reset live state to defaults.
	playable.vitals_state.configure({})
	playable.sanity_state.configure({})
	playable.radiation_state.configure({})
	playable.body_temperature_state.configure({})
	playable.status_effects_state.configure({})
	# Apply snapshot back.
	playable.vitals_state.apply_summary(snapshot.vitals_summary)
	playable.sanity_state.apply_summary(snapshot.sanity_summary)
	playable.radiation_state.apply_summary(snapshot.radiation_summary)
	playable.body_temperature_state.apply_summary(snapshot.temperature_summary)
	playable.status_effects_state.apply_summary(snapshot.status_effects_summary)
	phase = "assert"
	phase_frames = 0

func _assert() -> void:
	phase_frames += 1
	if phase_frames < SETTLE_FRAMES:
		return
	if absf(playable.vitals_state.health - 72.0) > 0.1:
		_fail("restored health mismatch")
		return
	if absf(playable.sanity_state.sanity - 38.0) > 0.1:
		_fail("restored sanity mismatch")
		return
	if absf(playable.radiation_state.radiation - 65.0) > 0.1:
		_fail("restored radiation mismatch")
		return
	if absf(playable.body_temperature_state.temperature - 35.0) > 0.1:
		_fail("restored temperature mismatch")
		return
	if playable.status_effects_state.get_stacks("radiation_sickness") != 2:
		_fail("restored status effect stacks mismatch")
		return
	finished = true
	print("VITALS SAVE LOAD PASS vitals=true sanity=true radiation=true temperature=true status=true")
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
	push_error("VITALS SAVE LOAD FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
