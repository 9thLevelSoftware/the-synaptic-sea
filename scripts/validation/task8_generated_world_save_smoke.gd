extends SceneTree

const Site := preload("res://scripts/systems/generated_world_site_identity.gd")
const Delta := preload("res://scripts/systems/procgen_mutation_delta.gd")
const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Compatibility := preload("res://scripts/systems/generated_world_compatibility.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
const Prompt := preload("res://scripts/ui/generated_world_prompt_state.gd")

class Provider extends RefCounted:
	var calls := 0
	func regenerate_site(identity: RefCounted) -> Dictionary:
		calls += 1
		return {"site_id": identity.site_id, "x": identity.x, "y": identity.y, "seed": identity.derived_site_seed, "structural_generator_version": identity.structural_generator_version, "semantic_hash": identity.base_bundle_semantic_hash, "targets": ["door:d1"]}

class Applier extends RefCounted:
	var calls := 0
	func validate_mutation(_identity: RefCounted, _operation: Dictionary, _bundle: Variant) -> bool: return true
	func apply_mutation(_identity: RefCounted, _operation: Dictionary, _bundle: Variant) -> bool:
		calls += 1; return true

func _init() -> void:
	var identity := Site.new(); assert(identity.configure("site-a", 2, -3, 99, "structural-2", "semantic-a"))
	var delta := Delta.new(); assert(delta.configure("site-a", "semantic-a", [{"operation":"door_open", "target_kind":"door", "target_id":"d1", "payload":{}}]))
	var envelope := Envelope.new(); assert(envelope.configure(7, "platform-3", "content-a", {"world":"world-ir-2"}, [{"identity":identity.to_dict(), "mutation_delta":delta.to_dict()}]))
	var provider := Provider.new(); var applier := Applier.new()
	var compatibility := Compatibility.new(); compatibility.configure("platform-3", "content-a", {"world":"world-ir-2"}, provider, applier)
	var result = compatibility.evaluate(envelope.to_dict(), "user://preserved.save")
	assert(result.status == Result.COMPATIBLE and provider.calls == 1 and applier.calls == 1)
	var mismatch = compatibility.evaluate({"schema":"generated-world-save-1", "world_seed":7, "platform_generator_version":"platform-9", "content_manifest_hash":"content-a", "export_schema_map":{"world":"world-ir-2"}, "sites":[]}, "user://preserved.save")
	assert(mismatch.status == Result.NEW_WORLD_REQUIRED and mismatch.preserved_path == "user://preserved.save")
	var prompt: Variant = Prompt.from_result(mismatch); assert(prompt.can_start_new_world and prompt.can_go_back)
	print("PASS: task8 generated-world save envelope")
	quit()
