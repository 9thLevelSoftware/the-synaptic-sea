extends RefCounted
class_name WorldV6LayoutProjection

## Version-pinned world-6 room/cell and attachment projection.
##
## This file intentionally embeds only the c51bcac room assignment and cell
## placement closure. It never preloads mutable current procgen or endpoint
## sources, never touches the scene tree, and returns detached Dictionaries.
##
## resolve_authenticated_candidates() is a public orchestration seam. Its
## candidate_set_complete argument is trusted migration authority established
## by project_procedural(); it is never accepted from persisted save data.

const AUTHORITY_PATH: String = "res://data/migrations/world_v6_geometry_authority_v1.json"
const AUTHORITY_SCHEMA: String = "world-v6-geometry-authority-1"
const SOURCE_COMMIT: String = "c51bcacbcb5557fd54ccf5a3e2775f0e35c61bad"
const LEGACY_TEMPLATES: Array[String] = ["spine", "bifurcated", "stacked"]
const MAX_CONNECTIVITY_ATTEMPTS: int = 4
const RETRY_SALT: int = 0x9E3779B9
const CELL_SIZE: float = 4.0
const DECK_HEIGHT: float = 4.0
const HALF_CELL: float = 2.0
const AIRLOCK_SIZE_CLASS: int = 1
const CELLS_PER_SLOT: int = 2
const HANGAR_BIG_CELL_THRESHOLD: int = 4

class FrozenBlueprint:
	extends RefCounted

	var size: int = 2
	var condition: int = 0
	var seed_value: int = 0
	var room_count_range: Vector2i = Vector2i(8, 12)
	var generation_context_v1: Dictionary = {}


class FrozenTopologyTemplate:
	extends RefCounted

	var id: String = ""
	var description: String = ""
	var zones: Array[Dictionary] = []
	var connections: Array[Dictionary] = []
	var deck_config: Dictionary = {}

	static func from_dict(data: Dictionary):
		var template = FrozenTopologyTemplate.new()
		template.id = str(data.get("id", ""))
		template.description = str(data.get("description", ""))
		var raw_zones: Variant = data.get("zones", [])
		if raw_zones is Array:
			for zone_v in raw_zones:
				if not zone_v is Dictionary:
					continue
				var zone: Dictionary = zone_v
				var pool: Array[String] = []
				for role_v in zone.get("role_pool", []) as Array:
					pool.append(str(role_v))
				template.zones.append({
					"id": str(zone.get("id", "")), "role_pool": pool,
					"count": zone.get("count", 1),
					"position_hint": str(zone.get("position_hint", "center")),
					"deck": int(zone.get("deck", 0)),
					"layout": str(zone.get("layout", "single")),
					"attach_to": str(zone.get("attach_to", "")),
				})
		var raw_connections: Variant = data.get("connections", [])
		if raw_connections is Array:
			for connection_v in raw_connections:
				if connection_v is Dictionary:
					var connection: Dictionary = connection_v
					template.connections.append({
						"from": str(connection.get("from", "")),
						"to": str(connection.get("to", "")),
						"distribution": str(connection.get("distribution", "adjacent")),
					})
		var raw_deck: Variant = data.get("deck_config", {})
		if raw_deck is Dictionary:
			template.deck_config = {
				"max_decks": int((raw_deck as Dictionary).get("max_decks", 1)),
				"vertical_transition_probability": float(
					(raw_deck as Dictionary).get("vertical_transition_probability", 0.0)),
			}
		return template

	func get_zones_attached_to(parent_zone_id: String) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for zone in zones:
			if str(zone.get("attach_to", "")) == parent_zone_id:
				result.append(zone)
		return result


