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
use wasm_bindgen::prelude::*;

const MAX_REQUEST: usize = 64 * 1024;
const MAX_ENTITIES: usize = 4096;
const MAX_TRACE: usize = 4096;
const MAX_EVENTS: usize = 32;
const QUEUE: usize = 8;
const RETAINED: usize = 16;
const CONTENT_HASH: &str = env!("SYNAPTIC_PROCGEN_CONTENT_MANIFEST_HASH");
const SOURCE_COMMIT: &str = env!("SYNAPTIC_PROCGEN_RUST_SOURCE_COMMIT");

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
}
impl Default for State {
    fn default() -> Self {
        Self {
            next_id: 1,
            queue: VecDeque::new(),
            entries: BTreeMap::new(),
            tombstones: BTreeMap::new(),
            data: None,
        }
    }
}
thread_local! { static STATE: RefCell<State> = RefCell::new(State::default()); }

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
    to_string(&result).expect("lifecycle result serializes")
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
            state
                .tombstones
                .insert(*oldest, ProcgenFailureCode::ResultExpired);
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
fn generate(req: ProcgenRequest) -> LifecycleResult {
    STATE.with(|cell| {
        let mut state = cell.borrow_mut();
        if state.data.is_none() {
            state.data = GenData::default_bundle().ok();
        }
        let Some(data) = state.data.as_ref() else {
            return failure(
                None,
                ProcgenFailureCode::AdapterFailure,
                "content data unavailable",
                LifecycleEvent::Failed,
            );
        };
        match core_generate_bundle(req, data) {
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
            Err(f) => LifecycleResult::failed(None, f, vec![LifecycleEvent::Failed]),
        }
    })
}

#[wasm_bindgen]
pub fn generate_bundle(request_json: &str) -> String {
    match validate_request(request_json) {
        Ok(req) => json(generate(req)),
        Err(result) => json(*result),
    }
}
#[wasm_bindgen]
pub fn generate_bundle_async(request_json: &str) -> String {
    let req = match validate_request(request_json) {
        Ok(r) => r,
        Err(result) => return json(*result),
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
        s.queue.push_back(id);
        s.entries.insert(id, Entry::Queued(Box::new(req)));
        json(LifecycleResult::accepted(
            id,
            vec![LifecycleEvent::Admitted, LifecycleEvent::Queued],
        ))
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
    STATE.with(|cell| {
        let mut s = cell.borrow_mut();
        match s.entries.remove(&request_id) {
            Some(Entry::Cancelled(result)) => {
                s.tombstones
                    .insert(request_id, ProcgenFailureCode::ResultConsumed);
                json(*result)
            }
            Some(Entry::Queued(req)) => {
                s.queue.retain(|id| *id != request_id);
                drop(s);
                let mut result = generate(*req);
                result.request_id = Some(request_id);
                STATE.with(|cell| {
                    cell.borrow_mut()
                        .tombstones
                        .insert(request_id, ProcgenFailureCode::ResultConsumed);
                });
                json(result)
            }
            None => json(failure(
                Some(request_id),
                s.tombstones
                    .get(&request_id)
                    .cloned()
                    .unwrap_or(ProcgenFailureCode::UnknownRequest),
                "request unavailable",
                LifecycleEvent::Rejected,
            )),
        }
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
    STATE.with(|cell| {
        let mut s = cell.borrow_mut();
        match s.entries.get(&request_id).cloned() {
            Some(Entry::Cancelled(result)) => json(*result),
            Some(Entry::Queued(_)) => {
                s.queue.retain(|id| *id != request_id);
                let result = failure(
                    Some(request_id),
                    ProcgenFailureCode::Cancellation,
                    "cancelled",
                    LifecycleEvent::Cancelled,
                );
                retain_cancelled(&mut s, request_id, result.clone());
                json(result)
            }
            None => json(failure(
                Some(request_id),
                s.tombstones
                    .get(&request_id)
                    .cloned()
                    .unwrap_or(ProcgenFailureCode::UnknownRequest),
                "request unavailable",
                LifecycleEvent::Rejected,
            )),
        }
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
