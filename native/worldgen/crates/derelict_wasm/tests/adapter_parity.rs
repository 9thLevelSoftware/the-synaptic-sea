use derelict_core::lifecycle::LifecycleResult;
use derelict_core::procgen::ProcgenRequest;
use derelict_wasm::{Clock, DataProvider, Generator, Serializer, WasmService};
use serde::Deserialize;
use std::sync::Arc;

const CONTENT_HASH: &str = "e0364ba52fbf0b1c629c676d622fdc2ffd6964bee47c11cad58c320de22a7c1a";

struct ZeroClock;
impl Clock for ZeroClock {
    fn now_ms(&self) -> u64 {
        0
    }
}
struct FixtureData;
impl DataProvider for FixtureData {
    fn data(&self) -> Result<derelict_core::GenData, String> {
        derelict_core::GenData::default_bundle().map_err(|error| error.to_string())
    }
}
struct FixtureGenerator;
impl Generator for FixtureGenerator {
    fn generate(
        &self,
        request: ProcgenRequest,
        data: &derelict_core::GenData,
    ) -> Result<derelict_core::procgen::ProcgenBundle, derelict_core::procgen::ProcgenFailure> {
        derelict_core::procgen::generate_bundle(request, data)
    }
}
struct JsonSerializer;
impl Serializer for JsonSerializer {
    fn serialize(&self, result: &LifecycleResult) -> Result<String, String> {
        serde_json::to_string(result).map_err(|error| error.to_string())
    }
}

#[derive(Deserialize)]
struct Vector {
    name: String,
    request: ProcgenRequest,
    expected_semantic_hash: String,
}

#[test]
fn wasm_host_sync_and_cooperative_async_match_corpus() {
    let vectors: Vec<Vector> =
        serde_json::from_str(include_str!("../../../tests/adapter_parity/corpus.json")).unwrap();
    let service = WasmService::new_with_content_hash(
        Arc::new(ZeroClock),
        Arc::new(FixtureData),
        Arc::new(FixtureGenerator),
        Arc::new(JsonSerializer),
        CONTENT_HASH.into(),
    );
    for vector in vectors {
        let raw = serde_json::to_string(&vector.request).unwrap();
        let sync = LifecycleResult::from_json(&service.sync(&raw)).unwrap();
        let sync_bundle = sync
            .bundle
            .unwrap_or_else(|| panic!("{} sync failed: {:?}", vector.name, sync.failure));
        assert_eq!(
            sync_bundle.semantic_hash, vector.expected_semantic_hash,
            "{} sync",
            vector.name
        );

        let accepted = LifecycleResult::from_json(&service.submit(&raw)).unwrap();
        let id = accepted.request_id.unwrap();
        let terminal = LifecycleResult::from_json(&service.poll_request(id)).unwrap();
        let terminal_bundle = terminal
            .bundle
            .unwrap_or_else(|| panic!("{} async failed: {:?}", vector.name, terminal.failure));
        assert_eq!(
            terminal_bundle.semantic_hash, vector.expected_semantic_hash,
            "{} async",
            vector.name
        );
        assert!(terminal.events.iter().any(|event| matches!(
            event,
            derelict_core::lifecycle::LifecycleEvent::ResultConsumed
        )));
    }
}
