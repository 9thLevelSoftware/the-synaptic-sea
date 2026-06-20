extends SceneTree

const DEFAULT_LAYOUT_PATH: String = "res://data/procgen/golden/coherent_ship_001/layout.json"
const DEFAULT_GAMEPLAY_PATH: String = "res://data/procgen/golden/coherent_ship_001/gameplay_slice.json"
const REQUIRED_ROLES: Array[String] = ["airlock", "main_spine", "reactor"]

var failures: Array[String] = []

func _initialize() -> void:
	var layout_path: String = DEFAULT_LAYOUT_PATH
	var gameplay_path: String = DEFAULT_GAMEPLAY_PATH
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 0 and args.size() != 2:
		failures.append("expected either 0 args or 2 args: layout_path gameplay_path")
		_report_failures()
		return
	if args.size() == 2:
		layout_path = args[0]
		gameplay_path = args[1]
	var layout: Dictionary = _load_json(layout_path, "layout")
	var gameplay: Dictionary = _load_json(gameplay_path, "gameplay")
	if failures.is_empty():
		_validate(layout, gameplay, layout_path, gameplay_path)
	if not failures.is_empty():
		_report_failures()
		return
	print("COHERENT STATIC FIXTURE PASS rooms=%d traversable_links=%d blocked_links=%d vertical_connections=%d" % [
		_safe_array(layout, "rooms").size(),
		_safe_array(layout, "room_links").size(),
		_safe_array(layout, "blocked_links").size(),
		_safe_array(layout, "vertical_connections").size(),
	])
	quit(0)


func _report_failures() -> void:
	for failure in failures:
		push_error("COHERENT STATIC FIXTURE FAIL %s" % failure)
	quit(1)


func _load_json(path: String, label: String) -> Dictionary:
	var global_path: String = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path):
		failures.append("%s not found: %s" % [label, path])
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("%s not found: %s" % [label, path])
		return {}
	var text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	var parse_err: int = json.parse(text)
	if parse_err != OK:
		failures.append("%s JSON is invalid: %s" % [label, path])
		return {}
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		failures.append("%s JSON is invalid: %s" % [label, path])
		return {}
	return data


# Defensive Variant helper: returns the array at `key` or pushes a failure and
# returns an empty array if the value is missing, null, or not an array.
# Mirrors the style used by generated_ship_loader.gd.
func _require_array(doc: Dictionary, key: String, label: String) -> Array:
	var v: Variant = doc.get(key, [])
	if typeof(v) != TYPE_ARRAY:
		failures.append("%s %s must be an array: got %s" % [label, key, _typeof_name(v)])
		return []
	return v


# Defensive Variant helper: returns the array at `key` or an empty array if
# the value is missing, null, or not an array. Does not push a failure.
# Used for keys that are optional / non-fatal if malformed.
func _safe_array(doc: Dictionary, key: String) -> Array:
	var v: Variant = doc.get(key, [])
	if typeof(v) != TYPE_ARRAY:
		return []
	return v


func _typeof_name(v: Variant) -> String:
	if v == null:
		return "null"
	return type_string(typeof(v))


func _validate(layout: Dictionary, gameplay: Dictionary, layout_path: String, gameplay_path: String) -> void:
	# Validate top-level array shape so malformed fixtures fail fast with a
	# clean message instead of crashing later in `for ... in null`.
	_require_array(layout, "rooms", "layout")
	_require_array(layout, "room_links", "layout")
	_require_array(layout, "blocked_links", "layout")
	_require_array(layout, "vertical_connections", "layout")
	_require_array(layout, "critical_path", "layout")
	if not failures.is_empty():
		return
	_assert_unique_room_ids(layout)
	_assert_required_roles(layout)
	_assert_gameplay_rooms_exist(layout, gameplay)
	_assert_links_reference_rooms(layout)
	_assert_blocked_links_not_traversable(layout)
	_assert_critical_path_reachable(layout, gameplay)
	_assert_vertical_transition_for_deck_change(layout, gameplay)


