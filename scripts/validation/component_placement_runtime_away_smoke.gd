extends SceneTree

## PKG-B2.3/D6.1: ComponentPlacementState on playable — populate or restore sparse pack.
## Marker: COMPONENT PLACEMENT RUNTIME AWAY PASS wired=true populate_or_empty=true round_trip=true

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
	playable.away_from_start = true
	if playable.get_component_placement_state_for_validation() == null:
		_fail("component_placement_state not wired"); return
	var place = playable.get_component_placement_state_for_validation()
	# Golden hub may have zero slots — still OK. Force populate with synthetic slots.
	var layout: Dictionary = {
		"rooms": [{
			"id": "eng_rt",
			"room_role": "engineering",
			"wall_slots": [{"against_wall": true, "cell": "(0,0)"}],
			"center_slots": [],
		}],
	}
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("catalog"); return
	var forced = ComponentPlacementStateScript.new()
	var n: int = forced.populate(layout, cat, 99)
	if n < 1:
		_fail("synthetic populate failed"); return
	# Round-trip via ShipInstance sparse pack (D6.1 path).
	if playable.current_ship == null:
		_fail("current_ship"); return
	playable.current_ship.component_placement_summary = forced.get_summary()
	playable.component_placement_state = null
	playable._restore_or_populate_component_placement_for_current_ship()
	var restored = playable.get_component_placement_state_for_validation()
	if restored == null or restored.placed.size() != forced.placed.size():
		_fail("restore size mismatch"); return
	var first_id: String = str(forced.placed[0].get("component_instance_id", ""))
	if not restored.is_mounted(first_id):
		_fail("mounted state lost on restore"); return
	# Dismount + leave flush
	restored.dismount(first_id)
	playable._sync_current_ship_pillar_summaries()
	if playable.current_ship.component_placement_summary.is_empty():
		_fail("flush should keep non-empty placement pack"); return
	playable.component_placement_state = null
	playable._restore_or_populate_component_placement_for_current_ship()
	var again = playable.get_component_placement_state_for_validation()
	if again.is_mounted(first_id):
		_fail("dismount should survive leave/revisit pack"); return

	if playable != null and not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("COMPONENT PLACEMENT RUNTIME AWAY PASS away=true wired=true populate_or_empty=true round_trip=true")
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
	print("COMPONENT PLACEMENT RUNTIME AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
