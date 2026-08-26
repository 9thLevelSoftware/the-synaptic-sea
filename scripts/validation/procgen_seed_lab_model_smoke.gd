extends SceneTree

const GraphViewScript := preload("res://scripts/procgen/seed_lab/procgen_seed_lab_graph_view.gd")
const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")

class FakeGenerator extends RefCounted:
	var calls: int = 0
	var lifecycle: String = ""
	func generate_bundle(_request: String) -> String:
		calls += 1
		return lifecycle

class FakeConsumer extends RefCounted:
	var last_error: String = ""
	var result: Dictionary = {}
	func consume(_raw: String, _request: Dictionary, _build: Dictionary, _runtime: Dictionary, _caps: Dictionary) -> Dictionary:
		return result.duplicate(true)

func _expect(condition: bool, marker: String) -> bool:
	if not condition:
		print("PROCGEN SEED LAB MODEL FAIL %s" % marker)
		quit(1)
		return false
	return true

func _init() -> void:
	var script := load("res://scripts/procgen/seed_lab/procgen_seed_lab_model.gd")
	if script == null or script.new() == null:
		print("PROCGEN SEED LAB MODEL RED missing_model")
		quit(1)
		return
	var model: RefCounted = script.new()
	var request := {"schema_version":"procgen-request-2", "generator_version":3, "content_manifest_hash":"e".repeat(64), "world_seed":44, "site": {"site_id":"site:44:2:3", "x":2, "y":3, "archetype_id":"shuttle", "kit_id":"ship_structural_v0", "intactness_override_bp":null, "cause_of_loss":null, "loot_richness_bp":10000}, "difficulty_id":"standard", "player_model": {"schema_version":"player-model-2", "signals":[]}, "presentation": {"seed":7, "locale":"en"}, "requested_domains":["world","site","gameplay","presentation"]}
	var bundle := {"schema_version":"procgen-bundle-5", "version": {"generator_version":3, "content_manifest_hash":"e".repeat(64), "export_schemas":model.EXPORT_SCHEMAS.duplicate(true)}, "semantic_hash": "a".repeat(64), "request": request, "world_ir": {"schema_version":"world-ir-2", "markers": [{"id": "marker:1"}]}, "site_ir": {"schema_version":"site-ir-2", "mission_graph": {"nodes": [{"id": "mission:1"}], "edges": []}, "ship": {"topology": {"rooms": [{"id": "room:1"}]}}, "navigation": {"nodes": [{"id": "nav:1"}]}}, "gameplay_ir": {"schema_version":"gameplay-ir-3", "encounter": {"spawns": [{"id": "spawn:1"}]}, "items": [{"id": "item:1"}], "creature_blueprints": [{"id": "creature:1"}]}, "presentation_ir": {"schema_version":"presentation-ir-2", "decisions":[], "fallback_subjects":[], "instructions":[], "repairs":[]}, "trace": {"schema_version":"generation-trace-4", "candidate_decisions": ["rejected"], "failed_constraints": ["none"], "repairs": ["repair:1"], "retries": ["retry:1"], "rng_channels": ["world.archetype"], "adaptive_decisions": [], "fallback": null, "stage_timings_micros": {"world":1}}, "metrics": {"schema_version":"generation-metrics-1", "pipeline_executions":1, "room_count":1, "entity_count":1, "structural_placement_count":1, "stage_timings_micros":{"world":1}, "threat": 10}}
	var malformed_bundle: Dictionary = bundle.duplicate(true)
	malformed_bundle.trace = "invalid"
	if not _expect(not model.load_bundle(1, malformed_bundle, request) and model.last_error == "bundle_version", "malformed_bundle_rejected"): return
	malformed_bundle = bundle.duplicate(true)
	malformed_bundle.version.export_schemas.procgen_bundle = "procgen-bundle-4"
	if not _expect(not model.load_bundle(1, malformed_bundle, request), "mixed_export_schema_rejected"): return
	malformed_bundle = bundle.duplicate(true)
	malformed_bundle.request.site.erase("kit_id")
	if not _expect(not model.load_bundle(1, malformed_bundle, request), "request_shape_rejected"): return
	if not _expect(model.load_bundle(0, bundle, request), "load_bundle:" + model.last_error + ":" + JSON.stringify(bundle.request) + ":" + JSON.stringify(request)): return
	var view: Dictionary = model.get_slot(0)
	for domain in ["world", "mission", "topology", "navigation", "encounter", "item", "creature"]:
		if not _expect(view.graphs.has(domain) and view.graphs[domain].nodes.size() > 0, "graph_%s" % domain): return
	var tampered: Dictionary = model.get_slot(0)
	tampered.bundle.request.world_seed = 999
	if not _expect(int(model.get_slot(0).request.world_seed) == 44, "deep_copy_isolation"): return
	if not _expect(model.set_lock("world_seed") and model.is_locked("world_seed"), "lock_world_seed"): return
	for field in ["site.site_id", "site.x", "site.y", "site.archetype_id", "site.kit_id", "site.intactness_override_bp", "site.loot_richness_bp", "site.cause_of_loss", "difficulty_id", "player_model", "presentation.seed", "presentation.locale"]:
		if not _expect(model.set_lock(field), "lock_%s" % field): return
	model.capture_locks(request)
	var proposed: Dictionary = request.duplicate(true); proposed.world_seed = 999; proposed.site.x = 99
	var selected_domains: Array[String] = ["presentation", "world"]
	var selected: Dictionary = model.selective_request(proposed, selected_domains, request)
	if not _expect(selected.requested_domains == ["world", "presentation"] and selected.world_seed == 44 and selected.site.x == 2, "selective_domains_order"): return
	var invalid_domains: Array[String] = ["invalid"]
	if not _expect(model.selective_request(request, invalid_domains).is_empty(), "invalid_domains"): return
	var no_domains: Array[String] = []
	if not _expect(model.selective_request(request, no_domains).is_empty(), "selective_empty"): return
	var compared_model: RefCounted = script.new()
	var second := bundle.duplicate(true)
	second.semantic_hash = "b".repeat(64)
	second.metrics.threat = 15
	if not _expect(compared_model.load_bundle(1, second, request), "load_compare_slot"): return
	# Use one model for the public two-slot compare.
	model.slots[1] = compared_model.get_slot(1)
	var comparison: Dictionary = model.compare()
	if not _expect(bool(comparison.valid) and not bool(comparison.same_hash) and comparison.metrics_delta.threat == 5.0, "compare"): return
	var inspected: Dictionary = model.inspect_trace(0)
	if not _expect(inspected.candidate_decisions.size() == 1 and inspected.repairs.size() == 1 and inspected.stage_timings_micros.world == 1, "trace_inspection"): return
	for domain in ["world", "mission", "topology", "navigation", "encounter", "item", "creature"]:
		var graph_view: Control = GraphViewScript.new()
		var graph_ok: bool = graph_view.set_graph(model.get_slot(0).graphs[domain])
		graph_view.free()
		if not _expect(graph_ok, "graph_view_%s" % domain): return
	var diagnostic := {
		"schema_version": "procgen-diagnostic-1", "kind": "bundle",
		"identity_hash": "c".repeat(64), "capture_hash": "d".repeat(64),
		"identity": {"world_seed": 44, "site_id": "site:44:2:3", "site_x": 2, "site_y": 3, "archetype_id": "shuttle", "difficulty_id": "standard", "generator_version": 3, "content_manifest_hash": "e".repeat(64), "requested_domains": ["world", "site", "gameplay", "presentation"]},
		"versions": {"generator_version": 3, "build_target": "x86_64-pc-windows-msvc"},
		"hashes": {"semantic_hash": bundle.semantic_hash, "content_manifest_hash": "e".repeat(64), "build_source_commit": "f".repeat(40), "artifact_sha256": "1".repeat(64)},
		"candidate_decisions": [], "failed_constraints": [], "repairs": [], "retries": [],
		"fallbacks": [], "failures": [],
	}
	for classification in ["approved_candidate", "failure_seed", "authored_fallback"]:
		var promotion_diagnostic: Dictionary = diagnostic.duplicate(true)
		if classification == "failure_seed": promotion_diagnostic.repairs = ["reconciled:fragment_metadata"]
		if classification == "authored_fallback":
			promotion_diagnostic.fallbacks = ["site:authored-safe-return"]
			promotion_diagnostic.candidate_decisions = ["site:selected_fallback"]
		var candidate: Dictionary = model.build_promotion_candidate(classification, promotion_diagnostic, request)
		if not _expect(candidate.schema_version == "procgen-promotion-candidate-1" and candidate.candidate_id == _sha256(classification + ":" + diagnostic.identity_hash) and candidate.expected.has_all(["semantic_hash", "failure_code", "fallback_id", "trace_code"]) and candidate.provenance.tool_version == "seed-lab-1" and not candidate.has("approval_ref"), "promotion_%s:%s" % [classification, model.last_error]): return
	var generator := FakeGenerator.new()
	var consumer := FakeConsumer.new()
	consumer.result = bundle
	generator.lifecycle = JSON.stringify({"bundle": bundle})
	var controller_script := load("res://scripts/procgen/seed_lab/procgen_seed_lab_controller.gd")
	var controller: RefCounted = controller_script.new()
	controller.configure(generator, consumer, {}, {}, {})
	if not _expect(controller.generate(0, request) and generator.calls == 1, "controller_exact_one_generation"): return
	consumer.result = {}
	consumer.last_error = "invalid_bundle"
	generator.lifecycle = JSON.stringify({"failure_code": "invalid_bundle"})
	if not _expect(not controller.generate(1, request) and not controller.last_result.success and controller.model.get_slot(1).failure.failure_code == "invalid_bundle", "controller_failure_state"): return
	var live := ClassDB.instantiate("DerelictGenerator") as Object
	var live_marker := "unavailable"
	if live != null:
		var live_consumer: RefCounted = ConsumerScript.new()
		var live_runtime: Dictionary = JSON.parse_string(str(live.generator_manifest()))
		var live_request: Dictionary = live_consumer.build_request(42, 0, 0, live_runtime)
		var live_build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
		var live_caps: Dictionary = JSON.parse_string(str(live.capabilities()))
		var live_bundle: Dictionary = live_consumer.consume(str(live.generate_bundle(JSON.stringify(live_request))), live_request, live_build, live_runtime, live_caps)
		if not _expect(not live_bundle.is_empty() and model.load_bundle(1, live_bundle, live_request), "live_bundle"): return
		for live_domain in ["world", "mission", "topology", "navigation", "encounter", "item", "creature"]:
			if not _expect(model.get_slot(1).graphs[live_domain].nodes.size() > 0, "live_graph_%s" % live_domain): return
		live_marker = "true"
	print("PROCGEN SEED LAB MODEL PASS graphs=7 compare=true locks=13 selective=true isolation=true trace=true promotion=3 controller_exact_one=true failure_state=true live=%s" % live_marker)
	quit(0)

func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()
