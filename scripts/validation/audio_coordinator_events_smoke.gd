extends SceneTree

## REQ-AU-001 coordinator-side audio event coupling smoke.
##
## Proves that _refresh_audio_state emits the four hazard/vitals SFX events
## and drives COMBAT music via threat_manager.has_combat_engagement():
##
##   SFX_FIRE_CRACKLE  — when any compartment is burning
##   SFX_ARC_ZAP       — when electrical_arc_state is ARCING
##   SFX_SUIT_BREATH   — when vitals_critical (oxygen == 0 or health < 25)
##   UI_VITALS_LOW     — exactly once per rising edge into vitals_critical
##   combat music      — music_state == COMBAT when threat_manager.combat_engaged
##
## Pass marker:
##   AUDIO COORDINATOR EVENTS PASS fire=true arc=true breath=true vitals_low_edge=true combat_music=true
##
## Headless:
##   <GODOT> --headless --path "C:/Users/dasbl/Documents/The Synaptic Sea"
##     --script res://scripts/validation/audio_coordinator_events_smoke.gd

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
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready within %d frames" % TIMEOUT_FRAMES)
		return
	_validate()

func _validate() -> void:
	if playable.audio_manager == null:
		_fail("audio_manager is null")
		return
	var mgr: Node = playable.audio_manager

	# -----------------------------------------------------------------------
	# 1. Fire crackle — force a burning compartment and check SFX routed.
	# -----------------------------------------------------------------------
	if playable.fire_suppression_state == null:
		_fail("fire_suppression_state is null")
		return
	# Ignite a smoke-test compartment (ignite() accepts any non-empty id).
	playable.fire_suppression_state.ignite("smoke_test_compartment", 1.0)
	if playable.fire_suppression_state.get_burning_compartments().is_empty():
		_fail("fire_suppression_state.ignite() did not register a burning compartment")
		return
	# Clear router state so cooldowns don't suppress this first emission.
	mgr.sfx_router.configure({})
	var fire_before: int = int(mgr.sfx_router.get_routed_count(&"sfx.fire.crackle"))
	playable._refresh_audio_state(false, 0.1)
	var fire_after: int = int(mgr.sfx_router.get_routed_count(&"sfx.fire.crackle"))
	var fire_ok: bool = fire_after > fire_before
	if not fire_ok:
		_fail("SFX_FIRE_CRACKLE was not routed when a compartment is burning (before=%d after=%d)" % [fire_before, fire_after])
		return

	# -----------------------------------------------------------------------
	# 2. Arc zap — force ARCING phase and check SFX routed.
	# -----------------------------------------------------------------------
	if playable.electrical_arc_state == null:
		_fail("electrical_arc_state is null")
		return
	playable.electrical_arc_state.phase = ElectricalArcState.Phase.ARCING
	mgr.sfx_router.configure({})
	var arc_before: int = int(mgr.sfx_router.get_routed_count(&"sfx.arc.zap"))
	playable._refresh_audio_state(false, 0.1)
	var arc_after: int = int(mgr.sfx_router.get_routed_count(&"sfx.arc.zap"))
	var arc_ok: bool = arc_after > arc_before
	if not arc_ok:
		_fail("SFX_ARC_ZAP was not routed when arc phase is ARCING (before=%d after=%d)" % [arc_before, arc_after])
		return

	# -----------------------------------------------------------------------
	# 3. Suit breath + vitals-low edge — drive vitals_critical via oxygen = 0.
	# -----------------------------------------------------------------------
	if playable.vitals_model == null:
		_fail("vitals_model is null")
		return
	# Ensure vitals_model has get_vitals_summary (sanity-check the fix).
	if not playable.vitals_model.has_method("get_vitals_summary"):
		_fail("vitals_model.get_vitals_summary() missing — fix not applied")
		return
	# Feed oxygen = 0 so vitals_critical becomes true.
	playable.vitals_model.apply_oxygen_summary({"oxygen": 0, "max_oxygen": 100})
	# Reset edge state and router so the rising edge fires cleanly.
	playable._prev_vitals_critical = false
	mgr.sfx_router.configure({})
	var breath_before: int = int(mgr.sfx_router.get_routed_count(&"sfx.suit.breath"))
	var vitals_low_before: int = int(mgr.sfx_router.get_routed_count(&"ui.vitals.low"))
	playable._refresh_audio_state(false, 0.1)
	var breath_after: int = int(mgr.sfx_router.get_routed_count(&"sfx.suit.breath"))
	var vitals_low_after: int = int(mgr.sfx_router.get_routed_count(&"ui.vitals.low"))
	var breath_ok: bool = breath_after > breath_before
	var vitals_low_edge_ok: bool = vitals_low_after > vitals_low_before
	if not breath_ok:
		_fail("SFX_SUIT_BREATH was not routed when vitals_critical (before=%d after=%d)" % [breath_before, breath_after])
		return
	if not vitals_low_edge_ok:
		_fail("UI_VITALS_LOW was not routed on rising edge into vitals_critical (before=%d after=%d)" % [vitals_low_before, vitals_low_after])
		return
	# Call again with vitals still critical — UI_VITALS_LOW must NOT fire a second time
	# (edge detection via _prev_vitals_critical should suppress it; cooldown also guards).
	var vitals_low_count_after_second_call: int = int(mgr.sfx_router.get_routed_count(&"ui.vitals.low"))
	playable._refresh_audio_state(false, 0.1)
	var vitals_low_count_final: int = int(mgr.sfx_router.get_routed_count(&"ui.vitals.low"))
	# vitals_low_count_final may equal vitals_low_count_after_second_call either due to
	# edge detection (_prev_vitals_critical=true) or due to the 4-second cooldown.
	# Both are correct behaviour; the smoke only verifies no extra emission occurred.
	if vitals_low_count_final != vitals_low_count_after_second_call:
		_fail("UI_VITALS_LOW fired on second consecutive critical frame — edge detection broken (count=%d->%d)" % [vitals_low_count_after_second_call, vitals_low_count_final])
		return

	# -----------------------------------------------------------------------
	# 4. Combat music — set threat_manager.combat_engaged and verify state.
	# -----------------------------------------------------------------------
	if playable.threat_manager == null:
		_fail("threat_manager is null")
		return
	playable.threat_manager.combat_engaged = true
	if not playable.threat_manager.has_combat_engagement():
		_fail("has_combat_engagement() returned false after combat_engaged=true")
		return
	# Reset vitals_critical to prevent CRITICAL from overriding COMBAT in the music FSM.
	playable.vitals_model.apply_oxygen_summary({"oxygen": 100, "max_oxygen": 100})
	playable.vitals_model.apply_vitals_summary({"health": 100.0, "max_health": 100.0})
	mgr.sfx_router.configure({})
	playable._refresh_audio_state(false, 0.1)
	var music_state_after: String = String(mgr.music_state.get_state())
	var combat_music_ok: bool = music_state_after == "COMBAT"
	if not combat_music_ok:
		_fail("music_state should be COMBAT with combat_engaged=true, got %s" % music_state_after)
		return

	# -----------------------------------------------------------------------
	# All assertions passed.
	# -----------------------------------------------------------------------
	finished = true
	print("AUDIO COORDINATOR EVENTS PASS fire=%s arc=%s breath=%s vitals_low_edge=%s combat_music=%s" % [
		str(fire_ok).to_lower(),
		str(arc_ok).to_lower(),
		str(breath_ok).to_lower(),
		str(vitals_low_edge_ok).to_lower(),
		str(combat_music_ok).to_lower(),
	])
	_cleanup_and_quit(0)

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
	push_error("AUDIO COORDINATOR EVENTS FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
