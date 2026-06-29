extends SceneTree

## Domain 1 home-path proof (live scene): low stamina slows the player via the
## vitals movement gate, and draining health to 0 ends the run as a death through
## the REAL coordinator _process tick (home branch, away_from_start=false).
##
## Pass marker:
##   MAIN PLAYABLE SURVIVAL STAKES PASS gate_half=true gate_locked=true death=true reachable=true

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
	if playable.vitals_state == null or playable.player == null:
		_fail("vitals / player missing")
		return
	# Isolate the measurement from combat damage.
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	playable.away_from_start = false

	# Exhausted stamina -> movement gate halves effective speed (before death).
	playable.vitals_state.health = 100.0
	playable.vitals_state.stamina = 5.0
	_pump(0.2)
	var gate_half: bool = absf(playable.player.get_effective_move_speed() - playable.player.move_speed * 0.5) < 0.001
	if not gate_half:
		_fail("exhausted stamina should halve effective move speed (got %.3f of %.3f)" % [playable.player.get_effective_move_speed(), playable.player.move_speed])
		return

	# Drain health to 0 -> incapacitation locks movement AND ends the run as death.
	playable.vitals_state.stamina = 100.0
	playable.vitals_state.health = 0.0
	_pump(0.1)
	var gate_locked: bool = absf(playable.player.get_effective_move_speed()) < 0.001
	if not gate_locked:
		_fail("incapacitation should lock movement (got %.3f)" % playable.player.get_effective_move_speed())
		return
	if not playable.slice_complete:
		_fail("health=0 should have ended the run (slice_complete still false)")
		return

	finished = true
	print("MAIN PLAYABLE SURVIVAL STAKES PASS gate_half=true gate_locked=true death=true reachable=true")
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
	push_error("MAIN PLAYABLE SURVIVAL STAKES FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
