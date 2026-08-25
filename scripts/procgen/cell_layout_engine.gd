extends RefCounted
class_name CellLayoutEngine

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0

const DIR_NORTH: Vector2i = Vector2i(0, -1)
const DIR_EAST: Vector2i = Vector2i(1, 0)
const DIR_SOUTH: Vector2i = Vector2i(0, 1)
const DIR_WEST: Vector2i = Vector2i(-1, 0)
const ALL_DIRS: Array[Vector2i] = [DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST]

const SENTINEL: Vector2i = Vector2i(-99999, -99999)
const MAX_GROW_STEPS: int = 24

# Ship axis: bow = +X (east), stern = -X (west).
# Lateral = north/south (port/starboard).
const HINT_DIRECTIONS: Dictionary = {
	"bow":     [DIR_EAST, DIR_NORTH, DIR_SOUTH, DIR_WEST],
	"stern":   [DIR_WEST, DIR_NORTH, DIR_SOUTH, DIR_EAST],
	"lateral": [DIR_SOUTH, DIR_NORTH, DIR_EAST, DIR_WEST],
	"center":  [DIR_EAST, DIR_WEST, DIR_SOUTH, DIR_NORTH],
}

# Connective roles: these form the spine/skeleton of the ship.
# Functional rooms should attach to these, not to each other.
const CONNECTIVE_ROLES: Array[String] = [
	"corridor", "main_spine", "hub", "ramp", "elevator", "airlock", "dock",
]

# Hazardous roles: loud, dangerous, should be isolated from crew areas.
# These must NOT share a wall with crew comfort roles.
const HAZARDOUS_ROLES: Array[String] = [
	"reactor", "engineering",
]

# Crew comfort roles: living/working spaces that must be kept away from
# hazardous areas. At least one corridor buffer between these and hazardous.
const CREW_COMFORT_ROLES: Array[String] = [
	"crew_quarters", "medical", "mess_hall", "bridge",
]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func layout(room_plan: Array[Dictionary], template: RefCounted, seed_value: int) -> Dictionary:
	# Rooms grow from template.connections / attach_to connectors onto a 4 m
	# grid. Same-deck links must share a cardinal cell edge; cross-deck links
	# stay vertical. Inventing portals between non-touching rooms is forbidden.
	rng.seed = seed_value

	var zone_rooms_map: Dictionary = {}
	for room in room_plan:
		var rid: String = str(room["id"])
		var zid: String = str(room.get("zone_id", ""))
		if not zone_rooms_map.has(zid):
			zone_rooms_map[zid] = []
		(zone_rooms_map[zid] as Array).append(rid)

	var zone_order: Array[Dictionary] = _build_zone_order(template)
	var graph: Dictionary = _build_connector_graph(room_plan, template, zone_rooms_map)

	# deck -> (Vector2i -> room_id)
	var occupied_per_deck: Dictionary = {}
	# room_id -> {cells, origin, footprint, deck, role}
	var placed: Dictionary = {}

	for zone_info in zone_order:
		var zone_id: String = str(zone_info["id"])
		var parent_zone_id: String = str(zone_info.get("attach_to", ""))
		var zone_room_ids: Array = zone_rooms_map.get(zone_id, [])
		var last_in_zone: String = ""

		for room_id_variant in zone_room_ids:
			var rid: String = str(room_id_variant)
			var room: Dictionary = _room_by_id(room_plan, rid)
			if room.is_empty():
				continue
			var committed: bool = _place_one_room(
				room, zone_id, parent_zone_id, last_in_zone, graph,
				zone_rooms_map, occupied_per_deck, placed)
			if committed:
				last_in_zone = rid
			else:
				push_error("CellLayoutEngine: could not place room %s" % rid)

	_realize_missing_connectors(graph, zone_rooms_map, occupied_per_deck, placed)

	var adjacencies: Array[Dictionary] = _discover_adjacencies(placed)
	_add_vertical_adjacencies(
		adjacencies, placed, graph, zone_rooms_map, template)

	return {"rooms": placed, "adjacencies": adjacencies}


func _build_zone_order(template: RefCounted) -> Array[Dictionary]:
	var order: Array[Dictionary] = []
	var visited: Dictionary = {}
	var queue: Array[Dictionary] = []

	for zone in template.zones:
		var attach: String = str(zone.get("attach_to", ""))
		if attach.is_empty():
			queue.append(zone)
			visited[str(zone["id"])] = true

	while not queue.is_empty():
		var zone: Dictionary = queue.pop_front()
		order.append(zone)
		var children: Array[Dictionary] = template.get_zones_attached_to(str(zone["id"]))
		for child in children:
			var cid: String = str(child["id"])
			if not visited.has(cid):
				visited[cid] = true
				queue.append(child)

	return order


