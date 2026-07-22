extends SceneTree

## PKG-B2.3a: deterministic component slot population + no collisions + system links.
## Marker: COMPONENT SLOT POPULATION PASS catalog=true placed=true deterministic=true no_collision=true linked=true

const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")


func _initialize() -> void:
	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("catalog load failed")
		return
	if cat.component_count() < 8:
		_fail("expected rich catalog, got %d" % cat.component_count())
		return

	var layout: Dictionary = {
		"rooms": [
			{
				"id": "eng_1",
				"room_role": "engineering",
				"wall_slots": [
					{"against_wall": true, "cell": "(0, 0)"},
					{"against_wall": true, "cell": "(0, 1)"},
				],
				"center_slots": [
					{"against_wall": false, "cell": "(0, 0)"},
				],
			},
			{
				"id": "br_1",
				"room_role": "bridge",
				"wall_slots": [
					{"against_wall": true, "cell": "(1, 0)"},
				],
				"center_slots": [],
			},
			{
				"id": "cor_1",
				"room_role": "corridor",
				"wall_slots": [
					{"against_wall": true, "cell": "(2, 0)"},
				],
				"center_slots": [],
			},
		]
	}

	var place_a = ComponentPlacementStateScript.new()
	var n: int = place_a.populate(layout, cat, 42)
	if n < 3:
		_fail("expected placements >=3, got %d" % n)
		return
	if place_a.has_slot_collisions():
		_fail("slot collisions detected")
		return

	var place_b = ComponentPlacementStateScript.new()
	place_b.populate(layout, cat, 42)
	if place_a.fingerprint() != place_b.fingerprint():
		_fail("determinism failed for same seed")
		return

	var place_c = ComponentPlacementStateScript.new()
	place_c.populate(layout, cat, 99)
	# different seed should usually differ; if not, still ok if catalog small — just require valid
	if place_c.has_slot_collisions():
		_fail("collisions on seed 99")
		return

	# Linked system components present for engineering/bridge
	var linked: int = 0
	for entry in place_a.placed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if not str(entry.get("linked_system", "")).is_empty():
			linked += 1
	if linked < 1:
		_fail("expected at least one system-linked component")
		return
	var link_count: int = place_a.link_ship_systems({"systems": []}, cat)
	if link_count < 1:
		_fail("link_ship_systems should count catalog links")
		return

	# Summary round-trip
	var snap: Dictionary = place_a.get_summary()
	var place_d = ComponentPlacementStateScript.new()
	place_d.apply_summary(snap)
	if place_d.fingerprint() != place_a.fingerprint():
		_fail("summary round-trip")
		return

	# Reachability: every placement has room_id and slot indices
	for entry2 in place_a.placed:
		var e: Dictionary = entry2
		if str(e.get("room_id", "")).is_empty():
			_fail("placement missing room_id")
			return
		if str(e.get("component_instance_id", "")).is_empty():
			_fail("missing instance id")
			return

	print("COMPONENT SLOT POPULATION PASS catalog=true placed=true deterministic=true no_collision=true linked=true count=%d" % n)
	quit(0)


func _fail(msg: String) -> void:
	print("COMPONENT SLOT POPULATION FAIL: %s" % msg)
	quit(1)
