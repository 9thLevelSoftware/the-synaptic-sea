extends SceneTree

## PKG-D6.2: pure SeaGraph — routes, biome bands, fuel/food travel costs.
## Marker: SEA GRAPH PASS nodes=true route=true cost=true biomes=true extract=true

const SeaGraphScript := preload("res://scripts/systems/sea_graph.gd")


func _initialize() -> void:
	var graph = SeaGraphScript.new()
	graph.configure({"world_seed": 42, "fuel_per_unit": 0.1, "food_per_unit": 0.05})

	var markers: Array = [
		{"marker_id": "m_a", "position": [30.0, 0.0, 0.0], "ship_type": "shuttle"},
		{"marker_id": "m_b", "position": [80.0, 0.0, 40.0], "ship_type": "freighter"},
		{"marker_id": "m_c", "position": [150.0, 0.0, 150.0], "ship_type": "derelict_hauler"},
	]
	var n: int = graph.build_from_markers(markers, Vector3.ZERO, Vector3(200, 0, 200))
	if n < 5:
		_fail("expected hub+extract+3 markers, got %d" % n); return
	if not graph.has_node(SeaGraphScript.HUB_NODE_ID):
		_fail("hub missing"); return
	if not graph.has_node(SeaGraphScript.EXTRACTION_NODE_ID):
		_fail("extraction missing"); return
	if graph.edge_count() < 3:
		_fail("expected edges, got %d" % graph.edge_count()); return

	# Biome bands by distance
	var na: Dictionary = graph.get_node("m_a")
	var nc: Dictionary = graph.get_node("m_c")
	if int(na.get("biome_band", -1)) >= int(nc.get("biome_band", -1)):
		_fail("farther marker should be deeper biome band"); return
	if SeaGraphScript.biome_band_name(0) != "near_field":
		_fail("band name"); return

	# Route hub -> extraction consumes resources
	var route: Dictionary = graph.route_to_extraction()
	if not bool(route.get("ok", false)):
		_fail("route to extraction failed: %s" % str(route.get("reason", ""))); return
	var path: Array = route.get("path", [])
	if path.is_empty() or str(path[0]) != SeaGraphScript.HUB_NODE_ID:
		_fail("path should start at hub"); return
	if str(path[path.size() - 1]) != SeaGraphScript.EXTRACTION_NODE_ID:
		_fail("path should end at extraction"); return
	if float(route.get("fuel", 0.0)) <= 0.0 or float(route.get("food", 0.0)) <= 0.0:
		_fail("travel must cost fuel and food"); return

	var resources: Dictionary = {"fuel": 1000.0, "food": 1000.0}
	var pay: Dictionary = graph.apply_travel_cost(resources, route)
	if not bool(pay.get("ok", false)):
		_fail("apply_travel_cost: %s" % str(pay.get("reason", ""))); return
	if float(resources.get("fuel", 0.0)) >= 1000.0:
		_fail("fuel should decrease"); return
	if float(resources.get("food", 0.0)) >= 1000.0:
		_fail("food should decrease"); return

	# Insufficient fuel rejected
	var poor: Dictionary = {"fuel": 0.01, "food": 1000.0}
	var fail: Dictionary = graph.apply_travel_cost(poor, route)
	if bool(fail.get("ok", false)):
		_fail("should reject insufficient fuel"); return
	if str(fail.get("reason", "")) != "insufficient_fuel":
		_fail("expected insufficient_fuel"); return

	# Edge costs present
	var edge: Dictionary = graph.get_edge(SeaGraphScript.HUB_NODE_ID, "m_a")
	if edge.is_empty():
		# may not be direct — use path segments
		if path.size() >= 2:
			edge = graph.get_edge(str(path[0]), str(path[1]))
	if edge.is_empty():
		_fail("expected an edge on the route"); return
	if float(edge.get("fuel_cost", 0.0)) <= 0.0:
		_fail("edge fuel_cost"); return

	# Deterministic world-seed build
	var g2 = SeaGraphScript.new()
	g2.configure({"world_seed": 99})
	var n2: int = g2.build_from_world_seed(99, 1)
	if n2 < 5:
		_fail("world seed build too small %d" % n2); return
	var g3 = SeaGraphScript.new()
	g3.build_from_world_seed(99, 1)
	if g2.node_count() != g3.node_count() or g2.edge_count() != g3.edge_count():
		_fail("world seed determinism"); return
	var r2: Dictionary = g2.route_to_extraction()
	var r3: Dictionary = g3.route_to_extraction()
	if bool(r2.get("ok", false)) != bool(r3.get("ok", false)):
		_fail("route determinism"); return
	if absf(float(r2.get("fuel", 0.0)) - float(r3.get("fuel", 0.0))) > 0.001:
		_fail("fuel determinism"); return

	# Summary round-trip
	var snap: Dictionary = graph.get_summary()
	var g4 = SeaGraphScript.new()
	if not g4.apply_summary(snap):
		_fail("apply_summary"); return
	if g4.node_count() != graph.node_count():
		_fail("round-trip nodes"); return
	var r4: Dictionary = g4.find_route(SeaGraphScript.HUB_NODE_ID, "m_c")
	if not bool(r4.get("ok", false)):
		_fail("round-trip route"); return

	print("SEA GRAPH PASS nodes=true route=true cost=true biomes=true extract=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SEA GRAPH FAIL: %s" % msg)
	quit(1)
