extends SceneTree

## Acceptance gate for the live ShipGenerator -> DerelictGenerator path.
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
const REAL_ENCOUNTER_KINDS: Array[String] = [
	"biomatter_lurker",
	"drone_scout",
	"drone_swarm",
	"breach_lurker",
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
	_free_ship(first)
	_free_ship(second)
	if first_layout != second_layout:
		_fail("same seed produced different loaded layout documents")
		return

	print(
		"WORLDGEN WIRED TRAVEL PASS cases=%d biome=%s difficulty=%s deterministic=true rich_objectives=true injected_encounters=true"
		% [generated_cases, TEST_BIOME, TEST_DIFFICULTY]
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
	if objectives.size() <= 1:
		_fail("%s lacks rich gameplay objectives count=%d" % [label, objectives.size()])
		return false
	var layout: Dictionary = ship.get_layout_copy()
	if str(layout.get("biome_id", "")) != TEST_BIOME or str(layout.get("difficulty_id", "")) != TEST_DIFFICULTY:
		_fail("%s lost run context biome=%s difficulty=%s" % [
			label, str(layout.get("biome_id", "")), str(layout.get("difficulty_id", ""))])
		return false
	var encounters_variant: Variant = layout.get("encounters", null)
	if not (encounters_variant is Array) or (encounters_variant as Array).is_empty():
		_fail("%s has no injected encounters" % label)
		return false
	for encounter_variant in encounters_variant as Array:
		if not (encounter_variant is Dictionary):
			_fail("%s has a malformed encounter marker" % label)
			return false
		var encounter: Dictionary = encounter_variant
		var instance_id: String = str(encounter.get("id", ""))
		var encounter_kind: String = str(encounter.get("encounter_kind", ""))
		if not instance_id.begins_with("enc_") or not REAL_ENCOUNTER_KINDS.has(encounter_kind):
			_fail("%s contains fallback encounter marker id=%s kind=%s" % [label, instance_id, encounter_kind])
			return false
	return true


func _free_ship(ship: Node) -> void:
	if ship != null and is_instance_valid(ship):
		ship.free()


func _fail(reason: String) -> void:
	push_error("WORLDGEN WIRED TRAVEL FAIL reason=%s" % reason)
	quit(1)
