extends SceneTree

## REQ-CMP-002 follow-on: stripping a linked component damages the ship subcomponent.
## Marker: DISMOUNT SYSTEM DAMAGE PASS link=true damage=true remount_no_autoheal=true

const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentMountResolverScript := preload("res://scripts/systems/component_mount_resolver.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")


func _initialize() -> void:
	var mgr = ShipSystemsManagerScript.new()
	mgr.configure(mgr.load_definitions(), 0, 0)
	if not mgr.systems.has("power"):
		_fail("power system missing"); return
	var sub = mgr.systems["power"].get_subcomponent("power_distribution")
	if sub == null:
		_fail("power_distribution missing"); return
	sub.health = 1.0

	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("catalog"); return
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
	if not work.start("eng_wall_0", {
		"tool_class": "wrench",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {"wrench": 1},
	}):
		_fail("start"); return
	work.tick(99.0, {})
	var inv: Dictionary = {}
	var res: Dictionary = ComponentMountResolverScript.resolve_dismount(work, place, inv)
	if not bool(res.get("ok", false)):
		_fail("dismount resolve"); return
	# Apply the production consequence
	if not mgr.damage_subcomponent(
		str(res.get("linked_system", "")),
		str(res.get("linked_subcomponent", "")),
		1.0
	):
		_fail("damage_subcomponent"); return
	if float(sub.health) > 0.001:
		_fail("expected sub health ~0 got %s" % str(sub.health)); return
	if sub.is_functional():
		_fail("should not be functional"); return
	# Remount does not auto-heal (repair is a separate verb)
	var work2 = WorkActionStateScript.new()
	work2.configure_action("mount_component", wa.get_action("mount_component"))
	work2.start("eng|wall|0|reactor_console", {
		"tool_class": "wrench",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": {"reactor_console": 1, "wrench": 1},
	})
	work2.tick(99.0, {})
	var inv2: Dictionary = {"reactor_console": 1}
	var mres: Dictionary = ComponentMountResolverScript.resolve_mount(work2, place, inv2, cat, {})
	if not bool(mres.get("ok", false)):
		_fail("remount %s" % str(mres)); return
	if float(sub.health) > 0.001:
		_fail("remount should not auto-heal"); return

	print("DISMOUNT SYSTEM DAMAGE PASS link=true damage=true remount_no_autoheal=true")
	quit(0)


func _fail(msg: String) -> void:
	print("DISMOUNT SYSTEM DAMAGE FAIL: %s" % msg)
	quit(1)
