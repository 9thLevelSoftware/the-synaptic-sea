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
        player_model: PlayerModel {
            schema_version: PLAYER_MODEL_SCHEMA.into(),
            signals: vec![1, -2],
        },
        requested_domains: vec![
            Domain::World,
            Domain::Site,
            Domain::Gameplay,
            Domain::Presentation,
        ],
        generator_version: 2,
        content_manifest_hash: "a".repeat(64),
        presentation: PresentationRequest {
            seed: 9,
            locale: "en-US".into(),
        },
    }
}

#[test]
fn request_round_trips_and_unknown_major_is_rejected() {
    let req = request();
    let json = serde_json::to_string(&req).unwrap();
    assert_eq!(serde_json::from_str::<ProcgenRequest>(&json).unwrap(), req);
    let bad = json.replace(PROCGEN_REQUEST_SCHEMA, "procgen-request-2");
    assert!(matches!(
        ProcgenRequest::from_json(&bad),
        Err(ProcgenError::UnknownSchemaMajor(_))
    ));
    let mut invalid = serde_json::to_value(req).unwrap();
    invalid["site"]["loot_richness_bp"] = 30_001.into();
    assert!(ProcgenRequest::from_json(&serde_json::to_string(&invalid).unwrap()).is_err());
    invalid["site"]["loot_richness_bp"] = 1.into();
    invalid["presentation"]["locale"] = "english".into();
    assert!(ProcgenRequest::from_json(&serde_json::to_string(&invalid).unwrap()).is_err());
}

#[test]
fn semantic_hash_is_order_and_presentation_invariant() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let a = generate_bundle(request(), &data).unwrap();
    let mut other = request();
    other.presentation = PresentationRequest {
        seed: 99,
        locale: "fr-FR".into(),
    };
    let b = generate_bundle(other, &data).unwrap();
    assert_eq!(a.semantic_hash, b.semantic_hash);
    assert_eq!(a.metrics.pipeline_executions, 1);
    assert!(a.trace.repairs.is_empty() && a.trace.fallback.is_none());
    for (index, event) in a
        .trace
        .candidate_decisions
        .iter()
        .enumerate()
        .filter(|(_, event)| event.starts_with("considered:"))
    {
        let key = event.strip_prefix("considered:").unwrap();
        let dispositions: Vec<_> = a.trace.candidate_decisions[index + 1..]
            .iter()
            .filter(|later| {
                later.ends_with(key)
                    && (later.starts_with("selected:") || later.starts_with("rejected:"))
            })
            .collect();
        assert_eq!(dispositions.len(), 1, "{event} => {dispositions:?}");
    }
}

#[test]
fn contracts_validate_actions_domains_and_bundle_unknown_fields() {
    let mut duplicate = request();
    duplicate.requested_domains.push(Domain::Site);
    assert!(duplicate.validate().is_err());
    let proposal = AdaptiveProposal {
        schema_version: ADAPTIVE_PROPOSAL_SCHEMA.into(),
        score: 1,
        rationale_codes: vec!["pace".into()],
        confidence_bp: 10_000,
        rule_model_version: "rules-1".into(),
        action: AdaptiveAction::SelectCandidate {
            candidate_id: "c1".into(),
        },
    };
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
    let bundle =
        generate_bundle_with_pipeline(request(), &data, || {
            count += 1;
            Ok(derelict_core::generate_ship_timed(
                42,
                &derelict_core::GenParams::new("shuttle"),
                &data,
            )
            .unwrap())
        })
        .unwrap();
    assert_eq!(count, 1);
    migration_layout(&bundle).unwrap();
    migration_gameplay(&bundle).unwrap();
    assert_eq!(count, 1);
    let a = serde_json::json!({"b": 2, "a": {"d": 4, "c": 3}});
    let b = serde_json::json!({"a": {"c": 3, "d": 4}, "b": 2});
    assert_eq!(
        canonical_json_hash(&a).unwrap(),
        canonical_json_hash(&b).unwrap()
    );
}

