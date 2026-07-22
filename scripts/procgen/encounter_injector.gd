extends RefCounted
class_name EncounterInjector

# EncounterInjector — pure deterministic encounter spawn marker
# generator. Walks every non-critical-path room in a layout and
# rolls a per-room encounter marker against the biome's encounter
# table, scaled by the combined biome × difficulty density
# multiplier. Emits one `encounters` array on the layout dict for
# the loader to consume.
#
# Each marker is a Dictionary with keys:
#   id               String, unique within the layout
#   room_id          String, in layout.rooms
#   deck             int,    matches room.deck
#   cell             Array   [x, y], one of the room's floor cells
#   local_position   Array   [x, y, z], scene-local world offset of the
#                            chosen floor cell (cell * cell_size); the
#                            loader/ThreatManager adds the ship anchor
#   encounter_kind   String, non-empty (e.g. "biomatter_lurker")
#   count            int,    >= 1
#   difficulty_tier  String, matches the supplied difficulty id
#   seed_offset      int,    >= 0 (recorded so a re-run picks the
#                             same marker; also lets combat look up
#                             the per-marker RNG stream)
#
# Critical-path rooms are NEVER used as *spawn camps* (REQ-PG-007 +
# RISK-011). Markers may still sit on branch rooms that *patrol across*
# the critical path (flagged patrol_crosses_critical). The critical path
# is read from layout.critical_path which LayoutSerializer populates.
#
# Density model (PKG-C5.3 tension budget):
#   - Walk non-critical rooms with graph progress + branch depth.
#   - Entry quiet (low progress), escalate toward objective, branch depth
#     scales risk/reward, density dial multiplies p_base.
#   - One authored spike slot near the objective when density is high.
#   - Clamp per-room p to [0.0, 1.0]; roll; emit marker.

const DIAL_HAZARD: String = "hazard_modifier"
const DIAL_ENCOUNTER: String = "encounter_density_modifier"

# Base encounter probability per room role. Tunable; see
# docs/game/balance/procgen_expansion_tuning.md.
const ENCOUNTER_BASE_PROBABILITY: Dictionary = {
	"airlock": 0.10,
	"corridor": 0.20,
	"bridge": 0.15,
	"cargo": 0.25,
	"medical": 0.20,
	"crew_quarters": 0.20,
	"engineering": 0.30,
	"maintenance": 0.35,
	"reactor": 0.40,
	"ramp": 0.05,
	"elevator": 0.05,
	"hub": 0.10,
	"dock": 0.10,
	"compartment": 0.30,
	"bay": 0.25,
	"quarters": 0.20,
	"hangar": 0.20,
	"main_spine": 0.15,
	"mess_hall": 0.15,
	"armory": 0.25,
	"storage": 0.20,
	"tool_storage": 0.20,
	"cockpit": 0.10,
	"engine_bay": 0.30,
}

const DEFAULT_BASE_PROBABILITY: float = 0.20

# Maps room role -> encounter_kind id. Encounter kinds are
# resolved by the loader; this list is the contract between
# procgen and combat.
const ROLE_TO_ENCOUNTER_KIND: Dictionary = {
	"airlock": "breach_lurker",
	"corridor": "biomatter_lurker",
	"bridge": "drone_scout",
	"cargo": "biomatter_lurker",
	"medical": "biomatter_lurker",
	"crew_quarters": "biomatter_lurker",
	"engineering": "drone_swarm",
	"maintenance": "biomatter_lurker",
	"reactor": "drone_swarm",
	"ramp": "",
	"elevator": "",
	"hub": "drone_scout",
	"dock": "drone_scout",
	"compartment": "biomatter_lurker",
	"bay": "drone_swarm",
	"quarters": "biomatter_lurker",
	"hangar": "drone_swarm",
	"main_spine": "biomatter_lurker",
	"mess_hall": "biomatter_lurker",
	"armory": "drone_swarm",
	"storage": "biomatter_lurker",
	"tool_storage": "biomatter_lurker",
	"cockpit": "drone_scout",
	"engine_bay": "drone_swarm",
}

const DEFAULT_ENCOUNTER_KIND: String = "biomatter_lurker"

const ENCOUNTER_TABLE_DIR: String = "res://data/procgen/encounter_tables/"

