extends SceneTree

## PKG-A2: SimKeys contract smoke.
## Asserts the vitals hot-path key set is stable and string values match the
## historical wire names so producers still interoperate during migration.

const SimKeysScript := preload("res://scripts/systems/sim_keys.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")


func _initialize() -> void:
	var hot: PackedStringArray = SimKeysScript.vitals_hot_path_keys()
	if hot.size() != 12:
		_fail("vitals hot-path key count expected 12, got %d" % hot.size())
		return

	# Wire-name stability (do not rename without a migration plan).
	var expected: Dictionary = {
		"moving": true,
		"radiation_health_drain": true,
		"atmosphere_health_drain": true,
		"fire_health_drain": true,
		"sanity_health_drain": true,
		"encumbrance_health_drain": true,
		"temperature_thirst_mult": true,
		"temperature_hunger_mult": true,
		"wound_thirst_mult": true,
		"wound_health_drain": true,
		"status_stamina_recovery_mult": true,
		"sanity_stamina_recovery_mult": true,
	}
	for k in hot:
		if not expected.has(k):
			_fail("unexpected vitals hot-path key: %s" % k)
			return
		expected.erase(k)
	if not expected.is_empty():
		_fail("missing vitals hot-path keys: %s" % str(expected.keys()))
		return

	# Const values equal wire strings.
	if SimKeysScript.FIRE_HEALTH_DRAIN != "fire_health_drain":
		_fail("FIRE_HEALTH_DRAIN wire mismatch")
		return
	if SimKeysScript.MOVING != "moving":
		_fail("MOVING wire mismatch")
		return

	# VitalsState accepts SimKeys-built context (and literal-equivalent keys).
	var v = VitalsStateScript.new()
	v.configure({"health_drain_rate": 0.0, "stamina_drain_rate": 0.0, "hunger_drain_rate": 0.0, "thirst_drain_rate": 1.0})
	v.health = 100.0
	v.thirst = 100.0
	var ctx: Dictionary = {
		SimKeysScript.MOVING: false,
		SimKeysScript.FIRE_HEALTH_DRAIN: 10.0,
		SimKeysScript.TEMPERATURE_THIRST_MULT: 2.0,
	}
	v.tick(1.0, ctx)
	if v.health > 90.1 or v.health < 89.9:
		_fail("fire drain via SimKeys expected health~90, got %s" % str(v.health))
		return
	if v.thirst > 98.1 or v.thirst < 97.9:
		# thirst_drain_rate 1.0 * mult 2.0 * 1s = 2.0 → 98
		_fail("thirst mult via SimKeys expected thirst~98, got %s" % str(v.thirst))
		return

	var all_keys: PackedStringArray = SimKeysScript.all_keys()
	if all_keys.size() < hot.size():
		_fail("all_keys smaller than hot path")
		return
	# Uniqueness
	var seen: Dictionary = {}
	for k2 in all_keys:
		if seen.has(k2):
			_fail("duplicate SimKeys entry: %s" % k2)
			return
		if str(k2).is_empty():
			_fail("empty SimKeys entry")
			return
		seen[k2] = true

	print("SIM KEYS PASS hot=%d total=%d vitals_wired=true" % [hot.size(), all_keys.size()])
	quit(0)


func _fail(msg: String) -> void:
	print("SIM KEYS FAIL: %s" % msg)
	quit(1)
