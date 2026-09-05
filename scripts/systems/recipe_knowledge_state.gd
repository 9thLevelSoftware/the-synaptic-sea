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
## Explicit current-run event receipts make replayed gameplay notifications no-ops.
var owner_id: String = ""
var _event_receipt_ids: Dictionary = {}
var _event_sequence: int = 0

func configure(current_owner_id: String, recipes: Dictionary) -> void:
	owner_id = current_owner_id
	seed_from_recipes(recipes)


func clear() -> void:
	_known.clear()
	_dismantle_counts.clear()
	_reverse_targets.clear()
	_event_receipt_ids.clear()
	_event_sequence = 0
	owner_id = ""


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
	return receive_book_read(book_id, "legacy-book:%s" % book_id, recipes).get("learned_recipe_ids", [])


func receive_book_read(book_id: String, event_receipt_id: String, recipes: Dictionary) -> Dictionary:
	return _receive_matching_event(SOURCE_BOOK, "knowledge_book_id", book_id, event_receipt_id, recipes)


func receive_codex_discovery(codex_id: String, event_receipt_id: String, recipes: Dictionary) -> Dictionary:
	return _receive_matching_event(SOURCE_CODEX, "knowledge_codex_id", codex_id, event_receipt_id, recipes)


func _legacy_learn_from_book(book_id: String, recipes: Dictionary) -> Array:
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
	return receive_codex_discovery(codex_id, "legacy-codex:%s" % codex_id, recipes).get("learned_recipe_ids", [])


func _legacy_learn_from_codex(codex_id: String, recipes: Dictionary) -> Array:
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
	var next_count: int = int(_dismantle_counts.get(component_id, 0)) + 1
	return receive_reverse_engineer(component_id, "legacy-reverse:%s:%d" % [component_id, next_count]).get("learned_recipe_ids", [])


func receive_reverse_engineer(component_id: String, event_receipt_id: String) -> Dictionary:
	if _is_duplicate_receipt(event_receipt_id):
		return {"ok": true, "already_received": true, "learned_recipe_ids": []}
	if component_id.is_empty():
		return {"ok": false, "reason": "bad_component", "learned_recipe_ids": []}
	_event_receipt_ids[event_receipt_id] = true
	_dismantle_counts[component_id] = int(_dismantle_counts.get(component_id, 0)) + 1
	var count: int = int(_dismantle_counts[component_id])
	var learned: Array = []
	for rid in _reverse_targets.keys():
		if is_known(str(rid)):
			continue
		var tgt: Dictionary = _reverse_targets[rid]
		if str(tgt.get("component_id", "")) == component_id and count >= int(tgt.get("need", 3)) and learn(str(rid)):
			learned.append(str(rid))
	return {"ok": true, "already_received": false, "learned_recipe_ids": learned}


## Allocate only after the source operation has committed consumption. The counter
## is current-run state and persists with receipts, so replay delivery uses the
## same operation key instead of a node-local sequence.
func allocate_event_receipt(event_kind: String) -> String:
	if event_kind.is_empty():
		return ""
	_event_sequence += 1
	return "%s:%s:%d" % [owner_id if not owner_id.is_empty() else "player", event_kind, _event_sequence]


func _legacy_register_dismantle(component_id: String) -> Array:
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
		"owner_id": owner_id,
		"known_recipe_ids": _known.keys(),
		"event_receipt_ids": _event_receipt_ids.keys(),
		"event_sequence": _event_sequence,
		"known": _known.duplicate(true), # legacy readers
		"dismantle_counts": _dismantle_counts.duplicate(true),
	}


func apply_summary(summary: Dictionary) -> bool:
	if summary.is_empty():
		return false
	owner_id = str(summary.get("owner_id", owner_id))
	_event_sequence = maxi(0, int(summary.get("event_sequence", _event_sequence)))
	var k: Variant = summary.get("known_recipe_ids", summary.get("known", {}))
	if k is Array:
		_known.clear()
		for recipe_id in k:
			_known[str(recipe_id)] = true
	elif typeof(k) == TYPE_DICTIONARY:
		_known = (k as Dictionary).duplicate(true)
	var receipts: Variant = summary.get("event_receipt_ids", [])
	if receipts is Array:
		_event_receipt_ids.clear()
		for receipt in receipts:
			_event_receipt_ids[str(receipt)] = true
	var d: Variant = summary.get("dismantle_counts", {})
	if typeof(d) == TYPE_DICTIONARY:
		_dismantle_counts = (d as Dictionary).duplicate(true)
	return true


func _receive_matching_event(source: String, field_name: String, source_id: String, event_receipt_id: String, recipes: Dictionary) -> Dictionary:
	if _is_duplicate_receipt(event_receipt_id):
		return {"ok": true, "already_received": true, "learned_recipe_ids": []}
	if source_id.is_empty():
		return {"ok": false, "reason": "bad_event", "learned_recipe_ids": []}
	_event_receipt_ids[event_receipt_id] = true
	var learned: Array = []
	for rid in recipes.keys():
		var raw: Variant = recipes[rid]
		if raw is Dictionary:
			var recipe: Dictionary = raw
			if str(recipe.get("knowledge_source", "")) == source and str(recipe.get(field_name, "")) == source_id and learn(str(rid)):
				learned.append(str(rid))
	return {"ok": true, "already_received": false, "learned_recipe_ids": learned}


func _is_duplicate_receipt(event_receipt_id: String) -> bool:
	return event_receipt_id.is_empty() or _event_receipt_ids.has(event_receipt_id)
