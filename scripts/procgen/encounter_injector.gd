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
#   cell             Array   [x, y] or [x, y, deck], in room.cells
#   encounter_kind   String, non-empty (e.g. "biomatter_lurker")
#   count            int,    >= 1
#   difficulty_tier  String, matches the supplied difficulty id
#   seed_offset      int,    >= 0 (recorded so a re-run picks the
#                             same marker; also lets combat look up
#                             the per-marker RNG stream)
#
# Critical-path rooms are NEVER spawned into (see REQ-PG-007 +
# RISK-011). The critical path is read from layout.critical_path
# which LayoutSerializer._build_critical_path() populates; if the
# field is missing, the injector computes it via
# TemplateCTraversal.critical_path().
#
# Density model:
#   - For every non-critical room, compute base probability p_base
#     per room role from ENCOUNTER_BASE_PROBABILITY.
#   - Multiply by DifficultyProfile.combined_modifier(
#       biome, difficulty, "encounter_density_modifier").
#   - Clamp to [0.0, 1.0]. Roll against p_final.
#   - If rolled, emit one marker; record count = 1.

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

	var marker_index: int = 0
	for room in rooms:
		if not (room is Dictionary):
			continue
		var rid: String = str(room.get("id", ""))
		if rid.is_empty():
			continue
		if critical_set.has(rid):
			continue

		var role: String = str(room.get("room_role", room.get("role", "")))
		var p_base: float = float(ENCOUNTER_BASE_PROBABILITY.get(role, DEFAULT_BASE_PROBABILITY))
		var p_final: float = clamp(p_base * density, 0.0, 1.0)
		if p_final <= 0.0:
			continue
		var roll: float = rng.randf()
		if roll >= p_final:
			continue

		var encounter_kind: String = str(ROLE_TO_ENCOUNTER_KIND.get(role, DEFAULT_ENCOUNTER_KIND))
		if encounter_kind.is_empty():
			continue

		var cells_raw: Variant = room.get("cells", [])
		var cells: Array = []
		if cells_raw is Array:
			cells = cells_raw
		var cell_entry: Variant = null
		var cell_xy: Vector2i = Vector2i.ZERO
		if not cells.is_empty():
			var cell: Variant = cells[0]
			if cell is Vector2i:
				cell_xy = cell
				cell_entry = [cell.x, cell.y]
			elif cell is Array:
				var arr: Array = cell
				if arr.size() >= 2:
					cell_xy = Vector2i(int(arr[0]), int(arr[1]))
					cell_entry = arr.duplicate()
		if cell_entry == null:
			cell_entry = [0, 0]

		marker_index += 1
		var marker: Dictionary = {
			"id": "enc_%s_%d" % [rid, marker_index],
			"room_id": rid,
			"deck": int(room.get("deck", 0)),
			"cell": cell_entry,
			"encounter_kind": encounter_kind,
			"count": 1,
			"difficulty_tier": difficulty_id,
			"encounter_table_id": encounter_table_id,
			"seed_offset": marker_index,
		}
		markers.append(marker)

	layout["encounters"] = markers
	return layout


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

	var room_lookup: Dictionary = {}
	for room in (rooms_raw as Array):
		if not (room is Dictionary):
			continue
		var rid: String = str(room.get("id", ""))
		if rid.is_empty():
			continue
		var cells: Dictionary = {}
		var cells_raw: Variant = room.get("cells", [])
		if cells_raw is Array:
			for c in (cells_raw as Array):
				if c is Vector2i:
					cells["%d,%d" % [c.x, c.y]] = true
				elif c is Array:
					var a: Array = c
					if a.size() >= 2:
						cells["%d,%d" % [int(a[0]), int(a[1])]] = true
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
