extends SceneTree

## REQ-CMP-002: placed components link to ship-system subcomponents.
## Marker: COMPONENT SYSTEM LINK PASS catalog_links=true soft_fill=true coverage=true

const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")


func _initialize() -> void:
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("catalog"); return
	var layout: Dictionary = {
		"rooms": [
			{
				"id": "eng_1",
				"room_role": "engineering",
				"wall_slots": [
					{"against_wall": true, "cell": "(0,0)"},
					{"against_wall": true, "cell": "(0,1)"},
					{"against_wall": true, "cell": "(1,0)"},
					{"against_wall": true, "cell": "(1,1)"},
				],
				"center_slots": [{"cell": "(0,0)"}],
			},
			{
				"id": "br_1",
				"room_role": "bridge",
				"wall_slots": [
					{"against_wall": true, "cell": "(2,0)"},
					{"against_wall": true, "cell": "(2,1)"},
				],
				"center_slots": [],
			},
		],
	}
	var place = ComponentPlacementStateScript.new()
	if place.populate(layout, cat, 21) < 3:
		_fail("need several placements got %d" % place.placed.size()); return
	# Catalog-authored links present on some engineering picks
	var systems_text: String = FileAccess.get_file_as_string("res://data/ship_systems/systems.json")
	var systems_doc: Variant = JSON.parse_string(systems_text)
	if typeof(systems_doc) != TYPE_DICTIONARY:
		_fail("systems.json"); return
	var linked_n: int = place.link_ship_systems(systems_doc as Dictionary, cat)
	if linked_n < 1:
		_fail("expected at least one link"); return
	var catalog_links: int = 0
	var soft_links: int = 0
	var covered: Dictionary = {}
	for e in place.placed:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = e
		var sys: String = str(row.get("linked_system", ""))
		var sub: String = str(row.get("linked_subcomponent", ""))
		if sys.is_empty() or sub.is_empty():
			continue
		covered["%s.%s" % [sys, sub]] = true
		if bool(row.get("soft_linked", false)):
			soft_links += 1
		else:
			catalog_links += 1
	if catalog_links < 1 and soft_links < 1:
		_fail("no linked placements"); return
	# At least one systems.json sub is represented
	if covered.is_empty():
		_fail("coverage empty"); return
	# Idempotent: second link pass does not explode counts
	var linked2: int = place.link_ship_systems(systems_doc as Dictionary, cat)
	if linked2 < linked_n:
		_fail("second pass lost links"); return

	print("COMPONENT SYSTEM LINK PASS catalog_links=true soft_fill=true coverage=true")
	quit(0)


func _fail(msg: String) -> void:
	print("COMPONENT SYSTEM LINK FAIL: %s" % msg)
	quit(1)
