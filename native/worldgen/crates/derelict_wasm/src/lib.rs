//! Cooperative WebAssembly adapter over the shared deterministic procgen core.
use derelict_core::lifecycle::{
    AdapterKind, AdapterSchemas, GeneratorManifest, LifecycleEvent, LifecycleResult,
    ProcgenCapabilities, WorkerMode,
};
use derelict_core::manifest::ExportSchemas;
use derelict_core::model::GENERATOR_VERSION;
use derelict_core::procgen::{
    generate_bundle as core_generate_bundle, Domain, ProcgenFailure, ProcgenFailureCode,
    ProcgenRequest,
};
use derelict_core::GenData;
use serde_json::to_string;
use std::cell::RefCell;
use std::collections::{BTreeMap, VecDeque};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;
#[cfg(not(target_arch = "wasm32"))]
use std::sync::OnceLock;
#[cfg(not(target_arch = "wasm32"))]
use std::time::Instant;
use wasm_bindgen::prelude::*;

const MAX_REQUEST: usize = 64 * 1024;
const MAX_ENTITIES: usize = 4096;
const MAX_TRACE: usize = 4096;
const MAX_EVENTS: usize = 32;
const QUEUE: usize = 8;
const RETAINED: usize = 16;
const CONTENT_HASH: &str = env!("SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH");
const SOURCE_COMMIT: &str = env!("SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT");

pub trait Clock: Send + Sync {
    fn now_ms(&self) -> u64;
}
pub trait DataProvider: Send + Sync {
    fn data(&self) -> Result<GenData, String>;
}
pub trait Generator: Send + Sync {
    fn generate(
        &self,
        request: ProcgenRequest,
        data: &GenData,
    ) -> Result<derelict_core::procgen::ProcgenBundle, ProcgenFailure>;
}
pub trait Serializer: Send + Sync {
    fn serialize(&self, result: &LifecycleResult) -> Result<String, String>;
}

struct DefaultClock;
impl Clock for DefaultClock {
    fn now_ms(&self) -> u64 {
        #[cfg(target_arch = "wasm32")]
        {
            js_sys::Date::now().max(0.0) as u64
        }
        #[cfg(not(target_arch = "wasm32"))]
        {
            static START: OnceLock<Instant> = OnceLock::new();
            START.get_or_init(Instant::now).elapsed().as_millis() as u64
        }
    }
}
struct DefaultData;
impl DataProvider for DefaultData {
    fn data(&self) -> Result<GenData, String> {
        GenData::default_bundle().map_err(|e| e.to_string())
    }
}
struct DefaultGenerator;
impl Generator for DefaultGenerator {
    fn generate(
        &self,
        request: ProcgenRequest,
        data: &GenData,
    ) -> Result<derelict_core::procgen::ProcgenBundle, ProcgenFailure> {
        core_generate_bundle(request, data)
    }
}
struct JsonSerializer;
impl Serializer for JsonSerializer {
    fn serialize(&self, result: &LifecycleResult) -> Result<String, String> {
        to_string(result).map_err(|e| e.to_string())
    }
}

#[derive(Clone)]
enum Entry {
    Queued(Box<ProcgenRequest>),
    Cancelled(Box<LifecycleResult>),
}
struct State {
    next_id: i64,
    queue: VecDeque<i64>,
    entries: BTreeMap<i64, Entry>,
    tombstones: BTreeMap<i64, ProcgenFailureCode>,
    data: Option<GenData>,
    highest_admitted: i64,
    admitted_at: BTreeMap<i64, u64>,
}
impl Default for State {
    fn default() -> Self {
        Self {
            next_id: 1,
            queue: VecDeque::new(),
            entries: BTreeMap::new(),
            tombstones: BTreeMap::new(),
            data: None,
            highest_admitted: 0,
            admitted_at: BTreeMap::new(),
        }
    }
}
pub struct WasmService {
    clock: Arc<dyn Clock>,
    data: Arc<dyn DataProvider>,
    generator: Arc<dyn Generator>,
    serializer: Arc<dyn Serializer>,
    state: RefCell<State>,
}
impl Default for WasmService {
    fn default() -> Self {
        Self {
            clock: Arc::new(DefaultClock),
            data: Arc::new(DefaultData),
            generator: Arc::new(DefaultGenerator),
            serializer: Arc::new(JsonSerializer),
            state: RefCell::new(State::default()),
        }
    }
}
impl WasmService {
    pub fn new(
        clock: Arc<dyn Clock>,
        data: Arc<dyn DataProvider>,
        generator: Arc<dyn Generator>,
        serializer: Arc<dyn Serializer>,
    ) -> Self {
        Self {
            clock,
            data,
            generator,
            serializer,
            state: RefCell::new(State::default()),
        }
    }
    fn encode(&self, result: LifecycleResult) -> String {
        self.serializer
            .serialize(&result)
            .ok()
            .filter(|s| !s.is_empty())
            .unwrap_or_else(json_fallback)
    }
}
fn json_fallback() -> String {
    r#"{"schema_version":"procgen-lifecycle-result-1","status":"failed","request_id":null,"bundle":null,"failure":{"schema_version":"procgen-failure-1","code":"internal_failure","stage":"adapter","message":"serialization failure","retryable":false,"fallback_id":null},"events":["failed"]}"#.into()
}

