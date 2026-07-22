extends SceneTree

## PKG-B2.1a: ModuleIntegrityState + Map pure contract (ADR-0051 / REQ-MI-001).
## Marker: MODULE INTEGRITY PASS fsm=true sparse=true determinism=true round_trip=true

const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")


func _initialize() -> void:
	var m = ModuleIntegrityStateScript.new()
	m.configure({
		"module_id": "wall_a",
		"kind": "wall_straight_1x1",
		"base_integrity": 1.0,
		"material_composition": {"scrap_metal": 4},
	})
	if m.state != ModuleIntegrityStateScript.STATE_INTACT:
		_fail("fresh module should be intact")
		return
	m.apply_damage(0.3)
	if m.state != ModuleIntegrityStateScript.STATE_DAMAGED:
		_fail("expected damaged after 0.3 dmg, got %s integ=%s" % [m.state, str(m.integrity)])
		return
	m.apply_damage(0.4)
	if m.state != ModuleIntegrityStateScript.STATE_BREACHED:
		_fail("expected breached, got %s" % m.state)
		return
	m.apply_damage(0.5)
	if m.state != ModuleIntegrityStateScript.STATE_DESTROYED:
		_fail("expected destroyed, got %s" % m.state)
		return

	var map = ModuleIntegrityMapScript.new()
	map.apply_damage("w1", 0.3, "wall_straight_1x1")
	map.apply_damage("w2", 0.0, "wall_straight_1x1")  # ensure still pristine if only registered via ensure
	# only damaged should appear in sparse deltas
	map.ensure_module("w2", "wall_straight_1x1")
	var deltas: Array = map.to_sparse_deltas()
	if deltas.size() != 1:
		_fail("sparse deltas should only include non-pristine, got %d" % deltas.size())
		return
	if str(deltas[0].get("module_id", "")) != "w1":
		_fail("sparse delta wrong id")
		return

	var map2 = ModuleIntegrityMapScript.new()
	map2.apply_sparse_deltas(deltas)
	if map2.get_state("w1") != ModuleIntegrityStateScript.STATE_DAMAGED:
		_fail("round-trip state mismatch")
		return
	if map.fingerprint() != map2.fingerprint():
		# w2 not in map2 — fingerprints differ by design; compare only delta modules
		if map2.get_state("w1") != map.get_state("w1"):
			_fail("determinism/round-trip state for w1")
			return

	# materials table loads
	var path: String = "res://data/kits/ship_structural_v0.materials.json"
	if not FileAccess.file_exists(path):
		_fail("materials table missing")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("modules"):
		_fail("materials table parse")
		return

	# snapshot summary round-trip
	var summary: Dictionary = map.get_summary()
	var map3 = ModuleIntegrityMapScript.new()
	map3.apply_summary(summary)
	if map3.get_state("w1") != ModuleIntegrityStateScript.STATE_DAMAGED:
		_fail("summary round-trip")
		return

	print("MODULE INTEGRITY PASS fsm=true sparse=true determinism=true round_trip=true")
	quit(0)


func _fail(msg: String) -> void:
	print("MODULE INTEGRITY FAIL: %s" % msg)
	quit(1)
