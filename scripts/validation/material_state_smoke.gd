extends SceneTree

const MaterialStateScript := preload("res://scripts/systems/material_state.gd")

## MATERIAL STATE PASS
## Validates MaterialState: definitions load, quality tracking, average
## ingredient quality computation, and save/load round-trip.

func _initialize() -> void:
	var mat = MaterialStateScript.new()
	var defined: int = mat.count_defined()
	assert(defined >= 30, "Expected >=30 materials, got %d" % defined)

	# Test known materials
	assert(mat.has_definition("scrap_metal"), "scrap_metal should be defined")
	assert(mat.has_definition("circuit_board"), "circuit_board should be defined")
	assert(mat.has_definition("nanite_slurry"), "nanite_slurry should be defined")
	assert(mat.get_display_name("scrap_metal") == "Scrap Metal", "display name mismatch")
	assert(mat.get_category("circuit_board") == "part", "category mismatch")
	assert(mat.get_weight("purified_water") == 1.0, "weight mismatch")
	assert(mat.get_max_stack("graphene_sheet") == 50, "max_stack mismatch")

	# Quality tracking
	mat.set_quality("scrap_metal", 0.75)
	assert(absf(mat.get_quality("scrap_metal") - 0.75) < 0.001, "quality set/get failed")
	assert(absf(mat.get_quality("circuit_board") - mat.get_base_quality("circuit_board")) < 0.001, "fallback base quality failed")

	# Average ingredient quality
	mat.set_quality("scrap_metal", 0.8)
	mat.set_quality("adhesive_paste", 0.6)
	var avg: float = mat.average_ingredient_quality({"scrap_metal": 2, "adhesive_paste": 1})
	var expected_avg: float = (0.8 * 2.0 + 0.6 * 1.0) / 3.0
	assert(absf(avg - expected_avg) < 0.001, "avg ingredient quality wrong: %.3f vs %.3f" % [avg, expected_avg])

	# Round-trip summary
	var summary: Dictionary = mat.get_summary()
	assert(summary.get("defined_count", 0) >= 30, "summary defined_count wrong")
	var mat2 = MaterialStateScript.new()
	assert(mat2.apply_summary(summary), "apply_summary should return true")
	assert(absf(mat2.get_quality("scrap_metal") - 0.8) < 0.001, "round-trip quality failed")

	print("MATERIAL STATE PASS defined=%d quality_tracked=true avg=true round_trip=true" % defined)
	quit()
