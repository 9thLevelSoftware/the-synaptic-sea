extends SceneTree

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_PATH: String = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"

func _initialize() -> void:
	var loader = LoaderScript.new()
	get_root().add_child(loader)
	if not loader.load_from_paths(LAYOUT_PATH, KIT_PATH, GAMEPLAY_PATH):
		push_error("COHERENT RUNTIME LOADER FAIL could not load fixture")
		quit(1)
		return
	if not loader.has_method("get_landmark_nodes"):
		push_error("COHERENT RUNTIME LOADER FAIL missing get_landmark_nodes")
		quit(1)
		return
	var landmark_count: int = loader.get_landmark_nodes().size()
	var blocked_count: int = loader.get_blocked_route_nodes().size()
	var transition_count: int = loader.get_visible_vertical_transition_nodes().size()
	if landmark_count < 2:
		push_error("COHERENT RUNTIME LOADER FAIL landmark nodes=%d" % landmark_count)
		quit(1)
		return
	if blocked_count != 1:
		push_error("COHERENT RUNTIME LOADER FAIL blocked route nodes=%d" % blocked_count)
		quit(1)
		return
	if transition_count != 1:
		push_error("COHERENT RUNTIME LOADER FAIL visible vertical transitions=%d" % transition_count)
		quit(1)
		return
	if loader.count_collision_shapes() <= 0:
		push_error("COHERENT RUNTIME LOADER FAIL collision_shapes=0")
		quit(1)
		return
	print("COHERENT RUNTIME LOADER PASS collision_shapes=%d landmarks=%d blocked_routes=%d visible_transitions=%d" % [loader.count_collision_shapes(), landmark_count, blocked_count, transition_count])
	loader.free()
	quit(0)
