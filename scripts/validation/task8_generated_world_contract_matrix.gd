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
const OPS := ["door_lock", "door_open", "container_inventory", "entity_remove", "objective", "hazard", "system_state"]
const KINDS := ["door", "door", "container", "entity", "objective", "hazard", "system"]

class Provider extends RefCounted:
	var mode := "dictionary"
	var calls := 0
	func procgen_bundle_provider_version() -> String: return "procgen-bundle-provider-1"
	func regenerate_site(identity: RefCounted):
		calls += 1
		if mode == "null": return null
		if mode == "object": return BundleObject.new(identity)
		if mode == "object_missing": return RefCounted.new()
		if mode == "object_bad_identity": return BadBundleObject.new(identity, "identity")
		if mode == "object_bad_targets": return BadBundleObject.new(identity, "targets")
		var targets: Array = []
		for i in 7: targets.append({"target_kind":KINDS[i], "target_id":"%s-%s" % [identity.site_id, i]})
		if mode == "targets_unknown": targets[0] = {"target_kind":"unknown", "target_id":"x"}
		if mode == "targets_missing": targets.remove_at(0)
		if mode == "targets_duplicate": targets[1] = targets[0]
		if mode == "targets_wrong_type": targets[0] = "wrong"
		var site_id: Variant = identity.site_id; var x: Variant = identity.x; var y: Variant = identity.y; var seed: Variant = identity.derived_site_seed; var structural: Variant = identity.structural_generator_version; var semantic: Variant = identity.base_bundle_semantic_hash
		match mode:
			"site_id": site_id = "other"
			"x": x += 1
			"y": y += 1
			"site_seed": seed += 1
			"structural_generator_version": structural += 1
			"semantic_hash": semantic = HASH_A
		if mode == "wrong_variant": return 42
		var bundle := {"site_id":site_id, "x":x, "y":y, "site_seed":seed, "structural_generator_version":structural, "semantic_hash":semantic, "targets":targets}
		if mode == "dict_missing": bundle.erase("targets")
		if mode == "dict_extra": bundle.extra = true
		if mode == "dict_wrong_type": bundle.x = "wrong"
		return bundle

class BundleObject extends RefCounted:
	var identity: RefCounted
	func _init(value: RefCounted): identity = value
	func procgen_identity() -> Dictionary:
		return {"site_id":identity.site_id, "x":identity.x, "y":identity.y, "site_seed":identity.derived_site_seed, "structural_generator_version":identity.structural_generator_version, "semantic_hash":identity.base_bundle_semantic_hash}
	func mutation_targets() -> Array:
		var result: Array = []
		for i in 7: result.append({"target_kind":KINDS[i], "target_id":"%s-%s" % [identity.site_id, i]})
		return result

class BadBundleObject extends RefCounted:
	var identity: RefCounted
	var failure: String
	func _init(value: RefCounted, kind: String): identity = value; failure = kind
	func procgen_identity() -> Dictionary:
		if failure == "identity": return {"site_id":identity.site_id, "x":identity.x}
		return {"site_id":identity.site_id, "x":identity.x, "y":identity.y, "site_seed":identity.derived_site_seed, "structural_generator_version":identity.structural_generator_version, "semantic_hash":identity.base_bundle_semantic_hash}
	func mutation_targets() -> Array:
		return ["wrong"]

class Applier extends RefCounted:
	var validate_ok := true
	var batch_ok := true
	var validation_calls := 0
	var batch_calls := 0
	var applied := 0
	func procgen_atomic_batch_version() -> String: return "procgen-mutation-atomic-1"
	func validate_mutation(_identity: RefCounted, _operation: Dictionary, _bundle: Variant) -> bool: validation_calls += 1; return validate_ok
	func apply_batch_atomic(pending: Array) -> bool:
		batch_calls += 1
		if batch_ok: applied = pending.size()
		return batch_ok

var failures: Array[String] = []
var cases := 0
var finished := false

