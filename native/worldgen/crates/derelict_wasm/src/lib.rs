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
        0
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
thread_local! { static STATE: RefCell<State> = RefCell::new(State::default()); }
thread_local! { static SERVICE: WasmService = WasmService::default(); }

pub struct WasmService {
    clock: Arc<dyn Clock>,
    data: Arc<dyn DataProvider>,
    generator: Arc<dyn Generator>,
    serializer: Arc<dyn Serializer>,
}
impl Default for WasmService {
    fn default() -> Self {
        Self {
            clock: Arc::new(DefaultClock),
            data: Arc::new(DefaultData),
            generator: Arc::new(DefaultGenerator),
            serializer: Arc::new(JsonSerializer),
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
        }
    }
    fn encode(&self, result: LifecycleResult) -> String {
        self.serializer
            .serialize(&result)
            .unwrap_or_else(|_| json_fallback())
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
            ProcgenFailureCode::UnknownRequest,
            "unknown request",
            LifecycleEvent::Rejected,
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
fn generate(
    service: &WasmService,
    req: ProcgenRequest,
    admitted_at: Option<u64>,
    request_id: Option<i64>,
) -> LifecycleResult {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        let start = service.clock.now_ms();
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
            state.data = service.data.data().ok();
        }
        let Some(data) = state.data.as_ref() else {
            return failure(
                None,
                ProcgenFailureCode::AdapterFailure,
                "content data unavailable",
                LifecycleEvent::Failed,
            );
        };
        let generated = catch_unwind(AssertUnwindSafe(|| service.generator.generate(req, data)));
        match generated {
            Err(_) => failure(
                request_id,
                ProcgenFailureCode::InternalFailure,
                "generator panicked",
                LifecycleEvent::Failed,
            ),
            Ok(Err(f)) => LifecycleResult::failed(request_id, f, vec![LifecycleEvent::Failed]),
            Ok(Ok(bundle))
                if bundle.validate().is_ok()
                    && bundle.site_ir.ship.entities.len() <= MAX_ENTITIES
                    && bundle.trace.rng_channels.len() <= MAX_TRACE
                    && bundle.trace.candidate_decisions.len() <= MAX_TRACE
                    && bundle.trace.failed_constraints.len() <= MAX_TRACE
                    && bundle.trace.repairs.len() <= MAX_TRACE
                    && bundle.trace.retries.len() <= MAX_TRACE
                    && bundle.trace.stage_timings_micros.len() <= MAX_TRACE =>
            {
                LifecycleResult::completed(
                    request_id,
                    bundle,
                    vec![LifecycleEvent::Started, LifecycleEvent::Completed],
                )
            }
            Ok(Ok(_)) => failure(
                request_id,
                ProcgenFailureCode::Capacity,
                "output exceeds adapter limits",
                LifecycleEvent::Failed,
            ),
            /*
            Ok(bundle)
                if bundle.site_ir.ship.entities.len() <= MAX_ENTITIES
                    && bundle.trace.candidate_decisions.len() <= MAX_TRACE
                    && bundle.trace.failed_constraints.len() <= MAX_TRACE
                    && bundle.trace.repairs.len() <= MAX_TRACE
                    && bundle.trace.retries.len() <= MAX_TRACE =>
            {
                LifecycleResult::completed(None, bundle, vec![LifecycleEvent::Completed])
            }
            Ok(_) => failure(
                None,
                ProcgenFailureCode::Capacity,
                "output exceeds adapter limits",
                LifecycleEvent::Failed,
            ),
            Err(f) => LifecycleResult::failed(request_id, f, vec![LifecycleEvent::Failed]), */
        }
    })
}

#[wasm_bindgen]
pub fn generate_bundle(request_json: &str) -> String {
    SERVICE.with(|service| match validate_request(request_json) {
        Ok(req) => service.encode(generate(service, req, None, None)),
        Err(result) => service.encode(*result),
    })
}
#[wasm_bindgen]
pub fn generate_bundle_async(request_json: &str) -> String {
    SERVICE.with(|service| {
        let req = match validate_request(request_json) {
            Ok(r) => r,
            Err(result) => return service.encode(*result),
        };
        STATE.with(|cell| {
            let mut s = cell.borrow_mut();
            if s.queue.len() >= QUEUE {
                return json(failure(
                    None,
                    ProcgenFailureCode::Overload,
                    "queue full",
                    LifecycleEvent::Overloaded,
                ));
            }
            let id = s.next_id;
            let Some(next_id) = s.next_id.checked_add(1) else {
                return json(failure(
                    None,
                    ProcgenFailureCode::Capacity,
                    "request id space exhausted",
                    LifecycleEvent::Rejected,
                ));
            };
            s.next_id = next_id;
            s.highest_admitted = id;
            s.admitted_at.insert(id, service.clock.now_ms());
            s.queue.push_back(id);
            s.entries.insert(id, Entry::Queued(Box::new(req)));
            service.encode(LifecycleResult::accepted(
                id,
                vec![LifecycleEvent::Admitted, LifecycleEvent::Queued],
            ))
        })
    })
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
    SERVICE.with(|service| {
        STATE.with(|cell| {
            let mut s = cell.borrow_mut();
            match s.entries.remove(&request_id) {
                Some(Entry::Cancelled(result)) => {
                    tombstone(&mut s, request_id, ProcgenFailureCode::ResultConsumed);
                    service.encode(*result)
                }
                Some(Entry::Queued(req)) => {
                    s.queue.retain(|id| *id != request_id);
                    let admitted = s.admitted_at.remove(&request_id);
                    drop(s);
                    let result = generate(service, *req, admitted, Some(request_id));
                    STATE.with(|cell| {
                        tombstone(
                            &mut cell.borrow_mut(),
                            request_id,
                            ProcgenFailureCode::ResultConsumed,
                        );
                    });
                    service.encode(result)
                }
                None => {
                    let (code, message, event) = unavailable(&s, request_id);
                    service.encode(failure(Some(request_id), code, message, event))
                }
            }
        })
    })
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
    SERVICE.with(|service| {
        STATE.with(|cell| {
            let mut s = cell.borrow_mut();
            match s.entries.get(&request_id).cloned() {
                Some(Entry::Cancelled(result)) => service.encode(*result),
                Some(Entry::Queued(_)) => {
                    s.queue.retain(|id| *id != request_id);
                    let result = failure(
                        Some(request_id),
                        ProcgenFailureCode::Cancellation,
                        "cancelled",
                        LifecycleEvent::Cancelled,
                    );
                    s.admitted_at.remove(&request_id);
                    retain_cancelled(&mut s, request_id, result.clone());
                    service.encode(result)
                }
                None => {
                    let (code, message, event) = unavailable(&s, request_id);
                    service.encode(failure(Some(request_id), code, message, event))
                }
            }
        })
    })
}
#[wasm_bindgen]
pub fn capabilities() -> String {
    json_capabilities(capabilities_value())
}
#[wasm_bindgen]
pub fn generator_manifest() -> String {
    to_string(&manifest_value()).expect("manifest serializes")
}
fn json_capabilities(value: ProcgenCapabilities) -> String {
    to_string(&value).expect("capabilities serialize")
}

#[cfg(test)]
mod tests {
    use super::*;
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
}
