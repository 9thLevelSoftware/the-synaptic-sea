extends Control
class_name ProcgenSeedLabGraphView

signal node_selected(id: String, payload: Dictionary)

const DOMAINS: Array[String] = ["world", "mission", "topology", "navigation", "encounter", "item", "creature"]
const MAX_NODES: int = 256
const MAX_EDGES: int = 512
const MAX_METADATA: int = 16
const MAX_METADATA_KEY_BYTES: int = 64
const MAX_METADATA_STRING_BYTES: int = 128
const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 4.0
const MAX_PAN: float = 4096.0
const NODE_W: float = 156.0
const NODE_H: float = 48.0
const LANE_H: float = 112.0
const GAP_X: float = 28.0
const ROOT_KEYS: Array[String] = ["domain", "nodes", "edges", "truncated"]
const NODE_KEYS: Array[String] = ["id", "label", "kind", "metadata"]
const EDGE_KEYS: Array[String] = ["id", "from", "to", "kind", "metadata"]

var _graph: Dictionary = {}
var _layout: Dictionary = {}
var _selected_id: String = ""
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _last_error: String = ""
var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			set_zoom(_zoom * 1.2)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			set_zoom(_zoom / 1.2)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			var hit: String = _hit_test(button.position)
			if not hit.is_empty(): select_node(hit)
			accept_event()
		elif [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT].has(button.button_index):
			_dragging = button.pressed
			_drag_last = button.position
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var motion: InputEventMouseMotion = event
		pan_by(motion.position - _drag_last)
		_drag_last = motion.position
		accept_event()

func set_graph(graph: Dictionary) -> bool:
	_last_error = ""
	if not _validate_graph(graph): return false
	_graph = graph.duplicate(true)
	_layout = _build_layout(_graph)
	_selected_id = ""
	queue_redraw()
	return true

func clear_graph() -> void:
	_graph = {}
	_layout = {}
	_selected_id = ""
	_last_error = ""
	queue_redraw()

func layout_snapshot() -> Dictionary:
	return _layout.duplicate(true)

func select_node(id: String) -> bool:
	if not _layout.has("nodes") or not _layout.nodes.has(id): return false
	_selected_id = id
	var payload: Dictionary = _layout.nodes[id].get("payload", {}).duplicate(true)
	node_selected.emit(id, payload)
	queue_redraw()
	return true

func selected_node() -> Dictionary:
	if _selected_id == "" or not _layout.has("nodes") or not _layout.nodes.has(_selected_id): return {}
	return _layout.nodes[_selected_id].duplicate(true)

func set_zoom(value: float) -> void:
	_zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	queue_redraw()

func pan_by(delta: Vector2) -> void:
	_pan += delta
	_pan.x = clampf(_pan.x, -MAX_PAN, MAX_PAN)
	_pan.y = clampf(_pan.y, -MAX_PAN, MAX_PAN)
	queue_redraw()

func transform_snapshot() -> Dictionary:
	return {"zoom": _zoom, "pan": _pan}

func _hit_test(screen_position: Vector2) -> String:
	if _layout.is_empty() or _zoom <= 0.0: return ""
	var local: Vector2 = (screen_position - Vector2(32.0, 32.0) - _pan) / _zoom
	var order: Array = _layout.get("node_order", []).duplicate()
	order.reverse()
	for id_value: Variant in order:
		var id: String = str(id_value)
		var entry: Dictionary = _layout.nodes.get(id, {})
		if Rect2(Vector2(entry.get("position", Vector2.ZERO)), Vector2(NODE_W, NODE_H)).has_point(local): return id
	return ""

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101722"), true)
	if _layout.is_empty(): return
	var origin := Vector2(32.0, 32.0) + _pan
	for edge: Dictionary in _layout.edges:
		var from_id: String = str(edge.from)
		var to_id: String = str(edge.to)
		if not _layout.nodes.has(from_id) or not _layout.nodes.has(to_id): continue
		var a: Vector2 = origin + Vector2(_layout.nodes[from_id].position) * _zoom + Vector2(NODE_W * _zoom, NODE_H * _zoom * 0.5)
		var b: Vector2 = origin + Vector2(_layout.nodes[to_id].position) * _zoom + Vector2(0.0, NODE_H * _zoom * 0.5)
		draw_line(a, b, Color("65758b"), maxf(1.0, 2.0 * _zoom), true)
	for id: String in _layout.node_order:
		var entry: Dictionary = _layout.nodes[id]
		var pos: Vector2 = origin + Vector2(entry.position) * _zoom
		var rect := Rect2(pos, Vector2(NODE_W, NODE_H) * _zoom)
		var color: Color = _node_color(str(entry.payload.kind))
		if id == _selected_id: color = color.lightened(0.3)
		draw_rect(rect, color, true)
		draw_rect(rect, Color("d9e2ef"), false, maxf(1.0, 1.5 * _zoom))
		var font := ThemeDB.fallback_font
		var label := str(entry.payload.label)
		draw_string(font, pos + Vector2(8.0, minf(29.0, NODE_H - 12.0)) * _zoom, label.left(24), HORIZONTAL_ALIGNMENT_LEFT, -1.0, maxf(10.0, 13.0 * _zoom), Color("f3f7fb"))
	if bool(_graph.truncated):
		draw_rect(Rect2(16.0, size.y - 42.0, maxf(220.0, size.x - 32.0), 28.0), Color("8a5b23"), true)
		draw_string(ThemeDB.fallback_font, Vector2(28.0, size.y - 23.0), "Graph truncated at renderer safety limit", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, Color("fff1cc"))