func _room_ids(layout: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for room in _safe_array(layout, "rooms"):
		if typeof(room) == TYPE_DICTIONARY and room.has("id"):
			ids.append(String(room["id"]))
	return ids


func _room_roles(layout: Dictionary) -> Dictionary:
	var role_map: Dictionary = {}
	for room in _safe_array(layout, "rooms"):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if room.has("id") and room.has("room_role"):
			role_map[String(room["id"])] = String(room["room_role"])
	return role_map


func _room_decks(layout: Dictionary) -> Dictionary:
	var deck_map: Dictionary = {}
	for room in _safe_array(layout, "rooms"):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if room.has("id") and room.has("deck"):
			deck_map[String(room["id"])] = int(room["deck"])
	return deck_map


func _assert_unique_room_ids(layout: Dictionary) -> void:
	var ids: Dictionary = {}
	for room_id in _room_ids(layout):
		if ids.has(room_id):
			failures.append("duplicate room id: %s" % room_id)
		ids[room_id] = true


func _assert_required_roles(layout: Dictionary) -> void:
	var roles_seen: Dictionary = {}
	for room in _safe_array(layout, "rooms"):
		if typeof(room) != TYPE_DICTIONARY:
			continue
		if room.has("room_role"):
			roles_seen[String(room["room_role"])] = true
	for required_role in REQUIRED_ROLES:
		if not roles_seen.has(required_role):
			failures.append("missing required role: %s" % required_role)


func _assert_gameplay_rooms_exist(layout: Dictionary, gameplay: Dictionary) -> void:
	var ids: Dictionary = {}
	for room_id in _room_ids(layout):
		ids[room_id] = true
	var start_room: String = String(gameplay.get("start_room", ""))
	var goal_room: String = String(gameplay.get("goal_room", ""))
	if start_room.is_empty():
		failures.append("gameplay missing start_room")
	elif not ids.has(start_room):
		failures.append("gameplay start_room not in layout: %s" % start_room)
	if goal_room.is_empty():
		failures.append("gameplay missing goal_room")
	elif not ids.has(goal_room):
		failures.append("gameplay goal_room not in layout: %s" % goal_room)


func _assert_links_reference_rooms(layout: Dictionary) -> void:
	var ids: Dictionary = {}
	for room_id in _room_ids(layout):
		ids[room_id] = true
	for link in _safe_array(layout, "room_links"):
		if typeof(link) != TYPE_DICTIONARY:
			continue
		var from_room: String = String(link.get("from_room", ""))
		var to_room: String = String(link.get("to_room", ""))
		if not ids.has(from_room):
			failures.append("room_link %s from_room missing: %s" % [String(link.get("id", "")), from_room])
		if not ids.has(to_room):
			failures.append("room_link %s to_room missing: %s" % [String(link.get("id", "")), to_room])
	for link in _safe_array(layout, "blocked_links"):
		if typeof(link) != TYPE_DICTIONARY:
			continue
		var from_room_b: String = String(link.get("from_room", ""))
		var to_room_b: String = String(link.get("to_room", ""))
		if not ids.has(from_room_b):
			failures.append("blocked_link %s from_room missing: %s" % [String(link.get("id", "")), from_room_b])
		if not ids.has(to_room_b):
			failures.append("blocked_link %s to_room missing: %s" % [String(link.get("id", "")), to_room_b])
	for vc in _safe_array(layout, "vertical_connections"):
		if typeof(vc) != TYPE_DICTIONARY:
			continue
		var from_room_v: String = String(vc.get("from_room", ""))
		var to_room_v: String = String(vc.get("to_room", ""))
		if not ids.has(from_room_v):
			failures.append("vertical_connection %s from_room missing: %s" % [String(vc.get("id", "")), from_room_v])
		if not ids.has(to_room_v):
			failures.append("vertical_connection %s to_room missing: %s" % [String(vc.get("id", "")), to_room_v])


func _assert_blocked_links_not_traversable(layout: Dictionary) -> void:
	var traversable_edges: Dictionary = {}
	for link in _safe_array(layout, "room_links"):
		if typeof(link) != TYPE_DICTIONARY:
			continue
		_add_edge_pair(traversable_edges, link, "from_room", "from_cell", "to_room", "to_cell")
	for vc in _safe_array(layout, "vertical_connections"):
		if typeof(vc) != TYPE_DICTIONARY:
			continue
		_add_edge_pair(traversable_edges, vc, "from_room", "from_cell", "to_room", "to_cell")
	for blocked in _safe_array(layout, "blocked_links"):
		if typeof(blocked) != TYPE_DICTIONARY:
			continue
		var blocked_fwd: String = _edge_key(blocked, "from_room", "from_cell", "to_room", "to_cell")
		var blocked_rev: String = _edge_key(blocked, "to_room", "to_cell", "from_room", "from_cell")
		var from_room: String = String(blocked.get("from_room", ""))
		var to_room: String = String(blocked.get("to_room", ""))
		if traversable_edges.has(blocked_fwd):
			failures.append("blocked_link %s is also traversable: %s>%s" % [String(blocked.get("id", "")), from_room, to_room])
		if traversable_edges.has(blocked_rev):
			failures.append("blocked_link %s is also traversable: %s>%s" % [String(blocked.get("id", "")), to_room, from_room])


func _assert_critical_path_reachable(layout: Dictionary, gameplay: Dictionary) -> void:
	var traversable_room_edges: Dictionary = {}
	for link in _safe_array(layout, "room_links"):
		if typeof(link) != TYPE_DICTIONARY:
			continue
		_add_room_pair(traversable_room_edges, link, "from_room", "to_room")
	for vc in _safe_array(layout, "vertical_connections"):
		if typeof(vc) != TYPE_DICTIONARY:
			continue
		_add_room_pair(traversable_room_edges, vc, "from_room", "to_room")
	var critical_path: Array = _safe_array(layout, "critical_path")
	for i in range(critical_path.size() - 1):
		var from_room: String = String(critical_path[i])
		var to_room: String = String(critical_path[i + 1])
		var key: String = "%s>%s" % [from_room, to_room]
		var reverse_key: String = "%s>%s" % [to_room, from_room]
		if not (traversable_room_edges.has(key) or traversable_room_edges.has(reverse_key)):
			failures.append("critical_path edge not traversable: %s>%s" % [from_room, to_room])
	var start_room: String = String(gameplay.get("start_room", ""))
	var goal_room: String = String(gameplay.get("goal_room", ""))
	if start_room.is_empty() or goal_room.is_empty():
		return
	if not _rooms_reachable(start_room, goal_room, traversable_room_edges):
		failures.append("start_room cannot reach goal_room: %s -> %s" % [start_room, goal_room])


func _rooms_reachable(start_room: String, goal_room: String, traversable_edges: Dictionary) -> bool:
	var adjacency: Dictionary = {}
	for edge_key in traversable_edges.keys():
		var parts: PackedStringArray = String(edge_key).split(">")
		if parts.size() != 2:
			continue
		var from_room: String = parts[0]
		var to_room: String = parts[1]
		if not adjacency.has(from_room):
			adjacency[from_room] = []
		(adjacency[from_room] as Array).append(to_room)
	var visited: Dictionary = {}
	var queue: Array = [start_room]
	visited[start_room] = true
	while not queue.is_empty():
		var current: String = queue.pop_front()
		if current == goal_room:
			return true
		if not adjacency.has(current):
			continue
		for neighbor in adjacency[current]:
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return false


func _add_edge_pair(edges: Dictionary, entry: Dictionary, from_room_key: String, from_cell_key: String, to_room_key: String, to_cell_key: String) -> void:
	var fwd: String = _edge_key(entry, from_room_key, from_cell_key, to_room_key, to_cell_key)
	var rev: String = _edge_key(entry, to_room_key, to_cell_key, from_room_key, from_cell_key)
	edges[fwd] = true
	edges[rev] = true


func _add_room_pair(edges: Dictionary, entry: Dictionary, from_room_key: String, to_room_key: String) -> void:
	var fwd: String = "%s>%s" % [String(entry.get(from_room_key, "")), String(entry.get(to_room_key, ""))]
	var rev: String = "%s>%s" % [String(entry.get(to_room_key, "")), String(entry.get(from_room_key, ""))]
	edges[fwd] = true
	edges[rev] = true


func _edge_key(entry: Dictionary, from_room_key: String, from_cell_key: String, to_room_key: String, to_cell_key: String) -> String:
	var from_room: String = String(entry.get(from_room_key, ""))
	var to_room: String = String(entry.get(to_room_key, ""))
	var from_cell: String = _cell_to_string(entry.get(from_cell_key, []))
	var to_cell: String = _cell_to_string(entry.get(to_cell_key, []))
	return "%s@%s>%s@%s" % [from_room, from_cell, to_room, to_cell]


func _cell_to_string(cell: Variant) -> String:
	if typeof(cell) != TYPE_ARRAY:
		return ""
	var parts: PackedStringArray = []
	for v in (cell as Array):
		parts.append(str(v))
	return "[%s]" % ",".join(parts)


func _assert_vertical_transition_for_deck_change(layout: Dictionary, gameplay: Dictionary) -> void:
	var deck_map: Dictionary = _room_decks(layout)
	var vertical_edges: Dictionary = {}
	for vc in _safe_array(layout, "vertical_connections"):
		if typeof(vc) != TYPE_DICTIONARY:
			continue
		var vc_key: String = "%s>%s" % [String(vc.get("from_room", "")), String(vc.get("to_room", ""))]
		vertical_edges[vc_key] = true
		var vc_reverse: String = "%s>%s" % [String(vc.get("to_room", "")), String(vc.get("from_room", ""))]
		vertical_edges[vc_reverse] = true
	var critical_path: Array = _safe_array(layout, "critical_path")
	for i in range(critical_path.size() - 1):
		var from_room: String = String(critical_path[i])
		var to_room: String = String(critical_path[i + 1])
		if not deck_map.has(from_room) or not deck_map.has(to_room):
			continue
		var from_deck: int = int(deck_map[from_room])
		var to_deck: int = int(deck_map[to_room])
		if from_deck == to_deck:
			continue
		var forward_key: String = "%s>%s" % [from_room, to_room]
		var reverse_key: String = "%s>%s" % [to_room, from_room]
		if not (vertical_edges.has(forward_key) or vertical_edges.has(reverse_key)):
			failures.append("critical_path crosses deck change without vertical_connection: %s(%d) -> %s(%d)" % [from_room, from_deck, to_room, to_deck])
