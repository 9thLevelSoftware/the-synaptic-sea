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

func _fail(reason: String) -> void:
	push_error("FIRST RUN CONTRACT FAIL reason=%s" % reason)
	quit(1)
