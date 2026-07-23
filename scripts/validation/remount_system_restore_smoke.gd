extends SceneTree

## Strip linked component damages sub; remount restores to operational floor (not full heal).
## Marker: REMOUNT SYSTEM RESTORE PASS damage=true remount=true floor=true no_full=true

const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentMountResolverScript := preload("res://scripts/systems/component_mount_resolver.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")


func _initialize() -> void:
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), 0, 0)
	var sub = mgr.systems["power"].get_subcomponent("power_distribution")
	if sub == null:
		_fail("sub missing"); return
	sub.health = 1.0
	var cat = ComponentCatalogScript.new()
	cat.load_default()
	var place = ComponentPlacementStateScript.new()
	place.placed = [{
		"component_instance_id": "eng_wall_0",
		"component_id": "reactor_console",
		"room_id": "eng",
		"slot_kind": "wall",
		"slot_index": 0,
		"item_form": "reactor_console",
		"mass": 15.0,
		"linked_system": "power",
		"linked_subcomponent": "power_distribution",
		"mounted": true,
	}]
	var wa = WorkActionCatalogScript.new()
	wa.load_default()
	var work = WorkActionStateScript.new()
	work.configure_action("dismount_component", wa.get_action("dismount_component"))
	work.start("eng_wall_0", {
		"tool_class": "wrench", "skill_id": "salvage", "skill_level": 0,
		"inventory": {"wrench": 1},
	})
	work.tick(99.0, {})
	var inv: Dictionary = {}
	var dres: Dictionary = ComponentMountResolverScript.resolve_dismount(work, place, inv)
	if not bool(dres.get("ok", false)):
		_fail("dismount"); return
	mgr.damage_subcomponent("power", "power_distribution", 1.0)
	if float(sub.health) > 0.001:
		_fail("expected zero after strip"); return
	var work2 = WorkActionStateScript.new()
	work2.configure_action("mount_component", wa.get_action("mount_component"))
	work2.start("eng|wall|0|reactor_console", {
		"tool_class": "wrench", "skill_id": "salvage", "skill_level": 0,
		"inventory": {"reactor_console": 1, "wrench": 1},
	})
	work2.tick(99.0, {})
	var inv2: Dictionary = {"reactor_console": 1}
	var mres: Dictionary = ComponentMountResolverScript.resolve_mount(work2, place, inv2, cat, {})
	if not bool(mres.get("ok", false)):
		_fail("remount"); return
	if not mgr.restore_subcomponent_on_remount("power", "power_distribution", 0.55):
		_fail("restore call"); return
	if float(sub.health) < 0.54:
		_fail("expected floor health got %s" % str(sub.health)); return
	if float(sub.health) > 0.56:
		_fail("should not full-heal got %s" % str(sub.health)); return
	if not sub.is_functional():
		_fail("should be functional at floor"); return
	print("REMOUNT SYSTEM RESTORE PASS damage=true remount=true floor=true no_full=true")
	quit(0)


func _fail(msg: String) -> void:
	print("REMOUNT SYSTEM RESTORE FAIL: %s" % msg)
	quit(1)