fn failure(
    id: Option<i64>,
    code: ProcgenFailureCode,
    message: &str,
    event: LifecycleEvent,
) -> LifecycleResult {
    LifecycleResult::failed(
        id,
        ProcgenFailure {
            schema_version: "procgen-failure-1".into(),
            code,
            stage: "adapter".into(),
            message: message.into(),
            retryable: false,
            fallback_id: None,
        },
        vec![event],
    )
}
fn json(result: LifecycleResult) -> String {
    to_string(&result).unwrap_or_else(|_| json_fallback())
}
fn tombstone(state: &mut State, id: i64, code: ProcgenFailureCode) {
    state.tombstones.insert(id, code);
    while state.tombstones.len() > RETAINED {
        if let Some(old) = state.tombstones.keys().next().copied() {
            state.tombstones.remove(&old);
        }
    }
}
fn unavailable(state: &State, id: i64) -> (ProcgenFailureCode, &'static str, LifecycleEvent) {
    match state.tombstones.get(&id) {
        Some(ProcgenFailureCode::ResultConsumed) => (
            ProcgenFailureCode::ResultConsumed,
            "result already consumed",
            LifecycleEvent::ResultConsumed,
        ),
        Some(ProcgenFailureCode::ResultExpired) => (
            ProcgenFailureCode::ResultExpired,
            "result expired",
            LifecycleEvent::ResultExpired,
        ),
        _ if id > state.highest_admitted => (
            ProcgenFailureCode::UnknownRequest,
            "future request id",
            LifecycleEvent::Rejected,
        ),
        _ => (
            ProcgenFailureCode::ResultExpired,
            "result expired",
            LifecycleEvent::ResultExpired,
        ),
    }
}
fn retain_cancelled(state: &mut State, id: i64, result: LifecycleResult) {
    let cancelled = state
        .entries
        .iter()
        .filter_map(|(key, value)| matches!(value, Entry::Cancelled(_)).then_some(*key))
        .collect::<Vec<_>>();
    if cancelled.len() >= RETAINED {
        if let Some(oldest) = cancelled.first() {
            state.entries.remove(oldest);
            tombstone(state, *oldest, ProcgenFailureCode::ResultExpired);
        }
    }
    state.entries.insert(id, Entry::Cancelled(Box::new(result)));
}
fn validate_request(raw: &str) -> Result<ProcgenRequest, Box<LifecycleResult>> {
    if raw.len() > MAX_REQUEST {
        return Err(Box::new(failure(
            None,
            ProcgenFailureCode::Capacity,
            "request too large",
            LifecycleEvent::Rejected,
        )));
    }
    let req = ProcgenRequest::from_json(raw).map_err(|e| {
        Box::new(failure(
            None,
            ProcgenFailureCode::InvalidRequest,
            &e.to_string(),
            LifecycleEvent::Rejected,
        ))
    })?;
    if req.content_manifest_hash != CONTENT_HASH {
        return Err(Box::new(failure(
            None,
            ProcgenFailureCode::GeneratorContentMismatch,
            "content manifest mismatch",
            LifecycleEvent::Rejected,
        )));
    }
    Ok(req)
}
fn capabilities_value() -> ProcgenCapabilities {
    ProcgenCapabilities {
        schema_version: "procgen-capabilities-1".into(),
        adapter_kind: AdapterKind::Web,
        target: "wasm32-unknown-unknown".into(),
        supports_sync: true,
        supports_async: true,
        supports_cancel: true,
        worker_mode: WorkerMode::Cooperative,
        worker_count: 0,
        queue_capacity: QUEUE as u32,
        retained_results: RETAINED as u32,
        max_request_bytes: MAX_REQUEST as u64,
        max_entities: MAX_ENTITIES as u32,
        max_trace_entries: MAX_TRACE as u32,
        max_events: MAX_EVENTS as u32,
        deadline_ms: 2_000,
        supported_domains: vec![
            Domain::World,
            Domain::Site,
            Domain::Gameplay,
            Domain::Presentation,
        ],
        schemas: AdapterSchemas::v1(),
    }
}
fn manifest_value() -> GeneratorManifest {
    GeneratorManifest {
        schema_version: "procgen-generator-manifest-1".into(),
        rust_source_commit: SOURCE_COMMIT.into(),
        generator_version: GENERATOR_VERSION,
        content_manifest_hash: CONTENT_HASH.into(),
        export_schemas: ExportSchemas::v1(),
        adapter_schemas: AdapterSchemas::v1(),
        target: "wasm32-unknown-unknown".into(),
        dirty_development: env!("SYNAPTIC_PROCGEN_DIRTY_DEVELOPMENT") == "true",
    }
}
impl WasmService {
    fn generate(
        &self,
        req: ProcgenRequest,
        admitted_at: Option<u64>,
        request_id: Option<i64>,
    ) -> LifecycleResult {
        {
            let mut state = self.state.borrow_mut();
            let start = self.clock.now_ms();
            if let Some(at) = admitted_at {
                if start.saturating_sub(at) >= 2_000 {
                    return failure(
                        request_id,
                        ProcgenFailureCode::Timeout,
                        "deadline exceeded",
                        LifecycleEvent::TimedOut,
                    );
                }
            }
            if state.data.is_none() {
                state.data = self.data.data().ok();
            }
            let Some(data) = state.data.as_ref() else {
                return failure(
                    request_id,
                    ProcgenFailureCode::AdapterFailure,
                    "content data unavailable",
                    LifecycleEvent::Failed,
                );
            };
            let generated = catch_unwind(AssertUnwindSafe(|| self.generator.generate(req, data)));
            let mut result = match generated {
                Err(_) => failure(
                    request_id,
                    ProcgenFailureCode::InternalFailure,
                    "generator panicked",
                    LifecycleEvent::Failed,
                ),
                Ok(Err(f)) => match f.validate() {
                    Ok(()) => LifecycleResult::failed(request_id, f, vec![LifecycleEvent::Failed]),
                    Err(_) => failure(
                        request_id,
                        ProcgenFailureCode::AdapterFailure,
                        "invalid generator failure",
                        LifecycleEvent::Failed,
                    ),
                },
                Ok(Ok(bundle)) => match bundle.validate() {
                    Err(error) => failure(
                        request_id,
                        ProcgenFailureCode::ValidationFailure,
                        &error.to_string(),
                        LifecycleEvent::Failed,
                    ),
                    Ok(())
                        if bundle.site_ir.ship.entities.len() > MAX_ENTITIES
                            || bundle.trace.rng_channels.len() > MAX_TRACE
                            || bundle.trace.candidate_decisions.len() > MAX_TRACE
                            || bundle.trace.failed_constraints.len() > MAX_TRACE
                            || bundle.trace.repairs.len() > MAX_TRACE
                            || bundle.trace.retries.len() > MAX_TRACE
                            || bundle
                                .trace
                                .fallback
                                .as_ref()
                                .is_some_and(|v| v.len() > MAX_TRACE)
                            || bundle.trace.stage_timings_micros.len() > MAX_TRACE
                            || bundle.metrics.stage_timings_micros.len() > MAX_TRACE =>
                    {
                        failure(
                            request_id,
                            ProcgenFailureCode::Capacity,
                            "output exceeds adapter limits",
                            LifecycleEvent::Failed,
                        )
                    }
                    Ok(()) => LifecycleResult::completed(
                        request_id,
                        bundle,
                        vec![LifecycleEvent::Started, LifecycleEvent::Completed],
                    ),
                },
            };
            if let Some(at) = admitted_at {
                if self.clock.now_ms().saturating_sub(at) >= 2_000 {
                    result = failure(
                        request_id,
                        ProcgenFailureCode::Timeout,
                        "deadline exceeded",
                        LifecycleEvent::TimedOut,
                    );
                    result.events.insert(0, LifecycleEvent::Started);
                } else if !result.events.contains(&LifecycleEvent::Started) {
                    result.events.insert(0, LifecycleEvent::Started);
                }
            }
            result
        }
    }

