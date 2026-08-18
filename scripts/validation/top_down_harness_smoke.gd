extends SceneTree
## Top-down harness smoke test — validates the harness scene renders at expected
## dimensions and the grid math round-trips correctly.
## Run: godot --headless --script res://scripts/validation/top_down_harness_smoke.gd

const GridCoordinateScript = preload("res://scripts/world/grid_coordinate.gd")
const CellOccupancyScript = preload("res://scripts/world/cell_occupancy.gd")

var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	_test_grid_coordinate_roundtrip()
	_test_grid_distance()
	_test_cell_occupancy()
	_test_cell_neighbors()
	_print_results()
	quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS  ", label)
	else:
		_fail_count += 1
		print("  FAIL  ", label)


func _test_grid_coordinate_roundtrip() -> void:
	print("\n--- GridCoordinate roundtrip ---")
	# world_to_grid at tile boundaries
	var g := GridCoordinateScript.world_to_grid(Vector2(0, 0))
	_assert(g == Vector2i(0, 0), "origin maps to (0,0)")

	g = GridCoordinateScript.world_to_grid(Vector2(48, 48))
	_assert(g == Vector2i(1, 1), "(48,48) maps to (1,1)")

	g = GridCoordinateScript.world_to_grid(Vector2(-1, -1))
	_assert(g == Vector2i(-1, -1), "(-1,-1) maps to (-1,-1)")

	g = GridCoordinateScript.world_to_grid(Vector2(47.9, 47.9))
	_assert(g == Vector2i(0, 0), "(47.9,47.9) maps to (0,0)")

	# grid_to_world center roundtrip
	var world := GridCoordinateScript.grid_to_world_center(Vector2i(3, 5))
	var back := GridCoordinateScript.world_to_grid(world)
	_assert(back == Vector2i(3, 5), "center(3,5) roundtrips")

	# grid_to_world gives top-left
	var tl := GridCoordinateScript.grid_to_world(Vector2i(2, 4))
	_assert(tl == Vector2(96, 192), "grid_to_world(2,4) = (96,192)")


func _test_grid_distance() -> void:
	print("\n--- GridCoordinate distance ---")
	var a := Vector2i(0, 0)
	var b := Vector2i(3, 4)
	_assert(GridCoordinateScript.grid_distance(a, b) == 7, "manhattan (0,0)->(3,4) = 7")
	_assert(GridCoordinateScript.grid_distance_chebyshev(a, b) == 4, "chebyshev (0,0)->(3,4) = 4")
	_assert(GridCoordinateScript.grid_distance(a, a) == 0, "manhattan self = 0")


func _test_cell_occupancy() -> void:
	print("\n--- CellOccupancy ---")
	var occ := CellOccupancyScript.new()
	_assert(not occ.is_occupied(Vector2i(5, 5)), "cell starts free")

	occ.occupy(Vector2i(5, 5), &"threat_01")
	_assert(occ.is_occupied(Vector2i(5, 5)), "cell occupied after occupy()")
	_assert(occ.is_walkable(Vector2i(5, 5)) == false, "occupied cell not walkable")
	_assert(occ.entities_at(Vector2i(5, 5)).has(&"threat_01"), "entity id stored")

	occ.release(Vector2i(5, 5), &"threat_01")
	_assert(not occ.is_occupied(Vector2i(5, 5)), "cell free after release()")

	occ.occupy(Vector2i(0, 0), &"a")
	occ.occupy(Vector2i(1, 1), &"b")
	occ.clear()
	_assert(not occ.is_occupied(Vector2i(0, 0)), "clear() empties all")


func _test_cell_neighbors() -> void:
	print("\n--- CellOccupancy neighbors ---")
	var occ := CellOccupancyScript.new()
	occ.occupy(Vector2i(1, 0), &"wall")
	var neighbors := occ.get_walkable_neighbors(Vector2i(0, 0))
	_assert(neighbors.size() == 7, "7 walkable neighbors with one blocked")
	_assert(not neighbors.has(Vector2i(1, 0)), "blocked neighbor excluded")

	var all_free := occ.get_walkable_neighbors(Vector2i(5, 5))
	_assert(all_free.size() == 8, "8 neighbors when all free")


func _print_results() -> void:
	print("\n========================================")
	print("Top-down harness smoke: %d PASS / %d FAIL" % [_pass_count, _fail_count])
	print("========================================")
	if _fail_count > 0:
		print("RESULT: FAIL")
	else:
		print("RESULT: PASS")
