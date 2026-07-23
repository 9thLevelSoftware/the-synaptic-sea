extends SceneTree

## ShipModificationState + pillar fields round-trip through RunSnapshot.
## Marker: SHIP MOD RUN SNAPSHOT PASS shipmod=true pillar=true count=true

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const PillarPersistenceScript := preload("res://scripts/systems/pillar_persistence.gd")


func _initialize() -> void:
	if RunSnapshotScript.SUMMARY_FIELDS.size() < 32:
		_fail("expected 32 SUMMARY_FIELDS got %d" % RunSnapshotScript.SUMMARY_FIELDS.size()); return
	if not RunSnapshotScript.SUMMARY_FIELDS.has("ship_modification_summary"):
		_fail("missing ship_modification_summary field"); return

	var mod = ShipModificationStateScript.new()
	mod.configure({"power_supply": 80.0})
	var inv: Dictionary = {"console_unit": 1}
	var inst: Dictionary = mod.install("hub_slot_0", "console_generic", "console_unit", inv, 5.0, 12.0, "home")
	if not bool(inst.get("ok", false)):
		_fail("install"); return

	var map = ModuleIntegrityMapScript.new()
	map.apply_damage("eng/wall_0", 0.4, "wall_straight_1x1")

	var snap = RunSnapshotScript.new()
	snap.slice_version = "gate2-current-run-4"
	snap.godot_version = "4.6.2"
	snap.layout_path = "res://data/procgen/golden/coherent_ship_001/layout.json"
	snap.kit_path = "res://data/kits/ship_structural_v0.json"
	snap.gameplay_slice_path = "res://data/gameplay/coherent_ship_001_slice.json"
	snap.player_position = [1.0, 0.0, 2.0]
	snap.ship_modification_summary = mod.get_summary()
	snap.module_integrity_summary = map.get_summary()
	snap.component_placement_summary = {"schema": "component_placement_v1", "placed": [], "seed": 1, "count": 0}
	snap.work_action_summary = {"schema": "work_action_v1", "active": false}

	var d: Dictionary = snap.to_dict()
	if not d.has("ship_modification_summary"):
		_fail("to_dict missing ship_modification"); return
	var loaded = RunSnapshotScript.from_dict(d, "gate2-current-run-4", "4.6.2")
	if loaded == null:
		_fail("from_dict"); return
	if loaded.get_summary_count() != 32:
		_fail("count %d" % loaded.get_summary_count()); return
	var mod2 = ShipModificationStateScript.new()
	mod2.apply_summary(loaded.ship_modification_summary)
	if mod2.installed_count() != 1:
		_fail("install lost"); return
	if float(mod2.power_supply) <= 0.0:
		_fail("power supply lost"); return
	var map2 = ModuleIntegrityMapScript.new()
	map2.apply_summary(loaded.module_integrity_summary)
	if map2.get_state("eng/wall_0") == "intact":
		_fail("integrity lost"); return
	# Historical fuzz still loads
	var hist: Dictionary = PillarPersistenceScript.sanitize_historical({
		"slice_version": "gate2-current-run-4",
		"godot_version": "4.6.2",
		"layout_path": "res://x",
		"player_position": [0, 0, 0],
	})
	var hist_snap = RunSnapshotScript.from_dict(hist, "gate2-current-run-4", "4.6.2")
	if hist_snap == null:
		_fail("historical"); return
	if not hist_snap.ship_modification_summary.is_empty() and typeof(hist_snap.ship_modification_summary) != TYPE_DICTIONARY:
		_fail("shipmod default"); return

	print("SHIP MOD RUN SNAPSHOT PASS shipmod=true pillar=true count=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SHIP MOD RUN SNAPSHOT FAIL: %s" % msg)
	quit(1)
