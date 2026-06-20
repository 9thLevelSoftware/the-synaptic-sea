extends RefCounted
class_name CellLayoutEngine

const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0

const DIR_NORTH: Vector2i = Vector2i(0, -1)
const DIR_EAST: Vector2i = Vector2i(1, 0)
const DIR_SOUTH: Vector2i = Vector2i(0, 1)
const DIR_WEST: Vector2i = Vector2i(-1, 0)
const ALL_DIRS: Array[Vector2i] = [DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST]

const HINT_DIRECTIONS: Dictionary = {
	"bow":     [DIR_NORTH, DIR_EAST, DIR_WEST, DIR_SOUTH],
	"stern":   [DIR_SOUTH, DIR_EAST, DIR_WEST, DIR_NORTH],
	"lateral": [DIR_EAST, DIR_WEST, DIR_NORTH, DIR_SOUTH],
	"center":  [DIR_EAST, DIR_SOUTH, DIR_NORTH, DIR_WEST],
}

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func layout(room_plan: Array[Dictionary], template: RefCounted, seed_value: int) -> Dictionary:
	rng.seed = seed_value

	# room_id -> zone_id for parent lookup
	var room_zone_map: Dictionary = {}
	for room in room_plan:
		room_zone_map[str(room["id"])] = str(room.get("zone_id", ""))

	# zone_id -> [room_id, ...] for finding parent zone rooms
	var zone_rooms_map: Dictionary = {}
	for room in room_plan:
		var zid: String = str(room.get("zone_id", ""))
		if not zone_rooms_map.has(zid):
			zone_rooms_map[zid] = []
		zone_rooms_map[zid].append(str(room["id"]))

	var zone_order: Array[Dictionary] = _build_zone_order(template)

	# deck -> (Vector2i -> room_id)
	var occupied_per_deck: Dictionary = {}
	# room_id -> {cells, origin, footprint, deck}
	var placed: Dictionary = {}

	for zone_info in zone_order:
		var zone_id: String = str(zone_info["id"])
		var parent_zone_id: String = str(zone_info.get("attach_to", ""))
		var zone_room_ids: Array = zone_rooms_map.get(zone_id, [])

		# Tracks the last room placed within this zone for intra-zone chaining
		var last_in_zone: String = ""

		for room_id in zone_room_ids:
			var room: Dictionary = {}
			for r in room_plan:
				if str(r["id"]) == room_id:
					room = r
					break

			var rid: String = str(room["id"])
			var fp: Vector2i = room["footprint"]
			var deck: int = int(room.get("deck", 0))
			var hint: String = str(room.get("position_hint", "center"))

			if not occupied_per_deck.has(deck):
				occupied_per_deck[deck] = {}
			var occupied: Dictionary = occupied_per_deck[deck]

			var origin: Vector2i
			if placed.is_empty():
				origin = Vector2i(0, 0)
			else:
				# Prefer chaining to prior room in this zone, then parent zone, then any
				var preferred_anchor: String = ""
				if not last_in_zone.is_empty() and placed.has(last_in_zone):
					preferred_anchor = last_in_zone
				else:
					preferred_anchor = _find_parent_room(parent_zone_id, zone_rooms_map, placed)
				if preferred_anchor.is_empty():
					preferred_anchor = _last_placed_id(placed)

				# Try preferred anchor first, then fall back to any placed room
				# This guarantees physical adjacency for connectivity
				origin = _find_adjacent_to_any(fp, hint, occupied, placed, preferred_anchor)
				if origin == Vector2i(-99999, -99999):
					var rotated_fp: Vector2i = Vector2i(fp.y, fp.x)
					origin = _find_adjacent_to_any(rotated_fp, hint, occupied, placed, preferred_anchor)
					if origin != Vector2i(-99999, -99999):
						fp = rotated_fp

				if origin == Vector2i(-99999, -99999):
					push_error("CellLayoutEngine: could not place room %s" % rid)
					continue

			var cells: Array[Vector2i] = _compute_cells(origin, fp)
			for cell in cells:
				occupied[cell] = rid

			placed[rid] = {
				"cells": cells,
				"origin": origin,
				"footprint": fp,
				"deck": deck,
			}
			last_in_zone = rid

	var adjacencies: Array[Dictionary] = _discover_adjacencies(placed)

	# Add logical connections for cross-deck zone relationships
	# (cell adjacency can't discover these since rooms are on separate deck grids)
	_add_cross_deck_adjacencies(adjacencies, placed, room_zone_map, zone_rooms_map, template)

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