#[test]
fn every_public_schema_is_json_and_closed_at_root() {
    let names = [
        "procgen-request-1",
        "procgen-bundle-1",
        "world-ir-1",
        "site-ir-1",
        "gameplay-ir-1",
        "presentation-ir-1",
        "generation-trace-1",
        "generation-metrics-1",
        "adaptive-proposal-1",
        "player-model-1",
        "procgen-failure-1",
    ];
    for name in names {
        let path = format!(
            "{}/../../schemas/{name}.schema.json",
            env!("CARGO_MANIFEST_DIR")
        );
        let value: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap();
        assert_eq!(value["additionalProperties"], false, "{name}");
        assert!(
            value["required"].as_array().is_some_and(|r| !r.is_empty()),
            "{name}"
        );
    }
}

#[test]
fn embedded_request_constraints_match_rust_and_bundle_schema() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let bundle = generate_bundle(request(), &data).unwrap();
    let schema: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(format!(
            "{}/../../schemas/procgen-bundle-1.schema.json",
            env!("CARGO_MANIFEST_DIR")
        ))
        .unwrap(),
    )
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    let mutations = [
        ("schema_version", serde_json::json!("procgen-request-2")),
        (
            "player_model.schema_version",
            serde_json::json!("player-model-2"),
        ),
        ("generator_version", serde_json::json!(3)),
        ("content_manifest_hash", serde_json::json!("bad")),
        ("site.site_id", serde_json::json!("")),
        ("site.archetype_id", serde_json::json!("")),
        ("site.kit_id", serde_json::json!("")),
        ("difficulty_id", serde_json::json!("")),
        ("site.intactness_override_bp", serde_json::json!(10001)),
        ("site.loot_richness_bp", serde_json::json!(30001)),
        ("requested_domains", serde_json::json!([])),
        ("requested_domains", serde_json::json!(["world", "world"])),
        ("presentation.locale", serde_json::json!("english")),
    ];
    for (path, replacement) in mutations {
        let mut value = serde_json::to_value(&bundle).unwrap();
        let mut cursor = &mut value["request"];
        for segment in path.split('.') {
            cursor = cursor.get_mut(segment).unwrap();
        }
        *cursor = replacement;
        assert!(
            ProcgenBundle::from_json(&serde_json::to_string(&value).unwrap()).is_err(),
            "Rust accepted {path}"
        );
        assert!(
            validator.iter_errors(&value).next().is_some(),
            "schema accepted {path}"
        );
    }
}

#[test]
fn embedded_gameplay_constraints_match_standalone_and_rust() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let bundle = generate_bundle(request(), &data).unwrap();
    let schema: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(format!(
            "{}/../../schemas/procgen-bundle-1.schema.json",
            env!("CARGO_MANIFEST_DIR")
        ))
        .unwrap(),
    )
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    for field in [
        "schema_version",
        "document_kind",
        "program_id",
        "start_room",
        "goal_room",
        "summary",
    ] {
        let mut value = serde_json::to_value(&bundle).unwrap();
        value["gameplay_ir"]["legacy_slice"][field] = "".into();
        assert!(
            ProcgenBundle::from_json(&serde_json::to_string(&value).unwrap()).is_err(),
            "Rust accepted gameplay {field}"
        );
        assert!(
            validator.iter_errors(&value).next().is_some(),
            "schema accepted gameplay {field}"
        );
    }
}

#[test]
fn adaptive_empty_targets_fail_rust_and_schema() {
    let schema: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(format!(
            "{}/../../schemas/adaptive-proposal-1.schema.json",
            env!("CARGO_MANIFEST_DIR")
        ))
        .unwrap(),
    )
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    for action in [
        AdaptiveAction::SelectCandidate {
            candidate_id: String::new(),
        },
        AdaptiveAction::AdjustEncounter {
            encounter_id: String::new(),
            pacing_delta: 1,
        },
    ] {
        let proposal = AdaptiveProposal {
            schema_version: ADAPTIVE_PROPOSAL_SCHEMA.into(),
            score: 0,
            rationale_codes: vec!["r".into()],
            confidence_bp: 1,
            rule_model_version: "v".into(),
            action,
        };
        let value = serde_json::to_value(&proposal).unwrap();
        assert!(AdaptiveProposal::from_json(&serde_json::to_string(&value).unwrap()).is_err());
        assert!(validator.iter_errors(&value).next().is_some());
    }
}