func _init() -> void:
	var site_a: RefCounted = _site("site-a", 2, -3, 99, 2, HASH_A)
	var site_b: RefCounted = _site("site-b", 4, 5, 100, 7, HASH_B)
	var delta_a: RefCounted = _delta(site_a, 4); var delta_b: RefCounted = _delta(site_b, 3)
	var envelope: RefCounted = _envelope(site_a, delta_a, site_b, delta_b)
	var provider := Provider.new(); var applier := Applier.new(); var compatibility := _compat(provider, applier)
	var success: Variant = compatibility.evaluate(envelope.to_dict(), "user://world.save")
	_expect(success.status == Result.COMPATIBLE and provider.calls == 2 and applier.validation_calls == 7 and applier.batch_calls == 1 and applier.applied == 7, "valid two-site seven-op atomic success")
	provider.mode = "object"; provider.calls = 0; applier.batch_calls = 0; applier.applied = 0
	var object_success: Variant = compatibility.evaluate(envelope.to_dict())
	_expect(object_success.status == Result.COMPATIBLE and provider.calls == 2 and applier.batch_calls == 1 and applier.applied == 7, "explicit object bundle success")
	for field in ["platform_generator_version", "content_manifest_hash"]:
		var changed: Dictionary = envelope.to_dict(); changed[field] = 999 if field == "platform_generator_version" else HASH_A
		var result: Variant = _compat(Provider.new(), Applier.new()).evaluate(changed, "user://preserved.save")
		_expect(result.status == Result.NEW_WORLD_REQUIRED and result.preserved_path == "user://preserved.save", "world mismatch " + field)
	for key in MAP.keys():
		var changed_map: Dictionary = envelope.to_dict(); changed_map.export_schema_map[key] = "changed"
		var result: Variant = _compat(Provider.new(), Applier.new()).evaluate(changed_map, "user://preserved.save")
		_expect(result.status == Result.NEW_WORLD_REQUIRED and result.preserved_path == "user://preserved.save", "schema mismatch " + key)
	for mismatch in ["site_id", "x", "y", "site_seed", "structural_generator_version", "semantic_hash"]:
		var p := Provider.new(); p.mode = mismatch; var a := Applier.new(); var result: Variant = _compat(p, a).evaluate(envelope.to_dict())
		_expect(result.status == Result.NEW_WORLD_REQUIRED and a.batch_calls == 0, "bundle identity mismatch " + mismatch)
	for mode in ["null", "wrong_variant", "dict_missing", "dict_extra", "dict_wrong_type", "object_missing", "object_bad_identity", "object_bad_targets"]:
		var p := Provider.new(); p.mode = mode; var a := Applier.new(); var result: Variant = _compat(p, a).evaluate(envelope.to_dict())
		_expect(result.status == Result.NEW_WORLD_REQUIRED and a.batch_calls == 0, "provider malformed " + mode)
	_expect(_compat(null, Applier.new()).evaluate(envelope.to_dict()).status == Result.IO_FAILURE, "provider null")
	_expect(_compat(Provider.new(), null).evaluate(envelope.to_dict()).status == Result.IO_FAILURE, "applier null")
	for target_mode in ["targets_unknown", "targets_missing", "targets_duplicate", "targets_wrong_type"]:
		var p := Provider.new(); p.mode = target_mode; var a := Applier.new(); var result: Variant = _compat(p, a).evaluate(envelope.to_dict())
		_expect(result.status == Result.NEW_WORLD_REQUIRED and a.batch_calls == 0, "target malformed " + target_mode)
	var rejected := _compat(Provider.new(), Applier.new()); var reject_a: Applier = rejected.applier; reject_a.validate_ok = false; var reject_result: Variant = rejected.evaluate(envelope.to_dict())
	_expect(reject_result.status == Result.NEW_WORLD_REQUIRED and reject_a.batch_calls == 0 and reject_a.applied == 0, "validate rejection zero batch")
	var failed_apply := _compat(Provider.new(), Applier.new()); var fail_a: Applier = failed_apply.applier; fail_a.batch_ok = false; var fail_result: Variant = failed_apply.evaluate(envelope.to_dict())
	_expect(fail_result.status == Result.IO_FAILURE and fail_a.batch_calls == 1 and fail_a.applied == 0, "false apply sentinel")

	_expect(_site("a", -2147483648, 2147483647, Site.MAX_SEED, Site.MAX_SEED, HASH_A) != null, "site int32/max seed boundaries")
	_expect(_site("a", 1.0, 2.0, 3.0, 4.0, HASH_A) != null, "site integral floats")
	for value in [true, "1", 1.5, INF, NAN]: _expect(_site("a", value, 1, 1, 1, HASH_A) == null, "site invalid x numeric")
	for value in [true, "1", -1, Site.MAX_SEED + 1]: _expect(_site("a", 1, 1, value, 1, HASH_A) == null, "site invalid seed numeric")
	for value in ["A".repeat(64), "g".repeat(64), "a".repeat(63), "a".repeat(65)]: _expect(_site("a", 1, 1, 1, 1, value) == null, "site invalid hash")
	for value in ["", "-bad", "A", "has space", "a/", "a".repeat(129)]: _expect(_site(value, 1, 1, 1, 1, HASH_A) == null, "site invalid id")
	var sd: Dictionary = site_a.to_dict()
	for key in sd.keys(): var m: Dictionary = sd.duplicate(); m.erase(key); _expect(Site.from_dict(m) == null, "site missing " + key)
	var se: Dictionary = sd.duplicate(); se.extra = true; _expect(Site.from_dict(se) == null, "site extra")
	_expect(Site.from_dict(JSON.parse_string(JSON.stringify(sd))) != null, "site JSON roundtrip")
	var empty_envelope: RefCounted = Envelope.new(); var empty_configured: bool = empty_envelope.configure(1.0, 1.0, HASH_A, MAP, [])
	_expect(empty_configured and Envelope.from_dict(JSON.parse_string(JSON.stringify(empty_envelope.to_dict()))) != null, "envelope integral floats/JSON")
	for value in [true, "1", 1.2, INF, NAN, -1, Envelope.MAX_SEED + 1]: _expect(Envelope.new().configure(value, 1, HASH_A, MAP, []) == false, "envelope invalid seed")
	var ed: Dictionary = envelope.to_dict()
	for key in ed.keys(): var m: Dictionary = ed.duplicate(true); m.erase(key); _expect(Envelope.from_dict(m) == null, "envelope missing " + key)
	var ee: Dictionary = ed.duplicate(true); ee.extra = true; _expect(Envelope.from_dict(ee) == null, "envelope extra")
	var bm := MAP.duplicate(); bm.erase("world_ir"); _expect(Envelope.new().configure(1, 1, HASH_A, bm, []) == false, "schema map missing")
	bm = MAP.duplicate(); bm.extra = "x"; _expect(Envelope.new().configure(1, 1, HASH_A, bm, []) == false, "schema map extra")
	bm = MAP.duplicate(); bm.world_ir = 1; _expect(Envelope.new().configure(1, 1, HASH_A, bm, []) == false, "schema map wrong value")
	var many: Array = []
	for i in 257:
		many.append({"identity":site_a.to_dict(), "mutation_delta":delta_a.to_dict()})
	_expect(Envelope.new().configure(1, 1, HASH_A, MAP, many) == false, "over 256 sites")
	var dup: Array = [{"identity":site_a.to_dict(), "mutation_delta":delta_a.to_dict()}, {"identity":site_a.to_dict(), "mutation_delta":delta_a.to_dict()}]; _expect(Envelope.new().configure(1, 1, HASH_A, MAP, dup) == false, "duplicate sites")
	var wrong: Dictionary = delta_a.to_dict(); wrong.base_site_id = "site-b"; _expect(Envelope.new().configure(1, 1, HASH_A, MAP, [{"identity":site_a.to_dict(), "mutation_delta":wrong}]) == false, "mismatched base site")
	wrong = delta_a.to_dict(); wrong.base_semantic_hash = HASH_B; _expect(Envelope.new().configure(1, 1, HASH_A, MAP, [{"identity":site_a.to_dict(), "mutation_delta":wrong}]) == false, "mismatched base hash")

	for value in [true, 1.2, -1, ""]: _expect(Delta.new().configure(value, HASH_A, []) == false, "delta invalid id")
	for value in [true, "x", "A".repeat(64), "g".repeat(64)]: _expect(Delta.new().configure("site-a", value, []) == false, "delta invalid hash")
	for op in _valid_operations(): _expect(Delta.new().configure("site-a", HASH_A, [op]), "valid op " + op.operation)
	for bad in _delta_bad_operations(): _expect(Delta.new().configure("site-a", HASH_A, [bad]) == false, "delta bad " + str(bad.operation))
	for i in 5:
		var bad: Dictionary = _op("door_open", "door", "x", {"open":true})
		var malformed: Dictionary = bad.duplicate(true)
		match i:
			0: malformed.operation = true
			1: malformed.target_kind = 1
			2: malformed.target_id = 1
			3: malformed.payload = "wrong"
			4: malformed.payload = null
		_expect(Delta.new().configure("site-a", HASH_A, [malformed]) == false, "delta field wrong type")
	var over_ops: Array = []
	for i in 129:
		over_ops.append(_op("door_open", "door", "d-%d" % i, {"open":true}))
	_expect(Delta.new().configure("site-a", HASH_A, over_ops) == false, "over 128 operations")
	var dups: Array = [_op("door_open", "door", "d", {"open":true}), _op("door_open", "door", "d", {"open":false})]; _expect(Delta.new().configure("site-a", HASH_A, dups) == false, "duplicate operation")
	var item_base := {"operation":"container_inventory", "target_kind":"container", "target_id":"c", "payload":{"items":[]}}
	for bad_item in [{"item_id":"", "quantity":1}, {"item_id":"x".repeat(129), "quantity":1}, {"item_id":"x", "quantity":true}, {"item_id":"x", "quantity":"1"}, {"item_id":"x", "quantity":1.0}, {"item_id":"x", "quantity":-1}, {"item_id":"x", "quantity":65536}]:
		var operation: Dictionary = item_base.duplicate(true); operation.payload.items = [bad_item]; _expect(Delta.new().configure("site-a", HASH_A, [operation]) == false, "container item invalid")
	var items: Array = []
	for i in 65:
		items.append({"item_id":"i%d" % i, "quantity":1})
	var item_operation: Dictionary = item_base.duplicate(true); item_operation.payload.items = items; _expect(Delta.new().configure("site-a", HASH_A, [item_operation]) == false, "container over 64")
	var duplicate_item: Dictionary = item_base.duplicate(true); duplicate_item.payload.items = [{"item_id":"x", "quantity":1}, {"item_id":"x", "quantity":2}]; _expect(Delta.new().configure("site-a", HASH_A, [duplicate_item]) == false, "duplicate item")
	var big := _op("door_open", "door", "big", {"open":true}); big.payload.pad = "x".repeat(4100); _expect(Delta.new().configure("site-a", HASH_A, [big]) == false, "payload byte limit")
	var dd: Dictionary = delta_a.to_dict(); for key in dd.keys(): var m: Dictionary = dd.duplicate(true); m.erase(key); _expect(Delta.from_dict(m) == null, "delta missing " + key)
	var de: Dictionary = dd.duplicate(true); de.extra = true; _expect(Delta.from_dict(de) == null, "delta extra")
	var targets: Array = []
	for i in 7:
		targets.append({"target_kind":KINDS[i], "target_id":"site-a-%s" % i})
	_expect(delta_a.validate_targets(targets), "seven targets")
	for target in [{"target_kind":"unknown", "target_id":"x"}, {"target_kind":"door"}, {"target_kind":"door", "target_id":"x", "extra":1}, {"target_kind":"door", "target_id":"A"}]: _expect(delta_a.validate_targets([target]) == false, "target malformed")
	var target_dup: Array = targets.duplicate(true); target_dup.append(targets[0]); _expect(delta_a.validate_targets(target_dup) == false, "target duplicate")

	for status in [Result.COMPATIBLE, Result.NEW_WORLD_REQUIRED, Result.CORRUPT, Result.IO_FAILURE]:
		var load: Variant = Result.make(status, "reason", "user://preserved"); var prompt: Variant = Prompt.from_result(load); _expect(prompt.status == status and prompt.preserved_path == "user://preserved", "prompt status " + status)
	_expect(Prompt.from_result(Result.make(Result.NEW_WORLD_REQUIRED, "reason", "p")).available_actions == ["start_new_world", "back"], "prompt new-world actions")
	_expect(Prompt.from_result(Result.make(Result.CORRUPT, "reason", "p")).available_actions == ["back"], "prompt corrupt actions")
	_expect(Prompt.from_result(Result.make(Result.IO_FAILURE, "reason", "p")).available_actions == ["back"], "prompt io actions")
	_expect(Prompt.from_result(Result.make(Result.COMPATIBLE, "reason")).available_actions.is_empty(), "prompt compatible actions")
	for reason in ["", "r".repeat(97)]: _expect(Result.make(Result.COMPATIBLE, reason).reason_code == "malformed", "result reason bound")
	_expect(Result.make("unknown", "reason").status == Result.CORRUPT, "result unknown status")
	var summary_result: Variant = Result.make(Result.NEW_WORLD_REQUIRED, "platform_generator_mismatch", "p", {"world_seed":7, "platform_generator_version":3, "content_manifest_hash":HASH_A, "export_schema_map":MAP})
	_expect(summary_result.identity_summary.world_seed == 7, "result identity summary preserved")
	_expect(Result.make(Result.COMPATIBLE, "validated", "p", {"nested":true}).identity_summary.is_empty(), "result summary type bound")
	for path in ["", "user://x", "p".repeat(1024)]: _expect(Result.make(Result.COMPATIBLE, "reason", path).preserved_path == path, "result path accepted")
	_expect(Result.make(Result.COMPATIBLE, "reason", "p".repeat(1025)).preserved_path == "", "result path bound")
	for source in ["generated_world_site_identity.gd", "procgen_mutation_delta.gd", "generated_world_save_envelope.gd", "generated_world_compatibility.gd", "procgen_load_result.gd", "generated_world_prompt_state.gd"]:
		var source_text := FileAccess.get_file_as_string("res://scripts/ui/" + source) if source == "generated_world_prompt_state.gd" else FileAccess.get_file_as_string("res://scripts/systems/" + source)
		for forbidden in ["FileAccess.", "DirAccess.", ".remove(", ".rename(", ".delete(", ".migrate("]: _expect(not source_text.to_lower().contains(forbidden.to_lower()), "pure source no " + forbidden)
	_finish()

