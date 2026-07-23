extends SceneTree

## Over-budget ship-mod state unpowers hub crafting stations on recompute.
## Marker: SHIP MOD OVERBUDGET POWER PASS over=true unpowered=true ok=true

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
	# Force over-budget by stuffing installed rows without going through can_install.
	playable.ship_modification_state.installed = [{
		"slot_id": "x0", "component_id": "machinery_block", "item_form": "machinery_block",
		"power_draw": 9999.0, "mass": 1.0, "source_ship": "test", "plating": false,
	}]
	if playable.ship_modification_state.is_power_budget_ok():
		_fail("expected over budget"); return
	# Drive recompute that applies station power.
	if playable.has_method("_recompute_expanded_ship_systems"):
		playable._recompute_expanded_ship_systems(0.016)
	var st = playable.crafting_state.get_or_create_station("fabricator")
	if bool(st.powered):
		_fail("fabricator should be unpowered when ship-mod over budget"); return
	# Clear over-budget and recompute — stations should follow grid again.
	playable.ship_modification_state.installed.clear()
	if playable.has_method("_recompute_expanded_ship_systems"):
		playable._recompute_expanded_ship_systems(0.016)
	# Power may still be false if grid allocation is zero; only assert over-budget path bit the teeth.
	print("SHIP MOD OVERBUDGET POWER PASS over=true unpowered=true ok=true")
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
	print("SHIP MOD OVERBUDGET POWER FAIL: %s" % msg)
	finished = true
	quit(1)
