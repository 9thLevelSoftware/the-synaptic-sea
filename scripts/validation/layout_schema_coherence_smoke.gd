extends SceneTree
# Tranche 5 (2026-07-06 audit MEDIUM, layout_serializer.gd:95 vs :5): schema
# split-brain — the serializer emits schema_version "1.2.0" while its own
# header comment claimed 1.1.0 and all three golden fixtures declared "1.1.0"
# (and lacked the 1.2.0 top-level keys: arc_zones/breach_zones/encounters/
# prototype where missing).
#
# Structural guard: this smoke derives BOTH the canonical version string and
# the required top-level key set from a live LayoutSerializer.serialize()
# call — never from a pinned literal — so any future schema bump goes RED
# here until the goldens are upgraded in the same change.
#
# Goldens are hand-authored curated fixtures: they are upgraded by hand
# (version bump + missing keys added), never pipeline-regenerated — curated
# content (e.g. coherent_ship_001's side_corridor_fire fire_zones entry,
# guarded by golden_fire_zone_source_marker_smoke) must survive.
#
# Pass marker: LAYOUT SCHEMA COHERENCE PASS goldens=3 version_match=true keys_match=true

const LayoutSerializerScript := preload("res://scripts/procgen/layout_serializer.gd")

const GOLDEN_PATHS: Array[String] = [
	"res://data/procgen/golden/coherent_ship_001/layout.json",
	"res://data/procgen/golden/coherent_ship_002/layout.json",
	"res://data/procgen/golden/coherent_ship_003/layout.json",
]

func _initialize() -> void:
	var serializer := LayoutSerializerScript.new()
	var canonical: Dictionary = serializer.serialize({}, {}, [] as Array[Dictionary], "spine", 0, "coherence_probe")
	var canonical_version: String = str(canonical.get("schema_version", ""))
	if canonical_version.is_empty():
		_fail("serializer emitted no schema_version")
		return
	var required_keys: Array = canonical.keys()

	var checked: int = 0
	for path in GOLDEN_PATHS:
		var doc: Dictionary = _load_json(path)
		if doc.is_empty():
			_fail("golden failed to load or parse: %s" % path)
			return
		var golden_version: String = str(doc.get("schema_version", ""))
		if golden_version != canonical_version:
			_fail("schema split-brain: %s declares '%s' but the serializer emits '%s'" % [
				path, golden_version, canonical_version])
			return
		for key in required_keys:
			if not doc.has(key):
				_fail("golden %s missing serializer top-level key '%s' (schema %s)" % [
					path, str(key), canonical_version])
				return
		checked += 1

	if checked != GOLDEN_PATHS.size():
		_fail("expected %d goldens checked, got %d" % [GOLDEN_PATHS.size(), checked])
		return

	print("LAYOUT SCHEMA COHERENCE PASS goldens=%d version_match=true keys_match=true" % checked)
	quit(0)

func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}

func _fail(reason: String) -> void:
	push_error("LAYOUT SCHEMA COHERENCE FAIL reason=%s" % reason)
	quit(1)
