extends SceneTree

## REQ-CS-016 pure-model smoke: CraftingState.list_recipe_entries returns sorted
## station rows with correct ready / blocked statuses (no scene tree).

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")

func _fail(msg: String) -> void:
	print("FAIL: %s" % msg)
	quit()

func _initialize() -> void:
	var crafting = CraftingStateScript.new()
	if not crafting.has_method("list_recipe_entries"):
		_fail("list_recipe_entries missing on CraftingState")
		return

	var inv = InventoryStateScript.new()
	# Skill 0, empty inventory: fabricator entries should all be blocked (skill or ingredients).
	var empty_entries: Array = crafting.list_recipe_entries("fabricator", inv, 0)
	if empty_entries.is_empty():
		_fail("fabricator should have recipes in the catalog")
		return
	# Sorted by recipe_id.
	var prev: String = ""
	for e in empty_entries:
		var rid: String = str((e as Dictionary).get("recipe_id", ""))
		if prev != "" and rid < prev:
			_fail("entries not sorted by recipe_id: %s before %s" % [prev, rid])
			return
		prev = rid
		if str((e as Dictionary).get("category", "")) == "deconstruction":
			_fail("deconstruction recipe leaked into fabricator list: %s" % rid)
			return
		if bool((e as Dictionary).get("craftable", false)):
			_fail("empty inv should not make %s craftable" % rid)
			return

	# Seed enough for at least two fabricator recipes at skill 6.
	inv.add_item("scrap_metal", 20)
	inv.add_item("wiring_bundle", 20)
	inv.add_item("reactive_gel", 10)
	inv.add_item("circuit_board", 10)
	inv.add_item("synth_fiber", 10)
	inv.add_item("titanium_ingot", 10)
	inv.add_item("ceramic_plate", 10)
	inv.add_item("adhesive_paste", 10)
	inv.add_item("polymer_pellet", 10)
	inv.add_item("graphene_sheet", 10)
	inv.add_item("medical_gauze", 10)

	var ready_entries: Array = crafting.list_recipe_entries("fabricator", inv, 6)
	var ready_n: int = 0
	var blocked_n: int = 0
	var first_ready: String = ""
	for e in ready_entries:
		if bool((e as Dictionary).get("craftable", false)):
			ready_n += 1
			if first_ready.is_empty():
				first_ready = str((e as Dictionary).get("recipe_id", ""))
		else:
			blocked_n += 1
	if ready_n < 2:
		_fail("expected >=2 ready fabricator recipes with seeded inv/skill, got %d" % ready_n)
		return
	if first_ready.is_empty():
		_fail("no first ready id")
		return

	# Insufficient skill: a high-skill recipe should report insufficient_skill when skill=0
	# even with full ingredients.
	var low_skill: Array = crafting.list_recipe_entries("fabricator", inv, 0)
	var saw_skill_block: bool = false
	for e in low_skill:
		var d: Dictionary = e as Dictionary
		if int(d.get("required_skill_level", 0)) > 0 and str(d.get("status", "")) == "insufficient_skill":
			saw_skill_block = true
			break
	if not saw_skill_block:
		_fail("expected at least one insufficient_skill row at skill 0")
		return

	print("CRAFTING RECIPE LIST PASS ready=%d blocked=%d station=fabricator" % [ready_n, blocked_n])
	quit()
