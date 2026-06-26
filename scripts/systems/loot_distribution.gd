extends RefCounted
class_name LootDistribution

const LootRollerScript := preload("res://scripts/systems/loot_roller.gd")
const RarityTierScript := preload("res://scripts/systems/rarity_tier.gd")
const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

static func roll(table_key: String, seed_source: String, tables: Dictionary, context: Dictionary = {}) -> Array:
	var table_variant: Variant = tables.get(table_key, null)
	if typeof(table_variant) != TYPE_DICTIONARY:
		return []
	var table: Dictionary = table_variant
	var entries_variant: Variant = table.get("entries", [])
	if typeof(entries_variant) != TYPE_ARRAY or (entries_variant as Array).is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = LootRollerScript._stable_seed("%s|%s|%s|%s|%s" % [
		table_key,
		seed_source,
		str(context.get("biome_id", "abyssal_synaptic_sea")),
		str(context.get("depth", 0)),
		str(context.get("container_kind", str(table.get("container_kind", table_key)))),
	])
	var rolls: int = max(1, int(table.get("rolls", 1)))
	var item_defs: Dictionary = context.get("item_definitions", ItemDefsScript.load_definitions())
	var results: Array = []
	var unique_state = context.get("unique_state", null)
	for roll_index in range(rolls):
		var weighted: Array = _weighted_entries(entries_variant as Array, context, unique_state, seed_source, item_defs)
		if weighted.is_empty():
			continue
		var choice: Dictionary = _choose_entry(weighted, rng)
		var qty_min: int = int(choice.get("qty_min", 1))
		var qty_max: int = int(choice.get("qty_max", max(1, qty_min)))
		var quantity: int = rng.randi_range(mini(qty_min, qty_max), maxi(qty_min, qty_max))
		if quantity <= 0:
			continue
		var item_id: String = str(choice.get("item_id", ""))
		if item_id.is_empty():
			continue
		var rarity: String = _resolve_rarity(choice, context, rng, item_defs, item_id)
		var unique_id: String = str(choice.get("unique_id", ItemDefsScript.unique_id(item_defs, item_id)))
		var codex_entry_id: String = str(choice.get("codex_entry_id", ItemDefsScript.codex_entry_id(item_defs, item_id)))
		var entry: Dictionary = {
			"item_id": item_id,
			"quantity": quantity,
			"rarity": rarity,
			"container_kind": str(context.get("container_kind", str(table.get("container_kind", table_key)))),
			"biome_id": str(context.get("biome_id", "abyssal_synaptic_sea")),
			"depth": int(context.get("depth", 0)),
			"condition": str(context.get("condition", "damaged")),
			"seed_key": "%s|%d|%s" % [seed_source, roll_index, item_id],
			"world_unique": not unique_id.is_empty(),
		}
		if not unique_id.is_empty():
			entry["unique_id"] = unique_id
		if not codex_entry_id.is_empty():
			entry["codex_entry_id"] = codex_entry_id
		results.append(entry)
	return _merge_results(results)

static func _weighted_entries(entries: Array, context: Dictionary, unique_state, seed_source: String, item_defs: Dictionary) -> Array:
	var out: Array = []
	var biome_id: String = str(context.get("biome_id", "abyssal_synaptic_sea"))
	var depth: int = int(context.get("depth", 0))
	var condition: String = str(context.get("condition", "damaged"))
	var container_kind: String = str(context.get("container_kind", "generic_crate"))
	for entry_v in entries:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = (entry_v as Dictionary).duplicate(true)
		var item_id: String = str(entry.get("item_id", ""))
		if item_id.is_empty():
			continue
		var unique_id: String = str(entry.get("unique_id", ItemDefsScript.unique_id(item_defs, item_id)))
		if unique_state != null and not unique_id.is_empty() and unique_state.has_method("can_claim"):
			var probe_seed: String = "%s|%s" % [seed_source, item_id]
			if not bool(unique_state.can_claim(unique_id, probe_seed)):
				continue
		var weight: float = maxf(0.0, float(entry.get("weight", 1.0)))
		weight *= _lookup_multiplier(entry.get("biome_weights", {}), biome_id)
		weight *= _lookup_multiplier(entry.get("condition_weights", {}), condition)
		weight *= _lookup_multiplier(entry.get("container_weights", {}), container_kind)
		weight *= maxf(0.10, 1.0 + float(entry.get("depth_weight_scale", 0.0)) * float(depth))
		weight *= RarityTierScript.weight_multiplier(str(entry.get("rarity", ItemDefsScript.rarity(item_defs, item_id))))
		if weight > 0.0:
			entry["_effective_weight"] = weight
			out.append(entry)
	return out

static func _choose_entry(weighted: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total_weight: float = 0.0
	for entry in weighted:
		total_weight += float((entry as Dictionary).get("_effective_weight", 0.0))
	if total_weight <= 0.0:
		return {}
	var pick: float = rng.randf() * total_weight
	for entry in weighted:
		pick -= float((entry as Dictionary).get("_effective_weight", 0.0))
		if pick <= 0.0:
			return (entry as Dictionary).duplicate(true)
	return (weighted.back() as Dictionary).duplicate(true)

static func _lookup_multiplier(variant: Variant, key: String) -> float:
	if variant is Dictionary:
		var table: Dictionary = variant as Dictionary
		if table.has(key):
			return maxf(0.0, float(table[key]))
		if table.has("default"):
			return maxf(0.0, float(table["default"]))
	return 1.0

static func _resolve_rarity(entry: Dictionary, context: Dictionary, rng: RandomNumberGenerator, item_defs: Dictionary, item_id: String) -> String:
	var explicit: String = str(entry.get("rarity", ""))
	if not explicit.is_empty():
		return RarityTierScript.normalize(explicit)
	var base_roll: float = rng.randf()
	base_roll += 0.04 * float(context.get("depth", 0))
	if str(context.get("biome_id", "")) == "dead_fleet":
		base_roll += 0.06
	if str(context.get("condition", "damaged")) == "wrecked":
		base_roll += 0.04
	var from_roll: String = RarityTierScript.from_roll(base_roll)
	return RarityTierScript.max_rarity(ItemDefsScript.rarity(item_defs, item_id), from_roll)

static func _merge_results(results: Array) -> Array:
	var merged: Dictionary = {}
	for result_v in results:
		if not (result_v is Dictionary):
			continue
		var result: Dictionary = result_v
		var key: String = str(result.get("unique_id", result.get("item_id", "")))
		if key.is_empty():
			continue
		if not merged.has(key):
			merged[key] = result.duplicate(true)
		else:
			var current: Dictionary = merged[key]
			current["quantity"] = int(current.get("quantity", 0)) + int(result.get("quantity", 0))
			current["rarity"] = RarityTierScript.max_rarity(str(current.get("rarity", "common")), str(result.get("rarity", "common")))
			merged[key] = current
	var keys: Array = merged.keys()
	keys.sort()
	var out: Array = []
	for key in keys:
		out.append(merged[key])
	return out
