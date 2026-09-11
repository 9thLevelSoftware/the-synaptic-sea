extends RefCounted

## Kernel fixtures: RandomNumberGenerator sequences, String/Variant hashes,
## JSON number/string formatting, and the SeedDeterminismContract FNV-1a hash.

const SeedDeterminismContractScript := preload("res://scripts/procgen/seed_determinism_contract.gd")
const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")

const RNG_SEEDS: Array = [0, 1, 17, 42, 777, 999, 7777, 2147483647, 12345678901]
const RNG_COUNT: int = 64
const INTERLEAVED_ITERATIONS: int = 32
const CRLF: String = "\r\n"
const LF: String = "\n"


func run(writer) -> bool:
	var ok: bool = true
	ok = _rng_fixture(writer) and ok
	ok = _string_hash_fixture(writer) and ok
	ok = _float_format_fixture(writer) and ok
	ok = _fnv1a_fixture(writer) and ok
	return ok


# --- RNG -------------------------------------------------------------------

## IEEE-754 float64 bit pattern of f as 16 lowercase hex digits.
static func float_bits_hex(f: float) -> String:
	var bytes: PackedByteArray = PackedFloat64Array([f]).to_byte_array()
	return String.num_uint64(bytes.decode_u64(0), 16).lpad(16, "0")


func _fresh_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _rng_fixture(writer) -> bool:
	var seeds_out: Array = []
	for seed_variant in RNG_SEEDS:
		var s: int = int(seed_variant)
		var record: Dictionary = {"seed": s}
		var probe := _fresh_rng(s)
		record["state_after_seed"] = probe.state
		record["seed_readback"] = probe.seed

		var rng := _fresh_rng(s)
		var randi_values: Array = []
		for i in range(RNG_COUNT):
			randi_values.append(rng.randi())
		record["randi"] = randi_values
		record["state_after_64_randi"] = rng.state

		rng = _fresh_rng(s)
		var randf_values: Array = []
		var randf_str: Array = []
		var randf_bits: Array = []
		for i in range(RNG_COUNT):
			var f: float = rng.randf()
			randf_values.append(f)
			randf_str.append(var_to_str(f))
			randf_bits.append(float_bits_hex(f))
		record["randf"] = randf_values
		record["randf_str"] = randf_str
		record["randf_bits"] = randf_bits

		rng = _fresh_rng(s)
		var r1_100: Array = []
		for i in range(RNG_COUNT):
			r1_100.append(rng.randi_range(1, 100))
		record["randi_range_1_100"] = r1_100

		rng = _fresh_rng(s)
		var rm5_5: Array = []
		for i in range(RNG_COUNT):
			rm5_5.append(rng.randi_range(-5, 5))
		record["randi_range_m5_5"] = rm5_5

		rng = _fresh_rng(s)
		var rf_range: Array = []
		var rf_range_str: Array = []
		var rf_range_bits: Array = []
		for i in range(RNG_COUNT):
			var f: float = rng.randf_range(-2.5, 7.5)
			rf_range.append(f)
			rf_range_str.append(var_to_str(f))
			rf_range_bits.append(float_bits_hex(f))
		record["randf_range_m2_5_7_5"] = rf_range
		record["randf_range_m2_5_7_5_str"] = rf_range_str
		record["randf_range_m2_5_7_5_bits"] = rf_range_bits

		rng = _fresh_rng(s)
		var rfn: Array = []
		var rfn_str: Array = []
		var rfn_bits: Array = []
		for i in range(RNG_COUNT):
			var f: float = rng.randfn(0.0, 1.0)
			rfn.append(f)
			rfn_str.append(var_to_str(f))
			rfn_bits.append(float_bits_hex(f))
		record["randfn_0_1"] = rfn
		record["randfn_0_1_str"] = rfn_str
		record["randfn_0_1_bits"] = rfn_bits

		rng = _fresh_rng(s)
		var interleaved: Array = []
		var interleaved_str: Array = []
		var interleaved_bits: Array = []
		for i in range(INTERLEAVED_ITERATIONS):
			var a: int = rng.randi()
			var b: float = rng.randf()
			var c: int = rng.randi_range(0, 9)
			interleaved.append([a, b, c])
			interleaved_str.append([var_to_str(a), var_to_str(b), var_to_str(c)])
			interleaved_bits.append(float_bits_hex(b))
		record["interleaved"] = interleaved
		record["interleaved_str"] = interleaved_str
		record["interleaved_randf_bits"] = interleaved_bits
		seeds_out.append(record)

	var mod7_rng := _fresh_rng(42)
	var mod7: Array = []
	for i in range(16):
		mod7.append(mod7_rng.randi() % 7)

	var fixture: Dictionary = {
		"schema": "parity.kernel.rng.v1",
		"notes": [
			"Every sequence except 'interleaved' uses a FRESH RandomNumberGenerator.new() with .seed = seed.",
			"interleaved: one generator, 32 iterations of [randi(), randf(), randi_range(0, 9)].",
			"*_str arrays hold var_to_str(value) as requested. CAUTION: for values exactly representable as float32 (all randf()/randf_range() outputs) Godot 4.7 var_to_str prints the SHORTEST FLOAT32 text (e.g. 0.2981868), which does NOT parse back to the same float64. Use *_bits or rng_fixture.fullprec.json for exact values.",
			"*_bits arrays hold the IEEE-754 float64 bit pattern as 16 hex digits (big-endian, e.g. 3fd0000000000000 = 0.25).",
			"The plain arrays go through Godot's default JSON writer (~15 significant digits, lossy); rng_fixture.fullprec.json is the same document with JSON.stringify(..., full_precision=true).",
			"randf() and randf_range() return float32-representable values (widened to float64); randfn() is full float64.",
			"interleaved_str keeps [var_to_str(randi), var_to_str(randf), var_to_str(randi_range)]; interleaved_randf_bits holds the middle element bits.",
		],
		"call_shapes": {
			"randi": "rng.randi()",
			"randf": "rng.randf()",
			"randi_range_1_100": "rng.randi_range(1, 100)",
			"randi_range_m5_5": "rng.randi_range(-5, 5)",
			"randf_range_m2_5_7_5": "rng.randf_range(-2.5, 7.5)",
			"randfn_0_1": "rng.randfn(0.0, 1.0)",
		},
		"seeds": seeds_out,
		"seed_42_randi_mod_7": mod7,
	}
	return writer.write_json("kernel/rng_fixture.json", fixture)


