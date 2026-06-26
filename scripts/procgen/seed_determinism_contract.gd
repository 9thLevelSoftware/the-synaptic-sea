extends RefCounted
class_name SeedDeterminismContract

# SeedDeterminismContract — asserts the procgen pipeline produces
# deterministic, byte-identical output for any
# (seed, archetype, biome, difficulty) tuple. Provides:
#
#   fnv1a_64(text: String) -> int
#       Deterministic 64-bit FNV-1a hash of `text`. Stable across
#       runs and platforms; used as a fingerprint for the
#       stringified layout JSON.
#
#   assert_layout_match(blueprint, archetype, biome_id, difficulty_id,
#                        kit_id: String = "") -> Dictionary
#       Runs the layout pipeline twice from the same inputs,
#       stringifies both layouts with JSON.stringify(layout, "  "),
#       and returns:
#           {
#               "match": bool,
#               "hash_a": int,
#               "hash_b": int,
#               "byte_equal": bool,
#               "length_a": int,
#               "length_b": int,
#               "diff_first_char": int,   # index of first diff (or -1)
#               "biome_id": String,
#               "difficulty_id": String,
#           }
#
#   record_golden(blueprint, archetype, biome_id, difficulty_id,
#                 kit_id: String = "") -> Dictionary
#       Runs the pipeline once and returns the same dict as
#       assert_layout_match but with `match=true` and the hash
#       recorded. Smoke-friendly helper for golden fixture capture.
#
# Both fnv1a_64 and the pipeline runner are pure functions of their
# inputs — no global state, no scene tree access, no push_warning /
# push_error side effects. Smokes can call them in any order.

# GDScript's int is signed 64-bit. The canonical FNV-1a 64-bit
# algorithm uses unsigned 64-bit wrap; we approximate it here
# using a deterministic split-and-add trick that produces the
# same bit pattern as unsigned 64-bit wrap for any input length.
#
# The key insight: any 64-bit unsigned value V can be written as
# V = V_lo + V_hi * 2^32 where V_lo, V_hi are non-negative 32-bit
# integers. Multiplying two unsigned 64-bit values and taking the
# low 64 bits is equivalent to:
#   (a_lo + a_hi * 2^32) * (b_lo + b_hi * 2^32)
#     = a_lo * b_lo
#     + (a_lo * b_hi + a_hi * b_lo) * 2^32
#     + a_hi * b_hi * 2^64
# The last term vanishes mod 2^64, so we only need three 64-bit
# multiplies and the carry is handled by the natural 64-bit wrap
# of GDScript int.
#
# We re-interpret the signed int64 argument as unsigned via
# `v & _MOD_64_MASK`, which produces the unsigned-equivalent
# signed int64 (negative input becomes positive int64 with the
# high bit set, which is exactly the unsigned representation).
const _OFFSET_NEGATIVE: int = -3750763034362895579  # 0xcbf29ce484222325 as int64
const _PRIME_POSITIVE: int = 1099511628211          # 0x100000001b3 (fits in positive int64)
const _MOD_64_MASK: int = -1                         # 0xFFFFFFFFFFFFFFFF as int64 (all bits set)
const _MASK_32: int = 0xFFFFFFFF


# FNV-1a 64-bit hash of `text`. Returns a signed int64 that is
# bit-identical to the canonical unsigned FNV-1a 64-bit hash
# re-interpreted as signed (callers comparing two hashes should
# compare as int64, which is what GDScript does naturally).
static func fnv1a_64(text: String) -> int:
	var h: int = _OFFSET_NEGATIVE
	for i in range(text.length()):
		var c: int = text.unicode_at(i)
		h = (h ^ c) & _MOD_64_MASK
		h = _umul64(h & _MOD_64_MASK, _PRIME_POSITIVE)
	return h


