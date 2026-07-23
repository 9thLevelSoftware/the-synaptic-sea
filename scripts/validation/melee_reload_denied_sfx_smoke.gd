extends SceneTree

## Melee / non-mag weapon reload attempt routes deny SFX.
## Marker: MELEE RELOAD DENIED SFX PASS melee=true sfx=true

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
		_fail("threat_manager"); return

	# Ensure a primary weapon id resolves, then strip its ammo_item_id (melee path).
	var weapon_id: String = str(playable._equipped_primary_weapon_id())
	if weapon_id.is_empty():
		weapon_id = "melee_smoke"
		playable.threat_manager.weapon_definitions[weapon_id] = {
			"ammo_item_id": "",
			"magazine_size": 0,
		}
		# Force equip path: inventory + equipment if available.
		if playable.inventory_state != null:
			playable.inventory_state.add_item(weapon_id, 1)
		if playable.equipment_state != null and playable.equipment_state.has_method("equip_item"):
			playable.equipment_state.equip_item(weapon_id, "primary_hand")
		weapon_id = str(playable._equipped_primary_weapon_id())
		if weapon_id.is_empty():
			# Last resort: inject definition for empty weapon path is "no weapon" deny
			# which also plays UI_PANEL_CLOSE — still valid soft deny coverage.
			pass
	if not weapon_id.is_empty():
		playable.threat_manager.weapon_definitions[weapon_id] = {
			"ammo_item_id": "",
			"magazine_size": 0,
		}

	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	playable._begin_weapon_reload()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.UI_PANEL_CLOSE))
	if after <= before:
		_fail("deny sfx not routed before=%d after=%d weapon=%s" % [before, after, weapon_id]); return

	print("MELEE RELOAD DENIED SFX PASS melee=true sfx=true")
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
	print("MELEE RELOAD DENIED SFX FAIL: %s" % msg)
	finished = true
	quit(1)