# --- hashes ----------------------------------------------------------------

func _hash_strings() -> Array:
	var long_text: String = ""
	for i in range(200):
		long_text += char(97 + (i % 26))
	return [
		"",
		"a",
		"abc",
		"A",
		"salvage_cargo",
		"generic_crate",
		"marker_12",
		"salvage_cargo|marker_12|c_03",
		long_text,
		"Ünïcødé",
		"日本語",
		"emoji 🚀",
		"0",
		"42",
		"-1",
		"3:1:0",
		"derelict_42|cargo|0",
		"marker_7|room_3|crate_2",
		"salvage|m1|c1",
		"generic_crate|salvage|m1|c1|abyssal_synaptic_sea|0|generic_crate",
		"3:1:0:salvage_01",
		"seed_000017",
		"a b\tc\nd",
	]


func _string_hash_fixture(writer) -> bool:
	var rows: Array = []
	for text_variant in _hash_strings():
		var s: String = text_variant
		var utf8: PackedByteArray = s.to_utf8_buffer()
		var code_points: Array = []
		for i in range(s.length()):
			code_points.append(s.unicode_at(i))
		rows.append({
			"string": s,
			"length_code_points": s.length(),
			"utf8_hex": utf8.hex_encode(),
			"code_points": code_points,
			"s_hash": s.hash(),
			"hash_s": hash(s),
			"abs_s_hash": abs(s.hash()),
		})
	var ints: Array = []
	for n in [0, 1, 42, -1]:
		ints.append({"value": n, "hash": hash(n)})
	var fixture: Dictionary = {
		"schema": "parity.kernel.string_hash.v1",
		"notes": [
			"s_hash = String.hash() (32-bit, returned as a non-negative int); hash_s = global hash(s); abs_s_hash = abs(s.hash()) as used by LootRoller._stable_seed().",
			"Strings are UTF-32 internally in Godot; code_points lists s.unicode_at(i).",
		],
		"strings": rows,
		"ints": ints,
		"string_name_abc": {"value": "abc", "hash": hash(StringName("abc"))},
		"string_abc_hash_for_comparison": hash("abc"),
	}
	return writer.write_json("kernel/string_hash_fixture.json", fixture)


