extends SceneTree
## Task 3C native lifecycle smoke.
##
## This intentionally uses Object.call() because the native class is supplied by
## the GDExtension.  The script is source/contract validation until the rebuilt
## adapter is installed in the sample project.

const LIFECYCLE_SCHEMA := "procgen-lifecycle-result-4"
const CAPABILITIES_SCHEMA := "procgen-capabilities-3"
const MANIFEST_SCHEMA := "procgen-generator-manifest-3"
const REQUEST_SCHEMA := "procgen-request-2"
const GENERATOR_VERSION := 3
const DOMAINS := ["world", "site", "gameplay", "presentation"]
const RNG_CHANNELS := [
	"world.archetype", "world.biome", "world.hazard", "world.resource",
	"world.landmark", "world.route_cost", "site.structural", "site.mission_template",
	"site.gate_order", "site.functional_props", "site.spatial_annotations", "meta",
	"hull", "template", "topology", "residual_fill", "door", "furnish", "story",
	"intact", "breach", "scorch", "seal", "bodies", "fracture", "debris", "loot",
	"gameplay.creature_blueprint", "gameplay.creature_ability", "gameplay.creature_material",
	"gameplay.encounter_candidate", "gameplay.encounter_faction", "gameplay.encounter_reward",
	"gameplay.encounter_selection", "gameplay.item_family", "gameplay.item_affix",
	"presentation.asset_assembly",
]
const EXPORT_SCHEMAS := {
	"procgen_request": "procgen-request-2",
	"procgen_bundle": "procgen-bundle-4",
	"world_ir": "world-ir-2",
	"site_ir": "site-ir-2",
	"gameplay_ir": "gameplay-ir-2",
	"presentation_ir": "presentation-ir-2",
	"generation_trace": "generation-trace-3",
	"adaptive_proposal": "adaptive-proposal-1",
}
const ADAPTER_SCHEMAS := {
	"lifecycle_result": LIFECYCLE_SCHEMA,
	"capabilities": CAPABILITIES_SCHEMA,
	"generator_manifest": MANIFEST_SCHEMA,
}
const MAX_FRAMES := 600

var _frames := 0
var _generator_a: Object
var _generator_b: Object
var _request_json := ""
var _async_id := 0
var _phase := "start"
var _sync_hash := ""
var _failed := false

