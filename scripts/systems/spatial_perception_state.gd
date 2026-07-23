extends RefCounted
class_name SpatialPerceptionState

## PKG-C4.1a: pure spatial perception over room adjacency + door state.
## Occlusion / noise muffling without physics raycasts. Scene layer (C4.1b)
## may add one engaged-threat raycast later.

const OPEN_NOISE_ATTEN: float = 0.85       # per open portal hop
const CLOSED_NOISE_ATTEN: float = 0.12     # closed hatch heavily muffles
const BLOCKED_NOISE_ATTEN: float = 0.05    # sealed / biomatter block
const MAX_HOPS: int = 8

## room_id -> true
var rooms: Dictionary = {}
## undirected link key "a|b" -> { from, to, link_id, kind: open|closed|blocked, module_id }
var links: Dictionary = {}
## door_id or link key -> "open"|"closed"
var door_states: Dictionary = {}


func clear() -> void:
	rooms.clear()
	links.clear()
	door_states.clear()


## Build from layout.json-shaped dict (rooms, room_links, blocked_links).
func configure_from_layout(layout: Dictionary) -> int:
	clear()
	var rooms_v: Variant = layout.get("rooms", [])
	if rooms_v is Array:
		for r in rooms_v:
			if typeof(r) != TYPE_DICTIONARY:
				continue
			var rid: String = str((r as Dictionary).get("id", ""))
			if not rid.is_empty():
				rooms[rid] = true
	var open_n: int = _ingest_links(layout.get("room_links", []), "open")
	var blocked_n: int = _ingest_links(layout.get("blocked_links", []), "blocked")
	return open_n + blocked_n


func _ingest_links(raw: Variant, default_kind: String) -> int:
	if typeof(raw) != TYPE_ARRAY:
		return 0
	var n: int = 0
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var a: String = str(d.get("from_room", d.get("from", "")))
		var b: String = str(d.get("to_room", d.get("to", "")))
		if a.is_empty() or b.is_empty() or a == b:
			continue
		rooms[a] = true
		rooms[b] = true
		var key: String = _link_key(a, b)
		var module_id: String = str(d.get("module_id", ""))
		var kind: String = default_kind
		if module_id.contains("blocked") or module_id.contains("sealed"):
			kind = "blocked"
		elif module_id.contains("closed") or module_id.contains("hatch_closed"):
			kind = "closed"
		elif module_id.contains("open") or module_id.contains("doorway") or module_id.contains("ramp"):
			if default_kind != "blocked":
				kind = "open"
		var link_id: String = str(d.get("id", key))
		links[key] = {
			"from": a,
			"to": b,
			"link_id": link_id,
			"kind": kind,
			"module_id": module_id,
		}
		# Initial door state from kind
		if kind == "open":
			door_states[key] = "open"
		elif kind == "closed":
			door_states[key] = "closed"
		else:
			door_states[key] = "blocked"
		n += 1
	return n


func _link_key(a: String, b: String) -> String:
	if a < b:
		return "%s|%s" % [a, b]
	return "%s|%s" % [b, a]


func set_door_state(room_a: String, room_b: String, state: String) -> bool:
	var key: String = _link_key(room_a, room_b)
	if not links.has(key):
		return false
	var s: String = state
	if s != "open" and s != "closed" and s != "blocked":
		return false
	# Cannot open a permanently blocked link without unblocking first
	var kind: String = str((links[key] as Dictionary).get("kind", "open"))
	if kind == "blocked" and s == "open":
		# allow explicit open only via unblock_link
		return false
	door_states[key] = s
	return true


func unblock_link(room_a: String, room_b: String) -> bool:
	var key: String = _link_key(room_a, room_b)
	if not links.has(key):
		return false
	var L: Dictionary = links[key]
	L["kind"] = "open"
	links[key] = L
	door_states[key] = "open"
	return true


func get_door_state(room_a: String, room_b: String) -> String:
	var key: String = _link_key(room_a, room_b)
	return str(door_states.get(key, ""))


func has_room(room_id: String) -> bool:
	return rooms.has(room_id)


func link_count() -> int:
	return links.size()


## Sight: same room, or path of only open doors (no closed/blocked).
func can_see(from_room: String, to_room: String) -> bool:
	if from_room.is_empty() or to_room.is_empty():
		return false
	if from_room == to_room:
		return true
	return _path_exists(from_room, to_room, true)