func _build_connector_graph(
		room_plan: Array[Dictionary], template: RefCounted, zone_rooms_map: Dictionary) -> Dictionary:
	var neighbors: Dictionary = {}
	var zone_pairs: Array[Dictionary] = []
	var zone_pair_seen: Dictionary = {}

	for conn_variant in template.connections:
		if typeof(conn_variant) != TYPE_DICTIONARY:
			continue
		var conn: Dictionary = conn_variant
		var from_ref: Dictionary = _parse_zone_ref(str(conn.get("from", "")))
		var to_ref: Dictionary = _parse_zone_ref(str(conn.get("to", "")))
		var from_zone: String = str(from_ref.get("id", ""))
		var to_zone: String = str(to_ref.get("id", ""))
		if from_zone.is_empty() or to_zone.is_empty():
			continue
		var from_rooms: Array = zone_rooms_map.get(from_zone, [])
		var to_rooms: Array = zone_rooms_map.get(to_zone, [])
		var distribution: String = str(conn.get("distribution", "adjacent"))
		var from_kind: String = str(from_ref.get("kind", "all"))
		var to_kind: String = str(to_ref.get("kind", "all"))

		if from_kind == "next" or to_kind == "next":
			var chain_zone: String = from_zone if from_kind == "next" else to_zone
			if from_zone == to_zone:
				chain_zone = from_zone
			var chain_rooms: Array = zone_rooms_map.get(chain_zone, [])
			for i in range(maxi(chain_rooms.size() - 1, 0)):
				_add_specific_neighbor(neighbors, str(chain_rooms[i]), str(chain_rooms[i + 1]))
			continue

		if from_zone != to_zone:
			_add_zone_pair(zone_pairs, zone_pair_seen, from_zone, to_zone)

		var from_ids: Array[String] = _resolve_ref_rooms(from_ref, from_rooms)
		var to_ids: Array[String] = _resolve_ref_rooms(to_ref, to_rooms)
		if from_ids.is_empty() or to_ids.is_empty():
			continue

		if distribution == "spread":
			for i in range(to_ids.size()):
				_add_specific_neighbor(neighbors, to_ids[i], from_ids[i % from_ids.size()])
		elif from_kind == "index" or to_kind == "index":
			for fr in from_ids:
				for tr in to_ids:
					_add_specific_neighbor(neighbors, fr, tr)
		else:
			_add_specific_neighbor(neighbors, from_ids[from_ids.size() - 1], to_ids[0])

	var zone_layout: Dictionary = {}
	for zone in template.zones:
		zone_layout[str(zone.get("id", ""))] = str(zone.get("layout", "single"))
		var child_zone: String = str(zone.get("id", ""))
		var parent_zone: String = str(zone.get("attach_to", ""))
		if parent_zone.is_empty() or child_zone.is_empty():
			continue
		if zone_pair_seen.has(_pair_key(parent_zone, child_zone)):
			continue
		_add_zone_pair(zone_pairs, zone_pair_seen, parent_zone, child_zone)
		var parent_rooms: Array = zone_rooms_map.get(parent_zone, [])
		var child_rooms: Array = zone_rooms_map.get(child_zone, [])
		if parent_rooms.is_empty() or child_rooms.is_empty():
			continue
		_add_specific_neighbor(neighbors, str(child_rooms[0]), str(parent_rooms[parent_rooms.size() - 1]))

	for zid in zone_rooms_map.keys():
		var z_rooms: Array = zone_rooms_map[zid]
		if z_rooms.size() < 2:
			continue
		for i in range(z_rooms.size() - 1):
			_add_specific_neighbor(neighbors, str(z_rooms[i]), str(z_rooms[i + 1]))
		if str(zone_layout.get(str(zid), "")) == "clustered":
			for i in range(1, z_rooms.size()):
				_add_specific_neighbor(neighbors, str(z_rooms[i]), str(z_rooms[0]))

	return {"neighbors": neighbors, "zone_pairs": zone_pairs}


func _parse_zone_ref(zone_ref: String) -> Dictionary:
	var raw: String = zone_ref.strip_edges()
	var bracket: int = raw.find("[")
	if bracket < 0:
		return {"id": raw, "kind": "all", "index": 0}
	var close: int = raw.find("]")
	var zone_id: String = raw.substr(0, bracket)
	var inner: String = raw.substr(bracket + 1, close - bracket - 1) if close > bracket else "*"
	if inner == "*" or inner.is_empty():
		return {"id": zone_id, "kind": "all", "index": 0}
	if inner.begins_with("*"):
		return {"id": zone_id, "kind": "next", "index": 1}
	return {"id": zone_id, "kind": "index", "index": int(inner)}


func _resolve_ref_rooms(parsed: Dictionary, zone_rooms: Array) -> Array[String]:
	var out: Array[String] = []
	if zone_rooms.is_empty():
		return out
	var kind: String = str(parsed.get("kind", "all"))
	if kind == "index":
		var rid: String = _index_room(zone_rooms, int(parsed.get("index", 0)))
		if not rid.is_empty():
			out.append(rid)
		return out
	for entry in zone_rooms:
		out.append(str(entry))
	return out


func _index_room(zone_rooms: Array, index: int) -> String:
	if zone_rooms.is_empty():
		return ""
	var i: int = index
	if i < 0:
		i = zone_rooms.size() + i
	if i < 0 or i >= zone_rooms.size():
		return ""
	return str(zone_rooms[i])


func _add_specific_neighbor(neighbors: Dictionary, a: String, b: String) -> void:
	if a.is_empty() or b.is_empty() or a == b:
		return
	if not neighbors.has(a):
		neighbors[a] = {}
	(neighbors[a] as Dictionary)[b] = true
	if not neighbors.has(b):
		neighbors[b] = {}
	(neighbors[b] as Dictionary)[a] = true


func _add_zone_pair(
		zone_pairs: Array[Dictionary], seen: Dictionary, a: String, b: String) -> void:
	if a.is_empty() or b.is_empty() or a == b:
		return
	var key: String = _pair_key(a, b)
	if seen.has(key):
		return
	seen[key] = true
	zone_pairs.append({"a": a, "b": b})


func _neighbor_ids(neighbors: Dictionary, rid: String) -> Array[String]:
	var out: Array[String] = []
	var raw_variant: Variant = neighbors.get(rid, {})
	if typeof(raw_variant) != TYPE_DICTIONARY:
		return out
	var keys: Array = (raw_variant as Dictionary).keys()
	keys.sort()
	for key in keys:
		out.append(str(key))
	return out


