use derelict_core::lifecycle::LifecycleResult;
use derelict_core::player_model::{PlayerModelV2, PlayerSignal, PlayerSignalKind};
use derelict_core::procgen::{Domain, PresentationRequest, ProcgenRequest, SiteRequest};
use derelict_core::world::PROCGEN_GENERATOR_VERSION;
use derelict_wasm::{Clock, DataProvider, Generator, Serializer, WasmService};
use std::sync::Arc;

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

struct Vector {
    name: &'static str,
    request: ProcgenRequest,
}

fn fixture(seed: u64, name: &'static str) -> Vector {
    Vector {
        name,
        request: ProcgenRequest {
            schema_version: "procgen-request-2".into(),
            world_seed: seed,
            site: SiteRequest {
                site_id: format!("parity-site-{seed}"),
                x: 3,
                y: -2,
                archetype_id: "shuttle".into(),
                kit_id: "ship_structural_v0".into(),
                intactness_override_bp: Some(10_000),
                cause_of_loss: None,
                loot_richness_bp: 5_000,
            },
            difficulty_id: "standard".into(),
            player_model: PlayerModelV2 {
                schema_version: "player-model-2".into(),
                signals: vec![PlayerSignal {
                    kind: PlayerSignalKind::CombatMastery,
                    value_bp: 5_000,
                }],
            },
            requested_domains: vec![
                Domain::World,
                Domain::Site,
                Domain::Gameplay,
                Domain::Presentation,
            ],
            generator_version: PROCGEN_GENERATOR_VERSION,
            content_manifest_hash: env!("SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH").into(),
            presentation: PresentationRequest {
                seed,
                locale: "en-US".into(),
            },
        },
    }
}

#[test]
fn wasm_host_sync_and_cooperative_async_match_typed_fixtures() {
    let vectors = vec![
        fixture(42, "standard_combat"),
        fixture(43, "standard_followup"),
    ];
    let content_hash = vectors[0].request.content_manifest_hash.clone();
    let service = WasmService::new_with_content_hash(
        Arc::new(ZeroClock),
        Arc::new(FixtureData),
        Arc::new(FixtureGenerator),
        Arc::new(JsonSerializer),
        content_hash,
    );
    for vector in vectors {
        let raw = serde_json::to_string(&vector.request).unwrap();
        let sync = LifecycleResult::from_json(&service.sync(&raw)).unwrap();
        let sync_bundle = sync
            .bundle
            .unwrap_or_else(|| panic!("{} sync failed: {:?}", vector.name, sync.failure));

        let accepted = LifecycleResult::from_json(&service.submit(&raw)).unwrap();
        let id = accepted.request_id.unwrap();
        let terminal = LifecycleResult::from_json(&service.poll_request(id)).unwrap();
        let terminal_bundle = terminal
            .bundle
            .unwrap_or_else(|| panic!("{} async failed: {:?}", vector.name, terminal.failure));
        assert_eq!(
            sync_bundle.semantic_hash, terminal_bundle.semantic_hash,
            "{} parity",
            vector.name
        );
        assert!(terminal.events.iter().any(|event| matches!(
            event,
            derelict_core::lifecycle::LifecycleEvent::ResultConsumed
        )));
    }
}
