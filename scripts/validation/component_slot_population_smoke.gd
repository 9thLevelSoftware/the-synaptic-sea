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
					{"against_wall": true, "cell": "(0, 0)", "component_slot_profile_id": "wall_console_mount_v1"},
					{"against_wall": true, "cell": "(0, 1)", "component_slot_profile_id": "wall_console_mount_v1"},
				],
				"center_slots": [
					{"against_wall": false, "cell": "(0, 0)", "component_slot_profile_id": "deck_machinery_mount_v1"},
				],
			},
			{
				"id": "br_1",
				"room_role": "bridge",
				"wall_slots": [
					{"against_wall": true, "cell": "(1, 0)", "component_slot_profile_id": "wall_console_mount_v1"},
				],
				"center_slots": [],
			},
			{
				"id": "cor_1",
				"room_role": "corridor",
				"wall_slots": [
					{"against_wall": true, "cell": "(2, 0)", "component_slot_profile_id": "wall_utility_mount_v1"},
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
	var prepared_authority: Dictionary = place_a.prepare_condition_authority(
		"component-slot-smoke", cat, ComponentPlacementStateScript.CONDITION_MODE_GENERATED)
	if not place_a.commit_condition_authority(prepared_authority):
		_fail("condition authority preparation")
		return
	var snap: Dictionary = place_a.get_summary()
	var place_d = ComponentPlacementStateScript.new()
	if not place_d.restore_from_layout(layout, cat, 42, snap):
		_fail("current-layout summary restore")
		return
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

	print("COMPONENT SLOT POPULATION PASS catalog=true placed=true deterministic=true no_collision=true linked=true")
	quit(0)


func _fail(msg: String) -> void:
	print("COMPONENT SLOT POPULATION FAIL: %s" % msg)
	quit(1)
