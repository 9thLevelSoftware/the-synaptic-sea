extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const MapperScript := preload("res://scripts/procgen/procgen_bundle_mapper.gd")

var _last_structural_difference: String = ""

func _init() -> void:
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null:
		print("TASK5 LIVE MAPPER BLOCKED adapter_missing=true"); quit(1); return
	var consumer: RefCounted = ConsumerScript.new()
	var cases: Array = [{"label":"intact", "seed":42, "size":0, "condition":0}, {"label":"damaged", "seed":77, "size":1, "condition":1}]
	var failures: Array[String] = []
	var fractured_case: Dictionary = _find_legacy_fractured_case(consumer, generator)
	if fractured_case.is_empty(): failures.append("bounded fractured fixture unavailable")
	else: cases.append(fractured_case)
	for item in cases:
		var request: Dictionary = consumer.build_request(int(item.seed), int(item.size), int(item.condition), {}, "standard", "", "", 0, 0, [{"kind":"combat_mastery", "value_bp":5000}, {"kind":"objective_pace", "value_bp":5000}])
		# The legacy export methods intentionally build the explicit migration-oracle
		# request identity. Compare the mapper against that same one-pass bundle.
		request.site.site_id = "legacy-site"
		if item.label == "fractured": request.site.archetype_id = "frigate"
		var lifecycle: Dictionary = JSON.parse_string(str(generator.generate_bundle(JSON.stringify(request))))
		if str(lifecycle.get("schema_version", "")) != "procgen-lifecycle-result-5" or str(lifecycle.get("status", "")) != "completed":
			failures.append("%s lifecycle_v5" % item.label); continue
		var bundle: Dictionary = lifecycle.get("bundle", {})
		if str(bundle.get("schema_version", "")) != "procgen-bundle-5": failures.append("%s bundle_v5" % item.label); continue
		if str((bundle.get("site_ir", {}) as Dictionary).get("schema_version", "")) != "site-ir-2": failures.append("%s site_ir_v2" % item.label); continue
		if item.label == "fractured" and not bool((bundle.get("site_ir", {}).get("ship", {}) as Dictionary).get("fractured", false)):
			failures.append("fractured fixture was not confirmed fractured")
			continue
		var mapped: Dictionary = MapperScript.new().map_to_loader_documents(bundle)
		var params: Dictionary = {"archetype_id": str(request.site.archetype_id), "intactness_override": int(request.site.intactness_override_bp), "loot_richness": int(request.site.loot_richness_bp), "difficulty_id": str(request.difficulty_id)}
		var native_layout: Variant = JSON.parse_string(str(generator.export_layout_json(int(item.seed), params, "ship_structural_v0")))
		# The legacy exports are migration oracles only. Structural layout remains
		# byte-equivalent, but gameplay is now authoritative in SiteIR v2 and must
		# not be asserted equal to the legacy gameplay slice export.
		if mapped.is_empty() or not _structural_oracle_matches(mapped.layout, native_layout, bundle.site_ir): failures.append("%s layout parity:%s" % [item.label, _last_structural_difference])
		var native_gameplay: Variant = JSON.parse_string(str(generator.export_gameplay_slice_json(int(item.seed), params)))
		if not native_gameplay is Dictionary: failures.append("%s legacy gameplay oracle unavailable" % item.label)
		if mapped.is_empty() or not _authoritative_objectives_match(mapped): failures.append("%s site mission projection" % item.label)
		if item.label == "fractured" and not bool((bundle.get("site_ir", {}).get("ship", {}) as Dictionary).get("fractured", false)): failures.append("%s fractured flag" % item.label)
	if not failures.is_empty():
		for failure in failures: print("TASK5 LIVE MAPPER FAIL:%s" % failure)
		quit(1); return
	print("TASK5 LIVE MAPPER PASS intact=true damaged=true fractured=true structural_native_oracle=true site_ir_authoritative=true legacy_gameplay_non_authoritative=true")
	quit(0)

