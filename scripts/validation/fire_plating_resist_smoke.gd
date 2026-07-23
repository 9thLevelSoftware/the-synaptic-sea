extends SceneTree

## Hub plating scales fire module damage rate (same resist curve as structure).
## Marker: FIRE PLATING RESIST PASS resist=true reduced=true

const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityConsequencesScript := preload("res://scripts/systems/module_integrity_consequences.gd")
const ShipModificationStateScript := preload("res://scripts/systems/ship_modification_state.gd")


func _initialize() -> void:
	var layout: Dictionary = {
		"rooms": [{
			"id": "eng",
			"room_role": "engineering",
			"structural_placements": [
				{"module_id": "wall_straight_1x1", "name": "wall_a", "world_position": [0, 0, 0]}
			]
		}]
	}
	var roles: Dictionary = {"engineering": "eng_comp"}
	var burning: Dictionary = {"eng_comp": 1.0}
	var map1 = ModuleIntegrityMapScript.new()
	ModuleIntegrityConsequencesScript.seed_map_from_layout(map1, layout)
	var map2 = ModuleIntegrityMapScript.new()
	ModuleIntegrityConsequencesScript.seed_map_from_layout(map2, layout)
	var full_rate: float = ModuleIntegrityConsequencesScript.FIRE_MODULE_DAMAGE_PER_INTENSITY
	ModuleIntegrityConsequencesScript.apply_fire_damage(map1, layout, burning, roles, 1.0, full_rate)
	var mod = ShipModificationStateScript.new()
	mod.configure({"power_supply": 200.0})
	var inv: Dictionary = {"hull_plate_kit": 1}
	mod.install("p0", "hull_plating", "hull_plate_kit", inv, 0.0, 5.0, "hub", true)
	var resist: float = mod.structure_damage_resist()
	if resist < 0.09:
		_fail("resist"); return
	var reduced_rate: float = full_rate * (1.0 - resist)
	ModuleIntegrityConsequencesScript.apply_fire_damage(map2, layout, burning, roles, 1.0, reduced_rate)
	var m1 = map1.get_module("eng/wall_a")
	var m2 = map2.get_module("eng/wall_a")
	if m1 == null or m2 == null:
		_fail("modules missing"); return
	if float(m2.integrity) <= float(m1.integrity):
		_fail("plated should take less fire dmg full=%s plated=%s" % [str(m1.integrity), str(m2.integrity)]); return
	print("FIRE PLATING RESIST PASS resist=true reduced=true")
	quit(0)


func _fail(msg: String) -> void:
	print("FIRE PLATING RESIST FAIL: %s" % msg)
	quit(1)