class FrozenRoomAssigner:
	extends RefCounted
	
	# Fills template zones with concrete rooms. Each zone produces 1..N rooms
	# based on its count field. Roles are picked from the zone's role_pool
	# using archetype weights when available. Each room gets a footprint
	# based on the ROOM_FOOTPRINT_OPTIONS table and the blueprint size.
	
	
	# Footprint options per role: array of Vector2i choices.
	# Larger blueprints (MEDIUM) pick from the full range; SMALL picks from
	# smaller options.
	const ROOM_FOOTPRINT_OPTIONS: Dictionary = {
		"airlock":        [Vector2i(2, 2), Vector2i(3, 2)],
		"dock":           [Vector2i(2, 2), Vector2i(3, 2)],
		"corridor":       [Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 1), Vector2i(5, 1)],
		"engineering":    [Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)],
		"bridge":         [Vector2i(3, 2), Vector2i(3, 3)],
		"cargo":          [Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 3)],
		"bay":            [Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 3)],
		"hangar":         [Vector2i(2, 2), Vector2i(3, 3), Vector2i(2, 3)],
		"compartment":    [Vector2i(2, 2)],
		"medical":        [Vector2i(2, 2), Vector2i(2, 1)],
		"quarters":       [Vector2i(2, 2)],
		"crew_quarters":  [Vector2i(2, 2), Vector2i(2, 1)],
		"mess_hall":      [Vector2i(2, 2), Vector2i(3, 2)],
		"armory":         [Vector2i(1, 2), Vector2i(2, 2)],
		# Vault guard-wing security rooms formerly took the implicit default 2x2
		# fallback.  Keep their authored role distinct from an armory and make its
		# compact guard-post footprint an explicit catalog contract.
		"security":       [Vector2i(2, 2)],
		"maintenance":    [Vector2i(1, 2), Vector2i(2, 2)],
		"life_support":   [Vector2i(2, 2)],
		"reactor":        [Vector2i(3, 3), Vector2i(2, 3), Vector2i(3, 2)],
		"main_spine":     [Vector2i(3, 3), Vector2i(2, 2)],
		"hub":            [Vector2i(3, 3), Vector2i(2, 2)],
		"ramp":           [Vector2i(1, 1)],
		"elevator":       [Vector2i(1, 1)],
		"storage":        [Vector2i(1, 2), Vector2i(2, 2)],
		"tool_storage":   [Vector2i(2, 2)],
	}
	
	const DEFAULT_FOOTPRINT: Vector2i = Vector2i(2, 2)
	
	## Procgen program F1: alias authored archetype role names onto template role_pool tokens
	## so guaranteed_roles / role_weights actually match zone pools (derelict used
	## compartment/bay/quarters while templates use cargo/crew_quarters/dock).
	const ROLE_ALIASES: Dictionary = {
		"compartment": "cargo",
		"bay": "cargo",
		"quarters": "crew_quarters",
		"tool_storage": "storage",
		"engine_bay": "engineering",
		"cockpit": "bridge",
	}
	
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var variant_selector: RefCounted = null  # set by assign() if RoomVariantSelector is passed
	
	
	func assign(template: RefCounted, blueprint: RefCounted, archetype: Dictionary) -> Array[Dictionary]:
		return assign_with_selector(template, blueprint, archetype, null)
	
	
	## Normalize a single role token through ROLE_ALIASES (identity if unmapped).
	static func normalize_role(role: String) -> String:
		var r: String = str(role)
		if ROLE_ALIASES.has(r):
			return str(ROLE_ALIASES[r])
		return r
	
	
	## Returns a shallow-normalized archetype dict (weights + guarantees remapped).
	static func normalize_archetype(archetype: Dictionary) -> Dictionary:
		if archetype.is_empty():
			return {}
		var out: Dictionary = archetype.duplicate(true)
		var weights_v: Variant = out.get("role_weights", {})
		if weights_v is Dictionary:
			var nw: Dictionary = {}
			for k in (weights_v as Dictionary):
				var nk: String = normalize_role(str(k))
				nw[nk] = int(nw.get(nk, 0)) + int((weights_v as Dictionary)[k])
			out["role_weights"] = nw
		var g_v: Variant = out.get("guaranteed_roles", [])
		if g_v is Array:
			var ng: Array = []
			var seen: Dictionary = {}
			for entry in (g_v as Array):
				var nr: String = normalize_role(str(entry))
				if seen.has(nr):
					continue
				seen[nr] = true
				ng.append(nr)
			out["guaranteed_roles"] = ng
		return out
	
	
	# Same as assign() but additionally accepts a RoomVariantSelector
	# (or any RefCounted with a `pick(role, room_index, seed, biome)`
	# method). When supplied, every room dict gets a `variant` key
	# written from the deterministic variant pick. When null, the room
	# dict still gets `variant = "standard"` so downstream consumers
	# can rely on the key existing.
	func assign_with_selector(
			template: RefCounted,
			blueprint: RefCounted,
			archetype: Dictionary,
			selector,
			biome: String = "") -> Array[Dictionary]:
		variant_selector = selector
	
		rng.seed = int(blueprint.seed_value)
		# F1: normalize before any pick/guarantee so weights and pools share a vocabulary.
		archetype = normalize_archetype(archetype)
	
		var room_plan: Array[Dictionary] = []
		var role_counter: Dictionary = {}  # role -> next index
		var zone_pools: Dictionary = {}  # zone_id -> Array[String] role pool
	
		# Process zones in template order. The template zone ordering defines
		# the room ordering: entry first, destination last.
		for zone in template.zones:
			var zone_id: String = str(zone.get("id", ""))
			var role_pool_raw: Variant = zone.get("role_pool", [])
			var role_pool: Array[String] = []
			if role_pool_raw is Array:
				# Normalize pool tokens so weights/guarantees share one vocabulary
				# with derelict templates that still author compartment/quarters/bay.
				var seen_pool: Dictionary = {}
				for entry in role_pool_raw:
					var nr: String = normalize_role(str(entry))
					if seen_pool.has(nr):
						continue
					seen_pool[nr] = true
					role_pool.append(nr)
			zone_pools[zone_id] = role_pool
	
			var count: int = _resolve_count(zone.get("count", 1))
			var deck: int = int(zone.get("deck", 0))
			var position_hint: String = str(zone.get("position_hint", "center"))
	
			for i in range(count):
				var role: String = _pick_role(role_pool, archetype, role_counter)
				var idx: int = _next_index(role, role_counter)
				var room_id: String = "%s_%02d" % [role, idx]
				var footprint: Vector2i = _pick_footprint(role, blueprint)
				var variant: String = _pick_variant(role, room_plan.size(), blueprint, biome)
	
				room_plan.append({
					"id": room_id,
					"role": role,
					"variant": variant,
					"zone_id": zone_id,
					"deck": deck,
					"position_hint": position_hint,
					"target_cells": footprint.x * footprint.y,
					"footprint": footprint,
				})
	
		# Tranche 5 (2026-07-06 audit HIGH): archetype guaranteed_roles were
		# authored in every archetype JSON (derelict guarantees "dock") but never
		# enforced. Deterministic post-pass — no RNG, so per-seed replay is stable.
		_enforce_guaranteed_roles(room_plan, archetype, zone_pools, blueprint, biome)
	
		return room_plan
	
	
	# Ensures every archetype guaranteed_role appears at least once, replacing the
	# most-duplicated non-guaranteed room whose zone role_pool permits the missing
	# role. Entry (first) and destination (last) rooms are never replaced.
	# Candidate choice uses no RNG (duplicate count descending, later plan index
	# breaking ties); the replacement's footprint/variant re-rolls draw from the
	# seeded rng, so per-seed replay stays byte-identical. When no eligible room
	# exists the guarantee is skipped with a warning — generation never fails.
	func _enforce_guaranteed_roles(room_plan: Array[Dictionary], archetype: Dictionary,
			zone_pools: Dictionary, blueprint: RefCounted, biome: String) -> void:
		var guaranteed_raw: Variant = archetype.get("guaranteed_roles", [])
		if not (guaranteed_raw is Array) or (guaranteed_raw as Array).is_empty():
			return
		var guaranteed: Array[String] = []
		for entry in (guaranteed_raw as Array):
			guaranteed.append(str(entry))
	
		var replaced_any: bool = false
		for wanted in guaranteed:
			var present: bool = false
			for room in room_plan:
				if str(room.get("role", "")) == wanted:
					present = true
					break
			if present:
				continue
	
			var role_counts: Dictionary = {}
			for room in room_plan:
				var r: String = str(room.get("role", ""))
				role_counts[r] = int(role_counts.get(r, 0)) + 1
	
			var best_index: int = -1
			var best_count: int = 0
			for i in range(1, room_plan.size() - 1):  # never the entry or destination
				var room: Dictionary = room_plan[i]
				var role: String = str(room.get("role", ""))
				if role in guaranteed:
					continue
				var pool: Array = zone_pools.get(str(room.get("zone_id", "")), [])
				if not (wanted in pool):
					continue
				var count: int = int(role_counts.get(role, 0))
				if count >= best_count:  # >= so later plan index wins ties
					best_count = count
					best_index = i
			if best_index < 0:
				continue
	
			var target: Dictionary = room_plan[best_index]
			target["role"] = wanted
			target["footprint"] = _pick_footprint(wanted, blueprint)
			target["target_cells"] = int(target["footprint"].x) * int(target["footprint"].y)
			target["variant"] = _pick_variant(wanted, best_index, blueprint, biome)
			replaced_any = true
	
		if replaced_any:
			# Re-derive ids so role indices stay contiguous and unique in plan order.
			var counter: Dictionary = {}
			for room in room_plan:
				var role: String = str(room.get("role", ""))
				room["id"] = "%s_%02d" % [role, _next_index(role, counter)]
	
	
	# Picks a variant string via the supplied selector (if any). Falls
	# back to "standard" so the room dict always has a `variant` key.
	func _pick_variant(role: String, room_index: int, blueprint: RefCounted, biome: String) -> String:
		if variant_selector == null:
			return "standard"
		if not variant_selector.has_method("pick"):
			return "standard"
		return str(variant_selector.pick(role, int(room_index), int(blueprint.seed_value), biome))
	
	
	func _resolve_count(count_value: Variant) -> int:
		if count_value is Array:
			var arr: Array = count_value
			if arr.size() >= 2:
				var lo: int = int(arr[0])
				var hi: int = int(arr[1])
				if hi < lo:
					hi = lo
				return rng.randi_range(lo, hi)
		return int(count_value)
	
	
	func _pick_role(pool: Array[String], archetype: Dictionary, role_counter: Dictionary) -> String:
		if pool.is_empty():
			return "corridor"
		if pool.size() == 1:
			# Single-role zones are authored intent (the zone demands that role);
			# max_duplicates applies only where alternatives exist.
			return pool[0]
	
		# Tranche 5 (2026-07-06 audit HIGH): archetype max_duplicates was authored
		# in every archetype JSON but never enforced. Roles already at the cap are
		# excluded from the weighted pick; if EVERY pool role is capped, fall back
		# to the least-used pool role — generation never fails.
		var max_dup: int = int(archetype.get("max_duplicates", 0))  # 0 = unlimited
	
		var weights: Dictionary = archetype.get("role_weights", {})
		var candidates: Array[String] = []
		var candidate_weights: Array[int] = []
		var total: int = 0
	
		for role in pool:
			if max_dup > 0 and int(role_counter.get(role, 0)) >= max_dup:
				continue
			var w: int = int(weights.get(role, 1))
			if w <= 0:
				w = 1
			candidates.append(role)
			candidate_weights.append(w)
			total += w
	
		if candidates.is_empty():
			var least_used: String = pool[0]
			var least_count: int = int(role_counter.get(pool[0], 0))
			for role in pool:
				var used: int = int(role_counter.get(role, 0))
				if used < least_count:
					least_count = used
					least_used = role
			return least_used
	
		var roll: int = rng.randi_range(1, total)
		var cumulative: int = 0
		for i in range(candidates.size()):
			cumulative += candidate_weights[i]
			if roll <= cumulative:
				return candidates[i]
	
		return candidates[0]
	
	
	func _next_index(role: String, role_counter: Dictionary) -> int:
		if not role_counter.has(role):
			role_counter[role] = 1
		else:
			role_counter[role] = int(role_counter[role]) + 1
		return int(role_counter[role])
	
	
	func _pick_footprint(role: String, blueprint: RefCounted) -> Vector2i:
		if not ROOM_FOOTPRINT_OPTIONS.has(role):
			return DEFAULT_FOOTPRINT
	
		var options: Array = ROOM_FOOTPRINT_OPTIONS[role]
		if options.is_empty():
			return DEFAULT_FOOTPRINT
	
		# For SMALL blueprints, prefer smaller footprints (first half of options).
		# For MEDIUM, pick from the full range.
		var max_idx: int = options.size() - 1
		if int(blueprint.size) <= 1 and options.size() > 1:  # LIFE_BOAT or SMALL
			max_idx = int(ceil(float(options.size()) / 2.0)) - 1
	
		var idx: int = rng.randi_range(0, max_idx)
		return options[idx]
	