    pub fn sync(&self, request_json: &str) -> String {
        match validate_request(request_json) {
            Ok(req) => {
                let admitted = self.clock.now_ms();
                let mut result = self.generate(req, Some(admitted), None);
                result.events.insert(0, LifecycleEvent::Admitted);
                self.encode(result)
            }
            Err(result) => self.encode(*result),
        }
    }
    pub fn submit(&self, request_json: &str) -> String {
        let req = match validate_request(request_json) {
            Ok(r) => r,
            Err(result) => return self.encode(*result),
        };
        let mut s = self.state.borrow_mut();
        if s.queue.len() >= QUEUE {
            return self.encode(failure(
                None,
                ProcgenFailureCode::Overload,
                "queue full",
                LifecycleEvent::Overloaded,
            ));
        }
        let id = match s.next_id.checked_add(1) {
            Some(next) => {
                let id = s.next_id;
                s.next_id = next;
                id
            }
            None => {
                return self.encode(failure(
                    None,
                    ProcgenFailureCode::Capacity,
                    "request id space exhausted",
                    LifecycleEvent::Rejected,
                ))
            }
        };
        s.highest_admitted = id;
        s.admitted_at.insert(id, self.clock.now_ms());
        s.queue.push_back(id);
        s.entries.insert(id, Entry::Queued(Box::new(req)));
        self.encode(LifecycleResult::accepted(
            id,
            vec![LifecycleEvent::Admitted, LifecycleEvent::Queued],
        ))
    }
    pub fn poll_request(&self, request_id: i64) -> String {
        if request_id <= 0 {
            return self.encode(failure(
                None,
                ProcgenFailureCode::UnknownRequest,
                "unknown request",
                LifecycleEvent::Rejected,
            ));
        }
        let entry = self.state.borrow_mut().entries.remove(&request_id);
        match entry {
            Some(Entry::Cancelled(mut result)) => {
                result.events.push(LifecycleEvent::ResultConsumed);
                let mut s = self.state.borrow_mut();
                tombstone(&mut s, request_id, ProcgenFailureCode::ResultConsumed);
                self.encode(*result)
            }
            Some(Entry::Queued(req)) => {
                let admitted = self.state.borrow_mut().admitted_at.remove(&request_id);
                self.state.borrow_mut().queue.retain(|id| *id != request_id);
                let mut result = self.generate(*req, admitted, Some(request_id));
                result.events.insert(0, LifecycleEvent::Queued);
                result.events.insert(0, LifecycleEvent::Admitted);
                result.events.push(LifecycleEvent::ResultConsumed);
                let mut s = self.state.borrow_mut();
                tombstone(&mut s, request_id, ProcgenFailureCode::ResultConsumed);
                self.encode(result)
            }
            None => {
                let s = self.state.borrow();
                let (code, message, event) = unavailable(&s, request_id);
                self.encode(failure(Some(request_id), code, message, event))
            }
        }
    }
    pub fn cancel_request(&self, request_id: i64) -> String {
        if request_id <= 0 {
            return self.encode(failure(
                None,
                ProcgenFailureCode::UnknownRequest,
                "unknown request",
                LifecycleEvent::Rejected,
            ));
        }
        let mut s = self.state.borrow_mut();
        match s.entries.get(&request_id).cloned() {
            Some(Entry::Cancelled(result)) => self.encode(*result),
            Some(Entry::Queued(_)) => {
                s.queue.retain(|id| *id != request_id);
                s.admitted_at.remove(&request_id);
                let result = LifecycleResult::failed(
                    Some(request_id),
                    ProcgenFailure {
                        schema_version: "procgen-failure-1".into(),
                        code: ProcgenFailureCode::Cancellation,
                        stage: "adapter".into(),
                        message: "cancelled".into(),
                        retryable: false,
                        fallback_id: None,
                    },
                    vec![
                        LifecycleEvent::Admitted,
                        LifecycleEvent::Queued,
                        LifecycleEvent::CancelRequested,
                        LifecycleEvent::Cancelled,
                    ],
                );
                retain_cancelled(&mut s, request_id, result.clone());
                self.encode(result)
            }
            None => {
                let (code, message, event) = unavailable(&s, request_id);
                self.encode(failure(Some(request_id), code, message, event))
            }
        }
    }
    pub fn reset(&self) {
        *self.state.borrow_mut() = State::default();
    }
}

