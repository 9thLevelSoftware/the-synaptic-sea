extends SceneTree

## Domain 3 Task 1: contaminated_water exists as a supply item (recycler input) and
## is reachable as loot. It is NOT a food/drink (never eaten), so it has no nutrition.
## Marker: CONTAMINATED WATER ITEM PASS defined=true supply=true lootable=true

const ItemDefsScript := preload("res://scripts/systems/item_defs.gd")
const LOOT_TABLES_PATH := "res://data/items/loot_tables.json"

func _initialize() -> void:
	var defs: Dictionary = ItemDefsScript.load_definitions()
	if not defs.has("contaminated_water"):
		_fail("contaminated_water not defined in item definitions"); return
	var d: Dictionary = defs["contaminated_water"]
	if str(d.get("category", "")) != "supply":
		_fail("contaminated_water category=%s expected supply" % str(d.get("category", ""))); return
	# Reachable as loot: appears in at least one loot table's entries.
	var f := FileAccess.open(LOOT_TABLES_PATH, FileAccess.READ)
	if f == null:
		_fail("could not open loot_tables.json"); return
	var raw: String = f.get_as_text()
	f.close()
	if not raw.contains("contaminated_water"):
		_fail("contaminated_water not seeded into any loot table"); return
	print("CONTAMINATED WATER ITEM PASS defined=true supply=true lootable=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CONTAMINATED WATER ITEM FAIL reason=%s" % reason)
	quit(1)
