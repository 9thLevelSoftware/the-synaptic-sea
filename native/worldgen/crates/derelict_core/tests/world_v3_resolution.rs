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
    out.world_ir.validate_for_request(&req, &rules).unwrap();
}

#[test]
fn bundled_generation_is_deterministic() {
    let req = request();
    assert_eq!(generate_world(&req).unwrap(), generate_world(&req).unwrap());
}

#[test]
fn fallback_handles_selected_site_id_matching_neighbor_shape() {
    let mut req = request();
    req.site_id = "site:3:6".into();
    let rules = WorldRules::bundled().unwrap();
    let fallback = WorldFallback::bundled().unwrap();
    let mut candidate = generate_candidate(&req, &rules).unwrap();
    candidate.markers[1].x += 1;
    let out = resolve_world(&req, candidate, &rules, &fallback).unwrap();
    assert_eq!(out.world_ir.markers.len(), 9);
    assert_eq!(out.world_ir.markers[0].site_id, req.site_id);
    out.world_ir.validate_for_request(&req, &rules).unwrap();
}
