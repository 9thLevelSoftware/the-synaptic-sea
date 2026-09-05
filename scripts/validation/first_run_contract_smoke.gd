extends SceneTree

## Task 2.3 / ADR-0067: the first-away contract selects from production
## ShipGenerator candidates and fails closed when none qualify.
## Marker: FIRST RUN CONTRACT PASS

const FirstRunContractScript: GDScript = preload("res://scripts/procgen/first_run_contract.gd")
const ShipBlueprintScript: GDScript = preload("res://scripts/procgen/ship_blueprint.gd")

const BIOME_ID: String = "breach_field"
const DIFFICULTY_ID: String = "standard"
const EXPECTED_FIRST_SEED: int = 42
const LOCKED_SEED: int = 777


func _initialize() -> void:
    if not ClassDB.class_exists("DerelictGenerator"):
        _fail("DerelictGenerator class unavailable")
        return
    var contract = FirstRunContractScript.new()
    if not contract.load_contract():
        _fail("contract did not load")
        return
    var candidates: Dictionary = {}
    for seed_variant in contract.contract.get("preferred_seeds", []):
        var seed_value: int = int(seed_variant)
        var candidate: Dictionary = _native_candidate(seed_value)
        if candidate.is_empty():
            _fail("native candidate generation failed seed=%d" % seed_value)
            return
        candidates[seed_value] = candidate

    if not contract.validate(
            (candidates[EXPECTED_FIRST_SEED] as Dictionary).get("layout", {}),
            (candidates[EXPECTED_FIRST_SEED] as Dictionary).get("gameplay_slice", {})):
        _fail("first native preferred candidate did not satisfy the complete contract")
        return
    var locked_layout: Dictionary = (candidates[LOCKED_SEED] as Dictionary).get("layout", {})
    var locked_gameplay: Dictionary = (candidates[LOCKED_SEED] as Dictionary).get("gameplay_slice", {})
    if contract.validation_failure_reason(locked_layout, locked_gameplay) != "standing_route":
        _fail("native locked candidate did not fail solely on standing route")
        return
    if not _has_locked_edge_between(locked_layout, "corridor_02", "corridor_03"):
        _fail("rejected native candidate lost corridor_02/corridor_03 LOCKED crossing")
        return

    # The same authored lock is off the standing critical route at DAMAGED
    # intactness. It must survive native integration without over-rejecting a
    # candidate that still has a valid standing start-to-goal path.
    var noncritical_lock_candidate: Dictionary = _native_candidate(
        LOCKED_SEED, ShipBlueprintScript.Condition.DAMAGED)
    if noncritical_lock_candidate.is_empty() or not contract.validate(
            noncritical_lock_candidate.get("layout", {}),
            noncritical_lock_candidate.get("gameplay_slice", {})):
        _fail("native candidate with noncritical LOCKED edge lost its standing route")
        return
    if not _has_locked_edge(noncritical_lock_candidate.get("layout", {})):
        _fail("qualifying native candidate lost its noncritical LOCKED edge")
        return

    var picked_seed: int = contract.pick_seed(candidates)
    if picked_seed != EXPECTED_FIRST_SEED:
        _fail("pick_seed selected %d expected first qualifying seed %d" % [picked_seed, EXPECTED_FIRST_SEED])
        return
    var no_candidate_seed: int = contract.pick_seed({})
    if no_candidate_seed != -1:
        _fail("pick_seed did not fail closed; selected %d from empty candidates" % no_candidate_seed)
        return

    var repeated: Dictionary = _native_candidate(EXPECTED_FIRST_SEED)
    if repeated.is_empty() or JSON.stringify(repeated.get("layout", {})) \
            != JSON.stringify((candidates[EXPECTED_FIRST_SEED] as Dictionary).get("layout", {})):
        _fail("repeated native candidate layout was not deterministic")
        return
    print("FIRST RUN CONTRACT PASS seed=%d native=true standing=true locked_rejected=true fail_closed=true" % picked_seed)
    quit(0)


func _native_candidate(
        seed_value: int,
        condition: int = ShipBlueprintScript.Condition.WRECKED) -> Dictionary:
    var generator = ShipGenerator.new()
    generator.configure_run_context(BIOME_ID, DIFFICULTY_ID)
    var scene: Node3D = generator.generate_from_seed(
        seed_value,
        ShipBlueprintScript.Size.LIFE_BOAT,
        condition,
    )
    if scene == null or not scene.has_method("get_layout_copy"):
        if scene != null and is_instance_valid(scene):
            scene.free()
        return {}
    var gameplay: Dictionary = scene.gameplay_doc.duplicate(true) \
        if typeof(scene.get("gameplay_doc")) == TYPE_DICTIONARY else {}
    var candidate: Dictionary = {
        "layout": scene.get_layout_copy(),
        "gameplay_slice": gameplay,
    }
    scene.free()
    return candidate


func _has_locked_edge(layout: Dictionary) -> bool:
    var plan_variant: Variant = layout.get("structural_plan", {})
    if not (plan_variant is Dictionary):
        return false
    var edges_variant: Variant = (plan_variant as Dictionary).get("edges", {})
    if not (edges_variant is Dictionary):
        return false
    for edge_variant in (edges_variant as Dictionary).values():
        if edge_variant is Dictionary and str((edge_variant as Dictionary).get("kind", "")).to_upper() == "LOCKED":
            return true
    return false


func _has_locked_edge_between(layout: Dictionary, room_a: String, room_b: String) -> bool:
    var plan_variant: Variant = layout.get("structural_plan", {})
    if not (plan_variant is Dictionary):
        return false
    var edges_variant: Variant = (plan_variant as Dictionary).get("edges", {})
    if not (edges_variant is Dictionary):
        return false
    for edge_variant in (edges_variant as Dictionary).values():
        if not (edge_variant is Dictionary) \
                or str((edge_variant as Dictionary).get("kind", "")).to_upper() != "LOCKED":
            continue
        var rooms_variant: Variant = (edge_variant as Dictionary).get("room_ids", [])
        if not (rooms_variant is Array):
            continue
        var rooms: Array = rooms_variant as Array
        if room_a in rooms and room_b in rooms:
            return true
    return false


func _fail(reason: String) -> void:
    push_error("FIRST RUN CONTRACT FAIL reason=%s" % reason)
    quit(1)