func _place_one_room(
		room: Dictionary,
		zone_id: String,
		parent_zone_id: String,
		last_in_zone: String,
		graph: Dictionary,
		zone_rooms_map: Dictionary,
		occupied_per_deck: Dictionary,
		placed: Dictionary) -> bool:
	var rid: String = str(room["id"])
	var fp: Vector2i = _coerce_footprint(room.get("footprint", Vector2i(2, 2)))
	var deck: int = int(room.get("deck", 0))
	var hint: String = str(room.get("position_hint", "center"))
	var role: String = str(room.get("role", ""))
	var target_cells: int = int(room.get("target_cells", fp.x * fp.y))
	if target_cells <= 0:
		target_cells = maxi(fp.x * fp.y, 1)

	if not occupied_per_deck.has(deck):
		occupied_per_deck[deck] = {}
	var occupied: Dictionary = occupied_per_deck[deck]

	if placed.is_empty() or occupied.is_empty():
		var vertical_ids: Array[String] = _filter_placed(
			_desired_anchors(
				rid, zone_id, parent_zone_id, last_in_zone, graph, zone_rooms_map, placed),
			placed, deck, false)
		var aligned: Dictionary = _best_aligned_rect(
			fp, hint, occupied, role, placed, vertical_ids, target_cells)
		if aligned.is_empty() and occupied.is_empty():
			aligned = {
				"origin": Vector2i.ZERO,
				"footprint": fp,
				"cells": _compute_cells(Vector2i.ZERO, fp),
			}
		if aligned.is_empty():
			return false
		_commit_room(
			placed, occupied, rid, _as_cells(aligned.get("cells", [])), deck, role,
			_coerce_footprint(aligned.get("footprint", fp)))
		return true

	var desired: Array[String] = _desired_anchors(
		rid, zone_id, parent_zone_id, last_in_zone, graph, zone_rooms_map, placed)
	var same_deck: Array[String] = _filter_placed(desired, placed, deck, true)
	if same_deck.is_empty():
		same_deck = _placed_ids_on_deck(placed, deck)
	var vertical_ids: Array[String] = _filter_placed(desired, placed, deck, false)

	var best: Dictionary = _best_rect_against_anchors(
		fp, hint, occupied, role, placed, same_deck, vertical_ids, target_cells, true, true)
	if best.is_empty():
		best = _best_grown_against_anchors(
			target_cells, hint, occupied, role, placed, same_deck, true, true)
	if best.is_empty():
		best = _best_rect_against_anchors(
			fp, hint, occupied, role, placed, same_deck, vertical_ids, target_cells, true, false)
	if best.is_empty():
		best = _best_rect_against_anchors(
			fp, hint, occupied, role, placed, same_deck, vertical_ids, target_cells, false, false)
	if best.is_empty():
		best = _best_grown_against_anchors(
			target_cells, hint, occupied, role, placed, same_deck, true, false)
	if best.is_empty():
		best = _best_grown_against_anchors(
			target_cells, hint, occupied, role, placed, same_deck, false, false)
	var all_deck: Array[String] = _placed_ids_on_deck(placed, deck)
	if best.is_empty() and all_deck.size() > same_deck.size():
		best = _best_rect_against_anchors(
			fp, hint, occupied, role, placed, all_deck, vertical_ids, target_cells, true, true)
	if best.is_empty() and all_deck.size() > same_deck.size():
		best = _best_rect_against_anchors(
			fp, hint, occupied, role, placed, all_deck, vertical_ids, target_cells, true, false)
	if best.is_empty() and all_deck.size() > same_deck.size():
		best = _best_rect_against_anchors(
			fp, hint, occupied, role, placed, all_deck, vertical_ids, target_cells, false, false)
	if best.is_empty() and all_deck.size() > same_deck.size():
		best = _best_grown_against_anchors(
			target_cells, hint, occupied, role, placed, all_deck, false, false)
	if best.is_empty() and not vertical_ids.is_empty():
		best = _best_aligned_rect(fp, hint, occupied, role, placed, vertical_ids, target_cells)
	if best.is_empty():
		return false
	_commit_room(
		placed, occupied, rid, _as_cells(best.get("cells", [])), deck, role,
		_coerce_footprint(best.get("footprint", fp)))
	return true


func _desired_anchors(
		rid: String,
		zone_id: String,
		parent_zone_id: String,
		last_in_zone: String,
		graph: Dictionary,
		zone_rooms_map: Dictionary,
		placed: Dictionary) -> Array[String]:
	# Declared graph neighbors are the only same-deck attach targets when any
	# of them are already placed. Using every room in a connected zone made
	# stern-hint destinations hug spine[0] instead of spine[-1].
	var neighbors: Dictionary = graph.get("neighbors", {})
	var neighbor_placed: Array[String] = []
	var neighbor_seen: Dictionary = {}
	for nid in _neighbor_ids(neighbors, rid):
		if nid == rid or not placed.has(nid) or neighbor_seen.has(nid):
			continue
		neighbor_seen[nid] = true
		neighbor_placed.append(nid)
	if not neighbor_placed.is_empty():
		return neighbor_placed

	var out: Array[String] = []
	var seen: Dictionary = {}
	var zone_pairs: Array = graph.get("zone_pairs", [])
	for pair_variant in zone_pairs:
		if typeof(pair_variant) != TYPE_DICTIONARY:
			continue
		var pair: Dictionary = pair_variant
		var other_zone: String = ""
		if str(pair.get("a", "")) == zone_id:
			other_zone = str(pair.get("b", ""))
		elif str(pair.get("b", "")) == zone_id:
			other_zone = str(pair.get("a", ""))
		if other_zone.is_empty():
			continue
		for other_rid in zone_rooms_map.get(other_zone, []):
			_append_unique(out, seen, str(other_rid))
	_append_unique(out, seen, last_in_zone)
	for parent_rid in zone_rooms_map.get(parent_zone_id, []):
		_append_unique(out, seen, str(parent_rid))
	var filtered: Array[String] = []
	for candidate in out:
		if candidate == rid:
			continue
		if placed.has(candidate):
			filtered.append(candidate)
	return filtered


