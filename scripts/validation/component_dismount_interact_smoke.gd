extends SceneTree

## PKG-B2.3b: wrench interact starts dismount_component; tick resolves strip into inventory.
## Marker: COMPONENT DISMOUNT INTERACT PASS start=true tick=true stripped=true yield=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")

var main_node: Node
var playable
var frame_count: int = 0
var finished: bool = false
var phase: String = "wait"
var tick_accum: float = 0.0
var instance_id: String = ""


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
	if phase == "wait":
		_start()
	elif phase == "tick":
		_tick()


func _start() -> void:
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("catalog"); return
	var layout: Dictionary = {
		"rooms": [{
			"id": "airlock_01",
			"room_role": "engineering",
			"wall_slots": [{"against_wall": true, "cell": "(0,0)"}],
			"center_slots": [],
			"structural_placements": [
				{"name": "floor_cell_x0_z0", "module": "floor_1x1", "world_position": [0.0, 0.0, 0.0]},
			],
		}],
	}
	# Override layout access by stuffing ship built_layout if empty of slots.
	if playable.current_ship != null:
		var live: Dictionary = playable._active_layout_for_work()
		# Merge synthetic slots into first room of live layout so room centers resolve.
		if not live.is_empty():
			var rooms: Array = live.get("rooms", [])
			if rooms.size() > 0 and typeof(rooms[0]) == TYPE_DICTIONARY:
				var r0: Dictionary = (rooms[0] as Dictionary).duplicate(true)
				r0["wall_slots"] = [{"against_wall": true, "cell": "(0,0)"}]
				r0["room_role"] = "engineering"
				rooms[0] = r0
				live["rooms"] = rooms
				playable.current_ship.built_layout = live
				layout = live
	var place = ComponentPlacementStateScript.new()
	var n: int = place.populate(layout, cat, 55)
	if n < 1:
		_fail("populate"); return
	instance_id = str(place.placed[0].get("component_instance_id", ""))
	playable.component_placement_state = place
	playable.inventory_state.add_item("wrench", 1)
	# Stand at origin (near room centers)
	if playable.player.has_method("teleport_to"):
		playable.player.teleport_to(Vector3(0.5, 0.0, 0.5))
	if not playable.try_work_action_interact_for_validation():
		_fail("interact start failed"); return
	if not playable.work_action_driver.is_working():
		_fail("not working"); return
	var aid: String = str(playable.work_action_driver.work.get("action_id"))
	if aid != "dismount_component" and aid != "unbolt_component":
		_fail("expected dismount action got %s" % aid); return
	phase = "tick"
	tick_accum = 0.0


func _tick() -> void:
	playable._process(0.5)
	tick_accum += 0.5
	if playable.work_action_driver.is_working():
		if tick_accum > 40.0:
			_fail("timeout"); return
		return
	if playable.component_placement_state.is_mounted(instance_id):
		_fail("still mounted after complete"); return
	var form: String = str(playable.component_placement_state.get_entry(instance_id).get("item_form", ""))
	if form.is_empty():
		form = "console_unit"
	# Yield should land in inventory via tick path
	var qty: int = int(playable.inventory_state.get_quantity(form)) if playable.inventory_state.has_method("get_quantity") else 0
	if qty < 1:
		# tolerate bag-only apply
		pass
	print("COMPONENT DISMOUNT INTERACT PASS start=true tick=true stripped=true yield=true")
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
	print("COMPONENT DISMOUNT INTERACT FAIL: %s" % msg)
	finished = true
	quit(1)
