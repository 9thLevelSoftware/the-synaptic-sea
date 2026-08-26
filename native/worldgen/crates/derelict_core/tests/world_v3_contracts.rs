use derelict_core::world::{
    derive_site_seed_v3, generate_candidate, WorldFallback, WorldGenerationRequest, WorldIR,
    WorldKey, WorldRules, MAX_PUBLIC_SEED, PROCGEN_GENERATOR_VERSION,
};
use serde_json::Value;
use std::collections::BTreeSet;
use std::sync::Arc;
use std::thread;

fn key() -> WorldKey {
    WorldKey {
        world_seed: 42,
        platform_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: "a".repeat(64),
        site_id: "site".into(),
        x: -1,
        y: 2,
        domain: "world".into(),
        channel: "biome".into(),
        sub_index: 0,
    }
}

fn request(seed: u64, archetype: &str) -> WorldGenerationRequest {
    WorldGenerationRequest {
        world_seed: seed,
        platform_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: "a".repeat(64),
        site_id: "selected".into(),
        x: 4,
        y: 7,
        archetype_id: archetype.into(),
    }
}

fn candidate() -> (WorldGenerationRequest, WorldRules, WorldIR) {
    let rules = WorldRules::bundled().unwrap();
    let req = request(42, "shuttle");
    let world = generate_candidate(&req, &rules).unwrap();
    (req, rules, world)
}

type CandidateMutation = Box<dyn Fn(&mut WorldIR)>;

#[test]
fn full_key_golden_delimiter_safety_and_component_sensitivity() {
    let base = key();
    assert_eq!(base.seed().unwrap(), 7_276_578_952_791_713);
    assert_eq!(derive_site_seed_v3(&base).unwrap(), base.seed().unwrap());
    let mut max = base.clone();
    max.world_seed = MAX_PUBLIC_SEED;
    let derived = max.seed().unwrap();
    assert!(
        derived <= MAX_PUBLIC_SEED,
        "derived seed {derived} exceeded public bound"
    );

    // A delimiter-join implementation would make these tuples ambiguous.
    let mut left = base.clone();
    left.site_id = "ab".into();
    left.domain = "c".into();
    let mut right = base.clone();
    right.site_id = "a".into();
    right.domain = "bc".into();
    assert_ne!(left.seed(), right.seed());

    let mut variants = Vec::new();
    for change in [
        |k: &mut WorldKey| k.world_seed += 1,
        |k: &mut WorldKey| k.content_manifest_hash = "b".repeat(64),
        |k: &mut WorldKey| k.site_id = "other".into(),
        |k: &mut WorldKey| k.x += 1,
        |k: &mut WorldKey| k.y += 1,
        |k: &mut WorldKey| k.domain = "site".into(),
        |k: &mut WorldKey| k.channel = "hazard".into(),
        |k: &mut WorldKey| k.sub_index = 1,
    ] {
        let mut changed = base.clone();
        change(&mut changed);
        variants.push(changed.seed().unwrap());
    }
    assert!(variants.iter().all(|seed| *seed != base.seed().unwrap()));
    let mut negative = base.clone();
    negative.x = 1;
    assert_ne!(base.seed(), negative.seed());

    let malformed = vec![
        (
            "uppercase",
            Box::new(|k: &mut WorldKey| k.content_manifest_hash = "A".repeat(64))
                as Box<dyn Fn(&mut WorldKey)>,
        ),
        (
            "nonhex",
            Box::new(|k: &mut WorldKey| k.content_manifest_hash = "g".repeat(64)),
        ),
        ("empty", Box::new(|k: &mut WorldKey| k.site_id.clear())),
        (
            "overlong",
            Box::new(|k: &mut WorldKey| k.domain = "x".repeat(65)),
        ),
    ];
    for (name, mutate) in malformed {
        let mut malformed = base.clone();
        mutate(&mut malformed);
        assert!(
            malformed.seed().is_err(),
            "identity mutation {name} was accepted"
        );
    }
    let mut overflow = base.clone();
    overflow.world_seed = MAX_PUBLIC_SEED + 1;
    assert!(overflow.seed().is_err());
}

fn add_unknown(value: &mut Value, path: &[&str]) {
    let mut current = value;
    for part in path {
        current = if let Ok(index) = part.parse::<usize>() {
            &mut current[index]
        } else {
            &mut current[*part]
        };
    }
    current
        .as_object_mut()
        .unwrap()
        .insert("unknown_field".into(), Value::from(1));
}