#[test]
fn injected_invalid_ship_fails_closed_before_bundle() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let mut report =
        derelict_core::generate_ship_timed(42, &derelict_core::GenParams::new("shuttle"), &data)
            .unwrap();
    report.ship.archetype_id = "wrong-archetype".into();
    let result = generate_bundle_with_pipeline(request(), &data, || Ok(report));
    assert!(matches!(
        result,
        Err(ProcgenFailure {
            code: ProcgenFailureCode::ValidationFailure,
            ..
        })
    ));
}

#[test]
fn injected_valid_ship_with_invalid_bundle_trace_fails_at_bundle_validation() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let mut report =
        derelict_core::generate_ship_timed(42, &derelict_core::GenParams::new("shuttle"), &data)
            .unwrap();
    report.candidate_decisions = vec!["candidate".into(); 4097];
    let result = generate_bundle_with_pipeline(request(), &data, || Ok(report));
    assert!(matches!(
        result,
        Err(ProcgenFailure {
            code: ProcgenFailureCode::ValidationFailure,
            ..
        })
    ));
    if let Err(failure) = result {
        assert_eq!(failure.stage, "bundle");
    }
}

#[test]
fn draft_schema_accepts_serialized_bundle_and_all_actions() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let bundle = generate_bundle(request(), &data).unwrap();
    let schema: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(format!(
            "{}/../../schemas/procgen-bundle-1.schema.json",
            env!("CARGO_MANIFEST_DIR")
        ))
        .unwrap(),
    )
    .unwrap();
    let compiled = jsonschema::validator_for(&schema).unwrap();
    let bundle_value = serde_json::to_value(&bundle).unwrap();
    let errors: Vec<_> = compiled
        .iter_errors(&bundle_value)
        .map(|e| e.to_string())
        .collect();
    assert!(errors.is_empty(), "{errors:?}");
    let round_trip =
        ProcgenBundle::from_json(&serde_json::to_string(&bundle_value).unwrap()).unwrap();
    assert_eq!(round_trip, bundle);
    for action in [
        AdaptiveAction::NoOp,
        AdaptiveAction::SelectCandidate {
            candidate_id: "c".into(),
        },
        AdaptiveAction::AdjustEncounter {
            encounter_id: "e".into(),
            pacing_delta: -1,
        },
    ] {
        let proposal = AdaptiveProposal {
            schema_version: ADAPTIVE_PROPOSAL_SCHEMA.into(),
            score: 0,
            rationale_codes: vec!["r".into()],
            confidence_bp: 1,
            rule_model_version: "v".into(),
            action,
        };
        let schema: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(format!(
                "{}/../../schemas/adaptive-proposal-1.schema.json",
                env!("CARGO_MANIFEST_DIR")
            ))
            .unwrap(),
        )
        .unwrap();
        let pv = serde_json::to_value(proposal).unwrap();
        let av = jsonschema::validator_for(&schema).unwrap();
        let es: Vec<_> = av.iter_errors(&pv).map(|e| e.to_string()).collect();
        assert!(es.is_empty(), "{pv} {es:?}");
    }
    for action_key in ["select_candidate", "adjust_encounter"] {
        let mut bad = serde_json::to_value(AdaptiveProposal {
            schema_version: ADAPTIVE_PROPOSAL_SCHEMA.into(),
            score: 0,
            rationale_codes: vec!["r".into()],
            confidence_bp: 1,
            rule_model_version: "v".into(),
            action: AdaptiveAction::SelectCandidate {
                candidate_id: "c".into(),
            },
        })
        .unwrap();
        if action_key == "select_candidate" {
            bad["action"]["select_candidate"]["unexpected"] = true.into();
        } else {
            bad["action"] = serde_json::json!({"adjust_encounter":{"encounter_id":"e","pacing_delta":1,"unexpected":true}});
        }
        assert!(AdaptiveProposal::from_json(&serde_json::to_string(&bad).unwrap()).is_err());
        let schema: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(format!(
                "{}/../../schemas/adaptive-proposal-1.schema.json",
                env!("CARGO_MANIFEST_DIR")
            ))
            .unwrap(),
        )
        .unwrap();
        assert!(jsonschema::validator_for(&schema)
            .unwrap()
            .iter_errors(&bad)
            .next()
            .is_some());
    }
    let docs = [
        (
            "procgen-request-1",
            serde_json::to_value(&bundle.request).unwrap(),
        ),
        (
            "world-ir-1",
            serde_json::to_value(&bundle.world_ir).unwrap(),
        ),
        ("site-ir-1", serde_json::to_value(&bundle.site_ir).unwrap()),
        (
            "gameplay-ir-1",
            serde_json::to_value(&bundle.gameplay_ir).unwrap(),
        ),
        (
            "presentation-ir-1",
            serde_json::to_value(&bundle.presentation_ir).unwrap(),
        ),
        (
            "generation-trace-1",
            serde_json::to_value(&bundle.trace).unwrap(),
        ),
        (
            "generation-metrics-1",
            serde_json::to_value(&bundle.metrics).unwrap(),
        ),
        (
            "player-model-1",
            serde_json::to_value(&bundle.request.player_model).unwrap(),
        ),
    ];
    for (name, document) in docs {
        let schema: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(format!(
                "{}/../../schemas/{name}.schema.json",
                env!("CARGO_MANIFEST_DIR")
            ))
            .unwrap(),
        )
        .unwrap();
        let validator = jsonschema::validator_for(&schema).unwrap();
        let errors: Vec<_> = validator
            .iter_errors(&document)
            .map(|e| e.to_string())
            .collect();
        assert!(errors.is_empty(), "{name}: {errors:?}");
    }
    let failure_codes = [
        ProcgenFailureCode::InvalidRequest,
        ProcgenFailureCode::UnsupportedSchema,
        ProcgenFailureCode::UnsupportedDomain,
        ProcgenFailureCode::GeneratorContentMismatch,
        ProcgenFailureCode::GenerationFailure,
        ProcgenFailureCode::ValidationFailure,
        ProcgenFailureCode::FallbackFailure,
        ProcgenFailureCode::AdapterFailure,
        ProcgenFailureCode::ManifestFailure,
        ProcgenFailureCode::Capacity,
        ProcgenFailureCode::Overload,
        ProcgenFailureCode::Cancellation,
        ProcgenFailureCode::Timeout,
        ProcgenFailureCode::InternalFailure,
    ];
    let schema: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(format!(
            "{}/../../schemas/procgen-failure-1.schema.json",
            env!("CARGO_MANIFEST_DIR")
        ))
        .unwrap(),
    )
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    for code in failure_codes {
        let failure = ProcgenFailure {
            schema_version: FAILURE_SCHEMA.into(),
            code,
            stage: "stage".into(),
            message: "message".into(),
            retryable: false,
            fallback_id: Some("fallback".into()),
        };
        let value = serde_json::to_value(&failure).unwrap();
        assert!(
            validator.iter_errors(&value).next().is_none(),
            "failure schema rejected {value}"
        );
        assert_eq!(
            ProcgenFailure::from_json(&serde_json::to_string(&value).unwrap()).unwrap(),
            failure
        );
    }
}

