extends RefCounted
class_name RoomVariantSelector

# RoomVariantSelector — deterministic per-room variant selection.
#
# Given a room role, the room's index in the room plan, the blueprint
# seed, and (optionally) the active biome, returns a variant string
# like "standard", "bio_seal", "refrigerated", etc. Same
# (role, room_index, seed, biome) always returns the same variant.
#
# This class is *pure*: it does not read scene tree state and does
# not mutate the room plan. RoomAssigner calls pick() and writes
# the returned variant string into the room dict under "variant".
# Unknown roles fall back to "standard" deterministically (the
# fallback is itself a function of role, so missing roles still
# produce a stable string instead of crashing the pipeline).
#
# Variants live in VARIANTS_BY_ROLE; the set is open — new variants
# can be added without touching RoomAssigner or the layout pipeline.
# The number of variants per role is intentionally generous so the
# Phase 2 HUD/scanner can show real per-room dressing detail.

const VARIANT_STANDARD: String = "standard"

# Role -> Array[String] of variants. Variants are listed in roughly
# ascending drama: the first variant is always VARIANT_STANDARD so
# that the deterministic fallback for unknown roles (and for the
# zero-index room) lands on a known baseline.
const VARIANTS_BY_ROLE: Dictionary = {
	"airlock": [
		"standard", "bio_seal", "maintenance_hatch", "cargo_lock",
	],
	"corridor": [
		"standard", "narrow", "wide", "junction",
		"flooded", "collapsed", "biomatter_crusted",
	],
	"main_spine": [
		"standard", "narrow", "wide", "junction",
	],
	"bridge": [
		"standard", "command", "observation", "dark_bridge",
	],
	"cargo": [
		"standard", "hold", "refrigerated", "secure", "empty_hold", "breached",
	],
	"medical": [
		"standard", "triage", "surgery", "contaminated",
	],
	"crew_quarters": [
		"standard", "bunks", "officer", "derelict_bunks",
	],
	"engineering": [
		"standard", "reactor", "life_support", "propulsion", "burned_out", "breached",
	],
	"maintenance": [
		"standard", "tool_storage", "junction", "sealed",
	],
	"reactor": [
		"standard", "primary", "secondary", "unstable",
	],
	"ramp": [
		"standard", "narrow", "service",
	],
	"elevator": [
		"standard", "service", "cargo",
	],
	"hub": [
		"standard", "central", "command",
	],
	"dock": [
		"standard", "lifeboat", "cargo",
	],
	"compartment": [
		"standard", "storage", "collapsed", "flooded",
	],
	"bay": [
		"standard", "service", "cargo",
	],
	"quarters": [
		"standard", "bunks", "officer", "derelict_bunks",
	],
	"hangar": [
		"standard", "small_craft", "cargo",
	],
	"mess_hall": [
		"standard", "long_table", "mess",
	],
	"armory": [
		"standard", "locked", "sealed",
	],
	"storage": [
		"standard", "general", "climate_controlled",
	],
	"tool_storage": [
		"standard", "secure", "open_rack",
	],
	"cockpit": [
		"standard", "command", "two_seat",
	],
	"engine_bay": [
		"standard", "primary", "service",
	],
}


# Variant -> gameplay/dressing effect payload. Sparse: only variants with a
# real consequence appear; everything else resolves to {} (neutral) via
# effects_for(). `sim.loot_bias` must be a key in data/items/loot_tables.json.
# `sim.hazard.kind` is "fire" or "breach" and only bites on compartment-mapped
# rooms (bridge/engineering/hydroponics/cargo). `weight` is reserved for future
# probabilistic seeding; state-level seeding today treats presence as forced.
const VARIANT_EFFECTS: Dictionary = {
	# --- fire ---
	"burned_out":   {"sim": {"loot_bias": "salvage_engineering", "hazard": {"kind": "fire", "weight": 0.6}}, "dressing": "scorch"},
	"unstable":     {"sim": {"hazard": {"kind": "fire", "weight": 0.5}}, "dressing": "sparks"},
	# --- breach ---
	"breached":     {"sim": {"loot_bias": "salvage_cargo", "hazard": {"kind": "breach", "weight": 0.6}}, "dressing": "vacuum"},
	"collapsed":    {"sim": {"hazard": {"kind": "breach", "weight": 0.4}}, "dressing": "rubble"},
	# --- loot-bias only ---
	"refrigerated": {"sim": {"loot_bias": "salvage_cargo"}, "dressing": "frost"},
	"secure":       {"sim": {"loot_bias": "hidden_cache"}, "dressing": "locked"},
	"triage":       {"sim": {"loot_bias": "repair_parts_common"}, "dressing": "medical"},
	# --- dressing only ---
	"flooded":      {"dressing": "water_plane"},
	"biomatter_crusted": {"dressing": "biomatter"},
	"contaminated": {"dressing": "haze"},
}


