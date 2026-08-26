extends SceneTree

## Acceptance gate for the live ShipGenerator -> one ProcgenBundle -> loader path.
## Marker: WORLDGEN WIRED TRAVEL PASS

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

const TEST_BIOME: String = "breach_field"
const TEST_DIFFICULTY: String = "deep_dive"
const TEST_SEEDS: Array[int] = [1701, 1702, 1703]
const SIZES: Array[int] = [
	ShipBlueprintScript.Size.LIFE_BOAT,
	ShipBlueprintScript.Size.SMALL,
	ShipBlueprintScript.Size.MEDIUM,
]
const CONDITIONS: Array[int] = [
	ShipBlueprintScript.Condition.PRISTINE,
	ShipBlueprintScript.Condition.DAMAGED,
	ShipBlueprintScript.Condition.WRECKED,
]
func _initialize() -> void:
	if not ClassDB.class_exists("DerelictGenerator"):
		_fail("DerelictGenerator class unavailable")
		return
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()
	generator.configure_run_context(TEST_BIOME, TEST_DIFFICULTY)
	var generated_cases: int = 0

	for size_index in range(SIZES.size()):
		for condition_index in range(CONDITIONS.size()):
			var size: int = SIZES[size_index]
			var condition: int = CONDITIONS[condition_index]
			var seed_value: int = TEST_SEEDS[size_index] + condition_index * 100
			var label: String = "size=%d condition=%d seed=%d" % [size, condition, seed_value]
			var ship: Node3D = generator.generate_from_seed(seed_value, size, condition)
			if not _assert_ship(label, ship):
				_free_ship(ship)
				return
			if generator.last_outcome != "generated" or not generator.last_error.is_empty():
				_fail("%s generator outcome=%s error=%s" % [label, generator.last_outcome, generator.last_error])
				_free_ship(ship)
				return
			generated_cases += 1
			_free_ship(ship)

	var determinism_seed: int = 424242
	var first: Node3D = generator.generate_from_seed(
			determinism_seed,
			ShipBlueprintScript.Size.MEDIUM,
			ShipBlueprintScript.Condition.DAMAGED,
	)
	var second: Node3D = generator.generate_from_seed(
			determinism_seed,
			ShipBlueprintScript.Size.MEDIUM,
			ShipBlueprintScript.Condition.DAMAGED,
	)
	if not _assert_ship("determinism_a", first) or not _assert_ship("determinism_b", second):
		_free_ship(first)
		_free_ship(second)
		return
	var first_layout: String = JSON.stringify(first.get_layout_copy())
	var second_layout: String = JSON.stringify(second.get_layout_copy())
	var first_gameplay: String = JSON.stringify(first.gameplay_doc)
	var second_gameplay: String = JSON.stringify(second.gameplay_doc)
	_free_ship(first)
	_free_ship(second)
	if first_layout != second_layout or first_gameplay != second_gameplay:
		_fail("same seed produced different bundle-derived loader documents")
		return
	if generator.migration_oracle_invocations != 0:
		_fail("production generation invoked migration oracle count=%d" % generator.migration_oracle_invocations)
		return

	print(
		"WORLDGEN WIRED TRAVEL PASS cases=%d difficulty=%s deterministic=true bundle_authoritative=true oracle_invocations=0"
		% [generated_cases, TEST_DIFFICULTY]
	)
	quit(0)


func _assert_ship(label: String, ship: Node3D) -> bool:
	if ship == null:
		_fail("%s returned null" % label)
		return false
	if not ship.has_method("has_loaded_ship") or not ship.has_loaded_ship():
		_fail("%s did not report a loaded ship" % label)
		return false
	var structure: Node = ship.get_node_or_null("StructuralRoot")
	if structure == null or structure.get_child_count() <= 0:
		_fail("%s has no structural geometry" % label)
		return false
	var start: Vector3 = ship.get_start_transform().origin
	var goal: Vector3 = ship.get_goal_position()
	if start == Vector3.INF or goal == Vector3.INF:
		_fail("%s has invalid start/goal start=%s goal=%s" % [label, str(start), str(goal)])
		return false
	var objectives: Array = ship.get_objective_specs_copy()
	var gameplay_objectives: Variant = ship.gameplay_doc.get("objectives", null)
	if objectives.is_empty() or not gameplay_objectives is Array \
			or objectives.size() != (gameplay_objectives as Array).size():
		_fail("%s changed authoritative objective count loaded=%d bundle=%s" % [label, objectives.size(), str(gameplay_objectives)])
		return false
	var layout: Dictionary = ship.get_layout_copy()
	if not str(layout.get("biome_id", "")).is_empty() or str(layout.get("difficulty_id", "")) != TEST_DIFFICULTY:
		_fail("%s bridge mutated biome or lost Rust request difficulty biome=%s difficulty=%s" % [
			label, str(layout.get("biome_id", "")), str(layout.get("difficulty_id", ""))])
		return false
	var encounters_variant: Variant = layout.get("encounters", null)
	if not encounters_variant is Array or not _encounters_are_authoritative(encounters_variant, ship.gameplay_doc):
		_fail("%s lost authoritative bundle encounter provenance" % label)
		return false
	var gameplay_loot: Variant = ship.gameplay_doc.get("loot_containers", null)
	if not gameplay_loot is Array or ship.get_loot_container_specs_copy().size() != (gameplay_loot as Array).size():
		_fail("%s changed authoritative loot-container count" % label)
		return false
	return true


func _encounters_are_authoritative(encounters: Array, gameplay: Dictionary) -> bool:
	var blueprints: Dictionary = {}
	for blueprint_value in gameplay.get("creature_blueprints", []):
		if not blueprint_value is Dictionary:
			return false
		blueprints[str((blueprint_value as Dictionary).get("id", ""))] = blueprint_value
	var selected_spawns: Dictionary = {}
	for decision_value in gameplay.get("gameplay_decisions", []):
		if decision_value is Dictionary and str((decision_value as Dictionary).get("domain", "")) == "encounter" \
				and bool((decision_value as Dictionary).get("accepted", false)):
			selected_spawns[str((decision_value as Dictionary).get("selected_id", ""))] = true
	for encounter_value in encounters:
		if not encounter_value is Dictionary:
			return false
		var encounter: Dictionary = encounter_value
		var spawn_id: String = str(encounter.get("spawn_id", ""))
		var blueprint_id: String = str(encounter.get("blueprint_id", ""))
		var blueprint_value: Variant = encounter.get("creature_blueprint", null)
		if spawn_id.is_empty() or str(encounter.get("id", "")) != spawn_id \
				or str(encounter.get("decision_id", "")).is_empty() \
				or not selected_spawns.has(spawn_id) or not blueprints.has(blueprint_id) \
				or not blueprint_value is Dictionary \
				or str((blueprint_value as Dictionary).get("id", "")) != blueprint_id \
				or not encounter.get("generated_items", null) is Array \
				or not encounter.get("asset_ids", null) is Array or (encounter.asset_ids as Array).is_empty() \
				or not encounter.get("presentation_binding_ids", null) is Array or (encounter.presentation_binding_ids as Array).is_empty() \
				or encounter.has("difficulty_tier") or encounter.has("encounter_table_id"):
			return false
	return true


func _free_ship(ship: Node) -> void:
	if ship != null and is_instance_valid(ship):
		ship.free()


func _fail(reason: String) -> void:
	push_error("WORLDGEN WIRED TRAVEL FAIL reason=%s" % reason)
	quit(1)
