extends SceneTree

## ADR-0038 reachability proof: crafting / salvage / field crafting are driven through the
## LIVE coordinator's OWN models (playable.crafting_state / material_state /
## field_crafting_state / deconstruction_resolver) and its real interaction seams — NOT
## freshly-built instances. This is the difference from main_playable_slice_crafting_smoke.gd
## (a model test in a main-scene costume that manually injects the snapshot fields). Here the
## coordinator must populate crafting_summary itself, with no manual injection.

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

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
	# Prove the coordinator OWNS the models (not the smoke).
	if playable.crafting_state == null or playable.material_state == null \
			or playable.field_crafting_state == null or playable.deconstruction_resolver == null:
		_fail("coordinator does not own the crafting models")
		return
	if playable.crafting_stations == null or playable.crafting_stations.is_empty():
		_fail("no crafting stations were built on the home ship")
		return

	# Seed a generous bundle of common ingredients + deconstructable items.
	inv.add_item("scrap_metal", 12)
	inv.add_item("wiring_bundle", 12)
	inv.add_item("reactive_gel", 8)
	inv.add_item("circuit_board", 8)
	inv.add_item("synth_fiber", 12)
	inv.add_item("medical_gauze", 6)
	inv.add_item("titanium_ingot", 6)
	inv.add_item("power_cell", 4)
	inv.add_item("ceramic_plate", 4)
	inv.add_item("adhesive_paste", 6)
	inv.add_item("purified_water", 6)
	inv.add_item("plating", 4)
	# Quality on the coordinator's OWN material_state.
	playable.material_state.set_quality("scrap_metal", 0.8)
	playable.material_state.set_quality("wiring_bundle", 0.7)
	playable.material_state.set_quality("reactive_gel", 0.9)
	playable.material_state.set_quality("circuit_board", 0.75)
	# Station crafting now enforces required_skill_level (PR #45). Grant fabrication skill so
	# the fabricator auto-craft can select a mid-tier recipe (boot skill is 0).
	if playable.player_progression != null:
		playable.player_progression.skills["fabrication"] = 6

	# --- 1) Station craft through the real interaction path -------------------------------
	if not playable.craft_at_station_for_validation("fabricator"):
		_fail("fabricator station craft did not start")
		return
	var rid: String = playable.crafting_state.get_active_recipe_id()
	if rid.is_empty():
		_fail("no active recipe after station craft start")
		return
	var produces: Dictionary = playable.crafting_state.get_produces(rid)
	var craft_item: String = str(produces.get("item_id", ""))
	if craft_item.is_empty():
		_fail("active recipe produces nothing")
		return
	var craft_before: int = inv.get_quantity(craft_item)
	# Advance well past the craft time; the coordinator deposits on completion.
	playable.advance_crafting_for_validation(120.0)
	if playable.crafting_state.is_crafting():
		_fail("station craft did not complete after advance")
		return
	if inv.get_quantity(craft_item) <= craft_before:
		_fail("station craft output not deposited: %s" % craft_item)
		return
	var crafted: bool = true

	# --- 2) Salvage / deconstruct through the real interaction path ------------------------
	# REQ-CS-017: first-ready is list_salvage_entries order (recipe_id sort), not raw
	# catalog iteration — match the validation seam so the assertion is order-stable.
	var salvage_item: String = ""
	var first_salvage: String = playable.deconstruction_resolver.first_ready_salvage_id(inv)
	if first_salvage.is_empty():
		_fail("no ready salvage target seeded")
		return
	for entry in playable.deconstruction_resolver.list_salvage_entries(inv):
		if str((entry as Dictionary).get("recipe_id", "")) == first_salvage:
			var dproduces: Variant = (entry as Dictionary).get("produces", {})
			if dproduces is Dictionary:
				salvage_item = str((dproduces as Dictionary).get("item_id", ""))
			break
	if salvage_item.is_empty():
		_fail("no deconstructable item seeded for salvage")
		return
	var salvage_before: int = inv.get_quantity(salvage_item)
	if not playable.craft_at_station_for_validation("salvage"):
		_fail("salvage station did not deconstruct")
		return
	if inv.get_quantity(salvage_item) <= salvage_before:
		_fail("salvage output not deposited: %s" % salvage_item)
		return
	var salvaged: bool = true

	# --- 3) Emergency field crafting through the real player entrypoint --------------------
	var field_item: String = ""
	var field_recipes: Array = playable.field_crafting_state.get_field_recipes()
	field_recipes.sort_custom(func(a, b): return str(a.get("recipe_id", "")) < str(b.get("recipe_id", "")))
	for recipe in field_recipes:
		var frid: String = str(recipe.get("recipe_id", ""))
		if frid.is_empty():
			continue
		if playable.field_crafting_state.can_craft(frid, inv):
			var fproduces: Variant = recipe.get("produces", {})
			if fproduces is Dictionary:
				field_item = str((fproduces as Dictionary).get("item_id", ""))
			break
	if field_item.is_empty():
		_fail("no craftable field recipe seeded")
		return
	var field_before: int = inv.get_quantity(field_item)
	# REQ-CS-016: KEY_C opens the field recipe picker; reachability still proves
	# the coordinator field model via first-ready begin (UI-free). Live picker
	# choice for field is covered by main_playable_slice_recipe_picker_smoke /
	# begin_craft_from_picker("field_crafting", ...).
	if playable.has_method("field_craft_first_ready_for_validation"):
		if not playable.field_craft_first_ready_for_validation():
			_fail("field craft first-ready did not start")
			return
	else:
		playable._on_player_field_craft_requested(playable.player)
	if not playable.field_crafting_state.is_crafting():
		_fail("field craft did not start via the player entrypoint")
		return
	playable.advance_crafting_for_validation(120.0)
	if playable.field_crafting_state.is_crafting():
		_fail("field craft did not complete after advance")
		return
	if inv.get_quantity(field_item) <= field_before:
		_fail("field craft output not deposited: %s" % field_item)
		return
	var field: bool = true

	# --- 4) The coordinator populates crafting_summary itself (NO manual injection) --------
	var snapshot = playable._build_run_snapshot()
	if snapshot == null:
		_fail("run snapshot missing")
		return
	if snapshot.crafting_summary == null or snapshot.crafting_summary.is_empty():
		_fail("crafting_summary empty — coordinator did not populate it")
		return
	if not snapshot.crafting_summary.has("field_crafting"):
		_fail("crafting_summary missing nested field_crafting key")
		return
	if snapshot.material_summary == null or snapshot.material_summary.is_empty():
		_fail("material_summary empty — coordinator did not populate it")
		return
	var reachable: bool = true

	finished = true
	print("MAIN PLAYABLE STATION CRAFT PASS crafted=%s salvaged=%s field=%s reachable=%s" % [
		str(crafted).to_lower(), str(salvaged).to_lower(), str(field).to_lower(), str(reachable).to_lower()])
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(0)

func _find_playable(node: Node):
	if not is_instance_valid(node):
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
	push_error("MAIN PLAYABLE STATION CRAFT FAIL reason=%s" % reason)
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
