extends SceneTree

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const GameplaySliceBuilderScript := preload("res://scripts/procgen/gameplay_slice_builder.gd")
const StructuralEdgeCompilerScript := preload("res://scripts/procgen/structural_edge_compiler.gd")
const StructuralPlanValidatorScript := preload("res://scripts/procgen/structural_plan_validator.gd")

const LAYOUT_PATH := "res://data/procgen/smoke/seed_000017/layout.json"
const GAMEPLAY_PATH := "res://data/procgen/smoke/seed_000017/gameplay_slice.json"


func _initialize() -> void:
	var blueprint = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM,
		ShipBlueprintScript.Condition.PRISTINE,
		17,
	)
	var layout_generator = ShipLayoutGeneratorScript.new()
	var layout: Dictionary = layout_generator.generate_with_options(blueprint, {}, "", "", false)
	if layout.is_empty():
		_fail("layout generation returned empty")
		return

	var structural_plan: Dictionary = StructuralEdgeCompilerScript.new().compile(layout)
	var verdict: Dictionary = StructuralPlanValidatorScript.new().validate(structural_plan, layout)
	if not bool(verdict.get("ok", false)):
		_fail("structural validation failed: %s" % JSON.stringify(verdict.get("errors", [])))
		return
	layout["structural_plan"] = structural_plan

	var gameplay: Dictionary = GameplaySliceBuilderScript.new().build(layout)
	if gameplay.is_empty() or not (gameplay.get("objectives", []) is Array) or (gameplay.get("objectives", []) as Array).is_empty():
		_fail("gameplay slice returned no objectives")
		return
	var layout_arcs: Variant = layout.get("arc_zones", [])
	var slice_arcs: Variant = gameplay.get("arc_zones", [])
	if (not (layout_arcs is Array) or (layout_arcs as Array).is_empty()) and slice_arcs is Array and not (slice_arcs as Array).is_empty():
		layout["arc_zones"] = (slice_arcs as Array).duplicate(true)

	if not _write_json(LAYOUT_PATH, layout) or not _write_json(GAMEPLAY_PATH, gameplay):
		_fail("could not write refreshed fixture")
		return

	var plan: Dictionary = layout.get("structural_plan", {})
	print(
		"SEED 000017 FIXTURE REFRESH PASS schema=%s rooms=%d objectives=%d floors=%d ceilings=%d sockets=%d placements=%d"
		% [
			str(layout.get("schema_version", "")),
			(layout.get("rooms", []) as Array).size(),
			(gameplay.get("objectives", []) as Array).size(),
			(plan.get("floor_placements", []) as Array).size(),
			(plan.get("ceiling_placements", []) as Array).size(),
			(plan.get("socket_bindings", []) as Array).size(),
			(plan.get("placements", []) as Array).size(),
		]
	)
	quit(0)


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "  "))
	file.close()
	return true


func _fail(reason: String) -> void:
	push_error("SEED 000017 FIXTURE REFRESH FAIL reason=%s" % reason)
	quit(1)