func _append_unique(out: Array[String], seen: Dictionary, rid: String) -> void:
	if rid.is_empty() or seen.has(rid):
		return
	seen[rid] = true
	out.append(rid)


func _filter_placed(
		ids: Array[String], placed: Dictionary, deck: int, same_deck: bool) -> Array[String]:
	var out: Array[String] = []
	for rid in ids:
		if not placed.has(rid):
			continue
		var other_deck: int = int(placed[rid].get("deck", 0))
		if same_deck and other_deck == deck:
			out.append(rid)
		elif (not same_deck) and other_deck != deck:
			out.append(rid)
	return out


func _placed_ids_on_deck(placed: Dictionary, deck: int) -> Array[String]:
	var out: Array[String] = []
	for rid in placed.keys():
		if int(placed[rid].get("deck", 0)) == deck:
			out.append(str(rid))
	return out


func _best_rect_against_anchors(
		fp: Vector2i,
		hint: String,
		occupied: Dictionary,
		role: String,
		placed: Dictionary,
		anchors: Array[String],
		vertical_ids: Array[String],
		target_cells: int,
		require_compat: bool,
		require_touch: bool) -> Dictionary:
	if anchors.is_empty():
		return {}
	var fps: Array[Vector2i] = [fp]
	if fp.x != fp.y:
		fps.append(Vector2i(fp.y, fp.x))
	var anchor_cells: Array[Vector2i] = _concat_room_cells(placed, anchors)
	var seeds: Array[Vector2i] = _empty_seeds(anchor_cells, occupied)
	_sort_seeds(seeds, anchor_cells, hint)

	var best: Dictionary = {}
	var best_score: int = -1
	var seen: Dictionary = {}
	for try_fp in fps:
		for seed in seeds:
			for origin in _origins_covering(seed, try_fp):
				var key: String = "%d_%d_%d_%d" % [origin.x, origin.y, try_fp.x, try_fp.y]
				if seen.has(key):
					continue
				seen[key] = true
				if not _can_place(origin, try_fp, occupied):
					continue
				var cells: Array[Vector2i] = _compute_cells(origin, try_fp)
				if require_compat and not _cells_compatible(cells, role, occupied, placed):
					continue
				if require_touch and not _cell_sets_share_edge(_cell_set(cells), anchor_cells):
					continue
				var score: int = _placement_score(
					cells, anchors, vertical_ids, placed, target_cells)
				if score > best_score:
					best_score = score
					best = {"origin": origin, "footprint": try_fp, "cells": cells}
	return best


func _best_grown_against_anchors(
		target_cells: int,
		hint: String,
		occupied: Dictionary,
		role: String,
		placed: Dictionary,
		anchors: Array[String],
		require_compat: bool,
		require_touch: bool) -> Dictionary:
	if anchors.is_empty():
		return {}
	var anchor_cells: Array[Vector2i] = _concat_room_cells(placed, anchors)
	var seeds: Array[Vector2i] = _empty_seeds(anchor_cells, occupied)
	_sort_seeds(seeds, anchor_cells, hint)
	var best: Dictionary = {}
	var best_score: int = -1
	for seed in seeds:
		var grown: Array[Vector2i] = _grow_from_seed(
			seed, target_cells, occupied, role, placed, require_compat, hint)
		if grown.is_empty():
			continue
		if require_touch and not _cell_sets_share_edge(_cell_set(grown), anchor_cells):
			continue
		var score: int = _placement_score(grown, anchors, [], placed, target_cells)
		if score > best_score:
			best_score = score
			best = {
				"origin": _origin_of(grown),
				"footprint": _bbox_fp(grown),
				"cells": grown,
			}
	return best


func _best_aligned_rect(
		fp: Vector2i,
		hint: String,
		occupied: Dictionary,
		role: String,
		placed: Dictionary,
		vertical_ids: Array[String],
		target_cells: int) -> Dictionary:
	var fps: Array[Vector2i] = [fp]
	if fp.x != fp.y:
		fps.append(Vector2i(fp.y, fp.x))
	var partner_cells: Array[Vector2i] = _concat_room_cells(placed, vertical_ids)
	var seeds: Array[Vector2i] = []
	var seen_seed: Dictionary = {}
	for cell in partner_cells:
		var xz: Vector2i = Vector2i(cell.x, cell.y)
		if seen_seed.has(xz):
			continue
		seen_seed[xz] = true
		seeds.append(xz)
	if seeds.is_empty():
		seeds.append(Vector2i.ZERO)
	_sort_seeds(seeds, seeds, hint)

	var best: Dictionary = {}
	var best_score: int = -1
	var seen: Dictionary = {}
	for try_fp in fps:
		for seed in seeds:
			for origin in _origins_covering(seed, try_fp):
				var key: String = "%d_%d_%d_%d" % [origin.x, origin.y, try_fp.x, try_fp.y]
				if seen.has(key):
					continue
				seen[key] = true
				if not _can_place(origin, try_fp, occupied):
					continue
				var cells: Array[Vector2i] = _compute_cells(origin, try_fp)
				if not _cells_compatible(cells, role, occupied, placed):
					continue
				var score: int = _placement_score(cells, [], vertical_ids, placed, target_cells)
				if score > best_score:
					best_score = score
					best = {"origin": origin, "footprint": try_fp, "cells": cells}
		if not best.is_empty():
			continue
		var fallback_origin: Vector2i = seeds[0]
		if _can_place(fallback_origin, try_fp, occupied):
			var cells: Array[Vector2i] = _compute_cells(fallback_origin, try_fp)
			if _cells_compatible(cells, role, occupied, placed):
				return {"origin": fallback_origin, "footprint": try_fp, "cells": cells}
	return best


