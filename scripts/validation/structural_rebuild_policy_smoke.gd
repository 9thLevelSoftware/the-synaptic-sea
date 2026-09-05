extends SceneTree

## Preparatory P17 proof for exact pure-policy ownership and independent loader
## identity. This is deliberately not FC-19 acceptance: it has no live safety,
## docking, egress, payment, timed-work, or scene-application evidence.

const LoaderScript := preload("res://scripts/procgen/generated_ship_loader.gd")
const ModuleIntegrityMapScript := preload("res://scripts/systems/module_integrity_map.gd")
const ShipGeneratorScript := preload("res://scripts/procgen/ship_generator.gd")
const ShipLayoutGeneratorScript := preload("res://scripts/procgen/ship_layout_generator.gd")
const StructuralRebuildCatalogScript := preload("res://scripts/systems/structural_rebuild_catalog.gd")

const V0_LAYOUT_PATH: String = "res://data/procgen/smoke/seed_000017/layout.json"
const HIVE_TEMPLATE_PATH: String = "res://data/procgen/templates/hive.json"
const REVISION: String = "p17-policy-proof-r2"
const FINGERPRINT: String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"


class ForgedIntegrityAdapter:
    extends RefCounted
    var _real_state: RefCounted

    func _init(real_state: RefCounted) -> void:
        _real_state = real_state

    func get_structural_rebuild_state() -> RefCounted:
        return _real_state

    func get_state(_module_id: String) -> String:
        return "destroyed"


func _initialize() -> void:
    var catalog = StructuralRebuildCatalogScript.new()
    if not catalog.load_canonical() or catalog.row_count() != 60:
        _fail("canonical runtime catalog did not load 60 active rows")
        return
    var first_row_id: String = "ship_structural_v0:floor_1x1"
    var exposed: Dictionary = catalog.resolve_row(first_row_id)
    if exposed.is_empty() or not _is_recursively_read_only(exposed):
        _fail("catalog did not expose a recursively immutable owned row")
        return
    if not _assert_valid_shape_mutants_reject(catalog, first_row_id, exposed):
        return

    var loader = LoaderScript.new()
    var sources: Dictionary = _production_sources()
    if sources.size() != 4:
        _fail("production layout/kit routing did not resolve four active sources")
        return
    var integrity_map: RefCounted = ModuleIntegrityMapScript.new()
    var state: RefCounted = integrity_map.call("get_structural_rebuild_state")
    var covered: int = 0
    var first_module_id: String = ""
    for row_id in catalog.row_ids():
        var expected: Dictionary = catalog.resolve_row(row_id)
        var layout_kit_id: String = str(expected.get("layout_kit_id", ""))
        if not sources.has(layout_kit_id):
            _fail("catalog row has no production layout route: %s" % row_id)
            return
        var source: Dictionary = sources[layout_kit_id] as Dictionary
        var source_layout: Dictionary = source.get("layout", {}) as Dictionary
        var source_kit: Dictionary = source.get("kit", {}) as Dictionary
        var structural_id: String = str(expected.get("original_structural_module_id", ""))
        var actual: Dictionary = loader.resolve_structural_source_identity(
            source_layout, source_kit, structural_id)
        if actual.is_empty():
            _fail("loader did not resolve actual identity for %s" % row_id)
            return
        var module_id: String = "proof/%s" % row_id.replace(":", "/")
        var descriptor: Dictionary = _descriptor_from_actual(actual, module_id)
        if not integrity_map.call("register_original_descriptor", descriptor):
            _fail("actual loader descriptor did not register for %s" % row_id)
            return
        integrity_map.call("apply_damage", module_id, 1.0, structural_id)
        var plan: Dictionary = state.call(
            "evaluate_replace", integrity_map, module_id, row_id, REVISION, FINGERPRINT)
        var requirements_match: bool = _same_requirements(
            plan.get("requirements", {}) as Dictionary,
            expected.get("requirements", {}) as Dictionary)
        var immutable: bool = _is_recursively_read_only(plan)
        if not bool(plan.get("ok", false)) \
                or not bool(plan.get("preflight_required", false)) \
                or bool(plan.get("scene_authorized", true)) \
                or not requirements_match or not immutable:
            _fail("canonical policy candidate invalid requirements=%s immutable=%s plan=%s" % [
                str(requirements_match), str(immutable), str(plan)])
            return
        if first_module_id.is_empty():
            first_module_id = module_id
        covered += 1
    if covered != 60:
        _fail("pure policy did not exercise all 60 active rows")
        return

    var forged := ForgedIntegrityAdapter.new(state)
    var forged_result: Dictionary = state.call(
        "evaluate_replace", forged, first_module_id, first_row_id, REVISION, FINGERPRINT)
    if str(forged_result.get("reason", "")) != "integrity_owner_mismatch":
        _fail("method-compatible forged owner was not rejected: %s" % str(forged_result))
        return
    var other_map: RefCounted = ModuleIntegrityMapScript.new()
    if bool(state.call("bind_integrity_owner", other_map)):
        _fail("rebuild registry rebound to a second concrete map")
        return
    var other_catalog = StructuralRebuildCatalogScript.new()
    if not other_catalog.load_canonical() \
            or bool(state.call("bind_catalog_authority", other_catalog)):
        _fail("rebuild registry rebound to a second catalog authority")
        return
    var wrong_row: Dictionary = state.call(
        "evaluate_replace", integrity_map, first_module_id,
        "ship_structural_v0:wall_end_cap", REVISION, FINGERPRINT)
    if str(wrong_row.get("reason", "")) != "missing_rebuild_policy":
        _fail("caller-selected wrong canonical row was not denied: %s" % str(wrong_row))
        return
    loader.free()
    print("P17 POLICY LOADER PREPARATORY PASS rows=60 forged_owner=true canonical_mutants=7")
    call_deferred("_finish_success")


