extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const MapperScript := preload("res://scripts/procgen/procgen_bundle_mapper.gd")

func _init() -> void:
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null:
		print("TASK5 LIVE MAPPER BLOCKED adapter_missing=true"); quit(1); return
	var consumer: RefCounted = ConsumerScript.new()
	var cases: Array = [{"label":"intact", "seed":42, "size":0, "condition":0}, {"label":"damaged", "seed":77, "size":1, "condition":1}, {"label":"fractured", "seed":1, "size":2, "condition":2}]
	var failures: Array[String] = []
	for item in cases:
		var request: Dictionary = consumer.build_request(int(item.seed), int(item.size), int(item.condition))
		# The legacy export methods intentionally build the explicit migration-oracle
		# request identity. Compare the mapper against that same one-pass bundle.
		request.site.site_id = "legacy-site"
		if item.label == "fractured": request.site.archetype_id = "frigate"
		var lifecycle: Dictionary = JSON.parse_string(str(generator.generate_bundle(JSON.stringify(request))))
		if str(lifecycle.get("schema_version", "")) != "procgen-lifecycle-result-3" or str(lifecycle.get("status", "")) != "completed":
			failures.append("%s lifecycle_v3" % item.label); continue
		var bundle: Dictionary = lifecycle.get("bundle", {})
		if str(bundle.get("schema_version", "")) != "procgen-bundle-3": failures.append("%s bundle_v3" % item.label); continue
		if str((bundle.get("site_ir", {}) as Dictionary).get("schema_version", "")) != "site-ir-2": failures.append("%s site_ir_v2" % item.label); continue
		if item.label == "fractured" and not bool((bundle.get("site_ir", {}).get("ship", {}) as Dictionary).get("fractured", false)):
			failures.append("fractured fixture was not confirmed fractured")
			continue
		var mapped: Dictionary = MapperScript.new().map_to_loader_documents(bundle)
		var params: Dictionary = {"archetype_id": str(request.site.archetype_id), "intactness_override": int(request.site.intactness_override_bp), "loot_richness": int(request.site.loot_richness_bp)}
		var native_layout: Variant = JSON.parse_string(str(generator.export_layout_json(int(item.seed), params, "ship_structural_v0")))
		# The legacy exports are migration oracles only. Structural layout remains
		# byte-equivalent, but gameplay is now authoritative in SiteIR v2 and must
		# not be asserted equal to the legacy gameplay slice export.
		if mapped.is_empty() or not _same(mapped.layout, native_layout): failures.append("%s layout parity" % item.label)
		var native_gameplay: Variant = JSON.parse_string(str(generator.export_gameplay_slice_json(int(item.seed), params)))
		if not native_gameplay is Dictionary: failures.append("%s legacy gameplay oracle unavailable" % item.label)
		if mapped.is_empty() or not _authoritative_objectives_match(mapped): failures.append("%s site mission projection" % item.label)
		if item.label == "fractured" and not bool((bundle.get("site_ir", {}).get("ship", {}) as Dictionary).get("fractured", false)): failures.append("%s fractured flag" % item.label)
	if not failures.is_empty():
		for failure in failures: print("TASK5 LIVE MAPPER FAIL:%s" % failure)
		quit(1); return
	print("TASK5 LIVE MAPPER PASS intact=true damaged=true fractured=true structural_native_oracle=true site_ir_authoritative=true legacy_gameplay_non_authoritative=true")
	quit(0)

func _authoritative_objectives_match(mapped: Dictionary) -> bool:
	var site: Dictionary = mapped.get("site_ir", {})
	var mission: Dictionary = site.get("mission_graph", {})
	var expected: Array[String] = []
	for node_value in mission.get("nodes", []):
		if node_value is Dictionary and str((node_value as Dictionary).get("kind", "")) != "start":
			expected.append(str((node_value as Dictionary).get("id", "")))
	var actual: Array[String] = []
	for objective_value in (mapped.get("gameplay_slice", {}) as Dictionary).get("objectives", []):
		if objective_value is Dictionary: actual.append(str((objective_value as Dictionary).get("id", "")))
	return not expected.is_empty() and expected == actual

func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a.keys():
			if not b.has(key) or not _same(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _same(a[i], b[i]): return false
		return true
	if (a is int or a is float) and (b is int or b is float): return float(a) == float(b)
	return a == b
