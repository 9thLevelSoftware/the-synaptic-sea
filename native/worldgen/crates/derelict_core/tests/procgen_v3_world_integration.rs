//! Task 6 B2 contract matrix: platform-v3 world generation and structural-v2
//! ship integration.  These tests intentionally exercise the public boundary
//! rather than private helpers; they may remain RED until the B2 implementation
//! lands.

use derelict_core::lifecycle::{
    AdapterSchemas, GeneratorManifest, LifecycleEvent, LifecycleResult,
    PROCGEN_GENERATOR_MANIFEST_SCHEMA,
};
use derelict_core::manifest::{
    ExportSchemas, PROCGEN_BUNDLE_SCHEMA_V3, PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3, WORLD_IR_SCHEMA_V2,
};
use derelict_core::procgen::{
    generate_bundle, semantic_hash, Domain, PlayerModel, PresentationRequest, ProcgenBundle,
    ProcgenError, ProcgenRequest, SiteRequest, PLAYER_MODEL_SCHEMA, PROCGEN_REQUEST_SCHEMA,
};
use derelict_core::world::{
    derive_site_seed_v3, generate_world, WorldGenerationRequest, MAX_PUBLIC_SEED,
    PROCGEN_GENERATOR_VERSION,
};
use derelict_core::{GenData, GENERATOR_VERSION};
use serde_json::{json, Value};

const CONTENT_HASH: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

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
        generator_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: CONTENT_HASH.into(),
        presentation: PresentationRequest {
            seed: 9,
            locale: "en-US".into(),
        },
    }
}

fn world_request(req: &ProcgenRequest) -> WorldGenerationRequest {
    WorldGenerationRequest {
        world_seed: req.world_seed,
        platform_version: req.generator_version,
        content_manifest_hash: req.content_manifest_hash.clone(),
        site_id: req.site.site_id.clone(),
        x: req.site.x,
        y: req.site.y,
        archetype_id: req.site.archetype_id.clone(),
    }
}

fn with_json_mutation<T: serde::Serialize>(value: &T, f: impl FnOnce(&mut Value)) -> String {
    let mut value = serde_json::to_value(value).unwrap();
    f(&mut value);
    serde_json::to_string(&value).unwrap()
}

fn public_schema(name: &str) -> Value {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../schemas")
        .join(format!("{name}.schema.json"));
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
}

#[test]
fn platform_v3_request_envelope_and_seed_bounds_are_strict() {
    let req = request();
    assert_eq!(req.generator_version, 3);
    assert_eq!(req.schema_version, PROCGEN_REQUEST_SCHEMA);
    assert_eq!(req.content_manifest_hash.len(), 64);
    assert!(req.validate().is_ok(), "v3 request should be admissible");
    assert_eq!(
        ExportSchemas::platform_v3().procgen_request,
        PROCGEN_REQUEST_SCHEMA
    );

    for schema in [
        "procgen-request-2",
        "procgen-request-3",
        "procgen-request-9",
    ] {
        let json = with_json_mutation(&req, |v| v["schema_version"] = schema.into());
        assert!(
            ProcgenRequest::from_json(&json).is_err(),
            "accepted {schema}"
        );
    }
    let mut different_site = req.clone();
    different_site.site.site_id = "site-b".into();
    assert!(ProcgenRequest::from_json(&serde_json::to_string(&different_site).unwrap()).is_ok());
    let over = with_json_mutation(&req, |v| v["world_seed"] = (MAX_PUBLIC_SEED + 1).into());
    assert!(
        ProcgenRequest::from_json(&over).is_err(),
        "accepted 53-bit overflow"
    );
    let unknown = with_json_mutation(&req, |v| v["site"]["unknown"] = true.into());
    assert!(
        ProcgenRequest::from_json(&unknown).is_err(),
        "accepted unknown nested field"
    );
}