# Tranche 5 (2026-07-06 audit HIGH): the authored encounter tables under
# data/procgen/encounter_tables/ were never loaded — the biome's
# encounter_table_id was stamped on markers but selected nothing. FULL table
# semantics (user decision 2026-07-07): for a role the table covers, the kind
# is a deterministic weighted roll among that role's table rolls and the count
# comes from the roll's authored int-or-[min,max]; roles the table does not
# cover (and biomes whose table file is missing/malformed) fall back to the
# ROLE_TO_ENCOUNTER_KIND constants with count 1, exactly as before.
# Cache: table_id -> Dictionary ({} = missing/malformed, warned once).
# Static (class scope) so the ADR-0047 warn-once contract holds across
# injector instances — production creates one injector per pipeline run
# (PR #67 Kilo review); tables are read-only data, so process-wide caching
# cannot affect per-seed determinism.
static var _table_cache: Dictionary = {}


# Injects encounter spawn markers into `layout` in place. Returns
# the same Dictionary with an `encounters` Array populated. The
# returned dict is the same reference the caller passed in.
func inject(
		layout: Dictionary,
		biome,
		difficulty,
		seed_value: int) -> Dictionary:

	# Compute critical-path room id set. Prefer the cached field;
	# fall back to TemplateCTraversal.critical_path() if missing.
	var critical_set: Dictionary = {}
	var cached_critical: Variant = layout.get("critical_path", null)
	if cached_critical is Array:
		for rid in (cached_critical as Array):
			critical_set[str(rid)] = true
	else:
		var TemplateCTraversalScript := load("res://scripts/procgen/template_c_traversal.gd")
		var path: Array = TemplateCTraversalScript.critical_path(layout)
		for rid in path:
			critical_set[str(rid)] = true

	# Combined density multiplier for the encounter dial. _safe_combined handles every
	# null combination (both / biome-only / difficulty-only / neither), so a non-null
	# biome with a null difficulty still applies its own density modifier. Floor at 0 but
	# DO NOT cap at 1.0 — biome/difficulty density > 1.0 (breach_field 1.3, deep_dive 1.6,
	# their 2.08 combination) must be able to RAISE the spawn rate, not just lower it. The
	# per-room probability is still clamped to [0,1] below (clamp(p_base * density, ...)),
	# so a high multiplier saturates each room's chance rather than being silently
	# neutered. (A prior clamp(density, 0, 1) here made all density > 1.0 a no-op.)
	var density: float = maxf(_safe_combined(biome, difficulty, DIAL_ENCOUNTER), 0.0)

	var difficulty_id: String = _safe_difficulty_id(difficulty)
	var encounter_table_id: String = _safe_encounter_table_id(biome)
	var cell_size: float = float(layout.get("cell_size", 4.0))

	var rooms_raw: Variant = layout.get("rooms", [])
	var rooms: Array = []
	if rooms_raw is Array:
		rooms = rooms_raw
	if rooms.is_empty():
		layout["encounters"] = []
		return layout

	var markers: Array = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = (int(seed_value) ^ 0xDEADBEEF) & 0x7FFFFFFF
	if rng.seed == 0:
		rng.seed = 1

	# PKG-C5.3: graph metrics for tension pacing.
	var adjacency: Dictionary = _build_room_adjacency(layout, rooms)
	var start_id: String = _resolve_start_room_id(layout, rooms, critical_set)
	var goal_id: String = _resolve_goal_room_id(layout, rooms, critical_set)
	var dist_from_start: Dictionary = _bfs_distances(adjacency, start_id)
	var branch_depth: Dictionary = _branch_depths(adjacency, critical_set)
	var max_progress: float = 1.0
	for rid_key in dist_from_start.keys():
		max_progress = maxf(max_progress, float(dist_from_start[rid_key]))

	var marker_index: int = 0
	var spiked_room: String = ""
	var candidates: Array = []  # non-critical rooms eligible for rolls
	for room in rooms:
		if not (room is Dictionary):
			continue
		var rid: String = str(room.get("id", ""))
		if rid.is_empty() or critical_set.has(rid):
			continue
		candidates.append(room)

	# Prefer a high-progress branch room for the authored spike slot.
	var spike_target: String = _pick_spike_room(candidates, dist_from_start, goal_id, max_progress)

	for room in candidates:
		var rid: String = str(room.get("id", ""))
		var role: String = str(room.get("room_role", room.get("role", "")))
		var p_base: float = float(ENCOUNTER_BASE_PROBABILITY.get(role, DEFAULT_BASE_PROBABILITY))
		var progress: float = float(dist_from_start.get(rid, 0))
		var progress_ratio: float = clampf(progress / max_progress, 0.0, 1.0)
		# Entry quiet, escalate toward objective.
		var tension: float = lerpf(0.35, 1.45, progress_ratio)
		if progress_ratio <= 0.15:
			tension *= 0.25  # guaranteed quieter near entry
		var depth: int = int(branch_depth.get(rid, 0))
		var depth_mult: float = 1.0 + 0.22 * float(mini(depth, 4))
		var p_final: float = clampf(p_base * density * tension * depth_mult, 0.0, 1.0)
		var force_spike: bool = (rid == spike_target and density >= 1.0 and p_final > 0.05)
		if p_final <= 0.0 and not force_spike:
			continue
		var roll: float = rng.randf()
		if not force_spike and roll >= p_final:
			continue
		if force_spike:
			spiked_room = rid

		var encounter_kind: String
		var marker_count: int = 1
		var table_rolls: Array = _table_rolls_for_role(encounter_table_id, role)
		if not table_rolls.is_empty():
			var pick: Dictionary = _pick_table_roll(table_rolls, rng)
			encounter_kind = str(pick.get("encounter_kind", ""))
			marker_count = _resolve_roll_count(pick.get("count", 1), rng)
		else:
			encounter_kind = str(ROLE_TO_ENCOUNTER_KIND.get(role, DEFAULT_ENCOUNTER_KIND))
		if encounter_kind.is_empty():
			continue

		var entries: Array = floor_cell_entries(room, cell_size)
		var cell_entry: Array = [0, 0]
		var local_position: Array = [0.0, 0.0, 0.0]
		if not entries.is_empty():
			var cell_pick: Dictionary = entries[entries.size() >> 1]
			cell_entry = cell_pick["cell"]
			local_position = cell_pick["local_position"]

		marker_index += 1
		var patrol_cross: bool = _adjacent_to_critical(rid, adjacency, critical_set)
		var marker: Dictionary = {
			"id": "enc_%s_%d" % [rid, marker_index],
			"room_id": rid,
			"deck": int(room.get("deck", 0)),
			"cell": cell_entry,
			"local_position": local_position,
			"encounter_kind": encounter_kind,
			"count": marker_count,
			"difficulty_tier": difficulty_id,
			"encounter_table_id": encounter_table_id,
			"seed_offset": marker_index,
			"tension_progress": progress_ratio,
			"branch_depth": depth,
			"patrol_crosses_critical": patrol_cross,
			"spike": force_spike,
		}
		markers.append(marker)

	layout["encounters"] = markers
	layout["encounter_pacing"] = {
		"model": "tension_budget_v1",
		"spike_room": spiked_room,
		"max_progress": max_progress,
		"density": density,
	}
	return layout


