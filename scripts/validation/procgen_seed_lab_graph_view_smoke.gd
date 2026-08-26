extends SceneTree

const ViewScript := preload("res://scripts/procgen/seed_lab/procgen_seed_lab_graph_view.gd")
var _failures: Array[String] = []
var _signal_id: String = ""
var _signal_payload: Dictionary = {}

func _init() -> void:
	_run()

func _run() -> void:
	var view: Control = ViewScript.new()
	view.size = Vector2(1024.0, 768.0)
	view.node_selected.connect(_on_node_selected)
	root.add_child(view)
	var graph := _graph("world")
	if not view.set_graph(graph): _fail("valid graph rejected")
	var baseline: Dictionary = view.layout_snapshot()
	var permuted := _graph("world")
	permuted.nodes.reverse()
	permuted.edges.reverse()
	if not view.set_graph(permuted): _fail("permuted graph rejected")
	if view.layout_snapshot() != baseline: _fail("permutation changed layout")
	if not view.select_node("node_b"): _fail("selection rejected")
	if _signal_id != "node_b" or str(_signal_payload.get("label", "")) != "Beta": _fail("selection payload mismatch")
	if view.selected_node().is_empty(): _fail("selected node missing")
	_signal_id = ""
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(40.0, 40.0)
	view._gui_input(click)
	if _signal_id != "node_a": _fail("mouse selection rejected")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(40.0, 40.0)
	view._gui_input(wheel)
	if float(view.transform_snapshot().zoom) <= 1.0: _fail("mouse zoom rejected")
	view.set_zoom(2.0)
	click.position = Vector2(300.0, 100.0)
	_signal_id = ""
	view._gui_input(click)
	if _signal_id != "node_a": _fail("zoomed mouse selection rejected")
	view.set_zoom(0.5)
	click.position = Vector2(100.0, 50.0)
	_signal_id = ""
	view._gui_input(click)
	if _signal_id != "node_a": _fail("reduced mouse selection rejected")
	var malformed := _graph("world")
	malformed.nodes.append({"id": "node_a", "label": "Duplicate", "kind": "waypoint"})
	if view.set_graph(malformed): _fail("duplicate node accepted")
	malformed = _graph("world")
	malformed.edges[0].to = "missing"
	if view.set_graph(malformed): _fail("dangling edge accepted")
	malformed = _graph("world")
	malformed.nodes[0].unexpected = true
	if view.set_graph(malformed): _fail("unknown key accepted")
	for domain: String in ["world", "mission", "topology", "navigation", "encounter", "item", "creature"]:
		if not view.set_graph(_graph(domain)): _fail("domain rejected: %s" % domain)
	view.set_zoom(99.0)
	view.pan_by(Vector2(99999.0, -99999.0))
	view.queue_redraw()
	await process_frame
	if float(view.transform_snapshot().zoom) != 4.0: _fail("zoom was not clamped")
	var pan: Vector2 = view.transform_snapshot().pan
	if pan != Vector2(4096.0, -4096.0): _fail("pan was not clamped")
	view.clear_graph()
	if not view.layout_snapshot().is_empty(): _fail("clear did not reset layout")
	malformed = _graph("world")
	malformed.nodes[0].erase("label")
	if view.set_graph(malformed): _fail("missing required key accepted")
	malformed = _graph("world")
	malformed.edges.append({"id": "edge_a", "from": "node_b", "to": "node_a", "kind": "route"})
	if view.set_graph(malformed): _fail("duplicate edge accepted")
	malformed = _graph("world")
	for index: int in range(17): malformed.nodes[0].metadata["key_%02d" % index] = index
	if view.set_graph(malformed): _fail("metadata overflow accepted")
	var oversized_nodes: Array[Dictionary] = []
	for index: int in range(257): oversized_nodes.append({"id": "node_%03d" % index, "label": "Node", "kind": "room"})
	malformed = {"domain": "world", "nodes": oversized_nodes, "edges": [], "truncated": false}
	if view.set_graph(malformed): _fail("node cap accepted")
	var oversized_edges: Array[Dictionary] = []
	for index: int in range(513): oversized_edges.append({"id": "edge_%03d" % index, "from": "node_a", "to": "node_b", "kind": "route"})
	malformed = _graph("world")
	malformed.edges = oversized_edges
	if view.set_graph(malformed): _fail("edge cap accepted")
	if _failures.is_empty():
		print("PROCGEN SEED LAB GRAPH VIEW PASS permutation=true malformed_rejected=true selection=true domains=7 clamp=true draw=true")
		quit(0)
	else:
		for failure: String in _failures: print("PROCGEN SEED LAB GRAPH VIEW FAIL %s" % failure)
		quit(1)

func _graph(domain: String) -> Dictionary:
	return {"domain": domain, "truncated": false, "nodes": [
		{"id": "node_b", "label": "Beta", "kind": "room", "metadata": {"weight": 2}},
		{"id": "node_a", "label": "Alpha", "kind": "waypoint"}
	], "edges": [{"id": "edge_a", "from": "node_a", "to": "node_b", "kind": "route"}]}

func _on_node_selected(id: String, payload: Dictionary) -> void:
	_signal_id = id
	_signal_payload = payload

func _fail(message: String) -> void:
	_failures.append(message)
