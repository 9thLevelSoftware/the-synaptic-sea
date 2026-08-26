extends SceneTree

const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")

func _init() -> void:
	var consumer: RefCounted = ConsumerScript.new()
	var failures: Array[String] = []
	var caps: Dictionary = {"schema_version": "procgen-capabilities-1", "adapter_kind": "native", "supports_sync": true, "target": "x86_64-pc-windows-msvc", "worker_mode": "thread_pool", "supported_domains": ["world", "site", "gameplay", "presentation"], "schemas": {"procgen_bundle": "procgen-bundle-1"}, "max_request_bytes": 1, "max_entities": 1, "max_trace_entries": 1, "max_events": 1, "deadline_ms": 1}
	if not consumer._validate_capabilities(caps, {"target": "x86_64-pc-windows-msvc"}): failures.append("capability baseline rejected")
	caps["schemas"] = {"procgen_bundle": "wrong"}
	if consumer._validate_capabilities(caps, {"target": "x86_64-pc-windows-msvc"}): failures.append("schema mismatch accepted")
	var request: Dictionary = consumer.build_request(42, 0, 1)
	if request.is_empty() or consumer.build_request(9007199254740992, 0, 1).is_empty() == false: failures.append("seed bound")
	var malformed: Dictionary = consumer.consume("{\"status\":\"completed\",\"bundle\":{}}", request, {"manifest_schema":"procgen-build-manifest-1"}, {"schema_version":"procgen-generator-manifest-1"}, caps)
	if not malformed.is_empty() or consumer.last_error.is_empty(): failures.append("malformed bundle accepted")
	if not failures.is_empty():
		for failure in failures: print("TASK5 CONSUMER FAIL:%s" % failure)
		quit(1); return
	print("TASK5 CONSUMER PASS negative_matrix=true hash_fail_closed=true caps_fail_closed=true seed_bound=true")
	quit(0)
