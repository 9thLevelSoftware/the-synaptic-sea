extends SceneTree

## PKG-B2.3b / REQ-CMP-003: dismount yields heavy item; remount restores placement via WorkActions.
## Marker: COMPONENT MOUNT DISMOUNT PASS dismount=true mount=true work=true mass=true round_trip=true

const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentMountResolverScript := preload("res://scripts/systems/component_mount_resolver.gd")
const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")


func _initialize() -> void:
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("component catalog"); return
	var wa = WorkActionCatalogScript.new()
	if not wa.load_default():
		_fail("work action catalog"); return
	if not wa.has_action("dismount_component") or not wa.has_action("mount_component"):
		_fail("missing mount/dismount work actions"); return

	var layout: Dictionary = {
		"rooms": [
			{
				"id": "eng_1",
				"room_role": "engineering",
				"wall_slots": [
					{"against_wall": true, "cell": "(0, 0)"},
					{"against_wall": true, "cell": "(0, 1)"},
				],
				"center_slots": [
					{"against_wall": false, "cell": "(0, 0)"},
				],
			},
		]
	}
	var place = ComponentPlacementStateScript.new()
	var n: int = place.populate(layout, cat, 42)
	if n < 1:
		_fail("need at least one placed component"); return
	var mounted_before: int = place.mounted_count()

	# Pick first mounted entry
	var entry: Dictionary = {}
	for e in place.placed:
		if typeof(e) == TYPE_DICTIONARY and bool((e as Dictionary).get("mounted", true)):
			entry = e
			break
	if entry.is_empty():
		_fail("no mounted entry"); return
	var instance_id: String = str(entry.get("component_instance_id", ""))
	var item_form: String = str(entry.get("item_form", ""))
	var mass: float = float(entry.get("mass", 0.0))
	var room_id: String = str(entry.get("room_id", ""))
	var slot_kind: String = str(entry.get("slot_kind", ""))
	var slot_index: int = int(entry.get("slot_index", 0))
	if mass < 5.0:
		_fail("component should be heavy (mass>=5), got %s" % str(mass)); return

	# --- WorkAction dismount ---
	var work = WorkActionStateScript.new()
	work.configure_action("dismount_component", wa.get_action("dismount_component"))
	var ctx: Dictionary = {
		"tool_class": "wrench",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {},
	}
	if not work.start(instance_id, ctx):
		_fail("dismount work start: %s" % work.block_reason); return
	work.tick(1.0, {})
	if work.progress_ratio() < 0.1:
		_fail("dismount progress"); return
	# Interrupt mid-work does not yield item
	work.tick(0.1, {"damaged": true})
	if work.status != WorkActionStateScript.STATUS_INTERRUPTED:
		_fail("expected interrupt"); return
	var inv: Dictionary = {}
	var bad = ComponentMountResolverScript.resolve_dismount(work, place, inv)
	if bool(bad.get("ok", false)):
		_fail("interrupted work must not dismount"); return

	# Complete dismount
	work = WorkActionStateScript.new()
	work.configure_action("dismount_component", wa.get_action("dismount_component"))
	work.start(instance_id, ctx)
	work.tick(20.0, {})
	if work.status != WorkActionStateScript.STATUS_COMPLETED:
		_fail("dismount complete"); return
	var res: Dictionary = ComponentMountResolverScript.resolve_dismount(work, place, inv)
	if not bool(res.get("ok", false)):
		_fail("dismount resolve: %s" % str(res.get("reason", ""))); return
	if int(inv.get(item_form, 0)) != 1:
		_fail("inventory should gain item_form %s" % item_form); return
	if place.is_mounted(instance_id):
		_fail("instance should be dismounted"); return
	if place.mounted_count() != mounted_before - 1:
		_fail("mounted_count should drop by 1"); return
	if float(res.get("mass", 0.0)) < 5.0:
		_fail("yield mass should be heavy"); return

	# Double dismount fails
	var work2 = WorkActionStateScript.new()
	work2.configure_action("dismount_component", wa.get_action("dismount_component"))
	work2.start(instance_id, ctx)
	work2.tick(20.0, {})
	var res2: Dictionary = ComponentMountResolverScript.resolve_dismount(work2, place, inv)
	if bool(res2.get("ok", false)):
		_fail("double dismount should fail"); return

	# --- WorkAction remount into same slot ---
	var mount_target: String = "%s|%s|%d|%s" % [room_id, slot_kind, slot_index, item_form]
	var mwork = WorkActionStateScript.new()
	mwork.configure_action("mount_component", wa.get_action("mount_component"))
	if not mwork.start(mount_target, ctx):
		_fail("mount work start: %s" % mwork.block_reason); return
	mwork.tick(20.0, {})
	if mwork.status != WorkActionStateScript.STATUS_COMPLETED:
		_fail("mount complete"); return
	var mres: Dictionary = ComponentMountResolverScript.resolve_mount(
		mwork, place, inv, cat, {
			"room_id": room_id,
			"slot_kind": slot_kind,
			"slot_index": slot_index,
			"item_form": item_form,
		})
	if not bool(mres.get("ok", false)):
		_fail("mount resolve: %s" % str(mres.get("reason", ""))); return
	if int(inv.get(item_form, 0)) != 0:
		_fail("item should be consumed on mount"); return
	if not place.is_mounted(instance_id):
		_fail("instance should be remounted"); return
	if place.mounted_count() != mounted_before:
		_fail("mounted_count should restore"); return

	# Catalog reverse lookup
	var rid: String = cat.component_id_for_item_form(item_form)
	if rid.is_empty():
		_fail("component_id_for_item_form"); return

	print("COMPONENT MOUNT DISMOUNT PASS dismount=true mount=true work=true mass=true round_trip=true")
	quit(0)


func _fail(msg: String) -> void:
	print("COMPONENT MOUNT DISMOUNT FAIL: %s" % msg)
	quit(1)
