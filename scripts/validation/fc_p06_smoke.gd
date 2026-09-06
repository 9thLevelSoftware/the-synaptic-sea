extends SceneTree

## FC-04: current-run recipe knowledge gates list and direct start. Explicit
## book/codex/reverse event receipts are idempotent; mere seeding is not learning.

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const RecipeKnowledgeStateScript := preload("res://scripts/systems/recipe_knowledge_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const LootContainerScript := preload("res://scripts/tools/loot_container.gd")
const LootDistributionScript := preload("res://scripts/systems/loot_distribution.gd")

func _initialize() -> void:
	var crafting = CraftingStateScript.new()
	var knowledge = RecipeKnowledgeStateScript.new()
	knowledge.configure("player:p06", crafting.get_recipe_catalog())
	var inventory = InventoryStateScript.new()
	var material = MaterialStateScript.new()
	# The one authored non-starter recipe must be locked despite sufficient input,
	# skill, and station tier.
	inventory.add_item("titanium_ingot", 2)
	inventory.add_item("ceramic_plate", 2)
	inventory.add_item("coolant_fluid", 1)
	var recipe_id := "craft_thruster_nozzle"
	if knowledge.is_known(recipe_id):
		_fail("book recipe started known")
		return
	var rows: Array = crafting.list_recipe_entries("fabricator", inventory, 6, 2, knowledge)
	var row: Dictionary = _find(rows, recipe_id)
	if str(row.get("status", "")) != "missing_recipe_knowledge" or not str(row.get("knowledge_hint", "")).contains("fabrication_schematic_basic"):
		_fail("picker listing did not expose knowledge gate: %s" % row)
		return
	if crafting.begin_craft(recipe_id, inventory, material, 6, knowledge):
		_fail("direct start bypassed recipe knowledge")
		return
	if crafting.enqueue_craft(recipe_id, 1, knowledge) != 0:
		_fail("legacy queue admitted locked recipe")
		return
	var learned_book: Dictionary = knowledge.receive_book_read("fabrication_schematic_basic", "book:p06:one", crafting.get_recipe_catalog())
	if not bool(learned_book.get("ok", false)) or not knowledge.is_known(recipe_id):
		_fail("book event did not unlock authored recipe")
		return
	var replay_book: Dictionary = knowledge.receive_book_read("fabrication_schematic_basic", "book:p06:one", crafting.get_recipe_catalog())
	if not bool(replay_book.get("already_received", false)) or not (replay_book.get("learned_recipe_ids", []) as Array).is_empty():
		_fail("book event replay was not idempotent")
		return
	crafting.get_or_create_station("fabricator").level = 2
	if not crafting.begin_craft(recipe_id, inventory, material, 6, knowledge):
		_fail("learned recipe did not start")
		return

	var synthetic := RecipeKnowledgeStateScript.new()
	var synthetic_recipes: Dictionary = {
		"book_recipe": {"knowledge_source": "book", "knowledge_book_id": "book-x"},
		"codex_recipe": {"knowledge_source": "codex", "knowledge_codex_id": "codex-x"},
		"reverse_recipe": {"knowledge_source": "reverse_engineer", "reverse_engineer_component": "console", "reverse_engineer_count": 2},
	}
	synthetic.configure("player:p06-events", synthetic_recipes)
	if not bool(synthetic.receive_book_read("book-x", "event:book", synthetic_recipes).get("ok", false)) or not synthetic.is_known("book_recipe"):
		_fail("synthetic book event failed")
		return
	if not bool(synthetic.receive_codex_discovery("codex-x", "event:codex", synthetic_recipes).get("ok", false)) or not synthetic.is_known("codex_recipe"):
		_fail("synthetic codex event failed")
		return
	var reverse_one: String = synthetic.allocate_event_receipt("reverse_engineer")
	synthetic.receive_reverse_engineer("console", reverse_one)
	if synthetic.is_known("reverse_recipe"):
		_fail("reverse recipe unlocked early")
		return
	synthetic.receive_reverse_engineer("console", reverse_one)
	if synthetic.is_known("reverse_recipe"):
		_fail("replayed reverse event incremented progress")
		return
	var reverse_two: String = synthetic.allocate_event_receipt("reverse_engineer")
	if reverse_one == reverse_two:
		_fail("distinct successful salvage operations reused a receipt")
		return
	synthetic.receive_reverse_engineer("console", reverse_two)
	if not synthetic.is_known("reverse_recipe"):
		_fail("second distinct reverse event did not unlock")
		return
	var summary: Dictionary = synthetic.get_summary()
	var restored := RecipeKnowledgeStateScript.new()
	restored.configure("player:p06-events", synthetic_recipes)
	restored.apply_summary(summary)
	if not bool(restored.receive_codex_discovery("codex-x", "event:codex", synthetic_recipes).get("already_received", false)):
		_fail("receipt did not survive summary round-trip")
		return
	if restored.allocate_event_receipt("reverse_engineer") == reverse_two:
		_fail("receipt allocator did not advance after summary round-trip")
		return
	_run_live_paths.call_deferred()

func _run_live_paths() -> void:
	var main_node: Node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	var playable = null
	for _frame in range(600):
		await process_frame
		playable = _find_playable(main_node)
		if playable != null and playable.loader != null and playable.loader.has_loaded_ship() and playable.playable_started:
			break
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		_fail("live playable did not become ready")
		return
	# Upgrade the real fabricator, keep the picker open on its locked row, and
	# learn through the normal inventory UI Use signal.
	playable.player_progression.skills["fabrication"] = 6
	var fabricator_node = null
	for station_node in playable.crafting_stations:
		if is_instance_valid(station_node) and str(station_node.station_kind) == "fabricator":
			fabricator_node = station_node
			break
	if fabricator_node == null:
		_fail("live physical fabricator was missing")
		return
	var fabricator = playable.crafting_state.get_station_instance(
		str(fabricator_node.ship_id), str(fabricator_node.station_instance_id))
	if fabricator == null:
		_fail("live physical fabricator state was missing")
		return
	# The current picker remains station-kind scoped; keep its compatibility
	# projection aligned while execution is validated against the real owner.
	playable.crafting_state.get_or_create_station("fabricator").apply_component_tier(2)
	fabricator.apply_component_tier(2)
	playable.inventory_state.add_item("titanium_ingot", 2)
	playable.inventory_state.add_item("ceramic_plate", 2)
	playable.inventory_state.add_item("coolant_fluid", 1)
	if not playable.open_recipe_picker_for_validation("fabricator"):
		_fail("could not open live fabricator picker")
		return
	var picker = playable.recipe_picker_panel
	var found_locked: bool = false
	for _i in range(picker.get_entry_count()):
		if picker.get_selected_id() == "craft_thruster_nozzle":
			found_locked = true
			break
		picker.move_selection(1)
	var rows_before: Array = picker.get_row_texts()
	var showed_locked: bool = false
	for row_text in rows_before:
		if "missing_recipe_knowledge" in str(row_text) and "Thruster Nozzle" in str(row_text):
			showed_locked = true
			break
	if not found_locked or not showed_locked:
		_fail("live picker did not show locked recipe")
		return
	var loot_seed: String = _book_loot_seed(playable)
	if loot_seed.is_empty():
		_fail("no deterministic authored schematic loot seed")
		return
	var loot = LootContainerScript.new()
	loot.configure("p06-schematic-cache", "salvage_engineering", loot_seed,
		playable.inventory_state, playable._loot_tables, playable.player.global_position, 1.8, {})
	loot.container_searched.connect(playable._on_loot_container_searched.bind(loot))
	main_node.add_child(loot)
	loot.set_validation_player_in_range(playable.player)
	if not loot.try_interact(playable.player) or playable.inventory_state.get_quantity("fabrication_schematic_basic") != 1:
		_fail("authored salvage_engineering container did not grant schematic")
		return
	playable.inventory_panel.use_requested.emit("fabrication_schematic_basic", false)
	if not playable.recipe_knowledge_state.is_known("craft_thruster_nozzle"):
		_fail("live inventory book Use did not unlock recipe")
		return
	var started: Dictionary = picker.confirm_selection()
	if not bool(started.get("ok", false)) or playable.crafting_state.get_active_recipe_id() != "craft_thruster_nozzle":
		_fail("learned tier-2 recipe did not start through live picker: %s" % started)
		return
	# Controlled authored fixtures make the real coordinator event seams observable.
	# They are added to the live catalog before the production callbacks, never sent
	# directly to RecipeKnowledgeState.
	playable.crafting_state._recipes["p06_codex_recipe"] = {"recipe_id": "p06_codex_recipe", "knowledge_source": "codex", "knowledge_codex_id": "p06-codex"}
	playable.crafting_state._recipes["p06_reverse_recipe"] = {"recipe_id": "p06_reverse_recipe", "knowledge_source": "reverse_engineer", "reverse_engineer_component": "thruster_nozzle", "reverse_engineer_count": 1}
	playable.recipe_knowledge_state.seed_from_recipes(playable.crafting_state.get_recipe_catalog())
	# The production loot postprocess is the callback reached after a successful
	# container search. It must update this owner and replay must be a no-op.
	var receipts_before_codex: int = (playable.recipe_knowledge_state.get_summary().get("event_receipt_ids", []) as Array).size()
	playable._postprocess_loot_grants([{
		"item_id": "power_cell", "quantity": 1, "seed_key": "p06-live-loot",
		"codex_entry_id": "p06-codex",
	}], "p06-live-loot")
	if not playable.recipe_knowledge_state.is_known("p06_codex_recipe"):
		_fail("live codex event did not reach current-run knowledge owner")
		return
	playable._postprocess_loot_grants([{"item_id": "power_cell", "quantity": 1, "seed_key": "p06-live-loot", "codex_entry_id": "p06-codex"}], "p06-live-loot")
	if (playable.recipe_knowledge_state.get_summary().get("event_receipt_ids", []) as Array).size() != receipts_before_codex + 1:
		_fail("replayed live codex event awarded again")
		return
	var receipts_before_reverse: int = (playable.recipe_knowledge_state.get_summary().get("event_receipt_ids", []) as Array).size()
	# This invokes the real salvage station -> consumed resolver -> receipt signal path.
	playable.inventory_state.add_item("thruster_nozzle", 1)
	if not bool(playable.begin_craft_from_picker("salvage", "deconstruct_thruster").get("ok", false)):
		_fail("live salvage did not complete")
		return
	if not playable.recipe_knowledge_state.is_known("p06_reverse_recipe") or (playable.recipe_knowledge_state.get_summary().get("event_receipt_ids", []) as Array).size() != receipts_before_reverse + 1:
		_fail("live salvage signal did not deliver exactly one reverse award")
		return
	print("FC P06 PASS")
	print("FC P06 PASS locked=true direct_gate=true book=true codex=true reverse=true receipts=true live_book=true live_codex=true live_salvage=true")
	quit(0)

func _find(rows: Array, recipe_id: String) -> Dictionary:
	for entry in rows:
		if entry is Dictionary and str((entry as Dictionary).get("recipe_id", "")) == recipe_id:
			return entry
	return {}

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

func _book_loot_seed(playable) -> String:
	for index in range(4096):
		var seed: String = "p06-schematic-%d" % index
		var rolled: Array = LootDistributionScript.roll("salvage_engineering", seed, playable._loot_tables, {})
		for entry in rolled:
			if entry is Dictionary and str((entry as Dictionary).get("item_id", "")) == "fabrication_schematic_basic":
				return seed
	return ""

func _fail(message: String) -> void:
	print("FC P06 FAIL: %s" % message)
	quit(1)
