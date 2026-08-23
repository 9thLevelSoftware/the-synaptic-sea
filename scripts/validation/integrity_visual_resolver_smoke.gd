extends SceneTree

## Smoke coverage for integrity visual resolution and P0 structural kind classification.
## Marker: INTEGRITY VISUAL RESOLVER PASS resolver=true consequences=true structural=true

const IntegrityVisualResolverScript: GDScript = preload("res://scripts/systems/integrity_visual_resolver.gd")
const ModuleIntegrityConsequencesScript: GDScript = preload("res://scripts/systems/module_integrity_consequences.gd")
const ModuleIntegrityMapScript: GDScript = preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityStateScript: GDScript = preload("res://scripts/systems/module_integrity_state.gd")


func _initialize() -> void:
	if IntegrityVisualResolverScript == null:
		_fail("IntegrityVisualResolver failed to load")
		return

	var wrapper := Node3D.new()
	var visual := Node3D.new()
	visual.name = "Visual"
	wrapper.add_child(visual)
	var intact := Node3D.new()
	intact.name = "VisualInstance_Intact"
	var damaged := Node3D.new()
	damaged.name = "VisualInstance_Damaged"
	var breached := Node3D.new()
	breached.name = "VisualInstance_Breached"
	visual.add_child(intact)
	visual.add_child(damaged)
	visual.add_child(breached)
	get_root().add_child(wrapper)
	for state in [
		ModuleIntegrityStateScript.STATE_INTACT,
		ModuleIntegrityStateScript.STATE_DAMAGED,
		ModuleIntegrityStateScript.STATE_BREACHED,
	]:
		if not IntegrityVisualResolverScript.apply_visual_state(wrapper, state):
			_fail("resolver did not apply state=%s" % state)
			wrapper.queue_free()
			return
		if state == ModuleIntegrityStateScript.STATE_INTACT and not intact.visible:
			_fail("intact visual should be visible")
			wrapper.queue_free()
			return
		if state == ModuleIntegrityStateScript.STATE_DAMAGED and not damaged.visible:
			_fail("damaged visual should be visible")
			wrapper.queue_free()
			return
		if state == ModuleIntegrityStateScript.STATE_BREACHED and not breached.visible:
			_fail("breached visual should be visible")
			wrapper.queue_free()
			return
	if not IntegrityVisualResolverScript.apply_visual_state(
			wrapper, ModuleIntegrityStateScript.STATE_DESTROYED):
		_fail("destroyed state should hide variant visuals")
		wrapper.queue_free()
		return
	if intact.visible or damaged.visible or breached.visible:
		_fail("destroyed state should hide all variant visuals")
		wrapper.queue_free()
		return
	wrapper.queue_free()

	for state in [
		ModuleIntegrityStateScript.STATE_INTACT,
		ModuleIntegrityStateScript.STATE_DAMAGED,
		ModuleIntegrityStateScript.STATE_BREACHED,
		ModuleIntegrityStateScript.STATE_DESTROYED,
	]:
		var consequence: Dictionary = ModuleIntegrityConsequencesScript.consequence_for_state(state)
		if not consequence.has("mesh_suffix") or not consequence.has("modulate"):
			_fail("consequence missing visual fields for state=%s" % state)
			return

	var p0_kinds: Array[String] = [
		"floor_1x1",
		"corridor_floor_1x1",
		"pillar_support_1x1",
		"ramp_up_1x2",
		"wall_straight_1x1",
		"doorway_frame_open_1x1",
	]
	for kind in p0_kinds:
		if not ModuleIntegrityConsequencesScript.is_structural_kind(kind):
			_fail("P0 kind not structural: %s" % kind)
			return

	var structural_map = ModuleIntegrityMapScript.new()
	var layout: Dictionary = {
		"rooms": [{
			"id": "smoke_room",
			"structural_placements": [
				{"module_id": "floor_1x1", "name": "floor_a"},
				{"module_id": "pillar_support_1x1", "name": "pillar_a"},
				{"module_id": "doorway_frame_open_1x1", "name": "door_a"},
			],
		}],
	}
	var registered: int = ModuleIntegrityConsequencesScript.seed_structural_map_from_layout(
		structural_map, layout)
	if registered != 3 or not structural_map.has_module("smoke_room/floor_a"):
		_fail("structural seed path missed P0 modules: registered=%d" % registered)
		return

	print("INTEGRITY VISUAL RESOLVER PASS resolver=true consequences=true structural=true")
	quit(0)


func _fail(message: String) -> void:
	print("INTEGRITY VISUAL RESOLVER FAIL: %s" % message)
	quit(1)
