//! Cooperative WebAssembly adapter over the shared deterministic procgen core.
use derelict_core::lifecycle::{
    AdapterKind, AdapterSchemas, GeneratorManifest, LifecycleEvent, LifecycleResult,
    ProcgenCapabilities, WorkerMode, PROCGEN_CAPABILITIES_SCHEMA,
    PROCGEN_GENERATOR_MANIFEST_SCHEMA, PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3,
};
use derelict_core::manifest::ExportSchemas;
use derelict_core::procgen::{
    generate_bundle as core_generate_bundle, Domain, ProcgenFailure, ProcgenFailureCode,
    ProcgenRequest,
};
use derelict_core::world::PROCGEN_GENERATOR_VERSION;
use derelict_core::GenData;
use serde_json::to_string;
#[cfg(target_arch = "wasm32")]
use std::cell::Cell;
use std::cell::RefCell;
use std::collections::{BTreeMap, VecDeque};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::Arc;
#[cfg(not(target_arch = "wasm32"))]
use std::sync::OnceLock;
#[cfg(not(target_arch = "wasm32"))]
use std::time::Instant;
use wasm_bindgen::prelude::*;

#[cfg(test)]
#[path = "../build_support.rs"]
mod build_support_tests;

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
            thread_local! {
                static LAST_MS: Cell<u64> = const { Cell::new(0) };
            }
            let global = js_sys::global();
            let monotonic = js_sys::Reflect::get(&global, &JsValue::from_str("performance"))
                .ok()
                .and_then(|performance| {
                    js_sys::Reflect::get(&performance, &JsValue::from_str("now"))
                        .ok()
                        .and_then(|value| value.dyn_into::<js_sys::Function>().ok())
                        .and_then(|now| now.call0(&performance).ok())
                        .and_then(|value| value.as_f64())
                })
                .unwrap_or_else(js_sys::Date::now)
                .max(0.0) as u64;
            LAST_MS.with(|last| {
                let clamped = monotonic.max(last.get());
                last.set(clamped);
                clamped
            })
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
    id_space_exhausted: bool,
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
            id_space_exhausted: false,
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
    expected_content_hash: String,
    state: RefCell<State>,
}
impl Default for WasmService {
    fn default() -> Self {
        Self {
            clock: Arc::new(DefaultClock),
            data: Arc::new(DefaultData),
            generator: Arc::new(DefaultGenerator),
            serializer: Arc::new(JsonSerializer),
            expected_content_hash: CONTENT_HASH.into(),
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
        Self::new_with_content_hash(clock, data, generator, serializer, CONTENT_HASH.into())
    }

    pub fn new_with_content_hash(
        clock: Arc<dyn Clock>,
        data: Arc<dyn DataProvider>,
        generator: Arc<dyn Generator>,
        serializer: Arc<dyn Serializer>,
        expected_content_hash: String,
    ) -> Self {
        assert!(
            expected_content_hash.len() == 64
                && expected_content_hash
                    .bytes()
                    .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
        );
        Self {
            clock,
            data,
            generator,
            serializer,
            expected_content_hash,
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
    format!(
        r#"{{"schema_version":"{PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3}","status":"failed","request_id":null,"bundle":null,"failure":{{"schema_version":"procgen-failure-1","code":"adapter_failure","stage":"adapter","message":"serialization failure","retryable":false,"fallback_id":null}},"events":["failed"]}}"#
    )
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
fn validate_request(
    raw: &str,
    expected_content_hash: &str,
) -> Result<ProcgenRequest, Box<LifecycleResult>> {
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
    if req.content_manifest_hash != expected_content_hash {
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
        schema_version: PROCGEN_CAPABILITIES_SCHEMA.into(),
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
        schemas: AdapterSchemas::platform_v3(),
    }
}
fn manifest_value() -> GeneratorManifest {
    GeneratorManifest {
        schema_version: PROCGEN_GENERATOR_MANIFEST_SCHEMA.into(),
        rust_source_commit: SOURCE_COMMIT.into(),
        generator_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: CONTENT_HASH.into(),
        export_schemas: ExportSchemas::platform_v3(),
        adapter_schemas: AdapterSchemas::platform_v3(),
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
                match self.data.data() {
                    Ok(data) => state.data = Some(data),
                    Err(message) => {
                        return failure(
                            request_id,
                            ProcgenFailureCode::AdapterFailure,
                            &message,
                            LifecycleEvent::Failed,
                        )
                    }
                }
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
        match validate_request(request_json, &self.expected_content_hash) {
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
        let req = match validate_request(request_json, &self.expected_content_hash) {
            Ok(r) => r,
            Err(result) => return self.encode(*result),
        };
        let mut s = self.state.borrow_mut();
        if s.queue.len() >= QUEUE {
            let mut result = failure(
                None,
                ProcgenFailureCode::Overload,
                "queue full",
                LifecycleEvent::Overloaded,
            );
            result.events.insert(0, LifecycleEvent::Rejected);
            return self.encode(result);
        }
        if s.id_space_exhausted {
            return self.encode(failure(
                None,
                ProcgenFailureCode::Capacity,
                "request id space exhausted",
                LifecycleEvent::Rejected,
            ));
        }
        let id = s.next_id;
        if let Some(next) = id.checked_add(1) {
            s.next_id = next;
        } else {
            s.id_space_exhausted = true;
        }
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

    #[cfg(test)]
    fn set_next_id(&self, next_id: i64) {
        assert!(next_id > 0);
        let mut state = self.state.borrow_mut();
        state.next_id = next_id;
        state.id_space_exhausted = false;
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
    use derelict_core::model::{EntityKind, GENERATOR_VERSION};
    use derelict_core::procgen::{
        semantic_hash, PlayerModel, PresentationRequest, ProcgenBundle, SiteRequest,
        GENERATION_TRACE_SCHEMA, PROCGEN_BUNDLE_SCHEMA, PROCGEN_REQUEST_SCHEMA, SITE_IR_SCHEMA,
    };
    use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};

    fn request(seed: u64, content_hash: &str) -> ProcgenRequest {
        ProcgenRequest {
            schema_version: PROCGEN_REQUEST_SCHEMA.into(),
            world_seed: seed,
            site: SiteRequest {
                site_id: format!("site-{seed}"),
                x: 1,
                y: 2,
                archetype_id: "shuttle".into(),
                kit_id: "ship_structural_v0".into(),
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
            generator_version: PROCGEN_GENERATOR_VERSION,
            content_manifest_hash: content_hash.into(),
            presentation: PresentationRequest {
                seed,
                locale: "en-US".into(),
            },
        }
    }

    fn request_json() -> String {
        serde_json::to_string(&request(42, CONTENT_HASH)).unwrap()
    }

    fn parse(json: &str) -> LifecycleResult {
        LifecycleResult::from_json(json)
            .unwrap_or_else(|error| panic!("invalid lifecycle JSON ({error}): {json}"))
    }

    fn failure_code(result: &LifecycleResult) -> Option<ProcgenFailureCode> {
        result.failure.as_ref().map(|failure| failure.code.clone())
    }

    #[derive(Default)]
    struct ManualClock(AtomicU64);
    impl ManualClock {
        fn set(&self, value: u64) {
            self.0.store(value, Ordering::SeqCst);
        }
    }
    impl Clock for ManualClock {
        fn now_ms(&self) -> u64 {
            self.0.load(Ordering::SeqCst)
        }
    }

    type GeneratorFn =
        dyn Fn(ProcgenRequest, &GenData) -> Result<ProcgenBundle, ProcgenFailure> + Send + Sync;
    struct TestGenerator {
        calls: Arc<AtomicUsize>,
        generate_fn: Arc<GeneratorFn>,
    }
    impl Generator for TestGenerator {
        fn generate(
            &self,
            request: ProcgenRequest,
            data: &GenData,
        ) -> Result<ProcgenBundle, ProcgenFailure> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            (self.generate_fn)(request, data)
        }
    }
    fn test_generator<F>(generate_fn: F) -> (Arc<TestGenerator>, Arc<AtomicUsize>)
    where
        F: Fn(ProcgenRequest, &GenData) -> Result<ProcgenBundle, ProcgenFailure>
            + Send
            + Sync
            + 'static,
    {
        let calls = Arc::new(AtomicUsize::new(0));
        (
            Arc::new(TestGenerator {
                calls: Arc::clone(&calls),
                generate_fn: Arc::new(generate_fn),
            }),
            calls,
        )
    }

    fn service_with(
        clock: Arc<dyn Clock>,
        generator: Arc<dyn Generator>,
        data: Arc<dyn DataProvider>,
        serializer: Arc<dyn Serializer>,
    ) -> WasmService {
        WasmService::new_with_content_hash(clock, data, generator, serializer, CONTENT_HASH.into())
    }

    struct FailingData;
    impl DataProvider for FailingData {
        fn data(&self) -> Result<GenData, String> {
            Err("content load failed".into())
        }
    }

    struct FailingSerializer;
    impl Serializer for FailingSerializer {
        fn serialize(&self, _: &LifecycleResult) -> Result<String, String> {
            Err("serializer failed".into())
        }
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
        assert_eq!(m.schema_version, PROCGEN_GENERATOR_MANIFEST_SCHEMA);
        assert_eq!(m.generator_version, PROCGEN_GENERATOR_VERSION);
        assert_eq!(m.export_schemas, ExportSchemas::platform_v3());
        assert_eq!(m.adapter_schemas, AdapterSchemas::platform_v3());
        let capabilities_json = json_capabilities(capabilities_value());
        ProcgenCapabilities::from_json(&capabilities_json).unwrap();
        let parsed = GeneratorManifest::from_json(&generator_manifest()).unwrap();
        assert_eq!(parsed.schema_version, PROCGEN_GENERATOR_MANIFEST_SCHEMA);
        assert_eq!(parsed.generator_version, PROCGEN_GENERATOR_VERSION);
    }

    #[test]
    fn malformed_oversized_and_mismatched_requests_do_not_consume_ids() {
        let service = WasmService::default();
        assert_eq!(
            failure_code(&parse(&service.submit("not-json"))),
            Some(ProcgenFailureCode::InvalidRequest)
        );
        assert_eq!(
            failure_code(&parse(&service.submit(&"x".repeat(MAX_REQUEST + 1)))),
            Some(ProcgenFailureCode::Capacity)
        );
        let mismatched_hash = if CONTENT_HASH.bytes().all(|byte| byte == b'1') {
            "0".repeat(64)
        } else {
            "1".repeat(64)
        };
        let mismatch = serde_json::to_string(&request(7, &mismatched_hash)).unwrap();
        assert_eq!(
            failure_code(&parse(&service.submit(&mismatch))),
            Some(ProcgenFailureCode::GeneratorContentMismatch)
        );
        assert_eq!(parse(&service.submit(&request_json())).request_id, Some(1));
    }

    #[test]
    fn request_schema_substitution_and_unknown_fields_fail_closed() {
        let service = WasmService::default();
        let valid = request_json();

        let substituted_schema = valid.replace(
            "\"schema_version\":\"procgen-request-1\"",
            "\"schema_version\":\"procgen-request-2\"",
        );
        assert_eq!(
            failure_code(&parse(&service.sync(&substituted_schema))),
            Some(ProcgenFailureCode::InvalidRequest)
        );

        let mut with_unknown: serde_json::Value = serde_json::from_str(&valid).unwrap();
        with_unknown["unexpected"] = serde_json::Value::Bool(true);
        let with_unknown = serde_json::to_string(&with_unknown).unwrap();
        assert_eq!(
            failure_code(&parse(&service.sync(&with_unknown))),
            Some(ProcgenFailureCode::InvalidRequest)
        );
        assert_eq!(parse(&service.submit(&valid)).request_id, Some(1));
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
    fn queue_overload_is_deterministic_and_recovery_uses_id_nine() {
        let service = WasmService::default();
        for expected in 1..=QUEUE as i64 {
            assert_eq!(
                parse(&service.submit(&request_json())).request_id,
                Some(expected)
            );
        }
        let overload = parse(&service.submit(&request_json()));
        assert_eq!(failure_code(&overload), Some(ProcgenFailureCode::Overload));
        assert_eq!(
            overload.events,
            vec![LifecycleEvent::Rejected, LifecycleEvent::Overloaded]
        );
        assert_eq!(
            parse(&service.poll_request(1)).status,
            derelict_core::lifecycle::LifecycleStatus::Completed
        );
        assert_eq!(parse(&service.submit(&request_json())).request_id, Some(9));
    }

    #[test]
    fn sync_and_cooperative_poll_generate_once_with_matching_semantics() {
        let (generator, calls) = test_generator(core_generate_bundle);
        let service = service_with(
            Arc::new(ManualClock::default()),
            generator,
            Arc::new(DefaultData),
            Arc::new(JsonSerializer),
        );
        let sync = parse(&service.sync(&request_json()));
        let sync_bundle = sync.bundle.as_ref().expect("sync bundle");
        assert_eq!(sync.schema_version, PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3);
        assert_eq!(sync_bundle.schema_version, PROCGEN_BUNDLE_SCHEMA);
        assert_eq!(sync_bundle.world_ir.schema_version, "world-ir-2");
        assert_eq!(sync_bundle.site_ir.schema_version, SITE_IR_SCHEMA);
        assert_eq!(sync_bundle.trace.schema_version, GENERATION_TRACE_SCHEMA);
        assert_eq!(
            sync_bundle.site_ir.ship.generator_version,
            GENERATOR_VERSION
        );
        assert_eq!(
            sync_bundle.site_ir.ship.seed,
            sync_bundle.world_ir.site_seed
        );
        assert_eq!(
            sync.events,
            vec![
                LifecycleEvent::Admitted,
                LifecycleEvent::Started,
                LifecycleEvent::Completed
            ]
        );
        let accepted = parse(&service.submit(&request_json()));
        assert_eq!(
            accepted.events,
            vec![LifecycleEvent::Admitted, LifecycleEvent::Queued]
        );
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        let terminal = parse(&service.poll_request(1));
        let terminal_bundle = terminal.bundle.as_ref().expect("terminal bundle");
        assert_eq!(terminal.schema_version, PROCGEN_LIFECYCLE_RESULT_SCHEMA_V3);
        assert_eq!(terminal_bundle.schema_version, PROCGEN_BUNDLE_SCHEMA);
        assert_eq!(terminal_bundle.world_ir.schema_version, "world-ir-2");
        assert_eq!(terminal_bundle.site_ir.schema_version, SITE_IR_SCHEMA);
        assert_eq!(
            terminal_bundle.trace.schema_version,
            GENERATION_TRACE_SCHEMA
        );
        assert_eq!(
            terminal_bundle.site_ir.ship.generator_version,
            GENERATOR_VERSION
        );
        assert_eq!(
            terminal_bundle.site_ir.ship.seed,
            terminal_bundle.world_ir.site_seed
        );
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert_eq!(
            terminal.events,
            vec![
                LifecycleEvent::Admitted,
                LifecycleEvent::Queued,
                LifecycleEvent::Started,
                LifecycleEvent::Completed,
                LifecycleEvent::ResultConsumed
            ]
        );
        assert_eq!(sync_bundle.semantic_hash, terminal_bundle.semantic_hash);
        let consumed = parse(&service.poll_request(1));
        assert_eq!(
            failure_code(&consumed),
            Some(ProcgenFailureCode::ResultConsumed)
        );
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn queued_cancellation_is_idempotent_and_consumed_once() {
        let service = WasmService::default();
        service.submit(&request_json());
        let first = parse(&service.cancel_request(1));
        let second = parse(&service.cancel_request(1));
        assert_eq!(first, second);
        assert_eq!(
            first.events,
            vec![
                LifecycleEvent::Admitted,
                LifecycleEvent::Queued,
                LifecycleEvent::CancelRequested,
                LifecycleEvent::Cancelled
            ]
        );
        let consumed = parse(&service.poll_request(1));
        assert_eq!(
            consumed.events.last(),
            Some(&LifecycleEvent::ResultConsumed)
        );
        assert_eq!(
            failure_code(&parse(&service.cancel_request(1))),
            Some(ProcgenFailureCode::ResultConsumed)
        );
    }

    #[test]
    fn retained_cancellations_and_tombstones_are_bounded_and_decay_to_expired() {
        let service = WasmService::default();
        for id in 1..=17 {
            assert_eq!(parse(&service.submit(&request_json())).request_id, Some(id));
            service.cancel_request(id);
        }
        assert_eq!(
            failure_code(&parse(&service.poll_request(1))),
            Some(ProcgenFailureCode::ResultExpired)
        );
        for id in 2..=17 {
            service.poll_request(id);
        }
        assert_eq!(
            failure_code(&parse(&service.poll_request(1))),
            Some(ProcgenFailureCode::ResultExpired)
        );
        let state = service.state.borrow();
        assert!(state.entries.len() <= RETAINED);
        assert!(state.tombstones.len() <= RETAINED);
        assert!(state.queue.is_empty());
        assert!(state.admitted_at.is_empty());
    }

    #[test]
    fn injected_clock_proves_prestart_and_postgeneration_deadlines() {
        let pre_clock = Arc::new(ManualClock::default());
        let (pre_generator, pre_calls) = test_generator(core_generate_bundle);
        let pre = service_with(
            pre_clock.clone(),
            pre_generator,
            Arc::new(DefaultData),
            Arc::new(JsonSerializer),
        );
        pre.submit(&request_json());
        pre_clock.set(2_000);
        let timed_out = parse(&pre.poll_request(1));
        assert_eq!(failure_code(&timed_out), Some(ProcgenFailureCode::Timeout));
        assert_eq!(pre_calls.load(Ordering::SeqCst), 0);

        let post_clock = Arc::new(ManualClock::default());
        let clock_for_generator = post_clock.clone();
        let (post_generator, post_calls) = test_generator(move |request, data| {
            let bundle = core_generate_bundle(request, data)?;
            clock_for_generator.set(2_000);
            Ok(bundle)
        });
        let post = service_with(
            post_clock,
            post_generator,
            Arc::new(DefaultData),
            Arc::new(JsonSerializer),
        );
        assert_eq!(
            failure_code(&parse(&post.sync(&request_json()))),
            Some(ProcgenFailureCode::Timeout)
        );
        assert_eq!(post_calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn panic_invalid_failure_and_data_errors_are_contained() {
        let (panic_generator, _) = test_generator(|_, _| panic!("boom"));
        let panic_service = service_with(
            Arc::new(ManualClock::default()),
            panic_generator,
            Arc::new(DefaultData),
            Arc::new(JsonSerializer),
        );
        assert_eq!(
            failure_code(&parse(&panic_service.sync(&request_json()))),
            Some(ProcgenFailureCode::InternalFailure)
        );

        let (bad_failure_generator, _) = test_generator(|_, _| {
            Err(ProcgenFailure {
                schema_version: "bad".into(),
                code: ProcgenFailureCode::GenerationFailure,
                stage: "generation".into(),
                message: "bad failure".into(),
                retryable: false,
                fallback_id: None,
            })
        });
        let bad_failure_service = service_with(
            Arc::new(ManualClock::default()),
            bad_failure_generator,
            Arc::new(DefaultData),
            Arc::new(JsonSerializer),
        );
        assert_eq!(
            failure_code(&parse(&bad_failure_service.sync(&request_json()))),
            Some(ProcgenFailureCode::AdapterFailure)
        );

        let (unused_generator, calls) = test_generator(core_generate_bundle);
        let data_service = service_with(
            Arc::new(ManualClock::default()),
            unused_generator,
            Arc::new(FailingData),
            Arc::new(JsonSerializer),
        );
        data_service.submit(&request_json());
        let failed = parse(&data_service.poll_request(1));
        assert_eq!(failed.request_id, Some(1));
        assert_eq!(
            failure_code(&failed),
            Some(ProcgenFailureCode::AdapterFailure)
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
    }

    #[test]
    fn invalid_bundle_trace_overflow_and_entity_overflow_fail_closed() {
        let (invalid_generator, _) = test_generator(|request, data| {
            let mut bundle = core_generate_bundle(request, data)?;
            bundle.semantic_hash = "f".repeat(64);
            Ok(bundle)
        });
        let invalid_service = service_with(
            Arc::new(ManualClock::default()),
            invalid_generator,
            Arc::new(DefaultData),
            Arc::new(JsonSerializer),
        );
        assert_eq!(
            failure_code(&parse(&invalid_service.sync(&request_json()))),
            Some(ProcgenFailureCode::ValidationFailure)
        );

        let (trace_generator, _) = test_generator(|request, data| {
            let mut bundle = core_generate_bundle(request, data)?;
            bundle.trace.candidate_decisions = vec!["candidate".into(); MAX_TRACE + 1];
            Ok(bundle)
        });
        let trace_service = service_with(
            Arc::new(ManualClock::default()),
            trace_generator,
            Arc::new(DefaultData),
            Arc::new(JsonSerializer),
        );
        assert_eq!(
            failure_code(&parse(&trace_service.sync(&request_json()))),
            Some(ProcgenFailureCode::ValidationFailure)
        );

        let (entity_generator, _) = test_generator(|request, data| {
            let mut bundle = core_generate_bundle(request, data)?;
            let mut entity = bundle.site_ir.ship.entities[0].clone();
            entity.kind = EntityKind::Furniture;
            entity.proto = "adapter-cap-probe".into();
            bundle.site_ir.ship.entities.clear();
            for id in 0..=MAX_ENTITIES as u32 {
                entity.id = id;
                bundle.site_ir.ship.entities.push(entity.clone());
            }
            bundle.gameplay_ir.legacy_slice = serde_json::from_value(
                derelict_core::structural::export::to_gameplay_slice_json(&bundle.site_ir.ship),
            )
            .unwrap();
            bundle.metrics.entity_count = bundle.site_ir.ship.entities.len() as u32;
            bundle.semantic_hash = semantic_hash(&bundle).unwrap();
            assert!(bundle.validate().is_ok());
            Ok(bundle)
        });
        let entity_service = service_with(
            Arc::new(ManualClock::default()),
            entity_generator,
            Arc::new(DefaultData),
            Arc::new(JsonSerializer),
        );
        assert_eq!(
            failure_code(&parse(&entity_service.sync(&request_json()))),
            Some(ProcgenFailureCode::Capacity)
        );
    }

    #[test]
    fn serialization_fallback_is_nonempty_and_typed() {
        let (generator, _) = test_generator(core_generate_bundle);
        let service = service_with(
            Arc::new(ManualClock::default()),
            generator,
            Arc::new(DefaultData),
            Arc::new(FailingSerializer),
        );
        let result = parse(&service.sync(&request_json()));
        assert_eq!(
            failure_code(&result),
            Some(ProcgenFailureCode::AdapterFailure)
        );
        assert!(!json_fallback().is_empty());
    }

    #[test]
    fn request_id_exhaustion_and_reset_are_deterministic() {
        let service = WasmService::default();
        service.set_next_id(i64::MAX);
        let first = parse(&service.submit(&request_json()));
        let second = parse(&service.submit(&request_json()));
        assert_eq!(first.request_id, Some(i64::MAX));
        assert!(first.failure.is_none());
        assert_eq!(failure_code(&second), Some(ProcgenFailureCode::Capacity));
        assert_eq!(
            parse(&service.poll_request(i64::MAX)).request_id,
            Some(i64::MAX)
        );
        service.reset();
        assert_eq!(parse(&service.submit(&request_json())).request_id, Some(1));
    }

    #[test]
    fn malformed_and_future_ids_are_stable_typed_failures() {
        let service = WasmService::default();
        assert_eq!(
            failure_code(&parse(&service.poll_request(i64::MAX))),
            Some(ProcgenFailureCode::UnknownRequest)
        );
        assert_eq!(
            failure_code(&parse(&service.cancel_request(-1))),
            Some(ProcgenFailureCode::UnknownRequest)
        );
    }
}