#[test]
fn nested_unknown_fields_fail_at_serde_and_schema_boundaries() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let bundle = generate_bundle(request(), &data).unwrap();
    let schema: serde_json::Value = serde_json::from_str(
        &std::fs::read_to_string(format!(
            "{}/../../schemas/procgen-bundle-1.schema.json",
            env!("CARGO_MANIFEST_DIR")
        ))
        .unwrap(),
    )
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    for path in [
        vec!["version", "export_schemas"],
        vec!["site_ir", "ship", "topology", "rooms", "0"],
        vec!["site_ir", "ship", "plan", "placements", "0"],
        vec!["site_ir", "ship", "entities", "0"],
        vec!["gameplay_ir", "legacy_slice", "objectives", "0"],
        vec!["gameplay_ir", "legacy_slice", "loot_containers", "0"],
    ] {
        let mut value = serde_json::to_value(&bundle).unwrap();
        let mut cursor = &mut value;
        for key in &path {
            cursor = if let Ok(index) = key.parse::<usize>() {
                cursor.get_mut(index)
            } else {
                cursor.get_mut(key)
            }
            .unwrap_or_else(|| panic!("missing fixture path {path:?}"));
        }
        cursor
            .as_object_mut()
            .unwrap()
            .insert("unexpected_nested_field".into(), true.into());
        assert!(
            ProcgenBundle::from_json(&serde_json::to_string(&value).unwrap()).is_err(),
            "serde accepted {path:?}"
        );
        assert!(
            validator.iter_errors(&value).next().is_some(),
            "schema accepted {path:?}"
        );
    }
}
