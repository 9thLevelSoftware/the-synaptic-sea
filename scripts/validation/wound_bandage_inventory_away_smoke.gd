extends SceneTree

## Bandaging a wound consumes bandage_kit with away_from_start true.
## Marker: WOUND BANDAGE INVENTORY AWAY PASS away=true wound=true bandage=true consume=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
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
	playable.wound_state.apply_wound({
		"kind": "laceration",
		"body_part": "arm",
		"severity": 0.5,
	})
	playable.inventory_state.add_item("bandage_kit", 1)
	var before: int = int(playable.inventory_state.get_quantity("bandage_kit"))
	var res: Dictionary = playable.bandage_wound_with_inventory_for_validation()
	if not bool(res.get("ok", false)):
		_fail("bandage %s" % str(res)); return
	var after: int = int(playable.inventory_state.get_quantity("bandage_kit"))
	if after != before - 1:
		_fail("consume %d -> %d" % [before, after]); return
	var wid: String = playable.wounds_panel.get_selected_wound_id()
	var entry: Dictionary = playable.wound_state.get_wound(wid)
	if not bool(entry.get("bandaged", false)):
		_fail("not bandaged"); return
	if bool(playable.bandage_wound_with_inventory_for_validation().get("ok", true)):
		playable.wound_state.apply_wound({
			"kind": "puncture",
			"body_part": "leg",
			"severity": 0.4,
		})
		var res2: Dictionary = playable.bandage_wound_with_inventory_for_validation()
		if bool(res2.get("ok", false)):
			_fail("should fail without kit"); return
	if not bool(playable.away_from_start):
		_fail("away cleared"); return
	print("WOUND BANDAGE INVENTORY AWAY PASS away=true wound=true bandage=true consume=true")
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
	print("WOUND BANDAGE INVENTORY AWAY FAIL: %s" % msg)
	finished = true
	quit(1)
