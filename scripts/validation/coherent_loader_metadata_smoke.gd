extends SceneTree

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_PATH: String = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"

func _initialize() -> void:
	var loader = LoaderScript.new()
	get_root().add_child(loader)
	var loaded: bool = loader.load_from_paths(LAYOUT_PATH, KIT_PATH, GAMEPLAY_PATH)
	if not loaded:
		push_error("COHERENT LOADER METADATA FAIL could not load golden fixture")
		quit(1)
		return
	if not loader.has_method("get_room_center"):
		push_error("COHERENT LOADER METADATA FAIL missing get_room_center")
		quit(1)
		return
	if loader.get_room_role("spine_01") != "main_spine":
		push_error("COHERENT LOADER METADATA FAIL expected spine_01 role main_spine got %s" % loader.get_room_role("spine_01"))
		quit(1)
		return
	if loader.get_room_deck("airlock_01") != 0 or loader.get_room_deck("spine_01") != 1:
		push_error("COHERENT LOADER METADATA FAIL deck mismatch airlock=%d spine=%d" % [loader.get_room_deck("airlock_01"), loader.get_room_deck("spine_01")])
		quit(1)
		return
	if loader.get_critical_path() != ["airlock_01", "corridor_01", "ramp_01", "spine_01", "reactor_01"]:
		push_error("COHERENT LOADER METADATA FAIL critical path mismatch %s" % str(loader.get_critical_path()))
		quit(1)
		return
	if loader.get_blocked_links().size() != 1:
		push_error("COHERENT LOADER METADATA FAIL blocked link count=%d" % loader.get_blocked_links().size())
		quit(1)
		return
	if loader.get_landmark_specs().size() < 2:
		push_error("COHERENT LOADER METADATA FAIL landmark spec count=%d" % loader.get_landmark_specs().size())
		quit(1)
		return
	var center: Vector3 = loader.get_room_center("reactor_01")
	if center == Vector3.INF:
		push_error("COHERENT LOADER METADATA FAIL reactor center unresolved")
		quit(1)
		return
	print("COHERENT LOADER METADATA PASS critical_path=%d blocked_links=%d landmarks=%d" % [loader.get_critical_path().size(), loader.get_blocked_links().size(), loader.get_landmark_specs().size()])
	loader.free()
	quit(0)