#[test]
fn world_is_complete_identity_bound_and_site_seeded() {
    let req = request();
    let outcome = generate_world(&world_request(&req)).unwrap();
    let world = outcome.world_ir;
    assert_eq!(world.schema_version, WORLD_IR_SCHEMA_V2);
    assert_eq!(world.world_seed, req.world_seed);
    assert_eq!(world.site_id, req.site.site_id);
    assert_eq!((world.x, world.y), (req.site.x, req.site.y));
    assert_eq!(world.archetype_id, req.site.archetype_id);
    assert_eq!(world.site_seed, world.markers[0].site_seed);
    assert_ne!(world.site_seed, world.world_seed);
    assert_eq!(world.markers.iter().filter(|m| m.selected).count(), 1);
    assert_eq!(
        world.extraction.path,
        vec!["marker:0", "anchor:hub", "anchor:extraction"]
    );

    let expected = derive_site_seed_v3(&derelict_core::WorldKey {
        world_seed: req.world_seed,
        platform_version: 3,
        content_manifest_hash: req.content_manifest_hash.clone(),
        site_id: req.site.site_id.clone(),
        x: req.site.x,
        y: req.site.y,
        domain: "site".into(),
        channel: "site.structural".into(),
        sub_index: 0,
    })
    .unwrap();
    assert_eq!(world.site_seed, expected);
}

#[test]
fn complete_bundle_embeds_public_world_and_runs_structural_pipeline_once() {
    let req = request();
    let expected_outcome = generate_world(&world_request(&req)).unwrap();
    let expected_world = expected_outcome.world_ir;
    let bundle = generate_bundle(req.clone(), &GenData::default_bundle().unwrap()).unwrap();
    assert_eq!(bundle.schema_version, PROCGEN_BUNDLE_SCHEMA_V3);
    assert_eq!(bundle.version.generator_version, 3);
    assert_eq!(bundle.version.export_schemas, ExportSchemas::platform_v3());
    assert_eq!(
        serde_json::to_value(&bundle.world_ir).unwrap(),
        serde_json::to_value(&expected_world).unwrap()
    );
    assert_eq!(bundle.metrics.pipeline_executions, 1);
    assert_eq!(bundle.site_ir.ship.generator_version, GENERATOR_VERSION);
    assert_eq!(bundle.site_ir.ship.seed, expected_world.site_seed);
    for decision in &expected_outcome.candidate_decisions {
        assert!(
            bundle.trace.candidate_decisions.contains(decision),
            "world decision {decision} was not propagated"
        );
    }
    for repair in &expected_outcome.repairs {
        assert!(
            bundle.trace.repairs.contains(repair),
            "world repair {repair} was not propagated"
        );
    }
    assert_eq!(
        bundle.trace.fallback.as_deref(),
        expected_outcome.fallback.as_deref()
    );
}

#[test]
fn world_candidate_repair_fallback_trace_is_deterministic_and_propagated() {
    let req = world_request(&request());
    let a = generate_world(&req).unwrap();
    let b = generate_world(&req).unwrap();
    assert_eq!(a, b);
    assert!(!a.candidate_decisions.is_empty());
    assert!(a.candidate_decisions.iter().all(|code| !code.is_empty()));
    assert!(a.repairs.len() <= 1);
    assert!(a.fallback.as_deref().is_none_or(|id| !id.is_empty()));
    assert!(a
        .world_ir
        .validate_for_request(&req, &derelict_core::world::WorldRules::bundled().unwrap())
        .is_ok());
}

#[test]
fn semantic_hash_covers_expanded_world_but_excludes_presentation() {
    let data = GenData::default_bundle().unwrap();
    let a = generate_bundle(request(), &data).unwrap();
    let mut presentation = request();
    presentation.presentation = PresentationRequest {
        seed: 99,
        locale: "fr-FR".into(),
    };
    let b = generate_bundle(presentation, &data).unwrap();
    assert_eq!(a.world_ir, b.world_ir);
    assert_eq!(a.site_ir, b.site_ir);
    assert_eq!(a.gameplay_ir, b.gameplay_ir);
    assert_eq!(a.semantic_hash, b.semantic_hash);
    assert_eq!(a.semantic_hash, semantic_hash(&a).unwrap());

    let mut changed = a.clone();
    changed.world_ir.world_seed ^= 1;
    assert_ne!(semantic_hash(&a).unwrap(), semantic_hash(&changed).unwrap());
}

