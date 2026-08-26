//! The `DerelictGenerator` Godot class and native lifecycle adapter.
use crate::async_gen::{AsyncGen, GenResult};
use crate::convert::{gen_params_from_dict, ship_to_dictionary};
use crate::service::{Limits, Service, SystemClock};
use derelict_core::lifecycle::{
    AdapterKind, AdapterSchemas, GeneratorManifest, LifecycleEvent, LifecycleResult,
    ProcgenCapabilities, WorkerMode,
};
use derelict_core::manifest::ExportSchemas;
use derelict_core::model::{GenParams, GENERATOR_VERSION};
use derelict_core::procgen::{
    Domain, PlayerModel, PresentationRequest, ProcgenRequest, SiteRequest,
};
use derelict_core::procgen::{ProcgenFailure, ProcgenFailureCode};
use derelict_core::GenData;
use godot::builtin::{GString, VarDictionary, Variant};
use godot::classes::RefCounted;
use godot::meta::ToGodot;
use godot::obj::Base;
use godot::prelude::{godot_api, GodotClass};
use serde::Serialize;
use std::sync::{Arc, OnceLock};

const SOURCE_COMMIT: &str = env!("SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT");
const CONTENT_HASH: &str = env!("SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH");
const TARGET: &str = env!("SYNAPTIC_PROCGEN_TARGET");
fn dirty_development() -> bool {
    env!("SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT") == "true"
}

fn adapter_failure(message: &str) -> ProcgenFailure {
    ProcgenFailure {
        schema_version: "procgen-failure-1".into(),
        code: ProcgenFailureCode::AdapterFailure,
        stage: "adapter".into(),
        message: message.into(),
        retryable: false,
        fallback_id: None,
    }
}

fn manifest_failure(message: &str) -> ProcgenFailure {
    ProcgenFailure {
        schema_version: "procgen-failure-1".into(),
        code: ProcgenFailureCode::ManifestFailure,
        stage: "manifest".into(),
        message: message.into(),
        retryable: false,
        fallback_id: None,
    }
}

pub(crate) fn runtime_manifest() -> Result<GeneratorManifest, ProcgenFailure> {
    let manifest = GeneratorManifest {
        schema_version: "procgen-generator-manifest-1".into(),
        rust_source_commit: SOURCE_COMMIT.into(),
        generator_version: GENERATOR_VERSION,
        content_manifest_hash: CONTENT_HASH.into(),
        export_schemas: ExportSchemas::v1(),
        adapter_schemas: AdapterSchemas::v1(),
        target: TARGET.into(),
        dirty_development: dirty_development(),
    };
    manifest
        .validate()
        .map(|_| manifest)
        .map_err(|_| manifest_failure("compiled manifest is invalid"))
}

pub(crate) fn runtime_capabilities() -> Result<ProcgenCapabilities, ProcgenFailure> {
    let limits = Limits::default();
    let capabilities = ProcgenCapabilities {
        schema_version: "procgen-capabilities-1".into(),
        adapter_kind: AdapterKind::Native,
        target: TARGET.into(),
        supports_sync: true,
        supports_async: true,
        supports_cancel: true,
        worker_mode: WorkerMode::ThreadPool,
        worker_count: limits.workers as u32,
        queue_capacity: limits.queue_capacity as u32,
        retained_results: limits.retained_results as u32,
        max_request_bytes: limits.max_request_bytes as u64,
        max_entities: limits.max_entities as u32,
        max_trace_entries: limits.max_trace_entries as u32,
        max_events: limits.max_events as u32,
        deadline_ms: limits.deadline_ms,
        supported_domains: vec![
            Domain::World,
            Domain::Site,
            Domain::Gameplay,
            Domain::Presentation,
        ],
        schemas: AdapterSchemas::v1(),
    };
    capabilities
        .validate()
        .map(|_| capabilities)
        .map_err(|_| adapter_failure("compiled capabilities are invalid"))
}