func _build_room_adjacency(layout: Dictionary, rooms: Array) -> Dictionary:
	var adj: Dictionary = {}
	for room in rooms:
		if room is Dictionary:
			var rid: String = str(room.get("id", ""))
			if not rid.is_empty():
				adj[rid] = []
	var links: Variant = layout.get("room_links", layout.get("adjacencies", []))
	if links is Array:
		for link in links:
			if not (link is Dictionary):
				continue
			var a: String = str(link.get("from_room", ""))
			var b: String = str(link.get("to_room", ""))
			if a.is_empty() or b.is_empty():
				continue
			if not adj.has(a):
				adj[a] = []
			if not adj.has(b):
				adj[b] = []
			(adj[a] as Array).append(b)
			(adj[b] as Array).append(a)
	return adj


func _bfs_distances(adjacency: Dictionary, start_id: String) -> Dictionary:
	var dist: Dictionary = {}
	if start_id.is_empty() or not adjacency.has(start_id):
		for rid in adjacency.keys():
			dist[str(rid)] = 0
		return dist
	var q: Array = [start_id]
	dist[start_id] = 0
	var head: int = 0
	while head < q.size():
		var cur: String = str(q[head])
		head += 1
		var neighbors: Array = adjacency.get(cur, [])
		for n in neighbors:
			var nid: String = str(n)
			if dist.has(nid):
				continue
			dist[nid] = int(dist[cur]) + 1
			q.append(nid)
	for rid in adjacency.keys():
		if not dist.has(str(rid)):
			dist[str(rid)] = 0
	return dist


