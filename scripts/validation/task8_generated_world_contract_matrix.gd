extends SceneTree

const Site := preload("res://scripts/systems/generated_world_site_identity.gd")
const Delta := preload("res://scripts/systems/procgen_mutation_delta.gd")
const Envelope := preload("res://scripts/systems/generated_world_save_envelope.gd")
const Compatibility := preload("res://scripts/systems/generated_world_compatibility.gd")
const Result := preload("res://scripts/systems/procgen_load_result.gd")
const Prompt := preload("res://scripts/ui/generated_world_prompt_state.gd")
const HASH_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const HASH_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const MAP := {"procgen_request":"a", "procgen_bundle":"b", "world_ir":"c", "site_ir":"d", "gameplay_ir":"e", "presentation_ir":"f", "generation_trace":"g", "adaptive_proposal":"h"}

class BundleProvider extends RefCounted:
	var object_mode := false
	var calls := 0
	func regenerate_site(identity: RefCounted):
		calls += 1
		if object_mode: return BundleObject.new(identity)
		return {"site_id":identity.site_id, "x":identity.x, "y":identity.y, "site_seed":identity.derived_site_seed, "structural_generator_version":identity.structural_generator_version, "semantic_hash":identity.base_bundle_semantic_hash, "targets": [{"target_kind":"door","target_id":"d1"}, {"target_kind":"container","target_id":"c1"}, {"target_kind":"entity","target_id":"e1"}, {"target_kind":"objective","target_id":"o1"}, {"target_kind":"hazard","target_id":"h1"}, {"target_kind":"system","target_id":"s1"}]}

class BundleObject extends RefCounted:
	var identity: RefCounted
	func _init(value: RefCounted): identity = value
	func procgen_identity() -> Dictionary:
		return {"site_id":identity.site_id, "x":identity.x, "y":identity.y, "site_seed":identity.derived_site_seed, "structural_generator_version":identity.structural_generator_version, "semantic_hash":identity.base_bundle_semantic_hash}
	func mutation_targets() -> Array:
		return [{"target_kind":"door","target_id":"d1"}]

class Applier extends RefCounted:
	var validate_ok := true
	var batch_ok := true
	var validation_calls := 0
	var batch_calls := 0
	func validate_mutation(_identity: RefCounted, _operation: Dictionary, _bundle: Variant) -> bool: validation_calls += 1; return validate_ok
	func apply_batch(_pending: Array) -> bool: batch_calls += 1; return batch_ok

var failures: Array[String] = []
var cases := 0
var finished := false

