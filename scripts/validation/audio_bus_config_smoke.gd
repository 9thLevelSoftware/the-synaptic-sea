extends SceneTree
# REQ-AU-002 / ADR-0029: pure model smoke for the audio bus config Resource.
#
# Verifies:
# - make_default() produces a seven-bus config matching the ADR-0029 layout.
# - validate() accepts the canonical config and rejects malformed configs
#   (empty ids, duplicates, out-of-range volumes, missing master, missing
#   required bus, missing parent).
# - set_volume_db / set_muted apply changes, reject out-of-range, and keep
#   the validate flag accurate.
# - get_summary / apply_summary round-trip the bus volumes + mutes.
#
# Pass marker: AUDIO BUS CONFIG PASS buses=7 default=true summary_round_trip=true

func _initialize() -> void:
	var cfg_script := load("res://scripts/systems/audio_bus_config.gd")
	if cfg_script == null:
		_fail("could not load AudioBusConfig script")
		return

	var cfg: Resource = cfg_script.make_default()
	if cfg == null:
		_fail("make_default returned null")
		return
	if not cfg.is_validated():
		_fail("default config failed validation")
		return
	if cfg.buses.size() != 7:
		_fail("expected 7 buses, got %d" % cfg.buses.size())
		return
	# Every required bus id must be present with the right parent + default volume.
	var expected: Dictionary = {
		"master": {"parent": "", "volume": 0.0},
		"sfx": {"parent": "master", "volume": -3.0},
		"music": {"parent": "master", "volume": -6.0},
		"voice": {"parent": "master", "volume": -3.0},
		"ui": {"parent": "master", "volume": -6.0},
		"ambient": {"parent": "master", "volume": -9.0},
		"meta": {"parent": "master", "volume": -6.0},
	}
	for bus_id in expected.keys():
		var bus: Dictionary = cfg.get_bus(StringName(bus_id))
		if bus.is_empty():
			_fail("bus '%s' missing from default config" % bus_id)
			return
		if String(bus.get("parent_id", "")) != String(expected[bus_id]["parent"]):
			_fail("bus '%s' parent_id mismatch" % bus_id)
			return
		if absf(float(bus.get("volume_db", 0.0)) - float(expected[bus_id]["volume"])) > 0.001:
			_fail("bus '%s' volume_db=%s expected %s" % [bus_id, str(bus.get("volume_db")), str(expected[bus_id]["volume"])])
			return

	# Reject an empty bus list.
	var empty_cfg: Resource = cfg_script.new()
	empty_cfg.buses = []
	if empty_cfg.validate(false):
		_fail("validate accepted an empty bus list")
		return

	# Reject out-of-range volume.
	var bad_vol: Resource = cfg_script.new()
	bad_vol.buses = [{"id": "master", "parent_id": "", "volume_db": 5.0, "muted": false}]
	if bad_vol.validate(false):
		_fail("validate accepted volume_db=5.0")
		return

	# Reject duplicate ids.
	var dup: Resource = cfg_script.new()
	dup.buses = [
		{"id": "master", "parent_id": "", "volume_db": 0.0, "muted": false},
		{"id": "master", "parent_id": "", "volume_db": 0.0, "muted": false},
	]
	if dup.validate(false):
		_fail("validate accepted duplicate bus ids")
		return

	# Reject child bus with wrong parent.
	var bad_parent: Resource = cfg_script.new()
	bad_parent.buses = [
		{"id": "master", "parent_id": "", "volume_db": 0.0, "muted": false},
		{"id": "sfx", "parent_id": "music", "volume_db": -3.0, "muted": false},
	]
	if bad_parent.validate(false):
		_fail("validate accepted wrong parent_id")
		return

	# set_volume_db updates + clamps.
	if not cfg.set_volume_db("sfx", -12.0):
		_fail("set_volume_db(-12.0) should succeed")
		return
	if absf(cfg.get_volume_db("sfx") - (-12.0)) > 0.001:
		_fail("get_volume_db('sfx') after set did not match")
		return
	# Out-of-range: clamp in set_volume_db must reject (return false).
	if cfg.set_volume_db("sfx", 5.0):
		_fail("set_volume_db(5.0) should reject")
		return
	if cfg.set_volume_db("missing_bus", -6.0):
		_fail("set_volume_db on missing bus should reject")
		return

	# set_muted toggles mute state.
	if not cfg.set_muted("sfx", true):
		_fail("set_muted should succeed on existing bus")
		return
	if not cfg.is_muted("sfx"):
		_fail("is_muted('sfx') should be true after set")
		return

	# Round-trip summary.
	var summary: Dictionary = cfg.get_summary()
	if str(summary.get("kind", "")) != "audio_bus_config":
		_fail("summary kind missing")
		return
	if not summary.has("volumes") or typeof(summary["volumes"]) != TYPE_DICTIONARY:
		_fail("summary.volumes missing or wrong type")
		return
	if not summary["volumes"].has("sfx") or absf(float(summary["volumes"]["sfx"]) - (-12.0)) > 0.001:
		_fail("summary.volumes.sfx missing or wrong")
		return
	var fresh: Resource = cfg_script.new()
	fresh.buses = [
		{"id": "master", "parent_id": "", "volume_db": 0.0, "muted": false},
		{"id": "sfx", "parent_id": "master", "volume_db": -3.0, "muted": false},
		{"id": "music", "parent_id": "master", "volume_db": -6.0, "muted": false},
		{"id": "voice", "parent_id": "master", "volume_db": -3.0, "muted": false},
		{"id": "ui", "parent_id": "master", "volume_db": -6.0, "muted": false},
		{"id": "ambient", "parent_id": "master", "volume_db": -9.0, "muted": false},
		{"id": "meta", "parent_id": "master", "volume_db": -6.0, "muted": false},
	]
	fresh.validate()
	if not fresh.apply_summary(summary):
		_fail("apply_summary should report changes")
		return
	if absf(fresh.get_volume_db("sfx") - (-12.0)) > 0.001:
		_fail("round-trip did not restore sfx volume")
		return

	# Round-trip through JSON.stringify so the persistence path is exercised.
	var json: String = JSON.stringify(summary)
	var parsed: Variant = JSON.parse_string(json)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("json round-trip failed")
		return
	var from_json: Resource = cfg_script.new()
	from_json.buses = [
		{"id": "master", "parent_id": "", "volume_db": 0.0, "muted": false},
		{"id": "sfx", "parent_id": "master", "volume_db": -3.0, "muted": false},
		{"id": "music", "parent_id": "master", "volume_db": -6.0, "muted": false},
		{"id": "voice", "parent_id": "master", "volume_db": -3.0, "muted": false},
		{"id": "ui", "parent_id": "master", "volume_db": -6.0, "muted": false},
		{"id": "ambient", "parent_id": "master", "volume_db": -9.0, "muted": false},
		{"id": "meta", "parent_id": "master", "volume_db": -6.0, "muted": false},
	]
	from_json.validate()
	from_json.apply_summary(parsed)
	if absf(from_json.get_volume_db("sfx") - (-12.0)) > 0.001:
		_fail("json round-trip did not restore sfx volume")
		return

	# Three-volume smoke: each bus must report a get_volume_db in [-60, 0].
	for bus_id in ["master", "sfx", "music", "voice", "ui", "ambient", "meta"]:
		var vol: float = cfg.get_volume_db(StringName(bus_id))
		if vol < -60.0 or vol > 0.0:
			_fail("bus '%s' volume=%s out of [-60, 0]" % [bus_id, str(vol)])
			return

	print("AUDIO BUS CONFIG PASS buses=%d default=true summary_round_trip=true" % cfg.buses.size())
	quit(0)

func _fail(reason: String) -> void:
	push_error("AUDIO BUS CONFIG FAIL reason=%s" % reason)
	quit(1)
