extends SceneTree

## ShipModificationState + pillar fields round-trip through RunSnapshot.
## Marker: SHIP MOD RUN SNAPSHOT PASS shipmod=true pillar=true count=true

const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")
const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const PillarPersistenceScript := preload("res://scripts/systems/pillar_persistence.gd")


func _initialize() -> void:
	if RunSnapshotScript.SUMMARY_FIELDS.size() < 32:
		_fail("expected 32 SUMMARY_FIELDS got %d" % RunSnapshotScript.SUMMARY_FIELDS.size()); return
	if not RunSnapshotScript.SUMMARY_FIELDS.has("ship_modification_summary"):
		_fail("missing ship_modification_summary field"); return

	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		_fail("catalog"); return
	var layout: Dictionary = {"rooms": [{
		"id": "eng",
		"room_role": "engineering",
		"wall_slots": [{"cell": [0, 0], "component_slot_profile_id": "wall_console_mount_v1"}],
		"center_slots": [],
	}]}
	var placement = ComponentPlacementStateScript.new()
	placement.populate(layout, catalog, 1)
	var prepared_lots: Dictionary = placement.prepare_condition_authority(
		"home", catalog, ComponentPlacementStateScript.CONDITION_MODE_GENERATED)
	if not bool(prepared_lots.get("ok", false)) \
			or not placement.commit_condition_authority(prepared_lots):
		_fail("condition authority"); return
	var dismounted: Dictionary = placement.dismount("eng_wall_0")
	var source_lot: Dictionary = dismounted.get("item_lot", {}) as Dictionary
	if not bool(dismounted.get("ok", false)) or source_lot.is_empty():
		_fail("dismount lot"); return
	var item_form: String = str(dismounted.get("item_form", ""))
	var inv: Dictionary = {item_form: 1}
	var mounted: Dictionary = placement.mount_by_slot_id(
		"eng_wall_0", item_form, inv, catalog, source_lot)
	if not bool(mounted.get("ok", false)) or not inv.is_empty():
		_fail("remount lot result=%s item=%s lot=%s" % [str(mounted), item_form, str(source_lot)]); return
	var mod = ShipModificationStateScript.new()
	mod.configure({"power_supply": 80.0})
	if not mod.bind_physical_slots("home", placement.get_physical_slot_descriptors("home"), catalog, placement):
		_fail("bind"); return
	if mod.installed_count() != 1:
		_fail("installed source lot"); return

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
	snap.component_placement_summary = placement.get_summary()
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
	var placement2 = ComponentPlacementStateScript.new()
	if not placement2.restore_from_layout(layout, catalog, 1, loaded.component_placement_summary):
		_fail("placement restore"); return
	if not mod2.bind_physical_slots("home", placement2.get_physical_slot_descriptors("home"), catalog, placement2):
		_fail("restored bind"); return
	if mod2.installed_count() != 1:
		_fail("install lost"); return
	var restored_entry: Dictionary = placement2.get_entry("eng_wall_0")
	if not bool(restored_entry.get("mounted", false)) \
			or restored_entry.get("source_lot", {}) != source_lot:
		_fail("source lot lost"); return
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
