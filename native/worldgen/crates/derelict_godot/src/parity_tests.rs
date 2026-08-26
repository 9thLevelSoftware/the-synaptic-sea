use crate::generator::sync_json;
use derelict_core::lifecycle::LifecycleResult;
use derelict_core::procgen::ProcgenRequest;
use serde::Deserialize;

#[derive(Deserialize)]
struct Vector {
    name: String,
    request: ProcgenRequest,
    expected_semantic_hash: String,
}

#[test]
fn native_adapter_matches_shared_parity_corpus() {
    let vectors: Vec<Vector> =
        serde_json::from_str(include_str!("../../../tests/adapter_parity/corpus.json")).unwrap();
    for vector in vectors {
        let result = LifecycleResult::from_json(&sync_json(
            &serde_json::to_string(&vector.request).unwrap(),
        ))
        .unwrap_or_else(|error| {
            panic!("{} returned invalid lifecycle JSON: {error:?}", vector.name)
        });
        let bundle = result
            .bundle
            .unwrap_or_else(|| panic!("{} failed: {:?}", vector.name, result.failure));
        assert_eq!(
            bundle.semantic_hash, vector.expected_semantic_hash,
            "{}",
            vector.name
        );
    }
}