## Noise remaining after attenuation along best path (0..source). Closed hatches muffle.
func attenuate_noise(from_room: String, to_room: String, source_noise: float) -> float:
	if source_noise <= 0.0:
		return 0.0
	if from_room.is_empty() or to_room.is_empty():
		return 0.0
	if from_room == to_room:
		return source_noise
	var path_atten: float = _best_noise_attenuation(from_room, to_room)
	return source_noise * path_atten


## True if any noise above threshold could be heard.
func can_hear(from_room: String, to_room: String, source_noise: float, threshold: float = 0.05) -> bool:
	return attenuate_noise(from_room, to_room, source_noise) >= threshold


func _edge_allows_sight(key: String) -> bool:
	var st: String = str(door_states.get(key, "closed"))
	return st == "open"


func _edge_noise_mult(key: String) -> float:
	var st: String = str(door_states.get(key, "closed"))
	match st:
		"open":
			return OPEN_NOISE_ATTEN
		"closed":
			return CLOSED_NOISE_ATTEN
		"blocked":
			return BLOCKED_NOISE_ATTEN
		_:
			return CLOSED_NOISE_ATTEN


func _neighbors(room_id: String) -> Array:
	var out: Array = []
	for key in links.keys():
		var L: Dictionary = links[key]
		var a: String = str(L.get("from", ""))
		var b: String = str(L.get("to", ""))
		if a == room_id:
			out.append({"room": b, "key": str(key)})
		elif b == room_id:
			out.append({"room": a, "key": str(key)})
	return out


func _path_exists(from_room: String, to_room: String, sight_only: bool) -> bool:
	if not rooms.has(from_room) or not rooms.has(to_room):
		return false
	var visited: Dictionary = {from_room: true}
	var queue: Array = [from_room]
	var hops: int = 0
	while not queue.is_empty() and hops < MAX_HOPS * rooms.size():
		var cur: String = str(queue.pop_front())
		hops += 1
		if cur == to_room:
			return true
		for nb in _neighbors(cur):
			var nroom: String = str(nb.get("room", ""))
			var key: String = str(nb.get("key", ""))
			if visited.has(nroom):
				continue
			if sight_only and not _edge_allows_sight(key):
				continue
			# noise paths always can traverse but attenuate — for path_exists noise use true
			if not sight_only:
				pass
			visited[nroom] = true
			queue.append(nroom)
	return visited.has(to_room)


## Dijkstra-like max product of attenuation (best remaining noise fraction).
func _best_noise_attenuation(from_room: String, to_room: String) -> float:
	if not rooms.has(from_room) or not rooms.has(to_room):
		return 0.0
	var best: Dictionary = {}  # room -> atten product
	for r in rooms.keys():
		best[str(r)] = 0.0
	best[from_room] = 1.0
	# Simple relaxation over hops
	for _pass in range(maxi(1, rooms.size())):
		var changed: bool = false
		for key in links.keys():
			var L: Dictionary = links[key]
			var a: String = str(L.get("from", ""))
			var b: String = str(L.get("to", ""))
			var mult: float = _edge_noise_mult(str(key))
			var via_a: float = float(best.get(a, 0.0)) * mult
			if via_a > float(best.get(b, 0.0)):
				best[b] = via_a
				changed = true
			var via_b: float = float(best.get(b, 0.0)) * mult
			if via_b > float(best.get(a, 0.0)):
				best[a] = via_b
				changed = true
		if not changed:
			break
	return float(best.get(to_room, 0.0))


## Convenience: build perception probe for threat AI.
func probe(observer_room: String, target_room: String, emitted_noise: float, emitted_visibility: float = 1.0) -> Dictionary:
	var seen: bool = can_see(observer_room, target_room)
	var heard_level: float = attenuate_noise(target_room, observer_room, emitted_noise)
	return {
		"observer_room": observer_room,
		"target_room": target_room,
		"seen": seen,
		"heard": heard_level >= 0.05,
		"noise_at_observer": heard_level,
		"visibility": emitted_visibility if seen else 0.0,
	}


func get_summary() -> Dictionary:
	return {
		"schema": "spatial_perception_v1",
		"room_count": rooms.size(),
		"link_count": links.size(),
		"links": links.duplicate(true),
		"door_states": door_states.duplicate(true),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	clear()
	var r: Variant = summary.get("links", {})
	if typeof(r) == TYPE_DICTIONARY:
		links = (r as Dictionary).duplicate(true)
		for key in links.keys():
			var L: Dictionary = links[key]
			rooms[str(L.get("from", ""))] = true
			rooms[str(L.get("to", ""))] = true
	var d: Variant = summary.get("door_states", {})
	if typeof(d) == TYPE_DICTIONARY:
		door_states = (d as Dictionary).duplicate(true)
	return true
