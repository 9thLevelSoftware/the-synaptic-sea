extends RefCounted
class_name RecipeKnowledgeState

## PKG-B2.4a: known/unknown recipe gating + reverse-engineer discovery.
## Recipes without knowledge_source (or source=starter) are known by default
## for backward compatibility with the existing 60-recipe catalog.

const SOURCE_STARTER: String = "starter"
const SOURCE_BOOK: String = "book"
const SOURCE_CODEX: String = "codex"
const SOURCE_REVERSE: String = "reverse_engineer"
const SCHEMA: String = "recipe-knowledge-1"
const MAX_SAFE_JSON_INTEGER: float = 9007199254740991.0

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
var migration_origin: String = "native"
var _catalog_recipe_ids: Dictionary = {}

func configure(current_owner_id: String, recipes: Dictionary) -> void:
	owner_id = current_owner_id
	_catalog_recipe_ids.clear()
	for recipe_id_variant in recipes:
		_catalog_recipe_ids[str(recipe_id_variant)] = true
	seed_from_recipes(recipes)


func clear() -> void:
	_known.clear()
	_dismantle_counts.clear()
	_reverse_targets.clear()
	_event_receipt_ids.clear()
	_event_sequence = 0
	owner_id = ""
	migration_origin = "native"
	_catalog_recipe_ids.clear()


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
	var known_ids: Array = _known.keys()
	known_ids.sort()
	var receipt_ids: Array = _event_receipt_ids.keys()
	receipt_ids.sort()
	return {
		"schema": SCHEMA,
		"owner_id": owner_id,
		"known_recipe_ids": known_ids,
		"event_receipt_ids": receipt_ids,
		"event_sequence": _event_sequence,
		"dismantle_counts": _dismantle_counts.duplicate(true),
		"migration_origin": migration_origin,
	}


func apply_summary(summary: Dictionary) -> bool:
	if not summary.has("schema"):
		return _apply_legacy_summary(summary)
	var normalized: Dictionary = _normalize_summary(summary)
	if normalized.is_empty():
		return false
	owner_id = normalized.owner_id
	_event_sequence = normalized.event_sequence
	migration_origin = normalized.migration_origin
	_known.clear()
	for recipe_id in normalized.known_recipe_ids:
		_known[str(recipe_id)] = true
	_event_receipt_ids.clear()
	for receipt_id in normalized.event_receipt_ids:
		_event_receipt_ids[str(receipt_id)] = true
	_dismantle_counts = normalized.dismantle_counts
	return true


func _apply_legacy_summary(summary: Dictionary) -> bool:
	if typeof(summary.get("owner_id", "")) != TYPE_STRING:
		return false
	var known_v: Variant = summary.get("known_recipe_ids", summary.get("known", {}))
	if not known_v is Array and not known_v is Dictionary:
		return false
	owner_id = str(summary.get("owner_id", owner_id))
	_known.clear()
	if known_v is Array:
		for recipe_id_variant in known_v as Array:
			if typeof(recipe_id_variant) != TYPE_STRING or str(recipe_id_variant).is_empty():
				return false
			_known[str(recipe_id_variant)] = true
	else:
		for recipe_id_variant in known_v as Dictionary:
			if typeof(recipe_id_variant) != TYPE_STRING or str(recipe_id_variant).is_empty():
				return false
			_known[str(recipe_id_variant)] = true
	return true


func _normalize_summary(summary: Dictionary) -> Dictionary:
	for key in [
		"schema", "owner_id", "known_recipe_ids", "event_receipt_ids",
		"event_sequence", "dismantle_counts", "migration_origin",
	]:
		if not summary.has(key):
			return {}
	if typeof(summary.schema) != TYPE_STRING or str(summary.schema) != SCHEMA \
			or typeof(summary.owner_id) != TYPE_STRING \
			or not summary.known_recipe_ids is Array \
			or not summary.event_receipt_ids is Array \
			or not summary.dismantle_counts is Dictionary \
			or typeof(summary.migration_origin) != TYPE_STRING \
			or not ["native", "legacy_unrecorded"].has(str(summary.migration_origin)) \
			or not _is_nonnegative_json_integer(summary.event_sequence):
		return {}
	var next_owner: String = str(summary.owner_id)
	if str(summary.migration_origin) == "legacy_unrecorded":
		# The first trusted migration arrives unbound and is bound to the
		# prepared target run. Subsequent v5 captures retain that canonical
		# owner while preserving the legacy evidence marker.
		if next_owner.is_empty():
			next_owner = owner_id
		elif owner_id.is_empty() or next_owner != owner_id:
			return {}
	elif (next_owner.is_empty() and not owner_id.is_empty()) \
			or (not owner_id.is_empty() and next_owner != owner_id):
		return {}
	var known_ids: Array[String] = []
	var known_seen: Dictionary = {}
	for recipe_id_variant in summary.known_recipe_ids as Array:
		if typeof(recipe_id_variant) != TYPE_STRING:
			return {}
		var recipe_id: String = str(recipe_id_variant)
		if recipe_id.is_empty() or known_seen.has(recipe_id) \
				or (not _catalog_recipe_ids.is_empty() and not _catalog_recipe_ids.has(recipe_id)):
			return {}
		known_seen[recipe_id] = true
		known_ids.append(recipe_id)
	if str(summary.migration_origin) == "legacy_unrecorded":
		for starter_id_variant in _known:
			var starter_id: String = str(starter_id_variant)
			if not known_seen.has(starter_id):
				known_ids.append(starter_id)
	var receipt_ids: Array[String] = []
	var receipt_seen: Dictionary = {}
	for receipt_variant in summary.event_receipt_ids as Array:
		if typeof(receipt_variant) != TYPE_STRING:
			return {}
		var receipt_id: String = str(receipt_variant)
		if receipt_id.is_empty() or receipt_seen.has(receipt_id):
			return {}
		receipt_seen[receipt_id] = true
		receipt_ids.append(receipt_id)
	var counts: Dictionary = {}
	for component_variant in summary.dismantle_counts as Dictionary:
		if typeof(component_variant) != TYPE_STRING \
				or str(component_variant).is_empty() \
				or not _is_nonnegative_json_integer(summary.dismantle_counts[component_variant]):
			return {}
		counts[str(component_variant)] = int(summary.dismantle_counts[component_variant])
	return {
		"owner_id": next_owner,
		"known_recipe_ids": known_ids,
		"event_receipt_ids": receipt_ids,
		"event_sequence": int(summary.event_sequence),
		"dismantle_counts": counts,
		"migration_origin": str(summary.migration_origin),
	}


static func _is_nonnegative_json_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 \
		and number <= MAX_SAFE_JSON_INTEGER and number == floor(number)


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
