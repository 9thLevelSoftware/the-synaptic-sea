use derelict_core::procgen::{generate_bundle, semantic_hash, ProcgenRequest};
use serde::Deserialize;

#[derive(Deserialize)]
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

#[test]
fn corpus_vectors_recompute_expected_hashes() {
    let data = derelict_core::GenData::default_bundle().unwrap();
    let vectors = vectors();
    assert_eq!(vectors.len(), 8);
    let mut hashes = std::collections::BTreeMap::new();
    let mut names = std::collections::BTreeSet::new();
    let mut archetypes = std::collections::BTreeSet::new();
    for vector in vectors {
        assert!(names.insert(vector.name.clone()), "duplicate vector name");
        assert_eq!(vector.request.content_manifest_hash.len(), 64);
        assert!(vector
            .request
            .content_manifest_hash
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit()));
        assert_eq!(vector.expected_semantic_hash.len(), 64);
        assert!(vector
            .expected_semantic_hash
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit()));
        archetypes.insert(vector.request.site.archetype_id.clone());
        let bundle = generate_bundle(vector.request, &data)
            .unwrap_or_else(|error| panic!("{} failed: {error:?}", vector.name));
        let hash = semantic_hash(&bundle).unwrap();
        println!("{}={hash}", vector.name);
        assert_eq!(bundle.semantic_hash, hash);
        assert_eq!(
            bundle.semantic_hash, vector.expected_semantic_hash,
            "{}",
            vector.name
        );
        if let Some(parent) = vector.same_semantics_as {
            assert_eq!(
                hashes.get(&parent),
                Some(&hash),
                "{parent} vs {}",
                vector.name
            );
        }
        hashes.insert(vector.name, hash);
    }
    assert_eq!(
        archetypes,
        ["corvette", "freighter", "frigate", "shuttle"]
            .into_iter()
            .map(String::from)
            .collect()
    );
}