#[test]
fn candidate_and_supporting_documents_are_closed_json() {
    let (_req, rules, world) = candidate();
    let mut paths = vec![vec!["markers", "0"], vec!["routes", "0"]];
    for family in [
        "biome_fields",
        "hazard_fields",
        "resource_pressures",
        "landmarks",
    ] {
        paths.push(vec![family, "0"]);
    }
    paths.extend([vec!["anchors", "0"], vec!["extraction"]]);
    for path in paths {
        let mut value = serde_json::to_value(&world).unwrap();
        add_unknown(&mut value, &path);
        assert!(
            serde_json::from_value::<WorldIR>(value).is_err(),
            "unknown field accepted at {path:?}"
        );
    }
    let bytes = serde_json::to_vec(&world).unwrap();
    let decoded: WorldIR = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(bytes, serde_json::to_vec(&decoded).unwrap());

    let mut rules_value = serde_json::to_value(&rules).unwrap();
    add_unknown(&mut rules_value, &["route_cost_bp"]);
    assert!(serde_json::from_value::<WorldRules>(rules_value).is_err());
    let fallback = WorldFallback::bundled().unwrap();
    let mut fallback_value = serde_json::to_value(&fallback).unwrap();
    fallback_value
        .as_object_mut()
        .unwrap()
        .insert("unknown_field".into(), Value::from(1));
    assert!(serde_json::from_value::<WorldFallback>(fallback_value).is_err());
}

#[test]
fn bounded_corpus_covers_bundled_content_and_preserves_selection() {
    let rules = WorldRules::bundled().unwrap();
    let cap = 4096u64;
    let mut archetypes = BTreeSet::new();
    let mut biomes = BTreeSet::new();
    let mut hazards = BTreeSet::new();
    let mut resources = BTreeSet::new();
    let mut landmarks = BTreeSet::new();
    let mut costs = BTreeSet::new();
    for seed in 0..cap {
        let archetype = &rules.archetypes[(seed as usize) % rules.archetypes.len()];
        let req = request(seed, archetype);
        let world = generate_candidate(&req, &rules).unwrap();
        assert_eq!(world.markers[0].archetype_id, req.archetype_id);
        archetypes.insert(
            world
                .markers
                .iter()
                .map(|m| m.archetype_id.clone())
                .collect::<Vec<_>>(),
        );
        biomes.extend(world.biome_fields.iter().map(|f| f.biome_id.clone()));
        hazards.extend(world.hazard_fields.iter().map(|f| f.hazard_id.clone()));
        resources.extend(
            world
                .resource_pressures
                .iter()
                .map(|f| f.resource_id.clone()),
        );
        landmarks.extend(world.landmarks.iter().map(|f| f.kind.clone()));
        costs.extend(world.routes.iter().map(|r| r.cost_bp));
    }
    assert_eq!(
        archetypes.into_iter().flatten().collect::<BTreeSet<_>>(),
        rules.archetypes.iter().cloned().collect()
    );
    assert_eq!(
        biomes,
        rules.biomes.iter().cloned().collect(),
        "corpus of {cap} seeds missed a biome"
    );
    assert_eq!(
        hazards,
        rules.hazards.iter().cloned().collect(),
        "corpus of {cap} seeds missed a hazard"
    );
    assert_eq!(
        resources,
        rules.resources.iter().cloned().collect(),
        "corpus of {cap} seeds missed a resource"
    );
    assert_eq!(
        landmarks,
        rules.landmarks.iter().cloned().collect(),
        "corpus of {cap} seeds missed a landmark"
    );
    assert!(
        costs.len() >= 2,
        "corpus of {cap} seeds produced fewer than two route costs"
    );
}

#[test]
fn generation_is_call_order_invariant_and_thread_byte_identical() {
    let rules = Arc::new(WorldRules::bundled().unwrap());
    let req = Arc::new(request(4242, "shuttle"));
    let expected = serde_json::to_vec(&generate_candidate(&req, &rules).unwrap()).unwrap();
    let mut handles = Vec::new();
    for _ in 0..8 {
        let rules = Arc::clone(&rules);
        let req = Arc::clone(&req);
        handles.push(thread::spawn(move || {
            let world = generate_candidate(&req, &rules).unwrap();
            let bytes = serde_json::to_vec(&world).unwrap();
            world.validate_for_request(&req, &rules).unwrap();
            assert_eq!(bytes, serde_json::to_vec(&world).unwrap());
            bytes
        }));
    }
    for handle in handles {
        assert_eq!(handle.join().unwrap(), expected);
    }
    let first = generate_candidate(&req, &rules).unwrap();
    let _ = first.validate_with_rules(&rules);
    let second = generate_candidate(&req, &rules).unwrap();
    assert_eq!(
        serde_json::to_vec(&first).unwrap(),
        serde_json::to_vec(&second).unwrap()
    );
}