func _init() -> void:
	var identity_a := Site.new(); var identity_b := Site.new()
	_expect(identity_a.configure("site-a", 2, -3, 99, 2, HASH_A), "site valid", 1)
	_expect(identity_b.configure("site-b", 4, 5, 100, 7, HASH_B), "site version valid", 2)
	_expect(Site.from_dict(JSON.parse_string(JSON.stringify(identity_a.to_dict()))) != null, "site JSON float roundtrip", 3)
	var ops := [{"operation":"door_lock","target_kind":"door","target_id":"d1","payload":{"locked":true}}, {"operation":"door_open","target_kind":"door","target_id":"d2","payload":{"open":true}}, {"operation":"container_inventory","target_kind":"container","target_id":"c1","payload":{"items":[{"item_id":"med-kit","quantity":2}]}}, {"operation":"entity_remove","target_kind":"entity","target_id":"e1","payload":{"removed":true}}, {"operation":"objective","target_kind":"objective","target_id":"o1","payload":{"completed":true}}, {"operation":"hazard","target_kind":"hazard","target_id":"h1","payload":{"active":true}}, {"operation":"system_state","target_kind":"system","target_id":"s1","payload":{"state":"offline"}}]
	var delta := Delta.new(); _expect(delta.configure("site-a", HASH_A, ops), "all seven ops", 4)
	var delta_json: Variant = Delta.from_dict(JSON.parse_string(JSON.stringify({"schema_version":Delta.SCHEMA,"base_site_id":"site-a","base_semantic_hash":HASH_A,"operations":[]})))
	_expect(delta_json != null, "delta JSON", 5)
	_expect(Delta.new().configure("site-a", HASH_A, [{"operation":"door_open","target_kind":"door","target_id":"d1","payload":{"open":true}}, {"operation":"door_open","target_kind":"door","target_id":"d1","payload":{"open":false}}]) == false, "duplicate operation", 6)
	_expect(Delta.new().configure("site-a", HASH_A, [{"operation":"door_open","target_kind":"door","target_id":"d1","payload":{"open":true,"extra":false}}]) == false, "unknown payload", 7)
	_expect(Delta.new().configure("site-a", HASH_A, [{"operation":"container_inventory","target_kind":"container","target_id":"c1","payload":{"items":[{"item_id":"x","quantity":1},{"item_id":"x","quantity":2}]}}]) == false, "duplicate item", 8)
	var save_delta := Delta.new(); _expect(save_delta.configure("site-a", HASH_A, [{"operation":"door_open","target_kind":"door","target_id":"d1","payload":{"open":true}}]), "save delta", 9)
	var envelope := Envelope.new(); _expect(envelope.configure(7.0, 3.0, HASH_B, MAP, [{"identity":identity_a.to_dict(),"mutation_delta":save_delta.to_dict()}]), "envelope integral floats", 10)
	var restored: Variant = Envelope.from_dict(JSON.parse_string(JSON.stringify(envelope.to_dict())))
	_expect(restored != null, "envelope JSON", 11)
	if restored == null:
		_finish()
		return
	var provider := BundleProvider.new(); var applier := Applier.new(); var compatibility := Compatibility.new(); compatibility.configure(3, HASH_B, MAP, provider, applier)
	var compatible: Variant = compatibility.evaluate(restored.to_dict(), "user://save")
	_expect(compatible.status == Result.COMPATIBLE and applier.batch_calls == 1, "compatible batch", 11)
	for field in ["platform_generator_version", "content_manifest_hash", "export_schema_map"]:
		var changed: Dictionary = restored.to_dict(); changed[field] = 9 if field == "platform_generator_version" else (HASH_A if field == "content_manifest_hash" else MAP.duplicate(true)); if field == "export_schema_map": changed.export_schema_map.procgen_request = "z"
		_expect(compatibility.evaluate(changed, "user://save").status == Result.NEW_WORLD_REQUIRED, "mismatch " + field, 12)
	var malformed: Dictionary = restored.to_dict(); malformed.sites = [{"identity":identity_a.to_dict()}]; _expect(compatibility.evaluate(malformed).status == Result.CORRUPT, "missing site field", 15)
	provider.object_mode = true; var object_result: Variant = compatibility.evaluate(envelope.to_dict()); _expect(object_result.status == Result.COMPATIBLE, "object bundle", 16)
	provider.object_mode = false; applier.validate_ok = false; applier.batch_calls = 0; _expect(compatibility.evaluate(envelope.to_dict()).status == Result.NEW_WORLD_REQUIRED and applier.batch_calls == 0, "validator zero batch", 17)
	applier.validate_ok = true; applier.batch_ok = false; applier.batch_calls = 0; _expect(compatibility.evaluate(envelope.to_dict()).status == Result.IO_FAILURE and applier.batch_calls == 1, "atomic false sentinel", 18)
	var new_prompt: Variant = Prompt.from_result(Result.make(Result.NEW_WORLD_REQUIRED, "platform_generator_mismatch", "user://save")); _expect(new_prompt.available_actions == ["start_new_world", "back"], "new-world actions", 19)
	var corrupt_prompt: Variant = Prompt.from_result(Result.make(Result.CORRUPT, "malformed", "user://save")); _expect(corrupt_prompt.available_actions == ["back"], "corrupt actions", 20)
	var compatible_prompt: Variant = Prompt.from_result(Result.make(Result.COMPATIBLE, "validated", "")); _expect(compatible_prompt.available_actions.is_empty(), "compatible actions", 21)
	_finish()

func _expect(condition: bool, label: String, number: int) -> void:
	cases = max(cases, number)
	if not condition: failures.append(label)

func _finish() -> void:
	if finished: return
	finished = true
	if failures.is_empty(): print("TASK8_GENERATED_WORLD_CONTRACT_PASS cases=%d" % cases); quit(0); return
	print("TASK8_GENERATED_WORLD_CONTRACT_FAIL cases=%d failures=%s" % [cases, ",".join(failures)]); quit(1)