func _placement_score(
		cells: Array[Vector2i],
		same_deck_ids: Array[String],
		vertical_ids: Array[String],
		placed: Dictionary,
		target_cells: int) -> int:
	var score: int = _connector_score(cells, same_deck_ids, placed) * 1000
	score += _xz_overlap_count(cells, vertical_ids, placed) * 10
	score += target_cells - absi(cells.size() - target_cells)
	return score


func _connector_score(
		cells: Array[Vector2i], desired: Array[String], placed: Dictionary) -> int:
	var cell_set: Dictionary = _cell_set(cells)
	var score: int = 0
	for aid in desired:
		if not placed.has(aid):
			continue
		if _cell_sets_share_edge(cell_set, placed[aid].get("cells", [])):
			score += 1
	return score


func _xz_overlap_count(
		cells: Array[Vector2i], vertical_ids: Array[String], placed: Dictionary) -> int:
	if vertical_ids.is_empty():
		return 0
	var partner: Dictionary = {}
	for vid in vertical_ids:
		if not placed.has(vid):
			continue
		for cell in _as_cells(placed[vid].get("cells", [])):
			partner[Vector2i(cell.x, cell.y)] = true
	var count: int = 0
	for cell in cells:
		if partner.has(Vector2i(cell.x, cell.y)):
			count += 1
	return count