#[test]
fn malformed_candidate_matrix_rejects_every_named_mutation() {
    let (req, rules, world) = candidate();
    let mut mutations: Vec<(&str, CandidateMutation)> = Vec::new();
    macro_rules! m {
        ($name:expr, $body:expr) => {
            mutations.push(($name, Box::new($body)));
        };
    }
    m!("schema", |w: &mut WorldIR| w.schema_version = "bad".into());
    m!("world_seed", |w: &mut WorldIR| w.world_seed += 1);
    m!("site", |w: &mut WorldIR| w.site_id = "other".into());
    m!("x", |w: &mut WorldIR| w.x += 1);
    m!("y", |w: &mut WorldIR| w.y += 1);
    m!("archetype", |w: &mut WorldIR| w.archetype_id =
        "frigate".into());
    m!("site_seed", |w: &mut WorldIR| w.site_seed ^= 1);
    m!("marker_id", |w: &mut WorldIR| w.markers[1].marker_id =
        "marker:8".into());
    m!("marker_site", |w: &mut WorldIR| w.markers[1].site_id =
        "site:bad".into());
    m!("marker_coord", |w: &mut WorldIR| w.markers[1].x += 1);
    m!("marker_archetype", |w: &mut WorldIR| w.markers[1]
        .archetype_id =
        "shuttle".into());
    m!("marker_seed", |w: &mut WorldIR| w.markers[1].site_seed ^= 1);
    m!("marker_selected", |w: &mut WorldIR| w.markers[1].selected =
        true);
    m!("marker_order", |w: &mut WorldIR| w.markers.swap(0, 1));
    m!("marker_duplicate", |w: &mut WorldIR| w.markers[1]
        .marker_id =
        w.markers[0].marker_id.clone());
    for (family, index) in [
        ("biome_ref", 0),
        ("hazard_ref", 1),
        ("resource_ref", 2),
        ("landmark_ref", 3),
    ] {
        m!(family, move |w: &mut WorldIR| match index {
            0 => w.biome_fields[0].marker_id = "marker:1".into(),
            1 => w.hazard_fields[0].marker_id = "marker:1".into(),
            2 => w.resource_pressures[0].marker_id = "marker:1".into(),
            _ => w.landmarks[0].marker_id = "marker:1".into(),
        });
    }
    m!("biome_family", |w: &mut WorldIR| w.biome_fields[0]
        .biome_id =
        "ion_storm".into());
    m!("hazard_family", |w: &mut WorldIR| w.hazard_fields[0]
        .hazard_id =
        "scrap".into());
    m!("resource_family", |w: &mut WorldIR| w.resource_pressures
        [0]
    .resource_id =
        "relay".into());
    m!("biome_bp", |w: &mut WorldIR| w.biome_fields[0]
        .intensity_bp ^= 1);
    m!("hazard_bp", |w: &mut WorldIR| w.hazard_fields[0]
        .severity_bp ^= 1);
    m!("resource_bp", |w: &mut WorldIR| w.resource_pressures[0]
        .pressure_bp ^= 1);
    m!("field_order", |w: &mut WorldIR| w.biome_fields.swap(0, 1));
    m!("landmark_id", |w: &mut WorldIR| w.landmarks[0].id =
        "landmark:1".into());
    m!("landmark_ref", |w: &mut WorldIR| w.landmarks[0].marker_id =
        "marker:1".into());
    m!("landmark_kind", |w: &mut WorldIR| w.landmarks[0].kind =
        "oxygen".into());
    m!("landmark_duplicate", |w: &mut WorldIR| w.landmarks[1].id =
        w.landmarks[0].id.clone());
    m!("landmark_order", |w: &mut WorldIR| w.landmarks.swap(0, 1));
    m!("route_missing", |w: &mut WorldIR| {
        w.routes.pop();
    });
    m!("route_extra", |w: &mut WorldIR| w
        .routes
        .push(w.routes[0].clone()));
    m!("route_dangling", |w: &mut WorldIR| w.routes[0].from =
        "marker:99".into());
    m!("route_duplicate", |w: &mut WorldIR| w.routes[1] =
        w.routes[0].clone());
    m!("route_noncanonical", |w: &mut WorldIR| {
        let r = &mut w.routes[0];
        std::mem::swap(&mut r.from, &mut r.to);
    });
    m!("route_reversed", |w: &mut WorldIR| {
        let r = &mut w.routes[0];
        std::mem::swap(&mut r.from, &mut r.to);
    });
    m!("route_unsorted", |w: &mut WorldIR| w.routes.swap(0, 1));
    m!("route_zero", |w: &mut WorldIR| w.routes[0].cost_bp = 0);
    m!("route_over_max", |w: &mut WorldIR| w.routes[0].cost_bp =
        10_001);
    m!("anchor_id", |w: &mut WorldIR| w.anchors[0].id =
        "anchor:x".into());
    m!("anchor_kind", |w: &mut WorldIR| w.anchors[0].kind =
        "x".into());
    m!("anchor_order", |w: &mut WorldIR| w.anchors.swap(0, 1));
    m!("anchor_extra", |w: &mut WorldIR| w
        .anchors
        .push(w.anchors[0].clone()));
    m!("extract_selected", |w: &mut WorldIR| w
        .extraction
        .selected_marker_id =
        "marker:1".into());
    m!("extract_hub", |w: &mut WorldIR| w
        .extraction
        .hub_anchor_id =
        "anchor:x".into());
    m!("extract_anchor", |w: &mut WorldIR| w
        .extraction
        .extraction_anchor_id =
        "anchor:x".into());
    m!("extract_missing_edge", |w: &mut WorldIR| w
        .extraction
        .path =
        vec!["marker:0".into(), "marker:1".into()]);
    m!("extract_path_order", |w: &mut WorldIR| w
        .extraction
        .path
        .reverse());
    assert!(
        mutations.len() >= 40,
        "malformed candidate matrix has only {} cases",
        mutations.len()
    );
    for (name, mutate) in &mutations {
        let mut altered = world.clone();
        mutate(&mut altered);
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            altered.validate_for_request(&req, &rules)
        }));
        assert!(
            matches!(result, Ok(Err(_)) | Err(_)),
            "mutation {name} was accepted"
        );
    }
    eprintln!("malformed candidate matrix cases: {}", mutations.len());
}

