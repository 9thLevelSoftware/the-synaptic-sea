extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")

func _init() -> void:
	var generator: Object = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null:
		print("TASK5 LIVE CONSUMER BLOCKED adapter_missing=true"); quit(1); return
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	var runtime: Dictionary = JSON.parse_string(str(generator.generator_manifest()))
	var caps: Dictionary = JSON.parse_string(str(generator.capabilities()))
	var verdict: String = ValidatorScript.new().validate(build, generator)
	if verdict != ValidatorScript.OK:
		print("TASK5 LIVE CONSUMER FAIL build_manifest=%s" % verdict); quit(1); return
	var consumer: RefCounted = ConsumerScript.new()
	var request: Dictionary = consumer.build_request(42, 0, 1, runtime, "standard", "", "", 0, 0, [{"kind":"combat_mastery", "value_bp":5000}, {"kind":"objective_pace", "value_bp":5000}])
	var lifecycle: String = str(generator.generate_bundle(JSON.stringify(request)))
	var bundle: Dictionary = consumer.consume(lifecycle, request, build, runtime, caps)
	if bundle.is_empty():
		var returned_bundle: Dictionary = (JSON.parse_string(lifecycle) as Dictionary).get("bundle", {})
		var returned: Variant = returned_bundle.get("request", {})
		var returned_site: Dictionary = returned_bundle.get("site_ir", {})
		var returned_ship: Dictionary = returned_site.get("ship", {})
		print("TASK5 LIVE CONSUMER FAIL valid=%s request=%s returned=%s props=%s entry=%s portals=%s" % [consumer.last_error, JSON.stringify(request), JSON.stringify(returned), JSON.stringify(returned_site.get("functional_props", [])), str(returned_ship.get("entry_room", null)), JSON.stringify((returned_ship.get("topology", {}) as Dictionary).get("portals", []))]); quit(1); return
	var tampered: Dictionary = JSON.parse_string(lifecycle)
	(tampered["bundle"] as Dictionary)["semantic_hash"] = "0".repeat(64)
	var rejected: Dictionary = consumer.consume(JSON.stringify(tampered), request, build, runtime, caps)
	if not rejected.is_empty() or consumer.last_error != "semantic_hash":
		print("TASK5 LIVE CONSUMER FAIL hash=%s" % consumer.last_error); quit(1); return
	print("TASK5 LIVE CONSUMER PASS valid_bundle=true semantic_hash_negative=true manifest=true caps=true")
	quit(0)