#[test]
fn requested_domain_order_and_locale_do_not_change_world_or_mechanics() {
    let data = GenData::default_bundle().unwrap();
    let mut reordered = request();
    reordered.requested_domains.reverse();
    reordered.presentation.locale = "de-DE".into();
    reordered.presentation.seed = 777;
    let a = generate_bundle(request(), &data).unwrap();
    let b = generate_bundle(reordered, &data).unwrap();
    assert_eq!(a.world_ir, b.world_ir);
    assert_eq!(a.site_ir, b.site_ir);
    assert_eq!(a.gameplay_ir, b.gameplay_ir);
    assert_eq!(a.semantic_hash, b.semantic_hash);
    assert_ne!(a.presentation_ir.locale, b.presentation_ir.locale);
    assert_ne!(a.presentation_ir.seed, b.presentation_ir.seed);
}

#[test]
fn expanded_nested_documents_reject_unknown_fields_and_schema_substitution() {
    let data = GenData::default_bundle().unwrap();
    let bundle = generate_bundle(request(), &data).unwrap();
    let bundle_schema = public_schema(PROCGEN_BUNDLE_SCHEMA_V3);
    let bundle_validator = jsonschema::validator_for(&bundle_schema).unwrap();
    let bundle_value = serde_json::to_value(&bundle).unwrap();
    assert!(bundle_validator.is_valid(&bundle_value));
    for schema in ["procgen-bundle-1", "procgen-bundle-2", "procgen-bundle-9"] {
        let json = with_json_mutation(&bundle, |v| v["schema_version"] = schema.into());
        assert!(
            ProcgenBundle::from_json(&json).is_err(),
            "accepted {schema}"
        );
    }
    for schema in ["world-ir-1", "world-ir-3", "world-ir-9"] {
        let json = with_json_mutation(&bundle, |v| v["world_ir"]["schema_version"] = schema.into());
        let value: Value = serde_json::from_str(&json).unwrap();
        assert!(
            ProcgenBundle::from_json(&json).is_err(),
            "accepted {schema}"
        );
        assert!(
            !bundle_validator.is_valid(&value),
            "bundle schema accepted nested {schema}"
        );
    }
    let mut missing_world_schema = bundle_value.clone();
    missing_world_schema["world_ir"]
        .as_object_mut()
        .unwrap()
        .remove("schema_version");
    assert!(!bundle_validator.is_valid(&missing_world_schema));
    let mut stray_root_world_field = bundle_value.clone();
    stray_root_world_field["site_seed"] = json!(1);
    assert!(!bundle_validator.is_valid(&stray_root_world_field));
    let unknown_world = with_json_mutation(&bundle, |v| v["world_ir"]["unknown"] = true.into());
    assert!(ProcgenBundle::from_json(&unknown_world).is_err());
    let unknown_trace = with_json_mutation(&bundle, |v| v["trace"]["unknown"] = true.into());
    assert!(ProcgenBundle::from_json(&unknown_trace).is_err());
    let world_json = with_json_mutation(&bundle.world_ir, |v| v["unknown"] = true.into());
    assert!(serde_json::from_str::<derelict_core::procgen::WorldIR>(&world_json).is_err());
    let world_schema = public_schema(WORLD_IR_SCHEMA_V2);
    let world_validator = jsonschema::validator_for(&world_schema).unwrap();
    assert!(world_validator.is_valid(&serde_json::to_value(&bundle.world_ir).unwrap()));
}