thread_local! { static SERVICE: RefCell<WasmService> = RefCell::new(WasmService::default()); }

#[wasm_bindgen]
pub fn generate_bundle(request_json: &str) -> String {
    SERVICE.with(|service| service.borrow().sync(request_json))
}
#[wasm_bindgen]
pub fn generate_bundle_async(request_json: &str) -> String {
    SERVICE.with(|service| service.borrow().submit(request_json))
}
#[wasm_bindgen]
pub fn poll(request_id: i64) -> String {
    if request_id <= 0 {
        return json(failure(
            None,
            ProcgenFailureCode::UnknownRequest,
            "unknown request",
            LifecycleEvent::Rejected,
        ));
    }
    SERVICE.with(|service| service.borrow().poll_request(request_id))
}
#[wasm_bindgen]
pub fn cancel(request_id: i64) -> String {
    if request_id <= 0 {
        return json(failure(
            None,
            ProcgenFailureCode::UnknownRequest,
            "unknown request",
            LifecycleEvent::Rejected,
        ));
    }
    SERVICE.with(|service| service.borrow().cancel_request(request_id))
}
#[wasm_bindgen]
pub fn capabilities() -> String {
    json_capabilities(capabilities_value())
}
#[wasm_bindgen]
pub fn generator_manifest() -> String {
    let value = manifest_value();
    if value.validate().is_err() {
        return json_fallback();
    }
    to_string(&value).unwrap_or_else(|_| json_fallback())
}
fn json_capabilities(value: ProcgenCapabilities) -> String {
    if value.validate().is_err() {
        return json_fallback();
    }
    to_string(&value).unwrap_or_else(|_| json_fallback())
}

