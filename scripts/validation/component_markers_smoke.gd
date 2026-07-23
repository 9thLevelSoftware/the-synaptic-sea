extends SceneTree

## PKG-B2.3: mounted component placement rebuilds scene placeholder markers.
## Marker: COMPONENT MARKERS PASS wired=true count=true rebuild=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")

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
	r0["wall_slots"] = [
		{"against_wall": true, "cell": "(0,0)"},
		{"against_wall": true, "cell": "(0,1)"},
	]
	r0["room_role"] = "engineering"
	rooms[0] = r0
	live["rooms"] = rooms
	playable.current_ship.built_layout = live
	var place = ComponentPlacementStateScript.new()
	if place.populate(live, cat, 12) < 1:
		_fail("populate"); return
	playable.component_placement_state = place
	playable._rebuild_component_markers()
	var markers: Array = playable.get_component_markers_for_validation()
	var mounted_n: int = 0
	for e in place.placed:
		if typeof(e) == TYPE_DICTIONARY and bool((e as Dictionary).get("mounted", true)):
			mounted_n += 1
	if markers.size() != mounted_n:
		_fail("marker count %d != mounted %d" % [markers.size(), mounted_n]); return
	# Dismount one and rebuild
	var mid: String = str(place.placed[0].get("component_instance_id", ""))
	place.dismount(mid)
	playable._rebuild_component_markers()
	markers = playable.get_component_markers_for_validation()
	if markers.size() != mounted_n - 1:
		_fail("rebuild after dismount expected %d got %d" % [mounted_n - 1, markers.size()]); return
	print("COMPONENT MARKERS PASS wired=true count=true rebuild=true")
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
	print("COMPONENT MARKERS FAIL: %s" % msg)
	finished = true
	quit(1)
