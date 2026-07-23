extends SceneTree

## Live Persistent Ships Phase 4: proves _catch_up_ship fast-forwards an absent ship's
## sim by elapsed world_time in capped sub-steps. Tests directly on the model — no full
## travel path needed. Checks: web grew, hull degraded, timestamp stamped, idempotent.
## Marker: SHIP CATCHUP AWAY PASS web_grew=true hull_degraded=true timestamp_stamped=true bounded=true

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
	playable.away_from_start = true
	finished = true  # prevent re-entry across frames

	# --- Build and seed a derelict instance (mirrors first-visit path) ---
	var ShipInstanceScript = load("res://scripts/systems/ship_instance.gd")
	var inst = ShipInstanceScript.create("ship_catchup", "catchup:1", null, null, null)
	if inst == null:
		_fail("could not create ShipInstance")
		return
	playable._seed_ship_models(inst)

	# After seeding: last_sim_time == world_time, hull seeded, web attached with coverage 0.
	if inst.last_sim_time != playable.world_time:
		_fail("seed did not stamp last_sim_time: expected %.4f got %.4f" % [playable.world_time, inst.last_sim_time])
		return

	# --- Simulate a 100-second absence ---
	inst.last_sim_time = playable.world_time - 100.0

	var cov_before: float = inst.get_web().coverage
	var integ_before: float = inst.get_hull().average_integrity()

	# --- Run the catch-up ---
	playable._catch_up_ship(inst)

	var cov_after: float = inst.get_web().coverage
	var integ_after: float = inst.get_hull().average_integrity()

	# --- Assertions ---
	var web_grew: bool = cov_after > cov_before and cov_after <= 1.0
	var hull_degraded: bool = integ_after < integ_before and integ_after >= 0.0 and is_finite(integ_after)
	var timestamp_stamped: bool = inst.last_sim_time == playable.world_time

	if not web_grew:
		_fail("web_grew failed: cov_before=%.6f cov_after=%.6f" % [cov_before, cov_after])
		return
	if not hull_degraded:
		_fail("hull_degraded failed: integ_before=%.6f integ_after=%.6f is_finite=%s" % [
			integ_before, integ_after, str(is_finite(integ_after))])
		return
	if not timestamp_stamped:
		_fail("timestamp_stamped failed: last_sim_time=%.4f world_time=%.4f" % [
			inst.last_sim_time, playable.world_time])
		return

	# --- Idempotence: second call with dt==0 must change nothing ---
	var cov_after2: float = cov_after
	var integ_after2: float = integ_after
	playable._catch_up_ship(inst)
	var cov_final: float = inst.get_web().coverage
	var integ_final: float = inst.get_hull().average_integrity()
	var bounded: bool = (cov_final == cov_after2) and (integ_final == integ_after2)

	if not bounded:
		_fail("bounded/idempotent failed: cov changed %.6f->%.6f integ changed %.6f->%.6f" % [
			cov_after2, cov_final, integ_after2, integ_final])
		return

	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("SHIP CATCHUP AWAY PASS away=true web_grew=true hull_degraded=true timestamp_stamped=true bounded=true")
	_cleanup_and_quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child: Node in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("SHIP CATCHUP AWAY FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