struct Runtime {
    data: GenData,
    service: Arc<Service>,
    manifest: GeneratorManifest,
    capabilities: ProcgenCapabilities,
}
static RUNTIME: OnceLock<Result<Runtime, ProcgenFailure>> = OnceLock::new();
fn runtime() -> Result<&'static Runtime, ProcgenFailure> {
    RUNTIME
        .get_or_init(|| {
            let manifest = runtime_manifest()?;
            let capabilities = runtime_capabilities()?;
            let data = GenData::default_bundle().map_err(|e| adapter_failure(&e.to_string()))?;
            let generator_data = data.clone();
            let service = Service::new(
                Limits::default(),
                Arc::new(SystemClock::default()),
                CONTENT_HASH.into(),
                Arc::new(move |request| {
                    derelict_core::procgen::generate_bundle(request, &generator_data)
                }),
            );
            Ok(Runtime {
                data,
                service,
                manifest,
                capabilities,
            })
        })
        .as_ref()
        .map_err(Clone::clone)
}

pub(crate) fn serialize_json<T, F>(value: &T, serializer: F) -> String
where
    T: Serialize,
    F: FnOnce(&T) -> Result<String, serde_json::Error>,
{
    match serializer(value) {
        Ok(json) => json,
        Err(_) => serde_json::to_string(&LifecycleResult::failed(None, adapter_failure("response serialization failed"), vec![LifecycleEvent::Failed])).unwrap_or_else(|_| "{\"schema_version\":\"procgen-lifecycle-result-1\",\"status\":\"failed\",\"failure\":{\"schema_version\":\"procgen-failure-1\",\"code\":\"adapter_failure\",\"stage\":\"adapter\",\"message\":\"response serialization failed\",\"retryable\":false},\"events\":[\"failed\"]}".into()),
    }
}
fn serialize<T: Serialize>(value: &T) -> GString {
    GString::from(serialize_json(value, serde_json::to_string).as_str())
}
fn lifecycle_failure(failure: ProcgenFailure) -> String {
    serialize_json(
        &LifecycleResult::failed(None, failure, vec![LifecycleEvent::Failed]),
        serde_json::to_string,
    )
}

pub(crate) fn legacy_request(seed: u64, params: &GenParams, kit_id: &str) -> ProcgenRequest {
    ProcgenRequest {
        schema_version: "procgen-request-1".into(),
        world_seed: seed,
        site: SiteRequest {
            site_id: "legacy-site".into(),
            x: 0,
            y: 0,
            archetype_id: params.archetype_id.clone(),
            kit_id: kit_id.into(),
            intactness_override_bp: params.intactness_override,
            cause_of_loss: params.cause_override,
            loot_richness_bp: params.loot_richness,
        },
        difficulty_id: "legacy".into(),
        player_model: PlayerModel {
            schema_version: "player-model-1".into(),
            signals: Vec::new(),
        },
        requested_domains: vec![
            Domain::World,
            Domain::Site,
            Domain::Gameplay,
            Domain::Presentation,
        ],
        generator_version: GENERATOR_VERSION,
        content_manifest_hash: CONTENT_HASH.into(),
        presentation: PresentationRequest {
            seed,
            locale: "en-US".into(),
        },
    }
}

#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct DerelictGenerator {
    base: Base<RefCounted>,
    #[init(val = AsyncGen::default())]
    async_gen: AsyncGen,
}
impl DerelictGenerator {
    fn runtime(&self) -> Result<&'static Runtime, ProcgenFailure> {
        runtime()
    }
    fn data(&self) -> Option<&GenData> {
        self.runtime().ok().map(|r| &r.data)
    }
}