class FrozenCellLayoutEngine:
	extends RefCounted
	
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
					pass
	
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
	

static func project_fixed(owner_kind: String) -> Dictionary:
	if owner_kind not in ["home", "lifeboat"]:
		return _failure("unsupported_fixed_owner")
	var authority_result: Dictionary = _load_authority()
	if not bool(authority_result.get("ok", false)):
		return authority_result
	var fixed: Dictionary = authority_result.authority.get("fixed", {})
	var owner_v: Variant = fixed.get(owner_kind, null)
	if not owner_v is Dictionary or not (owner_v as Dictionary).get("projection", null) is Dictionary:
		return _failure("invalid_geometry_authority")
	var projection: Dictionary = _normalized_projection(
		(owner_v as Dictionary).projection as Dictionary)
	if not _valid_projection(projection):
		return _failure("invalid_geometry_authority")
	return {"ok": true, "reason": "", "projection": projection}


static func _normalized_projection(raw: Dictionary) -> Dictionary:
	var airlock_raw: Dictionary = raw.get("airlock", {})
	var normalized: Dictionary = {
		"airlock": {
			"position": (airlock_raw.get("position", []) as Array).duplicate(),
			"facing": (airlock_raw.get("facing", []) as Array).duplicate(),
			"type": str(airlock_raw.get("type", "")),
			"size_class": int(airlock_raw.get("size_class", 0)),
			"condition": str(airlock_raw.get("condition", "")),
		},
		"hangar": {},
	}
	var hangar_v: Variant = raw.get("hangar", null)
	if hangar_v is Dictionary and not (hangar_v as Dictionary).is_empty():
		var hangar: Dictionary = hangar_v
		normalized.hangar = {
			"type": str(hangar.get("type", "")),
			"slot_count": int(hangar.get("slot_count", 0)),
			"slot_size_class": int(hangar.get("slot_size_class", 0)),
			"slot_anchors": (hangar.get("slot_anchors", []) as Array).duplicate(true),
		}
	return normalized


static func project_fallback_candidate(
		blueprint: Dictionary, witnesses: Dictionary = {}) -> Dictionary:
	var source: Dictionary = blueprint.duplicate(true)
	var validated: Dictionary = _validated_blueprint(source)
	if not bool(validated.get("ok", false)):
		return _failure("invalid_legacy_blueprint")
	var witness_reason: String = _validate_witnesses(witnesses)
	if not witness_reason.is_empty():
		return _failure(witness_reason)
	var authority_result: Dictionary = _load_authority()
	if not bool(authority_result.get("ok", false)):
		return authority_result
	var candidate: Dictionary = _generate_fallback_candidate(
		validated.blueprint, authority_result.authority)
	if candidate.is_empty():
		return _failure("legacy_layout_unreconstructable")
	return {"ok": true, "reason": "", "candidate": candidate}


