use derelict_core::creature::*;
use derelict_core::world::WorldGenerationRequest;

fn context() -> CreatureGenerationContext {
    CreatureGenerationContext {
        request: WorldGenerationRequest {
            world_seed: 7,
            platform_version: 3,
            content_manifest_hash: "a".repeat(64),
            site_id: "site".into(),
            x: 2,
            y: -3,
            archetype_id: "shuttle".into(),
        },
        min_clearance: 1,
        max_footprint_cells: 8,
        threat_cap: 1_000,
        performance_cap: 1_000,
        instance_cap: 32,
    }
}

fn catalogue() -> CreatureCatalogue {
    CreatureCatalogue::bundled().unwrap()
}

#[test]
fn bundled_set_covers_roles_and_is_canonical() {
    let c = catalogue();
    let out = c.generate_set(&context()).unwrap();
    out.validate(&context(), &c).unwrap();
    assert_eq!(out.schema_version, "creature-blueprint-set-2");
    assert_eq!(out.blueprints.len(), 3);
    assert!(out.blueprints.windows(2).all(|w| w[0].id < w[1].id));
    assert_eq!(
        out.blueprints
            .iter()
            .map(|b| b.threat_role)
            .collect::<std::collections::BTreeSet<_>>()
            .len(),
        3
    );
}

#[test]
fn set_is_deterministic_and_identity_sensitive() {
    let c = catalogue();
    let a = c.generate_set(&context()).unwrap();
    assert_eq!(a, c.generate_set(&context()).unwrap());
    let mut changed = context();
    changed.request.x += 1;
    assert_ne!(a, c.generate_set(&changed).unwrap());
    changed = context();
    changed.request.content_manifest_hash = "b".repeat(64);
    assert_ne!(a, c.generate_set(&changed).unwrap());
}

#[test]
fn invalid_caps_and_missing_role_fail_closed() {
    let c = catalogue();
    let mut bad = context();
    bad.threat_cap = 1;
    assert_eq!(
        c.generate_set(&bad),
        Err(CreatureError::NoCompatibleBlueprint)
    );
    let mut missing = c.clone();
    missing
        .fallbacks
        .retain(|b| b.threat_role != ThreatRole::Scout);
    assert_eq!(
        missing.generate_set(&context()),
        Err(CreatureError::NoCompatibleBlueprint)
    );
}

#[test]
fn tampering_and_unknown_fields_are_rejected() {
    let c = catalogue();
    let mut out = c.generate_set(&context()).unwrap();
    out.blueprints[0].id.push_str("_tampered");
    assert!(out.validate(&context(), &c).is_err());
    let mut json = serde_json::to_string(&c.generate_set(&context()).unwrap()).unwrap();
    json.insert(json.len() - 1, ',');
    json.push_str("\"extra\":1}");
    assert!(serde_json::from_str::<CreatureBlueprintSetOutcome>(&json).is_err());
}

#[test]
fn high_seed_bits_are_replayed_without_narrowing() {
    let c = catalogue();
    let mut high = context();
    high.request.world_seed = 9_007_199_254_740_000;
    let out = c.generate_set(&high).unwrap();
    out.validate(&high, &c).unwrap();
}
