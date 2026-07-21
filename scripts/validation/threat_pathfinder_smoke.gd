extends SceneTree

## ADR-0049: A* pathfinder + step_along_path pure unit tests.
## Marker: THREAT PATHFINDER PASS path=true step=true flee=true

const ShipNavGraphScript := preload("res://scripts/systems/ship_nav_graph.gd")
const ThreatPathfinderScript := preload("res://scripts/systems/threat_pathfinder.gd")

func _initialize() -> void:
	var graph = ShipNavGraphScript.new()
	# Manual 3x1 corridor layout.
	var layout := {
		"cell_size": 4.0,
		"deck_height": 4.0,
		"rooms": [
			{"id": "a", "structural_placements": [
				{"module": "floor_1x1", "world_position": [0.0, 0.0, 0.0]},
				{"module": "floor_1x1", "world_position": [4.0, 0.0, 0.0]},
				{"module": "floor_1x1", "world_position": [8.0, 0.0, 0.0]},
			]},
			{"id": "b", "structural_placements": [
				{"module": "floor_1x1", "world_position": [8.0, 0.0, 4.0]},
			]},
		],
	}
	if graph.build_from_layout(layout) < 4:
		_fail("manual layout build failed")
		return
	var path: Array = ThreatPathfinderScript.find_path(graph, Vector3(0, 0, 0), Vector3(8, 0, 4))
	if path.size() < 3:
		_fail("expected multi-step path, got %d" % path.size())
		return
	# Block direct corridor step 4->8 and require detour via z=4 if connected... 
	# Our graph only connects 8,0 to 8,4; path (0,0)-(4,0)-(8,0)-(8,4) is unique.
	var p0: Vector3 = path[0] as Vector3
	var step: Dictionary = ThreatPathfinderScript.step_along_path(path, 0, p0, 4.0, 0.5)
	var moved: Vector3 = step.get("position", p0) as Vector3
	if moved.distance_to(p0) < 0.1:
		_fail("step_along_path did not advance")
		return
	var flee: Vector3 = ThreatPathfinderScript.farthest_point(graph, Vector3(0, 0, 0), Vector3(0, 0, 0))
	if flee == Vector3.INF:
		_fail("farthest_point failed")
		return
	print("THREAT PATHFINDER PASS path=true step=true flee=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("THREAT PATHFINDER FAIL reason=%s" % reason)
	quit(1)
