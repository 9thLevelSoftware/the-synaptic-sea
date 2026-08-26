extends SceneTree

const SOURCE_PATH := "res://scripts/procgen/ship_generator.gd"

func _init() -> void:
	var failures: Array[String] = []
	var source: String = FileAccess.get_file_as_string(SOURCE_PATH)
	var production: String = _function_block(source, "func _generate_via_worldgen(", "func _load_worldgen_kit(")
	var public_generate: String = _function_block(source, "func generate(blueprint", "func _generate_via_worldgen(")
	_expect(not production.is_empty(), failures, "production_block")
	_expect(production.count("generator.generate_bundle(") == 1, failures, "single_bundle_call")
	for forbidden in [
		"generate_layout_json", "generate_gameplay_slice_json", "generate_migration_oracle(",
		"generate_layout_migration_oracle(", "ShipLayoutGenerator", "EncounterInjector",
		"GameplaySliceBuilder", "LootRoller", "layout_generator.", "_resolve_worldgen_loot_containers(",
		"_map_worldgen_loot_table(", "BiomeProfile", "DifficultyProfile",
	]:
		_expect(not production.contains(forbidden), failures, "production_forbidden_%s" % forbidden)
	_expect(public_generate.contains("_generate_via_worldgen("), failures, "public_routes_bundle")
	_expect(not public_generate.contains("migration_oracle("), failures, "public_no_oracle")
	_expect(source.contains("func generate_migration_oracle("), failures, "scene_oracle_named")
	_expect(source.contains("func generate_layout_migration_oracle("), failures, "layout_oracle_named")
	_expect(source.count("migration_oracle_invocations += 1") == 2, failures, "oracle_counter")
	_expect(source.contains("unsupported_legacy_archetype"), failures, "legacy_dictionary_rejected")
	_expect(source.contains("func configure_authored_fallback("), failures, "fallback_opt_in")
	_expect(source.contains("func clear_authored_fallback("), failures, "fallback_clear")
	_expect(source.contains("last_outcome = \"fallback_%s\""), failures, "fallback_outcome_namespaced")
	if not failures.is_empty():
		for failure in failures:
			print("TASK5 BRIDGE SOURCE FAIL:%s" % failure)
		quit(1)
		return
	print("TASK5 BRIDGE SOURCE PASS single_bundle=true no_post_authority=true oracle_explicit=true fallback_opt_in=true")
	quit(0)

func _function_block(source: String, start_marker: String, end_marker: String) -> String:
	var start: int = source.find(start_marker)
	if start < 0:
		return ""
	var end: int = source.find(end_marker, start + start_marker.length())
	return source.substr(start) if end < 0 else source.substr(start, end - start)

func _expect(ok: bool, failures: Array[String], label: String) -> void:
	if not ok:
		failures.append(label)