func _validate_graph(graph: Dictionary) -> bool:
	if not _exact_keys(graph, ROOT_KEYS): return _reject("root_keys")
	if not DOMAINS.has(str(graph.domain)): return _reject("domain")
	if not graph.nodes is Array or not graph.edges is Array: return _reject("collections")
	if graph.nodes.size() > MAX_NODES or graph.edges.size() > MAX_EDGES: return _reject("cap")
	if not graph.truncated is bool: return _reject("truncated")
	var ids: Dictionary = {}
	for node: Variant in graph.nodes:
		if not node is Dictionary or not _exact_keys(node, NODE_KEYS): return _reject("node_shape")
		if not _valid_text(node.id) or not _valid_text(node.label) or not _valid_text(node.kind): return _reject("node_text")
		if ids.has(node.id): return _reject("duplicate_node")
		if not _validate_metadata(node.get("metadata", {})): return _reject("node_metadata")
		ids[node.id] = true
	var edge_ids: Dictionary = {}
	for edge: Variant in graph.edges:
		if not edge is Dictionary or not _exact_keys(edge, EDGE_KEYS): return _reject("edge_shape")
		if not _valid_text(edge.id) or not _valid_text(edge.from) or not _valid_text(edge.to) or not _valid_text(edge.kind): return _reject("edge_text")
		if edge_ids.has(edge.id): return _reject("duplicate_edge")
		if edge.from == edge.to: return _reject("self_edge")
		if not _validate_metadata(edge.get("metadata", {})): return _reject("edge_metadata")
		if not ids.has(edge.from) or not ids.has(edge.to): return _reject("dangling_edge")
		edge_ids[edge.id] = true
	return true

func _build_layout(graph: Dictionary) -> Dictionary:
	var sorted_nodes: Array = graph.nodes.duplicate(true)
	sorted_nodes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var nodes: Dictionary = {}
	var order: Array[String] = []
	var lane_index: Dictionary = {}
	for index: int in range(DOMAINS.size()): lane_index[DOMAINS[index]] = index
	for index: int in range(sorted_nodes.size()):
		var payload: Dictionary = sorted_nodes[index].duplicate(true)
		var lane: int = int(lane_index.get(str(graph.domain), 0))
		var row: int = int(index / 8)
		var position := Vector2(float(index % 8) * (NODE_W + GAP_X), float(lane) * LANE_H + float(row) * (NODE_H + GAP_X))
		nodes[str(payload.id)] = {"position": position, "payload": payload}
		order.append(str(payload.id))
	var edges: Array = graph.edges.duplicate(true)
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return {"domain": str(graph.domain), "nodes": nodes, "node_order": order, "edges": edges, "truncated": bool(graph.truncated)}

func _exact_keys(value: Dictionary, allowed: Array[String]) -> bool:
	for key: Variant in value.keys():
		if not allowed.has(str(key)): return false
	var required_count: int = allowed.size() - (1 if allowed.has("metadata") else 0)
	for key: String in allowed:
		if key != "metadata" and not value.has(key): return false
	return value.size() == required_count or (allowed.has("metadata") and value.size() == allowed.size())

func _validate_metadata(value: Variant) -> bool:
	if not value is Dictionary: return false
	var metadata: Dictionary = value
	if metadata.size() > MAX_METADATA: return false
	for key: Variant in metadata.keys():
		if not key is String or str(key).to_utf8_buffer().size() > MAX_METADATA_KEY_BYTES: return false
		var item: Variant = metadata[key]
		if item == null or item is bool or item is int: continue
		if item is float:
			if not is_finite(float(item)): return false
			continue
		if item is String and str(item).to_utf8_buffer().size() <= MAX_METADATA_STRING_BYTES: continue
		return false
	return true

func _valid_text(value: Variant) -> bool:
	return value is String and not str(value).is_empty() and str(value).to_utf8_buffer().size() <= 128

func _reject(code: String) -> bool:
	_last_error = code
	return false

func _node_color(kind: String) -> Color:
	var palette: Array[Color] = [Color("246b91"), Color("477a5a"), Color("74549a"), Color("89633c"), Color("8d4d62")]
	return palette[abs(kind.hash()) % palette.size()]
