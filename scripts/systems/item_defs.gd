extends RefCounted
class_name ItemDefs

## Shared, all-static item-definition lookups. Extracted from InventoryState so
## both the player inventory and the per-ship ShipInventory read one source of
## truth for weights, stack limits, categories, and display names. Tool defs are
## merged first with a synthetic 'tool' category + default weight (preserving the
## original InventoryState merge order and semantics).

const ITEM_DEFINITIONS_PATH: String = "res://data/items/item_definitions.json"
const MEDICINE_DEFINITIONS_PATH: String = "res://data/items/medicine_definitions.json"
const STIMULANT_DEFINITIONS_PATH: String = "res://data/items/stimulant_definitions.json"
const AMMO_DEFINITIONS_PATH: String = "res://data/combat/ammo_definitions.json"
const UTILITY_DEFINITIONS_PATH: String = "res://data/items/utility_item_definitions.json"
const TRADE_DEFINITIONS_PATH: String = "res://data/items/trade_item_definitions.json"
const TOOL_DEFINITIONS_PATH: String = "res://data/tools/tool_definitions.json"
const MATERIAL_DEFINITIONS_PATH: String = "res://data/materials/material_definitions.json"
const EQUIPMENT_DEFINITIONS_PATH: String = "res://data/items/equipment_definitions.json"
const JUNK_ITEMS_PATH: String = "res://data/items/junk_items.json"
const UNIQUE_ITEMS_PATH: String = "res://data/items/unique_items.json"
const RARITY_PALETTE_PATH: String = "res://data/ui/rarity_palette.json"
const DEFAULT_TOOL_WEIGHT: float = 2.0
const DEFAULT_MAX_STACK: int = 99

## Merged tool+item definitions. Tools first (so item_definitions can override),
## tool defs get a synthetic 'tool' category + default weight while preserving
## their 'effect' field.
static func load_definitions() -> Dictionary:
	var defs: Dictionary = {}
	var tool_defs: Dictionary = _read_json_dict(TOOL_DEFINITIONS_PATH)
	for tool_id in tool_defs:
		var raw_def: Variant = tool_defs[tool_id]
		if not (raw_def is Dictionary):
			continue   # skip malformed/corrupt tool entries rather than crash on .duplicate(null)
		var def: Dictionary = (raw_def as Dictionary).duplicate(true)
		def["category"] = "tool"
		if not def.has("weight"):
			def["weight"] = DEFAULT_TOOL_WEIGHT
		defs[tool_id] = def
	var item_defs: Dictionary = _read_json_dict(ITEM_DEFINITIONS_PATH)
	for item_id in item_defs:
		if not (item_defs[item_id] is Dictionary):
			continue   # skip malformed/corrupt item entries rather than store a non-dict def
		defs[item_id] = item_defs[item_id]
	for extra_path in [
		MEDICINE_DEFINITIONS_PATH,
		STIMULANT_DEFINITIONS_PATH,
		AMMO_DEFINITIONS_PATH,
		UTILITY_DEFINITIONS_PATH,
		TRADE_DEFINITIONS_PATH,
	]:
		var extra_defs: Dictionary = _read_json_dict(extra_path)
		for item_id in extra_defs:
			if not (extra_defs[item_id] is Dictionary):
				continue
			# Field-merge onto any existing base def so keys present only in the
			# base are preserved when a secondary file defines the same item with
			# a different subset of fields (the extra file's fields win per-key).
			if defs.has(item_id) and defs[item_id] is Dictionary:
				var merged: Dictionary = (defs[item_id] as Dictionary).duplicate(true)
				for key in (extra_defs[item_id] as Dictionary):
					merged[key] = (extra_defs[item_id] as Dictionary)[key]
				defs[item_id] = merged
			else:
				defs[item_id] = extra_defs[item_id]
	# Crafting materials (data/materials/material_definitions.json, wrapped in
	# a "materials" root key). FILL-ONLY: an id already defined above (e.g.
	# scrap_metal, power_cell in item_definitions.json) keeps its live-balance
	# definition; only the ~26 material-only ids are added. Before this merge
	# every crafting material resolved with weight=0 and no category.
	var material_root: Dictionary = _read_json_dict(MATERIAL_DEFINITIONS_PATH)
	var material_defs: Variant = material_root.get("materials", {})
	if material_defs is Dictionary:
		for mat_id in (material_defs as Dictionary):
			var raw_mat: Variant = (material_defs as Dictionary)[mat_id]
			if not (raw_mat is Dictionary):
				continue
			if not defs.has(mat_id):
				defs[mat_id] = raw_mat
	var equip_defs: Dictionary = _read_json_dict(EQUIPMENT_DEFINITIONS_PATH)
	for equip_id in equip_defs:
		var raw_equip: Variant = equip_defs[equip_id]
		if not (raw_equip is Dictionary):
			continue   # skip malformed entries rather than crash
		defs[equip_id] = raw_equip
	var junk_root: Dictionary = _read_json_dict(JUNK_ITEMS_PATH)
	var junk_defs: Variant = junk_root.get("items", {})
	if junk_defs is Dictionary:
		for junk_id in (junk_defs as Dictionary):
			var raw_junk: Variant = (junk_defs as Dictionary)[junk_id]
			if not (raw_junk is Dictionary):
				continue
			if defs.has(junk_id) and defs[junk_id] is Dictionary:
				var merged_junk: Dictionary = (defs[junk_id] as Dictionary).duplicate(true)
				for key in (raw_junk as Dictionary):
					merged_junk[key] = (raw_junk as Dictionary)[key]
				defs[junk_id] = merged_junk
			else:
				defs[junk_id] = raw_junk
	var unique_root: Dictionary = _read_json_dict(UNIQUE_ITEMS_PATH)
	var unique_defs: Variant = unique_root.get("items", {})
	if unique_defs is Dictionary:
		for unique_id in (unique_defs as Dictionary):
			var raw_unique: Variant = (unique_defs as Dictionary)[unique_id]
			if not (raw_unique is Dictionary):
				continue
			var item_id: String = str((raw_unique as Dictionary).get("item_id", unique_id))
			if defs.has(item_id) and defs[item_id] is Dictionary:
				var merged_unique: Dictionary = (defs[item_id] as Dictionary).duplicate(true)
				for key in (raw_unique as Dictionary):
					merged_unique[key] = (raw_unique as Dictionary)[key]
				defs[item_id] = merged_unique
	return defs