#[test]
fn lifecycle_result_and_generator_manifest_are_platform_v3_contracts() {
    let data = GenData::default_bundle().unwrap();
    let bundle = generate_bundle(request(), &data).unwrap();
    let result =
        LifecycleResult::completed(Some(1), bundle.clone(), vec![LifecycleEvent::Completed]);
    assert_eq!(result.schema_version, PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3);
    assert!(result.validate().is_ok());
    let json = serde_json::to_string(&result).unwrap();
    assert!(LifecycleResult::from_json(&json).is_ok());
    let lifecycle_schema = public_schema(PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3);
    let lifecycle_validator = jsonschema::validator_for(&lifecycle_schema).unwrap();
    let lifecycle_value: Value = serde_json::from_str(&json).unwrap();
    assert!(lifecycle_validator.is_valid(&lifecycle_value));
    for schema in [
        "procgen-lifecycle-result-1",
        "procgen-lifecycle-result-2",
        "procgen-lifecycle-result-9",
    ] {
        let substituted = json.replace(PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3, schema);
        assert!(
            LifecycleResult::from_json(&substituted).is_err(),
            "accepted {schema}"
        );
    }
    let unknown = with_json_mutation(&result, |v| {
        v["bundle"]["world_ir"]["unknown"] = true.into()
    });
    assert!(LifecycleResult::from_json(&unknown).is_err());
    for schema in ["world-ir-1", "world-ir-3", "world-ir-9"] {
        let mut nested = lifecycle_value.clone();
        nested["bundle"]["world_ir"]["schema_version"] = schema.into();
        assert!(
            !lifecycle_validator.is_valid(&nested),
            "lifecycle schema accepted nested {schema}"
        );
    }
    let mut lifecycle_stray_root = lifecycle_value.clone();
    lifecycle_stray_root["world_seed"] = json!(42);
    assert!(!lifecycle_validator.is_valid(&lifecycle_stray_root));

    let manifest = GeneratorManifest {
        schema_version: PROCGEN_GENERATOR_MANIFEST_SCHEMA.into(),
        rust_source_commit: "a".repeat(40),
        generator_version: 3,
        content_manifest_hash: CONTENT_HASH.into(),
        export_schemas: ExportSchemas::platform_v3(),
        adapter_schemas: AdapterSchemas {
            lifecycle_result: PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3.into(),
            capabilities: "procgen-capabilities-1".into(),
            generator_manifest: PROCGEN_GENERATOR_MANIFEST_SCHEMA.into(),
        },
        target: "native".into(),
        dirty_development: false,
    };
    assert!(manifest.validate().is_ok());
    let manifest_unknown =
        with_json_mutation(&manifest, |v| v["export_schemas"]["unknown"] = true.into());
    assert!(GeneratorManifest::from_json(&manifest_unknown).is_err());
}

#[test]
fn invalid_identity_and_version_substitutions_fail_closed() {
    let req = request();
    for (field, value) in [
        ("generator_version", json!(2)),
        ("content_manifest_hash", json!("B".repeat(64))),
    ] {
        let json = with_json_mutation(&req, |v| {
            if field == "site_id" {
                v["site"][field] = value.clone();
            } else {
                v[field] = value.clone();
            }
        });
        assert!(
            ProcgenRequest::from_json(&json).is_err(),
            "accepted mutation {field}"
        );
    }
    let mut key = world_request(&req);
    key.platform_version = 2;
    assert!(generate_world(&key).is_err());
    key.platform_version = 3;
    key.world_seed = MAX_PUBLIC_SEED + 1;
    assert!(generate_world(&key).is_err());

    let bundle = generate_bundle(req, &GenData::default_bundle().unwrap()).unwrap();
    let mismatched = with_json_mutation(&bundle, |v| {
        v["request"]["site"]["site_id"] = "other".into()
    });
    assert!(ProcgenBundle::from_json(&mismatched).is_err());
}

#[allow(dead_code)]
fn _error_shape_is_publicly_stable(error: ProcgenError) -> bool {
    matches!(
        error,
        ProcgenError::InvalidRequest(_) | ProcgenError::UnknownSchemaMajor(_)
    )
}
