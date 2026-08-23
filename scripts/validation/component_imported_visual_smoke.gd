extends SceneTree

## PKG-B2.3 / Task6: the visual component smoke must use the authoritative catalog
## before injecting a catalog component into the live placement state.
## Marker: COMPONENT IMPORTED VISUAL PASS catalog=true reactor_console=true usable=true visual=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 240
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")

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
	# The live playable owns the authoritative catalog. Reload it and assert the
	# named component before constructing the hand-authored placement entry below.
	var catalog = playable.component_catalog
	if catalog == null or not catalog.has_method("load_default"):
		_fail("authoritative catalog unavailable"); return
	if not catalog.load_default():
		_fail("authoritative catalog load"); return
	if not catalog.has_method("has_component") or not catalog.has_component("reactor_console"):
		_fail("authoritative catalog missing reactor_console"); return
	if not catalog.has_method("get_component"):
		_fail("catalog component lookup unavailable"); return
	var definition: Dictionary = catalog.get_component("reactor_console")
	if definition.is_empty():
		_fail("reactor_console definition empty"); return
	if str(definition.get("item_form", "")) != "reactor_console":
		_fail("reactor_console item form unusable"); return
	if float(definition.get("mass", 0.0)) <= 0.0 or str(definition.get("slot", "")) != "wall":
		_fail("reactor_console definition unusable"); return
	if catalog.component_id_for_item_form("reactor_console") != "reactor_console":
		_fail("reactor_console reverse lookup unusable"); return

	var layout: Dictionary = playable._active_layout_for_work()
	var rooms: Array = layout.get("rooms", []) if typeof(layout.get("rooms", [])) == TYPE_ARRAY else []
	var room_id: String = "validation_room"
	if not rooms.is_empty() and typeof(rooms[0]) == TYPE_DICTIONARY:
		room_id = str((rooms[0] as Dictionary).get("id", room_id))

	# Manual injection is deliberately after the catalog assertions above. The
	# entry uses the catalog definition rather than a second hard-coded payload.
	var placement = ComponentPlacementStateScript.new()
	placement.placed = [{
		"component_instance_id": "catalog_reactor_console",
		"component_id": "reactor_console",
		"item_form": str(definition.get("item_form", "")),
		"mass": float(definition.get("mass", 0.0)),
		"room_id": room_id,
		"slot_kind": "wall",
		"slot_index": 0,
		"mounted": true,
	}]
	playable.component_placement_state = placement
	playable._rebuild_component_markers()

	var markers: Array = playable.get_component_markers_for_validation()
	if markers.size() != 1:
		_fail("expected one injected visual marker got %d" % markers.size()); return
	var marker: Node = markers[0] as Node
	if str(marker.get_meta("component_id", "")) != "reactor_console":
		_fail("visual marker component id"); return
	var has_visual: bool = false
	for child in marker.get_children():
		if child is MeshInstance3D:
			has_visual = true
			break
	if not has_visual:
		_fail("reactor_console visual missing"); return

	print("COMPONENT IMPORTED VISUAL PASS catalog=true reactor_console=true usable=true visual=true")
	quit(0)


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for c in n.get_children():
		var found = _find_playable(c)
		if found != null:
			return found
	return null


func _fail(msg: String) -> void:
	print("COMPONENT IMPORTED VISUAL FAIL: %s" % msg)
	finished = true
	quit(1)
