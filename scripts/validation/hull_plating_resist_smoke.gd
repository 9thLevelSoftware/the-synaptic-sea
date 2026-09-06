extends SceneTree

## Hub hull plating reduces ModuleDamageRouter threat amount; pure resist math.
## Marker: HULL PLATING RESIST PASS resist=true reduced=true zero_away=true

const ModuleDamageRouterScript := preload("res://scripts/systems/module_damage_router.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")


func _initialize() -> void:
	var mod = ShipModificationStateScript.new()
	mod.configure({"power_supply": 200.0, "power_demand_baseline": 0.0})
	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		_fail("catalog"); return
	var layout: Dictionary = {"rooms": [{
		"id": "cargo",
		"room_role": "cargo",
		"wall_slots": [
			{"cell": [0, 0], "component_slot_profile_id": "wall_utility_mount_v1"},
			{"cell": [0, 1], "component_slot_profile_id": "wall_utility_mount_v1"},
		],
		"center_slots": [],
	}]}
	var placement = ComponentPlacementStateScript.new()
	placement.populate(layout, catalog, 1)
	placement.dismount("cargo_wall_0")
	placement.dismount("cargo_wall_1")
	if not mod.bind_physical_slots("hub", placement.get_physical_slot_descriptors("hub"), catalog, placement):
		_fail("bind"); return
	if mod.structure_damage_resist() > 0.001:
		_fail("expected zero resist before plating"); return
	var inv: Dictionary = {"plating_plate": 2}
	var r1: Dictionary = mod.install("cargo_wall_0", "hull_plating", "plating_plate", inv)
	if not bool(r1.get("ok", false)):
		_fail("install plating"); return
	var resist: float = mod.structure_damage_resist()
	if resist < 0.09 or resist > 0.11:
		_fail("expected ~0.10 resist got %s" % str(resist)); return
	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("eng/wall_a", "wall")
	var full: Dictionary = ModuleDamageRouterScript.apply_threat_structure_hit(map, "eng/wall_a", 0.5, "", 0.0)
	var map2 = ModuleIntegrityMapScript.new()
	map2.ensure_module("eng/wall_a", "wall")
	var plated: Dictionary = ModuleDamageRouterScript.apply_threat_structure_hit(map2, "eng/wall_a", 0.5, "", resist)
	if not bool(full.get("ok", false)) or not bool(plated.get("ok", false)):
		_fail("apply failed"); return
	var a_full: float = float(full.get("amount", 0.0))
	var a_plat: float = float(plated.get("amount", 0.0))
	if a_plat >= a_full:
		_fail("plated amount should be lower full=%s plat=%s" % [str(a_full), str(a_plat)]); return
	if absf(a_plat - a_full * (1.0 - resist)) > 0.001:
		_fail("resist math mismatch"); return
	# Second plate stacks toward cap
	mod.install("cargo_wall_1", "hull_plating", "plating_plate", inv)
	if mod.structure_damage_resist() < 0.19:
		_fail("stacked resist"); return
	print("HULL PLATING RESIST PASS resist=true reduced=true zero_away=true")
	quit(0)


func _fail(msg: String) -> void:
	print("HULL PLATING RESIST FAIL: %s" % msg)
	quit(1)