# --- JSON / float formatting -------------------------------------------------

func _float_values() -> Array:
	return [0, 1, -1, 42, 9007199254740993, 0.0, 1.0, -0.0, 0.1, 0.2, 0.30000000000000004,
		1.0 / 3.0, 2.0 / 3.0, 4.0 / 3.0, -2.5, 1e-7, 1.5e-5, 123456789.123, 1e15, 1e16,
		1e21, 1e22, 3.14159265358979, 100.0, 0.5, 12.345678901234567, 60.0 * 0.016666666666666666]


func _float_format_fixture(writer) -> bool:
	var values: Array = _float_values()
	var each: Array = []
	for v in values:
		var row: Dictionary = {
			"var_to_str": var_to_str(v),
			"str": str(v),
			"json": JSON.stringify(v),
			"json_full_precision": JSON.stringify(v, "", true, true),
			"type": type_string(typeof(v)),
		}
		if typeof(v) == TYPE_FLOAT:
			row["float64_bits"] = float_bits_hex(float(v))
			row["var_to_str_roundtrips"] = str_to_var(var_to_str(v)) == v
			row["json_default_roundtrips"] = float(JSON.parse_string(JSON.stringify(v))) == float(v)
			if float(v) == 0.0:
				row["negative_zero_signbit"] = (1.0 / float(v)) < 0.0
		each.append(row)
	# The GDScript literal -0.0 in the list above folds to +0.0; produce a real
	# negative zero at runtime to show how every formatter treats the sign.
	var runtime_negative_zero: float = 0.0 * -1.0
	var negative_zero_row: Dictionary = {
		"expression": "0.0 * -1.0",
		"float64_bits": float_bits_hex(runtime_negative_zero),
		"negative_zero_signbit": (1.0 / runtime_negative_zero) < 0.0,
		"var_to_str": var_to_str(runtime_negative_zero),
		"str": str(runtime_negative_zero),
		"json": JSON.stringify(runtime_negative_zero),
		"json_full_precision": JSON.stringify(runtime_negative_zero, "", true, true),
	}
	var f32_value: float = _fresh_rng(42).randf()
	var f32_probe: Dictionary = {
		"note": "value exactly representable as float32 (first randf() of a RandomNumberGenerator seeded with 42)",
		"float64_bits": float_bits_hex(f32_value),
		"var_to_str": var_to_str(f32_value),
		"var_to_str_roundtrips": str_to_var(var_to_str(f32_value)) == f32_value,
		"json": JSON.stringify(f32_value),
		"json_full_precision": JSON.stringify(f32_value, "", true, true),
	}
	var tab_text: String = JSON.stringify(values, "\t")
	var compact_text: String = JSON.stringify(values)
	var parse_source: String = '{"i": 17, "f": 17.0, "e": 1e3, "n": -0, "big": 12345678901234}'
	var parsed: Variant = JSON.parse_string(parse_source)
	var parse_types: Dictionary = {}
	if parsed is Dictionary:
		for key in (parsed as Dictionary).keys():
			var pv: Variant = parsed[key]
			parse_types[str(key)] = {
				"typeof": typeof(pv),
				"type_name": type_string(typeof(pv)),
				"var_to_str": var_to_str(pv),
			}
	var fixture: Dictionary = {
		"schema": "parity.kernel.float_format.v1",
		"notes": [
			"values_stringified_tab = JSON.stringify(values, \"\\t\"); values_stringified_compact = JSON.stringify(values). Same text is written raw to float_format_raw.json.",
			"Godot JSON default (full_precision=false) prints floats with ~15 significant digits and always keeps a '.0' on integral floats; ints are printed exactly.",
			"JSON.parse_string returns EVERY number as float (TYPE_FLOAT=3), including integer literals.",
			"Negative zero loses its sign in var_to_str, str and JSON (both precisions) - see runtime_negative_zero.",
			"var_to_str on a float64 that is exactly representable as float32 prints the shortest float32 text, which does not round-trip as float64 - see float32_representable_probe.",
		],
		"values_stringified_tab": tab_text,
		"values_stringified_compact": compact_text,
		"values_stringified_full_precision": JSON.stringify(values, "", true, true),
		"each": each,
		"runtime_negative_zero": negative_zero_row,
		"float32_representable_probe": f32_probe,
		"parse_source": parse_source,
		"parse_types": parse_types,
		"typeof_constants": {"TYPE_INT": TYPE_INT, "TYPE_FLOAT": TYPE_FLOAT, "TYPE_STRING": TYPE_STRING},
	}
	var ok: bool = writer.write_json("kernel/float_format_fixture.json", fixture)
	ok = writer.write_text("kernel/float_format_raw.json", tab_text) and ok
	var sample: Dictionary = {"b": 1, "a": {"d": [1, 2, {"z": 0, "y": 1}], "c": "x\ty\"z\\"}, "é": "ü", "ctrl": "\u0001"}
	ok = writer.write_text("kernel/stringify_sample_raw.json", JSON.stringify(sample, "\t")) and ok
	ok = writer.write_text("kernel/stringify_sample_raw_2space.json", JSON.stringify(sample, "  ")) and ok
	return ok


