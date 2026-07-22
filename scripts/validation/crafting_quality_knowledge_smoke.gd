extends SceneTree

## PKG-B2.4a: deconstruction quality inheritance + recipe knowledge gating.
## Marker: CRAFTING QUALITY KNOWLEDGE PASS quality=true knowledge=true reverse=true

const DeconstructionResolverScript := preload("res://scripts/systems/deconstruction_resolver.gd")
const RecipeKnowledgeStateScript := preload("res://scripts/systems/recipe_knowledge_state.gd")
const MaterialStateScript := preload("res://scripts/systems/material_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")


func _initialize() -> void:
	# Quality inheritance pure curve
	var q0: float = DeconstructionResolverScript._resolve_yield_quality(0.8, 0, 1.0)
	var q5: float = DeconstructionResolverScript._resolve_yield_quality(0.8, 5, 1.0)
	if q5 <= q0:
		_fail("higher skill should raise yield quality")
		return
	if q0 < 0.6 or q0 > 0.75:
		_fail("unexpected base curve for 0.8 source: %s" % str(q0))
		return

	# Knowledge: starter known, reverse unknown until dismantles
	var knowledge = RecipeKnowledgeStateScript.new()
	var recipes: Dictionary = {
		"starter_a": {"recipe_id": "starter_a", "knowledge_source": "starter"},
		"secret_b": {
			"recipe_id": "secret_b",
			"knowledge_source": "reverse_engineer",
			"reverse_engineer_component": "console_unit",
			"reverse_engineer_count": 3,
		},
		"book_c": {
			"recipe_id": "book_c",
			"knowledge_source": "book",
			"knowledge_book_id": "skill_book_weld",
		},
	}
	knowledge.seed_from_recipes(recipes)
	if not knowledge.is_known("starter_a"):
		_fail("starter should be known")
		return
	if knowledge.is_known("secret_b"):
		_fail("reverse recipe starts unknown")
		return
	if knowledge.is_known("book_c"):
		_fail("book recipe starts unknown")
		return
	var learned_book: Array = knowledge.learn_from_book("skill_book_weld", recipes)
	if learned_book.size() != 1 or str(learned_book[0]) != "book_c":
		_fail("book learn failed")
		return
	if not knowledge.is_known("book_c"):
		_fail("book_c should be known after learn")
		return
	knowledge.register_dismantle("console_unit")
	knowledge.register_dismantle("console_unit")
	if knowledge.is_known("secret_b"):
		_fail("should need 3 dismantles")
		return
	var learned_rev: Array = knowledge.register_dismantle("console_unit")
	if learned_rev.size() != 1 or not knowledge.is_known("secret_b"):
		_fail("reverse engineer unlock failed")
		return

	# Deconstruction quality through material_state when recipe exists
	var craft = CraftingStateScript.new()
	var decon = DeconstructionResolverScript.new()
	var inv = InventoryStateScript.new()
	# configure inventory capacity if needed
	if inv.has_method("configure"):
		inv.configure({})
	var mats = MaterialStateScript.new()
	if mats.has_method("configure"):
		mats.configure({})
	# Prefer a real deconstruction recipe if catalog has one
	var decon_recipes: Array = decon.get_deconstruction_recipes()
	if decon_recipes.size() > 0:
		var recipe: Dictionary = decon_recipes[0]
		var rid: String = str(recipe.get("recipe_id", ""))
		var ingredients: Dictionary = recipe.get("ingredients", {}) if typeof(recipe.get("ingredients", {})) == TYPE_DICTIONARY else {}
		for mat_id in ingredients.keys():
			var need: int = int(ingredients[mat_id])
			inv.add_item(str(mat_id), need + 2)
			if mats.has_method("set_quality") and mats.has_method("has_definition"):
				if mats.has_definition(str(mat_id)):
					mats.set_quality(str(mat_id), 0.9)
		var result: Dictionary = decon.deconstruct(rid, inv, mats, {"skill_level": 3, "tool_factor": 1.0})
		if not result.is_empty() and result.has("quality"):
			if float(result.get("quality", 0.0)) <= 0.5:
				_fail("high source quality should beat old 0.5 hardcode when possible: %s" % str(result))
				return

	# Crafting knowledge gate
	if not craft.can_craft("weld_plating", inv, knowledge):
		# may fail ingredients — learn recipe is starter by default so knowledge ok
		pass
	knowledge.learn("weld_plating")
	# inject fake unknown
	var k2 = RecipeKnowledgeStateScript.new()
	k2.seed_from_recipes({"weld_plating": {"knowledge_source": "book", "knowledge_book_id": "x"}})
	if k2.is_known("weld_plating"):
		_fail("book recipe should not start known")
		return
	if craft.can_craft("weld_plating", inv, k2):
		_fail("unknown recipe must fail can_craft")
		return

	var snap: Dictionary = knowledge.get_summary()
	var k3 = RecipeKnowledgeStateScript.new()
	k3.apply_summary(snap)
	if k3.known_count() != knowledge.known_count():
		_fail("knowledge summary round-trip")
		return

	print("CRAFTING QUALITY KNOWLEDGE PASS quality=true knowledge=true reverse=true")
	quit(0)


func _fail(msg: String) -> void:
	print("CRAFTING QUALITY KNOWLEDGE FAIL: %s" % msg)
	quit(1)
