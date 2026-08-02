extends SceneTree

## Task 6: component markers prefer imported prop bindings and retain the primitive fallback.
## Marker: COMPONENT IMPORTED VISUAL PASS imported=true fallback=true primitive=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const PropVisualBindingCatalogScript := preload("res://scripts/systems/prop_visual_binding_catalog.gd")
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
	if playable == null or not bool(playable.get("playable_started")):
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	_validate()


func _validate() -> void:
	finished = true
	var failures: int = 0
	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		_fail("component catalog")
		return
	var bindings = PropVisualBindingCatalogScript.new()
	if not bindings.load_from_path():
		_fail("prop visual binding catalog: %s" % str(bindings.get_errors()))
		return
	failures += _expect(
		not bindings.get_component_binding("reactor_console").is_empty(),
		"reactor console binding resolves",
	)
	failures += _expect(
		bindings.get_component_binding("missing_component").is_empty(),
		"missing component binding is empty",
	)

	var live: Dictionary = playable._active_layout_for_work()
	if live.is_empty():
		_fail("layout")
		return
	var rooms: Array = live.get("rooms", []) as Array
	if rooms.is_empty():
		_fail("rooms")
		return
	var room_id: String = str((rooms[0] as Dictionary).get("id", ""))
	if room_id.is_empty():
		_fail("room id")
		return
	playable.current_ship.built_layout = live

	var placement = ComponentPlacementStateScript.new()
	placement.placed = [_placement_entry(room_id, "reactor_console")]
	playable.component_placement_state = placement
	playable._rebuild_component_markers()
	var marker: Node3D = _first_marker()
	failures += _expect(marker != null, "reactor console marker exists")
	if marker != null:
		failures += _expect(
			str(marker.get_meta("component_id", "")) == "reactor_console",
			"reactor console metadata is preserved",
		)
		failures += _expect(
			str(marker.get_meta("visual_source", "")) == "imported",
			"reactor console uses imported GLB",
		)
		failures += _expect(
			marker.get_node_or_null("ImportedVisual") != null,
			"imported visual child exists",
		)

	placement.placed = [_placement_entry(room_id, "missing_component")]
	playable._rebuild_component_markers()
	marker = _first_marker()
	failures += _expect(marker != null, "missing component marker exists")
	if marker != null:
		failures += _expect(
			str(marker.get_meta("component_id", "")) == "missing_component",
			"missing component metadata is preserved",
		)
		failures += _expect(
			str(marker.get_meta("visual_source", "")) == "fallback",
			"missing component uses fallback metadata",
		)
		failures += _expect(
			marker.get_node_or_null("ImportedVisual") == null,
			"missing component has no imported visual",
		)
		failures += _expect(
			_has_box_mesh_child(marker),
			"missing component retains primitive BoxMesh child",
		)

	if failures > 0:
		print("COMPONENT IMPORTED VISUAL FAIL failures=%d" % failures)
		_dispose_main_node()
		quit(1)
		return
	print("COMPONENT IMPORTED VISUAL PASS imported=true fallback=true primitive=true")
	_dispose_main_node()
	quit(0)


func _placement_entry(room_id: String, component_id: String) -> Dictionary:
	return {
		"component_instance_id": "task6_component",
		"component_id": component_id,
		"room_id": room_id,
		"slot_kind": "wall",
		"slot_index": 0,
		"cell": "(0,0)",
		"condition": 1.0,
		"item_form": component_id,
		"mass": 15.0,
		"linked_system": "power",
		"linked_subcomponent": "reactor_core",
		"mounted": true,
	}


func _first_marker() -> Node3D:
	var markers: Array = playable.get_component_markers_for_validation()
	if markers.is_empty():
		return null
	return markers[0] as Node3D


func _has_box_mesh_child(marker: Node3D) -> bool:
	for child_variant in marker.get_children():
		var child: Node = child_variant as Node
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			return true
	return false


func _find_playable(n: Node):
	if n is PlayableGeneratedShip:
		return n
	for child_variant in n.get_children():
		var found = _find_playable(child_variant as Node)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> int:
	if condition:
		return 0
	print("COMPONENT IMPORTED VISUAL ASSERTION FAILED: %s" % message)
	return 1


func _fail(message: String) -> void:
	print("COMPONENT IMPORTED VISUAL FAIL: %s" % message)
	finished = true
	_dispose_main_node()
	quit(1)


func _dispose_main_node() -> void:
	if is_instance_valid(main_node):
		main_node.free()
	main_node = null