static func project_native_candidate(blueprint: Dictionary) -> Dictionary:
	var source: Dictionary = blueprint.duplicate(true)
	var validated: Dictionary = _validated_blueprint(source)
	if not bool(validated.get("ok", false)):
		return _failure("invalid_legacy_blueprint")
	var authority_result: Dictionary = _load_authority()
	if not bool(authority_result.get("ok", false)):
		return authority_result
	var native_result: Dictionary = _form_native_candidate(
		validated.blueprint, authority_result.authority)
	if (
			not bool(native_result.get("candidate_set_complete", false))
			or not native_result.get("candidate", null) is Dictionary
	):
		return _failure("legacy_generation_route_unavailable")
	return {
		"ok": true,
		"reason": "",
		"candidate": (native_result.candidate as Dictionary).duplicate(true),
	}


static func project_procedural(
		blueprint: Dictionary, witnesses: Dictionary = {}) -> Dictionary:
	var source: Dictionary = blueprint.duplicate(true)
	var witness_source: Dictionary = witnesses.duplicate(true)
	var fallback_result: Dictionary = project_fallback_candidate(source, witness_source)
	if not bool(fallback_result.get("ok", false)):
		return fallback_result
	var authority_result: Dictionary = _load_authority()
	if not bool(authority_result.get("ok", false)):
		return authority_result
	var candidates: Array = [fallback_result.candidate]
	var native_result: Dictionary = _form_native_candidate(
		_validated_blueprint(source).blueprint, authority_result.authority)
	var complete: bool = bool(native_result.get("candidate_set_complete", false))
	if native_result.get("candidate", null) is Dictionary:
		candidates.append(native_result.candidate)
	return resolve_authenticated_candidates(candidates, witness_source, complete)


## Resolve already-formed historical candidates. candidate_set_complete is
## trusted only from migration orchestration which has authenticated every
## platform-bounded route. Persisted data must never control this Boolean.
static func resolve_authenticated_candidates(
		candidates: Array, witnesses: Dictionary, candidate_set_complete: bool) -> Dictionary:
	var witness_reason: String = _validate_witnesses(witnesses)
	if not witness_reason.is_empty():
		return _failure(witness_reason)
	var validated_candidates: Array[Dictionary] = []
	for candidate_v in candidates:
		if not candidate_v is Dictionary or not _valid_candidate(candidate_v as Dictionary):
			return _failure("invalid_legacy_layout_candidate")
		validated_candidates.append((candidate_v as Dictionary).duplicate(true))
	if not candidate_set_complete:
		return _failure("legacy_generation_route_unavailable")
	var survivors: Array[Dictionary] = []
	for candidate in validated_candidates:
		if _candidate_matches_witnesses(candidate, witnesses):
			survivors.append(candidate)
	if survivors.is_empty():
		return _failure("legacy_layout_unreconstructable")
	var canonical_projection: String = JSON.stringify(
		survivors[0].projection, "", true, true)
	for candidate in survivors:
		if JSON.stringify(candidate.projection, "", true, true) != canonical_projection:
			return _failure("legacy_generation_route_ambiguous")
	var admitted_routes: Array[String] = []
	for candidate in survivors:
		admitted_routes.append(str(candidate.route))
	return {
		"ok": true,
		"reason": "",
		"origin_resolution": "single_candidate" if survivors.size() == 1 			else "equivalent_projection",
		"admitted_routes": admitted_routes,
		"projection": (survivors[0].projection as Dictionary).duplicate(true),
	}


static func compute_mobile_root_transform(
		host_airlock: Dictionary, mobile_airlock: Dictionary) -> Dictionary:
	if not _valid_airlock(host_airlock) or not _valid_airlock(mobile_airlock):
		return _failure("invalid_legacy_airlock")
	var host_pos: Vector3 = _array_to_vector3(host_airlock.position)
	var host_facing: Vector3 = _array_to_vector3(host_airlock.facing).normalized()
	var local_pos: Vector3 = _array_to_vector3(mobile_airlock.position)
	var local_facing: Vector3 = _array_to_vector3(mobile_airlock.facing).normalized()
	var source_yaw: float = atan2(local_facing.x, local_facing.z)
	var target_facing: Vector3 = -host_facing
	var target_yaw: float = atan2(target_facing.x, target_facing.z)
	var basis := Basis(Vector3.UP, target_yaw - source_yaw)
	var transform := Transform3D(basis, host_pos - basis * local_pos)
	if not transform.is_finite():
		return _failure("invalid_legacy_airlock")
	return {
		"ok": true,
		"reason": "",
		"transform": [
			transform.basis.x.x, transform.basis.x.y, transform.basis.x.z,
			transform.basis.y.x, transform.basis.y.y, transform.basis.y.z,
			transform.basis.z.x, transform.basis.z.y, transform.basis.z.z,
			transform.origin.x, transform.origin.y, transform.origin.z,
		],
	}


static func _load_authority() -> Dictionary:
	if not FileAccess.file_exists(AUTHORITY_PATH):
		return _failure("missing_geometry_authority")
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(AUTHORITY_PATH)) != OK 			or not parser.data is Dictionary:
		return _failure("invalid_geometry_authority")
	var authority: Dictionary = parser.data
	if str(authority.get("schema", "")) != AUTHORITY_SCHEMA 			or str(authority.get("source_commit", "")) != SOURCE_COMMIT:
		return _failure("invalid_geometry_authority")
	return {"ok": true, "reason": "", "authority": authority.duplicate(true)}


static func _validated_blueprint(raw: Dictionary) -> Dictionary:
	var allowed: Array[String] = [
		"size", "condition", "seed_value", "room_count_range", "generation_context_v1",
	]
	if not _has_only_string_keys(raw, allowed) 			or not _has_required_keys(raw, ["size", "condition", "seed_value", "room_count_range"]):
		return {"ok": false}
	for key in ["size", "condition", "seed_value"]:
		if not _is_exact_integer(raw[key]):
			return {"ok": false}
	var size: int = int(raw.size)
	var condition: int = int(raw.condition)
	if size < 0 or size > 2 or condition < 0 or condition > 2:
		return {"ok": false}
	if not raw.room_count_range is Dictionary:
		return {"ok": false}
	var range_data: Dictionary = raw.room_count_range
	if (
			not _has_exact_keys(range_data, ["min", "max"])
			or not _is_exact_integer(range_data.min)
			or not _is_exact_integer(range_data.max)
			or int(range_data.min) <= 0
			or int(range_data.max) < int(range_data.min)
	):
		return {"ok": false}
	var context: Dictionary = {}
	if raw.has("generation_context_v1"):
		if not raw.generation_context_v1 is Dictionary:
			return {"ok": false}
		context = raw.generation_context_v1
		if (
				not _has_exact_keys(context, ["biome", "difficulty"])
				or not context.biome is String
				or not context.difficulty is String
				or (context.biome as String).is_empty()
				or (context.difficulty as String).is_empty()
		):
			return {"ok": false}
	var blueprint := FrozenBlueprint.new()
	blueprint.size = size
	blueprint.condition = condition
	blueprint.seed_value = int(raw.seed_value)
	blueprint.room_count_range = Vector2i(int(range_data.min), int(range_data.max))
	blueprint.generation_context_v1 = context.duplicate(true)
	return {"ok": true, "blueprint": blueprint}