func _find_parent_room(parent_zone_id: String, zone_rooms_map: Dictionary, placed: Dictionary) -> String:
	if parent_zone_id.is_empty():
		return _last_placed_id(placed)

	var candidates: Array = zone_rooms_map.get(parent_zone_id, [])
	# Return the last placed room from the parent zone
	var best: String = ""
	for rid in candidates:
		if placed.has(rid):
			best = rid
	return best


func _last_placed_id(placed: Dictionary) -> String:
	var keys: Array = placed.keys()
	if keys.is_empty():
		return ""
	return str(keys[keys.size() - 1])


func _find_adjacent_to_any(new_fp: Vector2i, hint: String, occupied: Dictionary,
		placed: Dictionary, preferred_anchor: String) -> Vector2i:
	# Try preferred anchor first, then all others, so every placed room is
	# physically adjacent to at least one existing room (guarantees connectivity).
	var anchor_order: Array = []
	if not preferred_anchor.is_empty():
		anchor_order.append(preferred_anchor)
	for rid in placed.keys():
		if str(rid) != preferred_anchor:
			anchor_order.append(str(rid))

	for anchor_id in anchor_order:
		var anchor_data: Dictionary = placed[anchor_id]
		var anchor_origin: Vector2i = anchor_data.get("origin", Vector2i.ZERO)
		var anchor_fp: Vector2i = anchor_data.get("footprint", Vector2i(1, 1))
		var result: Vector2i = _find_placement_adjacent(anchor_origin, anchor_fp, new_fp, hint, occupied)
		if result != Vector2i(-99999, -99999):
			return result

	return Vector2i(-99999, -99999)


func _find_placement_adjacent(anchor_origin: Vector2i, anchor_fp: Vector2i, new_fp: Vector2i,
		hint: String, occupied: Dictionary) -> Vector2i:
	var preferred: Array = HINT_DIRECTIONS.get(hint, ALL_DIRS)

	# Try each direction; for each direction, try aligned then shifted placements.
	# Shifts stay within anchor bounds so new room always shares an edge with anchor.
	for dir in preferred:
		var result: Vector2i = _try_dir_with_shifts(anchor_origin, anchor_fp, new_fp, dir, occupied)
		if result != Vector2i(-99999, -99999):
			return result

	for dir in ALL_DIRS:
		var result: Vector2i = _try_dir_with_shifts(anchor_origin, anchor_fp, new_fp, dir, occupied)
		if result != Vector2i(-99999, -99999):
			return result

	return Vector2i(-99999, -99999)


func _try_dir_with_shifts(anchor_origin: Vector2i, anchor_fp: Vector2i, new_fp: Vector2i,
		dir: Vector2i, occupied: Dictionary) -> Vector2i:
	# Base position: new room flush with anchor edge in direction dir
	var base: Vector2i = _adjacent_origin(anchor_origin, anchor_fp, new_fp, dir)
	if _can_place(base, new_fp, occupied):
		return base

	# Shift along the perpendicular axis. Limit shifts so new room still
	# overlaps the anchor's extent on that axis (guarantees shared edge).
	if dir.x == 0:
		# Moving north/south: shift east/west within anchor width
		var max_shift: int = anchor_fp.x + new_fp.x - 1
		for shift in range(-max_shift, max_shift + 1):
			if shift == 0:
				continue
			var shifted: Vector2i = Vector2i(base.x + shift, base.y)
			# Verify new room still overlaps anchor on X axis (shares an edge)
			var new_right: int = shifted.x + new_fp.x
			var anchor_right: int = anchor_origin.x + anchor_fp.x
			if shifted.x >= anchor_right or new_right <= anchor_origin.x:
				continue
			if _can_place(shifted, new_fp, occupied):
				return shifted
	else:
		# Moving east/west: shift north/south within anchor height
		var max_shift: int = anchor_fp.y + new_fp.y - 1
		for shift in range(-max_shift, max_shift + 1):
			if shift == 0:
				continue
			var shifted: Vector2i = Vector2i(base.x, base.y + shift)
			var new_bottom: int = shifted.y + new_fp.y
			var anchor_bottom: int = anchor_origin.y + anchor_fp.y
			if shifted.y >= anchor_bottom or new_bottom <= anchor_origin.y:
				continue
			if _can_place(shifted, new_fp, occupied):
				return shifted

	return Vector2i(-99999, -99999)


func _adjacent_origin(anchor_origin: Vector2i, anchor_fp: Vector2i,
		new_fp: Vector2i, dir: Vector2i) -> Vector2i:
	if dir == DIR_NORTH:
		return Vector2i(anchor_origin.x, anchor_origin.y - new_fp.y)
	elif dir == DIR_EAST:
		return Vector2i(anchor_origin.x + anchor_fp.x, anchor_origin.y)
	elif dir == DIR_SOUTH:
		return Vector2i(anchor_origin.x, anchor_origin.y + anchor_fp.y)
	else:
		return Vector2i(anchor_origin.x - new_fp.x, anchor_origin.y)


