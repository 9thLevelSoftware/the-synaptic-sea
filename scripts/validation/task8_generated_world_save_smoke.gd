extends SceneTree

const Site := preload("res://scripts/systems/generated_world_site_identity.gd")
const Delta := preload("res://scripts/systems/procgen_mutation_delta.gd")
const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Compatibility := preload("res://scripts/systems/generated_world_compatibility.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
const Prompt := preload("res://scripts/ui/generated_world_prompt_state.gd")
const MAP := {"procgen_request":"a","procgen_bundle":"b","world_ir":"c","site_ir":"d","gameplay_ir":"e","presentation_ir":"f","generation_trace":"g","adaptive_proposal":"h"}

class Provider extends RefCounted:
	var calls := 0
	func procgen_bundle_provider_version() -> String: return "procgen-bundle-provider-1"
	func regenerate_site(identity: RefCounted) -> Dictionary:
		calls += 1
		return {"site_id": identity.site_id, "x": identity.x, "y": identity.y, "site_seed": identity.derived_site_seed, "structural_generator_version": identity.structural_generator_version, "semantic_hash": identity.base_bundle_semantic_hash, "targets": [{"target_kind":"door", "target_id":"d1"}]}

class Applier extends RefCounted:
	var calls := 0
	func procgen_atomic_batch_version() -> String: return "procgen-mutation-atomic-1"
	func validate_mutation(_identity: RefCounted, _operation: Dictionary, _bundle: Variant) -> bool: return true
	func apply_batch_atomic(_pending: Array) -> bool: calls += 1; return true

var finished := false

func _init() -> void:
	var failures: Array[String] = []
	var identity := Site.new(); _expect(identity.configure("site-a", 2, -3, 99, 2, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), "identity", failures)
	var delta := Delta.new(); _expect(delta.configure("site-a", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", [{"operation":"door_open", "target_kind":"door", "target_id":"d1", "payload":{"open":true}}]), "delta", failures)
	var envelope := Envelope.new(); _expect(envelope.configure(7, 3, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", MAP, [{"identity":identity.to_dict(), "mutation_delta":delta.to_dict()}]), "envelope", failures)
	var provider := Provider.new(); var applier := Applier.new()
	var compatibility := Compatibility.new(); compatibility.configure(3, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", MAP, provider, applier)
	var result = compatibility.evaluate(envelope.to_dict(), "user://preserved.save")
	_expect(result.status == Result.COMPATIBLE and provider.calls == 1 and applier.calls == 1, "compatible", failures)
	var mismatch = compatibility.evaluate({"schema_version":"generated-world-save-1", "world_seed":7, "platform_generator_version":9, "content_manifest_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "export_schema_map":MAP, "sites":[]}, "user://preserved.save")
	_expect(mismatch.status == Result.NEW_WORLD_REQUIRED and mismatch.preserved_path == "user://preserved.save", "mismatch", failures)
	var prompt: Variant = Prompt.from_result(mismatch); _expect(prompt.available_actions == ["start_new_world", "back"], "prompt", failures)
	_finish(failures, 5)

func _expect(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition: failures.append(label)

func _finish(failures: Array[String], cases: int) -> void:
	if finished: return
	finished = true
	if failures.is_empty(): print("TASK8_GENERATED_WORLD_SAVE_PASS cases=%d" % cases); quit(0); return
	print("TASK8_GENERATED_WORLD_SAVE_FAIL cases=%d failures=%s" % [cases, ",".join(failures)]); quit(1)