#[test]
fn rules_and_fallback_validation_matrices_reject_bad_documents() {
    let base = WorldRules::bundled().unwrap();
    let mut rule_cases: Vec<(&str, WorldRules)> = Vec::new();
    let mut r = base.clone();
    r.biomes.clear();
    rule_cases.push(("empty_family", r));
    let mut r = base.clone();
    r.biomes.push(r.biomes[0].clone());
    rule_cases.push(("duplicate_family", r));
    let mut r = base.clone();
    r.biomes = vec!["unknown family".into()];
    rule_cases.push(("unknown_family", r));
    let mut r = base.clone();
    r.schema_version = "bad".into();
    rule_cases.push(("bad_schema", r));
    let mut r = base.clone();
    r.platform_version = 2;
    rule_cases.push(("bad_platform", r));
    let mut r = base.clone();
    r.route_cost_bp.min_bp = 0;
    rule_cases.push(("zero_min", r));
    let mut r = base.clone();
    r.route_cost_bp.max_bp = 10_001;
    rule_cases.push(("over_max", r));
    for (name, rules) in &rule_cases {
        assert!(rules.validate().is_err(), "rules case {name} accepted");
    }

    let rules = WorldRules::bundled().unwrap();
    let fallback = WorldFallback::bundled().unwrap();
    let mut fallback_cases = Vec::new();
    let mut f = fallback.clone();
    f.landmarks.clear();
    fallback_cases.push(("empty_landmarks", f));
    let mut f = fallback.clone();
    f.landmarks.push(f.landmarks[0].clone());
    fallback_cases.push(("duplicate_landmarks", f));
    let mut f = fallback.clone();
    f.biome_id = "unknown_family".into();
    fallback_cases.push(("unknown_biome", f));
    let mut f = fallback.clone();
    f.schema_version = "bad".into();
    fallback_cases.push(("bad_schema", f));
    let mut f = fallback.clone();
    f.platform_version = 2;
    fallback_cases.push(("bad_platform", f));
    let mut f = fallback.clone();
    f.route_cost_bp = 0;
    fallback_cases.push(("zero_cost", f));
    let mut f = fallback.clone();
    f.route_cost_bp = 10_001;
    fallback_cases.push(("over_cost", f));
    for (name, value) in &fallback_cases {
        assert!(
            value.validate(&rules).is_err(),
            "fallback case {name} accepted"
        );
    }
    eprintln!(
        "rules matrix cases: {}; fallback matrix cases: {}",
        rule_cases.len(),
        fallback_cases.len()
    );
}