# --- FNV-1a (SeedDeterminismContract) ------------------------------------------

func _hex64(value: int) -> String:
	return String.num_uint64(value, 16).lpad(16, "0")


func _fnv_row(label: String, text: String) -> Dictionary:
	var h: int = SeedDeterminismContractScript.fnv1a_64(text)
	return {
		"label": label,
		"length_code_points": text.length(),
		"fnv1a_64": h,
		"fnv1a_64_hex": _hex64(h),
	}


func _fnv1a_fixture(writer) -> bool:
	var strings: Array = []
	for text in ["", "a", "b", "abc", "foobar", "salvage_cargo", "seed_000017", "Ünïcødé", "日本語", "emoji 🚀", "{\n  \"a\": 1\n}"]:
		var row: Dictionary = _fnv_row(str(text), str(text))
		row["input"] = str(text)
		strings.append(row)

	var files_out: Array = []
	var ok: bool = true
	var layout_files: Array = [
		"res://data/procgen/smoke/seed_000017/layout.json",
		"res://data/procgen/golden/coherent_ship_001/layout.json",
		"res://data/procgen/golden/coherent_ship_002/layout.json",
		"res://data/procgen/golden/coherent_ship_003/layout.json",
	]
	for path_variant in layout_files:
		var path: String = path_variant
		if not FileAccess.file_exists(path):
			continue
		# Normalize CRLF so the hash matches the git blob bytes regardless of the
		# checkout's core.autocrlf setting.
		var raw_text: String = FileAccess.get_file_as_string(path).replace(CRLF, LF)
		var reserialized: String = JSON.stringify(JSON.parse_string(raw_text), "  ")
		var name: String = path.get_base_dir().get_file()
		var raw_row: Dictionary = _fnv_row("%s file text (LF)" % path, raw_text)
		raw_row["source"] = path
		raw_row["hashed_text"] = "file text decoded as UTF-8 with CRLF normalized to LF (= the git blob bytes; copies live in fixtures/golden/)"
		var re_row: Dictionary = _fnv_row("%s JSON.stringify(JSON.parse_string(text), \"  \")" % path, reserialized)
		re_row["source"] = path
		re_row["hashed_text_file"] = "kernel/fnv1a_inputs/%s_reserialized_2space.json" % name
		ok = writer.write_text("kernel/fnv1a_inputs/%s_reserialized_2space.json" % name, reserialized) and ok
		files_out.append(raw_row)
		files_out.append(re_row)

	# derelict.json's guaranteed "dock" role has no eligible zone in the legacy
	# (non-extended) templates the contract pipeline selects from, which only
	# emits a RoomAssigner warning; use the debug exporter's archetype instead.
	var debug_archetype: Dictionary = {
		"name": "Derelict",
		"type": "derelict",
		"template": "derelict_a",
		"guaranteed_roles": [],
		"role_weights": {},
		"max_duplicates": 3,
	}
	var goldens: Array = []
	var golden_specs: Array = [
		{"tag": "s17_medium_pristine", "size": ShipBlueprintScript.Size.MEDIUM, "condition": ShipBlueprintScript.Condition.PRISTINE, "seed": 17, "archetype": {}, "archetype_label": "{}", "biome_id": "", "difficulty_id": ""},
		{"tag": "s42_small_wrecked_abyssal_standard", "size": ShipBlueprintScript.Size.SMALL, "condition": ShipBlueprintScript.Condition.WRECKED, "seed": 42, "archetype": {}, "archetype_label": "{}", "biome_id": "abyssal_synaptic_sea", "difficulty_id": "standard"},
		{"tag": "s42_small_damaged_derelict_a_dead_fleet_deep_dive", "size": ShipBlueprintScript.Size.SMALL, "condition": ShipBlueprintScript.Condition.DAMAGED, "seed": 42, "archetype": debug_archetype, "archetype_label": "procgen_structural_debug_export.gd _derelict_archetype() (template derelict_a, no guaranteed roles)", "biome_id": "dead_fleet", "difficulty_id": "deep_dive"},
	]
	for spec_variant in golden_specs:
		var spec: Dictionary = spec_variant
		var blueprint = ShipBlueprintScript.new(int(spec["size"]), int(spec["condition"]), int(spec["seed"]))
		var result: Dictionary = SeedDeterminismContractScript.record_golden(
			blueprint, spec["archetype"], str(spec["biome_id"]), str(spec["difficulty_id"]))
		var match_result: Dictionary = SeedDeterminismContractScript.assert_layout_match(
			ShipBlueprintScript.new(int(spec["size"]), int(spec["condition"]), int(spec["seed"])),
			spec["archetype"], str(spec["biome_id"]), str(spec["difficulty_id"]))
		var pipeline_layout: Dictionary = SeedDeterminismContractScript._run_pipeline(
			ShipBlueprintScript.new(int(spec["size"]), int(spec["condition"]), int(spec["seed"])),
			spec["archetype"], str(spec["biome_id"]), str(spec["difficulty_id"]), "")
		var pipeline_text: String = JSON.stringify(pipeline_layout, "  ")
		var text_rel: String = "kernel/fnv1a_inputs/%s_contract_pipeline_2space.json" % str(spec["tag"])
		ok = writer.write_text(text_rel, pipeline_text) and ok
		var text_hash: int = SeedDeterminismContractScript.fnv1a_64(pipeline_text)
		if text_hash != int(result.get("golden_hash", 0)):
			writer.errors.append("fnv1a golden text hash mismatch for %s" % str(spec["tag"]))
			ok = false
		goldens.append({
			"tag": spec["tag"],
			"hashed_text_file": text_rel,
			"hashed_text_note": "exact JSON.stringify(layout, \"  \") text (engine Vector2i/Vector3 values appear as \"(x, y)\" strings, as Godot's JSON writer emits them).",
			"inputs": {
				"size": int(spec["size"]),
				"condition": int(spec["condition"]),
				"seed": int(spec["seed"]),
				"archetype": spec["archetype_label"],
				"archetype_dict": spec["archetype"],
				"biome_id": spec["biome_id"],
				"difficulty_id": spec["difficulty_id"],
			},
			"record_golden": result,
			"golden_hash_hex": _hex64(int(result.get("golden_hash", 0))),
			"assert_layout_match": match_result,
		})

	var fixture: Dictionary = {
		"schema": "parity.kernel.fnv1a.v1",
		"source": "res://scripts/procgen/seed_determinism_contract.gd",
		"notes": [
			"SeedDeterminismContract.fnv1a_64(text) iterates text.unicode_at(i) (UTF-32 code points, NOT UTF-8 bytes): h ^= code_point; h *= 0x100000001b3 (mod 2^64). Offset basis 0xcbf29ce484222325.",
			"fnv1a_64 is the signed int64 reinterpretation; fnv1a_64_hex is the unsigned 64-bit value.",
			"record_golden / assert_layout_match hash JSON.stringify(layout, \"  \") of SeedDeterminismContract._run_pipeline (template/room/cell/wall/serializer + optional EncounterInjector with the contract's built-in biome/difficulty defaults) - a DIFFERENT pipeline than ShipLayoutGenerator.generate_with_options.",
		],
		"strings": strings,
		"files": files_out,
		"pipeline_goldens": goldens,
	}
	ok = writer.write_json("kernel/fnv1a_fixture.json", fixture) and ok
	return ok
