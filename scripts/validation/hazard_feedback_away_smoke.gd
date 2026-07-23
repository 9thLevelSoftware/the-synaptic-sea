extends SceneTree

## Hazard extinguish/seal feedback under away_from_start using active fire/hull seams.
## Marker: HAZARD FEEDBACK AWAY PASS away=true extinguish_blocked=true seal_blocked=true breach_sealed=true sfx_routed=true

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
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) \
			or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()


func _feedback() -> String:
	return playable.get_last_loot_feedback_line_for_validation()


func _validate() -> void:
	finished = true
	playable.away_from_start = true

	if not playable.force_ignite_active_compartment_for_validation("smoke_feedback_cmp"):
		if not playable.force_ignite_compartment_for_validation("smoke_feedback_cmp"):
			_fail("could not force-ignite a compartment"); return
	var points: Array = playable.get_fire_suppression_points_for_validation()
	if points.is_empty():
		playable._refresh_fire_zones()
		points = playable.get_fire_suppression_points_for_validation()
	if points.is_empty():
		_fail("no suppression point built for the burning compartment"); return
	var fp = points[0]
	playable.teleport_player_to_fire_suppression_point_for_validation(fp)
	fp.try_start(playable.player)
	var extinguish_line: String = _feedback()
	if not (extinguish_line.begins_with("Extinguish blocked") or extinguish_line.begins_with("Emergency vent")):
		_fail("extinguish interact produced no HUD feedback (line='%s')" % extinguish_line)
		return

	var hull = playable._active_hull()
	if hull == null or hull.compartments.is_empty():
		_fail("active hull missing/empty"); return
	var cid: String = str(hull.compartments.keys()[0])
	(hull.compartments[cid] as Dictionary)["breach_open"] = true
	playable._build_breach_seal_points()
	if playable.breach_seal_points.is_empty():
		_fail("no seal point built for the forced breach"); return
	var sp = playable.breach_seal_points[0]
	(playable.player as Node3D).global_position = (sp as Node3D).global_position
	sp.set_validation_player_in_range(playable.player)
	sp.try_start(playable.player)
	if not _feedback().begins_with("Seal blocked"):
		_fail("seal_blocked produced no HUD feedback (line='%s')" % _feedback())
		return

	playable.inventory_state.add_item("hull_sealant", 2)
	var mgr: Node = playable.get_audio_manager()
	if mgr == null:
		_fail("audio_manager missing"); return
	mgr.sfx_router.configure({})
	var routed_before: int = int(mgr.sfx_router.get_routed_count(&"sfx.tool.use"))
	(playable.player as Node3D).global_position = (sp as Node3D).global_position
	if not sp.try_start(playable.player):
		_fail("seal try_start failed with sealant in inventory"); return
	sp.advance_channel(10.0)
	if not _feedback().begins_with("Breach sealed"):
		_fail("breach_sealed produced no HUD feedback (line='%s')" % _feedback())
		return
	var routed_after: int = int(mgr.sfx_router.get_routed_count(&"sfx.tool.use"))
	if routed_after <= routed_before:
		_fail("breach_sealed routed no SFX cue"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return

	print("HAZARD FEEDBACK AWAY PASS away=true extinguish_blocked=true seal_blocked=true breach_sealed=true sfx_routed=true")
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
	print("HAZARD FEEDBACK AWAY FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)


func _cleanup(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
