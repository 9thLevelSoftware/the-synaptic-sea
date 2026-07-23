extends SceneTree

## Hub hull plating reduces ModuleDamageRouter threat amount; pure resist math.
## Marker: HULL PLATING RESIST PASS resist=true reduced=true zero_away=true

const ModuleDamageRouterScript := preload("res://scripts/systems/module_damage_router.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")


func _initialize() -> void:
	var mod = ShipModificationStateScript.new()
	mod.configure({"power_supply": 200.0, "power_demand_baseline": 0.0})
	if mod.structure_damage_resist() > 0.001:
		_fail("expected zero resist before plating"); return
	var inv: Dictionary = {"hull_plate_kit": 2}
	var r1: Dictionary = mod.install("hull_0", "hull_plating", "hull_plate_kit", inv, 0.0, 5.0, "hub", true)
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
	mod.install("hull_1", "hull_plating", "hull_plate_kit", inv, 0.0, 5.0, "hub", true)
	if mod.structure_damage_resist() < 0.19:
		_fail("stacked resist"); return
	print("HULL PLATING RESIST PASS resist=true reduced=true zero_away=true")
	quit(0)


func _fail(msg: String) -> void:
	print("HULL PLATING RESIST FAIL: %s" % msg)
	quit(1)
