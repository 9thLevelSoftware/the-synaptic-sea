extends SceneTree

## Domain 1 away-path proof (live scene): on a boarded derelict
## (away_from_start=true, past the line 4808 early-return) the survival attrition
## tick must ADVANCE — radiation drains health, the extreme-zone signal heats body
## temperature — and draining health to 0 must end the run as a death.
##
## Pass marker:
##   MAIN PLAYABLE SURVIVAL AWAY PASS away_ticks=true rad_drain=true temp_rise=true away_death=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
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
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	if playable.vitals_state == null or playable.radiation_state == null or playable.body_temperature_state == null:
		_fail("vitals / radiation / body_temperature missing")
		return
	# Isolate from combat damage; board a derelict.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.away_from_start = true

	# Radiation must drain health on the AWAY branch (it ran home-only before).
	playable.radiation_state.radiation = 100.0
	playable.vitals_state.health = 90.0
	var rad_before: float = playable.vitals_state.health
	_pump(2.0)
	var rad_drain: bool = playable.vitals_state.health < rad_before - 0.001
	if not rad_drain:
		_fail("radiation should drain health on a derelict (%.3f -> %.3f)" % [rad_before, playable.vitals_state.health])
		return

	# Extreme-zone signal must engage body temperature away (was always-false before).
	var temp_before: float = playable.body_temperature_state.temperature
	_pump(2.0)
	var temp_rise: bool = playable.body_temperature_state.temperature > temp_before + 0.001
	if not temp_rise:
		_fail("body temperature should rise in the derelict extreme zone (%.3f -> %.3f)" % [temp_before, playable.body_temperature_state.temperature])
		return

	# Death must fire on the AWAY branch.
	playable.vitals_state.health = 0.0
	_pump(0.1)
	if not playable.slice_complete:
		_fail("health=0 on a derelict should end the run (slice_complete still false)")
		return

	finished = true
	print("MAIN PLAYABLE SURVIVAL AWAY PASS away_ticks=true rad_drain=true temp_rise=true away_death=true")
	_cleanup_and_quit(0)

func _pump(seconds: float) -> void:
	var step: float = 1.0 / 30.0
	var elapsed: float = 0.0
	while elapsed < seconds:
		playable._process(step)
		elapsed += step

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
	push_error("MAIN PLAYABLE SURVIVAL AWAY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
