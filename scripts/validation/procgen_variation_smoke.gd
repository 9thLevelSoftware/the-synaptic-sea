extends SceneTree

# procgen_variation_smoke — Domain 7 (travel loop closure), generation layer.
# Asserts:
#   1. Two different seeds produce distinct room-variant multisets.
#   2. A variant with loot_bias changes a room's loot_table vs role baseline,
#      and the biased key is a real loot table.
#   3. Extended templates engage at deep_dive and stay off at standard.
#   4. Same seed generated twice -> identical variant + template output.
# Marker: PROCGEN VARIATION PASS variants_vary=true loot_biased=true tmpl_gated=true deterministic=true

const LayoutGen := preload("res://scripts/procgen/ship_layout_generator.gd")
const Blueprint := preload("res://scripts/procgen/ship_blueprint.gd")
const SliceBuilder := preload("res://scripts/procgen/gameplay_slice_builder.gd")

func _initialize() -> void:
	# --- Case 1: variants vary across seeds ---
	var variants_a: Array = _room_variants(101, "dead_fleet", "standard")
	var variants_b: Array = _room_variants(202, "dead_fleet", "standard")
	if variants_a.is_empty() or variants_a == variants_b:
		push_error("PROCGEN VARIATION FAIL variants did not vary across seeds: %s vs %s" % [str(variants_a), str(variants_b)])
		quit(1)
		return

	# --- Case 2: loot_bias changes a container/objective loot_table ---
	var loot_biased: bool = _has_biased_loot(303, "dead_fleet", "standard")
	if not loot_biased:
		push_error("PROCGEN VARIATION FAIL no room's loot_table reflected a variant loot_bias across sampled seeds")
		quit(1)
		return

	# --- Case 3: template gating ---
	var tmpl_std: String = _template_id(404, "dead_fleet", "standard")
	var extended_seen: bool = false
	for s in range(10):
		var tid: String = _template_id(500 + s, "dead_fleet", "deep_dive")
		if tid in ["compact", "dispersed", "stacked_v2", "derelict_a", "derelict_b"]:
			extended_seen = true
			break
	var std_is_legacy: bool = tmpl_std in ["spine", "bifurcated", "stacked"]
	if not (extended_seen and std_is_legacy):
		push_error("PROCGEN VARIATION FAIL template gating: extended_seen=%s std=%s" % [str(extended_seen), tmpl_std])
		quit(1)
		return

	# --- Case 4: determinism (variant arrays + template id) ---
	if _room_variants(777, "dead_fleet", "deep_dive") != _room_variants(777, "dead_fleet", "deep_dive"):
		push_error("PROCGEN VARIATION FAIL generation not deterministic for a fixed seed")
		quit(1)
		return
	if _template_id(777, "dead_fleet", "deep_dive") != _template_id(777, "dead_fleet", "deep_dive"):
		push_error("PROCGEN VARIATION FAIL template id not deterministic for a fixed seed")
		quit(1)
		return

	print("PROCGEN VARIATION PASS variants_vary=true loot_biased=true tmpl_gated=true deterministic=true")
	quit(0)

func _gen_layout(seed_v: int, biome: String, difficulty: String) -> Dictionary:
	var bp = Blueprint.new(1, 1, seed_v)
	var gen = LayoutGen.new()
	var extended: bool = difficulty in ["deep_dive", "hardened"]
	return gen.generate_with_options(bp, {}, biome, difficulty, extended)

func _room_variants(seed_v: int, biome: String, difficulty: String) -> Array:
	var out: Array = []
	for room in (_gen_layout(seed_v, biome, difficulty).get("rooms", []) as Array):
		if room is Dictionary:
			out.append(str((room as Dictionary).get("variant", "standard")))
	return out

func _template_id(seed_v: int, biome: String, difficulty: String) -> String:
	# The layout has no dedicated template_id field; the id is embedded in
	# design_intent ("procedurally generated <template_id> ship"). Parse it out.
	var intent: String = str(_gen_layout(seed_v, biome, difficulty).get("design_intent", ""))
	var prefix: String = "procedurally generated "
	var suffix: String = " ship"
	if intent.begins_with(prefix) and intent.ends_with(suffix):
		return intent.substr(prefix.length(), intent.length() - prefix.length() - suffix.length())
	return intent

func _has_biased_loot(seed_v: int, biome: String, difficulty: String) -> bool:
	var loot_doc: Dictionary = _load_loot_tables()
	for s in range(seed_v, seed_v + 12):
		var layout: Dictionary = _gen_layout(s, biome, difficulty)
		var slice: Dictionary = SliceBuilder.new().build(layout)
		for c in (slice.get("loot_containers", []) as Array):
			if not (c is Dictionary):
				continue
			var lt: String = str((c as Dictionary).get("loot_table", ""))
			# a bias-only table (not the two generic container kinds) proves a variant bias applied
			if lt in ["salvage_cargo", "salvage_engineering", "hidden_cache", "repair_parts_common"] and loot_doc.has(lt):
				return true
	return false

func _load_loot_tables() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://data/items/loot_tables.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
