extends RefCounted
class_name RecipeKnowledgeState

## PKG-B2.4a: known/unknown recipe gating + reverse-engineer discovery.
## Recipes without knowledge_source (or source=starter) are known by default
## for backward compatibility with the existing 60-recipe catalog.

const SOURCE_STARTER: String = "starter"
const SOURCE_BOOK: String = "book"
const SOURCE_CODEX: String = "codex"
const SOURCE_REVERSE: String = "reverse_engineer"

## recipe_id -> true when learned
var _known: Dictionary = {}
## component_id -> dismantle count for reverse-engineer
var _dismantle_counts: Dictionary = {}
## reverse_engineer: recipe_id -> required dismantle count of component_id
## Stored as recipe_id -> {component_id, need}
var _reverse_targets: Dictionary = {}


func clear() -> void:
	_known.clear()
	_dismantle_counts.clear()
	_reverse_targets.clear()


## Seed knowledge from full recipe catalog dict (recipe_id -> recipe).
func seed_from_recipes(recipes: Dictionary) -> void:
	_reverse_targets.clear()
	for rid in recipes.keys():
		var recipe: Variant = recipes[rid]
		if typeof(recipe) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = recipe
		var source: String = str(r.get("knowledge_source", SOURCE_STARTER))
		if source.is_empty() or source == SOURCE_STARTER:
			_known[str(rid)] = true
		elif source == SOURCE_REVERSE:
			var need: int = maxi(1, int(r.get("reverse_engineer_count", 3)))
			var comp: String = str(r.get("reverse_engineer_component", ""))
			_reverse_targets[str(rid)] = {"component_id": comp, "need": need}
		# book/codex start unknown


func is_known(recipe_id: String) -> bool:
	return bool(_known.get(recipe_id, false))


func learn(recipe_id: String) -> bool:
	if recipe_id.is_empty():
		return false
	if _known.has(recipe_id):
		return false
	_known[recipe_id] = true
	return true


func learn_from_book(book_id: String, recipes: Dictionary) -> Array:
	var learned: Array = []
	for rid in recipes.keys():
		var recipe: Variant = recipes[rid]
		if typeof(recipe) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = recipe
		if str(r.get("knowledge_source", "")) != SOURCE_BOOK:
			continue
		if str(r.get("knowledge_book_id", "")) != book_id:
			continue
		if learn(str(rid)):
			learned.append(str(rid))
	return learned


func learn_from_codex(codex_id: String, recipes: Dictionary) -> Array:
	var learned: Array = []
	for rid in recipes.keys():
		var recipe: Variant = recipes[rid]
		if typeof(recipe) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = recipe
		if str(r.get("knowledge_source", "")) != SOURCE_CODEX:
			continue
		if str(r.get("knowledge_codex_id", "")) != codex_id:
			continue
		if learn(str(rid)):
			learned.append(str(rid))
	return learned


## Register dismantling a component; unlock reverse-engineer recipes when count met.
func register_dismantle(component_id: String) -> Array:
	if component_id.is_empty():
		return []
	_dismantle_counts[component_id] = int(_dismantle_counts.get(component_id, 0)) + 1
	var count: int = int(_dismantle_counts[component_id])
	var learned: Array = []
	for rid in _reverse_targets.keys():
		if is_known(str(rid)):
			continue
		var tgt: Dictionary = _reverse_targets[rid]
		if str(tgt.get("component_id", "")) != component_id:
			continue
		if count >= int(tgt.get("need", 3)):
			if learn(str(rid)):
				learned.append(str(rid))
	return learned


func known_count() -> int:
	return _known.size()


func get_summary() -> Dictionary:
	return {
		"known": _known.duplicate(true),
		"dismantle_counts": _dismantle_counts.duplicate(true),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	var k: Variant = summary.get("known", {})
	if typeof(k) == TYPE_DICTIONARY:
		_known = (k as Dictionary).duplicate(true)
	var d: Variant = summary.get("dismantle_counts", {})
	if typeof(d) == TYPE_DICTIONARY:
		_dismantle_counts = (d as Dictionary).duplicate(true)
	return true