func _branch_depths(adjacency: Dictionary, critical_set: Dictionary) -> Dictionary:
	# Distance to nearest critical-path room (0 if on critical path).
	var dist: Dictionary = {}
	var q: Array = []
	for rid in critical_set.keys():
		var sid: String = str(rid)
		dist[sid] = 0
		q.append(sid)
	var head: int = 0
	while head < q.size():
		var cur: String = str(q[head])
		head += 1
		var neighbors: Array = adjacency.get(cur, [])
		for n in neighbors:
			var nid: String = str(n)
			if dist.has(nid):
				continue
			dist[nid] = int(dist[cur]) + 1
			q.append(nid)
	for rid in adjacency.keys():
		if not dist.has(str(rid)):
			dist[str(rid)] = 0
	return dist


func _resolve_start_room_id(layout: Dictionary, rooms: Array, critical_set: Dictionary) -> String:
	var proto: Variant = layout.get("prototype", {})
	if proto is Dictionary and not str(proto.get("start_room", "")).is_empty():
		return str(proto.get("start_room", ""))
	var cp: Variant = layout.get("critical_path", [])
	if cp is Array and (cp as Array).size() > 0:
		return str((cp as Array)[0])
	if rooms.size() > 0 and rooms[0] is Dictionary:
		return str(rooms[0].get("id", ""))
	return ""


func _resolve_goal_room_id(layout: Dictionary, rooms: Array, critical_set: Dictionary) -> String:
	var proto: Variant = layout.get("prototype", {})
	if proto is Dictionary and not str(proto.get("goal_room", "")).is_empty():
		return str(proto.get("goal_room", ""))
	var cp: Variant = layout.get("critical_path", [])
	if cp is Array and (cp as Array).size() > 0:
		return str((cp as Array)[(cp as Array).size() - 1])
	if rooms.size() > 0 and rooms[rooms.size() - 1] is Dictionary:
		return str(rooms[rooms.size() - 1].get("id", ""))
	return ""


func _pick_spike_room(candidates: Array, dist_from_start: Dictionary, goal_id: String, max_progress: float) -> String:
	var best_id: String = ""
	var best_score: float = -1.0
	for room in candidates:
		if not (room is Dictionary):
			continue
		var rid: String = str(room.get("id", ""))
		var progress: float = float(dist_from_start.get(rid, 0))
		var score: float = progress
		if rid == goal_id:
			score += 2.0
		# Prefer late-ship rooms (progress >= 60% of max).
		if progress < max_progress * 0.55:
			continue
		if score > best_score:
			best_score = score
			best_id = rid
	return best_id


func _adjacent_to_critical(rid: String, adjacency: Dictionary, critical_set: Dictionary) -> bool:
	var neighbors: Array = adjacency.get(rid, [])
	for n in neighbors:
		if critical_set.has(str(n)):
			return true
	return false


