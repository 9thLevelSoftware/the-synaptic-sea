extends SceneTree

## REQ-HIVE-001 / hive topology + biomatter kit-id stamp (v0 wrapper paths).
## Marker: HIVE BIOMATTER KIT PASS template=true kit=true sockets_fallback=true occupancy=true v0_paths=true

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const TemplateSelectorScript := preload("res://scripts/procgen/template_selector.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")

const HIVE_TEMPLATE_PATH := "res://data/procgen/templates/hive.json"
const BIOMATTER_KIT_PATH := "res://data/kits/ship_structural_biomatter.json"
const HAZARD_KIT_PATH := "res://data/kits/ship_structural_hazard.json"
const INDUSTRIAL_KIT_PATH := "res://data/kits/ship_structural_industrial.json"
const V0_WRAPPER_PREFIX := "res://scenes/wrappers/structural/ship_structural_v0/"
const DERELICT_ARCHETYPE_PATH := "res://data/procgen/archetypes/derelict.json"


func _initialize() -> void:
	if not _check_template_pool():
		return
	if not _check_hive_json():
		return
	if not _check_not_forced_on_derelict():
		return
	if not _check_v0_wrapper_paths():
		return
	if not _check_wrapper_map_fallback():
		return
	if not _check_sockets_fallback():
		return
	if not _check_hive_layout_and_occupancy():
		return
	if not _check_hive_kit_independent_of_biome():
		return
	if not _check_ship_generator_kit_file():
		return

	print("HIVE BIOMATTER KIT PASS template=true kit=true sockets_fallback=true occupancy=true v0_paths=true")
	quit(0)


func _check_template_pool() -> bool:
	var selector: TemplateSelectorScript = TemplateSelectorScript.new()
	var available: Array[String] = selector.available_templates(false, false)
	var derelict: Array[String] = selector.available_templates(true, false)
	var extended: Array[String] = selector.available_templates(false, true)
	if available.has("hive"):
		return _fail("hive must not be in AVAILABLE_TEMPLATES / default pool")
	if derelict.has("hive"):
		return _fail("hive must not be a derelict guaranteed template")
	if TemplateSelectorScript.DERELICT_TEMPLATES.has("hive"):
		return _fail("hive listed in DERELICT_TEMPLATES")
	if TemplateSelectorScript.WRECK_TEMPLATES.has("hive"):
		return _fail("hive listed in WRECK_TEMPLATES")
	if not extended.has("hive"):
		return _fail("hive missing from EXTENDED_TEMPLATES")
	if not FileAccess.file_exists(HIVE_TEMPLATE_PATH):
		return _fail("hive.json missing")
	return true


func _check_hive_json() -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(HIVE_TEMPLATE_PATH))
	if not (parsed is Dictionary):
		return _fail("hive.json is not a Dictionary")
	var data: Dictionary = parsed
	if str(data.get("id", "")) != "hive":
		return _fail("hive.json id=%s" % str(data.get("id", "")))
	var zones_v: Variant = data.get("zones", [])
	if not (zones_v is Array):
		return _fail("hive.json missing zones")
	var zone_ids: Dictionary = {}
	var saw_clustered: bool = false
	var saw_overgrown_lateral: bool = false
	var dest_bow: bool = false
	for zone_v in (zones_v as Array):
		if not (zone_v is Dictionary):
			continue
		var zone: Dictionary = zone_v
		var zid: String = str(zone.get("id", ""))
		zone_ids[zid] = true
		if str(zone.get("layout", "")) == "clustered":
			saw_clustered = true
		if zid == "overgrown" and str(zone.get("position_hint", "")) == "lateral":
			saw_overgrown_lateral = true
		if zid == "destination" and str(zone.get("position_hint", "")) == "bow":
			dest_bow = true
	if not zone_ids.has("entry") or not zone_ids.has("destination"):
		return _fail("hive.json missing entry or destination")
	if not saw_clustered:
		return _fail("hive.json has no clustered zone")
	if not saw_overgrown_lateral:
		return _fail("hive.json missing lateral overgrown pocket")
	if not dest_bow:
		return _fail("hive.json destination is not on the bow")
	return true


func _check_not_forced_on_derelict() -> bool:
	if not FileAccess.file_exists(DERELICT_ARCHETYPE_PATH):
		return _fail("derelict archetype missing")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DERELICT_ARCHETYPE_PATH))
	if not (parsed is Dictionary):
		return _fail("derelict archetype invalid JSON")
	var arch: Dictionary = parsed
	if str(arch.get("template", "")) == "hive":
		return _fail("derelict archetype forces template=hive")
	return true


