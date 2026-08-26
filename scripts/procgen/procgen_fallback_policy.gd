extends RefCounted
class_name ProcgenFallbackPolicy

var provider: Callable = Callable()
var selected_id: String = ""
var last_error: String = ""
var last_outcome: String = "unconfigured"

func configure(fallback_id: String, fallback_provider: Callable) -> void:
	selected_id = fallback_id
	provider = fallback_provider
	last_outcome = "configured"

func resolve(request: Dictionary, consumer: RefCounted) -> Dictionary:
	last_error = ""
	if selected_id.is_empty() or not provider.is_valid():
		last_outcome = "unconfigured"
		last_error = "fallback_unconfigured"
		return {}
	var value: Variant = provider.call(request)
	if not value is Dictionary:
		last_outcome = "invalid"
		last_error = "fallback_invalid"
		return {}
	var context: Dictionary = value
	var parsed: Dictionary = consumer.consume(str(context.get("lifecycle", "")), request, context.get("build_manifest", {}), context.get("runtime_manifest", {}), context.get("capabilities", {}))
	if parsed.is_empty() or str((parsed.get("trace", {}) as Dictionary).get("fallback", "")) != selected_id:
		last_outcome = "invalid"
		last_error = "fallback_identity"
		return {}
	last_outcome = "selected"
	return parsed
