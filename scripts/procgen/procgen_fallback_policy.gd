extends RefCounted
class_name ProcgenFallbackPolicy

var provider: Callable = Callable()
var selected_id: String = ""
var last_error: String = ""
var last_outcome: String = "unconfigured"

func configure(fallback_id: String, fallback_provider: Callable) -> void:
	selected_id = fallback_id
	provider = fallback_provider
	last_error = ""
	last_outcome = "configured" if not fallback_id.is_empty() and fallback_provider.is_valid() else "unconfigured"

func resolve(request: Dictionary, consumer: RefCounted) -> Dictionary:
	last_error = ""
	if selected_id.is_empty() or not provider.is_valid():
		last_outcome = "unconfigured"
		last_error = "fallback_unconfigured"
		return {}
	var value: Variant = provider.call(request.duplicate(true))
	if not value is Dictionary:
		last_outcome = "invalid"
		last_error = "fallback_invalid"
		return {}
	var context: Dictionary = value
	if not _has_exact_keys(context, ["lifecycle", "build_manifest", "runtime_manifest", "capabilities"]) \
			or not context.get("lifecycle", null) is String:
		last_outcome = "invalid"
		last_error = "fallback_invalid"
		return {}
	var parsed: Dictionary = consumer.consume(context.lifecycle, request, context.build_manifest, context.runtime_manifest, context.capabilities)
	if parsed.is_empty():
		last_outcome = "invalid"
		last_error = "fallback_validation_%s" % str(consumer.last_error)
		return {}
	if str((parsed.get("trace", {}) as Dictionary).get("fallback", "")) != selected_id:
		last_outcome = "invalid"
		last_error = "fallback_identity"
		return {}
	last_outcome = "selected"
	return parsed

func _has_exact_keys(value: Dictionary, expected: Array[String]) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true