func _site(id: Variant, x: Variant, y: Variant, seed: Variant, structural: Variant, semantic: Variant) -> Variant:
	var result := Site.new(); return result if result.configure(id, x, y, seed, structural, semantic) else null

func _delta(site: RefCounted, count: int) -> RefCounted:
	var values: Array = []; for i in count: values.append(_op(OPS[i], KINDS[i], "%s-%d" % [site.site_id, i], _payload(OPS[i])))
	var result := Delta.new(); result.configure(site.site_id, site.base_bundle_semantic_hash, values); return result

func _payload(operation: String) -> Dictionary:
	match operation:
		"door_lock": return {"locked":true}
		"door_open": return {"open":true}
		"container_inventory": return {"items":[{"item_id":"med-kit", "quantity":2}]}
		"entity_remove": return {"removed":true}
		"objective": return {"completed":true}
		"hazard": return {"active":true}
		_: return {"state":"offline"}

func _op(operation: String, kind: String, id: String, payload: Dictionary) -> Dictionary:
	return {"operation":operation, "target_kind":kind, "target_id":id, "payload":payload}

func _valid_operations() -> Array:
	var result: Array = []
	for i in 7:
		result.append(_op(OPS[i], KINDS[i], "target-%d" % i, _payload(OPS[i])))
	return result