static func _generate_fallback_candidate(blueprint, authority: Dictionary) -> Dictionary:
	var templates_v: Variant = authority.get("ordered_templates", null)
	if not templates_v is Array or (templates_v as Array).size() != 14:
		return {}
	var template_by_id: Dictionary = {}
	var ordered_ids: Array[String] = []
	for index in range((templates_v as Array).size()):
		var row_v: Variant = (templates_v as Array)[index]
		if not row_v is Dictionary:
			return {}
		var row: Dictionary = row_v
		var template_id: String = str(row.get("id", ""))
		if (
				int(row.get("order", -1)) != index
				or template_id.is_empty()
				or not row.get("data", null) is Dictionary
		):
			return {}
		ordered_ids.append(template_id)
		template_by_id[template_id] = (row.data as Dictionary).duplicate(true)
	var archetype: Dictionary = {}
	var extended: bool = not blueprint.generation_context_v1.is_empty()
	if extended:
		if not authority.get("fallback_archetype", null) is Dictionary:
			return {}
		archetype = (authority.fallback_archetype as Dictionary).duplicate(true)
	var base_seed: int = blueprint.seed_value
	var best: Dictionary = {}
	for attempt in range(MAX_CONNECTIVITY_ATTEMPTS):
		var attempt_seed: int = base_seed if attempt == 0 			else int(base_seed ^ (attempt * RETRY_SALT))
		var attempt_blueprint := FrozenBlueprint.new()
		attempt_blueprint.size = blueprint.size
		attempt_blueprint.condition = blueprint.condition
		attempt_blueprint.seed_value = attempt_seed
		attempt_blueprint.room_count_range = blueprint.room_count_range
		attempt_blueprint.generation_context_v1 = blueprint.generation_context_v1.duplicate(true)
		var pool: Array[String] = ordered_ids if extended else LEGACY_TEMPLATES
		var selector_rng := RandomNumberGenerator.new()
		selector_rng.seed = attempt_seed
		var template_id: String = pool[selector_rng.randi_range(0, pool.size() - 1)]
		var template = FrozenTopologyTemplate.from_dict(template_by_id[template_id])
		if template == null:
			continue
		var room_plan: Array[Dictionary] = FrozenRoomAssigner.new().assign(
			template, attempt_blueprint, archetype)
		if room_plan.is_empty():
			continue
		var grid: Dictionary = FrozenCellLayoutEngine.new().layout(
			room_plan, template, attempt_seed)
		if (
				not grid.get("rooms", null) is Dictionary
				or (grid.rooms as Dictionary).is_empty()
		):
			continue
		var candidate: Dictionary = _candidate_from_grid(
			grid, room_plan, template_id, blueprint.seed_value, blueprint.condition)
		if candidate.is_empty():
			continue
		best = candidate
		if _grid_is_connected(grid, room_plan):
			return candidate
	return best


static func _candidate_from_grid(
		grid: Dictionary, room_plan: Array[Dictionary], template_id: String,
		base_seed: int, condition: int) -> Dictionary:
	var placed: Dictionary = grid.rooms
	var rooms: Array = []
	for planned in room_plan:
		var room_id: String = str(planned.get("id", ""))
		if not placed.has(room_id):
			continue
		var placed_room: Dictionary = placed[room_id]
		var cells: Array = []
		for cell_v in placed_room.get("cells", []) as Array:
			if not cell_v is Vector2i:
				return {}
			var cell: Vector2i = cell_v
			cells.append([cell.x, cell.y])
		rooms.append({
			"id": room_id,
			"role": str(planned.get("role", "")),
			"deck": int(placed_room.get("deck", planned.get("deck", 0))),
			"cells": cells,
		})
	var projection: Dictionary = _projection_from_cell_rooms(
		rooms, base_seed, condition)
	if not _valid_projection(projection):
		return {}
	return {
		"route": "fallback-gdscript-v6",
		"template_id": template_id,
		"projection": projection,
		"rooms": rooms,
	}


static func _projection_from_cell_rooms(
		rooms: Array, seed_value: int, condition: int) -> Dictionary:
	var dock_cells: Array = _first_role_world_cells(rooms, "dock", "dock")
	if dock_cells.is_empty():
		dock_cells = _first_role_world_cells(rooms, "airlock", "airlock")
	if dock_cells.is_empty():
		return {}
	var airlock_position: Array = _average_positions(dock_cells)
	var hangar_cells: Array = _first_role_world_cells(rooms, "hangar", "hangar")
	if hangar_cells.is_empty():
		hangar_cells = _first_role_world_cells(rooms, "cargo", "cargo")
	var hangar: Dictionary = {}
	if not hangar_cells.is_empty():
		var slot_count: int = maxi(1, int(hangar_cells.size() / CELLS_PER_SLOT))
		var anchors: Array = []
		for index in range(slot_count):
			anchors.append((hangar_cells[index * CELLS_PER_SLOT] as Array).duplicate())
		hangar = {
			"type": "hangar",
			"slot_count": slot_count,
			"slot_size_class": 2 if hangar_cells.size() >= HANGAR_BIG_CELL_THRESHOLD else 1,
			"slot_anchors": anchors,
		}
	return {
		"airlock": {
			"position": airlock_position,
			"facing": [1.0, 0.0, 0.0],
			"type": "airlock",
			"size_class": AIRLOCK_SIZE_CLASS,
			"condition": _condition_from_seed(seed_value, condition),
		},
		"hangar": hangar,
	}


static func _first_role_world_cells(
		rooms: Array, role_match: String, id_prefix: String) -> Array:
	for room_v in rooms:
		if not room_v is Dictionary:
			continue
		var room: Dictionary = room_v
		if (
				str(room.get("role", "")) != role_match
				and not str(room.get("id", "")).begins_with(id_prefix)
		):
			continue
		var world_cells: Array = []
		var deck: int = int(room.get("deck", 0))
		for cell_v in room.get("cells", []) as Array:
			if not cell_v is Array or (cell_v as Array).size() != 2:
				return []
			world_cells.append([
				float((cell_v as Array)[0]) * CELL_SIZE,
				float(deck) * DECK_HEIGHT,
				float((cell_v as Array)[1]) * CELL_SIZE,
			])
		if not world_cells.is_empty():
			return world_cells
	return []