func _check_v0_wrapper_paths() -> bool:
	if not FileAccess.file_exists(BIOMATTER_KIT_PATH):
		return _fail("biomatter kit missing")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BIOMATTER_KIT_PATH))
	if not (parsed is Dictionary):
		return _fail("biomatter kit invalid JSON")
	var kit: Dictionary = parsed
	if str(kit.get("kit_id", "")) != "ship_structural_biomatter":
		return _fail("biomatter kit_id=%s" % str(kit.get("kit_id", "")))
	var modules_v: Variant = kit.get("modules", [])
	if not (modules_v is Array) or (modules_v as Array).is_empty():
		return _fail("biomatter kit has no modules array")
	for entry_v in (modules_v as Array):
		if not (entry_v is Dictionary):
			return _fail("biomatter module entry is not a Dictionary")
		var entry: Dictionary = entry_v
		var mid: String = str(entry.get("module_id", ""))
		var scene: String = str(entry.get("godot_wrapper_scene", ""))
		if mid.is_empty() or scene.is_empty():
			return _fail("biomatter module missing module_id or godot_wrapper_scene")
		if not scene.begins_with(V0_WRAPPER_PREFIX):
			return _fail("biomatter wrapper is not a v0 path: %s" % scene)
	return true


func _check_wrapper_map_fallback() -> bool:
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()
	if not generator._kit_has_wrapper_map(BIOMATTER_KIT_PATH):
		return _fail("biomatter kit should have a wrapper map")
	if generator._kit_has_wrapper_map(HAZARD_KIT_PATH):
		return _fail("hazard kit should still lack wrapper map (fallback to v0)")
	if generator._kit_has_wrapper_map(INDUSTRIAL_KIT_PATH):
		return _fail("industrial kit should still lack wrapper map (fallback to v0)")
	return true


func _check_sockets_fallback() -> bool:
	var biomatter_dir: String = ProjectSettings.globalize_path(
		"res://data/placement/contracts/structural/ship_structural_biomatter")
	var v0_dir: String = ProjectSettings.globalize_path(
		"res://data/placement/contracts/structural/ship_structural_v0")
	if DirAccess.dir_exists_absolute(biomatter_dir):
		return _fail("biomatter must not ship a unique contract dir this milestone")
	if not DirAccess.dir_exists_absolute(v0_dir):
		return _fail("v0 contract dir missing for socket fallback")
	var catalog_path: String = "res://scripts/procgen/modular_socket_catalog.gd"
	if ResourceLoader.exists(catalog_path):
		var catalog_script: Variant = load(catalog_path)
		if not (catalog_script is GDScript):
			return _fail("modular_socket_catalog.gd is not a GDScript")
		var catalog: RefCounted = (catalog_script as GDScript).new()
		if not bool(catalog.call("load_kit", "ship_structural_biomatter")):
			return _fail("socket catalog failed to load biomatter via v0 fallback")
		if str(catalog.get("kit_id")) != "ship_structural_v0":
			return _fail("biomatter sockets should fall back to v0, kit_id=%s" % str(catalog.get("kit_id")))
		var modules_v: Variant = catalog.get("modules")
		if not (modules_v is Dictionary) or (modules_v as Dictionary).is_empty():
			return _fail("v0 fallback contracts empty")
	return true


func _check_hive_layout_and_occupancy() -> bool:
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)
	var layout: Dictionary = generator.generate(bp, {"template": "hive"})
	if layout.is_empty():
		return _fail("hive layout generation returned empty")
	if str(layout.get("template_id", "")) != "hive":
		return _fail("template_id=%s expected=hive" % str(layout.get("template_id", "")))
	if str(layout.get("kit_id", "")) != "ship_structural_biomatter":
		return _fail("hive kit_id=%s expected=ship_structural_biomatter" % str(layout.get("kit_id", "")))
	var rooms_v: Variant = layout.get("rooms", [])
	if not (rooms_v is Array) or (rooms_v as Array).size() < 3:
		return _fail("hive occupancy rooms=%s" % str((rooms_v as Array).size() if rooms_v is Array else 0))
	for room_v in (rooms_v as Array):
		if not (room_v is Dictionary):
			return _fail("hive room is not a Dictionary")
		var cells_v: Variant = (room_v as Dictionary).get("cells", [])
		if not (cells_v is Array) or (cells_v as Array).is_empty():
			return _fail("hive room %s has empty occupancy" % str((room_v as Dictionary).get("id", "")))
		for cell_v in (cells_v as Array):
			if not _is_integer_cell(cell_v):
				return _fail("hive occupancy cell is not an integer cell")
	var portals_v: Variant = layout.get("portals", [])
	if not (portals_v is Array) or (portals_v as Array).is_empty():
		return _fail("hive layout has no portals (no shared cardinal edges)")
	var shared: int = 0
	for portal_v in (portals_v as Array):
		if not (portal_v is Dictionary):
			continue
		var portal: Dictionary = portal_v
		var from_cell: Variant = portal.get("from_cell", portal.get("cell", null))
		var to_cell: Variant = portal.get("to_cell", null)
		if not _is_integer_cell(from_cell):
			return _fail("hive portal from_cell is not integer")
		if to_cell != null and _is_integer_cell(to_cell) and not _is_cardinal_neighbor(from_cell, to_cell):
			return _fail("hive portal endpoints are not a shared cardinal edge")
		shared += 1
	if shared < 1:
		return _fail("hive layout produced no shared-edge portals")
	return true