func _concat_room_cells(placed: Dictionary, ids: Array[String]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for rid in ids:
		if not placed.has(rid):
			continue
		for cell in _as_cells(placed[rid].get("cells", [])):
			cells.append(cell)
	return cells


func _empty_seeds(anchor_cells: Array[Vector2i], occupied: Dictionary) -> Array[Vector2i]:
	var seeds: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in anchor_cells:
		for dir in ALL_DIRS:
			var seed: Vector2i = Vector2i(cell.x + dir.x, cell.y + dir.y)
			if occupied.has(seed) or seen.has(seed):
				continue
			seen[seed] = true
			seeds.append(seed)
	return seeds


func _sort_seeds(seeds: Array[Vector2i], anchor_cells: Array[Vector2i], hint: String) -> void:
	for i in range(1, seeds.size()):
		var key: Vector2i = seeds[i]
		var j: int = i
		while j > 0 and _seed_less(key, seeds[j - 1], anchor_cells, hint):
			seeds[j] = seeds[j - 1]
			j -= 1
		seeds[j] = key


func _seed_less(
		a: Vector2i, b: Vector2i, anchor_cells: Array[Vector2i], hint: String) -> bool:
	var ra: int = _seed_rank(a, anchor_cells, hint)
	var rb: int = _seed_rank(b, anchor_cells, hint)
	if ra != rb:
		return ra < rb
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


func _seed_rank(seed: Vector2i, anchor_cells: Array[Vector2i], hint: String) -> int:
	if anchor_cells.is_empty():
		return 0
	var nearest: Vector2i = _nearest_cell(seed, anchor_cells)
	var delta: Vector2i = Vector2i(seed.x - nearest.x, seed.y - nearest.y)
	var preferred: Array = HINT_DIRECTIONS.get(hint, ALL_DIRS)
	for i in range(preferred.size()):
		if preferred[i] == delta:
			return i
	return preferred.size()


func _nearest_cell(seed: Vector2i, cells: Array[Vector2i]) -> Vector2i:
	var best: Vector2i = cells[0]
	var best_d: int = 999999
	for cell in cells:
		var d: int = absi(cell.x - seed.x) + absi(cell.y - seed.y)
		if d < best_d:
			best_d = d
			best = cell
	return best


func _origins_covering(seed: Vector2i, fp: Vector2i) -> Array[Vector2i]:
	var origins: Array[Vector2i] = []
	for dx in range(fp.x):
		for dy in range(fp.y):
			origins.append(Vector2i(seed.x - dx, seed.y - dy))
	return origins


func _grow_from_seed(
		seed: Vector2i,
		target_cells: int,
		occupied: Dictionary,
		role: String,
		placed: Dictionary,
		require_compat: bool,
		hint: String) -> Array[Vector2i]:
	if occupied.has(seed):
		return []
	if require_compat and not _cell_compatible(seed, role, occupied, placed):
		return []
	var cells: Array[Vector2i] = [seed]
	var in_set: Dictionary = {seed: true}
	var want: int = maxi(target_cells, 1)
	while cells.size() < want:
		var best: Vector2i = SENTINEL
		var best_score: int = -999999
		for cell in cells:
			for dir in ALL_DIRS:
				var nxt: Vector2i = Vector2i(cell.x + dir.x, cell.y + dir.y)
				if in_set.has(nxt) or occupied.has(nxt):
					continue
				if require_compat and not _cell_compatible(nxt, role, occupied, placed):
					continue
				var score: int = _growth_cell_score(nxt, in_set, seed, hint)
				if score > best_score or (score == best_score and _vec_less(nxt, best)):
					best_score = score
					best = nxt
		if best == SENTINEL:
			break
		cells.append(best)
		in_set[best] = true
	if cells.is_empty():
		return []
	_sort_cells(cells)
	return cells


func _growth_cell_score(
		cell: Vector2i, in_set: Dictionary, seed: Vector2i, hint: String) -> int:
	var neighbors_in_set: int = 0
	for dir in ALL_DIRS:
		if in_set.has(Vector2i(cell.x + dir.x, cell.y + dir.y)):
			neighbors_in_set += 1
	var preferred: Array = HINT_DIRECTIONS.get(hint, ALL_DIRS)
	var hint_bonus: int = 0
	var delta: Vector2i = Vector2i(
		_sign_int(cell.x - seed.x),
		_sign_int(cell.y - seed.y))
	if preferred.size() > 0 and preferred[0] == delta:
		hint_bonus = 2
	var dist: int = absi(cell.x - seed.x) + absi(cell.y - seed.y)
	return neighbors_in_set * 100 + hint_bonus * 10 - dist


func _sign_int(value: int) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0


func _vec_less(a: Vector2i, b: Vector2i) -> bool:
	if b == SENTINEL:
		return true
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


func _coerce_footprint(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Array and (raw as Array).size() >= 2:
		var arr: Array = raw
		return Vector2i(maxi(int(arr[0]), 1), maxi(int(arr[1]), 1))
	return Vector2i(2, 2)


func _min_manhattan(cell: Vector2i, cells: Array[Vector2i]) -> int:
	var best: int = 999999
	for other in cells:
		var d: int = absi(cell.x - other.x) + absi(cell.y - other.y)
		if d < best:
			best = d
	return best


func _commit_room(
		placed: Dictionary,
		occupied: Dictionary,
		rid: String,
		cells: Array[Vector2i],
		deck: int,
		role: String,
		fp: Vector2i) -> void:
	var owned: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in cells:
		if seen.has(cell):
			continue
		seen[cell] = true
		owned.append(cell)
	_sort_cells(owned)
	for cell in owned:
		occupied[cell] = rid
	var origin: Vector2i = _origin_of(owned)
	var stored_fp: Vector2i = fp
	if stored_fp.x <= 0 or stored_fp.y <= 0:
		stored_fp = _bbox_fp(owned)
	placed[rid] = {
		"cells": owned,
		"origin": origin,
		"footprint": stored_fp,
		"deck": deck,
		"role": role,
	}


func _realize_missing_connectors(
		graph: Dictionary,
		zone_rooms_map: Dictionary,
		occupied_per_deck: Dictionary,
		placed: Dictionary) -> void:
	var neighbors: Dictionary = graph.get("neighbors", {})
	var pending: Array = []
	var seen_pairs: Dictionary = {}
	for rid in placed.keys():
		for other in _neighbor_ids(neighbors, str(rid)):
			if not placed.has(other):
				continue
			var key: String = _pair_key(str(rid), other)
			if seen_pairs.has(key):
				continue
			seen_pairs[key] = true
			pending.append([str(rid), other])
	for pair in pending:
		_try_grow_pair(str(pair[0]), str(pair[1]), occupied_per_deck, placed)

	var zone_pairs: Array = graph.get("zone_pairs", [])
	for pair_variant in zone_pairs:
		if typeof(pair_variant) != TYPE_DICTIONARY:
			continue
		var pair: Dictionary = pair_variant
		var zone_a: String = str(pair.get("a", ""))
		var zone_b: String = str(pair.get("b", ""))
		if _zones_share_edge_or_vertical(zone_a, zone_b, zone_rooms_map, placed):
			continue
		var a_ids: Array = zone_rooms_map.get(zone_a, [])
		var b_ids: Array = zone_rooms_map.get(zone_b, [])
		if a_ids.is_empty() or b_ids.is_empty():
			continue
		_try_grow_pair(str(a_ids[a_ids.size() - 1]), str(b_ids[0]), occupied_per_deck, placed)


func _try_grow_pair(
		a: String, b: String, occupied_per_deck: Dictionary, placed: Dictionary) -> void:
	if not placed.has(a) or not placed.has(b):
		return
	var deck_a: int = int(placed[a].get("deck", 0))
	var deck_b: int = int(placed[b].get("deck", 0))
	if deck_a != deck_b:
		return
	if _rooms_share_edge(placed, a, b):
		return
	var occupied: Dictionary = occupied_per_deck[deck_a]
	if _grow_room_to_touch(b, a, occupied, placed):
		return
	_grow_room_to_touch(a, b, occupied, placed)


func _zones_share_edge_or_vertical(
		zone_a: String, zone_b: String, zone_rooms_map: Dictionary, placed: Dictionary) -> bool:
	for ar in zone_rooms_map.get(zone_a, []):
		for br in zone_rooms_map.get(zone_b, []):
			if not placed.has(str(ar)) or not placed.has(str(br)):
				continue
			var deck_a: int = int(placed[str(ar)].get("deck", 0))
			var deck_b: int = int(placed[str(br)].get("deck", 0))
			if deck_a != deck_b:
				return true
			if _rooms_share_edge(placed, str(ar), str(br)):
				return true
	return false


func _grow_room_to_touch(
		from_id: String, to_id: String, occupied: Dictionary, placed: Dictionary) -> bool:
	var from_cells: Array[Vector2i] = _as_cells(placed[from_id].get("cells", []))
	var to_cells: Array[Vector2i] = _as_cells(placed[to_id].get("cells", []))
	if from_cells.is_empty() or to_cells.is_empty():
		return false
	var to_set: Dictionary = _cell_set(to_cells)
	if _cell_sets_share_edge(_cell_set(from_cells), to_cells):
		return true
	var from_set: Dictionary = _cell_set(from_cells)
	var prev: Dictionary = {}
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for cell in from_cells:
		queue.append(cell)
		seen[cell] = true
	var hit: Vector2i = SENTINEL
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for dir in ALL_DIRS:
			var nxt: Vector2i = Vector2i(cur.x + dir.x, cur.y + dir.y)
			if to_set.has(nxt):
				hit = cur
				queue.clear()
				break
			if seen.has(nxt):
				continue
			if occupied.has(nxt) and str(occupied[nxt]) != from_id:
				continue
			if _min_manhattan(nxt, from_cells) > MAX_GROW_STEPS:
				continue
			seen[nxt] = true
			prev[nxt] = cur
			queue.append(nxt)
	if hit == SENTINEL:
		return false
	if from_set.has(hit):
		return _rooms_share_edge(placed, from_id, to_id)
	var path: Array[Vector2i] = []
	var walk: Vector2i = hit
	var guard: int = 0
	while not from_set.has(walk) and guard < MAX_GROW_STEPS:
		path.append(walk)
		if not prev.has(walk):
			break
		walk = prev[walk]
		guard += 1
	if path.is_empty() or path.size() > MAX_GROW_STEPS:
		return false
	var merged: Array[Vector2i] = []
	for cell in from_cells:
		merged.append(cell)
	for cell in path:
		if occupied.has(cell) and str(occupied[cell]) != from_id:
			return false
		if from_set.has(cell):
			continue
		merged.append(cell)
		occupied[cell] = from_id
		from_set[cell] = true
	_sort_cells(merged)
	placed[from_id]["cells"] = merged
	placed[from_id]["origin"] = _origin_of(merged)
	placed[from_id]["footprint"] = _bbox_fp(merged)
	return _rooms_share_edge(placed, from_id, to_id)


func _can_place(origin: Vector2i, fp: Vector2i, occupied: Dictionary) -> bool:
	for dx in range(fp.x):
		for dz in range(fp.y):
			if occupied.has(Vector2i(origin.x + dx, origin.y + dz)):
				return false
	return true


func _cells_compatible(
		cells: Array[Vector2i], new_role: String, occupied: Dictionary, placed: Dictionary) -> bool:
	if new_role.is_empty() or CONNECTIVE_ROLES.has(new_role):
		return true
	var is_hazardous: bool = HAZARDOUS_ROLES.has(new_role)
	var is_comfort: bool = CREW_COMFORT_ROLES.has(new_role)
	if not is_hazardous and not is_comfort:
		return true
	for cell in cells:
		if not _cell_compatible(cell, new_role, occupied, placed):
			return false
	return true


func _cell_compatible(
		cell: Vector2i, new_role: String, occupied: Dictionary, placed: Dictionary) -> bool:
	if new_role.is_empty() or CONNECTIVE_ROLES.has(new_role):
		return true
	var is_hazardous: bool = HAZARDOUS_ROLES.has(new_role)
	var is_comfort: bool = CREW_COMFORT_ROLES.has(new_role)
	if not is_hazardous and not is_comfort:
		return true
	for dir in ALL_DIRS:
		var neighbor: Vector2i = Vector2i(cell.x + dir.x, cell.y + dir.y)
		if not occupied.has(neighbor):
			continue
		var neighbor_rid: String = str(occupied[neighbor])
		if not placed.has(neighbor_rid):
			continue
		var neighbor_role: String = str(placed[neighbor_rid].get("role", ""))
		if is_hazardous and CREW_COMFORT_ROLES.has(neighbor_role):
			return false
		if is_comfort and HAZARDOUS_ROLES.has(neighbor_role):
			return false
	return true


func _compute_cells(origin: Vector2i, fp: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(fp.x):
		for dz in range(fp.y):
			cells.append(Vector2i(origin.x + dx, origin.y + dz))
	return cells


func _sort_cells(cells: Array[Vector2i]) -> void:
	for i in range(1, cells.size()):
		var key: Vector2i = cells[i]
		var j: int = i
		while j > 0 and _vec_less(key, cells[j - 1]):
			cells[j] = cells[j - 1]
			j -= 1
		cells[j] = key


func _origin_of(cells: Array[Vector2i]) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var min_x: int = cells[0].x
	var min_y: int = cells[0].y
	for cell in cells:
		if cell.x < min_x:
			min_x = cell.x
		if cell.y < min_y:
			min_y = cell.y
	return Vector2i(min_x, min_y)


func _bbox_fp(cells: Array[Vector2i]) -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var origin: Vector2i = _origin_of(cells)
	var max_x: int = origin.x
	var max_y: int = origin.y
	for cell in cells:
		if cell.x > max_x:
			max_x = cell.x
		if cell.y > max_y:
			max_y = cell.y
	return Vector2i(max_x - origin.x + 1, max_y - origin.y + 1)


func _as_cells(raw: Variant) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if raw is Array:
		for item in raw:
			if item is Vector2i:
				cells.append(item)
	return cells


func _cell_set(cells: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for cell in cells:
		result[cell] = true
	return result


func _cell_sets_share_edge(a_set: Dictionary, b_cells_raw: Variant) -> bool:
	var b_cells: Array[Vector2i] = _as_cells(b_cells_raw)
	for cell in b_cells:
		for dir in ALL_DIRS:
			if a_set.has(Vector2i(cell.x + dir.x, cell.y + dir.y)):
				return true
	return false


func _rooms_share_edge(placed: Dictionary, a: String, b: String) -> bool:
	if not placed.has(a) or not placed.has(b):
		return false
	return _cell_sets_share_edge(
		_cell_set(_as_cells(placed[a].get("cells", []))),
		placed[b].get("cells", []))


func _discover_adjacencies(placed: Dictionary) -> Array[Dictionary]:
	var cell_to_room: Dictionary = {}
	for rid in placed.keys():
		var room_data: Dictionary = placed[rid]
		var deck: int = int(room_data.get("deck", 0))
		for cell in _as_cells(room_data.get("cells", [])):
			var key: String = "%d_%d_%d" % [cell.x, cell.y, deck]
			cell_to_room[key] = str(rid)

	var adjacencies: Array[Dictionary] = []
	var seen_pairs: Dictionary = {}

	for rid in placed.keys():
		var room_id: String = str(rid)
		var room_data: Dictionary = placed[rid]
		var deck: int = int(room_data.get("deck", 0))
		for cell in _as_cells(room_data.get("cells", [])):
			for dir in ALL_DIRS:
				var neighbor_cell: Vector2i = Vector2i(cell.x + dir.x, cell.y + dir.y)
				var key: String = "%d_%d_%d" % [neighbor_cell.x, neighbor_cell.y, deck]
				if not cell_to_room.has(key):
					continue
				var neighbor_id: String = str(cell_to_room[key])
				if neighbor_id == room_id:
					continue
				var pair_key: String = _pair_key(room_id, neighbor_id)
				if seen_pairs.has(pair_key):
					continue
				seen_pairs[pair_key] = true
				adjacencies.append({
					"from_room": room_id,
					"to_room": neighbor_id,
					"from_cell": cell,
					"to_cell": neighbor_cell,
				})

	return adjacencies


func _add_vertical_adjacencies(
		adjacencies: Array[Dictionary],
		placed: Dictionary,
		graph: Dictionary,
		zone_rooms_map: Dictionary,
		template: RefCounted) -> void:
	var existing_pairs: Dictionary = {}
	for adj in adjacencies:
		existing_pairs[_pair_key(str(adj["from_room"]), str(adj["to_room"]))] = true

	var neighbors: Dictionary = graph.get("neighbors", {})
	for rid in placed.keys():
		for other in _neighbor_ids(neighbors, str(rid)):
			_maybe_add_vertical(adjacencies, existing_pairs, placed, str(rid), other)

	var zone_pairs: Array = graph.get("zone_pairs", [])
	for pair_variant in zone_pairs:
		if typeof(pair_variant) != TYPE_DICTIONARY:
			continue
		var pair: Dictionary = pair_variant
		var from_zone: String = str(pair.get("a", ""))
		var to_zone: String = str(pair.get("b", ""))
		if _zone_pair_already_linked(from_zone, to_zone, zone_rooms_map, existing_pairs):
			continue
		var from_rid: String = _last_placed_in_zone(from_zone, zone_rooms_map, placed)
		var to_rid: String = _first_placed_in_zone(to_zone, zone_rooms_map, placed)
		_maybe_add_vertical(adjacencies, existing_pairs, placed, from_rid, to_rid)

	# attach_to remains a vertical fallback when a child zone sits on another deck
	# and connections already covered the zone pair as a same-deck miss.
	for zone in template.zones:
		var child_zone_id: String = str(zone.get("id", ""))
		var parent_zone_id: String = str(zone.get("attach_to", ""))
		if parent_zone_id.is_empty():
			continue
		if _zone_pair_already_linked(parent_zone_id, child_zone_id, zone_rooms_map, existing_pairs):
			continue
		var parent_rid: String = _last_placed_in_zone(parent_zone_id, zone_rooms_map, placed)
		var child_rid: String = _first_placed_in_zone(child_zone_id, zone_rooms_map, placed)
		_maybe_add_vertical(adjacencies, existing_pairs, placed, parent_rid, child_rid)


func _maybe_add_vertical(
		adjacencies: Array[Dictionary],
		existing_pairs: Dictionary,
		placed: Dictionary,
		from_rid: String,
		to_rid: String) -> void:
	if from_rid.is_empty() or to_rid.is_empty():
		return
	if not placed.has(from_rid) or not placed.has(to_rid):
		return
	var pk: String = _pair_key(from_rid, to_rid)
	if existing_pairs.has(pk):
		return
	var from_deck: int = int(placed[from_rid].get("deck", 0))
	var to_deck: int = int(placed[to_rid].get("deck", 0))
	if from_deck == to_deck:
		# Same-deck declared connections must already be real shared edges.
		# Inventing a doorway between non-touching rooms is forbidden.
		return
	existing_pairs[pk] = true
	var pair_cells: Dictionary = _vertical_cell_pair(
		_as_cells(placed[from_rid].get("cells", [])),
		_as_cells(placed[to_rid].get("cells", [])))
	adjacencies.append({
		"from_room": from_rid,
		"to_room": to_rid,
		"from_cell": pair_cells.get("from_cell", Vector2i.ZERO),
		"to_cell": pair_cells.get("to_cell", Vector2i.ZERO),
	})


func _zone_pair_already_linked(
		zone_a: String, zone_b: String, zone_rooms_map: Dictionary, existing_pairs: Dictionary) -> bool:
	for ar in zone_rooms_map.get(zone_a, []):
		for br in zone_rooms_map.get(zone_b, []):
			if existing_pairs.has(_pair_key(str(ar), str(br))):
				return true
	return false


func _last_placed_in_zone(zone_id: String, zone_rooms_map: Dictionary, placed: Dictionary) -> String:
	var best: String = ""
	for rid in zone_rooms_map.get(zone_id, []):
		if placed.has(str(rid)):
			best = str(rid)
	return best


func _first_placed_in_zone(zone_id: String, zone_rooms_map: Dictionary, placed: Dictionary) -> String:
	for rid in zone_rooms_map.get(zone_id, []):
		if placed.has(str(rid)):
			return str(rid)
	return ""


func _vertical_cell_pair(from_cells: Array[Vector2i], to_cells: Array[Vector2i]) -> Dictionary:
	for from_cell in from_cells:
		for to_cell in to_cells:
			if from_cell.x == to_cell.x and from_cell.y == to_cell.y:
				return {"from_cell": from_cell, "to_cell": to_cell}
	return {
		"from_cell": from_cells[0] if not from_cells.is_empty() else Vector2i.ZERO,
		"to_cell": to_cells[0] if not to_cells.is_empty() else Vector2i.ZERO,
	}


func _room_by_id(room_plan: Array[Dictionary], rid: String) -> Dictionary:
	for room in room_plan:
		if str(room["id"]) == rid:
			return room
	return {}


# "spine", "spine[0]", "spine[*]", "spine[*+1]" all refer to zone "spine".
func _zone_ref_id(zone_ref: String) -> String:
	return str(_parse_zone_ref(zone_ref).get("id", ""))


func _pair_key(a: String, b: String) -> String:
	if a < b:
		return a + "|" + b
	return b + "|" + a