# Validates the encounter markers embedded in `layout`. Returns a
# Dictionary:
#   {
#     "valid": bool,
#     "marker_count": int,
#     "missing_room": String,
#     "critical_path_violation": String,
#     "missing_cell": String,
#     "duplicate_id": String
#   }
#
# A marker is invalid iff it references a room not in layout.rooms,
# is placed in a critical-path room, or has a duplicate id. The
# helper returns on the first violation so the smoke can pin the
# error precisely.
static func validate(layout: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"valid": true,
		"marker_count": 0,
		"missing_room": "",
		"critical_path_violation": "",
		"missing_cell": "",
		"duplicate_id": "",
		"bad_kind": "",
	}

	var rooms_raw: Variant = layout.get("rooms", [])
	if not (rooms_raw is Array):
		result["valid"] = false
		result["missing_room"] = "<no rooms array>"
		return result

	var validate_cell_size: float = float(layout.get("cell_size", 4.0))
	var room_lookup: Dictionary = {}
	for room in (rooms_raw as Array):
		if not (room is Dictionary):
			continue
		var rid: String = str(room.get("id", ""))
		if rid.is_empty():
			continue
		var cells: Dictionary = {}
		for entry in floor_cell_entries(room, validate_cell_size):
			var xz: Array = (entry as Dictionary)["cell"]
			cells["%d,%d" % [int(xz[0]), int(xz[1])]] = true
		room_lookup[rid] = {
			"deck": int(room.get("deck", 0)),
			"cells": cells,
		}

	var critical_set: Dictionary = {}
	var cp: Variant = layout.get("critical_path", null)
	if cp is Array:
		for r in (cp as Array):
			critical_set[str(r)] = true

	var markers_raw: Variant = layout.get("encounters", null)
	if markers_raw == null:
		# No encounters field is valid (older 1.1.0 layouts or
		# standard difficulty with zero density).
		return result
	if not (markers_raw is Array):
		result["valid"] = false
		result["bad_kind"] = "encounters_not_array"
		return result

	var seen_ids: Dictionary = {}
	for marker in (markers_raw as Array):
		if not (marker is Dictionary):
			result["valid"] = false
			result["bad_kind"] = "marker_not_dict"
			return result
		result["marker_count"] += 1
		var mid: String = str(marker.get("id", ""))
		if mid.is_empty() or seen_ids.has(mid):
			result["valid"] = false
			result["duplicate_id"] = mid
			return result
		seen_ids[mid] = true

		var rid: String = str(marker.get("room_id", ""))
		if not room_lookup.has(rid):
			result["valid"] = false
			result["missing_room"] = rid
			return result
		if critical_set.has(rid):
			result["valid"] = false
			result["critical_path_violation"] = rid
			return result

		var room_data: Dictionary = room_lookup[rid]
		var marker_deck: int = int(marker.get("deck", -1))
		if marker_deck >= 0 and marker_deck != int(room_data.get("deck", 0)):
			result["valid"] = false
			result["missing_room"] = "%s (deck mismatch)" % rid
			return result

		var cell_raw: Variant = marker.get("cell", null)
		if cell_raw is Array and (cell_raw as Array).size() >= 2:
			var cell_key: String = "%d,%d" % [int((cell_raw as Array)[0]), int((cell_raw as Array)[1])]
			var cells: Dictionary = room_data.get("cells", {})
			if not cells.is_empty() and not cells.has(cell_key):
				result["valid"] = false
				result["missing_cell"] = "%s/%s" % [rid, cell_key]
				return result

		var kind: String = str(marker.get("encounter_kind", ""))
		if kind.is_empty():
			result["valid"] = false
			result["bad_kind"] = "%s (empty kind)" % rid
			return result

		var count: int = int(marker.get("count", 0))
		if count < 1:
			result["valid"] = false
			result["bad_kind"] = "%s (count<1)" % rid
			return result

	return result


# --- Internal helpers ---

# Enumerates a room's floor cells as [{cell: [x, z], local_position: [x, y, z]}].
# Prefers an explicit `cells` array (pre-serialization dicts / hand-built
# fixtures); otherwise derives from the serialized `structural_placements`,
# whose floor entries are named "floor_cell_*" with world_position =
# cell * cell_size (LayoutSerializer._build_structural_placements).
static func floor_cell_entries(room: Dictionary, cell_size: float) -> Array:
	# Guard degenerate cell_size once for BOTH branches: a zero/negative size
	# would silently produce wrong local positions (cells branch) or divide
	# incorrectly (placements branch). The grid contract is CELL_SIZE = 4.0.
	var safe_size: float = cell_size if cell_size > 0.0 else 4.0
	var out: Array = []
	var cells_raw: Variant = room.get("cells", [])
	if cells_raw is Array:
		for c in (cells_raw as Array):
			var xz: Variant = null
			if c is Vector2i:
				xz = [c.x, c.y]
			elif c is Array and (c as Array).size() >= 2:
				xz = [int((c as Array)[0]), int((c as Array)[1])]
			if xz != null:
				out.append({
					"cell": xz,
					"local_position": [float(xz[0]) * safe_size, 0.0, float(xz[1]) * safe_size],
				})
	if not out.is_empty():
		return out
	var placements_raw: Variant = room.get("structural_placements", [])
	if placements_raw is Array:
		for p in (placements_raw as Array):
			if not (p is Dictionary):
				continue
			if not str((p as Dictionary).get("name", "")).begins_with("floor_cell"):
				continue
			var wp: Variant = (p as Dictionary).get("world_position", null)
			if wp is Array and (wp as Array).size() >= 3:
				out.append({
					"cell": [int(roundf(float(wp[0]) / safe_size)), int(roundf(float(wp[2]) / safe_size))],
					"local_position": [float(wp[0]), float(wp[1]), float(wp[2])],
				})
	return out