func _find_legacy_fractured_case(consumer: RefCounted, generator: Object) -> Dictionary:
	for seed in range(256):
		var request: Dictionary = consumer.build_request(seed, 2, 2, {}, "standard", "", "", 0, 0, [{"kind":"combat_mastery", "value_bp":5000}, {"kind":"objective_pace", "value_bp":5000}])
		request.site.site_id = "legacy-site"
		request.site.archetype_id = "frigate"
		var lifecycle_value: Variant = JSON.parse_string(str(generator.generate_bundle(JSON.stringify(request))))
		if not lifecycle_value is Dictionary or str((lifecycle_value as Dictionary).get("status", "")) != "completed": continue
		var ship: Dictionary = (((lifecycle_value as Dictionary).get("bundle", {}) as Dictionary).get("site_ir", {}) as Dictionary).get("ship", {})
		if bool(ship.get("fractured", false)):
			return {"label":"fractured", "seed":seed, "size":2, "condition":2}
	return {}

func _structural_oracle_matches(mapped_layout: Dictionary, native_layout: Variant, site: Dictionary) -> bool:
	if not native_layout is Dictionary: return false
	var gated_refs: Dictionary = {}
	var edge_index: Dictionary = {}
	for edge_value in (site.get("navigation", {}) as Dictionary).get("edges", []):
		if edge_value is Dictionary: edge_index[str((edge_value as Dictionary).get("id", ""))] = edge_value
	for gate_value in (site.get("mission_graph", {}) as Dictionary).get("gates", []):
		if not gate_value is Dictionary: return false
		var edge_id: String = str((gate_value as Dictionary).get("navigation_edge", ""))
		if not edge_index.has(edge_id): return false
		gated_refs[str((edge_index[edge_id] as Dictionary).get("structural_ref", ""))] = true
	var mapped_view: Dictionary = mapped_layout.duplicate(true)
	var native_view: Dictionary = (native_layout as Dictionary).duplicate(true)
	for view in [mapped_view, native_view]:
		# Gate 3 replaces the migration oracle's empty encounter array with the
		# authoritative GameplayIR projection and adds the approved presentation
		# assembly. Keep this migration-oracle comparison strictly structural.
		view["encounters"] = []
		view.erase("presentation_assembly")
		view["blocked_links"] = []
		for portal_value in view.get("portals", []):
			if portal_value is Dictionary and gated_refs.has(str((portal_value as Dictionary).get("edge_key", ""))):
				(portal_value as Dictionary)["state"] = "SITE_GATE"
	_last_structural_difference = _first_difference(mapped_view, native_view, "layout")
	return _last_structural_difference.is_empty()

func _first_difference(a: Variant, b: Variant, path: String) -> String:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			var only_a: Array = []
			var only_b: Array = []
			for key in a.keys():
				if not b.has(key): only_a.append(key)
			for key in b.keys():
				if not a.has(key): only_b.append(key)
			return "%s.keys(%d!=%d only_mapped=%s only_oracle=%s)" % [path, a.size(), b.size(), str(only_a), str(only_b)]
		for key in a.keys():
			if not b.has(key): return "%s.%s(missing)" % [path, str(key)]
			var nested: String = _first_difference(a[key], b[key], "%s.%s" % [path, str(key)])
			if not nested.is_empty(): return nested
		return ""
	if a is Array and b is Array:
		if a.size() != b.size(): return "%s.size(%d!=%d)" % [path, a.size(), b.size()]
		for i in a.size():
			var nested: String = _first_difference(a[i], b[i], "%s[%d]" % [path, i])
			if not nested.is_empty(): return nested
		return ""
	if (a is int or a is float) and (b is int or b is float):
		return "" if float(a) == float(b) else "%s(%s!=%s)" % [path, str(a), str(b)]
	return "" if a == b else "%s(%s!=%s)" % [path, str(a), str(b)]

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