## Pure validation seam for already-observed runtime facts. Production gathers
## these facts itself; persisted save data never supplies them.
static func authenticate_native_route_facts(facts: Dictionary) -> Dictionary:
	var authority_result: Dictionary = _load_authority()
	if not bool(authority_result.get("ok", false)):
		return authority_result
	if not _valid_native_facts(facts):
		return _failure("invalid_native_route_facts")
	return _authenticate_native_facts(facts, authority_result.authority)


static func native_route_status() -> Dictionary:
	var authority_result: Dictionary = _load_authority()
	if not bool(authority_result.get("ok", false)):
		return authority_result
	var authority: Dictionary = authority_result.authority
	var native: Dictionary = authority.get("native_v2", {})
	var platforms: Dictionary = native.get("platforms", {})
	var platform_name: String = OS.get_name()
	var platform_v: Variant = platforms.get(platform_name, null)
	if not platform_v is Dictionary:
		return _failure("legacy_generation_route_unavailable")
	var platform: Dictionary = platform_v
	var binary_path: String = str(platform.get("path", ""))
	var binary_sha256: String = ""
	if FileAccess.file_exists(binary_path):
		binary_sha256 = FileAccess.get_sha256(binary_path).to_lower()
	if binary_sha256 != str(platform.get("sha256", "")).to_lower():
		return _failure("legacy_generation_route_unavailable")
	var class_registered: bool = ClassDB.class_exists(
		str(native.get("generator_class", "")))
	var generator_version: int = -1
	if class_registered:
		var generator = ClassDB.instantiate(str(native.generator_class))
		if generator != null and generator.has_method("generator_version"):
			generator_version = int(generator.generator_version())
	return _authenticate_native_facts({
		"platform": platform_name,
		"binary_path": binary_path,
		"binary_sha256": binary_sha256,
		"class_registered": class_registered,
		"generator_version": generator_version,
	}, authority)


static func _form_native_candidate(blueprint, authority: Dictionary) -> Dictionary:
	var native_v: Variant = authority.get("native_v2", null)
	if not native_v is Dictionary:
		return {"candidate_set_complete": false}
	var native: Dictionary = native_v
	var platforms_v: Variant = native.get("platforms", null)
	if not platforms_v is Dictionary:
		return {"candidate_set_complete": false}
	var platform_name: String = OS.get_name()
	var platform_v: Variant = (platforms_v as Dictionary).get(platform_name, null)
	if not platform_v is Dictionary:
		return {"candidate_set_complete": false}
	var platform: Dictionary = platform_v
	var binary_path: String = str(platform.get("path", ""))
	var binary_sha256: String = ""
	if FileAccess.file_exists(binary_path):
		binary_sha256 = FileAccess.get_sha256(binary_path).to_lower()
	if binary_sha256 != str(platform.get("sha256", "")).to_lower():
		return {"candidate_set_complete": false}
	var class_registered: bool = ClassDB.class_exists(
		str(native.get("generator_class", "")))
	if not class_registered:
		return {"candidate_set_complete": false}
	var generator = ClassDB.instantiate(str(native.generator_class))
	var generator_version: int = -1
	if generator != null and generator.has_method("generator_version"):
		generator_version = int(generator.generator_version())
	var fact_result: Dictionary = _authenticate_native_facts({
		"platform": platform_name,
		"binary_path": binary_path,
		"binary_sha256": binary_sha256,
		"class_registered": class_registered,
		"generator_version": generator_version,
	}, authority)
	if (
			not bool(fact_result.get("ok", false))
			or generator == null
			or not generator.has_method("export_layout_json")
	):
		return {"candidate_set_complete": false}
	var sizes: Dictionary = native.get("size_to_archetype", {})
	var conditions: Dictionary = native.get("condition_to_intactness", {})
	var size_key: String = str(blueprint.size)
	var condition_key: String = str(blueprint.condition)
	if not sizes.has(size_key) or not conditions.has(condition_key):
		return {"candidate_set_complete": false}
	var params: Dictionary = {
		"archetype_id": str(sizes[size_key]),
		"intactness_override": int(conditions[condition_key]),
	}
	var text: String = str(generator.export_layout_json(
		blueprint.seed_value, params, str(native.get("kit_id", ""))))
	var parser := JSON.new()
	if text.is_empty() or parser.parse(text) != OK or not parser.data is Dictionary:
		return {"candidate_set_complete": false}
	var candidate: Dictionary = _candidate_from_native_layout(
		parser.data, blueprint.seed_value, blueprint.condition)
	if candidate.is_empty():
		return {"candidate_set_complete": false}
	return {"candidate_set_complete": true, "candidate": candidate}


static func _authenticate_native_facts(
		facts: Dictionary, authority: Dictionary) -> Dictionary:
	if not _valid_native_facts(facts):
		return _failure("invalid_native_route_facts")
	var native_v: Variant = authority.get("native_v2", null)
	if not native_v is Dictionary:
		return _failure("invalid_geometry_authority")
	var native: Dictionary = native_v
	var platforms_v: Variant = native.get("platforms", null)
	if not platforms_v is Dictionary:
		return _failure("invalid_geometry_authority")
	var platform_v: Variant = (platforms_v as Dictionary).get(
		str(facts.platform), null)
	if not platform_v is Dictionary:
		return _failure("legacy_generation_route_unavailable")
	var platform: Dictionary = platform_v
	if (
			str(facts.binary_path) != str(platform.get("path", ""))
			or str(facts.binary_sha256).to_lower()
				!= str(platform.get("sha256", "")).to_lower()
			or not bool(facts.class_registered)
			or int(facts.generator_version)
				!= int(native.get("generator_version", -1))
	):
		return _failure("legacy_generation_route_unavailable")
	return {"ok": true, "reason": ""}


static func _valid_native_facts(facts: Dictionary) -> bool:
	return (
		_has_exact_keys(facts, [
			"platform", "binary_path", "binary_sha256",
			"class_registered", "generator_version",
		])
		and facts.platform is String
		and not (facts.platform as String).is_empty()
		and facts.binary_path is String
		and not (facts.binary_path as String).is_empty()
		and facts.binary_sha256 is String
		and not (facts.binary_sha256 as String).is_empty()
		and facts.class_registered is bool
		and _is_exact_integer(facts.generator_version)
	)


