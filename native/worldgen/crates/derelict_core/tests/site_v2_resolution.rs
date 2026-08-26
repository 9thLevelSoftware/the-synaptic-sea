use derelict_core::site::{
    fallback_return_path, generate_site, resolve_site_candidate, validate_site_for_request,
    PropKind,
};
use derelict_core::world::{WorldGenerationRequest, WorldKey, PROCGEN_GENERATOR_VERSION};
use derelict_core::{generate_ship, GenData, GenParams};

fn request(seed: u64) -> WorldGenerationRequest {
    WorldGenerationRequest {
        world_seed: seed,
        platform_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: "a".repeat(64),
        site_id: "site:test".into(),
        x: 4,
        y: -3,
        archetype_id: "shuttle".into(),
    }
}

fn try_fixture_for(
    request: &WorldGenerationRequest,
) -> Result<derelict_core::site::SiteIR, derelict_core::site::SiteError> {
    let key = WorldKey {
        world_seed: request.world_seed,
        platform_version: request.platform_version,
        content_manifest_hash: request.content_manifest_hash.clone(),
        site_id: request.site_id.clone(),
        x: request.x,
        y: request.y,
        domain: "site".into(),
        channel: "site.structural".into(),
        sub_index: 0,
    };
    let ship = generate_ship(
        key.seed().unwrap(),
        &GenParams::new(&request.archetype_id),
        &GenData::default_bundle().unwrap(),
    )
    .unwrap();
    generate_site(ship, request).map(|outcome| outcome.site)
}

fn survey_fixture() -> (WorldGenerationRequest, derelict_core::site::SiteIR) {
    for seed in 0..192 {
        let req = request(seed);
        let Ok(site) = try_fixture_for(&req) else { continue };
        if site.mission_graph.gates.is_empty() {
            validate_site_for_request(&site, &req).unwrap();
            return (req, site);
        }
    }
    panic!("no ungated survey fixture in bounded seed range");
}

#[test]
fn valid_candidate_passes_through_without_repairs() {
    let (req, site) = survey_fixture();
    let expected = site.clone();
    let outcome = resolve_site_candidate(site, &req).unwrap();
    assert_eq!(outcome.site, expected);
    assert!(outcome.trace.repairs.is_empty());
    assert!(outcome.trace.fallback.is_none());
    validate_site_for_request(&outcome.site, &req).unwrap();
}

#[test]
fn overlapping_required_prop_is_relocated_with_one_named_repair() {
    let mut repaired = None;
    'seeds: for seed in 0..192 {
        let req = request(seed);
        let Ok(site) = try_fixture_for(&req) else { continue };
        if site.mission_graph.gates.is_empty() {
            for index in 0..site.functional_props.len() {
                let mut malformed = site.clone();
                let other = (index + 1) % site.functional_props.len();
                malformed.functional_props[index].anchor = site.functional_props[other].anchor;
                if let Ok(outcome) = resolve_site_candidate(malformed, &req) {
                    if outcome.trace.repairs == ["relocate_required_prop"]
                        && outcome.trace.fallback.is_none()
                    {
                        repaired = Some((req, outcome));
                        break 'seeds;
                    }
                }
            }
        }
    }
    let (req, outcome) = repaired.expect("no repairable overlapping prop fixture");
    assert_eq!(outcome.trace.repairs, vec!["relocate_required_prop"]);
    assert!(outcome.trace.fallback.is_none());
    validate_site_for_request(&outcome.site, &req).unwrap();
}

#[test]
fn invalid_gate_navigation_binding_is_repaired_with_one_named_repair() {
    let mut repaired = None;
    'seeds: for seed in 0..192 {
        let req = request(seed);
        let Ok(site) = try_fixture_for(&req) else { continue };
        for index in 0..site.mission_graph.gates.len() {
            let mut malformed = site.clone();
            malformed.mission_graph.gates[index].navigation_edge = "missing-edge".into();
            if let Ok(outcome) = resolve_site_candidate(malformed, &req) {
                if outcome.trace.repairs == ["replace_gate_binding"] {
                    repaired = Some((req, outcome));
                    break 'seeds;
                }
            }
        }
    }
    let (req, outcome) = repaired.expect("no repairable gated fixture");
    assert_eq!(outcome.trace.repairs, vec!["replace_gate_binding"]);
    assert!(outcome.trace.fallback.is_none());
    validate_site_for_request(&outcome.site, &req).unwrap();
}

#[test]
fn irreparable_candidate_uses_complete_authored_fallback() {
    let (req, mut site) = survey_fixture();
    site.mission_graph.mission_id.clear();
    let expected_path = fallback_return_path(&site);
    let outcome = resolve_site_candidate(site, &req).unwrap();
    assert_eq!(outcome.trace.repairs.len(), 0);
    assert_eq!(outcome.trace.fallback.as_deref(), Some("authored-safe-return"));
    assert_eq!(outcome.site.mission_graph.mission_id, "authored-safe-return");
    assert!(outcome.site.mission_graph.gates.is_empty());
    assert_eq!(fallback_return_path(&outcome.site), expected_path);
    validate_site_for_request(&outcome.site, &req).unwrap();
}

#[test]
fn invalid_request_identity_fails_closed_without_fallback() {
    let (req, site) = survey_fixture();
    let invalid = request(req.world_seed + 1);
    let error = resolve_site_candidate(site, &invalid).unwrap_err();
    assert!(matches!(error, derelict_core::site::SiteError::Invalid(_)));
}

#[test]
fn repair_count_and_trace_are_bounded() {
    let (req, mut site) = survey_fixture();
    let extraction = site
        .functional_props
        .iter()
        .position(|prop| prop.kind == PropKind::ExtractionConsole)
        .unwrap();
    site.functional_props[extraction].anchor = site.functional_props[0].anchor;
    let outcome = resolve_site_candidate(site, &req).unwrap();
    assert!(outcome.trace.repairs.len() <= 2);
    assert!(outcome.trace.candidate_decisions.len() <= 64);
    assert!(outcome.trace.repairs.iter().all(|repair| {
        matches!(repair.as_str(), "relocate_required_prop" | "replace_gate_binding")
    }));
}
