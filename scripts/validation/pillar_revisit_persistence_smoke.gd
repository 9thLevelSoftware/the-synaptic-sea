extends SceneTree

## PKG-D6.1: ModuleIntegrityMap + component placement sparse deltas survive
## ShipInstance leave/revisit and ShipRuntime snapshot round-trip.
## Marker: PILLAR REVISIT PERSISTENCE PASS integrity=true components=true ship=true runtime=true

const ShipInstanceScript := preload("res://scripts/systems/ship_instance.gd")
const ShipRuntimeScript := preload("res://scripts/systems/ship_runtime.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")
const ComponentCatalogScript := preload("res://scripts/systems/component_catalog.gd")
const PillarPersistenceScript := preload("res://scripts/systems/pillar_persistence.gd")


func _initialize() -> void:
	# --- Damage + strip on a live map/placement (visit 1) ---
	var map = ModuleIntegrityMapScript.new()
	map.ensure_module("eng/wall_0", "wall_straight_1x1", {"scrap_metal": 2}, "eng")
	map.apply_damage("eng/wall_0", 0.55, "wall_straight_1x1")
	var wall = map.get_module("eng/wall_0")
	if wall != null:
		wall.set("mounted_components", [])
	if map.get_state("eng/wall_0") == ModuleIntegrityStateScript.STATE_INTACT:
		_fail("expected damaged wall before leave"); return
	var damage_state: String = map.get_state("eng/wall_0")
	var damage_fp: String = map.fingerprint()

	var cat = ComponentCatalogScript.new()
	if not cat.load_default():
		_fail("component catalog load"); return
	var place = ComponentPlacementStateScript.new()
	place.populate({
		"rooms": [{
			"id": "eng_1",
			"room_role": "engineering",
			"wall_slots": [{"against_wall": true, "cell": "(0,0)"}],
			"center_slots": [],
		}],
	}, cat, 42)
	if place.placed.is_empty():
		_fail("need at least one placed component"); return
	var first_id: String = str(place.placed[0].get("component_instance_id", ""))
	var dis: Dictionary = place.dismount(first_id)
	if not bool(dis.get("ok", false)):
		_fail("dismount before leave"); return
	if place.is_mounted(first_id):
		_fail("component should be stripped"); return

	# --- Leave: pack onto ShipInstance (sparse) ---
	var inst = ShipInstanceScript.create("ship_m:1", "m:1", null, null, null)
	inst.module_integrity_summary = PillarPersistenceScript.pack_module_integrity(map)
	# Prefer placement summary; pack helper adds schema.
	inst.component_placement_summary = PillarPersistenceScript.pack_component_placement(place)
	if (inst.module_integrity_summary.get("deltas", []) as Array).is_empty():
		_fail("sparse integrity deltas expected on leave"); return

	# ShipInstance get_summary/apply_summary round-trip (world save path).
	var ship_sum: Dictionary = inst.get_summary()
	if not ship_sum.has("module_integrity") or not ship_sum.has("component_placement"):
		_fail("ShipInstance summary missing pillar fields"); return
	var inst2 = ShipInstanceScript.create("ship_m:1", "m:1", null, null, null)
	if not inst2.apply_summary(ship_sum):
		_fail("apply_summary ship"); return
	if inst2.module_integrity_summary.is_empty() or inst2.component_placement_summary.is_empty():
		_fail("pillar fields lost on ship apply_summary"); return

	# --- Revisit: geometry "regenerated" (fresh empty map) + sparse apply ---
	var map_revisit = PillarPersistenceScript.unpack_module_integrity(inst2.module_integrity_summary)
	if map_revisit.get_state("eng/wall_0") != damage_state:
		_fail("integrity state mismatch on revisit got=%s want=%s" % [
			map_revisit.get_state("eng/wall_0"), damage_state
		]); return
	if map_revisit.fingerprint() != damage_fp:
		_fail("integrity fingerprint mismatch on revisit"); return

	var place_revisit = PillarPersistenceScript.unpack_component_placement(inst2.component_placement_summary)
	if place_revisit.is_mounted(first_id):
		_fail("stripped component remounted on revisit"); return
	if place_revisit.placed.size() != place.placed.size():
		_fail("component count mismatch on revisit"); return

	# --- ShipRuntime compose includes integrity + component manifest ---
	var rt = ShipRuntimeScript.new()
	rt.configure(inst2, {
		"is_home": false,
		"module_integrity": map_revisit,
		"component_placement": place_revisit,
	})
	var snap: Dictionary = rt.to_snapshot()
	if typeof(snap.get("module_integrity", null)) != TYPE_DICTIONARY:
		_fail("runtime snapshot module_integrity"); return
	var mi_snap: Dictionary = snap.get("module_integrity", {})
	if (mi_snap.get("deltas", []) as Array).is_empty():
		_fail("runtime snapshot should carry integrity deltas"); return
	if typeof(snap.get("component_manifest", null)) != TYPE_DICTIONARY:
		_fail("runtime snapshot component_manifest"); return
	var cm: Dictionary = snap.get("component_manifest", {})
	if int(cm.get("count", 0)) < 1 and (cm.get("placed", []) as Array).is_empty():
		_fail("runtime component_manifest empty"); return

	var map3 = ModuleIntegrityMapScript.new()
	var place3 = ComponentPlacementStateScript.new()
	var inst3 = ShipInstanceScript.create("ship_m:1", "m:1", null, null, null)
	var rt3 = ShipRuntimeScript.new()
	rt3.configure(inst3, {
		"is_home": false,
		"module_integrity": map3,
		"component_placement": place3,
	})
	rt3.from_snapshot(snap)
	if map3.get_state("eng/wall_0") != damage_state:
		_fail("runtime from_snapshot integrity"); return
	if place3.is_mounted(first_id):
		_fail("runtime from_snapshot should keep dismounted"); return
	if inst3.module_integrity_summary.is_empty():
		_fail("from_snapshot should mirror integrity onto ShipInstance"); return
	if inst3.component_placement_summary.is_empty():
		_fail("from_snapshot should mirror components onto ShipInstance"); return

	# Pristine ship omits pillar keys (sparse).
	var clean = ShipInstanceScript.create("clean", "m:2", null, null, null)
	var clean_sum: Dictionary = clean.get_summary()
	if clean_sum.has("module_integrity") or clean_sum.has("component_placement"):
		_fail("pristine ship should omit empty pillar keys"); return

	print("PILLAR REVISIT PERSISTENCE PASS integrity=true components=true ship=true runtime=true")
	quit(0)


func _fail(msg: String) -> void:
	print("PILLAR REVISIT PERSISTENCE FAIL: %s" % msg)
	quit(1)