# Returns the effect payload for `variant`, or an empty Dictionary for
# unmapped variants (neutral: no loot bias, no hazard, no dressing).
func effects_for(variant: String) -> Dictionary:
	var raw: Variant = VARIANT_EFFECTS.get(variant, {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}


# Returns a variant string for `role` at `room_index` under the
# supplied `seed_value`. `biome` is optional and reserved for future
# per-biome variant lists; today every biome uses the same default
# list, but the parameter is part of the public signature so callers
# don't have to change when biome-specific variants are added.
func pick(role: String, room_index: int, seed_value: int, biome: String = "") -> String:
	var variant_list: Array = _variants_for_role(role)
	if variant_list.is_empty():
		# Unknown role: produce a stable fallback derived from role
		# name + seed so the same unknown role on the same seed
		# always returns the same string.
		return _fallback_for_unknown(role, seed_value)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _seed_for(role, room_index, seed_value, biome)
	var idx: int = rng.randi_range(0, variant_list.size() - 1)
	return str(variant_list[idx])


# Returns the list of variants registered for `role`, or an empty
# Array if the role is unknown. Pure accessor — no RNG.
func variants_for_role(role: String) -> Array[String]:
	return _variants_for_role(role)


# Returns the count of variants registered for `role`. Returns 1
# for unknown roles (the standard fallback) so callers that need a
# positive count can rely on it.
func variant_count(role: String) -> int:
	var arr: Array = _variants_for_role(role)
	if arr.is_empty():
		return 1
	return arr.size()


# Stable 32-bit hash of a role name. Used by the unknown-role
# fallback so different roles on the same seed still return
# different fallback strings.
static func role_hash(role: String) -> int:
	var h: int = 0
	for i in range(role.length()):
		h = (h * 31 + role.unicode_at(i)) & 0x7FFFFFFF
	return h


# Internal: returns the variant list for `role` (typed as
# `Array[String]` via the const table).
func _variants_for_role(role: String) -> Array[String]:
	if not VARIANTS_BY_ROLE.has(role):
		return []
	var raw: Variant = VARIANTS_BY_ROLE[role]
	if not (raw is Array):
		return []
	var typed: Array[String] = []
	for entry in raw:
		typed.append(String(entry))
	return typed


# Internal: combine role + index + seed + biome into a single 32-bit
# seed for the variant RNG. The combination is stable across runs
# and platforms (no float math, no string interning dependency).
func _seed_for(role: String, room_index: int, seed_value: int, biome: String) -> int:
	var h: int = seed_value & 0x7FFFFFFF
	h = (h ^ role_hash(role)) & 0x7FFFFFFF
	h = (h ^ (int(room_index) * 2654435761)) & 0x7FFFFFFF
	if not biome.is_empty():
		h = (h ^ role_hash(biome)) & 0x7FFFFFFF
	if h == 0:
		h = 1  # Godot's RNG.seed = 0 means default seed; offset by 1.
	return h


# Internal: produce a stable fallback for an unknown role.
# Returns "standard_<role>" if the role name is non-empty, else
# "standard".
func _fallback_for_unknown(role: String, seed_value: int) -> String:
	if role.is_empty():
		return VARIANT_STANDARD
	return "%s_%s" % [VARIANT_STANDARD, role]
