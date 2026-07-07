extends RefCounted
class_name BuildMetadataState

## REQ-RL-002 build metadata state.
##
## Pure data service. Reads `data/release/build_metadata.json` and
## exposes a single source of truth for "what kind of build is running"
## (`dev`, `demo`, `release`). Consumed by `DemoScopeGate`,
## `ReleaseReadinessLedger`, and the release badge overlay UI.
##
## Per ADR-0029: this service owns the manifest; downstream services
## consume it but never duplicate the build_kind logic. An invalid
## `build_kind` is recorded in `get_summary()["build_kind_validated"]`
## as `false` so callers can detect a misconfigured release pipeline.

const VALID_BUILD_KINDS: Array = ["dev", "demo", "release"]
const DEFAULT_VERSION: String = "v0.0.0"
const DEFAULT_STORE: String = "direct"

var version: String = DEFAULT_VERSION
var build_kind: String = ""
var store: String = DEFAULT_STORE
var language_defaults: Array = ["en"]
var achievements_supported: bool = false
var demo_hub_unlocked_features: Array = []
var release_date: String = ""
# ADR-0029 deferred crash-upload endpoint placeholder; no consumer exists until crash upload is wired.
var telemetry_endpoint_placeholder: String = ""

# `true` after configure() ran with a known build_kind.
var _validated: bool = false

func configure(manifest: Dictionary) -> void:
	if manifest == null:
		manifest = {}
	version = str(manifest.get("version", DEFAULT_VERSION))
	build_kind = str(manifest.get("build_kind", "dev"))
	store = str(manifest.get("store", DEFAULT_STORE))
	language_defaults.clear()
	var lang_variant: Variant = manifest.get("language_defaults", ["en"])
	if typeof(lang_variant) == TYPE_ARRAY:
		for lang in (lang_variant as Array):
			var lang_str: String = str(lang)
			if lang_str.is_empty():
				continue
			language_defaults.append(lang_str)
	if language_defaults.is_empty():
		language_defaults.append("en")
	achievements_supported = bool(manifest.get("achievements_supported", false))
	demo_hub_unlocked_features.clear()
	var hub_variant: Variant = manifest.get("demo_hub_unlocked_features", [])
	if typeof(hub_variant) == TYPE_ARRAY:
		for hub_id in (hub_variant as Array):
			var hub_id_str: String = str(hub_id)
			if hub_id_str.is_empty():
				continue
			demo_hub_unlocked_features.append(hub_id_str)
	release_date = str(manifest.get("release_date", ""))
	telemetry_endpoint_placeholder = str(manifest.get("telemetry_endpoint_placeholder", ""))
	_validated = build_kind in VALID_BUILD_KINDS

func get_build_kind() -> String:
	return build_kind

func is_achievements_supported() -> bool:
	return achievements_supported

func is_build_kind_validated() -> bool:
	return _validated

func get_default_language() -> String:
	if language_defaults.is_empty():
		return "en"
	return String(language_defaults[0])

func get_summary() -> Dictionary:
	return {
		"version": version,
		"build_kind": build_kind,
		"store": store,
		"language_defaults": language_defaults.duplicate(),
		"achievements_supported": achievements_supported,
		"demo_hub_unlocked_features": demo_hub_unlocked_features.duplicate(),
		"release_date": release_date,
		"telemetry_endpoint_placeholder": telemetry_endpoint_placeholder,
		"build_kind_validated": _validated,
		"valid_build_kinds": VALID_BUILD_KINDS.duplicate(),
	}

func get_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Build: %s (%s)" % [version, build_kind])
	if not _validated:
		lines.append("Build: WARN unknown build_kind=%s" % build_kind)
	lines.append("Store: %s" % store)
	lines.append("Languages: %s" % ",".join(language_defaults))
	return lines
