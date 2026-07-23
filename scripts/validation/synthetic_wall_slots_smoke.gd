extends SceneTree

## Floor-only golden-style rooms still receive synthesized wall/center slots for populate.
## Marker: SYNTHETIC WALL SLOTS PASS wall=true center=true placed=true

const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")


func _initialize() -> void:
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("catalog"); return
	var layout: Dictionary = {
		"rooms": [{
			"id": "airlock_01",
			"room_role": "engineering",
			"structural_placements": [
				{"name": "floor_cell_x0_z0", "module": "floor_1x1", "world_position": [0.0, 0.0, 0.0]},
				{"name": "floor_cell_x1_z0", "module": "floor_1x1", "world_position": [4.0, 0.0, 0.0]},
				{"name": "floor_cell_x0_z1", "module": "floor_1x1", "world_position": [0.0, 0.0, 4.0]},
			],
		}],
	}
	var place = ComponentPlacementStateScript.new()
	# Extract synthesized slots directly
	var walls: Array = place._extract_slots(layout["rooms"][0], "wall_slots")
	var centers: Array = place._extract_slots(layout["rooms"][0], "center_slots")
	if walls.size() < 1:
		_fail("expected synthesized wall slots"); return
	if centers.size() != 1:
		_fail("expected one center slot"); return
	var n: int = place.populate(layout, cat, 9)
	if n < 1:
		_fail("populate should place on synthetic slots got %d" % n); return
	print("SYNTHETIC WALL SLOTS PASS wall=true center=true placed=true")
	quit(0)


func _fail(msg: String) -> void:
	print("SYNTHETIC WALL SLOTS FAIL: %s" % msg)
	quit(1)
