use derelict_core::world::{
    generate_candidate, generate_world, resolve_world, WorldFallback, WorldGenerationRequest,
    WorldRules,
};

fn request() -> WorldGenerationRequest {
    WorldGenerationRequest {
        world_seed: 42,
        platform_version: 3,
        content_manifest_hash: "a".repeat(64),
        site_id: "selected".into(),
        x: 4,
        y: 7,
        archetype_id: "corvette".into(),
    }
}

#[test]
fn valid_candidate_is_selected_without_repair_or_fallback() {
    let req = request();
    let rules = WorldRules::bundled().unwrap();
    let fallback = WorldFallback::bundled().unwrap();
    let out = resolve_world(
        &req,
        generate_candidate(&req, &rules).unwrap(),
        &rules,
        &fallback,
    )
    .unwrap();
    assert!(out.repairs.is_empty());
    assert!(out.fallback.is_none());
    assert_eq!(
        out.candidate_decisions,
        ["considered_candidate", "selected_candidate"]
    );
}

#[test]
fn missing_selected_hub_edge_is_repaired_once() {
    let req = request();
    let rules = WorldRules::bundled().unwrap();
    let fallback = WorldFallback::bundled().unwrap();
    let mut candidate = generate_candidate(&req, &rules).unwrap();
    candidate
        .routes
        .retain(|r| !(r.from == "anchor:hub" && r.to == "marker:0"));
    let out = resolve_world(&req, candidate, &rules, &fallback).unwrap();
    assert_eq!(out.repairs, ["repair_missing_selected_hub_route"]);
    assert!(out.fallback.is_none());
    out.world_ir.validate_for_request(&req, &rules).unwrap();
}

#[test]
fn unrelated_candidate_defect_selects_complete_fallback() {
    let req = request();
    let rules = WorldRules::bundled().unwrap();
    let fallback = WorldFallback::bundled().unwrap();
    let mut candidate = generate_candidate(&req, &rules).unwrap();
    candidate.markers[1].x += 1;
    let out = resolve_world(&req, candidate, &rules, &fallback).unwrap();
    assert_eq!(out.fallback.as_deref(), Some("safe-world-v3"));
    assert!(out.repairs.is_empty());
    assert_eq!(out.world_ir.archetype_id, req.archetype_id);
    assert_eq!(out.world_ir.markers.len(), 9);
    out.validate_with_fallback(&rules, &req, &fallback).unwrap();
}

#[test]
fn bundled_generation_is_deterministic() {
    let req = request();
    assert_eq!(generate_world(&req).unwrap(), generate_world(&req).unwrap());
}

#[test]
fn fallback_handles_selected_site_id_matching_neighbor_shape() {
    let mut req = request();
    req.site_id = "selected:site".into();
    let rules = WorldRules::bundled().unwrap();
    let fallback = WorldFallback::bundled().unwrap();
    let mut candidate = generate_candidate(&req, &rules).unwrap();
    candidate.markers[1].x += 1;
    let out = resolve_world(&req, candidate, &rules, &fallback).unwrap();
    assert_eq!(out.world_ir.markers.len(), 9);
    assert_eq!(out.world_ir.markers[0].site_id, req.site_id);
    out.validate_with_fallback(&rules, &req, &fallback).unwrap();
}

#[test]
fn synthesized_neighbor_site_id_collision_is_rejected() {
    let mut req = request();
    req.site_id = "site:3:6".into();
    assert!(generate_world(&req).is_err());
}

#[test]
fn authored_fallback_rejects_each_independent_mutation() {
    let req = request();
    let rules = WorldRules::bundled().unwrap();
    let fallback = WorldFallback::bundled().unwrap();
    let mut candidate = generate_candidate(&req, &rules).unwrap();
    candidate.markers[1].x += 1;
    let base = resolve_world(&req, candidate, &rules, &fallback).unwrap();
    let mut cases: Vec<(
        &str,
        Box<dyn Fn(&mut derelict_core::world::WorldGenerationOutcome)>,
    )> = vec![
        (
            "neighbor_archetype",
            Box::new(|o| o.world_ir.markers[1].archetype_id = "corvette".into()),
        ),
        (
            "biome",
            Box::new(|o| o.world_ir.biome_fields[0].biome_id = "dead_fleet".into()),
        ),
        (
            "intensity",
            Box::new(|o| o.world_ir.biome_fields[0].intensity_bp ^= 1),
        ),
        (
            "hazard",
            Box::new(|o| o.world_ir.hazard_fields[0].hazard_id = "ion_storm".into()),
        ),
        (
            "severity",
            Box::new(|o| o.world_ir.hazard_fields[0].severity_bp ^= 1),
        ),
        (
            "resource",
            Box::new(|o| o.world_ir.resource_pressures[0].resource_id = "scrap".into()),
        ),
        (
            "pressure",
            Box::new(|o| o.world_ir.resource_pressures[0].pressure_bp ^= 1),
        ),
        (
            "landmark",
            Box::new(|o| o.world_ir.landmarks[0].kind = "wreck".into()),
        ),
        (
            "route_cost",
            Box::new(|o| o.world_ir.routes[0].cost_bp ^= 1),
        ),
        ("coordinate", Box::new(|o| o.world_ir.markers[1].x ^= 1)),
        (
            "site_seed",
            Box::new(|o| o.world_ir.markers[1].site_seed ^= 1),
        ),
        (
            "marker_id",
            Box::new(|o| o.world_ir.markers[1].marker_id = "marker:8".into()),
        ),
        (
            "fallback_label",
            Box::new(|o| o.fallback = Some("other".into())),
        ),
        (
            "trace_bounds",
            Box::new(|o| o.candidate_decisions = vec!["x".into(); 129]),
        ),
        (
            "trace_code",
            Box::new(|o| o.candidate_decisions[0] = "request:secret".into()),
        ),
    ];
    for (name, mutate) in cases.drain(..) {
        let mut altered = base.clone();
        mutate(&mut altered);
        assert!(
            altered
                .validate_with_fallback(&rules, &req, &fallback)
                .is_err(),
            "accepted {name}"
        );
    }
}

#[test]
fn uniform_tampered_candidate_is_not_accepted() {
    let req = request();
    let rules = WorldRules::bundled().unwrap();
    let fallback = WorldFallback::bundled().unwrap();
    let mut candidate = generate_candidate(&req, &rules).unwrap();
    for marker in &mut candidate.markers[1..] {
        marker.archetype_id = "shuttle".into();
    }
    for field in &mut candidate.biome_fields {
        field.biome_id = "abyssal_synaptic_sea".into();
        field.intensity_bp = 5000;
    }
    for field in &mut candidate.hazard_fields {
        field.hazard_id = "none".into();
        field.severity_bp = 1000;
    }
    for field in &mut candidate.resource_pressures {
        field.resource_id = "oxygen".into();
        field.pressure_bp = 5000;
    }
    for edge in &mut candidate.routes {
        edge.cost_bp = fallback.route_cost_bp;
    }
    let out = resolve_world(&req, candidate, &rules, &fallback).unwrap();
    assert_eq!(out.fallback.as_deref(), Some("safe-world-v3"));
}
