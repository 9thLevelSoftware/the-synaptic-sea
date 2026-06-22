extends RefCounted
class_name LootRoller

## Pure, deterministic loot-table roller. Same (table_key, seed_source, tables)
## always yields the same result. Never touches the scene tree.

const LOOT_TABLES_PATH: String = "res://data/items/loot_tables.json"

static func load_tables() -> Dictionary:
	if not FileAccess.file_exists(LOOT_TABLES_PATH):
		return {}
	var file := FileAccess.open(LOOT_TABLES_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

## Returns [{item_id, quantity}], merged by item_id, ordered by item_id.
static func roll(table_key: String, seed_source: String, tables: Dictionary) -> Array:
	var table_variant: Variant = tables.get(table_key, null)
	if typeof(table_variant) != TYPE_DICTIONARY:
		return []
	var table: Dictionary = table_variant
	var entries_variant: Variant = table.get("entries", [])
	if typeof(entries_variant) != TYPE_ARRAY or (entries_variant as Array).is_empty():
		return []
	var entries: Array = entries_variant
	var rolls: int = max(1, int(table.get("rolls", 1)))

	var rng := RandomNumberGenerator.new()
	rng.seed = _stable_seed(seed_source)

	var total_weight: float = 0.0
	for entry in entries:
		total_weight += float((entry as Dictionary).get("weight", 1.0))
	if total_weight <= 0.0:
		return []

	var accum: Dictionary = {}  # item_id -> qty
	for _i in range(rolls):
		var pick: float = rng.randf() * total_weight
		var chosen: Dictionary = entries[0]
		for entry in entries:
			pick -= float((entry as Dictionary).get("weight", 1.0))
			if pick <= 0.0:
				chosen = entry
				break
		var item_id: String = str(chosen.get("item_id", ""))
		if item_id.is_empty():
			continue
		var qty: int = rng.randi_range(int(chosen.get("qty_min", 1)), int(chosen.get("qty_max", 1)))
		if qty <= 0:
			continue
		accum[item_id] = int(accum.get(item_id, 0)) + qty

	var out: Array = []
	var ids: Array = accum.keys()
	ids.sort()
	for item_id in ids:
		out.append({ "item_id": item_id, "quantity": int(accum[item_id]) })
	return out

## Deterministic non-negative seed from a string, stable within a Godot version.
static func _stable_seed(seed_source: String) -> int:
	return abs(seed_source.hash())