func _check_hive_kit_independent_of_biome() -> bool:
	var generator: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)
	var hive_layout: Dictionary = generator.generate_with_options(
		bp, {"template": "hive"}, "breach_field", "", false)
	if hive_layout.is_empty():
		return _fail("hive+breach_field layout empty")
	if str(hive_layout.get("kit_id", "")) != "ship_structural_biomatter":
		return _fail("hive kit must ignore biome, kit_id=%s" % str(hive_layout.get("kit_id", "")))
	var spine_layout: Dictionary = generator.generate_with_options(
		bp, {"template": "spine"}, "breach_field", "", false)
	if spine_layout.is_empty():
		return _fail("spine+breach_field layout empty")
	if str(spine_layout.get("kit_id", "")) == "ship_structural_biomatter":
		return _fail("non-hive biome mapping must not stamp biomatter")
	if str(spine_layout.get("template_id", "")) != "spine":
		return _fail("spine template_id=%s" % str(spine_layout.get("template_id", "")))
	return true


func _check_ship_generator_kit_file() -> bool:
	# Resolve the same kit path ShipGenerator._load_layout_as_scene uses.
	# Do not instantiate wrappers: this smoke is the kit-id/occupancy gate.
	var layout_gen: ShipLayoutGeneratorScript = ShipLayoutGeneratorScript.new()
	var generator: ShipGeneratorScript = ShipGeneratorScript.new()
	var bp: ShipBlueprintScript = ShipBlueprintScript.new(
		ShipBlueprintScript.Size.MEDIUM, ShipBlueprintScript.Condition.PRISTINE, 42)
	var hive_layout: Dictionary = layout_gen.generate(bp, {"template": "hive"})
	var hive_path: String = _resolve_generator_kit_path(generator, hive_layout)
	if hive_path != BIOMATTER_KIT_PATH:
		return _fail("ShipGenerator hive kit_path=%s expected=%s" % [hive_path, BIOMATTER_KIT_PATH])
	var hazard_layout: Dictionary = layout_gen.generate_with_options(
		bp, {"template": "spine"}, "breach_field", "", false)
	var hazard_path: String = _resolve_generator_kit_path(generator, hazard_layout)
	if hazard_path != "res://data/kits/ship_structural_v0.json":
		return _fail("hazard kit without wrapper map should fall back to v0, got %s" % hazard_path)
	return true


func _resolve_generator_kit_path(generator: ShipGeneratorScript, layout: Dictionary) -> String:
	var kit_id: String = str(layout.get("kit_id", "ship_structural_v0"))
	if kit_id.is_empty():
		kit_id = "ship_structural_v0"
	var kit_path: String = "res://data/kits/%s.json" % kit_id
	if not FileAccess.file_exists(kit_path) or not generator._kit_has_wrapper_map(kit_path):
		kit_path = "res://data/kits/ship_structural_v0.json"
	return kit_path


func _is_integer_cell(raw: Variant) -> bool:
	if raw is Vector2i:
		return true
	if raw is Array and (raw as Array).size() == 2:
		return typeof((raw as Array)[0]) == TYPE_INT and typeof((raw as Array)[1]) == TYPE_INT
	return false


func _as_cell(raw: Variant) -> Vector2i:
	if raw is Vector2i:
		return raw
	var values: Array = raw
	return Vector2i(int(values[0]), int(values[1]))


func _is_cardinal_neighbor(from_raw: Variant, to_raw: Variant) -> bool:
	var delta: Vector2i = _as_cell(to_raw) - _as_cell(from_raw)
	return abs(delta.x) + abs(delta.y) == 1


func _fail(msg: String) -> bool:
	push_error("HIVE BIOMATTER KIT FAIL: %s" % msg)
	quit(1)
	return false
