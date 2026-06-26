extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

const SaveLoadServiceScript := preload("res://scripts/systems/save_load_service.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

var main_node: Node
var frame_count: int = 0
var finished: bool = false
var exercised: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	if not playable.playable_started:
		return
	if exercised:
		return
	exercised = true
	_validate(playable)

func _validate(playable) -> void:
	var inv = playable.inventory_state
	if inv == null:
		_fail("inventory_state missing")
		return
	inv.add_item("scrap_metal", 10)
	inv.add_item("wiring_bundle", 10)
	inv.add_item("reactive_gel", 5)
	inv.add_item("circuit_board", 5)
	inv.add_item("synth_fiber", 10)
	inv.add_item("medical_gauze", 5)
	inv.add_item("titanium_ingot", 5)
	inv.add_item("power_cell", 3)
	inv.add_item("ceramic_plate", 4)
	inv.add_item("purified_water", 5)
	inv.add_item("ration_pack", 5)

	var crafting = CraftingStateScript.new()
	var materials = MaterialStateScript.new()
	materials.set_quality("scrap_metal", 0.8)
	materials.set_quality("wiring_bundle", 0.7)
	materials.set_quality("reactive_gel", 0.9)
	materials.set_quality("circuit_board", 0.75)

	if not crafting.begin_craft("craft_power_cell", inv, materials, 2):
		_fail("begin craft failed")
		return
	crafting.tick(10.0)
	if not crafting.is_crafting():
		_fail("craft should still be active after partial tick")
		return

	var snapshot = playable._build_run_snapshot()
	if snapshot == null:
		_fail("run snapshot missing")
		return
	snapshot.inventory_summary = inv.get_summary()
	snapshot.crafting_summary = crafting.get_summary()
	snapshot.material_summary = materials.get_summary()

	var service = SaveLoadServiceScript.new()
	var slot_id: String = "crafting_smoke_test"
	service.delete_slot(slot_id)
	if not service.save_to_slot(slot_id, snapshot, "manual", false, "crafting smoke test"):
		_fail("save_to_slot failed")
		return

	var loaded = service.load_from_slot(slot_id)
	if loaded == null:
		_fail("load_from_slot returned null")
		return
	if loaded.crafting_summary.is_empty():
		_fail("crafting_summary missing after load")
		return
	if loaded.material_summary.is_empty():
		_fail("material_summary missing after load")
		return

	var crafting2 = CraftingStateScript.new()
	var materials2 = MaterialStateScript.new()
	if not materials2.apply_summary(loaded.material_summary):
		_fail("material_summary apply failed")
		return
	if not crafting2.apply_summary(loaded.crafting_summary):
		_fail("crafting_summary apply failed")
		return
	if not crafting2.is_crafting():
		_fail("craft should resume after load")
		return
	var station = crafting2.get_station("fabricator")
	if station == null:
		_fail("station missing after load")
		return
	if station.get_progress_ratio() <= 0.0:
		_fail("progress ratio did not survive save/load")
		return

	var remaining: float = station.required_seconds - station.progress_seconds
	if not crafting2.tick(remaining + 1.0):
		_fail("resumed craft did not complete")
		return
	var result: Dictionary = crafting2.finish_craft()
	if result.get("item_id", "") != "power_cell":
		_fail("wrong output item after resume")
		return
	if int(result.get("quantity", 0)) != 1:
		_fail("wrong output quantity after resume")
		return

	var inv2 = InventoryStateScript.new()
	inv2.apply_summary(loaded.inventory_summary)
	if inv2.get_quantity("scrap_metal") != 9 or inv2.get_quantity("wiring_bundle") != 8 or inv2.get_quantity("reactive_gel") != 4:
		_fail("ingredients duplicated or not consumed")
		return

	service.delete_slot(slot_id)
	finished = true
	print("MAIN PLAYABLE CRAFTING PASS mid_craft_save=true resume=true no_duplication=true quality=true")
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

func _find_playable(node: Node):
	if node == null:
		return null
	if node.get_script() == load("res://scripts/procgen/playable_generated_ship.gd"):
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE CRAFTING FAIL reason=%s" % reason)
	var service = SaveLoadServiceScript.new()
	service.delete_slot("crafting_smoke_test")
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