func _initialize() -> void:
	_generator_a = ClassDB.instantiate("DerelictGenerator") as Object
	_generator_b = ClassDB.instantiate("DerelictGenerator") as Object
	_expect(_generator_a != null and _generator_b != null, "generator_instances")
	if _failed:
		return

	for method_name in [
		"generate_bundle", "generate_bundle_async", "poll", "cancel",
		"capabilities", "generator_manifest",
	]:
		_expect(_generator_a.has_method(method_name), "method_a_%s" % method_name)
		_expect(_generator_b.has_method(method_name), "method_b_%s" % method_name)

	var capabilities := _read_object(_generator_a.call("capabilities"), "capabilities_json")
	_expect(capabilities.get("schema_version") == CAPABILITIES_SCHEMA, "capabilities_schema")
	_expect(capabilities.get("adapter_kind") == "native", "capabilities_adapter")
	_expect(capabilities.get("target") == "x86_64-pc-windows-msvc", "capabilities_target")
	_expect(capabilities.get("supports_sync") == true, "capabilities_sync")
	_expect(capabilities.get("supports_async") == true, "capabilities_async")
	_expect(capabilities.get("supports_cancel") == true, "capabilities_cancel")
	_expect(capabilities.get("worker_mode") == "thread_pool", "capabilities_worker_mode")
	_expect(capabilities.get("worker_count") == 2, "capabilities_worker_count")
	_expect(capabilities.get("queue_capacity") == 8, "capabilities_queue")
	_expect(capabilities.get("retained_results") == 16, "capabilities_retained")
	_expect(capabilities.get("max_request_bytes") == 65536, "capabilities_request_bytes")
	_expect(capabilities.get("max_entities") == 4096, "capabilities_entities")
	_expect(capabilities.get("max_trace_entries") == 4096, "capabilities_trace")
	_expect(capabilities.get("max_events") == 32, "capabilities_events")
	_expect(capabilities.get("deadline_ms") == 2000, "capabilities_deadline")
	_expect(capabilities.get("supported_domains") == DOMAINS, "capabilities_domains")
	_expect(capabilities.get("schemas") == ADAPTER_SCHEMAS, "capabilities_schemas")

	var manifest := _read_object(_generator_a.call("generator_manifest"), "manifest_json")
	_expect(manifest.get("schema_version") == MANIFEST_SCHEMA, "manifest_schema")
	_expect(manifest.get("target") == "x86_64-pc-windows-msvc", "manifest_target")
	_expect(capabilities.get("target") == manifest.get("target"), "target_identity")
	_expect(manifest.get("generator_version") == GENERATOR_VERSION, "manifest_generator")
	_expect(manifest.has("dirty_development") and manifest.get("dirty_development") is bool, "manifest_dirty_type")
	_expect(manifest.get("dirty_development") == false, "manifest_dirty_release")
	var source_commit := str(manifest.get("rust_source_commit", ""))
	var content_hash := str(manifest.get("content_manifest_hash", ""))
	_expect(_is_lower_hex(source_commit, 40), "manifest_source_hash")
	_expect(_is_lower_hex(content_hash, 64), "manifest_content_hash")
	_expect(manifest.get("export_schemas") == EXPORT_SCHEMAS, "manifest_export_schemas")
	_expect(manifest.get("adapter_schemas") == ADAPTER_SCHEMAS, "manifest_adapter_schemas")

	var request := {
		"schema_version": REQUEST_SCHEMA,
		"world_seed": 424242,
		"site": {
			"site_id": "lifecycle-smoke",
			"x": 3,
			"y": -7,
			"archetype_id": "frigate",
			"kit_id": "ship_structural_v0",
			"intactness_override_bp": null,
			"cause_of_loss": null,
			"loot_richness_bp": 1000,
		},
		"difficulty_id": "standard",
		"player_model": {"schema_version": "player-model-2", "signals": []},
		"requested_domains": DOMAINS,
		"generator_version": GENERATOR_VERSION,
		"content_manifest_hash": content_hash,
		"presentation": {"seed": 424242, "locale": "en-US"},
	}
	_request_json = JSON.stringify(request)
	var sync_result := _read_object(_generator_a.call("generate_bundle", _request_json), "sync_result_json")
	_expect(sync_result.get("schema_version") == LIFECYCLE_SCHEMA, "sync_schema")
	_expect(sync_result.get("status") == "completed", "sync_completed")
	var sync_bundle: Dictionary = sync_result.get("bundle", {})
	_assert_bundle_contract(sync_bundle, "sync")
	_sync_hash = str(sync_bundle.get("semantic_hash", ""))
	_expect(_sync_hash.length() > 0, "sync_semantic_hash")

	var accepted := _read_object(_generator_a.call("generate_bundle_async", _request_json), "async_accept_json")
	_expect(accepted.get("schema_version") == LIFECYCLE_SCHEMA, "async_schema")
	_expect(["accepted", "queued", "running"].has(accepted.get("status")), "async_accepted")
	_expect(accepted.get("events", []).has("admitted"), "async_admitted")
	_expect(accepted.get("events", []).has("queued"), "async_queued")
	_async_id = int(accepted.get("request_id", 0))
	_expect(_async_id > 0, "async_request_id")
	_phase = "poll"

func _process(_delta: float) -> bool:
	if _failed:
		return true
	_frames += 1
	if _frames > MAX_FRAMES:
		_fail("poll_timeout")
		return true
	if _phase != "poll":
		return false

	# Deliberately poll with the other object: the service identity is process-wide.
	var result := _read_object(_generator_b.call("poll", _async_id), "poll_json")
	var status := str(result.get("status", ""))
	if status != "completed":
		_expect(["accepted", "queued", "running"].has(status), "poll_state")
		return false
	var bundle: Dictionary = result.get("bundle", {})
	_assert_bundle_contract(bundle, "async")
	_expect(str(bundle.get("semantic_hash", "")) == _sync_hash, "semantic_hash_match")
	var consumed := _read_object(_generator_b.call("poll", _async_id), "consumed_json")
	_expect(consumed.get("status") == "failed", "consumed_status")
	var failure: Dictionary = consumed.get("failure", {})
	_expect(failure.get("code") == "result_consumed", "consumed_code")

	var legacy: Variant = _generator_a.call("generate", 12, {"archetype_id": "frigate"})
	if legacy is Dictionary and (legacy as Dictionary).has("error"):
		print("LIFECYCLE_SMOKE:LEGACY_ERROR:", JSON.stringify(legacy))
	_expect(legacy is Dictionary, "legacy_dictionary")
	if _failed:
		return true
	_expect(not (legacy as Dictionary).has("error"), "legacy_ship")
	if _failed:
		return true
	print("LIFECYCLE_SMOKE: PASS")
	quit(0)
	return true