#[godot_api]
impl DerelictGenerator {
    #[func]
    fn generate_bundle(&self, request_json: GString) -> GString {
        match self.runtime() {
            Ok(r) => serialize(
                &r.service
                    .generate_sync_json(request_json.to_string().as_str()),
            ),
            Err(e) => GString::from(lifecycle_failure(e).as_str()),
        }
    }
    #[func]
    fn generate_bundle_async(&self, request_json: GString) -> GString {
        match self.runtime() {
            Ok(r) => serialize(&r.service.submit_json(request_json.to_string().as_str())),
            Err(e) => GString::from(lifecycle_failure(e).as_str()),
        }
    }
    #[func]
    fn poll(&self, request_id: i64) -> GString {
        match self.runtime() {
            Ok(r) => serialize(&r.service.poll(request_id)),
            Err(e) => GString::from(lifecycle_failure(e).as_str()),
        }
    }
    #[func]
    fn cancel(&self, request_id: i64) -> GString {
        match self.runtime() {
            Ok(r) => serialize(&r.service.cancel(request_id)),
            Err(e) => GString::from(lifecycle_failure(e).as_str()),
        }
    }
    #[func]
    fn capabilities(&self) -> GString {
        match self.runtime() {
            Ok(r) => serialize(&r.capabilities),
            Err(e) => GString::from(lifecycle_failure(e).as_str()),
        }
    }
    #[func]
    fn generator_manifest(&self) -> GString {
        match self.runtime() {
            Ok(r) => serialize(&r.manifest),
            Err(e) => GString::from(lifecycle_failure(e).as_str()),
        }
    }
    #[func]
    fn generate(&self, seed: i64, params: VarDictionary) -> VarDictionary {
        let p = gen_params_from_dict(&params);
        let Ok(r) = self.runtime() else {
            let mut d = VarDictionary::new();
            d.set("error", "adapter failure");
            return d;
        };
        let result = r
            .service
            .generate_sync(legacy_request(seed as u64, &p, "legacy"));
        if result.status == derelict_core::lifecycle::LifecycleStatus::Completed {
            ship_to_dictionary(&result.bundle.unwrap().site_ir.ship)
        } else {
            let mut d = VarDictionary::new();
            d.set(
                "error",
                result
                    .failure
                    .map(|f| f.message)
                    .unwrap_or_else(|| "generation failed".into()),
            );
            d
        }
    }
    #[func]
    fn generate_async(&mut self, seed: i64, params: VarDictionary) -> i64 {
        let Ok(r) = self.runtime() else {
            return -1;
        };
        self.async_gen.start(
            legacy_request(seed as u64, &gen_params_from_dict(&params), "legacy"),
            &r.service,
        )
    }
    #[func]
    fn poll_async(&mut self, request_id: i64) -> Variant {
        let Ok(r) = self.runtime() else {
            return Variant::nil();
        };
        match self.async_gen.poll(request_id, &r.service) {
            None => Variant::nil(),
            Some(GenResult::Ok(ship)) => ship_to_dictionary(&ship).to_variant(),
            Some(GenResult::Err(e)) => {
                let mut d = VarDictionary::new();
                d.set("error", e);
                d.to_variant()
            }
        }
    }
    #[func]
    fn derive_site_seed(&self, world_seed: i64, world_x: i64, world_y: i64) -> i64 {
        derelict_core::derive_site_seed(world_seed as u64, world_x, world_y) as i64
    }
    #[func]
    fn item_catalog(&self) -> VarDictionary {
        let mut d = VarDictionary::new();
        if let Some(data) = self.data() {
            for item in &data.items.items {
                d.set(item.id as i64, item.name.as_str());
            }
        }
        d
    }
    #[func]
    fn archetypes(&self) -> godot::builtin::PackedStringArray {
        self.data()
            .map(|d| d.archetypes.keys().map(|k| k.into()).collect())
            .unwrap_or_default()
    }
    #[func]
    fn generator_version(&self) -> i64 {
        GENERATOR_VERSION as i64
    }
    #[func]
    fn export_layout_json(&self, seed: i64, params: VarDictionary, kit_id: GString) -> GString {
        self.export_bundle(seed, &params, &kit_id.to_string(), true)
    }
    #[func]
    fn export_gameplay_slice_json(&self, seed: i64, params: VarDictionary) -> GString {
        self.export_bundle(seed, &params, "legacy", false)
    }
}
impl DerelictGenerator {
    fn export_bundle(
        &self,
        seed: i64,
        params: &VarDictionary,
        kit_id: &str,
        layout: bool,
    ) -> GString {
        let Ok(r) = self.runtime() else {
            return GString::new();
        };
        let result = r.service.generate_sync(legacy_request(
            seed as u64,
            &gen_params_from_dict(params),
            kit_id,
        ));
        let Some(bundle) = result.bundle else {
            return GString::new();
        };
        let value = if layout {
            derelict_core::procgen::migration_layout(&bundle)
        } else {
            derelict_core::procgen::migration_gameplay(&bundle)
        };
        GString::from(
            value
                .ok()
                .and_then(|v| serde_json::to_string_pretty(&v).ok())
                .unwrap_or_default()
                .as_str(),
        )
    }
}
