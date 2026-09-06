extends RefCounted
class_name DeconstructionResolver

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const JunkYieldResolverScript := preload("res://scripts/systems/junk_yield_resolver.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

## Pure model for breaking items down into base materials.
## Reads deconstruction recipes (category == "deconstruction") from the
## recipe catalog and resolves them against inventory. Also runs the
## JunkYieldResolver catalog for raw junk salvage (Stream E residual MVP).
## Never touches the scene tree.

var _crafting_state = CraftingStateScript.new()
var _junk_defs: Dictionary = {}

func _init() -> void:
	_junk_defs = JunkYieldResolverScript.load_definitions()

## Returns all deconstruction recipes.
func get_deconstruction_recipes() -> Array:
	return _crafting_state.get_recipes_by_category("deconstruction")

## Returns true if the inventory has the target item to deconstruct.
func can_deconstruct(recipe_id: String, inventory) -> bool:
	var recipe: Dictionary = _crafting_state.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if str(recipe.get("category", "")) != "deconstruction":
		return false
	return _crafting_state.can_craft(recipe_id, inventory)

## Deconstructs an item, consuming it and producing base materials.
## Returns the produces dict {item_id, quantity} or empty dict on failure.
## PKG-B2.4a: output quality inherits source material quality × skill × tool (no 0.5 hardcode).
## context optional keys: skill_level (int), tool_factor (float, default 1.0)
func deconstruct(recipe_id: String, inventory, material_state, context: Dictionary = {}) -> Dictionary:
	var recipe: Dictionary = _crafting_state.get_recipe(recipe_id)
	if recipe.is_empty():
		return {}
	if str(recipe.get("category", "")) != "deconstruction":
		return {}
	var candidate = _inventory_candidate(inventory)
	if candidate == null or not can_deconstruct(recipe_id, candidate):
		return {}
	var ingredients: Dictionary = recipe.get("ingredients", {}) as Dictionary
	var ingredient_ids: Array = ingredients.keys()
	ingredient_ids.sort()
	if ingredient_ids.size() != 1 or int(ingredients[ingredient_ids[0]]) != 1:
		return {}
	var source_item_id: String = str(ingredient_ids[0])
	var taken: Array = candidate.take_lots(source_item_id, 1)
	if taken.size() != 1:
		return {}
	var source_lot: Dictionary = taken[0] as Dictionary
	# Lot state is the modern quality authority. MaterialState is retained only as
	# a compatibility fallback for an older source shape without lot metadata.
	var source_quality: float = _source_ingredient_quality(recipe, material_state)
	if source_lot.has("quality_score"):
		source_quality = clampf(float(source_lot.quality_score), 0.0, 1.0)
	var skill_level: int = int(context.get("skill_level", 0))
	var tool_factor: float = maxf(0.25, float(context.get("tool_factor", 1.0)))
	var out_quality: float = _resolve_yield_quality(source_quality, skill_level, tool_factor)
	var produces: Dictionary = _crafting_state.get_produces(recipe_id)
	var out_id: String = str(produces.get("item_id", ""))
	var out_qty: int = int(produces.get("quantity", 0))
	if out_id.is_empty() or out_qty <= 0:
		return {}
	var salvage_lot_id: String = _yield_lot_id("deconstruct:%s" % recipe_id, str(source_lot.lot_id), 0, out_id)
	var output_lot: Dictionary = {
		"lot_id": salvage_lot_id,
		"item_id": out_id,
		"quantity": out_qty,
		"quality_score": out_quality,
		"quality_tier": QualityTierResolverScript.tier_for_score(out_quality),
		"condition": 1.0,
		"origin": {"salvage_target": recipe_id, "source_lot_id": str(source_lot.lot_id)},
	}
	var pending: RefCounted = context.get("pending_output_store", null) as RefCounted
	if pending != null:
		var receipt_id: String = _salvage_receipt_id(
			str(context.get("ship_id", "")), str(context.get("station_instance_id", "")),
			recipe_id, str(source_lot.lot_id))
		if not _commit_pending_salvage(
			pending, receipt_id, [output_lot], inventory, candidate,
			str(context.get("station_instance_id", "")), str(inventory.get_holder_namespace())):
			return {}
	else:
		if not candidate.can_accept(out_id, out_qty) or candidate.add_lot(output_lot) != out_qty \
				or not inventory.apply_summary(candidate.get_summary()):
			return {}
	if material_state != null and material_state.has_method("has_definition") \
			and material_state.has_definition(out_id) and material_state.has_method("set_quality"):
		material_state.set_quality(out_id, out_quality)
	var result: Dictionary = produces.duplicate()
	result["quality"] = out_quality
	result["source_quality"] = source_quality
	result["salvage_lot_id"] = salvage_lot_id
	result["deposited"] = pending == null
	result["pending"] = pending != null
	result["output_lots"] = [output_lot]
	return result


func _source_ingredient_quality(recipe: Dictionary, material_state) -> float:
	if material_state == null or not material_state.has_method("get_quality"):
		return 0.5
	var ingredients: Variant = recipe.get("ingredients", {})
	if typeof(ingredients) != TYPE_DICTIONARY or (ingredients as Dictionary).is_empty():
		return 0.5
	var total: float = 0.0
	var weight: float = 0.0
	for mat_id in (ingredients as Dictionary).keys():
		var qty: float = float((ingredients as Dictionary)[mat_id])
		var q: float = float(material_state.get_quality(str(mat_id)))
		total += q * qty
		weight += qty
	if weight <= 0.0:
		return 0.5
	return clampf(total / weight, 0.0, 1.0)


## Quality inheritance curve: source × (0.8 + 0.04*skill) × tool_factor, clamped.
static func _resolve_yield_quality(source_quality: float, skill_level: int, tool_factor: float) -> float:
	var skill_curve: float = 0.80 + 0.04 * float(clampi(skill_level, 0, 10))
	return clampf(source_quality * skill_curve * tool_factor, 0.0, 1.0)

## Auto-deconstruct: finds the first deconstruction recipe for a given item_id
## and executes it. Returns the produces dict or empty.
func auto_deconstruct(item_id: String, inventory, material_state) -> Dictionary:
	for recipe in get_deconstruction_recipes():
		var ingredients: Variant = recipe.get("ingredients", {})
		if ingredients is Dictionary and (ingredients as Dictionary).has(item_id):
			return deconstruct(str(recipe.get("recipe_id", "")), inventory, material_state)
	return {}

## REQ-CS-017: headless salvage target listing for the picker.
## Returns Array[Dictionary] sorted by recipe_id. Shape matches craft list rows so
## RecipePickerPanel can reuse them (recipe_id is the selection key).
##   deconstruct: recipe_id = catalog id
##   junk:        recipe_id = "junk:<source_item_id>"
func list_salvage_entries(inventory, allow_pending_output: bool = false) -> Array:
	var out: Array = []
	if inventory == null:
		return out
	if _junk_defs.is_empty():
		_junk_defs = JunkYieldResolverScript.load_definitions()
	# 1) Deconstruction recipes (catalog order by recipe_id).
	var recipes: Array = get_deconstruction_recipes()
	recipes.sort_custom(func(a, b): return str(a.get("recipe_id", "")) < str(b.get("recipe_id", "")))
	for recipe in recipes:
		if not (recipe is Dictionary):
			continue
		var rid: String = str(recipe.get("recipe_id", ""))
		if rid.is_empty():
			continue
		var produces: Dictionary = {}
		var produces_raw: Variant = recipe.get("produces", {})
		if produces_raw is Dictionary:
			produces = (produces_raw as Dictionary).duplicate()
		var ingredients: Dictionary = {}
		var ingredients_raw: Variant = recipe.get("ingredients", {})
		if ingredients_raw is Dictionary:
			ingredients = (ingredients_raw as Dictionary).duplicate()
		var status: String = "ready"
		if not can_deconstruct(rid, inventory):
			status = "missing_ingredients"
		else:
			var out_id: String = str(produces.get("item_id", ""))
			var out_qty: int = int(produces.get("quantity", 0))
			if not allow_pending_output and not out_id.is_empty() and out_qty > 0 \
					and inventory.has_method("can_accept") \
					and not inventory.can_accept(out_id, out_qty):
				status = "output_full"
		out.append({
			"recipe_id": rid,
			"display_name": str(recipe.get("display_name", rid)),
			"category": "deconstruction",
			"required_skill_level": 0,
			"ingredients": ingredients,
			"produces": produces,
			"craft_time_seconds": 0.0,
			"status": status,
			"craftable": status == "ready",
			"salvage_kind": "deconstruct",
		})
	# 2) Junk catalog items currently in inventory (sorted by item id).
	var ids: Array = inventory.items.keys() if inventory.items is Dictionary else []
	ids.sort()
	for item_id_variant in ids:
		var item_id: String = str(item_id_variant)
		if inventory.get_quantity(item_id) <= 0:
			continue
		var yields: Array = JunkYieldResolverScript.yields_for_item(item_id, _junk_defs)
		if yields.is_empty():
			continue
		var materials: Dictionary = {}
		var first_id: String = ""
		var first_qty: int = 0
		var can_all: bool = true
		for entry_variant in yields:
			if not (entry_variant is Dictionary):
				continue
			var entry: Dictionary = entry_variant
			var mid: String = str(entry.get("material_id", ""))
			var qty: int = int(entry.get("quantity", 0))
			if mid.is_empty() or qty <= 0:
				continue
			materials[mid] = int(materials.get(mid, 0)) + qty
			if first_id.is_empty():
				first_id = mid
				first_qty = qty
			if not allow_pending_output and inventory.has_method("can_accept") \
					and not inventory.can_accept(mid, qty):
				can_all = false
		if first_id.is_empty():
			continue
		var jstatus: String = "ready" if can_all else "output_full"
		out.append({
			"recipe_id": "junk:%s" % item_id,
			"display_name": "Salvage %s" % item_id,
			"category": "junk",
			"required_skill_level": 0,
			"ingredients": {item_id: 1},
			"produces": {"item_id": first_id, "quantity": first_qty},
			"craft_time_seconds": 0.0,
			"status": jstatus,
			"craftable": jstatus == "ready",
			"salvage_kind": "junk",
			"source_item_id": item_id,
			"materials": materials,
		})
	# Keep a single sorted list by selection key.
	out.sort_custom(func(a, b): return str(a.get("recipe_id", "")) < str(b.get("recipe_id", "")))
	return out

func first_ready_salvage_id(inventory, allow_pending_output: bool = false) -> String:
	for entry in list_salvage_entries(inventory, allow_pending_output):
		if entry is Dictionary and bool((entry as Dictionary).get("craftable", false)):
			return str((entry as Dictionary).get("recipe_id", ""))
	return ""

## Execute a listed salvage target id (recipe_id from list_salvage_entries).
func execute_salvage_target(target_id: String, inventory, material_state, context: Dictionary = {}) -> Dictionary:
	if target_id.is_empty() or inventory == null:
		return {}
	if target_id.begins_with("junk:"):
		var junk_id: String = target_id.substr(5)
		return salvage_junk_item(junk_id, inventory, material_state, context)
	var produced: Dictionary = deconstruct(target_id, inventory, material_state, context)
	return produced

## Stream E: salvage the first inventory junk item that has a JunkYieldResolver
## catalog entry. Deterministic (sorted item ids). Returns produces-shaped dict
## for the primary material plus multi-yield metadata, or empty on no match.
##
## Shape on success:
##   {item_id, quantity, source_junk, materials: {mid: qty}, multi_yield: true}
func salvage_junk(inventory, material_state) -> Dictionary:
	if inventory == null:
		return {}
	if _junk_defs.is_empty():
		_junk_defs = JunkYieldResolverScript.load_definitions()
	var ids: Array = inventory.items.keys() if inventory.items is Dictionary else []
	ids.sort()
	for item_id_variant in ids:
		var item_id: String = str(item_id_variant)
		if inventory.get_quantity(item_id) <= 0:
			continue
		var result: Dictionary = salvage_junk_item(item_id, inventory, material_state)
		if not result.is_empty():
			return result
	return {}

## Stream E + REQ-CS-017: salvage one specific junk item_id if catalogued.
func salvage_junk_item(item_id: String, inventory, material_state, context: Dictionary = {}) -> Dictionary:
	if item_id.is_empty() or inventory == null:
		return {}
	if inventory.get_quantity(item_id) <= 0:
		return {}
	if _junk_defs.is_empty():
		_junk_defs = JunkYieldResolverScript.load_definitions()
	var yields: Array = JunkYieldResolverScript.yields_for_item(item_id, _junk_defs)
	if yields.is_empty():
		return {}
	var candidate = _inventory_candidate(inventory)
	if candidate == null:
		return {}
	var taken: Array = candidate.take_lots(item_id, 1)
	if taken.size() != 1:
		return {}
	var source_lot: Dictionary = taken[0] as Dictionary
	var totals: Dictionary = {}
	for entry_variant in yields:
		if not (entry_variant is Dictionary):
			return {}
		var entry: Dictionary = entry_variant as Dictionary
		var material_id: String = str(entry.get("material_id", ""))
		var quantity: int = int(entry.get("quantity", 0))
		if material_id.is_empty() or quantity <= 0:
			return {}
		totals[material_id] = int(totals.get(material_id, 0)) + quantity
	var materials: Dictionary = {}
	var output_lots: Array = []
	var first_id: String = ""
	var first_qty: int = 0
	var quality: float = _resolve_yield_quality(float(source_lot.quality_score), 0, 1.0)
	for yield_index in range(yields.size()):
		var y: Dictionary = yields[yield_index] as Dictionary
		var mid2: String = str(y.get("material_id", ""))
		var qty2: int = int(y.get("quantity", 0))
		var output_lot: Dictionary = {
			"lot_id": _yield_lot_id("junk:%s" % item_id, str(source_lot.lot_id), yield_index, mid2),
			"item_id": mid2, "quantity": qty2, "quality_score": quality,
			"quality_tier": QualityTierResolverScript.tier_for_score(quality), "condition": 1.0,
			"origin": {"junk_source": item_id, "source_lot_id": str(source_lot.lot_id)},
		}
		output_lots.append(output_lot)
		materials[mid2] = int(materials.get(mid2, 0)) + qty2
		if first_id.is_empty():
			first_id = mid2
			first_qty = qty2
	if first_id.is_empty():
		return {}
	var pending: RefCounted = context.get("pending_output_store", null) as RefCounted
	if pending != null:
		var receipt_id: String = _salvage_receipt_id(
			str(context.get("ship_id", "")), str(context.get("station_instance_id", "")),
			"junk:%s" % item_id, str(source_lot.lot_id))
		if not _commit_pending_salvage(
			pending, receipt_id, output_lots, inventory, candidate,
			str(context.get("station_instance_id", "")), str(inventory.get_holder_namespace())):
			return {}
	else:
		for output_lot_variant in output_lots:
			var output_lot: Dictionary = output_lot_variant
			if not candidate.can_accept(str(output_lot.item_id), int(output_lot.quantity)) \
					or candidate.add_lot(output_lot) != int(output_lot.quantity):
				return {}
		if not inventory.apply_summary(candidate.get_summary()):
			return {}
	for material_id in materials:
		if material_state != null and material_state.has_method("has_definition") \
				and material_state.has_definition(str(material_id)) \
				and material_state.has_method("set_quality"):
			material_state.set_quality(str(material_id), quality)
	return {
		"item_id": first_id,
		"quantity": first_qty,
		"source_junk": item_id,
		"materials": materials,
		"multi_yield": materials.size() > 1,
		"pending": pending != null,
		"deposited": pending == null,
		"output_lots": output_lots,
	}


func _commit_pending_salvage(
		store: RefCounted,
		receipt_id: String,
		lots: Array,
		inventory: RefCounted,
		inventory_candidate: RefCounted,
		station_instance_id: String,
		source_holder_id: String) -> bool:
	if receipt_id.is_empty() or station_instance_id.is_empty() \
			or not store.has_method("deposit_once") or not store.has_method("apply_summary"):
		return false
	var store_before: Dictionary = store.call("get_summary")
	var inventory_before: Dictionary = inventory.call("get_summary")
	var metadata: Dictionary = {
		"station_instance_id": station_instance_id,
		"producer_kind": "salvage",
		"producer_id": receipt_id,
		"purpose": "output",
		"source_holder_id": source_holder_id,
	}
	# Existing receipts are terminal idempotency authority. Never consume a
	# source again even if a crash left the source visible after publication.
	if not bool(store.call("deposit_once", receipt_id, lots, metadata)):
		return false
	if inventory.call("apply_summary", inventory_candidate.call("get_summary")):
		return true
	# Both sides roll back when source publication fails.
	store.call("apply_summary", store_before)
	inventory.call("apply_summary", inventory_before)
	return false


static func _salvage_receipt_id(
		ship_id: String, station_instance_id: String, target_id: String, source_lot_id: String) -> String:
	if ship_id.is_empty() or station_instance_id.is_empty() or source_lot_id.is_empty():
		return ""
	return "%s/%s/salvage:%s:source=%s" % [ship_id, station_instance_id, target_id, source_lot_id]

func _inventory_candidate(inventory):
	if inventory == null or not inventory.has_method("get_summary") \
			or not inventory.has_method("apply_summary") \
			or not inventory.has_method("get_holder_namespace") \
			or not inventory.has_method("take_lots") or not inventory.has_method("add_lot") \
			or not inventory.has_method("can_accept"):
		return null
	var candidate = InventoryStateScript.new(str(inventory.get_holder_namespace()))
	if not candidate.apply_summary(inventory.get_summary()):
		return null
	return candidate

static func _yield_lot_id(action_id: String, source_lot_id: String, yield_index: int, item_id: String) -> String:
	return "salvage:%s:source=%s:yield=%03d:%s" % [action_id, source_lot_id, yield_index, item_id]

func get_summary() -> Dictionary:
	return {
		"deconstruction_recipes": get_deconstruction_recipes().size(),
		"junk_catalog_items": _junk_defs.size(),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	return false

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Deconstruction recipes: %d" % get_deconstruction_recipes().size())
	return lines
