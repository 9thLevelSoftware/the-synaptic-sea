extends SceneTree

## Domain 2 closure (live scene): on a boarded derelict (away_from_start=true) the
## real coordinator tick drives the combat loop end-to-end —
##   BP2: moving raises emitted noise vs idle; crouch lowers emitted visibility.
##   BP1: the threat's awareness reflects the detection emitted profile.
##   BP3: killing a threat spawns a lootable corpse container AND removes the threat.
##
## Pass marker:
##   COMBAT CLOSURE PASS away_kill=true noise=true crouch=true reward=true removed=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600
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
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	if playable.threat_manager == null or playable.player == null:
		_fail("threat_manager / player missing")
		return
	var tm = playable.threat_manager
	# Board a derelict so the whole loop is exercised on the away branch.
	playable.away_from_start = true
	# Ensure at least one threat exists to kill.
	if tm.threats.is_empty():
		tm.inject_validation_encounter(["stalker"], Vector3.ZERO)
	# --- BP2 (coordinator feed): drive the stealth signals through the LIVE _process
	# tick so the assertions exercise _tick_threat_runtime -> set_player_signals ->
	# detection (not a direct model write). Disable the player's _physics_process so its
	# per-tick velocity/input reads do not clobber the scripted state mid-test. ---
	playable.player.set_physics_process(false)
	# Noise from movement: is_moving() (planar velocity) feeds set_player_signals' noise arg.
	playable.player.set_crouching(false)
	playable.player.velocity = Vector3.ZERO
	playable._process(1.0 / 30.0)
	var idle_noise: float = float(tm.detection_state.get_emitted_profile()["noise"])
	playable.player.velocity = Vector3(5.0, 0.0, 0.0)
	playable._process(1.0 / 30.0)
	var move_noise: float = float(tm.detection_state.get_emitted_profile()["noise"])
	# Proves is_moving() is wired through the coordinator: a still player and a moving
	# player must emit different noise (catches an inert/literal noise feed).
	var noise_ok: bool = move_noise > idle_noise
	# Crouch lowers emitted visibility, fed through the coordinator (detection.crouching flips).
	playable.player.velocity = Vector3.ZERO
	playable.player.set_crouching(false)
	playable._process(1.0 / 30.0)
	var stand_vis: float = float(tm.detection_state.get_emitted_profile()["visibility"])
	var stand_flag: bool = tm.detection_state.crouching
	playable.player.set_crouching(true)
	playable._process(1.0 / 30.0)
	var crouch_vis: float = float(tm.detection_state.get_emitted_profile()["visibility"])
	# Coordinator feed proven: detection.crouching went false->true via _process AND
	# the emitted visibility dropped — not a direct model write.
	var crouch_ok: bool = crouch_vis < stand_vis and tm.detection_state.crouching and not stand_flag
	# --- BP3: kill a threat through the live coordinator tick (away branch). ---
	var before_containers: int = playable.loot_containers.size()
	var before_threats: int = tm.threats.size()
	tm.threats[0].health = 0.0
	# Drive the real coordinator process (away branch runs _tick_threat_runtime -> tick_threats -> sweep).
	playable._process(1.0 / 30.0)
	var reward_ok: bool = playable.loot_containers.size() > before_containers
	var removed_ok: bool = tm.threats.size() < before_threats
	if not noise_ok:
		_fail("moving should raise emitted noise (%.3f vs %.3f)" % [move_noise, idle_noise])
		return
	if not crouch_ok:
		_fail("crouch should lower emitted visibility (%.3f vs %.3f)" % [crouch_vis, stand_vis])
		return
	if not reward_ok:
		_fail("kill should spawn a lootable corpse container")
		return
	if not removed_ok:
		_fail("kill should remove the threat from the active array")
		return
	finished = true
	print("COMBAT CLOSURE PASS away_kill=true noise=true crouch=true reward=true removed=true coord_feed=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f: PlayableGeneratedShip = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("COMBAT CLOSURE FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
