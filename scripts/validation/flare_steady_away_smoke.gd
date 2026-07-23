extends SceneTree

## Domain 5 Task 7: an active utility_flare steadies the player -> less sanity drain
## in an unsafe zone than without it.
## Marker: FLARE STEADY AWAY PASS drain_no_flare=<f> drain_flare=<f> steadier=true

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
	if finished: return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES: _fail("not ready")
		return
	_validate()

func _boost_vitals() -> void:
	# Tranche 1 away death guard: 20s of away attrition would kill the player
	# and (correctly) freeze the sim mid-measurement — this smoke measures
	# SANITY drain, not survival, so keep the player alive like
	# ship_systems_closure_smoke does.
	if playable.vitals_state != null:
		playable.vitals_state.hunger = playable.vitals_state.max_hunger
		playable.vitals_state.thirst = playable.vitals_state.max_thirst
		playable.vitals_state.health = playable.vitals_state.max_health

func _validate() -> void:
	finished = true
	playable.away_from_start = true
	playable.away_from_start = true  # unsafe zone
	# Run A: no flare.
	playable.sanity_state.configure({})
	var a0: float = playable.sanity_state.sanity
	for i in range(10):
		_boost_vitals()
		playable._process(1.0)
	var drain_no_flare: float = a0 - playable.sanity_state.sanity
	# Run B: flare active for the whole window.
	playable.sanity_state.configure({})
	var b0: float = playable.sanity_state.sanity
	for i in range(10):
		_boost_vitals()
		playable.status_effects_state.add_effect("utility_flare", 5.0, 1)  # keep it topped up
		playable._process(1.0)
	var drain_flare: float = b0 - playable.sanity_state.sanity
	var steadier: bool = drain_flare < drain_no_flare - 0.01
	if steadier:
		print("FLARE STEADY AWAY PASS drain_no_flare=%.3f drain_flare=%.3f steadier=true" % [drain_no_flare, drain_flare])
		_cleanup(0)
	else:
		_fail("drain_no_flare=%.3f drain_flare=%.3f" % [drain_no_flare, drain_flare])

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip: return node as PlayableGeneratedShip
	for child in node.get_children():
		var f := _find_playable(child)
		if f != null: return f
	return null

func _fail(reason: String) -> void:
	push_error("FLARE STEADY AWAY FAIL reason=%s" % reason); _cleanup(1)

func _cleanup(code: int) -> void:
	if main_node != null and is_instance_valid(main_node): main_node.queue_free()
	quit(code)