# Loads (and caches) the encounter table for `table_id`, returning the rolls
# whose `role` matches. Missing/malformed tables warn once per injector
# instance and resolve to {} so every role falls back to the constants.
func _table_rolls_for_role(table_id: String, role: String) -> Array:
	if table_id.is_empty() or role.is_empty():
		return []
	var table: Dictionary = _load_encounter_table(table_id)
	var rolls_raw: Variant = table.get("rolls", [])
	if not (rolls_raw is Array):
		return []
	var matched: Array = []
	for roll_variant in (rolls_raw as Array):
		if not (roll_variant is Dictionary):
			continue
		if str((roll_variant as Dictionary).get("role", "")) == role:
			matched.append(roll_variant)
	return matched


func _load_encounter_table(table_id: String) -> Dictionary:
	if _table_cache.has(table_id):
		return _table_cache[table_id]
	var path: String = ENCOUNTER_TABLE_DIR + table_id + ".json"
	var result: Dictionary = {}
	if not FileAccess.file_exists(path):
		push_warning("EncounterInjector: encounter table file missing, falling back to role constants: %s" % path)
	else:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			result = parsed
		else:
			push_warning("EncounterInjector: encounter table is not a JSON object, falling back to role constants: %s" % path)
	_table_cache[table_id] = result
	return result


# Deterministic weighted pick among a role's table rolls. A single roll is
# returned without consuming an rng draw; non-positive weights count as 1.
func _pick_table_roll(rolls: Array, rng: RandomNumberGenerator) -> Dictionary:
	if rolls.size() == 1:
		return rolls[0]
	var total: int = 0
	var weights: Array[int] = []
	for roll in rolls:
		var w: int = int((roll as Dictionary).get("weight", 1))
		if w <= 0:
			w = 1
		weights.append(w)
		total += w
	var drawn: int = rng.randi_range(1, total)
	var cumulative: int = 0
	for i in range(rolls.size()):
		cumulative += weights[i]
		if drawn <= cumulative:
			return rolls[i]
	return rolls[0]


# Authored count is either an int or an inclusive [min, max] range; ranges
# consume one rng draw. Result is floored at 1 (validate() requires count>=1).
# Every Array shape is handled inside the Array branch (PR #67 review:
# int(<Array>) is not a valid conversion, and a single-element [n] is an
# author's explicit count whose intent must not be silently dropped).
func _resolve_roll_count(count_value: Variant, rng: RandomNumberGenerator) -> int:
	if count_value is Array:
		var arr: Array = count_value
		if arr.size() >= 2:
			var lo: int = int(arr[0])
			var hi: int = int(arr[1])
			if hi < lo:
				hi = lo
			return maxi(1, rng.randi_range(lo, hi))
		if arr.size() == 1:
			push_warning("EncounterInjector: roll count %s is a single-element array; treating as int" % str(count_value))
			return maxi(1, int(arr[0]))
		return 1
	return maxi(1, int(count_value))


func _safe_combined(biome, difficulty, dial: String) -> float:
	if biome != null and difficulty != null:
		var DifficultyProfileScript := load("res://scripts/procgen/difficulty_profile.gd")
		return float(DifficultyProfileScript.combined_modifier(biome, difficulty, dial))
	if biome != null:
		return _safe_modifier(biome, dial)
	if difficulty != null:
		return _safe_modifier(difficulty, dial)
	return 1.0


func _safe_modifier(profile, dial: String) -> float:
	if profile == null:
		return 1.0
	if not profile.has_method("modifier"):
		return 1.0
	return float(profile.modifier(dial))


func _safe_difficulty_id(difficulty) -> String:
	if difficulty == null:
		return "standard"
	if difficulty == null or not ("id" in difficulty):
		return "standard"
	return str(difficulty.id)


func _safe_encounter_table_id(biome) -> String:
	if biome == null:
		return ""
	if not ("encounter_table_id" in biome):
		return ""
	return str(biome.encounter_table_id)
