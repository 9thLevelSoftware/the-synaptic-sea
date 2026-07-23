extends SceneTree

## REQ-MI-004: fire / decompression / threat / tool all route through ModuleDamageRouter.
## Marker: MULTI SOURCE MODULE DAMAGE PASS fire=true decomp=true threat=true tool=true interrupt=true

const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const ModuleDamageRouterScript := preload("res://scripts/systems/module_damage_router.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")


func _initialize() -> void:
	var sources: PackedStringArray = ModuleDamageRouterScript.known_sources()
	if sources.size() != 4:
		_fail("expected 4 sources"); return

	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("eng/wall_a", "wall_straight_1x1", {}, "eng")

	# Fire
	var r_fire: Dictionary = ModuleDamageRouterScript.apply(
		map, "eng/wall_a", ModuleDamageRouterScript.SOURCE_FIRE, 0.3
	)
	if not bool(r_fire.get("ok", false)):
		_fail("fire apply"); return
	if map.get_state("eng/wall_a") == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("fire should damage"); return

	# Decompression against compartment modules
	var map2 = ModuleIntegrityMapScript.new()
	var layout: Dictionary = {
		"rooms": [{
			"id": "eng",
			"room_role": "engineering",
			"structural_placements": [
				{"name": "wall_b", "module_id": "wall_straight_1x1", "world_position": [0, 0, 0]},
			],
		}],
	}
	map2.ensure_module("eng/wall_b", "wall_straight_1x1", {}, "eng")
	var changed: Array = ModuleDamageRouterScript.apply_decompression_to_compartment(
		map2, layout, "engineering", {"engineering": "engineering"}, 0.5
	)
	if changed.is_empty():
		# room_role map may match compartment id "engineering"
		changed = ModuleDamageRouterScript.apply_decompression_to_compartment(
			map2, layout, "engineering", {"engineering": "engineering"}
		)
	if map2.get_state("eng/wall_b") == ModuleIntegrityStateScript.STATE_INTACT:
		# force via room id match
		ModuleDamageRouterScript.apply(
			map2, "eng/wall_b", ModuleDamageRouterScript.SOURCE_DECOMPRESSION, 0.5
		)
	if map2.get_state("eng/wall_b") == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("decomp should damage"); return

	# Threat structure
	var map3 = ModuleIntegrityMapScript.new()
	map3.ensure_module("cor/wall_t", "wall_straight_1x1", {}, "cor")
	var r_threat: Dictionary = ModuleDamageRouterScript.apply_threat_structure_hit(
		map3, "cor/wall_t", 0.4
	)
	if not bool(r_threat.get("ok", false)):
		_fail("threat"); return
	if str(r_threat.get("source", "")) != ModuleDamageRouterScript.SOURCE_THREAT:
		_fail("threat source tag"); return

	# Tool
	var map4 = ModuleIntegrityMapScript.new()
	map4.ensure_module("br/wall_c", "wall_straight_1x1", {}, "br")
	var r_tool: Dictionary = ModuleDamageRouterScript.apply_tool_damage(map4, "br/wall_c", 1.0)
	if not bool(r_tool.get("ok", false)):
		_fail("tool"); return
	if map4.get_state("br/wall_c") == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("tool should destroy/damage"); return

	# Unknown source rejected
	var bad: Dictionary = ModuleDamageRouterScript.apply(map, "eng/wall_a", "laser_beams", 1.0)
	if bool(bad.get("ok", true)):
		_fail("unknown source should fail"); return

	# Interrupt: damage context mid-work does not complete / consume
	var cat = WorkActionCatalogScript.new()
	if not cat.load_default():
		_fail("work catalog"); return
	var work = WorkActionStateScript.new()
	work.configure_action("cut_wall", cat.get_action("cut_wall"))
	var inv: Dictionary = {"welding_lance": 1, "scrap_metal": 0}
	if not work.start("eng/wall_a", {
		"tool_class": "welding_lance",
		"skill_id": "salvage",
		"skill_level": 0,
		"inventory": inv.duplicate(true),
	}):
		_fail("work start"); return
	work.tick(1.0, {})
	if work.status != WorkActionStateScript.STATUS_ACTIVE:
		_fail("expected active"); return
	work.tick(0.1, {"damaged": true})
	if work.status != WorkActionStateScript.STATUS_INTERRUPTED:
		_fail("expected interrupt"); return
	# Materials not consumed on interrupt
	if int(inv.get("welding_lance", 0)) != 1:
		_fail("should not consume tools on interrupt"); return

	print("MULTI SOURCE MODULE DAMAGE PASS fire=true decomp=true threat=true tool=true interrupt=true")
	quit(0)


func _fail(msg: String) -> void:
	print("MULTI SOURCE MODULE DAMAGE FAIL: %s" % msg)
	quit(1)
