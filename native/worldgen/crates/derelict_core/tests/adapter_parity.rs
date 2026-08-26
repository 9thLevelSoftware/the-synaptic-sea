use derelict_core::procgen::{generate_bundle, semantic_hash, ProcgenRequest};
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Vector {
    name: String,
    request: ProcgenRequest,
    expected_semantic_hash: String,
    #[serde(default)]
    same_semantics_as: Option<String>,
}

fn vectors() -> Vec<Vector> {
    serde_json::from_str(include_str!("../../../tests/adapter_parity/corpus.json")).unwrap()
}

fn is_lower_sha256(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

#[test]
fn corpus_vectors_recompute_expected_hashes() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let vectors = vectors();
    assert_eq!(vectors.len(), 8);
    let manifest: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../../data/procgen/manifests/content_manifest.json"
    ))
    .unwrap();
    let current_content_hash = manifest["content_manifest_hash"].as_str().unwrap();
    assert!(is_lower_sha256(current_content_hash));

    let expected_domains = ["world", "site", "gameplay", "presentation"];
    let mut hashes = BTreeMap::new();
    let mut semantic_links = Vec::new();
    let mut names = BTreeSet::new();
    let mut requests = BTreeSet::new();
    let mut archetypes = BTreeSet::new();
    let mut difficulties = BTreeSet::new();
    let mut saw_positive_coordinate = false;
    let mut saw_negative_coordinate = false;
    let mut saw_origin = false;
    let mut saw_empty_player = false;
    let mut saw_nonempty_player = false;
    let mut saw_intact = false;
    let mut saw_damaged = false;
    let mut saw_fractured = false;
    for vector in vectors {
        assert!(names.insert(vector.name.clone()), "duplicate vector name");
        assert!(requests.insert(serde_json::to_string(&vector.request).unwrap()));
        vector.request.validate().unwrap();
        assert_eq!(vector.request.content_manifest_hash, current_content_hash);
        assert!(is_lower_sha256(&vector.request.content_manifest_hash));
        assert!(is_lower_sha256(&vector.expected_semantic_hash));
        assert!(vector.request.world_seed <= 9_007_199_254_740_991);
        assert!(vector.request.presentation.seed <= 9_007_199_254_740_991);
        assert_eq!(
            vector
                .request
                .requested_domains
                .iter()
                .map(|domain| serde_json::to_value(domain).unwrap())
                .map(|value| value.as_str().unwrap().to_owned())
                .collect::<Vec<_>>(),
            expected_domains
        );
        archetypes.insert(vector.request.site.archetype_id.clone());
        difficulties.insert(vector.request.difficulty_id.clone());
        saw_positive_coordinate |= vector.request.site.x > 0 || vector.request.site.y > 0;
        saw_negative_coordinate |= vector.request.site.x < 0 || vector.request.site.y < 0;
        saw_origin |= vector.request.site.x == 0 && vector.request.site.y == 0;
        saw_empty_player |= vector.request.player_model.signals.is_empty();
        saw_nonempty_player |= !vector.request.player_model.signals.is_empty();

        let bundle = generate_bundle(vector.request, &data)
            .unwrap_or_else(|error| panic!("{} failed: {error:?}", vector.name));
        let hash = semantic_hash(&bundle).unwrap();
        assert_eq!(bundle.semantic_hash, hash);
        assert_eq!(
            bundle.semantic_hash, vector.expected_semantic_hash,
            "{}",
            vector.name
        );
        if vector.name.contains("_intact_") {
            assert_eq!(bundle.site_ir.ship.intactness, 10_000, "{}", vector.name);
            assert!(!bundle.site_ir.ship.fractured, "{}", vector.name);
            saw_intact = true;
        }
        if vector.name.contains("_damaged_") {
            assert!(bundle.site_ir.ship.intactness < 10_000, "{}", vector.name);
            saw_damaged = true;
        }
        if vector.name.contains("_fractured_") {
            assert!(bundle.site_ir.ship.fractured, "{}", vector.name);
            saw_fractured = true;
        }
        if let Some(parent) = vector.same_semantics_as {
            assert_ne!(parent, vector.name);
            semantic_links.push((vector.name.clone(), parent));
        }
        hashes.insert(vector.name, hash);
    }
    for (name, parent) in semantic_links {
        assert_eq!(hashes.get(&name), hashes.get(&parent), "{parent} vs {name}");
    }
    assert_eq!(
        archetypes,
        ["corvette", "freighter", "frigate", "shuttle"]
            .into_iter()
            .map(String::from)
            .collect()
    );
    assert_eq!(
        difficulties,
        ["easy", "extreme", "hard", "nightmare", "standard"]
            .into_iter()
            .map(String::from)
            .collect()
    );
    assert!(saw_positive_coordinate && saw_negative_coordinate && saw_origin);
    assert!(saw_empty_player && saw_nonempty_player);
    assert!(saw_intact && saw_damaged && saw_fractured);
}