func _finish_success() -> void:
    await process_frame
    quit(0)


func _production_sources() -> Dictionary:
    var v0_layout: Dictionary = _load_json(V0_LAYOUT_PATH)
    var hive_template: Dictionary = _load_json(HIVE_TEMPLATE_PATH)
    if v0_layout.is_empty() or str(hive_template.get("id", "")) != "hive":
        return {}
    var layout_generator = ShipLayoutGeneratorScript.new()
    var ship_generator = ShipGeneratorScript.new()
    var layouts: Array[Dictionary] = [
        v0_layout,
        {"kit_id": str(layout_generator.call("_kit_id_for_biome", "breach_field"))},
        {"kit_id": str(layout_generator.call("_kit_id_for_biome", "dead_fleet"))},
        {"template_id": str(hive_template.get("id", "")), "kit_id": "ship_structural_biomatter"},
    ]
    var out: Dictionary = {}
    for layout in layouts:
        var layout_kit_id: String = str(layout.get("kit_id", ""))
        var kit_path: String = str(ship_generator.call("kit_path_for_layout", layout))
        var kit: Dictionary = _load_json(kit_path)
        if layout_kit_id.is_empty() or kit.is_empty() \
                or not kit.get("modules", null) is Array \
                or (kit.get("modules", []) as Array).size() != 15:
            return {}
        out[layout_kit_id] = {"layout": layout, "kit": kit, "kit_path": kit_path}
    return out


