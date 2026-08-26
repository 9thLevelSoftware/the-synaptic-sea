use derelict_core::procgen::*;

fn request() -> ProcgenRequest {
    ProcgenRequest {
        schema_version: PROCGEN_REQUEST_SCHEMA.into(),
        world_seed: 42,
        site: SiteRequest {
            site_id: "site-a".into(),
            x: 3,
            y: -2,
            archetype_id: "shuttle".into(),
            kit_id: "default".into(),
            intactness_override_bp: None,
            cause_of_loss: None,
            loot_richness_bp: 10_000,
        },
        difficulty_id: "standard".into(),
        player_model: PlayerModel { schema_version: PLAYER_MODEL_SCHEMA.into(), signals: vec![1, -2] },
        requested_domains: vec![Domain::World, Domain::Site, Domain::Gameplay, Domain::Presentation],
        generator_version: 2,
        content_manifest_hash: "a".repeat(64),
        presentation: PresentationRequest { seed: 9, locale: "en-US".into() },
    }
}

#[test]
fn request_round_trips_and_unknown_major_is_rejected() {
    let req = request();
    let json = serde_json::to_string(&req).unwrap();
    assert_eq!(serde_json::from_str::<ProcgenRequest>(&json).unwrap(), req);
    let bad = json.replace(PROCGEN_REQUEST_SCHEMA, "procgen-request-2");
    assert!(matches!(ProcgenRequest::from_json(&bad), Err(ProcgenError::UnknownSchemaMajor(_))));
}

#[test]
fn semantic_hash_is_order_and_presentation_invariant() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let a = generate_bundle(request(), &data).unwrap();
    let mut other = request();
    other.presentation = PresentationRequest { seed: 99, locale: "fr-FR".into() };
    let b = generate_bundle(other, &data).unwrap();
    assert_eq!(a.semantic_hash, b.semantic_hash);
    assert_eq!(a.metrics.pipeline_executions, 1);
}
