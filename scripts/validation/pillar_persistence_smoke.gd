extends SceneTree

## PKG-D8: pillar snapshots (integrity/components/work-in-progress) + historical fuzz.
## Marker: PILLAR PERSISTENCE PASS integrity=true components=true work=true fuzz=true snapshot=true

const PillarPersistenceScript := preload("res://scripts/systems/pillar_persistence.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const RunSnapshotScript := preload("res://scripts/systems/run_snapshot.gd")


func _initialize() -> void:
	# --- Integrity pack/unpack ---
	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("eng/wall_0", "wall_straight_1x1", {}, "eng")
	map.apply_damage("eng/wall_0", 0.5, "wall_straight_1x1")
	var mi_pack: Dictionary = PillarPersistenceScript.pack_module_integrity(map)
	if (mi_pack.get("deltas", []) as Array).is_empty():
		_fail("expected sparse deltas for damaged module"); return
	var map2 = PillarPersistenceScript.unpack_module_integrity(mi_pack)
	if map2.get_state("eng/wall_0") == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("integrity should survive unpack"); return

	# --- Components pack/unpack ---
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("component catalog"); return
	var place = ComponentPlacementStateScript.new()
	place.populate({
		"rooms": [{
			"id": "eng_1",
			"room_role": "engineering",
			"wall_slots": [{"against_wall": true, "cell": "(0,0)"}],
			"center_slots": [],
		}],
	}, cat, 11)
	if place.placed.is_empty():
		_fail("need placements"); return
	var first_id: String = str(place.placed[0].get("component_instance_id", ""))
	place.dismount(first_id)
	var cp_pack: Dictionary = PillarPersistenceScript.pack_component_placement(place)
	var place2 = PillarPersistenceScript.unpack_component_placement(cp_pack)
	if place2.is_mounted(first_id):
		_fail("dismounted state should survive"); return
	if place2.placed.size() != place.placed.size():
		_fail("placement count"); return

	# --- WorkAction mid-progress ---
	var wa_cat = WorkActionCatalogScript.new()
	if not wa_cat.load_default():
		_fail("work catalog"); return
	var work = WorkActionStateScript.new()
	work.configure_action("cut_wall", wa_cat.get_action("cut_wall"))
	work.start("wall_x", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	})
	work.tick(1.5, {})
	if work.status != WorkActionStateScript.STATUS_ACTIVE:
		_fail("expected active mid-work"); return
	var mid_progress: float = work.progress
	var wa_pack: Dictionary = PillarPersistenceScript.pack_work_action(work)
	if not bool(wa_pack.get("active", false)):
		_fail("pack should mark active"); return
	var work2 = PillarPersistenceScript.unpack_work_action(wa_pack)
	if work2.status != WorkActionStateScript.STATUS_ACTIVE:
		_fail("work status round-trip"); return
	if absf(float(work2.progress) - mid_progress) > 0.001:
		_fail("work progress round-trip"); return
	# Complete after load
	work2.tick(20.0, {})
	if work2.status != WorkActionStateScript.STATUS_COMPLETED:
		_fail("resumed work should complete"); return

	# Idle work packs as inactive
	var idle = WorkActionStateScript.new()
	var idle_pack: Dictionary = PillarPersistenceScript.pack_work_action(idle)
	if bool(idle_pack.get("active", true)):
		_fail("idle should not be active"); return

	# Bundle + RunSnapshot fields
	var bundle: Dictionary = PillarPersistenceScript.pack_all(map, place, work)
	var snap = RunSnapshotScript.new()
	snap.slice_version = "gate2-current-run-4"
	snap.godot_version = "4.6.2"
	snap.module_integrity_summary = bundle["module_integrity"]
	snap.component_placement_summary = bundle["component_placement"]
	snap.work_action_summary = bundle["work_action"]
	var d: Dictionary = snap.to_dict()
	if not d.has("module_integrity_summary") or not d.has("work_action_summary"):
		_fail("to_dict missing pillar fields"); return
	var loaded = RunSnapshotScript.from_dict(d, "gate2-current-run-4", "4.6.2")
	if loaded == null:
		_fail("from_dict failed"); return
	if loaded.get_summary_count() < 31:
		_fail("SUMMARY_FIELDS should include pillar (got %d)" % loaded.get_summary_count()); return
	var unp: Dictionary = PillarPersistenceScript.unpack_all({
		"module_integrity": loaded.module_integrity_summary,
		"component_placement": loaded.component_placement_summary,
		"work_action": loaded.work_action_summary,
	})
	var w3 = unp["work_action"]
	if str(w3.get("status")) != WorkActionStateScript.STATUS_ACTIVE:
		_fail("snapshot work active"); return

	# Historical fuzz: missing keys + garbage values
	var historical: Dictionary = {
		"slice_version": "gate2-current-run-4",
		"godot_version": "4.6.2",
		"layout_path": "res://x",
		"player_position": [0, 0, 0],
		"module_integrity_summary": "not_a_dict",
		"extra_garbage": 123,
	}
	var cleaned: Dictionary = PillarPersistenceScript.sanitize_historical(historical)
	if typeof(cleaned.get("module_integrity_summary")) != TYPE_DICTIONARY:
		_fail("sanitize should coerce integrity"); return
	var hist_snap = RunSnapshotScript.from_dict(cleaned, "gate2-current-run-4", "4.6.2")
	if hist_snap == null:
		_fail("historical fixture should load with empty pillar defaults"); return
	if not hist_snap.module_integrity_summary.is_empty() and typeof(hist_snap.module_integrity_summary) != TYPE_DICTIONARY:
		_fail("integrity default"); return
	# Empty pillar ok
	var empty_map = PillarPersistenceScript.unpack_module_integrity(hist_snap.module_integrity_summary)
	if empty_map.size() != 0:
		_fail("empty historical integrity"); return

	print("PILLAR PERSISTENCE PASS integrity=true components=true work=true fuzz=true snapshot=true")
	quit(0)


func _fail(msg: String) -> void:
	print("PILLAR PERSISTENCE FAIL: %s" % msg)
	quit(1)