static func _candidate_from_native_layout(
		layout: Dictionary, seed_value: int, condition: int) -> Dictionary:
	var rooms_v: Variant = layout.get("rooms", null)
	if not rooms_v is Array or (rooms_v as Array).is_empty():
		return {}
	var rooms: Array = []
	var projection_rooms: Array = []
	for room_v in rooms_v as Array:
		if not room_v is Dictionary:
			return {}
		var room: Dictionary = room_v
		var room_id: String = str(room.get("id", ""))
		var role: String = str(room.get("room_role", room.get("role", "")))
		var deck: int = int(room.get("deck", 0))
		var topology_cells: Array = []
		for cell_v in room.get("cells", []) as Array:
			var parsed_cell: Array = _native_topology_cell(cell_v)
			if not parsed_cell.is_empty():
				topology_cells.append(parsed_cell)
		rooms.append({"id": room_id, "role": role, "deck": deck, "cells": topology_cells})
		var floor_positions: Array = []
		for placement_v in room.get("structural_placements", []) as Array:
			if not placement_v is Dictionary:
				continue
			var placement: Dictionary = placement_v
			var module_id: String = str(placement.get("module_id", placement.get("module", "")))
			if module_id not in ["floor_1x1", "corridor_floor_1x1"]:
				continue
			var position_v: Variant = placement.get(
				"world_position", placement.get("position", null))
			if not _valid_numeric_array(position_v, 3):
				continue
			floor_positions.append([
				float((position_v as Array)[0]), float((position_v as Array)[1]),
				float((position_v as Array)[2]),
			])
		projection_rooms.append({
			"id": room_id, "role": role, "deck": deck,
			"cells": topology_cells, "floor_positions": floor_positions,
		})
	var projection: Dictionary = _projection_from_native_rooms(
		projection_rooms, seed_value, condition)
	if not _valid_projection(projection):
		return {}
	return {
		"route": "native-v2",
		"template_id": "native-v2",
		"projection": projection,
		"rooms": rooms,
	}


static func _projection_from_native_rooms(
		rooms: Array, seed_value: int, condition: int) -> Dictionary:
	var dock_positions: Array = _first_native_floor_positions(rooms, "dock", "dock")
	if dock_positions.is_empty():
		dock_positions = _first_native_floor_positions(rooms, "airlock", "airlock")
	if dock_positions.is_empty():
		return {}
	var hangar_positions: Array = _first_native_floor_positions(rooms, "hangar", "hangar")
	if hangar_positions.is_empty():
		hangar_positions = _first_native_floor_positions(rooms, "cargo", "cargo")
	var hangar: Dictionary = {}
	if not hangar_positions.is_empty():
		var count: int = maxi(1, int(hangar_positions.size() / CELLS_PER_SLOT))
		var anchors: Array = []
		for index in range(count):
			anchors.append((hangar_positions[index * CELLS_PER_SLOT] as Array).duplicate())
		hangar = {
			"type": "hangar", "slot_count": count,
			"slot_size_class": 2 if hangar_positions.size() >= HANGAR_BIG_CELL_THRESHOLD else 1,
			"slot_anchors": anchors,
		}
	return {
		"airlock": {
			"position": _average_positions(dock_positions),
			"facing": [1.0, 0.0, 0.0], "type": "airlock",
			"size_class": AIRLOCK_SIZE_CLASS,
			"condition": _condition_from_seed(seed_value, condition),
		},
		"hangar": hangar,
	}


static func _first_native_floor_positions(
		rooms: Array, role_match: String, id_prefix: String) -> Array:
	for room_v in rooms:
		var room: Dictionary = room_v
		if (
				str(room.get("role", "")) == role_match
				or str(room.get("id", "")).begins_with(id_prefix)
		):
			return (room.get("floor_positions", []) as Array).duplicate(true)
	return []


static func _grid_is_connected(grid: Dictionary, room_plan: Array[Dictionary]) -> bool:
	if room_plan.is_empty():
		return false
	var adjacency: Dictionary = {}
	for room in room_plan:
		adjacency[str(room.id)] = []
	for edge_v in grid.get("adjacencies", []) as Array:
		if not edge_v is Dictionary:
			continue
		var edge: Dictionary = edge_v
		var from_id: String = str(edge.get("from_room", ""))
		var to_id: String = str(edge.get("to_room", ""))
		if adjacency.has(from_id) and adjacency.has(to_id):
			(adjacency[from_id] as Array).append(to_id)
			(adjacency[to_id] as Array).append(from_id)
	var start: String = str(room_plan[0].id)
	var seen: Dictionary = {start: true}
	var queue: Array[String] = [start]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor_v in adjacency.get(current, []) as Array:
			var neighbor: String = str(neighbor_v)
			if not seen.has(neighbor):
				seen[neighbor] = true
				queue.append(neighbor)
	return seen.size() >= room_plan.size()


static func _candidate_matches_witnesses(
		candidate: Dictionary, witnesses: Dictionary) -> bool:
	var projection: Dictionary = candidate.projection
	for edge_v in witnesses.get("dock_edges", []) as Array:
		var edge: Dictionary = edge_v
		if edge.port_type == "airlock":
			if (projection.airlock as Dictionary).is_empty():
				return false
		elif edge.port_type == "hangar":
			var hangar: Dictionary = projection.hangar
			if hangar.is_empty() or int(edge.slot_index) >= int(hangar.slot_count):
				return false
	var hangar_witness_v: Variant = witnesses.get("hangar_summary", null)
	if hangar_witness_v is Dictionary:
		var expected: Dictionary = hangar_witness_v
		var actual: Dictionary = projection.hangar
		if (
				actual.is_empty()
				or int(actual.slot_count) != int(expected.slot_count)
				or int(actual.slot_size_class) != int(expected.slot_size_class)
		):
			return false
	for marker_v in witnesses.get("room_cell_markers", []) as Array:
		var marker: Dictionary = marker_v
		var found: bool = false
		for room_v in candidate.rooms as Array:
			var room: Dictionary = room_v
			if (
					str(room.id) == str(marker.room_id)
					and (room.cells as Array).has(marker.cell)
			):
				found = true
				break
		if not found:
			return false
	return true