# Unsigned 64-bit multiply returning the low 64 bits, re-interpreted
# as signed int64. Both `a_unsigned` and `b_unsigned` must already
# be in `[0, 2^64)`, i.e. positive int64 (the caller is responsible
# for masking them with `_MOD_64_MASK` before passing them in).
#
# Implementation: split each operand into 32-bit halves, compute
# the three sub-products, and accumulate with the natural 64-bit
# wrap. The high term `a_hi * b_hi * 2^64` vanishes mod 2^64.
static func _umul64(a_unsigned: int, b_unsigned: int) -> int:
	var a_lo: int = a_unsigned & _MASK_32
	var a_hi: int = (a_unsigned >> 32) & _MASK_32
	var b_lo: int = b_unsigned & _MASK_32
	var b_hi: int = (b_unsigned >> 32) & _MASK_32

	# All four sub-products fit comfortably in positive int64 because
	# each factor is < 2^32 (max product 2^64 - 2^33 + 1, still
	# positive int64). But we mask the result anyway to be safe.
	var p0: int = a_lo * b_lo           # low 64 bits
	var p1: int = a_lo * b_hi           # middle 64 bits
	var p2: int = a_hi * b_lo           # middle 64 bits (other order)
	var p3: int = a_hi * b_hi           # high 64 bits (vanishes mod 2^64)

	# Compose: result = p0 + ((p1 + p2) << 32) mod 2^64
	var mid: int = (p1 + p2) & _MOD_64_MASK
	var shifted_mid: int = (mid << 32) & _MOD_64_MASK
	var result: int = (p0 + shifted_mid) & _MOD_64_MASK
	# p3 << 64 contributes 0 mod 2^64; ignore.
	return result


# Asserts the layout pipeline produces byte-equal output for the
# given inputs. Returns the comparison dict described above.
# `kit_id` is optional; empty string falls back to the default kit.
static func assert_layout_match(
		blueprint, archetype: Dictionary,
		biome_id: String, difficulty_id: String,
		kit_id: String = "") -> Dictionary:

	var layout_a: Dictionary = _run_pipeline(blueprint, archetype, biome_id, difficulty_id, kit_id)
	var layout_b: Dictionary = _run_pipeline(blueprint, archetype, biome_id, difficulty_id, kit_id)
	return _compare_layouts(layout_a, layout_b, biome_id, difficulty_id)


# Records the golden hash for the given inputs by running the
# pipeline once. Returns the same dict as assert_layout_match but
# always reports `match=true`.
static func record_golden(
		blueprint, archetype: Dictionary,
		biome_id: String, difficulty_id: String,
		kit_id: String = "") -> Dictionary:
	var layout: Dictionary = _run_pipeline(blueprint, archetype, biome_id, difficulty_id, kit_id)
	var text: String = JSON.stringify(layout, "  ")
	var hash: int = fnv1a_64(text)
	return {
		"match": true,
		"hash_a": hash,
		"hash_b": hash,
		"byte_equal": true,
		"length_a": text.length(),
		"length_b": text.length(),
		"diff_first_char": -1,
		"biome_id": biome_id,
		"difficulty_id": difficulty_id,
		"golden_text_length": text.length(),
		"golden_hash": hash,
	}


# Runs the full procgen pipeline once with the given inputs and
# returns the layout Dictionary. Internal helper. The pipeline
# runner is a self-contained orchestrator that mirrors the
# production ShipLayoutGenerator.generate() call shape without
# depending on Godot scene-tree state.
static func _run_pipeline(
		blueprint, archetype: Dictionary,
		biome_id: String, difficulty_id: String,
		kit_id: String) -> Dictionary:
	if blueprint == null:
		return {}

	# Stage 1: template selection.
	var TemplateSelectorScript := load("res://scripts/procgen/template_selector.gd")
	var selector: RefCounted = TemplateSelectorScript.new()
	var template: RefCounted = selector.select(blueprint, archetype)
	if template == null:
		return {}

	# Stage 2: room assigner.
	var RoomAssignerScript := load("res://scripts/procgen/room_assigner.gd")
	var assigner: RefCounted = RoomAssignerScript.new()
	var room_plan: Array[Dictionary] = assigner.assign(template, blueprint, archetype)
	if room_plan.is_empty():
		return {}

	# Stage 3: cell layout engine.
	var CellLayoutEngineScript := load("res://scripts/procgen/cell_layout_engine.gd")
	var engine: RefCounted = CellLayoutEngineScript.new()
	var cell_grid: Dictionary = engine.layout(room_plan, template, int(blueprint.seed_value))
	if cell_grid.get("rooms", {}).is_empty():
		return {}

	# Stage 4: wall door resolver.
	var WallDoorResolverScript := load("res://scripts/procgen/wall_door_resolver.gd")
	var resolver: RefCounted = WallDoorResolverScript.new()
	var geometry: Dictionary = resolver.resolve(cell_grid, room_plan)

	# Stage 5: layout serializer.
	var LayoutSerializerScript := load("res://scripts/procgen/layout_serializer.gd")
	var serializer: RefCounted = LayoutSerializerScript.new()
	var archetype_name: String = str(archetype.get("name", str(archetype.get("template", "default"))))
	var layout: Dictionary = serializer.serialize(
		cell_grid, geometry, room_plan,
		str(template.id), int(blueprint.seed_value), archetype_name)
	if layout.is_empty():
		return {}

	# Stage 6: encounter injection (REQs PG-005..007).
	if not biome_id.is_empty() or not difficulty_id.is_empty():
		var BiomeProfileScript := load("res://scripts/procgen/biome_profile.gd")
		var DifficultyProfileScript := load("res://scripts/procgen/difficulty_profile.gd")
		var biome_data: Dictionary = _default_biome(biome_id)
		var difficulty_data: Dictionary = _default_difficulty(difficulty_id)
		var biome = BiomeProfileScript.from_dict(biome_data)
		var difficulty = DifficultyProfileScript.from_dict(difficulty_data)

		var EncounterInjectorScript := load("res://scripts/procgen/encounter_injector.gd")
		var injector: RefCounted = EncounterInjectorScript.new()
		layout = injector.inject(layout, biome, difficulty, int(blueprint.seed_value))

	return layout


