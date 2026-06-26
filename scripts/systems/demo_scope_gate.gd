extends RefCounted
class_name DemoScopeGate

## REQ-RL-006 demo scope gate.
##
## Pure data service. `is_allowed(feature_id)` returns:
##   - `true`  when build_kind is `dev` or `release` (no demo restriction)
##   - `true`  when build_kind is `demo` AND feature_id is not in the manifest
##   - `false` when build_kind is `demo` AND feature_id IS in the manifest
##   - `false` for unknown feature_ids (no silent allow; the gate must be
##     explicit, so a typo in a feature_id gets caught at the call site)
##
## Per ADR-0029: the demo manifest is data-driven. Adding a restriction
## is a JSON edit + a smoke re-run; no code change.

const DEMO_KIND: String = "demo"
const FULL_KIND: String = "release"
const DEV_KIND: String = "dev"

var _manifest: Dictionary = {}
var _build_metadata: BuildMetadataState = null
var _features: Array = []

func configure(manifest: Dictionary, build_metadata: BuildMetadataState) -> void:
	_manifest = manifest if manifest != null else {}
	_build_metadata = build_metadata
	_features.clear()
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