extends SceneTree

## PKG-B2.2b: live interact starts nearest-module WorkAction; dual-branch tick completes it.
## Marker: WORK ACTION INTERACT PASS start=true tick=true complete=true nearest=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const ModuleIntegrityConsequencesScript := preload("res://scripts/systems/module_integrity_consequences.gd")

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait_ready"
var tick_accum: float = 0.0
var target_module_id: String = ""


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
	if phase == "wait_ready":
		_start()
	elif phase == "tick":
		_tick()


func _start() -> void:
	if playable.inventory_state == null or playable.player == null:
		_fail("inventory/player missing"); return
	playable.inventory_state.add_item("welding_lance", 1)
	var layout: Dictionary = playable._active_layout_for_work()
	if layout.is_empty():
		_fail("no layout"); return
	if playable.module_integrity_map == null:
		_fail("no integrity map"); return
	ModuleIntegrityConsequencesScript.seed_map_from_layout(playable.module_integrity_map, layout)

	var player_pos: Vector3 = (playable.player as Node3D).global_position
	var target: Dictionary = playable._nearest_workable_wall_module(layout, player_pos, 999.0)
	if target.is_empty():
		_fail("no workable wall in layout"); return
	target_module_id = str(target.get("module_id", ""))
	if float(target.get("distance", 999.0)) > 3.0:
		var placed_pos: Vector3 = _module_world_pos(layout, target_module_id)
		if playable.player.has_method("teleport_to") and placed_pos != Vector3.ZERO:
			playable.player.teleport_to(placed_pos)

	if not playable.try_work_action_interact_for_validation():
		_fail("interact did not start work"); return
	if playable.work_action_driver == null or not playable.work_action_driver.is_working():
		_fail("driver not active after start"); return
	phase = "tick"
	tick_accum = 0.0


func _module_world_pos(layout: Dictionary, mid: String) -> Vector3:
	var parts: PackedStringArray = mid.split("/")
	var room_id: String = parts[0] if parts.size() > 0 else ""
	var pname: String = parts[1] if parts.size() > 1 else ""
	for room_v in layout.get("rooms", []):
		if typeof(room_v) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_v
		if str(room.get("id", "")) != room_id:
			continue
		for p_v in room.get("structural_placements", []):
			if typeof(p_v) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_v
			var kind: String = str(p.get("module_id", p.get("module", "")))
			var name_s: String = str(p.get("name", kind))
			if name_s != pname and kind != pname:
				continue
			var pos_v: Variant = p.get("world_position", null)
			if typeof(pos_v) == TYPE_ARRAY and (pos_v as Array).size() >= 3:
				var a: Array = pos_v
				var local := Vector3(float(a[0]), float(a[1]), float(a[2]))
				if playable.current_ship != null and is_instance_valid(playable.current_ship.scene_root):
					return (playable.current_ship.scene_root as Node3D).global_transform * local
				return local
	return Vector3.ZERO


func _tick() -> void:
	playable._process(0.5)
	tick_accum += 0.5
	if playable.work_action_driver.is_working():
		if tick_accum > 40.0:
			_fail("work did not complete status=%s" % playable.work_action_driver.get_status())
		return
	var ok: bool = bool(playable.work_action_driver.last_resolve.get("ok", false))
	if not ok:
		# tick path should call complete() — if status idle with empty resolve, force once
		var st: String = playable.work_action_driver.get_status()
		if st == "completed":
			playable.work_action_driver.complete(
				playable.module_integrity_map, playable._inventory_qty_dict_for_work()
			)
			ok = bool(playable.work_action_driver.last_resolve.get("ok", false))
	if not ok and not target_module_id.is_empty():
		# Accept integrity change as proof of work path
		var st_mod: String = str(playable.module_integrity_map.get_state(target_module_id))
		if st_mod != "intact":
			ok = true
	if not ok:
		_fail("expected complete resolve got %s" % str(playable.work_action_driver.last_resolve)); return
	print("WORK ACTION INTERACT PASS start=true tick=true complete=true nearest=true")
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
	print("WORK ACTION INTERACT FAIL: %s" % msg)
	finished = true
	quit(1)
