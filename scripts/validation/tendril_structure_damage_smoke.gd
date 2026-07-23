extends SceneTree

## REQ-MI-004: hull_tendril structure_damage routes into ModuleIntegrityMap.
## Marker: TENDRIL STRUCTURE DAMAGE PASS archetype=true hit=true damaged=true

const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const ModuleDamageRouterScript := preload("res://scripts/systems/module_damage_router.gd")
const ThreatAIStateScript := preload("res://scripts/systems/threat_ai_state.gd")


func _initialize() -> void:
	var path: String = "res://data/combat/threat_archetypes.json"
	var text: String = FileAccess.get_file_as_string(path)
	var root: Variant = JSON.parse_string(text)
	if typeof(root) != TYPE_DICTIONARY:
		_fail("archetypes parse"); return
	var tendril: Dictionary = (root as Dictionary).get("hull_tendril", {})
	if float(tendril.get("structure_damage", 0.0)) < 0.1:
		_fail("hull_tendril needs structure_damage"); return

	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("eng/wall_t", "wall_straight_1x1", {}, "eng")

	var threat = ThreatAIStateScript.new()
	threat.configure({
		"instance_id": "t1",
		"archetype_id": "hull_tendril",
		"structure_damage": float(tendril.get("structure_damage", 0.4)),
		"attack_damage": 8.0,
		"world_position": [0.0, 0.0, 0.0],
	})
	if float(threat.structure_damage) <= 0.0:
		_fail("threat structure_damage not loaded"); return

	var res: Dictionary = ModuleDamageRouterScript.apply_threat_structure_hit(
		map, "eng/wall_t", float(threat.structure_damage)
	)
	if not bool(res.get("ok", false)):
		_fail("router apply"); return
	if map.get_state("eng/wall_t") == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("module should take structure damage"); return
	if str(res.get("source", "")) != ModuleDamageRouterScript.SOURCE_THREAT:
		_fail("source tag"); return

	print("TENDRIL STRUCTURE DAMAGE PASS archetype=true hit=true damaged=true")
	quit(0)


func _fail(msg: String) -> void:
	print("TENDRIL STRUCTURE DAMAGE FAIL: %s" % msg)
	quit(1)
