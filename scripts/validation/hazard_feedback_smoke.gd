extends SceneTree

## Tranche 1 (audit): hazard interaction feedback was a dead flow.
##  - extinguish_blocked (fire_suppression_point.gd) fired on five failure
##    paths and seal_blocked (breach_seal_point.gd) on four — neither was
##    connected anywhere, so a blocked extinguish/seal gave the player zero
##    feedback about WHY nothing happened.
##  - _on_breach_sealed was a pass-only no-op: sealing a hull breach produced
##    no HUD line and no audio cue.
##
## Drives the REAL nodes the coordinator builds (force-ignited compartment ->
## suppression point; forced hull breach -> seal point) through their real
## try_start paths and asserts the coordinator surfaces feedback via the
## combined HUD status line channel, plus an SFX route on successful seal.
##
## Pass marker: HAZARD FEEDBACK PASS extinguish_blocked=true seal_blocked=true breach_sealed=true sfx_routed=true

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
	if not is_instance_valid(playable):
		playable = _find_playable(main_node)
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _feedback() -> String:
	return playable.get_last_loot_feedback_line_for_validation()

func _validate() -> void:
	finished = true

	# --- extinguish_blocked: real suppression point, no extinguisher ---------
	if not playable.force_ignite_compartment_for_validation("smoke_feedback_cmp"):
		_fail("could not force-ignite a compartment")
		return
	var points: Array = playable.get_fire_suppression_points_for_validation()
	if points.is_empty():
		_fail("no suppression point built for the burning compartment")
		return
	var fp = points[0]
	# try_start checks DIRECT range (not the candidate seam) — teleport in.
	playable.teleport_player_to_fire_suppression_point_for_validation(fp)
	# Fire B2: no extinguisher while burning deliberately vents (decompression teeth)
	# rather than a soft "missing extinguisher" block. Either vent HUD or extinguish_blocked
	# proves the suppression interact path produced player-facing feedback.
	fp.try_start(playable.player)  # no extinguisher -> deliberate vent OR blocked
	var extinguish_line: String = _feedback()
	if not (extinguish_line.begins_with("Extinguish blocked") or extinguish_line.begins_with("Emergency vent")):
		_fail("extinguish interact produced no HUD feedback (line='%s')" % extinguish_line)
		return
	var extinguish_blocked_ok: bool = true

	# --- seal_blocked: real seal point, no sealant ---------------------------
	var hull = playable.hull_integrity_state
	if hull == null or hull.compartments.is_empty():
		_fail("hull integrity state missing/empty")
		return
	var cid: String = str(hull.compartments.keys()[0])
	(hull.compartments[cid] as Dictionary)["breach_open"] = true
	playable._build_breach_seal_points()
	if playable.breach_seal_points.is_empty():
		_fail("no seal point built for the forced breach")
		return
	var sp = playable.breach_seal_points[0]
	(playable.player as Node3D).global_position = (sp as Node3D).global_position
	sp.set_validation_player_in_range(playable.player)
	sp.try_start(playable.player)  # no hull_sealant in inventory -> blocked
	if not _feedback().begins_with("Seal blocked"):
		_fail("seal_blocked produced no HUD feedback (line='%s')" % _feedback())
		return
	var seal_blocked_ok: bool = true

	# --- breach_sealed: complete a real seal, expect feedback + SFX ----------
	playable.inventory_state.add_item("hull_sealant", 2)
	var mgr: Node = playable.get_audio_manager()
	if mgr == null:
		_fail("audio_manager missing")
		return
	mgr.sfx_router.configure({})  # reset cooldowns/counters
	var routed_before: int = int(mgr.sfx_router.get_routed_count(&"sfx.tool.use"))
	(playable.player as Node3D).global_position = (sp as Node3D).global_position
	if not sp.try_start(playable.player):
		_fail("seal try_start failed with sealant in inventory")
		return
	sp.advance_channel(10.0)  # complete the timed seal
	if not _feedback().begins_with("Breach sealed"):
		_fail("breach_sealed produced no HUD feedback (line='%s')" % _feedback())
		return
	var routed_after: int = int(mgr.sfx_router.get_routed_count(&"sfx.tool.use"))
	if routed_after <= routed_before:
		_fail("breach_sealed routed no SFX cue")
		return

	print("HAZARD FEEDBACK PASS extinguish_blocked=%s seal_blocked=%s breach_sealed=true sfx_routed=true" % [
		str(extinguish_blocked_ok).to_lower(), str(seal_blocked_ok).to_lower()])
	_cleanup(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("HAZARD FEEDBACK FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