static func _validate_witnesses(witnesses: Dictionary) -> String:
	if not _has_only_string_keys(
			witnesses, ["dock_edges", "hangar_summary", "room_cell_markers"]):
		return "invalid_legacy_layout_witnesses"
	if witnesses.has("dock_edges"):
		if not witnesses.dock_edges is Array:
			return "invalid_legacy_layout_witnesses"
		for edge_v in witnesses.dock_edges as Array:
			if not edge_v is Dictionary:
				return "invalid_legacy_layout_witnesses"
			var edge: Dictionary = edge_v
			if (
					not _has_exact_keys(edge, ["port_type", "slot_index"])
					or not edge.port_type is String
					or str(edge.port_type) not in ["airlock", "hangar"]
					or not _is_exact_integer(edge.slot_index)
			):
				return "invalid_legacy_layout_witnesses"
			if (
					(edge.port_type == "airlock" and int(edge.slot_index) != -1)
					or (edge.port_type == "hangar" and int(edge.slot_index) < 0)
			):
				return "invalid_legacy_layout_witnesses"
	if witnesses.has("hangar_summary"):
		if not witnesses.hangar_summary is Dictionary:
			return "invalid_legacy_layout_witnesses"
		var hangar: Dictionary = witnesses.hangar_summary
		if (
				not _has_exact_keys(
					hangar, ["slot_count", "slot_size_class", "slots"])
				or not _is_exact_integer(hangar.slot_count)
				or not _is_exact_integer(hangar.slot_size_class)
				or int(hangar.slot_count) <= 0
				or int(hangar.slot_size_class) <= 0
				or not hangar.slots is Array
				or (hangar.slots as Array).size() != int(hangar.slot_count)
		):
			return "invalid_legacy_layout_witnesses"
		var occupied: Dictionary = {}
		for ship_id_v in hangar.slots as Array:
			if not ship_id_v is String:
				return "invalid_legacy_layout_witnesses"
			var ship_id: String = ship_id_v
			if not ship_id.is_empty():
				if occupied.has(ship_id):
					return "invalid_legacy_layout_witnesses"
				occupied[ship_id] = true
	if witnesses.has("room_cell_markers"):
		if not witnesses.room_cell_markers is Array:
			return "invalid_legacy_layout_witnesses"
		for marker_v in witnesses.room_cell_markers as Array:
			if not marker_v is Dictionary:
				return "invalid_legacy_layout_witnesses"
			var marker: Dictionary = marker_v
			if (
					not _has_exact_keys(marker, ["room_id", "cell"])
					or not marker.room_id is String
					or (marker.room_id as String).is_empty()
					or not _valid_integer_array(marker.cell, 2)
			):
				return "invalid_legacy_layout_witnesses"
	return ""


static func _valid_candidate(candidate: Dictionary) -> bool:
	if (
			not _has_exact_keys(
				candidate, ["route", "template_id", "projection", "rooms"])
			or not candidate.route is String
			or str(candidate.route) not in ["fallback-gdscript-v6", "native-v2"]
			or not candidate.template_id is String
			or (candidate.template_id as String).is_empty()
			or not candidate.projection is Dictionary
			or not _valid_projection(candidate.projection)
			or not candidate.rooms is Array
	):
		return false
	var room_ids: Dictionary = {}
	for room_v in candidate.rooms as Array:
		if not room_v is Dictionary:
			return false
		var room: Dictionary = room_v
		if (
				not _has_exact_keys(room, ["id", "role", "deck", "cells"])
				or not room.id is String
				or (room.id as String).is_empty()
				or room_ids.has(room.id)
				or not room.role is String
				or not _is_exact_integer(room.deck)
				or not room.cells is Array
		):
			return false
		room_ids[room.id] = true
		for cell_v in room.cells as Array:
			if not _valid_integer_array(cell_v, 2):
				return false
	return true


static func _valid_projection(projection: Dictionary) -> bool:
	if (
			not _has_exact_keys(projection, ["airlock", "hangar"])
			or not projection.airlock is Dictionary
			or not _valid_airlock(projection.airlock)
			or not projection.hangar is Dictionary
	):
		return false
	var hangar: Dictionary = projection.hangar
	if hangar.is_empty():
		return true
	if (
			not _has_exact_keys(
				hangar, ["type", "slot_count", "slot_size_class", "slot_anchors"])
			or hangar.type != "hangar"
			or not _is_exact_integer(hangar.slot_count)
			or not _is_exact_integer(hangar.slot_size_class)
			or int(hangar.slot_count) <= 0
			or int(hangar.slot_size_class) not in [1, 2]
			or not hangar.slot_anchors is Array
			or (hangar.slot_anchors as Array).size() != int(hangar.slot_count)
	):
		return false
	for anchor_v in hangar.slot_anchors as Array:
		if not _valid_numeric_array(anchor_v, 3):
			return false
	return true


static func _valid_airlock(airlock: Dictionary) -> bool:
	return (
		_has_exact_keys(
			airlock, ["position", "facing", "type", "size_class", "condition"])
		and airlock.type == "airlock"
		and _is_exact_integer(airlock.size_class)
		and int(airlock.size_class) == 1
		and airlock.condition is String
		and str(airlock.condition) in ["intact", "broken"]
		and _valid_numeric_array(airlock.position, 3)
		and _valid_numeric_array(airlock.facing, 3)
		and _array_to_vector3(airlock.facing).length() > 0.0001
	)


static func _condition_from_seed(seed_value: int, condition: int) -> String:
	if condition <= 0:
		return "intact"
	if condition >= 3:
		return "broken"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return "broken" if rng.randf() < 0.25 * float(condition) else "intact"


static func _average_positions(positions: Array) -> Array:
	var sum := Vector3.ZERO
	for position_v in positions:
		sum += _array_to_vector3(position_v)
	var center: Vector3 = sum / float(positions.size())
	return [center.x, center.y, center.z]


static func _native_topology_cell(value: Variant) -> Array:
	if value is Array:
		var cell: Array = value
		if cell.size() == 2 and _is_exact_integer(cell[0]) and _is_exact_integer(cell[1]):
			return [int(cell[0]), int(cell[1])]
		if cell.size() >= 3 and _is_exact_integer(cell[0]) and _is_exact_integer(cell[2]):
			return [int(cell[0]), int(cell[2])]
	return []


static func _array_to_vector3(value: Variant) -> Vector3:
	var values: Array = value
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


static func _valid_numeric_array(value: Variant, required_size: int) -> bool:
	if not value is Array or (value as Array).size() != required_size:
		return false
	for component in value as Array:
		if (
				typeof(component) not in [TYPE_INT, TYPE_FLOAT]
				or component is bool
				or not is_finite(float(component))
		):
			return false
	return true


static func _valid_integer_array(value: Variant, required_size: int) -> bool:
	if not value is Array or (value as Array).size() != required_size:
		return false
	for component in value as Array:
		if not _is_exact_integer(component):
			return false
	return true


static func _is_exact_integer(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and not value is bool 		and is_finite(float(value)) and float(value) == floor(float(value))


static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	return value.size() == expected.size() and _has_required_keys(value, expected)


static func _has_required_keys(value: Dictionary, expected: Array) -> bool:
	for key in expected:
		if not value.has(key):
			return false
	return true


static func _has_only_string_keys(value: Dictionary, allowed: Array[String]) -> bool:
	for key_v in value:
		if not key_v is String or str(key_v) not in allowed:
			return false
	return true


static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