# Compares two layout dicts and returns the match report.
static func _compare_layouts(
		layout_a: Dictionary, layout_b: Dictionary,
		biome_id: String, difficulty_id: String) -> Dictionary:
	var text_a: String = JSON.stringify(layout_a, "  ")
	var text_b: String = JSON.stringify(layout_b, "  ")
	var hash_a: int = fnv1a_64(text_a)
	var hash_b: int = fnv1a_64(text_b)
	var byte_equal: bool = text_a == text_b

	var diff_first_char: int = -1
	if not byte_equal:
		var max_check: int = min(text_a.length(), text_b.length())
		for i in range(max_check):
			if text_a[i] != text_b[i]:
				diff_first_char = i
				break
		if diff_first_char == -1 and text_a.length() != text_b.length():
			diff_first_char = max_check

	return {
		"match": byte_equal and hash_a == hash_b,
		"hash_a": hash_a,
		"hash_b": hash_b,
		"byte_equal": byte_equal,
		"length_a": text_a.length(),
		"length_b": text_b.length(),
		"diff_first_char": diff_first_char,
		"biome_id": biome_id,
		"difficulty_id": difficulty_id,
	}


# Returns a minimal biome Dictionary for `biome_id`. Used as a
# default when a biome JSON file isn't loaded — the contract
# doesn't depend on the catalog being on disk.
static func _default_biome(biome_id: String) -> Dictionary:
	if biome_id.is_empty():
		biome_id = "abyssal_synapse_sea"
	# Tuned values match data/procgen/biomes/abyssal_synapse_sea.json.
	match biome_id:
		"breach_field":
			return {
				"id": "breach_field",
				"hazard_modifier": 1.4,
				"loot_quality_modifier": 1.1,
				"encounter_density_modifier": 1.3,
				"ambient_intensity": 0.85,
				"encounter_table_id": "biomatter_lurker",
			}
		"dead_fleet":
			return {
				"id": "dead_fleet",
				"hazard_modifier": 1.1,
				"loot_quality_modifier": 1.4,
				"encounter_density_modifier": 0.8,
				"ambient_intensity": 1.1,
				"encounter_table_id": "derelict_pirate",
			}
		_:
			return {
				"id": "abyssal_synapse_sea",
				"hazard_modifier": 1.0,
				"loot_quality_modifier": 1.0,
				"encounter_density_modifier": 1.0,
				"ambient_intensity": 1.0,
				"encounter_table_id": "biomatter_lurker",
			}


static func _default_difficulty(difficulty_id: String) -> Dictionary:
	if difficulty_id.is_empty():
		difficulty_id = "standard"
	match difficulty_id:
		"hardened":
			return {
				"id": "hardened",
				"hazard_modifier": 1.4,
				"loot_quality_modifier": 0.85,
				"encounter_density_modifier": 1.3,
				"ambient_intensity": 1.0,
			}
		"deep_dive":
			return {
				"id": "deep_dive",
				"hazard_modifier": 1.7,
				"loot_quality_modifier": 1.1,
				"encounter_density_modifier": 1.6,
				"ambient_intensity": 1.0,
			}
		_:
			return {
				"id": "standard",
				"hazard_modifier": 1.0,
				"loot_quality_modifier": 1.0,
				"encounter_density_modifier": 1.0,
				"ambient_intensity": 1.0,
			}
