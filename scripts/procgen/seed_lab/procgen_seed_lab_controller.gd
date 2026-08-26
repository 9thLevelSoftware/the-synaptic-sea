extends RefCounted
class_name ProcgenSeedLabController

const ModelScript := preload("res://scripts/procgen/seed_lab/procgen_seed_lab_model.gd")

var model: RefCounted
var generator: Object
var consumer: RefCounted
var build_manifest: Dictionary
var runtime_manifest: Dictionary
var capabilities: Dictionary
var last_error: String = ""
var generation_count: int = 0
var last_result: Dictionary = {}

func configure(injected_generator: Object, injected_consumer: RefCounted, injected_build: Dictionary, injected_runtime: Dictionary, injected_caps: Dictionary) -> void:
	generator = injected_generator
	consumer = injected_consumer
	build_manifest = injected_build.duplicate(true)
	runtime_manifest = injected_runtime.duplicate(true)
	capabilities = injected_caps.duplicate(true)
	model = ModelScript.new()

func generate(slot: int, request: Dictionary) -> bool:
	last_error = ""
	if model == null or generator == null or consumer == null:
		last_error = "not_configured"
		return false
	if not generator.has_method("generate_bundle"):
		last_error = "generator_missing"
		return false
	generation_count += 1
	var lifecycle: String = str(generator.generate_bundle(JSON.stringify(request)))
	var bundle: Dictionary = consumer.consume(lifecycle, request, build_manifest, runtime_manifest, capabilities)
	if bundle.is_empty():
		var parsed: Variant = JSON.parse_string(lifecycle)
		last_error = str(consumer.get("last_error"))
		if last_error.is_empty(): last_error = "generation_failed"
		var failure: Dictionary = {}
		if parsed is Dictionary and parsed.has("failure") and parsed.failure is Dictionary:
			failure = parsed.failure
		else:
			failure = {"failure_code": last_error}
		last_result = {"success": false, "failure": failure}
		model.load_lifecycle(slot, parsed if parsed is Dictionary else failure, request)
		return false
	last_result = {"success": true, "bundle": bundle}
	return model.load_bundle(slot, bundle, request)

func regenerate(slot: int, request: Dictionary, domains: Array[String]) -> bool:
	var selected: Dictionary = model.selective_request(request, domains)
	return generate(slot, selected)

func get_model() -> RefCounted:
	return model

func inspect(slot: int) -> Dictionary:
	return model.inspect_trace(slot) if model != null else {}
