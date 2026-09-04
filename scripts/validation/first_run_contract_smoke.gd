extends SceneTree

## Task 2.3: first-run derelict beat contract.
## Marker: FIRST RUN CONTRACT PASS

const FirstRunContractScript: GDScript = preload("res://scripts/procgen/first_run_contract.gd")
const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript: GDScript = preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript: GDScript = preload("res://scripts/procgen/gameplay_slice_builder.gd")

const BIOME_ID: String = "breach_field"
const DIFFICULTY_ID: String = "standard"

func _initialize() -> void:
	var contract = FirstRunContractScript.new()
	if not contract.load_contract():
		_fail("contract did not load")
		return
	if not _assert_structural_hazard_cases(contract):
		_fail("structural hazard contract cases failed")
		return
	var generator = ShipLayoutGeneratorScript.new()
	var slice_builder = GameplaySliceBuilderScript.new()
	var validated_seeds: Array[int] = []
	for seed_value in [42, 777]:
		var blueprint = ShipBlueprintScript.new(1, 2, seed_value)
		var layout: Dictionary = generator.generate_with_options(
			blueprint,
			{},
			BIOME_ID,
			DIFFICULTY_ID,
			true
		)
		if layout.is_empty():
			continue
		var gameplay_slice: Dictionary = slice_builder.build(layout)
		if contract.validate(layout, gameplay_slice):
			validated_seeds.append(seed_value)
	if validated_seeds.is_empty():
		_fail("neither preferred seed satisfies the first-run beat")
		return
	var picked_seed: int = contract.pick_seed(func(seed_value: int) -> Dictionary:
		var blueprint = ShipBlueprintScript.new(1, 2, seed_value)
		var layout: Dictionary = generator.generate_with_options(blueprint, {}, BIOME_ID, DIFFICULTY_ID, true)
		return {"layout": layout, "gameplay_slice": slice_builder.build(layout)}
	)
	if picked_seed != validated_seeds[0]:
		_fail("pick_seed selected %d expected %d" % [picked_seed, validated_seeds[0]])
		return
	var fallback_seed: int = contract.pick_seed({})
	if fallback_seed != 42:
		_fail("pick_seed fallback selected %d expected 42" % fallback_seed)
	print("FIRST RUN CONTRACT PASS seed=%d validated=%s fallback=%d" % [picked_seed, str(validated_seeds), fallback_seed])
	quit(0)

func _assert_structural_hazard_cases(contract) -> bool:
	var mapped_layout: Dictionary = _hazard_case_layout(["airlock_01", "reactor_01"], ["reactor_01"])
	var gameplay: Dictionary = {"loot_containers": [{}]}
	if not contract.validate(mapped_layout, gameplay):
		return false

	var unmapped_layout: Dictionary = _hazard_case_layout(["airlock_01", "corridor_01"], ["corridor_01"])
	if contract.validate(unmapped_layout, gameplay):
		return false

	var empty_path_layout: Dictionary = _hazard_case_layout([], ["reactor_01"])
	if contract.validate(empty_path_layout, gameplay):
		return false
	return true


func _hazard_case_layout(critical_path: Array, breach_room_ids: Array) -> Dictionary:
	return {
		"biome_id": BIOME_ID,
		"difficulty_id": DIFFICULTY_ID,
		"critical_path": critical_path,
		"encounters": [{}],
		"rooms": [
			{"id": "airlock_01", "room_role": "airlock"},
			{"id": "reactor_01", "room_role": "reactor"},
			{"id": "corridor_01", "room_role": "corridor"},
		],
		"structural_plan": {
			"edges": {
				"edge:breach": {"kind": "BREACH", "room_ids": breach_room_ids},
			},
		},
	}


func _fail(reason: String) -> void:
	push_error("FIRST RUN CONTRACT FAIL reason=%s" % reason)
	quit(1)