func _can_place(origin: Vector2i, fp: Vector2i, occupied: Dictionary) -> bool:
	for dx in range(fp.x):
		for dz in range(fp.y):
			if occupied.has(Vector2i(origin.x + dx, origin.y + dz)):
				return false
	return true


func _compute_cells(origin: Vector2i, fp: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for dx in range(fp.x):
		for dz in range(fp.y):
			cells.append(Vector2i(origin.x + dx, origin.y + dz))
	return cells


func _discover_adjacencies(placed: Dictionary) -> Array[Dictionary]:
	var cell_to_room: Dictionary = {}
	for rid in placed.keys():
		var room_data: Dictionary = placed[rid]
		var deck: int = int(room_data.get("deck", 0))
		for cell in room_data.get("cells", []):
			var key: String = "%d_%d_%d" % [cell.x, cell.y, deck]
			cell_to_room[key] = str(rid)

	var adjacencies: Array[Dictionary] = []
	var seen_pairs: Dictionary = {}

	for rid in placed.keys():
		var room_data: Dictionary = placed[rid]
		var deck: int = int(room_data.get("deck", 0))
		for cell in room_data.get("cells", []):
			for dir in ALL_DIRS:
				var neighbor_cell: Vector2i = Vector2i(cell.x + dir.x, cell.y + dir.y)
				var key: String = "%d_%d_%d" % [neighbor_cell.x, neighbor_cell.y, deck]
				if not cell_to_room.has(key):
					continue
				var neighbor_id: String = cell_to_room[key]
				if neighbor_id == rid:
					continue
				var pair_key: String = _pair_key(rid, neighbor_id)
				if seen_pairs.has(pair_key):
					continue
				seen_pairs[pair_key] = true
				adjacencies.append({
					"from_room": rid,
					"to_room": neighbor_id,
					"from_cell": cell,
					"to_cell": neighbor_cell,
				})

	return adjacencies


func _add_cross_deck_adjacencies(adjacencies: Array[Dictionary], placed: Dictionary,
		room_zone_map: Dictionary, zone_rooms_map: Dictionary, template: RefCounted) -> void:
	# Build set of already-connected pairs
	var existing_pairs: Dictionary = {}
	for adj in adjacencies:
		existing_pairs[_pair_key(str(adj["from_room"]), str(adj["to_room"]))] = true

	# For each zone connection in the template, if the rooms are on different
	# decks, add a logical adjacency between the last room in the parent zone
	# and the first room in the child zone.
	for zone in template.zones:
		var child_zone_id: String = str(zone.get("id", ""))
		var parent_zone_id: String = str(zone.get("attach_to", ""))
		if parent_zone_id.is_empty():
			continue

		var parent_rooms: Array = zone_rooms_map.get(parent_zone_id, [])
		var child_rooms: Array = zone_rooms_map.get(child_zone_id, [])
		if parent_rooms.is_empty() or child_rooms.is_empty():
			continue

		# Use last placed room from parent, first placed room from child
		var parent_rid: String = ""
		for rid in parent_rooms:
			if placed.has(rid):
				parent_rid = rid
		var child_rid: String = ""
		for rid in child_rooms:
			if placed.has(rid):
				child_rid = rid
				break

		if parent_rid.is_empty() or child_rid.is_empty():
			continue
		if not placed.has(parent_rid) or not placed.has(child_rid):
			continue

		var parent_deck: int = int(placed[parent_rid].get("deck", 0))
		var child_deck: int = int(placed[child_rid].get("deck", 0))
		if parent_deck == child_deck:
			continue  # Same-deck adjacencies are handled by cell discovery

		var pk: String = _pair_key(parent_rid, child_rid)
		if existing_pairs.has(pk):
			continue

		existing_pairs[pk] = true
		var parent_cells: Array = placed[parent_rid].get("cells", [])
		var child_cells: Array = placed[child_rid].get("cells", [])
		var from_cell: Vector2i = parent_cells[0] if not parent_cells.is_empty() else Vector2i.ZERO
		var to_cell: Vector2i = child_cells[0] if not child_cells.is_empty() else Vector2i.ZERO

		adjacencies.append({
			"from_room": parent_rid,
			"to_room": child_rid,
			"from_cell": from_cell,
			"to_cell": to_cell,
		})


func _pair_key(a: String, b: String) -> String:
	if a < b:
		return a + "|" + b
	return b + "|" + a
