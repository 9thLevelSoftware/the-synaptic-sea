extends SceneTree

## RED/REGRESSION smoke for the worldgen integration contract gap.
##
## Background: worldgen v2 (DerelictGenerator.export_layout_json) emits a
## layout whose `prototype` field is the literal String "worldgen" instead of
## a Dictionary with start_room/goal_room. Downstream consumers
## (GameplaySliceBuilder.build at gameplay_slice_builder.gd:51 and
## GeneratedShipLoader.load_from_documents at generated_ship_loader.gd:159)
## both type-assert `var x: Dictionary = layout.get("prototype", {})`, which
## raises a runtime error Godot silently swallows. The resulting empty slice
## then makes ShipGenerator._generate_via_worldgen bail out with
## "SHIP GENERATOR FAIL worldgen gameplay slice builder returned no
## objectives" and the world_save_anywhere_smoke's first travel call fails.
##
## The root-cause fix lives in ShipGenerator._generate_via_worldgen
## (scripts/procgen/ship_generator.gd): the prototype is promoted to a
## Dictionary before any consumer sees it. This test exercises that
## normalization by driving ShipGenerator end-to-end against the live
## DerelictGenerator and asserting the resulting ship is non-null and
## reports rich gameplay objectives (the symptom that broke the smoke).
##
## Marker: WORLDGEN PROTOTYPE NORMALIZATION PASS

const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")


func _initialize() -> void:
	if not ClassDB.class_exists("DerelictGenerator"):
		push_error("WORLDGEN PROTOTYPE NORMALIZATION FAIL DerelictGenerator unavailable")
		quit(1)
		return

	# Confirm the upstream contract gap exists (the RED half). If this
	# assertion starts failing the worldgen contract changed and the
	# consumer-side fixes may be redundant — keep this honest.
	var gen: Object = ClassDB.instantiate("DerelictGenerator")
	var params: Dictionary = {
		"archetype_id": "shuttle",
		"intactness_override": 9500,
	}
	var layout_text: String = str(gen.export_layout_json(42, params, "ship_structural_v0"))
	var layout_variant: Variant = JSON.parse_string(layout_text)
	if not (layout_variant is Dictionary):
		push_error("WORLDGEN PROTOTYPE NORMALIZATION FAIL layout not a Dictionary")
		quit(1)
		return
	var layout_doc: Dictionary = layout_variant
	var raw_proto: Variant = layout_doc.get("prototype", null)
	if raw_proto is Dictionary:
		print("WORLDGEN PROTOTYPE NORMALIZATION SKIP worldgen already emits Dictionary prototype")
		# Upstream contract changed: nothing to prove here.
		print("WORLDGEN PROTOTYPE NORMALIZATION PASS skipped=true")
		quit(0)
		return
	if str(raw_proto) != "worldgen":
		push_error("WORLDGEN PROTOTYPE NORMALIZATION FAIL unexpected prototype shape kind=%s val=%s" % [typeof(raw_proto), str(raw_proto)])
		quit(1)
		return

	# Drive the full ShipGenerator path the smoke exercises. The fix in
	# ShipGenerator._generate_via_worldgen must produce a non-null ship
	# and a rich gameplay slice.
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()
	generator.configure_run_context("breach_field", "deep_dive")
	var ship: Node3D = generator.generate_from_seed(42, 0, 1)
	if ship == null:
		push_error("WORLDGEN PROTOTYPE NORMALIZATION FAIL generate_from_seed returned null after fix")
		quit(1)
		return
	if not ship.has_method("has_loaded_ship") or not ship.has_loaded_ship():
		push_error("WORLDGEN PROTOTYPE NORMALIZATION FAIL generated ship has no loaded geometry")
		quit(1)
		return
	var objectives: Array = ship.get_objective_specs_copy()
	if objectives.size() < 2:
		push_error("WORLDGEN PROTOTYPE NORMALIZATION FAIL ship lacks rich objectives count=%d" % objectives.size())
		quit(1)
		return
	ship.free()

	print("WORLDGEN PROTOTYPE NORMALIZATION PASS raw_proto=%s objectives=%d" % [str(raw_proto), objectives.size()])
	quit(0)
