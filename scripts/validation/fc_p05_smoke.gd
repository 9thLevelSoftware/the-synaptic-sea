extends SceneTree

## P05 / FC-06: exact crafted quality is deterministic, visible, and reaches
## the currently authored tool, repair, consumable, and component consumers.
## Marker: FC P05 PASS

const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")
const ItemQualityEffectsScript := preload("res://scripts/systems/item_quality_effects.gd")
const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const ConsumableStateScript := preload("res://scripts/systems/consumable_state.gd")
const MedicineStateScript := preload("res://scripts/systems/medicine_state.gd")
const StimulantStateScript := preload("res://scripts/systems/stimulant_state.gd")
const InventoryStateScript := preload("res://scripts/systems/inventory_state.gd")
const VitalsStateScript := preload("res://scripts/systems/vitals_state.gd")
const SanityStateScript := preload("res://scripts/systems/sanity_state.gd")
const EffectDispatcherScript := preload("res://scripts/systems/effect_dispatcher.gd")
const EquipmentStateScript := preload("res://scripts/systems/equipment_state.gd")
const InventoryPanelScript := preload("res://scripts/ui/inventory_panel.gd")
const RecipePickerPanelScript := preload("res://scripts/ui/recipe_picker_panel.gd")
const WorkActionDriverScript := preload("res://scripts/systems/work_action_driver.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementScript := preload("res://scripts/systems/component_placement_state.gd")
const ShipModificationScript := preload("res://scripts/systems/ship_modification_state.gd")
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

const TIMEOUT_FRAMES: int = 300

var _main: Node = null
var _playable = null
var _frames: int = 0
var _finished: bool = false
var _crafted: Dictionary = {}


func _initialize() -> void:
	if not _verify_catalog_coverage_and_exact_crafting():
		return
	if not _verify_consumable_quality():
		return
	if not _verify_tool_speed_once():
		return
	if not _verify_component_mount_quality():
		return
	if not await _verify_inventory_rows_and_exact_use():
		return
	_main = MAIN_SCENE.instantiate()
	get_root().add_child(_main)
	process_frame.connect(_on_frame)


func _verify_catalog_coverage_and_exact_crafting() -> bool:
	if not is_equal_approx(QualityTierResolverScript.compute_score(1.0, 99, 99, true), 1.0) \
			or QualityTierResolverScript.tier_for_score(1.0) != "masterwork":
		_fail("authored quality curve cannot reach masterwork")
		return false
	var recipe_root: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/recipes/recipe_definitions.json"))
	if not recipe_root is Dictionary or not (recipe_root as Dictionary).get("recipes", []) is Array:
		_fail("recipe catalog")
		return false
	var effects = ItemQualityEffectsScript.new()
	var quality_root: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/items/quality_effects.json"))
	if not quality_root is Dictionary or not (quality_root as Dictionary).get("items", {}) is Dictionary:
		_fail("quality effects catalog")
		return false
	var explicit_effect_rows: Dictionary = (quality_root as Dictionary).get("items", {}) as Dictionary
	var output_ids: Dictionary = {}
	var counts: Dictionary = {}
	for recipe_v in (recipe_root as Dictionary).get("recipes", []) as Array:
		if not recipe_v is Dictionary:
			_fail("malformed recipe row")
			return false
		var produces_v: Variant = (recipe_v as Dictionary).get("produces", {})
		if not produces_v is Dictionary:
			_fail("malformed recipe output")
			return false
		var item_id: String = str((produces_v as Dictionary).get("item_id", ""))
		if item_id.is_empty():
			_fail("empty recipe output")
			return false
		output_ids[item_id] = true
	for item_id_v in output_ids.keys():
		if not explicit_effect_rows.has(str(item_id_v)):
			_fail("recipe output lacks explicit quality rule %s" % str(item_id_v))
			return false
		var consumer: String = effects.consumer_for(str(item_id_v))
		if consumer not in ItemQualityEffectsScript.VALID_CONSUMERS:
			_fail("invalid output consumer %s=%s" % [str(item_id_v), consumer])
			return false
		counts[consumer] = int(counts.get(consumer, 0)) + 1
	if output_ids.size() != 53 or int(counts.get("quantity_only", 0)) != 49 \
			or int(counts.get("consumable_potency", 0)) != 2 \
			or int(counts.get("repair_integrity", 0)) != 1 \
			or int(counts.get("tool_work_speed", 0)) != 1 \
			or int(counts.get("component_efficiency", 0)) != 0:
		_fail("dishonest recipe output classifications outputs=%d counts=%s" % [output_ids.size(), str(counts)])
		return false
	if not _verify_preview_selection_order():
		return false

	# The crafted component bridge belongs to P09. P05 still proves every actual
	# physical component item form has a declared live consumer.
	var component_root: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/components/component_catalog.json"))
	if not component_root is Dictionary or not (component_root as Dictionary).get("components", {}) is Dictionary:
		_fail("component catalog")
		return false
	for component_v in ((component_root as Dictionary).get("components", {}) as Dictionary).values():
		if component_v is Dictionary:
			var item_form: String = str((component_v as Dictionary).get("item_form", ""))
			if not item_form.is_empty() and effects.consumer_for(item_form) != "component_efficiency":
				_fail("physical component quality missing for %s" % item_form)
				return false

	var low_sealant: Dictionary = _craft_recipe("craft_sealant", 0.1, "poor", 0, 0, true, "low-sealant")
	var high_sealant: Dictionary = _craft_recipe("craft_sealant", 1.0, "masterwork", 99, 5, true, "high-sealant")
	var low_repair: Dictionary = _craft_recipe("craft_hull_sealant", 0.1, "poor", 2, 0, true, "low-repair")
	var high_repair: Dictionary = _craft_recipe("craft_hull_sealant", 1.0, "masterwork", 99, 5, true, "high-repair")
	var low_meal: Dictionary = _craft_recipe("cook_basic_meal", 0.1, "poor", 0, 0, true, "low-meal")
	var high_meal: Dictionary = _craft_recipe("cook_protein_fry", 1.0, "masterwork", 99, 5, true, "high-meal")
	var low_paste: Dictionary = _craft_recipe(
		"synthesize_nutrient_paste", 0.1, "poor", 0, 0, true, "low-paste")
	var high_paste: Dictionary = _craft_recipe(
		"synthesize_nutrient_paste", 1.0, "masterwork", 99, 5, true, "high-paste")
	var low_quantity: Dictionary = _craft_recipe("weld_plating", 0.1, "poor", 0, 0, true, "low-quantity")
	var high_quantity: Dictionary = _craft_recipe("weld_plating", 1.0, "masterwork", 99, 5, true, "high-quantity")
	for output_v in [
		low_sealant, high_sealant, low_repair, high_repair,
		low_meal, high_meal, low_paste, high_paste, low_quantity, high_quantity,
	]:
		if (output_v as Dictionary).is_empty():
			return false
	if str(low_sealant.get("quality_tier", "")) != "poor" \
			or str(high_sealant.get("quality_tier", "")) != "masterwork" \
			or str(low_repair.get("quality_tier", "")) != "poor" \
			or str(high_repair.get("quality_tier", "")) != "masterwork" \
			or str(low_meal.get("quality_tier", "")) != "poor" \
			or str(high_meal.get("quality_tier", "")) != "masterwork" \
			or str(low_paste.get("quality_tier", "")) != "poor" \
			or str(high_paste.get("quality_tier", "")) != "masterwork":
		_fail("crafted consumer outputs did not span poor/masterwork")
		return false
	if int(low_quantity.get("quantity", 0)) != 1 or int(high_quantity.get("quantity", 0)) != 1 \
			or effects.multiplier_for_lot("plating", low_quantity.output_lot) != 1.0 \
			or effects.multiplier_for_lot("plating", high_quantity.output_lot) != 1.0:
		_fail("quantity-only output changed quantity/effect")
		return false
	_crafted = {
		"low_sealant": low_sealant.output_lot,
		"high_sealant": high_sealant.output_lot,
		"low_repair": low_repair.output_lot,
		"high_repair": high_repair.output_lot,
		"low_meal": low_meal.output_lot,
		"high_meal": high_meal.output_lot,
		"low_paste": low_paste.output_lot,
		"high_paste": high_paste.output_lot,
		"high_quantity": high_quantity.output_lot,
	}
	return true


func _verify_consumable_quality() -> bool:
	# Crafted food uses the exact consumed lot for positive potency, while a
	# harmful sanity delta remains exactly authored across tiers.
	var food_results: Dictionary = {}
	for item_id in ["cooked_meal", "synthesized_paste"]:
		for tier_key in ["low", "high"]:
			var lot_key: String = "%s_%s" % [tier_key, "meal" if item_id == "cooked_meal" else "paste"]
			var lot: Dictionary = (_crafted[lot_key] as Dictionary).duplicate(true)
			var inventory = InventoryStateScript.new("p05-food:%s:%s" % [item_id, tier_key])
			inventory.add_lot(lot)
			var vitals = VitalsStateScript.new()
			vitals.configure({"hunger": 0.0, "thirst": 0.0})
			var sanity = SanityStateScript.new()
			sanity.configure({"sanity": 50.0})
			var dispatcher = EffectDispatcherScript.new()
			dispatcher.configure({})
			var consumable = ConsumableStateScript.new()
			consumable.configure({})
			var used: Dictionary = consumable.use_item(item_id, inventory, {
				"effect_dispatcher": dispatcher,
				"vitals_state": vitals,
				"sanity_state": sanity,
			}, false, str(lot.get("lot_id", "")))
			if not bool(used.get("ok", false)) or (used.get("results", []) as Array).is_empty():
				_fail("exact food quality use %s/%s: %s" % [item_id, tier_key, str(used)])
				return false
			food_results["%s_%s" % [item_id, tier_key]] = (used.get("results", []) as Array)[0]
	if float((food_results.cooked_meal_high as Dictionary).get("hunger_restored", 0.0)) \
			<= float((food_results.cooked_meal_low as Dictionary).get("hunger_restored", 0.0)) \
			or float((food_results.synthesized_paste_high as Dictionary).get("hunger_restored", 0.0)) \
			<= float((food_results.synthesized_paste_low as Dictionary).get("hunger_restored", 0.0)) \
			or absf(float((food_results.synthesized_paste_low as Dictionary).get("sanity_restored", 0.0)) + 2.0) > 0.0001 \
			or absf(float((food_results.synthesized_paste_high as Dictionary).get("sanity_restored", 0.0)) + 2.0) > 0.0001:
		_fail("food quality positive/negative contract %s" % str(food_results))
		return false

	var medicine_health: Dictionary = {}
	for tier_key in ["poor", "master"]:
		var score: float = 0.1 if tier_key == "poor" else 0.95
		var tier: String = "poor" if tier_key == "poor" else "masterwork"
		var lot: Dictionary = _lot("p05-medicine/%s" % tier_key, "bandage_kit", 1, score, tier, 0.44)
		var inventory = InventoryStateScript.new("p05-medicine:%s" % tier_key)
		inventory.add_lot(lot)
		var vitals = VitalsStateScript.new()
		vitals.configure({"health": 10.0})
		var medicine = MedicineStateScript.new()
		medicine.configure({})
		var dispatcher = EffectDispatcherScript.new()
		dispatcher.configure({})
		var consumable = ConsumableStateScript.new()
		consumable.configure({})
		var used: Dictionary = consumable.use_item("bandage_kit", inventory, {
			"effect_dispatcher": dispatcher,
			"medicine_state": medicine,
			"vitals_state": vitals,
		}, false, str(lot.lot_id))
		if not bool(used.get("ok", false)) or inventory.get_quantity("bandage_kit") != 0:
			_fail("exact medicine quality use %s: %s" % [tier_key, str(used)])
			return false
		medicine_health[tier_key] = vitals.health
	if float(medicine_health.master) <= float(medicine_health.poor):
		_fail("medicine positive quality did not improve healing %s" % str(medicine_health))
		return false

	var stimulant_duration: Dictionary = {}
	for tier_key in ["poor", "master"]:
		var score: float = 0.1 if tier_key == "poor" else 0.95
		var tier: String = "poor" if tier_key == "poor" else "masterwork"
		var lot: Dictionary = _lot("p05-stimulant/%s" % tier_key, "focus_ampoule", 1, score, tier, 0.62)
		var inventory = InventoryStateScript.new("p05-stimulant:%s" % tier_key)
		inventory.add_lot(lot)
		var stimulant = StimulantStateScript.new()
		stimulant.configure({})
		var dispatcher = EffectDispatcherScript.new()
		dispatcher.configure({})
		var consumable = ConsumableStateScript.new()
		consumable.configure({})
		var used: Dictionary = consumable.use_item("focus_ampoule", inventory, {
			"effect_dispatcher": dispatcher,
			"stimulant_state": stimulant,
		}, false, str(lot.lot_id))
		if not bool(used.get("ok", false)) or (used.get("results", []) as Array).is_empty() \
				or inventory.get_quantity("focus_ampoule") != 0:
			_fail("exact stimulant quality use %s: %s" % [tier_key, str(used)])
			return false
		stimulant_duration[tier_key] = float(((used.get("results", []) as Array)[0] as Dictionary).get("duration", 0.0))
	if float(stimulant_duration.master) <= float(stimulant_duration.poor):
		_fail("stimulant positive quality did not improve duration %s" % str(stimulant_duration))
		return false
	return true


func _verify_preview_selection_order() -> bool:
	var crafting = CraftingStateScript.new()
	var inventory = InventoryStateScript.new("p05-preview-order")
	# Stable quality is preferred even though its lot ID sorts after masterwork.
	inventory.add_lot(_lot("a-master", "reactive_gel", 1, 0.95, "masterwork", 0.2))
	inventory.add_lot(_lot("z-standard", "reactive_gel", 1, 0.5, "standard", 0.9))
	inventory.add_lot(_lot("polymer-standard", "polymer_pellet", 2, 0.5, "standard", 0.4))
	var entry: Dictionary = {}
	for entry_v in crafting.list_recipe_entries("workbench", inventory, 0, 0, null, 0, true):
		if entry_v is Dictionary and str((entry_v as Dictionary).get("recipe_id", "")) == "craft_sealant":
			entry = entry_v as Dictionary
			break
	var preview: Dictionary = entry.get("quality_preview", {}) as Dictionary
	var preview_ids: Array = preview.get("input_lot_ids", []) as Array
	if preview_ids != ["polymer-standard", "z-standard"]:
		_fail("preview lot order %s" % str(preview_ids))
		return false
	if not crafting.begin_craft(
			"craft_sealant", inventory, null, 0, null,
			"p05-preview-order", "p05-preview-order-station"):
		_fail("preview order craft start")
		return false
	var job_id: String = crafting.get_craft_job_scheduler().call(
		"get_active_job_id", "p05-preview-order", "p05-preview-order-station")
	var job: Dictionary = crafting.get_craft_job_scheduler().call("get_job", job_id)
	var paid_ids: Array[String] = []
	for lot_v in job.get("consumed_lots", []) as Array:
		if lot_v is Dictionary:
			paid_ids.append(str((lot_v as Dictionary).get("lot_id", "")))
	if paid_ids != ["polymer-standard", "z-standard"]:
		_fail("preview/reservation selection order diverged preview=%s paid=%s" % [str(preview_ids), str(paid_ids)])
		return false
	return true


func _craft_recipe(
		recipe_id: String,
		input_score: float,
		input_tier: String,
		skill_level: int,
		station_tier: int,
		powered: bool,
		fixture_id: String) -> Dictionary:
	var crafting = CraftingStateScript.new()
	var recipe: Dictionary = crafting.get_recipe(recipe_id)
	if recipe.is_empty():
		_fail("missing recipe %s" % recipe_id)
		return {}
	var station_kind: String = str(recipe.get("station_kind", ""))
	var station = crafting.get_or_create_station(station_kind)
	station.set("level", station_tier)
	station.set("tier", station_tier)
	station.call("set_power", powered)
	var inventory = InventoryStateScript.new("p05:%s" % fixture_id)
	var ingredients: Dictionary = recipe.get("ingredients", {}) as Dictionary
	var expected_input_ids: Array[String] = []
	var ingredient_ids: Array = ingredients.keys()
	ingredient_ids.sort()
	for ingredient_v in ingredient_ids:
		var ingredient_id: String = str(ingredient_v)
		var lot_id: String = "p05:%s/input:%s" % [fixture_id, ingredient_id]
		var quantity: int = int(ingredients[ingredient_v])
		if inventory.add_lot(_lot(lot_id, ingredient_id, quantity, input_score, input_tier, 0.23)) != quantity:
			_fail("ingredient setup %s/%s" % [recipe_id, ingredient_id])
			return {}
		expected_input_ids.append(lot_id)
	var entries: Array = crafting.list_recipe_entries(
		station_kind, inventory, skill_level, station_tier, null, skill_level, powered)
	var preview: Dictionary = {}
	for entry_v in entries:
		if entry_v is Dictionary and str((entry_v as Dictionary).get("recipe_id", "")) == recipe_id:
			preview = (entry_v as Dictionary).get("quality_preview", {}) as Dictionary
			break
	if preview.is_empty() or preview.get("input_lot_ids", []) != expected_input_ids:
		_fail("exact-lot preview %s expected=%s got=%s" % [recipe_id, str(expected_input_ids), str(preview)])
		return {}
	var ship_id: String = "p05-ship:%s" % fixture_id
	var station_id: String = "p05-station:%s" % fixture_id
	if not crafting.begin_craft(
			recipe_id, inventory, null, skill_level, null, ship_id, station_id):
		_fail("paid craft start %s" % recipe_id)
		return {}
	var active_job_id: String = crafting.get_craft_job_scheduler().call(
		"get_active_job_id", ship_id, station_id)
	var running_job: Dictionary = crafting.get_craft_job_scheduler().call("get_job", active_job_id)
	var escrow_ids: Array[String] = []
	for lot_v in running_job.get("consumed_lots", []) as Array:
		if lot_v is Dictionary:
			escrow_ids.append(str((lot_v as Dictionary).get("lot_id", "")))
	if escrow_ids != expected_input_ids:
		_fail("preview/reservation lot mismatch %s expected=%s got=%s" % [recipe_id, str(expected_input_ids), str(escrow_ids)])
		return {}
	if not crafting.tick(999.0):
		_fail("craft did not finish %s" % recipe_id)
		return {}
	var result: Dictionary = crafting.finish_craft()
	if result.is_empty() or not result.get("output_lot", null) is Dictionary \
			or absf(float(result.get("quality_score", -1.0)) - float(preview.get("score", -2.0))) > 0.0001 \
			or str(result.get("quality_tier", "")) != str(preview.get("tier", "")):
		_fail("preview/finished output mismatch %s preview=%s result=%s" % [recipe_id, str(preview), str(result)])
		return {}
	result["quality_preview"] = preview.duplicate(true)
	return result


func _verify_tool_speed_once() -> bool:
	var poor_lot: Dictionary = _crafted.low_sealant
	var master_lot: Dictionary = _crafted.high_sealant
	var poor = WorkActionDriverScript.new()
	poor.configure({})
	var poor_ctx: Dictionary = poor.build_context(
		"sealant", "repair", 0, {"hull_sealant": 1}, null, "", false, poor_lot)
	if not poor.start_action("patch_breach", "p05-tool-poor", poor_ctx):
		_fail("poor crafted tool start")
		return false
	poor.tick(1.0, {})
	var master = WorkActionDriverScript.new()
	master.configure({})
	var master_ctx: Dictionary = master.build_context(
		"sealant", "repair", 0, {"hull_sealant": 1}, null, "", false, master_lot)
	if not master.start_action("patch_breach", "p05-tool-master", master_ctx):
		_fail("masterwork crafted tool start")
		return false
	master.tick(1.0, {})
	# Base duration is 3.5. One second at x0.7/x2.0 gives exactly these ratios;
	# squared quality would instead produce 0.14 and complete the masterwork job.
	if absf(poor.progress_ratio() - 0.2) > 0.0001 \
			or absf(master.progress_ratio() - (2.0 / 3.5)) > 0.0001 \
			or absf(poor.get_active_start_speed_multiplier() - 0.7) > 0.0001 \
			or absf(master.get_active_start_speed_multiplier() - 2.0) > 0.0001:
		_fail("tool multiplier applied other than once poor=%s master=%s" % [poor.progress_ratio(), master.progress_ratio()])
		return false
	return true


func _verify_component_mount_quality() -> bool:
	var catalog = ComponentCatalogScript.new()
	if not catalog.load_default():
		_fail("component catalog load")
		return false
	var placement = ComponentPlacementScript.new()
	placement.populate({"rooms": [{
		"id": "engineering",
		"room_role": "engineering",
		"center_slots": [{"cell": [0, 0], "component_slot_profile_id": "deck_machinery_mount_v1"}],
	}]}, catalog, 12)
	for entry_v in placement.placed.duplicate(true):
		placement.dismount(str((entry_v as Dictionary).get("component_instance_id", "")))
	var slot_id: String = ""
	for slot_v in placement.get_physical_slot_descriptors("p05-component-ship"):
		if slot_v is Dictionary and bool(catalog.validate_component_fit("machinery_block", slot_v).get("ok", false)):
			slot_id = str((slot_v as Dictionary).get("slot_id", ""))
			break
	if slot_id.is_empty():
		_fail("physical machinery slot")
		return false
	var mods = ShipModificationScript.new()
	mods.configure({})
	mods.power_supply = 100.0
	mods.power_demand_baseline = 0.0
	if not mods.bind_physical_slots(
			"p05-component-ship", placement.get_physical_slot_descriptors("p05-component-ship"), catalog, placement):
		_fail("physical component binding")
		return false
	var poor_lot: Dictionary = _lot(
		"p05-salvage/machinery-poor", "machinery_block", 1, 0.1, "poor", 0.31)
	poor_lot.origin = {"source": "salvaged_component"}
	var master_lot: Dictionary = _lot(
		"p05-salvage/machinery-master", "machinery_block", 1, 0.95, "masterwork", 0.31)
	master_lot.origin = {"source": "salvaged_component"}
	var inventory: Dictionary = {"machinery_block": 1}
	var mounted_poor: Dictionary = placement.mount_by_slot_id(
		slot_id, "machinery_block", inventory, catalog, poor_lot)
	mods.sync_from_placement()
	var poor_draw: float = float((mods.installed[0] as Dictionary).get("power_draw", 0.0)) \
		if not mods.installed.is_empty() else 0.0
	var recovered: Dictionary = placement.dismount(slot_id)
	inventory["machinery_block"] = 1
	var mounted_master: Dictionary = placement.mount_by_slot_id(
		slot_id, "machinery_block", inventory, catalog, master_lot)
	mods.sync_from_placement()
	var master_draw: float = float((mods.installed[0] as Dictionary).get("power_draw", 0.0)) \
		if not mods.installed.is_empty() else 0.0
	if not bool(mounted_poor.get("ok", false)) or not bool(mounted_master.get("ok", false)) \
			or str((recovered.get("item_lot", {}) as Dictionary).get("lot_id", "")) != str(poor_lot.lot_id) \
			or absf(poor_draw - (12.0 / 0.7)) > 0.0001 \
			or absf(master_draw - 6.0) > 0.0001:
		_fail("physical component exact quality poor=%s master=%s recovered=%s" % [poor_draw, master_draw, str(recovered)])
		return false
	# Prospective and committed power use the same lot. At a ten-unit budget poor
	# is denied while masterwork fits; legacy missing metadata remains neutral 12.
	mods.power_supply = 10.0
	placement.dismount(slot_id)
	mods.sync_from_placement()
	var poor_gate: Dictionary = mods.preflight_install(
		slot_id, "machinery_block", "machinery_block", {"machinery_block": 1},
		"p05-component-ship", poor_lot)
	var master_gate: Dictionary = mods.preflight_install(
		slot_id, "machinery_block", "machinery_block", {"machinery_block": 1},
		"p05-component-ship", master_lot)
	if str(poor_gate.get("reason", "")) != "power_budget" or not bool(master_gate.get("ok", false)) \
			or absf(mods.effective_power_draw("machinery_block") - 12.0) > 0.0001:
		_fail("component prospective quality gate poor=%s master=%s" % [str(poor_gate), str(master_gate)])
		return false
	_crafted["master_component"] = master_lot
	_crafted["poor_component"] = poor_lot
	return true


func _verify_inventory_rows_and_exact_use() -> bool:
	var inventory = InventoryStateScript.new("p05-ui-holder")
	for lot_key in ["low_meal", "high_meal", "high_sealant", "high_repair", "high_quantity", "master_component"]:
		var lot: Dictionary = (_crafted[lot_key] as Dictionary).duplicate(true)
		if inventory.add_lot(lot) != int(lot.get("quantity", 0)):
			_fail("inventory UI lot setup %s" % lot_key)
			return false
	var equipment = EquipmentStateScript.create()
	var panel = InventoryPanelScript.new()
	get_root().add_child(panel)
	await process_frame
	panel.open_self(inventory, equipment)
	await process_frame
	var rendered: Array[String] = []
	var rows: Array = panel._lot_rows_for_pane("self")
	for index in range(rows.size()):
		var row = panel.row_at("self", index)
		if row != null:
			rendered.append(str(row.get_display_text()))
	for expected in [
		["sealant", "Masterwork — Work speed x2.00"],
		["hull_sealant", "Masterwork — Repair integrity x2.00"],
		["cooked_meal", "Masterwork — Potency x2.00"],
		["plating", "Quantity only (no quality modifier)"],
		["machinery_block", "Masterwork — Power draw /2.00"],
	]:
		var found_text: bool = false
		for rendered_text in rendered:
			if rendered_text.contains(str(expected[0]).replace("_", " ").capitalize()) \
					and rendered_text.contains(str(expected[1])):
				found_text = true
				break
		if not found_text:
			_fail("missing quality effect text %s rows=%s" % [str(expected), str(rendered)])
			panel.queue_free()
			return false
	var high_meal_id: String = str((_crafted.high_meal as Dictionary).get("lot_id", ""))
	var high_meal_index: int = -1
	for index in range(rows.size()):
		if str((rows[index] as Dictionary).get("lot_id", "")) == high_meal_id:
			high_meal_index = index
			break
	if high_meal_index < 0:
		_fail("masterwork meal row")
		panel.queue_free()
		return false
	var menu: PopupMenu = panel._build_context_menu("self", high_meal_index)
	var labels: Array[String] = []
	for index in range(menu.item_count):
		labels.append(menu.get_item_text(index))
	menu.free()
	if not labels.has("Use This Lot") or not labels.has("Use Entire Lot"):
		_fail("lot use labels %s" % str(labels))
		panel.queue_free()
		return false
	var vitals = VitalsStateScript.new()
	vitals.configure({"hunger": 0.0, "thirst": 0.0})
	var sanity = SanityStateScript.new()
	sanity.configure({"sanity": 0.0})
	var dispatcher = EffectDispatcherScript.new()
	dispatcher.configure({})
	var consumable = ConsumableStateScript.new()
	consumable.configure({})
	var routed: Dictionary = {}
	panel.use_lot_requested.connect(func(item_id: String, lot_id: String, use_all: bool):
		routed.merge(consumable.use_item(item_id, inventory, {
			"effect_dispatcher": dispatcher,
			"vitals_state": vitals,
			"sanity_state": sanity,
		}, use_all, lot_id), true)
		routed["lot_id"] = lot_id
	)
	panel._on_context_id(panel._ACT_USE_ALL, "self", high_meal_index)
	if not bool(routed.get("ok", false)) or int(routed.get("used", 0)) != 2 \
			or str(routed.get("lot_id", "")) != high_meal_id \
			or inventory.get_quantity("cooked_meal") != 1 \
			or not _inventory_has_lot(inventory, str((_crafted.low_meal as Dictionary).get("lot_id", ""))):
		_fail("rendered exact meal use routed=%s lots=%s" % [str(routed), str(inventory.get_lot_summary())])
		panel.queue_free()
		return false
	var before_missing: Dictionary = inventory.get_lot_summary()
	var missing: Dictionary = consumable.use_item("cooked_meal", inventory, {
		"effect_dispatcher": dispatcher, "vitals_state": vitals, "sanity_state": sanity,
	}, false, "forged-lot")
	if bool(missing.get("ok", false)) or inventory.get_lot_summary() != before_missing:
		_fail("forged selected use changed inventory")
		panel.queue_free()
		return false
	var picker = RecipePickerPanelScript.new()
	var preview_text: String = picker._format_row({
		"status": "ready", "display_name": "Mix Vacuum Sealant", "required_skill_level": 0,
		"ingredients": {"reactive_gel": 1, "polymer_pellet": 2},
		"produces": {"item_id": "sealant", "quantity": 2},
		"quality_preview": _craft_result_preview("high_sealant"),
	})
	if not preview_text.contains("predicted=Masterwork — Work speed x2.00"):
		_fail("recipe effect preview text=%s" % preview_text)
		picker.free()
		panel.queue_free()
		return false
	var unavailable_text: String = picker._format_row({
		"status": "missing_ingredients", "display_name": "Missing", "required_skill_level": 0,
		"ingredients": {"missing": 1}, "produces": {"item_id": "sealant", "quantity": 1},
		"quality_preview": {},
	})
	if not unavailable_text.contains("predicted=unavailable (exact inputs missing)"):
		_fail("missing-input preview invented quality")
		picker.free()
		panel.queue_free()
		return false
	picker.free()
	panel.queue_free()
	return true


func _craft_result_preview(key: String) -> Dictionary:
	var lot: Dictionary = _crafted.get(key, {}) as Dictionary
	var effects = ItemQualityEffectsScript.new()
	return {
		"tier": str(lot.get("quality_tier", "standard")),
		"effect_text": effects.effect_text_for_lot(str(lot.get("item_id", "")), lot),
	}


func _on_frame() -> void:
	if _finished:
		return
	_frames += 1
	if _playable == null:
		_playable = _find_playable(_main)
	if _playable == null or not bool(_playable.get("playable_started")):
		if _frames > TIMEOUT_FRAMES:
			_fail("playable not ready")
		return
	if not _verify_live_component_panel_boundary():
		return
	_verify_live_paid_repair()


func _verify_live_component_panel_boundary() -> bool:
	var fixture: Dictionary = _playable.prepare_p12_component_work_fixture_for_validation()
	if not bool(fixture.get("ok", false)):
		_fail("live component fixture: %s" % str(fixture))
		return false
	var slot_id: String = str(fixture.get("slot_id", ""))
	var instance_id: String = str(fixture.get("instance_id", slot_id))
	var component_id: String = str(fixture.get("component_id", ""))
	var item_form: String = str(fixture.get("item_form", ""))
	var panel = _playable.get_ship_modification_panel_for_validation()
	var placement = _playable.get_component_placement_state_for_validation()
	var mods = _playable.get_ship_modification_state_for_validation()
	var inventory = _playable.inventory_state
	if panel == null or placement == null or mods == null or item_form.is_empty():
		_fail("live component runtime")
		return false
	var removed: Dictionary = placement.dismount(instance_id)
	if not bool(removed.get("ok", false)):
		_fail("live component fixture dismount: %s" % str(removed))
		return false
	mods.sync_from_placement()
	_drain_item(inventory, item_form)
	var master_lot: Dictionary = removed.get("item_lot", {}) as Dictionary
	if master_lot.is_empty():
		master_lot = _lot("p05-live-component/master", item_form, 1, 0.95, "masterwork", 0.73)
	else:
		master_lot = master_lot.duplicate(true)
		master_lot["lot_id"] = "p05-live-component/master"
		master_lot["item_id"] = item_form
		master_lot["quantity"] = 1
		master_lot["quality_score"] = 0.95
		master_lot["quality_tier"] = "masterwork"
	var poor_lot: Dictionary = master_lot.duplicate(true)
	poor_lot["lot_id"] = "p05-live-component/poor"
	poor_lot["quality_score"] = 0.1
	poor_lot["quality_tier"] = "poor"
	var remaining_draw: float = mods.total_power_draw()
	var master_draw: float = mods.effective_power_draw(component_id, master_lot)
	var poor_draw: float = mods.effective_power_draw(component_id, poor_lot)
	if master_draw >= poor_draw:
		_fail("live component quality draws master=%s poor=%s" % [master_draw, poor_draw])
		return false
	mods.power_supply = remaining_draw + (master_draw + poor_draw) * 0.5
	if inventory.add_lot(master_lot) != 1:
		_fail("live master component setup")
		return false
	panel.set_inventory(_playable._inventory_qty_dict_for_work())
	panel.select_slot_id(slot_id)
	_playable.vitals_state.stamina = _playable.vitals_state.max_stamina
	if not panel.install_into_selected(component_id, item_form):
		_fail("actual panel rejected fitting masterwork component: %s" % str(panel.get_status_lines()))
		return false
	if not _playable.has_active_ship_work_for_validation() or inventory.get_quantity(item_form) != 0 \
			or placement.is_mounted(instance_id):
		_fail("actual panel masterwork reservation/deferral")
		return false
	_playable.advance_active_ship_work_for_validation(999.0)
	var mounted: Dictionary = placement.get_entry(instance_id)
	var installed_draw: float = -1.0
	for installed_v in mods.installed:
		if installed_v is Dictionary and str((installed_v as Dictionary).get("slot_id", "")) == slot_id:
			installed_draw = float((installed_v as Dictionary).get("power_draw", -1.0))
			break
	if not placement.is_mounted(instance_id) \
			or str(mounted.get("source_lot_id", "")) != str(master_lot.lot_id) \
			or absf(installed_draw - master_draw) > 0.0001:
		_fail("actual panel exact masterwork commit: mounted=%s draw=%s" % [str(mounted), installed_draw])
		return false
	if not bool(placement.dismount(instance_id).get("ok", false)):
		_fail("live master component cleanup")
		return false
	mods.sync_from_placement()
	_drain_item(inventory, item_form)
	if inventory.add_lot(poor_lot) != 1:
		_fail("live poor component setup")
		return false
	panel.set_inventory(_playable._inventory_qty_dict_for_work())
	panel.select_slot_id(slot_id)
	var requested: bool = panel.install_into_selected(component_id, item_form)
	if requested or _playable.has_active_ship_work_for_validation() \
			or inventory.get_quantity(item_form) != 1 or placement.is_mounted(instance_id):
		_fail("actual panel admitted over-budget poor component: %s" % str(panel.get_status_lines()))
		return false
	return true


func _verify_live_paid_repair() -> void:
	_finished = true
	var inventory = _playable.inventory_state
	var module_map = _playable.get_module_integrity_map_for_validation()
	if inventory == null or module_map == null:
		_fail("live repair runtime")
		return
	if inventory.get_quantity("sealant") <= 0:
		inventory.add_item("sealant", 1)
	var module_ids: PackedStringArray = module_map.module_ids()
	if module_ids.is_empty():
		_fail("live repair module")
		return
	var module_id: String = str(module_ids[0])
	var module = module_map.get_module(module_id)
	var module_kind: String = str(module.get("kind"))
	var room_id: String = str(module.get("room_id"))
	_drain_item(inventory, "hull_sealant")
	var low_lot: Dictionary = (_crafted.low_repair as Dictionary).duplicate(true)
	var high_lot: Dictionary = (_crafted.high_repair as Dictionary).duplicate(true)
	if not _run_live_repair(module, module_id, module_kind, room_id, low_lot, 0.245):
		return
	if not _run_live_repair(module, module_id, module_kind, room_id, high_lot, 0.7):
		return

	module.configure({"module_id": module_id, "kind": module_kind, "room_id": room_id, "integrity": 0.2})
	if inventory.add_lot(low_lot) != 1:
		_fail("cancel lot setup")
		return
	_playable.vitals_state.stamina = _playable.vitals_state.max_stamina
	var cancel_start: Dictionary = _start_live_repair(module_id)
	if not bool(cancel_start.get("ok", false)) or inventory.get_quantity("hull_sealant") != 0:
		_fail("cancel reserve")
		return
	if not _playable.cancel_active_ship_work_for_validation("explicit_cancel") \
			or not _inventory_has_lot(inventory, str(low_lot.lot_id)) \
			or absf(float(module.get("integrity")) - 0.2) > 0.0001:
		_fail("cancel exact refund/no repair")
		return
	_drain_item(inventory, "hull_sealant")

	module.configure({"module_id": module_id, "kind": module_kind, "room_id": room_id, "integrity": 0.2})
	inventory.add_lot(high_lot)
	_playable.vitals_state.stamina = _playable.vitals_state.max_stamina
	if not bool(_start_live_repair(module_id).get("ok", false)):
		_fail("stale repair start")
		return
	module.configure({"module_id": module_id, "kind": module_kind, "room_id": room_id, "integrity": 0.25})
	_playable.vitals_state.stamina = _playable.vitals_state.max_stamina
	_playable.advance_active_ship_work_for_validation(999.0)
	var stale: Dictionary = _playable.get_last_ship_work_result_for_validation()
	if str(stale.get("reason", "")) != "stale_target" or inventory.get_quantity("hull_sealant") != 0 \
			or absf(float(module.get("integrity")) - 0.25) > 0.0001:
		_fail("stale target applied/refunded early %s" % str(stale))
		return
	if not _playable.cancel_active_ship_work_for_validation("stale_target") \
			or not _inventory_has_lot(inventory, str(high_lot.lot_id)) \
			or absf(float(module.get("integrity")) - 0.25) > 0.0001:
		_fail("stale target exact recovery")
		return

	_finish_success()


func _finish_success() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	await process_frame
	await process_frame
	print("FC P05 PASS")
	print("FC P05 DETAIL outputs=53 tool_once=true exact_use=true repair_paid=true component_physical=true")
	quit(0)


func _run_live_repair(
		module,
		module_id: String,
		module_kind: String,
		room_id: String,
		paid_lot: Dictionary,
		expected_delta: float) -> bool:
	var inventory = _playable.inventory_state
	module.configure({"module_id": module_id, "kind": module_kind, "room_id": room_id, "integrity": 0.2})
	if inventory.add_lot(paid_lot) != 1:
		_fail("paid repair lot setup %s" % str(paid_lot))
		return false
	_playable.vitals_state.stamina = _playable.vitals_state.max_stamina
	var started: Dictionary = _start_live_repair(module_id)
	if not bool(started.get("ok", false)) or inventory.get_quantity("hull_sealant") != 0:
		_fail("repair did not reserve before effect %s" % str(started))
		return false
	if absf(float(module.get("integrity")) - 0.2) > 0.0001:
		_fail("repair happened before timed commit")
		return false
	var record: Dictionary = _playable.get_active_ship_work_record_for_validation()
	var escrow: Array = record.get("escrow", []) as Array
	if escrow.size() != 1 or str((escrow[0] as Dictionary).get("lot_id", "")) != str(paid_lot.lot_id):
		_fail("repair reserved wrong exact lot %s" % str(escrow))
		return false
	_playable.vitals_state.stamina = _playable.vitals_state.max_stamina
	_playable.advance_active_ship_work_for_validation(999.0)
	var receipt: Dictionary = _playable.get_last_ship_work_result_for_validation()
	var result: Dictionary = receipt.get("result", {}) as Dictionary
	if not bool(receipt.get("ok", false)) \
			or absf(float(module.get("integrity")) - (0.2 + expected_delta)) > 0.0001 \
			or str(((receipt.get("consumed_lots", []) as Array)[0] as Dictionary).get("lot_id", "")) != str(paid_lot.lot_id) \
			or absf(float(result.get("repair_quality_multiplier", 0.0)) - (expected_delta / 0.35)) > 0.0001:
		_fail("paid repair quality receipt=%s integrity=%s" % [str(receipt), str(module.get("integrity"))])
		return false
	var before_duplicate: float = float(module.get("integrity"))
	var duplicate: Dictionary = _playable.commit_last_ship_work_for_validation()
	if not bool(duplicate.get("already_committed", false)) \
			or absf(float(module.get("integrity")) - before_duplicate) > 0.0001:
		_fail("duplicate repair applied twice")
		return false
	return true


func _start_live_repair(module_id: String) -> Dictionary:
	var context: Dictionary = {
		"tool_class": "sealant",
		"skill_id": "repair",
		"skill_level": 99,
		"inventory": {"hull_sealant": 1},
		"selected_tool_lot": _playable._selected_work_tool_lot("sealant"),
	}
	return _playable._start_transactional_work(
		"patch_breach", module_id, "module", _playable._module_target_revision(module_id),
		context, {}, null)


func _lot(
		lot_id: String,
		item_id: String,
		quantity: int,
		score: float,
		tier: String,
		condition: float) -> Dictionary:
	return {
		"lot_id": lot_id,
		"item_id": item_id,
		"quantity": quantity,
		"quality_score": score,
		"quality_tier": tier,
		"condition": condition,
		"origin": {"fixture": "fc-p05"},
	}


func _inventory_has_lot(inventory, lot_id: String) -> bool:
	for lot_v in inventory.get_lot_summary().get("lots", []) as Array:
		if lot_v is Dictionary and str((lot_v as Dictionary).get("lot_id", "")) == lot_id:
			return true
	return false


func _drain_item(inventory, item_id: String) -> void:
	var quantity: int = int(inventory.get_quantity(item_id))
	if quantity > 0:
		inventory.take_lots(item_id, quantity)


func _find_playable(node: Node):
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null


func _fail(message: String) -> void:
	_finished = true
	print("FC P05 FAIL: %s" % message)
	quit(1)
