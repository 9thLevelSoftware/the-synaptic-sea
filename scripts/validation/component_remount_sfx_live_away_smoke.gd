extends SceneTree

## Live remount WorkAction stamps mount SFX and routes via audio_manager.
## Marker: COMPONENT REMOUNT SFX LIVE AWAY PASS remount=true sfx=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const AudioEventSeamScript := preload("res://scripts/audio/audio_event_seam.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait"
var tick_accum: float = 0.0
var instance_id: String = ""
var item_form: String = ""
var sfx_before: int = 0


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
	match phase:
		"wait":
			_setup()
		"dismount_tick":
			_tick_until("after_dismount")
		"after_dismount":
			_start_remount()
		"remount_tick":
			_tick_until("done")
		"done":
			_finish()


func _setup() -> void:
	playable.away_from_start = true
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("catalog"); return
	var live: Dictionary = playable._active_layout_for_work()
	if live.is_empty():
		_fail("layout"); return
	var rooms: Array = live.get("rooms", [])
	if rooms.is_empty():
		_fail("rooms"); return
	var r0: Dictionary = (rooms[0] as Dictionary).duplicate(true)
	r0["wall_slots"] = [{"against_wall": true, "cell": "(0,0)"}]
	r0["room_role"] = "engineering"
	rooms[0] = r0
	live["rooms"] = rooms
	playable.current_ship.built_layout = live
	var place = ComponentPlacementStateScript.new()
	if place.populate(live, cat, 77) < 1:
		_fail("populate"); return
	instance_id = str(place.placed[0].get("component_instance_id", ""))
	item_form = str(place.placed[0].get("item_form", ""))
	playable.component_placement_state = place
	playable.inventory_state.add_item("wrench", 1)
	playable.vitals_state.stamina = 100.0
	playable._work_requires_hold = false
	if playable.player.has_method("teleport_to"):
		playable.player.teleport_to(Vector3(0.5, 0.0, 0.5))
	if not playable.try_work_action_interact_for_validation():
		_fail("dismount start"); return
	instance_id = str(playable.work_action_driver.work.get("target_id"))
	var entry0: Dictionary = playable.component_placement_state.get_entry(instance_id)
	item_form = str(entry0.get("item_form", item_form))
	phase = "dismount_tick"
	tick_accum = 0.0


func _tick_until(next_phase: String) -> void:
	playable.away_from_start = true
	playable._process(0.5)
	tick_accum += 0.5
	if playable.work_action_driver.is_working():
		if tick_accum > 40.0:
			_fail("timeout %s" % next_phase)
		return
	phase = next_phase
	tick_accum = 0.0


func _start_remount() -> void:
	playable.away_from_start = true
	if playable.inventory_state.get_quantity(item_form) < 1:
		playable.inventory_state.add_item(item_form, 1)
	playable.vitals_state.stamina = 100.0
	if playable.audio_manager == null or playable.audio_manager.sfx_router == null:
		_fail("audio"); return
	playable.audio_manager.sfx_router.configure({})
	sfx_before = int(playable.audio_manager.sfx_router.get_routed_count(AudioEventSeamScript.SFX_WORK_MOUNT))
	if not playable.try_work_action_interact_for_validation():
		_fail("remount start"); return
	var aid: String = str(playable.work_action_driver.work.get("action_id"))
	if aid != "mount_component":
		_fail("expected mount got %s" % aid); return
	phase = "remount_tick"
	tick_accum = 0.0


func _finish() -> void:
	var after: int = int(playable.audio_manager.sfx_router.get_routed_count(AudioEventSeamScript.SFX_WORK_MOUNT))
	if after <= sfx_before:
		var lr: Dictionary = playable.work_action_driver.last_resolve if playable.work_action_driver != null else {}
		_fail("mount sfx not routed before=%d after=%d last=%s" % [sfx_before, after, str(lr.get("audio_event", ""))]); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("COMPONENT REMOUNT SFX LIVE AWAY PASS away=true remount=true sfx=true")
	finished = true
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
	print("COMPONENT REMOUNT SFX LIVE AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