func _delta_bad_operations() -> Array:
	return [_op("unknown", "door", "x", {"open":true}), _op("door_open", "container", "x", {"open":true}), _op("door_open", "door", "", {"open":true}), _op("door_open", "door", "x", {}), _op("door_open", "door", "x", {"open":"true"}), _op("door_open", "door", "x", {"open":true, "extra":1}), _op("entity_remove", "entity", "x", {"removed":false}), _op("system_state", "system", "x", {"state":"Bad"})]

func _envelope(a: RefCounted, da: RefCounted, b: RefCounted, db: RefCounted) -> RefCounted:
	var result := Envelope.new(); result.configure(7, 3, HASH_B, MAP, [{"identity":a.to_dict(), "mutation_delta":da.to_dict()}, {"identity":b.to_dict(), "mutation_delta":db.to_dict()}]); return result

func _compat(provider: Object, applier: Object) -> Compatibility:
	var result := Compatibility.new(); result.configure(3, HASH_B, MAP, provider, applier); return result

func _expect(condition: bool, label: String) -> void:
	cases += 1
	if not condition: failures.append("%d:%s" % [cases, label])

func _finish() -> void:
	if finished: return
	finished = true
	if failures.is_empty() and cases >= 70: print("TASK8_GENERATED_WORLD_CONTRACT_PASS cases=%d" % cases); quit(0)
	else: print("TASK8_GENERATED_WORLD_CONTRACT_FAIL cases=%d failures=%s" % [cases, ",".join(failures)]); quit(1)
