extends SceneTree

## Domain 4 Task 3: the ship_systems loop is live on the AWAY (derelict) branch.
## Drives away_from_start = true and asserts that, on the away branch:
##  - the hub web infestation ticks (coverage grows from 0),
##  - it damages the hub hull (average_integrity drops / a breach opens),
##  - the resulting breach engages the life-support atmosphere->vitals drain.
## ship_systems_manager.advance runs in the same away block as the web tick.
## Marker: SHIP SYSTEMS CLOSURE PASS away_ticks=<n> web_grew=true hull_damaged=true breach_to_vitals=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

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
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _validate() -> void:
	finished = true  # prevent re-entry across frames

	var coverage_before: float = playable.hull_web_state.coverage
	var integrity_before: float = playable.hull_integrity_state.average_integrity()

	# Force the AWAY branch and drive enough simulated seconds for the web to
	# breach a compartment (growth 0.05/s with contact, damage_rate 0.03/s).
	# Re-boost vitals each iteration so Domain 1 attrition / Domain 2 combat on the
	# away branch cannot kill the player mid-loop (which would reset the slice and
	# void the ship-systems assertion). This test isolates ship systems, not survival.
	playable.away_from_start = true
	var n: int = 0
	for i: int in range(60):
		if playable.vitals_state != null:
			playable.vitals_state.hunger = playable.vitals_state.max_hunger
			playable.vitals_state.thirst = playable.vitals_state.max_thirst
			playable.vitals_state.health = playable.vitals_state.max_health
		playable._process(1.0)
		n += 1

	var web_grew: bool = playable.hull_web_state.coverage > coverage_before + 0.05
	var hull_damaged: bool = playable.hull_integrity_state.average_integrity() < integrity_before - 0.05
	var breach_to_vitals: bool = playable.hull_integrity_state.get_breach_count() > 0 \
		and playable.life_support_expanded_state.get_health_drain_per_second() > 0.0

	if web_grew and hull_damaged and breach_to_vitals:
		print("SHIP SYSTEMS CLOSURE PASS away_ticks=%d web_grew=true hull_damaged=true breach_to_vitals=true" % n)
		_cleanup_and_quit(0)
	else:
		_fail("web_grew=%s hull_damaged=%s breach_to_vitals=%s cov_before=%.3f cov_after=%.3f integ_before=%.3f integ_after=%.3f breaches=%d drain=%.4f" % [
			str(web_grew), str(hull_damaged), str(breach_to_vitals),
			coverage_before, playable.hull_web_state.coverage,
			integrity_before, playable.hull_integrity_state.average_integrity(),
			playable.hull_integrity_state.get_breach_count(),
			playable.life_support_expanded_state.get_health_drain_per_second()
		])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child: Node in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("SHIP SYSTEMS CLOSURE FAIL reason=%s" % reason)
	finished = true
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
