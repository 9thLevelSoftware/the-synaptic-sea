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

#[test]
fn contracts_validate_actions_domains_and_bundle_unknown_fields() {
    let mut duplicate = request();
    duplicate.requested_domains.push(Domain::Site);
    assert!(duplicate.validate().is_err());
    let proposal = AdaptiveProposal { schema_version: ADAPTIVE_PROPOSAL_SCHEMA.into(), score: 1, rationale_codes: vec!["pace".into()], confidence_bp: 10_000, rule_model_version: "rules-1".into(), action: AdaptiveAction::SelectCandidate { candidate_id: "c1".into() } };
    proposal.validate().unwrap();
    let data = derelict_core::GenData::default_bundle().unwrap();
    let bundle = generate_bundle(request(), &data).unwrap();
    let mut json = serde_json::to_value(&bundle).unwrap();
    json["site_ir"]["ship"]["unexpected"] = true.into();
    assert!(ProcgenBundle::from_json(&serde_json::to_string(&json).unwrap()).is_err());
}

#[test]
fn migration_helpers_do_not_generate_again_and_json_key_order_is_irrelevant() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let mut count = 0;
    let bundle = generate_bundle_with_pipeline(request(), &data, || { count += 1; Ok(derelict_core::generate_ship_timed(42, &derelict_core::GenParams::new("shuttle"), &data).unwrap()) }).unwrap();
    assert_eq!(count, 1);
    migration_layout(&bundle).unwrap(); migration_gameplay(&bundle).unwrap(); assert_eq!(count, 1);
    let a = serde_json::json!({"b": 2, "a": {"d": 4, "c": 3}});
    let b = serde_json::json!({"a": {"c": 3, "d": 4}, "b": 2});
    assert_eq!(canonical_json_hash(&a).unwrap(), canonical_json_hash(&b).unwrap());
}

#[test]
fn every_public_schema_is_json_and_closed_at_root() {
    let names = ["procgen-request-1", "procgen-bundle-1", "world-ir-1", "site-ir-1", "gameplay-ir-1", "presentation-ir-1", "generation-trace-1", "adaptive-proposal-1", "player-model-1", "procgen-failure-1"];
    for name in names {
        let path = format!("{}/../../schemas/{name}.schema.json", env!("CARGO_MANIFEST_DIR"));
        let value: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        assert_eq!(value["additionalProperties"], false, "{name}");
        assert!(value["required"].as_array().map_or(false, |r| !r.is_empty()), "{name}");
    }
}
