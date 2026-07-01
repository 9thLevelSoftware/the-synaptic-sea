extends SceneTree

## Domain 5 Task 4: stimulant + addiction per-frame decay advance on the AWAY branch.
## Drives away_from_start = true, applies a stim, and asserts its buff timer decays
## and the addiction model ticks while boarded.
## Marker: CONSUMABLES AWAY TICK PASS away_ticks=<n> stim_decayed=true addiction_ticked=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
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
	finished = true
	# Seed an active stim buff (StimulantState.active_stims entries carry "remaining")
	# and an addiction profile (AddictionState.record_dose seeds tolerance/dependence).
	playable.stimulant_state.active_stims.append({
		"item_id": "stim_focus", "remaining": 20.0, "base_duration": 20.0,
		"effects": [], "withdrawal_effects": [],
	})
	playable.addiction_state.record_dose("stim_focus", {"tolerance_gain": 0.5, "dependence_gain": 0.5})
	var stim_before: float = _active_buff_seconds()
	var tol_before: float = playable.addiction_state.get_tolerance("stim_focus")
	playable.away_from_start = true
	var n: int = 0
	for i in range(20):
		playable._process(1.0)
		n += 1
	# Stim "remaining" decays each away tick; addiction tolerance decays by delta*0.01/s.
	var stim_decayed: bool = _active_buff_seconds() < stim_before - 0.5
	var addiction_ticked: bool = playable.addiction_state.get_tolerance("stim_focus") < tol_before - 0.001
	if stim_decayed and addiction_ticked:
		print("CONSUMABLES AWAY TICK PASS away_ticks=%d stim_decayed=true addiction_ticked=true" % n)
		_cleanup(0)
	else:
		_fail("stim_decayed=%s addiction_ticked=%s stim_before=%.2f stim_after=%.2f tol_before=%.3f tol_after=%.3f" % [
			str(stim_decayed), str(addiction_ticked), stim_before, _active_buff_seconds(),
			tol_before, playable.addiction_state.get_tolerance("stim_focus")])

## Highest active-stim remaining-seconds from StimulantState.get_summary()["active_stims"].
func _active_buff_seconds() -> float:
	var s: Dictionary = playable.stimulant_state.get_summary()
	var best: float = 0.0
	var actives: Variant = s.get("active_stims", [])
	if actives is Array:
		for e in actives:
			if e is Dictionary:
				best = maxf(best, float((e as Dictionary).get("remaining", 0.0)))
	return best

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("CONSUMABLES AWAY TICK FAIL reason=%s" % reason)
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
