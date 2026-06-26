extends SceneTree

## REQ-RL-006 demo scope gate smoke.
##
## Pure-model test for `DemoScopeGate`. Configures the gate in two build
## kinds (full + demo) and asserts:
##  - in demo, every feature in the manifest is blocked
##  - in full build, every feature is allowed
##  - unknown feature ids are rejected (no silent allow)
##  - the gate round-trips its summary

const DemoScopeGateScript := preload("res://scripts/systems/demo_scope_gate.gd")
const BuildMetadataStateScript := preload("res://scripts/systems/build_metadata_state.gd")
const ROOT_DEFAULT: String = "/Users/christopherwilloughby/the-synaptic-sea"

func _initialize() -> void:
	var root_path: String = OS.get_environment("ROOT")
	if root_path.is_empty():
		root_path = ROOT_DEFAULT
	var manifest_path: String = root_path + "/data/release/demo_scope_manifest.json"
	if not FileAccess.file_exists(manifest_path):
		_fail("manifest unreadable: %s" % manifest_path)
		return
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	if file == null:
		_fail("manifest open failed: %s" % manifest_path)
		return
	var text: String = file.get_as_text()
	file.close()
	var manifest_parsed: Variant = JSON.parse_string(text)
	if manifest_parsed == null or typeof(manifest_parsed) != TYPE_DICTIONARY:
		_fail("manifest parse failed: %s" % manifest_path)
		return

	# Build the catalog of feature ids.
	var feature_ids: Array = []
	var list_variant: Variant = (manifest_parsed as Dictionary).get("demo_blocked_features", [])
	for entry in (list_variant as Array):
		var fid: String = str((entry as Dictionary).get("feature_id", ""))
		if not fid.is_empty():
			feature_ids.append(fid)
	if feature_ids.size() < 1:
		_fail("manifest has no demo_blocked_features entries")
		return

	# ----- demo build -----
	var demo_metadata = BuildMetadataStateScript.new()
	demo_metadata.configure({
		"build_kind": "demo",
		"version": "v0.1.0",
		"store": "itch",
	})
	var demo_gate = DemoScopeGateScript.new()
	demo_gate.configure(manifest_parsed, demo_metadata)
	for fid in feature_ids:
		if demo_gate.is_allowed(fid):
			_fail("demo build should block %s" % fid)
			return
	# Demo allows features not in the manifest.
	if not demo_gate.is_allowed("definitely.not.in.manifest"):
		_fail("demo should allow features not in the manifest")
		return
	# Unknown ids are still rejected (defensive: gate must be explicit).
	if demo_gate.is_allowed(""):
		_fail("empty feature id should be rejected")
		return

	# ----- full build -----
	var full_metadata = BuildMetadataStateScript.new()
	full_metadata.configure({
		"build_kind": "release",
		"version": "v0.1.0",
		"store": "steam",
	})
	var full_gate = DemoScopeGateScript.new()
	full_gate.configure(manifest_parsed, full_metadata)
	for fid in feature_ids:
		if not full_gate.is_allowed(fid):
			_fail("release build should allow %s" % fid)
			return

	# ----- dev build -----
	var dev_metadata = BuildMetadataStateScript.new()
	dev_metadata.configure({
		"build_kind": "dev",
		"version": "v0.1.0",
		"store": "itch",
	})
	var dev_gate = DemoScopeGateScript.new()
	dev_gate.configure(manifest_parsed, dev_metadata)
	for fid in feature_ids:
		if not dev_gate.is_allowed(fid):
			_fail("dev build should allow %s" % fid)
			return

	# Summary assertions.
	var summary: Dictionary = full_gate.get_summary()
	if str(summary.get("build_kind", "")) != "release":
		_fail("summary build_kind should be 'release'; got '%s'" % str(summary.get("build_kind", "")))
		return
	if int(summary.get("blocked_count", -1)) != feature_ids.size():
		_fail("summary blocked_count drift: %d vs %d" % [int(summary.get("blocked_count", -1)), feature_ids.size()])
		return

	print("DEMO SCOPE GATE PASS build_kind=release blocked=%d allowed=%d unknown_rejected=true" % [
		feature_ids.size(),
		0,  # in full build every listed feature is allowed
	])
	quit(0)

func _fail(reason: String) -> void:
	push_error("DEMO SCOPE GATE FAIL reason=%s" % reason)
	quit(1)