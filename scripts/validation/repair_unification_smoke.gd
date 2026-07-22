extends SceneTree

## PKG-B2.5 / REQ-WA-004: repair_point, breach_seal, fire suppression share one
## WorkAction progress/interrupt path via WorkActionChannel.
## Marker: REPAIR UNIFICATION PASS repair=true seal=true suppress=true interrupt=true catalog=true

const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const WorkActionChannelScript := preload("res://scripts/systems/work_action_channel.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const RepairPointScript := preload("res://scripts/tools/repair_point.gd")
const BreachSealPointScript := preload("res://scripts/tools/breach_seal_point.gd")
const FireSuppressionPointScript := preload("res://scripts/tools/fire_suppression_point.gd")
const HullIntegrityStateScript := preload("res://scripts/systems/hull_integrity_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
const ExtinguisherStateScript := preload("res://scripts/systems/extinguisher_state.gd")


func _initialize() -> void:
	_run()


func _run() -> void:
	var cat = WorkActionCatalogScript.new()
	if not cat.load_default():
		_fail("catalog load"); return
	for needed in ["repair_subcomponent", "patch_breach", "suppress_fire", "weld_patch"]:
		if not cat.has_action(needed):
			_fail("missing catalog action %s" % needed); return

	# --- Pure shared channel: progress + interrupt ---
	var ch = WorkActionChannelScript.new()
	if not ch.begin("repair_subcomponent", "propulsion/nav_linkage", 4.0, {}):
		_fail("repair_subcomponent begin"); return
	if ch.action_id != "repair_subcomponent":
		_fail("action_id mismatch"); return
	ch.tick(2.0, {})
	var mid: float = ch.progress_ratio()
	if mid < 0.45 or mid > 0.55:
		_fail("expected ~0.5 progress, got %s" % str(mid)); return
	var st: String = ch.tick(0.1, {"damaged": true})
	if st != WorkActionStateScript.STATUS_INTERRUPTED:
		_fail("expected interrupt on damage, got %s" % st); return
	ch.cancel()
	if ch.is_active():
		_fail("cancel should clear active work"); return

	# Seal + suppress pure channel complete without domain (progress only)
	var ch_seal = WorkActionChannelScript.new()
	var seal_ctx: Dictionary = {
		"tool_class": "sealant",
		"skill_id": "repair",
		"skill_level": 0,
		"inventory": {"hull_sealant": 1},
	}
	if not ch_seal.begin("patch_breach", "cargo", 3.5, seal_ctx):
		_fail("patch_breach begin"); return
	ch_seal.tick(10.0, {})
	if not ch_seal.is_completed():
		_fail("patch_breach should complete"); return

	var ch_fire = WorkActionChannelScript.new()
	if not ch_fire.begin("suppress_fire", "engineering", 4.0, {}):
		_fail("suppress_fire begin"); return
	ch_fire.tick(10.0, {})
	if not ch_fire.is_completed():
		_fail("suppress_fire should complete"); return

	# --- Scene wrappers expose WorkAction ids while channeling ---
	var inv := InventoryStateScript.new()
	inv.add_item("hull_sealant", 1)
	inv.add_item("fire_extinguisher", 1)

	var player := Node3D.new()
	get_root().add_child(player)
	player.position = Vector3.ZERO

	# BreachSealPoint
	var hull = HullIntegrityStateScript.new()
	hull.configure({"compartments": [{"compartment_id": "cargo", "health": 0.3, "breach_open": true, "isolation_rating": 0.6}]})
	var seal_point = BreachSealPointScript.new()
	seal_point.configure("cargo", hull, inv, null, Vector3.ZERO, 4.0, "hull_sealant", 1.0, 1.8)
	get_root().add_child(seal_point)
	await process_frame
	if not seal_point.try_start(player):
		_fail("breach try_start"); return
	if seal_point.get_work_action_id() != "patch_breach":
		_fail("breach should drive patch_breach, got '%s'" % seal_point.get_work_action_id()); return
	if not seal_point.channeling:
		_fail("breach should be channeling"); return
	seal_point.advance_channel(0.5)
	if seal_point.progress <= 0.0:
		_fail("breach progress should advance via WorkActionChannel"); return
	# Leave unfinished — cancel path
	seal_point._cancel()
	if seal_point.channeling or seal_point.get_work_action_id() != "":
		_fail("breach cancel should clear work channel"); return
	# Complete path
	if not seal_point.try_start(player):
		_fail("breach restart"); return
	seal_point.advance_channel(10.0)
	if not seal_point.sealed:
		_fail("breach should seal on complete"); return
	if hull.get_breach_count() != 0:
		_fail("breach_count should be 0"); return

	# FireSuppressionPoint
	var fire = FireSuppressionStateScript.new()
	fire.configure({"compartments": ["engineering"], "adjacency": {}})
	fire.ignite("engineering", 1.0)
	var ext = ExtinguisherStateScript.new()
	ext.configure({"charge": 100.0, "max_charge": 100.0, "charge_cost_per_use": 34.0})
	var fire_point = FireSuppressionPointScript.new()
	fire_point.configure("engineering", fire, ext, inv, null, Vector3.ZERO, 4.0, "fire_extinguisher", 1.8)
	get_root().add_child(fire_point)
	await process_frame
	if not fire_point.try_start(player):
		_fail("fire try_start"); return
	if fire_point.get_work_action_id() != "suppress_fire":
		_fail("fire should drive suppress_fire, got '%s'" % fire_point.get_work_action_id()); return
	fire_point.advance_channel(10.0)
	if fire.is_burning("engineering"):
		_fail("fire should extinguish"); return

	# RepairPoint: catalog constant only (full systems manager path covered by repair_loop_smoke)
	if RepairPointScript.WORK_ACTION_ID != "repair_subcomponent":
		_fail("RepairPoint WORK_ACTION_ID"); return
	if BreachSealPointScript.WORK_ACTION_ID != "patch_breach":
		_fail("BreachSealPoint WORK_ACTION_ID"); return
	if FireSuppressionPointScript.WORK_ACTION_ID != "suppress_fire":
		_fail("FireSuppressionPoint WORK_ACTION_ID"); return

	print("REPAIR UNIFICATION PASS repair=true seal=true suppress=true interrupt=true catalog=true")
	quit(0)


func _fail(msg: String) -> void:
	print("REPAIR UNIFICATION FAIL: %s" % msg)
	quit(1)