static func _read_json_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

static func get_definition(defs: Dictionary, item_id: String) -> Dictionary:
	var def: Variant = defs.get(item_id, {})
	return def if def is Dictionary else {}

static func category(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("category", ""))

static func weight_each(defs: Dictionary, item_id: String) -> float:
	# Unknown items weigh 0 so a foreign save round-trips without corrupting the cap.
	return float(get_definition(defs, item_id).get("weight", 0.0))

static func max_stack(defs: Dictionary, item_id: String) -> int:
	return int(get_definition(defs, item_id).get("max_stack", DEFAULT_MAX_STACK))

static func display_name(defs: Dictionary, item_id: String) -> String:
	var name: String = str(get_definition(defs, item_id).get("display_name", ""))
	return name if not name.is_empty() else item_id.replace("_", " ").capitalize()

static func equip_slot(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("equip_slot", ""))

static func container_capacity(defs: Dictionary, item_id: String) -> float:
	return float(get_definition(defs, item_id).get("container_capacity", 0.0))

static func weight_reduction(defs: Dictionary, item_id: String) -> float:
	return clampf(float(get_definition(defs, item_id).get("weight_reduction", 0.0)), 0.0, 1.0)

static func effects(defs: Dictionary, item_id: String) -> Array:
	var e: Variant = get_definition(defs, item_id).get("effects", [])
	return e if e is Array else []

static func icon(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("icon", ""))

static func rarity(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("rarity", "common"))

static func codex_entry_id(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("codex_entry_id", ""))

static func unique_id(defs: Dictionary, item_id: String) -> String:
	return str(get_definition(defs, item_id).get("unique_id", ""))

static func junk_yields(defs: Dictionary, item_id: String) -> Array:
	var yields_v: Variant = get_definition(defs, item_id).get("junk_yields", [])
	return (yields_v as Array).duplicate(true) if yields_v is Array else []

static func rarity_color_hex(item_id: String) -> String:
	var palette_root: Dictionary = _read_json_dict(RARITY_PALETTE_PATH)
	var rarities: Variant = palette_root.get("rarities", {})
	if rarities is Dictionary:
		var rarity_id: String = rarity(load_definitions(), item_id)
		var entry: Variant = (rarities as Dictionary).get(rarity_id, {})
		if entry is Dictionary:
			return str((entry as Dictionary).get("color", "#9AA4AF"))
	return "#9AA4AF"
