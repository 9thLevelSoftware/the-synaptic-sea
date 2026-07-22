extends SceneTree

## PKG-B5.1: dressing presets are data-complete and load into descriptors deterministically.
## Marker: DRESSING CONSUMPTION PASS presets=true descriptors=true lights=true density=true

const RoomVariantSelectorScript := preload("res://scripts/procgen/room_variant_selector.gd")
const GeneratedShipLoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")


func _initialize() -> void:
	var selector = RoomVariantSelectorScript.new()
	var ids: PackedStringArray = selector.known_dressing_ids()
	if ids.size() < 8:
		_fail("expected >=8 dressing presets, got %d" % ids.size())
		return
	for dressing_id in ids:
		var preset: Dictionary = selector.dressing_preset(str(dressing_id))
		if preset.is_empty():
			_fail("empty preset for %s" % dressing_id)
			return
		if not preset.has("fog_density") or not preset.has("prop_density") or not preset.has("light_energy"):
			_fail("preset missing keys for %s" % dressing_id)
			return
		if not preset.has("tint") or not preset.has("light_color"):
			_fail("preset missing colors for %s" % dressing_id)
			return

	# effects_for dressing maps into presets
	var frost: Dictionary = selector.effects_for("refrigerated")
	if str(frost.get("dressing", "")) != "frost":
		_fail("refrigerated should dress frost")
		return
	if selector.dressing_preset("frost").is_empty():
		_fail("frost preset missing")
		return

	# Loader builds expanded descriptors + DressingVisuals when layout has variants.
	var loader = GeneratedShipLoaderScript.new()
	get_root().add_child(loader)
	# Minimal layout with a refrigerated cargo room
	loader.layout_doc = {
		"rooms": [
			{
				"id": "cargo_1",
				"room_role": "cargo",
				"variant": "refrigerated",
				"cells": [[0, 0]],
				"structural_placements": [],
			},
			{
				"id": "eng_1",
				"room_role": "engineering",
				"variant": "burned_out",
				"cells": [[1, 0]],
				"structural_placements": [],
			},
		]
	}
	loader._build_room_variant_descriptors()
	var descs: Dictionary = loader.get_room_variant_descriptors()
	if not descs.has("cargo_1") or not descs.has("eng_1"):
		_fail("descriptors missing rooms: %s" % str(descs.keys()))
		return
	var cargo: Dictionary = descs["cargo_1"]
	if str(cargo.get("dressing", "")) != "frost":
		_fail("cargo dressing expected frost")
		return
	if float(cargo.get("prop_density", 0.0)) <= 0.0:
		_fail("prop_density should be set")
		return
	if float(cargo.get("fog_density", -1.0)) < 0.0:
		_fail("fog_density should be set")
		return
	if not cargo.has("tint") or not cargo.has("light_color"):
		_fail("tint/light_color required on descriptors")
		return

	# Apply visuals onto a temp root
	var ship_root := Node3D.new()
	get_root().add_child(ship_root)
	loader._apply_dressing_visuals(loader.layout_doc, ship_root)
	var dressing_node: Node = ship_root.get_node_or_null("DressingVisuals")
	if dressing_node == null:
		_fail("DressingVisuals root missing")
		return
	var light_count: int = 0
	for child in dressing_node.get_children():
		if child is OmniLight3D:
			light_count += 1
			if not child.has_meta("dressing"):
				_fail("light missing dressing meta")
				return
			if not child.has_meta("prop_density"):
				_fail("light missing prop_density meta")
				return
	if light_count < 2:
		_fail("expected dressing lights for both rooms, got %d" % light_count)
		return

	# Determinism: rebuild descriptors twice
	loader._build_room_variant_descriptors()
	var descs2: Dictionary = loader.get_room_variant_descriptors()
	if JSON.stringify(descs) != JSON.stringify(descs2):
		_fail("descriptor rebuild not deterministic")
		return

	print("DRESSING CONSUMPTION PASS presets=true descriptors=true lights=true density=true")
	quit(0)


func _fail(msg: String) -> void:
	print("DRESSING CONSUMPTION FAIL: %s" % msg)
	quit(1)