func _read_object(raw: Variant, code: String) -> Dictionary:
	_expect(raw is String, code + "_string")
	var parsed: Variant = JSON.parse_string(raw as String)
	_expect(parsed is Dictionary, code + "_object")
	return parsed as Dictionary

func _assert_bundle_contract(bundle: Dictionary, prefix: String) -> void:
	_expect(bundle.get("schema_version") == "procgen-bundle-4", prefix + "_bundle_schema")
	_expect(bundle.get("version", {}).get("generator_version") == GENERATOR_VERSION, prefix + "_version_generator")
	_expect(bundle.get("version", {}).get("export_schemas") == EXPORT_SCHEMAS, prefix + "_version_schemas")
	var request: Dictionary = bundle.get("request", {})
	_expect(request.get("schema_version") == REQUEST_SCHEMA, prefix + "_request_schema")
	_expect(request.get("player_model", {}).get("schema_version") == "player-model-2", prefix + "_player_model_schema")
	var world_ir: Dictionary = bundle.get("world_ir", {})
	var site_ir: Dictionary = bundle.get("site_ir", {})
	var gameplay_ir: Dictionary = bundle.get("gameplay_ir", {})
	var presentation_ir: Dictionary = bundle.get("presentation_ir", {})
	var trace: Dictionary = bundle.get("trace", {})
	_expect(world_ir.get("schema_version") == "world-ir-2", prefix + "_world_schema")
	_expect(site_ir.get("schema_version") == "site-ir-2", prefix + "_site_schema")
	_expect(gameplay_ir.get("schema_version") == "gameplay-ir-2", prefix + "_gameplay_schema")
	_expect(presentation_ir.get("schema_version") == "presentation-ir-2", prefix + "_presentation_schema")
	_expect(trace.get("schema_version") == "generation-trace-3", prefix + "_trace_schema")
	_expect(trace.get("rng_channels") == RNG_CHANNELS, prefix + "_trace_channels")
	_expect(site_ir.has("mission_graph") and site_ir.has("navigation")
			and site_ir.has("functional_props") and site_ir.has("spatial_annotations"), prefix + "_site_overlay")

	var creature_blueprints: Array = gameplay_ir.get("creature_blueprints", [])
	var encounter: Dictionary = gameplay_ir.get("encounter", {})
	var items: Array = gameplay_ir.get("items", [])
	var drops: Array = gameplay_ir.get("drops", [])
	var decisions: Array = gameplay_ir.get("decisions", [])
	_expect(creature_blueprints.size() == 3, prefix + "_creature_count")
	_expect(_is_sorted_by_id(creature_blueprints), prefix + "_creature_order")
	var creature_ids := {}
	for blueprint in creature_blueprints:
		_expect(blueprint is Dictionary and str(blueprint.get("id", "")).length() > 0, prefix + "_creature_identity")
		creature_ids[blueprint.get("id")] = true
	for spawn in encounter.get("spawns", []):
		_expect(creature_ids.has(spawn.get("blueprint_id")), prefix + "_encounter_creature_ref")
	_expect(items.size() == drops.size(), prefix + "_item_drop_alignment")
	_expect(decisions.size() > 0, prefix + "_gameplay_decisions")
	_expect(_has_accepted_domain(decisions, "creature"), prefix + "_creature_decision")
	_expect(_has_accepted_domain(decisions, "item"), prefix + "_item_decision")
	var instructions: Array = presentation_ir.get("instructions", [])
	_expect(instructions.size() > 0, prefix + "_presentation_instructions")
	for instruction in instructions:
		_expect(instruction.get("asset_ids", []).size() > 0 and instruction.get("adapter_binding_ids", []).size() > 0, prefix + "_presentation_bindings")

func _is_sorted_by_id(values: Array) -> bool:
	for index in range(1, values.size()):
		if str(values[index - 1].get("id", "")) >= str(values[index].get("id", "")):
			return false
	return true

func _has_accepted_domain(decisions: Array, domain: String) -> bool:
	for decision in decisions:
		if decision.get("domain") == domain and decision.get("accepted") == true:
			return true
	return false

func _is_lower_hex(value: String, expected_length: int) -> bool:
	if value.length() != expected_length:
		return false
	for character in value:
		if not (character in "0123456789abcdef"):
			return false
	return true

func _expect(condition: bool, code: String) -> void:
	if not condition:
		_failed = true
		_fail(code)
	assert(condition, code)

func _fail(code: String) -> void:
	push_error("LIFECYCLE_SMOKE:%s" % code)
	quit(1)