func _descriptor_from_actual(actual: Dictionary, module_id: String) -> Dictionary:
    return {
        "module_id": module_id,
        "structural_module_id": str(actual.get("structural_module_id", "")),
        "placement_id": module_id,
        "layout_layer": "proof",
        "wrapper_id": str(actual.get("wrapper_id", "")),
        "transform": {"position": [0.0, 0.0, 0.0], "yaw_degrees": 0.0},
        "footprint": (actual.get("footprint_cells", []) as Array).duplicate(true),
        "sockets": (actual.get("socket_names", []) as Array).duplicate(true),
        "socket_bindings": [],
        "room_bindings": [],
        "edge_binding": {},
        "component_bindings": [],
        "system_links": [],
        "layout_revision": REVISION,
        "layout_fingerprint": FINGERPRINT,
        "layout_kit_id": str(actual.get("layout_kit_id", "")),
        "structural_kit_id": str(actual.get("structural_kit_id", "")),
        "structural_contract_id": str(actual.get("structural_contract_id", "")),
        "rebuild_contract_status": str(actual.get("rebuild_contract_status", "")),
    }


func _assert_valid_shape_mutants_reject(
        catalog, row_id: String, canonical: Dictionary) -> bool:
    var mutants: Array[Dictionary] = []
    var material_amount: Dictionary = canonical.duplicate(true)
    material_amount["requirements"]["materials"]["plating"] = \
        int(material_amount["requirements"]["materials"]["plating"]) + 1
    mutants.append(material_amount)
    var material_id: Dictionary = canonical.duplicate(true)
    material_id["requirements"]["materials"].erase("plating")
    material_id["requirements"]["materials"]["different_material"] = 1
    mutants.append(material_id)
    var tool: Dictionary = canonical.duplicate(true)
    tool["requirements"]["tool_class"] = "different_tool_class"
    mutants.append(tool)
    var skill_id: Dictionary = canonical.duplicate(true)
    skill_id["requirements"]["skill_id"] = "different_skill"
    mutants.append(skill_id)
    var skill_threshold: Dictionary = canonical.duplicate(true)
    skill_threshold["requirements"]["min_skill"] = \
        int(skill_threshold["requirements"]["min_skill"]) + 1
    mutants.append(skill_threshold)
    var duration: Dictionary = canonical.duplicate(true)
    duration["requirements"]["duration_seconds"] = \
        int(duration["requirements"]["duration_seconds"]) + 1
    mutants.append(duration)
    var action: Dictionary = canonical.duplicate(true)
    action["action_id"] = "different_action"
    mutants.append(action)
    for mutant in mutants:
        var result: Dictionary = catalog.verify_row_claim(row_id, mutant)
        if bool(result.get("ok", true)) \
                or str(result.get("reason", "")) != "catalog_authority_mismatch":
            _fail("valid-shape caller policy mutation was not rejected: %s" % str(result))
            return false
    if not bool(catalog.verify_row_claim(row_id, canonical).get("ok", false)):
        _fail("canonical immutable row did not verify against its owner")
        return false
    return true


func _same_requirements(left: Dictionary, right: Dictionary) -> bool:
    if str(left.get("tool_class", "")) != str(right.get("tool_class", "")) \
            or str(left.get("skill_id", "")) != str(right.get("skill_id", "")) \
            or int(left.get("min_skill", -1)) != int(right.get("min_skill", -1)) \
            or int(left.get("duration_seconds", -1)) != int(right.get("duration_seconds", -1)):
        return false
    var left_materials: Dictionary = left.get("materials", {}) as Dictionary
    var right_materials: Dictionary = right.get("materials", {}) as Dictionary
    if left_materials.size() != right_materials.size():
        return false
    for item_id in left_materials.keys():
        if not right_materials.has(item_id) \
                or int(left_materials[item_id]) != int(right_materials[item_id]):
            return false
    return true


func _is_recursively_read_only(value: Variant) -> bool:
    if value is Dictionary:
        if not (value as Dictionary).is_read_only():
            return false
        for child in (value as Dictionary).values():
            if not _is_recursively_read_only(child):
                return false
    elif value is Array:
        if not (value as Array).is_read_only():
            return false
        for child in value as Array:
            if not _is_recursively_read_only(child):
                return false
    return true


func _load_json(path: String) -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}


func _fail(reason: String) -> void:
    print("P17 POLICY LOADER PREPARATORY FAIL: %s" % reason)
    quit(1)
