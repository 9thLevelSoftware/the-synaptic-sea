extends SceneTree

## REQ-CS-018 pure-ish smoke: ProductionStation.list_crop_entries + try_plant_crop
## without the full main scene (headless node tree).

const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
const HydroponicsStateScript := preload("res://scripts/systems/hydroponics_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	var inv = InventoryStateScript.new()
	var model = HydroponicsStateScript.new()
	var crops_cfg: Dictionary = {
		"crops": [
			{
				"crop_id": "alien_flora_cultivar",
				"display_name": "Alien Flora Cultivar",
				"produce_item_id": "alien_flora",
				"produce_quantity": 2,
				"growth_seconds": 180.0,
				"water_cost": 3.0,
				"power_cost": 5.0,
				"required_skill_level": 2,
			},
			{
				"crop_id": "hydroponic_greens",
				"display_name": "Hydroponic Greens",
				"produce_item_id": "hydroponic_greens",
				"produce_quantity": 3,
				"growth_seconds": 120.0,
				"water_cost": 2.0,
				"power_cost": 3.0,
				"required_skill_level": 0,
			},
		],
	}
	var st = ProductionStationScript.new()
	get_root().add_child(st)
	st.configure(
		"hydroponics",
		model,
		inv,
		func() -> float: return 999.0,
		func() -> int: return 0,
		crops_cfg,
		Vector3.ZERO,
		1.8,
	)

	# No water: both crops blocked.
	var empty: Array = st.list_crop_entries()
	if empty.size() != 2:
		_fail("expected 2 crop rows, got %d" % empty.size())
		return
	# Sorted by crop_id: alien before hydroponic.
	if str((empty[0] as Dictionary).get("recipe_id", "")) != "alien_flora_cultivar":
		_fail("entries not sorted by crop_id")
		return
	for e in empty:
		if bool((e as Dictionary).get("craftable", false)):
			_fail("empty water should not make crop ready")
			return

	inv.add_item("purified_water", 10)
	var ready: Array = st.list_crop_entries()
	var ready_n: int = 0
	var first_ready: String = ""
	for e in ready:
		if bool((e as Dictionary).get("craftable", false)):
			ready_n += 1
			if first_ready.is_empty():
				first_ready = str((e as Dictionary).get("recipe_id", ""))
		else:
			# Skill 0: alien should be insufficient_skill.
			if str((e as Dictionary).get("recipe_id", "")) == "alien_flora_cultivar":
				if str((e as Dictionary).get("status", "")) != "insufficient_skill":
					_fail("alien should be insufficient_skill at skill 0")
					return
	if ready_n < 1 or first_ready != "hydroponic_greens":
		_fail("expected first ready = hydroponic_greens, ready=%d first=%s" % [ready_n, first_ready])
		return

	if not st.try_plant_crop("hydroponic_greens"):
		_fail("try_plant_crop hydroponic_greens failed")
		return
	if model.state != HydroponicsStateScript.State.PLANTED:
		_fail("model not PLANTED after plant")
		return
	if inv.get_quantity("purified_water") != 8:
		_fail("water not consumed correctly: %d" % inv.get_quantity("purified_water"))
		return
	if st.try_plant_crop("alien_flora_cultivar"):
		_fail("second plant while PLANTED should fail")
		return

	print("HYDROPONICS CROP LIST PASS crops=2 ready=%d first=%s planted=true" % [ready_n, first_ready])
	quit()
