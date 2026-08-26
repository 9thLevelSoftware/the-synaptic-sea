extends RefCounted
class_name ProcgenFallbackPolicy

var provider: Callable = Callable()
var selected_id: String = ""
var last_error: String = ""

func configure(fallback_id: String, fallback_provider: Callable) -> void:
	selected_id = fallback_id
	provider = fallback_provider

func resolve(request: Dictionary, consumer: ProcgenBundleConsumer) -> Dictionary:
	last_error = ""
	if selected_id.is_empty() or not provider.is_valid():
		last_error = "fallback_unconfigured"
		return {}
	var value: Variant = provider.call(request)
	if not value is String:
		last_error = "fallback_invalid"
		return {}
	var parsed: Dictionary = consumer.consume(value, request)
	if parsed.is_empty() or str((parsed.get("trace", {}) as Dictionary).get("fallback", "")) != selected_id:
		last_error = "fallback_identity"
		return {}
	return parsed