#[cfg(test)]
mod tests {
    use super::*;
    use derelict_core::procgen::{
        PlayerModel, PresentationRequest, SiteRequest, PROCGEN_REQUEST_SCHEMA,
    };

    fn request_json() -> String {
        serde_json::to_string(&ProcgenRequest {
            schema_version: PROCGEN_REQUEST_SCHEMA.into(),
            world_seed: 42,
            site: SiteRequest {
                site_id: "site-a".into(),
                x: 1,
                y: 2,
                archetype_id: "shuttle".into(),
                kit_id: "default".into(),
                intactness_override_bp: None,
                cause_of_loss: None,
                loot_richness_bp: 10_000,
            },
            difficulty_id: "standard".into(),
            player_model: PlayerModel {
                schema_version: "player-model-1".into(),
                signals: vec![],
            },
            requested_domains: vec![
                Domain::World,
                Domain::Site,
                Domain::Gameplay,
                Domain::Presentation,
            ],
            generator_version: 2,
            content_manifest_hash: "0".repeat(64),
            presentation: PresentationRequest {
                seed: 1,
                locale: "en-US".into(),
            },
        })
        .unwrap()
    }
    #[test]
    fn capabilities_are_cooperative() {
        let c = capabilities_value();
        assert_eq!(c.worker_count, 0);
        assert_eq!(c.worker_mode, WorkerMode::Cooperative);
        c.validate().unwrap();
    }
    #[test]
    fn manifest_round_trips() {
        let m = manifest_value();
        assert_eq!(m.target, "wasm32-unknown-unknown");
        assert!(m.validate().is_ok());
    }

    #[test]
    fn invalid_requests_do_not_consume_ids_or_queue_slots() {
        let service = WasmService::default();
        let first = service.submit("not-json");
        assert!(first.contains("invalid_request"));
        assert!(service.submit(&request_json()).contains("\"request_id\":1"));
    }

    #[test]
    fn injected_services_have_isolated_lifecycle_state() {
        let left = WasmService::default();
        let right = WasmService::default();
        assert!(left.submit(&request_json()).contains("\"request_id\":1"));
        assert!(right.submit(&request_json()).contains("\"request_id\":1"));
        assert!(left.poll_request(1).contains("result_consumed"));
        assert!(right.poll_request(1).contains("result_consumed"));
    }

    #[test]
    fn lifecycle_events_preserve_admission_queue_and_consumption_order() {
        let service = WasmService::default();
        let accepted = service.submit(&request_json());
        assert!(accepted.find("admitted").unwrap() < accepted.find("queued").unwrap());
        let terminal = service.poll_request(1);
        assert!(terminal.find("admitted").unwrap() < terminal.find("queued").unwrap());
        assert!(terminal.find("started").unwrap() < terminal.find("result_consumed").unwrap());
        assert!(service.poll_request(1).contains("result_consumed"));
    }

    #[test]
    fn malformed_and_future_ids_are_stable_typed_failures() {
        let service = WasmService::default();
        assert!(service.poll_request(i64::MAX).contains("unknown_request"));
        assert!(service.cancel_request(-1).contains("unknown_request"));
    }
}
