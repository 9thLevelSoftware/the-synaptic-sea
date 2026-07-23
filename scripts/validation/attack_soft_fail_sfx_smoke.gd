extends SceneTree

## Attack soft-fail (non dry-fire) routes deny SFX via UI_PANEL_CLOSE.
## Marker: ATTACK SOFT FAIL SFX PASS soft_fail=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const TIMEOUT_FRAMES: int = 240

var main_node: Node
var playable
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
	if playable == null or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()


func _validate() -> void:
	finished = true
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	if playable.threat_manager == null:
		_fail("threat"); return
	# Force attack path to return a soft-fail reason other than dry-fire.
	# attack_with_weapon with no threats / cooldown typically returns out_of_range or similar.
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before_deny: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var before_tool: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	var before_hit: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_HIT))
	var result: Dictionary = playable._attack_with_equipped_weapon()
	var after_deny: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	var after_tool: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	var after_hit: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_COMBAT_HIT))
	# If the swing hit something (ok or phantom), that's fine but not this smoke's path.
	if bool(result.get("ok", false)) or after_hit > before_hit:
		# Retry with threats cleared to force soft fail.
		if playable.threat_manager != null:
			playable.threat_manager.threats.clear()
		mgr.sfx_router.configure({})
		before_deny = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
		before_tool = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
		result = playable._attack_with_equipped_weapon()
		after_deny = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
		after_tool = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	var reason: String = str(result.get("reason", ""))
	if bool(result.get("ok", false)):
		_fail("expected soft-fail attack result=%s" % str(result)); return
	if reason in ["empty_magazine", "no_ammo", "reloading"]:
		if after_tool <= before_tool:
			_fail("dry-fire tool sfx missing reason=%s" % reason); return
	else:
		if after_deny <= before_deny:
			_fail("soft-fail deny sfx missing reason=%s result=%s" % [reason, str(result)]); return

	print("ATTACK SOFT FAIL SFX PASS soft_fail=true sfx=true")
	quit(0)


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var f = _find_playable(c)
		if f != null:
			return f
	return null


func _fail(msg: String) -> void:
	print("ATTACK SOFT FAIL SFX FAIL: %s" % msg)
	finished = true
	quit(1)
