extends RefCounted
class_name DemoScopeGate

## REQ-RL-006 demo scope gate.
##
## Pure data service. `is_allowed(feature_id)` returns:
##   - `true`  when build_kind is `dev` or `release` (no demo restriction)
##   - `true`  when build_kind is `demo` AND feature_id is not in the manifest
##     (blocklist semantics: the manifest lists what a demo build restricts;
##     everything else is allowed)
##   - `false` when build_kind is `demo` AND feature_id IS in the manifest
##   - `false` for the empty string (defensive; the only rejected input)
##
## Per ADR-0029: the demo manifest is data-driven. Adding a restriction
## is a JSON edit + a smoke re-run; no code change. Tranche 6: entries may
## carry a machine-readable `params` dict (enforcement caps) exposed via
## `get_params(feature_id)` so the coordinator's enforcement points read
## their caps from data, not hardcoded constants.

const DEMO_KIND: String = "demo"
const FULL_KIND: String = "release"
const DEV_KIND: String = "dev"

var _manifest: Dictionary = {}
var _build_metadata: BuildMetadataState = null
var _features: Array = []
var _params_by_feature: Dictionary = {}

func configure(manifest: Dictionary, build_metadata: BuildMetadataState) -> void:
	_manifest = manifest if manifest != null else {}
	_build_metadata = build_metadata
	_features.clear()
	_params_by_feature.clear()
	if typeof(_manifest) != TYPE_DICTIONARY:
		return
	var list_variant: Variant = _manifest.get("demo_blocked_features", [])
	if typeof(list_variant) == TYPE_ARRAY:
		for entry in (list_variant as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var feature_id: String = str((entry as Dictionary).get("feature_id", ""))
			if feature_id.is_empty():
				continue
			_features.append(feature_id)
			var params_variant: Variant = (entry as Dictionary).get("params", {})
			if typeof(params_variant) == TYPE_DICTIONARY and not (params_variant as Dictionary).is_empty():
				_params_by_feature[feature_id] = (params_variant as Dictionary).duplicate(true)

## Machine-readable enforcement caps for a manifest entry (Tranche 6).
## Returns an empty Dictionary for entries without authored params and for
## feature_ids not in the manifest.
func get_params(feature_id: String) -> Dictionary:
	var params_variant: Variant = _params_by_feature.get(feature_id, {})
	if typeof(params_variant) != TYPE_DICTIONARY:
		return {}
	return (params_variant as Dictionary).duplicate(true)

func is_allowed(feature_id: String) -> bool:
	if feature_id.is_empty():
		return false
	# Unknown feature_id is always rejected; the gate must be explicit.
	if not feature_id in _features:
		# If we are in dev/release build, every feature is allowed.
		if _build_metadata == null:
			return true
		var kind: String = _build_metadata.get_build_kind()
		if kind != DEMO_KIND:
			return true
		# In demo, a feature not in the manifest IS allowed.
		return true
	# Feature is in the demo-blocked list. Blocked only when in demo.
	if _build_metadata == null:
		return true
	var active_kind: String = _build_metadata.get_build_kind()
	if active_kind == DEMO_KIND:
		return false
	return true

func is_blocked(feature_id: String) -> bool:
	return not is_allowed(feature_id)

func list_blocked() -> Array:
	return _features.duplicate()

func list_allowed_in_demo() -> Array:
	if _build_metadata == null:
		return []
	if _build_metadata.get_build_kind() != DEMO_KIND:
		return []
	# In demo, the allowed set is everything not in the manifest.
	# The gate does not know the full feature surface, so this returns
	# just the manifest's complement hint: an empty array when the
	# manifest is comprehensive. Callers can compare against their
	# own feature list externally.
	return []

func get_blocked_count() -> int:
	return _features.size()

func get_summary() -> Dictionary:
	var kind: String = ""
	if _build_metadata != null:
		kind = _build_metadata.get_build_kind()
	return {
		"build_kind": kind,
		"manifest_features": _features.duplicate(),
		"blocked_count": _features.size(),
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if _build_metadata != null:
		lines.append("Build: %s" % _build_metadata.get_build_kind())
	lines.append("Demo-blocked features: %d" % _features.size())
	return lines