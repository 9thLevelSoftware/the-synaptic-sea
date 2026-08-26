extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")

func _init() -> void:
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null:
		print("PROCGEN ADAPTIVE TRACE BLOCKED adapter_missing=true"); quit(1); return
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	var runtime: Dictionary = JSON.parse_string(str(generator.generator_manifest()))
	var caps: Dictionary = JSON.parse_string(str(generator.capabilities()))
	if ValidatorScript.new().validate(build, generator) != ValidatorScript.OK:
		print("PROCGEN ADAPTIVE TRACE FAIL manifest"); quit(1); return
	var consumer: RefCounted = ConsumerScript.new()
	var request: Dictionary = consumer.build_request(42, 0, 1, runtime, "standard", "", "", 0, 0, [{"kind":"combat_mastery", "value_bp":5000}, {"kind":"objective_pace", "value_bp":5000}])
	var raw: String = str(generator.generate_bundle(JSON.stringify(request)))
	var baseline: Dictionary = consumer.consume(raw, request, build, runtime, caps)
	if baseline.is_empty():
		print("PROCGEN ADAPTIVE TRACE FAIL baseline=%s" % consumer.last_error); quit(1); return
	var trace: Array = baseline.trace.adaptive_decisions
	if trace.size() != 3:
		print("PROCGEN ADAPTIVE TRACE FAIL decision_count=%d" % trace.size()); quit(1); return
	var tampered: Dictionary = JSON.parse_string(raw)
	(tampered.bundle.trace.adaptive_decisions as Array)[0].proposal.score += 1
	if not consumer.consume(JSON.stringify(tampered), request, build, runtime, caps).is_empty():
		print("PROCGEN ADAPTIVE TRACE FAIL accepted_score_tamper"); quit(1); return
	var reordered: Dictionary = JSON.parse_string(raw)
	var decisions: Array = reordered.bundle.trace.adaptive_decisions
	var first: Variant = decisions[0]; decisions[0] = decisions[1]; decisions[1] = first
	if not consumer.consume(JSON.stringify(reordered), request, build, runtime, caps).is_empty():
		print("PROCGEN ADAPTIVE TRACE FAIL accepted_reorder"); quit(1); return
	var invalid_action: Dictionary = JSON.parse_string(raw)
	invalid_action.bundle.trace.adaptive_decisions[2].proposal.action = {"adjust_encounter":{"encounter_id":"forged", "pacing_delta_bp":9999}}
	if not consumer.consume(JSON.stringify(invalid_action), request, build, runtime, caps).is_empty():
		print("PROCGEN ADAPTIVE TRACE FAIL accepted_invalid_action"); quit(1); return
	print("PROCGEN ADAPTIVE TRACE PASS bundle=true decisions=3 deterministic_replay=true tamper_rejected=true reorder_rejected=true invalid_action_rejected=true")
	quit(0)
