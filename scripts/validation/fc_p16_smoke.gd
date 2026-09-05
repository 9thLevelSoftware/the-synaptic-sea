extends SceneTree

## FC-18 / P16: destroyed structural wrappers retain authored rebuild identity.
## Marker: FC P16 PASS

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ModuleIntegrityStateScript := preload("res://scripts/systems/module_integrity_state.gd")
const PlayableGeneratedShipScript := preload("res://scripts/procgen/playable_generated_ship.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const StructuralRebuildCatalogScript := preload("res://scripts/systems/structural_rebuild_catalog.gd")

const LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const KIT_PATH: String = "res://data/kits/ship_structural_v0.json"
const GAMEPLAY_PATH: String = "res://data/procgen/smoke/seed_000017/gameplay_slice.json"
const HIVE_TEMPLATE_PATH: String = "res://data/procgen/templates/hive.json"


func _initialize() -> void:
	var layout: Dictionary = _load_json(LAYOUT_PATH)
	var kit: Dictionary = _load_json(KIT_PATH)
	var gameplay: Dictionary = _load_json(GAMEPLAY_PATH)
	if layout.is_empty() or kit.is_empty() or gameplay.is_empty():
		_fail("real generated/authored fixture documents did not load")
		return
	var placements: Array = (layout.get("structural_plan", {}) as Dictionary).get("placements", [])
	if placements.is_empty() or not placements[0] is Dictionary:
		_fail("fixture has no structural edge placement")
		return
	var placement: Dictionary = placements[0]
	var edge_key: String = str(placement.get("edge_key", ""))
	var target_id: String = "edge/%s" % edge_key
	var placement_id: String = str(placement.get("placement_id", ""))
	var structural_kind: String = str(placement.get("module_id", ""))
	var expected_position: Array = (placement.get("position", []) as Array).duplicate(true)

	var loader = LoaderScript.new()
	get_root().add_child(loader)
	if not loader.load_from_documents(layout.duplicate(true), kit, gameplay, false):
		_fail("intact real fixture failed to load")
		return
	if not loader.has_method("get_structural_rebuild_state"):
		_fail("loader did not register structural rebuild descriptors")
		return
	var rebuild_state: RefCounted = loader.call("get_structural_rebuild_state")
	var intact_result: Dictionary = rebuild_state.call("inspect_target", target_id)
	if not bool(intact_result.get("ok", false)):
		_fail("intact target descriptor is not queryable: %s" % str(intact_result))
		return
	var original: Dictionary = intact_result.get("original_descriptor", {})
	if not _assert_authored_descriptor(original, target_id, placement_id, edge_key, structural_kind, expected_position):
		return
	if not _assert_all_active_contract_identity(loader, layout):
		return
	if not _assert_unsupported_contract_loads(
			layout, kit, gameplay, target_id, structural_kind):
		return
	var intact_revision: String = str(original.get("layout_revision", ""))
	var intact_fingerprint: String = str(original.get("layout_fingerprint", ""))
	if not intact_revision.begins_with("derived:") or intact_fingerprint.length() != 64:
		_fail("missing derived source-layout identity revision=%s fingerprint=%s" % [intact_revision, intact_fingerprint])
		return

	# Dynamic damage uses the production integrity map and real authored wrapper.
	if not loader.has_method("get_module_integrity_map") or not loader.has_method("apply_module_integrity_state"):
		_fail("loader has no integrity-to-registered-descriptor scene seam")
		return
	var integrity_map: RefCounted = loader.call("get_module_integrity_map")
	integrity_map.call("apply_damage", target_id, 1.0, structural_kind)
	if not bool(loader.call("apply_module_integrity_state", target_id)):
		_fail("dynamic destruction did not reach the real wrapper")
		return
	var destroyed_result: Dictionary = integrity_map.call("inspect_rebuild_target", target_id)
	if not bool(destroyed_result.get("ok", false)) \
			or str(destroyed_result.get("state", "")) != "destroyed" \
			or not bool(destroyed_result.get("replaceable", false)):
		_fail("destroyed target is not inspectable: %s" % str(destroyed_result))
		return
	if destroyed_result.get("original_descriptor", {}) != original:
		_fail("destruction mutated the original descriptor")
		return
	var sparse_integrity: Dictionary = integrity_map.call("get_summary")
	if not bool(integrity_map.call("apply_summary", sparse_integrity)):
		_fail("existing integrity summary did not reapply")
		return
	var reapplied_result: Dictionary = integrity_map.call("inspect_rebuild_target", target_id)
	if not bool(reapplied_result.get("ok", false)) \
			or reapplied_result.get("original_descriptor", {}) != original \
			or str(reapplied_result.get("state", "")) != "destroyed":
		_fail("sparse integrity reapply erased the original descriptor: %s" % str(reapplied_result))
		return
	var wrapper: Node3D = _find_wrapper(loader.structural_root, target_id)
	if wrapper == null or not _wrapper_is_destroyed_noncolliding(wrapper):
		_fail("destroyed real wrapper remained visible or collidable")
		return

	# A pristine sparse summary resets the mutable integrity owner while keeping
	# every descriptor-seeded module, kind, and room binding synchronized.
	if not bool(integrity_map.call("apply_summary", {
		"schema": "module_integrity_map_v1",
		"deltas": [],
		"registered": integrity_map.call("size"),
	})):
		_fail("pristine integrity summary was rejected")
		return
	var pristine_result: Dictionary = integrity_map.call("inspect_rebuild_target", target_id)
	var pristine_module: RefCounted = integrity_map.call("get_module", target_id)
	if not bool(pristine_result.get("ok", false)) \
			or str(pristine_result.get("state", "")) != "intact" \
			or bool(pristine_result.get("replaceable", true)) \
			or pristine_result.get("original_descriptor", {}) != original \
			or pristine_module == null \
			or str(pristine_module.get("kind")) != structural_kind \
			or pristine_module.get("owner_rooms") != PackedStringArray(["storage_11"]):
		_fail("pristine summary did not rebuild the descriptor baseline: %s" % str(pristine_result))
		return

	# Direct calls on the ordinary repair API remain visible to rebuild
	# inspection because the map owns the only mutable integrity state.
	integrity_map.call("apply_damage", target_id, 0.3, structural_kind)
	pristine_module.call("repair", 0.3)
	var repaired_result: Dictionary = integrity_map.call("inspect_rebuild_target", target_id)
	if str(repaired_result.get("state", "")) != "intact" \
			or bool(repaired_result.get("replaceable", true)):
		_fail("ordinary repair and rebuild inspection diverged: %s" % str(repaired_result))
		return
	var repair_state = ModuleIntegrityStateScript.new()
	repair_state.configure({"module_id": target_id, "kind": structural_kind})
	repair_state.apply_damage(1.0)
	repair_state.repair(1.0)
	if repair_state.state != ModuleIntegrityStateScript.STATE_DESTROYED:
		_fail("ordinary repair resurrected a destroyed module")
		return

	# A clean regeneration of the same source must produce identical identity.
	loader.clear_loaded_ship()
	if not loader.load_from_documents(layout.duplicate(true), kit, gameplay, false):
		_fail("same-source regeneration failed")
		return
	var reloaded_result: Dictionary = loader.call("get_structural_rebuild_state").call("inspect_target", target_id)
	if reloaded_result.get("original_descriptor", {}) != original:
		_fail("same seed/version regeneration changed descriptor identity")
		return

	# Damage overlays are excluded from source-layout identity, including initial wrecks.
	var wrecked_layout: Dictionary = layout.duplicate(true)
	wrecked_layout["module_damage"] = [{
		"module_id": target_id,
		"module_key": target_id,
		"placement_id": placement_id,
		"kind": structural_kind,
		"room_id": str((placement.get("room_ids", []) as Array)[0]),
		"amount": 1.0,
		"state": "destroyed",
	}]
	loader.clear_loaded_ship()
	if not loader.load_from_documents(wrecked_layout, kit, gameplay, false):
		_fail("initially destroyed real fixture failed to load")
		return
	var wreck_result: Dictionary = loader.call("inspect_rebuild_target", target_id)
	if not bool(wreck_result.get("replaceable", false)) \
			or str(wreck_result.get("state", "")) != "destroyed":
		_fail("initial wreck was not registered as a destroyed target: %s" % str(wreck_result))
		return
	var wreck_descriptor: Dictionary = wreck_result.get("original_descriptor", {})
	if str(wreck_descriptor.get("layout_revision", "")) != intact_revision \
			or str(wreck_descriptor.get("layout_fingerprint", "")) != intact_fingerprint:
		_fail("damage overlay changed original layout identity")
		return
	wrapper = _find_wrapper(loader.structural_root, target_id)
	if wrapper == null or not _wrapper_is_destroyed_noncolliding(wrapper):
		_fail("initially destroyed wrapper remained visible or collidable")
		return

	# Original geometry changes must invalidate a derived revision even at one schema.
	var all_originals: Array = loader.call("get_structural_rebuild_state").call("get_original_descriptors")
	var same_identity: Dictionary = loader.call("derive_structural_layout_identity", layout, all_originals)
	if str(same_identity.get("layout_revision", "")) != intact_revision:
		_fail("canonical re-hash of same source changed derived revision")
		return
	var moved_originals: Array = all_originals.duplicate(true)
	var moved_index: int = -1
	for index in range(moved_originals.size()):
		if str((moved_originals[index] as Dictionary).get("module_id", "")) == target_id:
			moved_index = index
			break
	if moved_index < 0:
		_fail("target missing from canonical descriptor set")
		return
	var moved_descriptor: Dictionary = moved_originals[moved_index]
	var moved_transform: Dictionary = (moved_descriptor.get("transform", {}) as Dictionary).duplicate(true)
	var moved_position: Array = (moved_transform.get("position", []) as Array).duplicate()
	moved_position[0] = float(moved_position[0]) + 0.25
	moved_transform["position"] = moved_position
	moved_descriptor["transform"] = moved_transform
	moved_originals[moved_index] = moved_descriptor
	var moved_identity: Dictionary = loader.call("derive_structural_layout_identity", layout, moved_originals)
	if str(moved_identity.get("layout_revision", "")) == intact_revision:
		_fail("changed original transform retained the prior derived revision")
		return
	var identity_changed_originals: Array = all_originals.duplicate(true)
	var identity_changed_descriptor: Dictionary = (identity_changed_originals[0] as Dictionary).duplicate(true)
	identity_changed_descriptor["structural_contract_id"] = "res://data/placement/contracts/structural/ship_structural_v0/not-authored.tres"
	identity_changed_originals[0] = identity_changed_descriptor
	var contract_changed_identity: Dictionary = loader.call("derive_structural_layout_identity", layout, identity_changed_originals)
	if str(contract_changed_identity.get("layout_revision", "")) == intact_revision:
		_fail("changed structural contract retained the prior derived revision")
		return

	# Explicit revisions remain authoritative while still recording a fingerprint.
	var explicit_layout: Dictionary = layout.duplicate(true)
	explicit_layout["layout_revision"] = "layout-fixture-r42"
	loader.clear_loaded_ship()
	if not loader.load_from_documents(explicit_layout, kit, gameplay, false):
		_fail("explicit-revision fixture failed to load")
		return
	var explicit_descriptor: Dictionary = loader.call("get_structural_rebuild_state").call("inspect_target", target_id).get("original_descriptor", {})
	if str(explicit_descriptor.get("layout_revision", "")) != "layout-fixture-r42" \
			or str(explicit_descriptor.get("layout_revision_source", "")) != "explicit" \
			or str(explicit_descriptor.get("layout_fingerprint", "")).length() != 64:
		_fail("explicit layout revision was not preserved with fingerprint evidence")
		return

	var missing: Dictionary = loader.call("get_structural_rebuild_state").call("inspect_target", "edge/not-authored")
	if bool(missing.get("ok", true)) or str(missing.get("reason", "")) != "missing_original_descriptor":
		_fail("unknown target did not return missing_original_descriptor: %s" % str(missing))
		return

	# A normally initialized playable coordinator must share its generated
	# loader's integrity owner before fire/work/threat damage is routed.
	loader.free()
	var coordinator = PlayableGeneratedShipScript.new()
	get_root().add_child(coordinator)
	for _frame in range(3):
		await process_frame
	var coordinator_loader: Node = coordinator.get("loader")
	if coordinator_loader == null or not coordinator_loader.has_method("get_module_integrity_map"):
		_fail("playable coordinator did not initialize its generated loader")
		return
	if coordinator.call("get_module_integrity_map_for_validation") \
			!= coordinator_loader.call("get_module_integrity_map"):
		_fail("playable coordinator retained a parallel integrity authority")
		return
	var coordinator_rebuild: RefCounted = coordinator_loader.call("get_structural_rebuild_state")
	var coordinator_ids: PackedStringArray = coordinator_rebuild.call("module_ids")
	if coordinator_ids.is_empty():
		_fail("playable coordinator loader had no structural descriptors")
		return
	var coordinator_target_id: String = coordinator_ids[0]
	var coordinator_damage: Dictionary = coordinator.call(
		"apply_threat_structure_damage_for_validation", coordinator_target_id, 1.0)
	var coordinator_result: Dictionary = coordinator.call(
		"inspect_structural_rebuild_target_for_validation", coordinator_target_id)
	if not bool(coordinator_damage.get("ok", false)) \
			or str(coordinator_result.get("state", "")) != "destroyed" \
			or not bool(coordinator_result.get("replaceable", false)):
		_fail("coordinator damage target was not inspectable as destroyed: %s" % str(coordinator_result))
		return
	wrapper = _find_wrapper(coordinator_loader, coordinator_target_id)
	if wrapper == null or not _wrapper_is_destroyed_noncolliding(wrapper):
		_fail("coordinator destruction did not disable the real wrapper")
		return
	var coordinator_map: RefCounted = coordinator.call("get_module_integrity_map_for_validation")
	var active_ship: RefCounted = coordinator.get("current_ship")
	active_ship.set("module_integrity_summary", {
		"schema": "module_integrity_map_v1",
		"deltas": [],
		"registered": coordinator_map.call("size"),
	})
	coordinator.call("_restore_module_integrity_for_current_ship")
	var restored_result: Dictionary = coordinator.call(
		"inspect_structural_rebuild_target_for_validation", coordinator_target_id)
	if coordinator.call("get_module_integrity_map_for_validation") != coordinator_map \
			or str(restored_result.get("state", "")) != "intact" \
			or restored_result.get("original_descriptor", {}) \
			!= coordinator_result.get("original_descriptor", {}):
		_fail("coordinator pristine restore replaced its owner or lost identity: %s" % str(restored_result))
		return

	coordinator.free()
	print("FC P16 PASS")
	quit(0)


func _assert_authored_descriptor(
		descriptor: Dictionary,
		target_id: String,
		placement_id: String,
		edge_key: String,
		structural_kind: String,
		expected_position: Array) -> bool:
	if str(descriptor.get("module_id", "")) != target_id:
		_fail("descriptor lost stable target module_id")
		return false
	if str(descriptor.get("structural_module_id", "")) != structural_kind \
			or str(descriptor.get("placement_id", "")) != placement_id:
		_fail("descriptor lost component/layout placement binding")
		return false
	if str(descriptor.get("wrapper_id", "")) != "res://scenes/wrappers/structural/ship_structural_v0/wall_outer_corner.tscn":
		_fail("descriptor lost authoritative wrapper")
		return false
	if str(descriptor.get("layout_kit_id", "")) != "ship_structural_v0" \
			or str(descriptor.get("structural_kit_id", "")) != "ship_structural_v0" \
			or str(descriptor.get("structural_contract_id", "")) \
			!= "res://data/placement/contracts/structural/ship_structural_v0/wall_outer_corner_contract.tres" \
			or str(descriptor.get("rebuild_contract_status", "")) != "supported":
		_fail("descriptor lost exact layout/kit/contract identity: %s" % str(descriptor))
		return false
	if descriptor.get("footprint", []) != [1.0, 1.0]:
		_fail("descriptor lost authored footprint: %s" % str(descriptor.get("footprint", null)))
		return false
	var transform: Dictionary = descriptor.get("transform", {})
	if transform.get("position", []) != expected_position or float(transform.get("yaw_degrees", -1.0)) != 180.0:
		_fail("descriptor lost authored transform")
		return false
	var sockets: Array = descriptor.get("sockets", [])
	if not sockets.has("SOCK_outer_corner_vertex_north_01") \
			or not sockets.has("SOCK_inner_corner_vertex_south_01"):
		_fail("descriptor lost authored module sockets")
		return false
	if descriptor.get("socket_bindings", null) != []:
		_fail("empty authored socket bindings were guessed or lost")
		return false
	var room_bindings: Array = descriptor.get("room_bindings", [])
	if room_bindings != ["storage_11", ""]:
		_fail("descriptor lost exact room bindings: %s" % str(room_bindings))
		return false
	var edge_binding: Dictionary = descriptor.get("edge_binding", {})
	if str(edge_binding.get("edge_key", "")) != edge_key \
			or edge_binding.get("source_cells", []) != [[12.0, 3.0, 0.0], [12.0, 2.0, 0.0]]:
		_fail("descriptor lost edge binding: %s" % str(edge_binding))
		return false
	if str(edge_binding.get("topology_state", "")) != "SOLID" \
			or str(edge_binding.get("topology_kind", "")) != "SOLID" \
			or edge_binding.has("state") \
			or edge_binding.has("kind") \
			or edge_binding.has("integrity_state"):
		_fail("edge topology and runtime integrity were not distinguished: %s" % str(edge_binding))
		return false
	if descriptor.get("component_bindings", null) != [] or descriptor.get("system_links", null) != []:
		_fail("absent component/system bindings were guessed")
		return false
	return true


## P17 dependency proof: actual layout routing selects an exact structural kit,
## and the loader resolves every module from that kit and its loaded contract
## Resource. The rebuild catalog is only the expected side of the comparison.
func _assert_all_active_contract_identity(loader, v0_layout: Dictionary) -> bool:
	var catalog = StructuralRebuildCatalogScript.new()
	if not catalog.load_canonical() or catalog.row_count() != 60:
		_fail("canonical rebuild catalog did not expose all 60 reviewed rows")
		return false
	var layout_generator = ShipLayoutGeneratorScript.new()
	var ship_generator = ShipGeneratorScript.new()
	var hive_template: Dictionary = _load_json(HIVE_TEMPLATE_PATH)
	if str(hive_template.get("id", "")) != "hive":
		_fail("actual hive template identity is missing")
		return false
	var routes: Array[Dictionary] = [
		{"source": "v0_fixture", "layout": v0_layout.duplicate(true)},
		{"source": "breach_field", "layout": {
			"kit_id": str(layout_generator.call("_kit_id_for_biome", "breach_field")),
		}},
		{"source": "dead_fleet", "layout": {
			"kit_id": str(layout_generator.call("_kit_id_for_biome", "dead_fleet")),
		}},
		# ShipLayoutGenerator's actual hive branch stamps this exact kit ID. The
		# checked source template above prevents a catalog row from inventing it.
		{"source": "hive", "layout": {
			"template_id": str(hive_template.get("id", "")),
			"kit_id": "ship_structural_biomatter",
		}},
	]
	var seen_rows: Dictionary = {}
	var route_kits: Dictionary = {}
	for route in routes:
		var source_layout: Dictionary = route.get("layout", {}) as Dictionary
		var layout_kit_id: String = str(source_layout.get("kit_id", ""))
		var kit_path: String = str(ship_generator.call("kit_path_for_layout", source_layout))
		var source_kit: Dictionary = _load_json(kit_path)
		if layout_kit_id.is_empty() or source_kit.is_empty():
			_fail("production structural route did not resolve: %s" % str(route))
			return false
		route_kits[layout_kit_id] = source_kit
		var modules_variant: Variant = source_kit.get("modules", null)
		if not modules_variant is Array or (modules_variant as Array).size() != 15:
			_fail("resolved kit did not contain 15 actual modules: %s" % kit_path)
			return false
		for module_variant in modules_variant as Array:
			if not module_variant is Dictionary:
				_fail("resolved kit contains a non-module row")
				return false
			var module_id: String = str((module_variant as Dictionary).get("module_id", ""))
			var row_id: String = "%s:%s" % [layout_kit_id, module_id]
			var expected: Dictionary = catalog.resolve_row(row_id)
			var actual: Dictionary = loader.resolve_structural_source_identity(
				source_layout, source_kit, module_id)
			if expected.is_empty() or actual.is_empty() \
					or not _actual_identity_matches_catalog(actual, expected):
				_fail("production loader/catalog identity mismatch for %s actual=%s" % [
					row_id, str(actual)])
				return false
			seen_rows[row_id] = true
	if seen_rows.size() != 60 or seen_rows.size() != catalog.row_count():
		_fail("production identity proof did not cover exactly 60 rows")
		return false
	var v0_kit: Dictionary = route_kits.get("ship_structural_v0", {}) as Dictionary
	var v0_source: Dictionary = {"kit_id": "ship_structural_v0"}
	for mutant_case in [
		{"kit": _mutated_kit(v0_kit, "floor_1x1", "godot_contract", ""),
			"reason": "missing_socket_contract"},
		{"kit": _mutated_kit(v0_kit, "floor_1x1", "godot_contract",
			"res://data/placement/contracts/structural/ship_structural_v0/wall_end_cap_contract.tres"),
			"reason": "unsupported_rebuild"},
		{"kit": _mutated_kit(v0_kit, "floor_1x1", "godot_wrapper_scene",
			"res://scenes/wrappers/structural/ship_structural_v0/wall_end_cap.tscn"),
			"reason": "unsupported_rebuild"},
		{"kit": _mutated_kit(v0_kit, "floor_1x1", "footprint_cells", [2, 1]),
			"reason": "unsupported_rebuild"},
		{"kit": _mutated_kit(v0_kit, "floor_1x1", "socket_names", ["SOCK_not_authored"]),
			"reason": "unsupported_rebuild"},
	]:
		var unsupported: Dictionary = loader.resolve_structural_source_identity(
			v0_source, mutant_case.get("kit", {}) as Dictionary, "floor_1x1")
		if unsupported.is_empty() \
				or str(unsupported.get("structural_contract_id", "")) != "" \
				or str(unsupported.get("rebuild_contract_status", "")) \
				!= str(mutant_case.get("reason", "")):
			_fail("loader authorized missing/mismatched contract identity: %s" % str(unsupported))
			return false
	return true


func _actual_identity_matches_catalog(actual: Dictionary, expected: Dictionary) -> bool:
	if str(actual.get("rebuild_contract_status", "")) != "supported" \
			or str(actual.get("layout_kit_id", "")) != str(expected.get("layout_kit_id", "")) \
			or str(actual.get("structural_kit_id", "")) != str(expected.get("structural_kit_id", "")) \
			or str(actual.get("structural_contract_id", "")) != str(expected.get("structural_contract_id", "")) \
			or str(actual.get("structural_module_id", "")) != str(expected.get("original_structural_module_id", "")) \
			or str(actual.get("wrapper_id", "")) != str(expected.get("replacement_wrapper_id", "")) \
			or actual.get("footprint_cells", []) != expected.get("footprint_cells", []) \
			or str(actual.get("contract_kit_id", "")) != "ship_structural_v0":
		return false
	var actual_sockets: Array = actual.get("socket_names", []) as Array
	var expected_sockets: Array = []
	for mapping_variant in expected.get("socket_mapping", []) as Array:
		expected_sockets.append(str((mapping_variant as Dictionary).get("original_socket", "")))
	actual_sockets.sort()
	expected_sockets.sort()
	return actual_sockets == expected_sockets


## P17 contract metadata is optional for physical compatibility. These cases
## drive the real loader, retain the actual wrapper and kit-authored descriptor,
## then prove pure replacement policy denies without deriving a fallback.
func _assert_unsupported_contract_loads(
		source_layout: Dictionary,
		source_kit: Dictionary,
		gameplay: Dictionary,
		target_id: String,
		structural_module_id: String) -> bool:
	var kit_record: Dictionary = _kit_module_record(source_kit, structural_module_id)
	var conflicting_contract: String = _different_contract_path(
		source_kit, structural_module_id)
	if kit_record.is_empty() or conflicting_contract.is_empty():
		_fail("fixture cannot build unsupported rebuild contract cases")
		return false
	var cases: Array[Dictionary] = [
		{"kit": _mutated_kit(source_kit, structural_module_id, "godot_contract", ""),
			"reason": "missing_socket_contract"},
		{"kit": _mutated_kit(
			source_kit, structural_module_id, "godot_contract", conflicting_contract),
			"reason": "unsupported_rebuild"},
	]
	for test_case in cases:
		var probe = LoaderScript.new()
		get_root().add_child(probe)
		if not probe.load_from_documents(
				source_layout.duplicate(true),
				(test_case.get("kit", {}) as Dictionary).duplicate(true),
				gameplay.duplicate(true), false):
			probe.free()
			_fail("wrapper-valid ship failed for unsupported rebuild contract")
			return false
		var wrapper: Node3D = _find_wrapper(probe.structural_root, target_id)
		var integrity_map: RefCounted = probe.call("get_module_integrity_map")
		var inspection: Dictionary = integrity_map.call("inspect_rebuild_target", target_id)
		var descriptor: Dictionary = inspection.get("original_descriptor", {}) as Dictionary
		var expected_reason: String = str(test_case.get("reason", ""))
		if wrapper == null or not bool(inspection.get("ok", false)) \
				or str(descriptor.get("structural_module_id", "")) != structural_module_id \
				or str(descriptor.get("wrapper_id", "")) \
				!= str(kit_record.get("godot_wrapper_scene", "")) \
				or descriptor.get("footprint", []) != kit_record.get("footprint_cells", []) \
				or descriptor.get("sockets", []) != kit_record.get("socket_names", []) \
				or not str(descriptor.get("structural_contract_id", "")).is_empty() \
				or str(descriptor.get("rebuild_contract_status", "")) != expected_reason:
			probe.free()
			_fail("unsupported contract lost physical descriptor: %s" % str(inspection))
			return false
		integrity_map.call("apply_damage", target_id, 1.0, structural_module_id)
		var rebuild_state: RefCounted = integrity_map.call("get_structural_rebuild_state")
		var denial: Dictionary = rebuild_state.call(
			"evaluate_replace", integrity_map, target_id,
			"%s:%s" % [str(source_layout.get("kit_id", "")), structural_module_id],
			str(descriptor.get("layout_revision", "")),
			str(descriptor.get("layout_fingerprint", "")))
		probe.free()
		if bool(denial.get("ok", true)) \
				or str(denial.get("reason", "")) != expected_reason:
			_fail("unsupported contract replacement did not fail closed: %s" % str(denial))
			return false
	return true


func _kit_module_record(source_kit: Dictionary, module_id: String) -> Dictionary:
	for module_variant in source_kit.get("modules", []) as Array:
		if module_variant is Dictionary \
				and str((module_variant as Dictionary).get("module_id", "")) == module_id:
			return (module_variant as Dictionary).duplicate(true)
	return {}


func _different_contract_path(source_kit: Dictionary, module_id: String) -> String:
	for module_variant in source_kit.get("modules", []) as Array:
		if not module_variant is Dictionary \
				or str((module_variant as Dictionary).get("module_id", "")) == module_id:
			continue
		var contract_path: String = str((module_variant as Dictionary).get("godot_contract", ""))
		if not contract_path.is_empty():
			return contract_path
	return ""


func _mutated_kit(
		source_kit: Dictionary, module_id: String, field: String, value: Variant) -> Dictionary:
	var mutated: Dictionary = source_kit.duplicate(true)
	var modules: Array = mutated.get("modules", []) as Array
	for index in range(modules.size()):
		var module: Dictionary = modules[index] as Dictionary
		if str(module.get("module_id", "")) != module_id:
			continue
		module[field] = value
		modules[index] = module
		break
	mutated["modules"] = modules
	return mutated


func _wrapper_is_destroyed_noncolliding(wrapper: Node3D) -> bool:
	if str(wrapper.get_meta("integrity_state", "")) != "destroyed":
		return false
	var visual: Node = wrapper.get_node_or_null("Visual")
	if visual == null:
		return false
	for child in visual.get_children():
		if child is Node3D and (child as Node3D).visible:
			return false
	var shapes: Array[CollisionShape3D] = []
	_collect_collision_shapes(wrapper, shapes)
	if shapes.is_empty():
		return false
	for shape in shapes:
		if not shape.disabled:
			return false
	return true


func _collect_collision_shapes(node: Node, out: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		out.append(node as CollisionShape3D)
	for child in node.get_children():
		_collect_collision_shapes(child, out)


func _find_wrapper(node: Node, module_id: String) -> Node3D:
	if node is Node3D and str(node.get_meta("module_key", "")) == module_id:
		return node as Node3D
	for child in node.get_children():
		var found: Node3D = _find_wrapper(child, module_id)
		if found != null:
			return found
	return null


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _fail(reason: String) -> void:
	print("FC P16 FAIL: %s" % reason)
	quit(1)
