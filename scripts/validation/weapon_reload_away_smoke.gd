extends SceneTree

## Weapon reload success SFX works with away_from_start true.
## Marker: WEAPON RELOAD AWAY PASS away=true reload=true sfx=true

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
	playable.away_from_start = true
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	if playable.ammo_state == null or playable.threat_manager == null:
		_fail("ammo/threat"); return
	var weapon_id: String = "sidearm"
	if playable.threat_manager.weapon_definitions is Dictionary:
		for k in playable.threat_manager.weapon_definitions.keys():
			var w: Dictionary = playable.threat_manager.weapon_definitions[k]
			if typeof(w) == TYPE_DICTIONARY and not str(w.get("ammo_item_id", "")).is_empty():
				weapon_id = str(k)
				break
	var weapon: Dictionary = playable.threat_manager.weapon_definitions.get(weapon_id, {}) if playable.threat_manager.weapon_definitions.get(weapon_id, {}) is Dictionary else {}
	var ammo_item: String = str(weapon.get("ammo_item_id", "pistol_rounds"))
	if playable.inventory_state.get_quantity(weapon_id) < 1:
		playable.inventory_state.add_item(weapon_id, 1)
	if playable.inventory_state.get_quantity(ammo_item) < 10:
		playable.inventory_state.add_item(ammo_item, 20)
	if playable.has_method("_equip_from_inventory"):
		playable._equip_from_inventory(weapon_id, false)
	var mgr: Node = playable.audio_manager
	mgr.sfx_router.configure({})
	var before: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	playable._begin_weapon_reload()
	var after: int = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if after <= before:
		if playable.ammo_state.has_method("apply_summary"):
			playable.ammo_state.apply_summary({
				"weapon_id": weapon_id,
				"magazine": 0,
				"magazine_size": int(weapon.get("magazine_size", 6)),
			})
		mgr.sfx_router.configure({})
		before = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
		playable._begin_weapon_reload()
		after = int(mgr.sfx_router.get_routed_count(AudioEventSeamScript.SFX_TOOL_USE))
	if after <= before:
		_fail("reload sfx missing away weapon=%s" % weapon_id); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WEAPON RELOAD AWAY PASS away=true reload=true sfx=true")
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
	print("WEAPON RELOAD AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
