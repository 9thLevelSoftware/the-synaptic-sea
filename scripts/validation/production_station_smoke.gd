extends SceneTree

## Domain 3 Task 2: ProductionStation drives a stateful production model via interact.
## - IDLE interact starts production (consumes input from inventory).
## - interact while RUNNING is a no-op (production_blocked "in_progress").
## - interact while READY harvests/collects into inventory.
## Validated against BOTH a HydroponicsState and a WaterRecyclerState with a fake inventory.
## Marker: PRODUCTION STATION PASS hydro_harvest=true recycler_collect=true blocked_in_progress=true

const ProductionStationScript := preload("res://scripts/tools/production_station.gd")
const HydroStateScript := preload("res://scripts/systems/hydroponics_state.gd")
const RecyclerStateScript := preload("res://scripts/systems/water_recycler_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

var blocked_in_progress: bool = false
# Keep station references at class scope so _initialize() can free them on BOTH pass and
# fail paths, preventing RID leaks (Area3D + CollisionShape3D + MeshInstance3D allocate
# server-side RIDs at creation; free() is required before quit()).
var _st_hydro    # ProductionStation
var _st_recycler # ProductionStation

func _initialize() -> void:
	var ok_hydro: bool = _test_hydro()
	var ok_recycler: bool = _test_recycler()
	# Free stations unconditionally to avoid leaked RID warnings at headless teardown.
	if is_instance_valid(_st_hydro):
		_st_hydro.free()
	if is_instance_valid(_st_recycler):
		_st_recycler.free()
	if ok_hydro and ok_recycler and blocked_in_progress:
		print("PRODUCTION STATION PASS hydro_harvest=true recycler_collect=true blocked_in_progress=true")
		quit(0)
	else:
		push_error("PRODUCTION STATION FAIL hydro=%s recycler=%s blocked=%s" % [str(ok_hydro), str(ok_recycler), str(blocked_in_progress)])
		quit(1)

func _test_hydro() -> bool:
	var inv = InventoryStateScript.new()
	inv.add_item("purified_water", 5)
	var model = HydroStateScript.new()
	var crops := {"crops": [{
		"crop_id": "hydroponic_greens", "display_name": "Hydroponic Greens",
		"produce_item_id": "hydroponic_greens", "produce_quantity": 3,
		"growth_seconds": 1.0, "water_cost": 2.0, "power_cost": 3.0, "required_skill_level": 0,
	}]}
	_st_hydro = ProductionStationScript.new()
	_st_hydro.configure("hydroponics", model, inv, func(): return 999.0, func(): return 5, crops, Vector3.ZERO, 1.8)
	_st_hydro.set_validation_player_in_range(self)  # bypass spatial gate in headless
	# IDLE -> start
	if not _st_hydro.try_interact(self):
		return false
	if model.state != HydroStateScript.State.PLANTED:
		return false
	if inv.get_quantity("purified_water") != 3:  # 5 - water_cost(2)
		return false
	# RUNNING -> no-op
	if _st_hydro.try_interact(self):
		return false  # should return false while growing
	# tick to HARVESTABLE
	model.tick(2.0)
	if model.state != HydroStateScript.State.HARVESTABLE:
		return false
	# READY -> harvest
	if not _st_hydro.try_interact(self):
		return false
	if inv.get_quantity("hydroponic_greens") != 3:
		return false
	if model.state != HydroStateScript.State.IDLE:
		return false
	return true

func _test_recycler() -> bool:
	var inv = InventoryStateScript.new()
	inv.add_item("contaminated_water", 4)
	var model = RecyclerStateScript.new()
	model.configure({"input_item_id": "contaminated_water", "output_item_id": "purified_water",
		"conversion_ratio": 1.0, "recycle_time_seconds": 1.0, "power_cost": 5.0})
	_st_recycler = ProductionStationScript.new()
	_st_recycler.configure("water_recycler", model, inv, func(): return 999.0, func(): return 0, {}, Vector3.ZERO, 1.8)
	_st_recycler.production_blocked.connect(func(_k, reason):
		if reason == "in_progress":
			blocked_in_progress = true)
	_st_recycler.set_validation_player_in_range(self)
	if not _st_recycler.try_interact(self):  # IDLE -> load contaminated_water
		return false
	if model.state != RecyclerStateScript.State.RECYCLING:
		return false
	if inv.get_quantity("contaminated_water") != 0:
		return false
	_st_recycler.try_interact(self)  # RUNNING -> blocked in_progress (sets blocked_in_progress via signal)
	model.tick(2.0)                  # -> output_ready
	if not _st_recycler.try_interact(self):  # READY -> collect
		return false
	if inv.get_quantity("purified_water") != 4:
		return false
	return true
