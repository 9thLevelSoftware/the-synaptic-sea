extends SceneTree

## ItemDefs equipment-metadata smoke: the new equipment defs load and the
## equip_slot / container_capacity / effects readers return the declared values;
## non-equippable items report empty/zero (the readers never crash on plain items).

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")

func _approx(a: float, b: float) -> bool:
	return absf(a - b) <= 0.0001

func _init() -> void:
	var defs: Dictionary = ItemDefsScript.load_definitions()
	assert(defs.has("eva_backpack"), "equipment defs merged into the catalog")

	assert(ItemDefsScript.equip_slot(defs, "eva_backpack") == "back", "backpack -> back slot")
	assert(ItemDefsScript.equip_slot(defs, "tool_belt") == "waist", "tool_belt -> waist slot")
	assert(ItemDefsScript.equip_slot(defs, "hardsuit") == "suit", "hardsuit -> suit slot")
	assert(ItemDefsScript.container_capacity(defs, "eva_backpack") == 40.0, "backpack capacity 40")
	assert(ItemDefsScript.container_capacity(defs, "tool_belt") == 12.0, "tool_belt capacity 12")
	assert(ItemDefsScript.container_capacity(defs, "hardsuit") == 0.0, "suit is not a container")

	assert(_approx(ItemDefsScript.weight_reduction(defs, "eva_backpack"), 0.30), "backpack reduces 30%")
	assert(_approx(ItemDefsScript.weight_reduction(defs, "field_pack"), 0.15), "field_pack reduces 15%")
	assert(_approx(ItemDefsScript.weight_reduction(defs, "tool_belt"), 0.10), "tool_belt reduces 10%")
	assert(ItemDefsScript.weight_reduction(defs, "hardsuit") == 0.0, "suit has no weight reduction")
	assert(ItemDefsScript.weight_reduction(defs, "scrap_metal") == 0.0, "plain item has no weight reduction")

	var fx: Array = ItemDefsScript.effects(defs, "hardsuit")
	assert(fx.size() == 1 and str(fx[0].get("type", "")) == "oxygen_drain", "suit carries an oxygen_drain effect")
	assert(float(fx[0].get("value", 1.0)) == 0.75, "suit oxygen_drain value 0.75")

	# Non-equippable real item (scrap_metal: part) -> empty/zero, no crash.
	assert(ItemDefsScript.equip_slot(defs, "scrap_metal") == "", "plain item has no slot")
	assert(ItemDefsScript.container_capacity(defs, "scrap_metal") == 0.0, "plain item not a container")
	assert(ItemDefsScript.effects(defs, "scrap_metal").is_empty(), "plain item has no effects")

	print("EQUIPMENT DEFS SMOKE PASS slots=3 effects=1")
	quit()
