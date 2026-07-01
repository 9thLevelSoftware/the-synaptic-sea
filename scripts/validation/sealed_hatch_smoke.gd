extends SceneTree

## Domain 5 Task 6: sealed hatches are seeded on a boarded derelict; priming the
## lockpick flag then interacting opens a mechanical hatch, consuming the flag and
## disabling its passage collision. Drives away_from_start = true.
## Marker: SEALED HATCH PASS away_ticks=<n> seeded=true mechanical_open=true flag_consumed=true

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
	playable.away_from_start = true
	playable._build_sealed_hatches()
	var n: int = 0
	for i in range(3):
		playable._process(0.1); n += 1
	var seeded: bool = playable.sealed_hatches.size() > 0
	# Find a mechanical hatch; prime the lockpick flag; force in-range; bypass.
	var mech = null
	for h in playable.sealed_hatches:
		if h.lock_kind == "mechanical":
			mech = h; break
	if mech == null:
		_fail("no mechanical hatch seeded (count=%d)" % playable.sealed_hatches.size()); return
	playable.utility_item_state.active_flags["lockpick"] = {"item_id": "lockpick_set", "count": 1}
	mech.set_validation_player_in_range(true)
	var res: Dictionary = mech.try_bypass(playable.player, playable.utility_item_state.active_flags)
	# Coordinator consumes the flag via the hatch_bypassed signal handler.
	var mechanical_open: bool = bool(res.get("ok", false)) and mech.bypassed
	var flag_consumed: bool = not playable.utility_item_state.active_flags.has("lockpick")
	if seeded and mechanical_open and flag_consumed:
		print("SEALED HATCH PASS away_ticks=%d seeded=true mechanical_open=true flag_consumed=true" % n)
		_cleanup(0)
	else:
		_fail("seeded=%s open=%s consumed=%s" % [str(seeded), str(mechanical_open), str(flag_consumed)])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	push_error("SEALED HATCH FAIL reason=%s" % reason)
	_cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
