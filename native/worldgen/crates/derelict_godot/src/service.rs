//! Bounded, target-neutral native generation service.
use derelict_core::lifecycle::{LifecycleEvent, LifecycleResult};
use derelict_core::procgen::{ProcgenBundle, ProcgenFailure, ProcgenFailureCode, ProcgenRequest};
use std::collections::{BTreeMap, VecDeque};
use std::panic::AssertUnwindSafe;
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Instant;

const MAX_WORKERS: usize = 2;
const MAX_QUEUE_CAPACITY: usize = 8;
const MAX_RETAINED_RESULTS: usize = 16;
const MAX_REQUEST_BYTES: usize = 64 * 1024;
const MAX_ENTITIES: usize = 4096;
const MAX_TRACE_ENTRIES: usize = 4096;
const MAX_EVENTS: usize = 32;
const MAX_DEADLINE_MS: u64 = 2000;

pub trait MonotonicClock: Send + Sync {
    fn now_ms(&self) -> u64;
}
pub struct SystemClock(Instant);
impl Default for SystemClock {
    fn default() -> Self {
        Self(Instant::now())
    }
}
impl MonotonicClock for SystemClock {
    fn now_ms(&self) -> u64 {
        self.0.elapsed().as_millis() as u64
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Limits {
    pub workers: usize,
    pub queue_capacity: usize,
    pub retained_results: usize,
    pub max_request_bytes: usize,
    pub max_entities: usize,
    pub max_trace_entries: usize,
    pub max_events: usize,
    pub deadline_ms: u64,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            workers: 2,
            queue_capacity: 8,
            retained_results: 16,
            max_request_bytes: 64 * 1024,
            max_entities: 4096,
            max_trace_entries: 4096,
            max_events: 32,
            deadline_ms: 2000,
        }
    }
}
impl Limits {
    pub(crate) fn valid(&self) -> bool {
        (1..=MAX_WORKERS).contains(&self.workers)
            && (1..=MAX_QUEUE_CAPACITY).contains(&self.queue_capacity)
            && (1..=MAX_RETAINED_RESULTS).contains(&self.retained_results)
            && (1..=MAX_REQUEST_BYTES).contains(&self.max_request_bytes)
            && (1..=MAX_ENTITIES).contains(&self.max_entities)
            && (1..=MAX_TRACE_ENTRIES).contains(&self.max_trace_entries)
            && (1..=MAX_EVENTS).contains(&self.max_events)
            && (1..=MAX_DEADLINE_MS).contains(&self.deadline_ms)
    }
}
pub type Generator =
    Arc<dyn Fn(ProcgenRequest) -> Result<ProcgenBundle, ProcgenFailure> + Send + Sync + 'static>;
#[cfg(test)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum AdmissionOperation {
    SubmitJson,
    Submit,
    GenerateSyncJson,
    GenerateSync,
    Shutdown,
}
#[cfg(test)]
type AdmissionHook = Arc<dyn Fn(AdmissionOperation) + Send + Sync>;
#[derive(Clone)]
struct Job {
    request: ProcgenRequest,
    admitted_ms: u64,
    cancel_requested: bool,
    events: Vec<LifecycleEvent>,
}
#[allow(clippy::large_enum_variant)]
enum Entry {
    Queued(Job),
    Running(Job),
    Terminal(LifecycleResult),
}
#[derive(Clone, Copy)]
enum Tombstone {
    Consumed,
    Expired,
}
struct State {
    next_id: i64,
    first_admitted: Option<i64>,
    highest_admitted: i64,
    queue: VecDeque<i64>,
    entries: BTreeMap<i64, Entry>,
    tombstones: BTreeMap<i64, Tombstone>,
    shutdown: bool,
}
struct Shared {
    state: Mutex<State>,
    wake: Condvar,
}
pub struct Service {
    shared: Arc<Shared>,
    admission: Mutex<()>,
    #[cfg(test)]
    admission_hook: Mutex<Option<AdmissionHook>>,
    limits: Limits,
    clock: Arc<dyn MonotonicClock>,
    expected_content_hash: String,
    generator: Generator,
    workers: Mutex<Vec<JoinHandle<()>>>,
}
fn failure(code: ProcgenFailureCode, message: impl Into<String>) -> ProcgenFailure {
    ProcgenFailure {
        schema_version: "procgen-failure-1".into(),
        code,
        stage: "lifecycle".into(),
        message: message.into(),
        retryable: false,
        fallback_id: None,
    }
}
fn events(mut e: Vec<LifecycleEvent>, max: usize, x: LifecycleEvent) -> Vec<LifecycleEvent> {
    e.push(x);
    if e.len() > max {
        let excess = e.len() - max;
        e.drain(..excess);
    }
    e
}
fn limit_events(mut events: Vec<LifecycleEvent>, max: usize) -> Vec<LifecycleEvent> {
    if events.len() > max {
        let excess = events.len() - max;
        events.drain(..excess);
    }
    events
}
fn lifecycle_events(max: usize, final_event: LifecycleEvent) -> Vec<LifecycleEvent> {
    events(
        events(vec![LifecycleEvent::Admitted], max, LifecycleEvent::Started),
        max,
        final_event,
    )
}
fn bundle_ok(b: &ProcgenBundle, l: &Limits) -> bool {
    b.validate().is_ok()
        && b.site_ir.ship.entities.len() <= l.max_entities
        && b.trace.rng_channels.len() <= l.max_trace_entries
        && b.trace.candidate_decisions.len() <= l.max_trace_entries
        && b.trace.failed_constraints.len() <= l.max_trace_entries
        && b.trace.repairs.len() <= l.max_trace_entries
        && b.trace.retries.len() <= l.max_trace_entries
        && b.trace.stage_timings_micros.len() <= l.max_trace_entries
}
fn sanitize_failure(value: ProcgenFailure) -> ProcgenFailure {
    if value.validate().is_ok() {
        value
    } else {
        failure(
            ProcgenFailureCode::InternalFailure,
            "generator returned an invalid failure contract",
        )
    }
}
fn record_tombstone(s: &mut State, l: &Limits, id: i64, kind: Tombstone) {
    s.tombstones.insert(id, kind);
    prune_tombstones(s, l);
}
fn retain(s: &mut State, l: &Limits, id: i64, result: LifecycleResult) {
    s.entries.insert(id, Entry::Terminal(result));
    while s
        .entries
        .values()
        .filter(|v| matches!(v, Entry::Terminal(_)))
        .count()
        > l.retained_results
    {
        if let Some(old) = s
            .entries
            .keys()
            .copied()
            .find(|k| matches!(s.entries.get(k), Some(Entry::Terminal(_))))
        {
            s.entries.remove(&old);
            record_tombstone(s, l, old, Tombstone::Expired);
        }
    }
}
fn prune_tombstones(s: &mut State, l: &Limits) {
    while s.tombstones.len() > l.retained_results {
        if let Some(old) = s.tombstones.keys().next().copied() {
            s.tombstones.remove(&old);
        } else {
            break;
        }
    }
}
#[allow(dead_code)]
impl Service {
    pub fn new(
        limits: Limits,
        clock: Arc<dyn MonotonicClock>,
        expected_content_hash: String,
        generator: Generator,
    ) -> Arc<Self> {
        Self::new_with_next_id(limits, clock, expected_content_hash, generator, 1)
    }
    pub fn new_with_next_id(
        limits: Limits,
        clock: Arc<dyn MonotonicClock>,
        expected_content_hash: String,
        generator: Generator,
        next_id: i64,
    ) -> Arc<Self> {
        assert!(limits.valid() && next_id > 0);
        let service = Arc::new(Self {
            shared: Arc::new(Shared {
                state: Mutex::new(State {
                    next_id,
                    first_admitted: None,
                    highest_admitted: 0,
                    queue: VecDeque::new(),
                    entries: BTreeMap::new(),
                    tombstones: BTreeMap::new(),
                    shutdown: false,
                }),
                wake: Condvar::new(),
            }),
            admission: Mutex::new(()),
            #[cfg(test)]
            admission_hook: Mutex::new(None),
            limits,
            clock,
            expected_content_hash,
            generator,
            workers: Mutex::new(Vec::new()),
        });
        service.start_workers();
        service
    }
    fn start_workers(self: &Arc<Self>) {
        let mut handles = self.workers.lock().unwrap();
        for _ in 0..self.limits.workers {
            let shared = Arc::clone(&self.shared);
            let limits = self.limits.clone();
            let clock = Arc::clone(&self.clock);
            let generator = Arc::clone(&self.generator);
            handles.push(thread::spawn(move || {
                worker(shared, limits, clock, generator)
            }));
        }
    }
    fn failed(
        &self,
        id: Option<i64>,
        f: ProcgenFailure,
        e: Vec<LifecycleEvent>,
    ) -> LifecycleResult {
        LifecycleResult::failed(id, f, limit_events(e, self.limits.max_events))
    }
    fn validate_request(
        &self,
        request: &ProcgenRequest,
        raw_len: usize,
    ) -> Result<(), ProcgenFailure> {
        if raw_len > self.limits.max_request_bytes {
            return Err(failure(ProcgenFailureCode::Capacity, "request too large"));
        }
        request
            .validate()
            .map_err(|e| failure(ProcgenFailureCode::InvalidRequest, e.to_string()))?;
        if request.content_manifest_hash != self.expected_content_hash {
            return Err(failure(
                ProcgenFailureCode::GeneratorContentMismatch,
                "content manifest mismatch",
            ));
        }
        Ok(())
    }
    fn is_shutdown(&self) -> bool {
        self.shared.state.lock().unwrap().shutdown
    }
    #[cfg(test)]
    fn run_admission_hook(&self, operation: AdmissionOperation) {
        let hook = self.admission_hook.lock().unwrap().clone();
        if let Some(hook) = hook {
            hook(operation);
        }
    }
    #[cfg(test)]
    pub(crate) fn set_admission_hook(&self, hook: AdmissionHook) {
        *self.admission_hook.lock().unwrap() = Some(hook);
    }
    #[cfg(test)]
    pub(crate) fn wait_terminal_for_test(&self, id: i64, timeout: std::time::Duration) -> bool {
        let state = self.shared.state.lock().unwrap();
        let (state, _) = self
            .shared
            .wake
            .wait_timeout_while(state, timeout, |state| {
                !matches!(state.entries.get(&id), Some(Entry::Terminal(_)))
            })
            .unwrap();
        matches!(state.entries.get(&id), Some(Entry::Terminal(_)))
    }
    fn admit(&self, request: ProcgenRequest, raw_len: usize) -> LifecycleResult {
        let mut s = self.shared.state.lock().unwrap();
        if s.shutdown {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Shutdown, "service is shut down"),
                vec![LifecycleEvent::Rejected, LifecycleEvent::Shutdown],
            );
        }
        if let Err(f) = self.validate_request(&request, raw_len) {
            return self.failed(None, f, vec![LifecycleEvent::Rejected]);
        }
        if s.queue.len() >= self.limits.queue_capacity {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Overload, "queue full"),
                vec![LifecycleEvent::Rejected, LifecycleEvent::Overloaded],
            );
        }
        if s.next_id <= 0 {
            return self.failed(
                None,
                failure(ProcgenFailureCode::InternalFailure, "request id exhausted"),
                vec![LifecycleEvent::Rejected],
            );
        }
        let id = s.next_id;
        s.next_id = if id == i64::MAX { 0 } else { id + 1 };
        s.first_admitted.get_or_insert(id);
        s.highest_admitted = id;
        let ev = events(
            vec![LifecycleEvent::Admitted],
            self.limits.max_events,
            LifecycleEvent::Queued,
        );
        s.queue.push_back(id);
        s.entries.insert(
            id,
            Entry::Queued(Job {
                request,
                admitted_ms: self.clock.now_ms(),
                cancel_requested: false,
                events: ev.clone(),
            }),
        );
        self.shared.wake.notify_one();
        LifecycleResult::accepted(id, ev)
    }
    pub fn submit_json(&self, json: &str) -> LifecycleResult {
        let _admission = self.admission.lock().unwrap();
        #[cfg(test)]
        self.run_admission_hook(AdmissionOperation::SubmitJson);
        if self.is_shutdown() {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Shutdown, "service is shut down"),
                vec![LifecycleEvent::Rejected, LifecycleEvent::Shutdown],
            );
        }
        if json.len() > self.limits.max_request_bytes {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Capacity, "request too large"),
                vec![LifecycleEvent::Rejected],
            );
        }
        match ProcgenRequest::from_json(json) {
            Ok(r) => self.admit(r, json.len()),
            Err(e) => self.failed(
                None,
                failure(ProcgenFailureCode::InvalidRequest, e.to_string()),
                vec![LifecycleEvent::Rejected],
            ),
        }
    }
    pub(crate) fn submit(&self, request: ProcgenRequest) -> LifecycleResult {
        let _admission = self.admission.lock().unwrap();
        #[cfg(test)]
        self.run_admission_hook(AdmissionOperation::Submit);
        let raw_len = serde_json::to_vec(&request)
            .map(|v| v.len())
            .unwrap_or(usize::MAX);
        self.admit(request, raw_len)
    }
    pub fn generate_sync_json(&self, json: &str) -> LifecycleResult {
        let _admission = self.admission.lock().unwrap();
        #[cfg(test)]
        self.run_admission_hook(AdmissionOperation::GenerateSyncJson);
        if self.is_shutdown() {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Shutdown, "service is shut down"),
                vec![LifecycleEvent::Rejected, LifecycleEvent::Shutdown],
            );
        }
        if json.len() > self.limits.max_request_bytes {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Capacity, "request too large"),
                vec![LifecycleEvent::Rejected],
            );
        }
        match ProcgenRequest::from_json(json) {
            Ok(r) => match self.validate_request(&r, json.len()) {
                Ok(()) => {
                    drop(_admission);
                    self.generate_sync_validated(r)
                }
                Err(failure) => self.failed(None, failure, vec![LifecycleEvent::Rejected]),
            },
            Err(e) => self.failed(
                None,
                failure(ProcgenFailureCode::InvalidRequest, e.to_string()),
                vec![LifecycleEvent::Rejected],
            ),
        }
    }
    pub(crate) fn generate_sync(&self, request: ProcgenRequest) -> LifecycleResult {
        let admission = self.admission.lock().unwrap();
        #[cfg(test)]
        self.run_admission_hook(AdmissionOperation::GenerateSync);
        if self.is_shutdown() {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Shutdown, "service is shut down"),
                vec![LifecycleEvent::Rejected, LifecycleEvent::Shutdown],
            );
        }
        let raw_len = serde_json::to_vec(&request)
            .map(|v| v.len())
            .unwrap_or(usize::MAX);
        match self.validate_request(&request, raw_len) {
            Ok(()) => {
                drop(admission);
                self.generate_sync_validated(request)
            }
            Err(failure) => self.failed(None, failure, vec![LifecycleEvent::Rejected]),
        }
    }
    fn generate_sync_validated(&self, request: ProcgenRequest) -> LifecycleResult {
        let start = self.clock.now_ms();
        let result = std::panic::catch_unwind(AssertUnwindSafe(|| (self.generator)(request)));
        if self.clock.now_ms().saturating_sub(start) >= self.limits.deadline_ms {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Timeout, "completion deadline exceeded"),
                lifecycle_events(self.limits.max_events, LifecycleEvent::TimedOut),
            );
        }
        match result {
            Ok(Ok(bundle)) => {
                if !bundle_ok(&bundle, &self.limits) {
                    self.failed(
                        None,
                        failure(ProcgenFailureCode::ValidationFailure, "invalid output"),
                        lifecycle_events(self.limits.max_events, LifecycleEvent::Failed),
                    )
                } else {
                    LifecycleResult::completed(
                        None,
                        bundle,
                        lifecycle_events(self.limits.max_events, LifecycleEvent::Completed),
                    )
                }
            }
            Ok(Err(f)) => self.failed(
                None,
                sanitize_failure(f),
                lifecycle_events(self.limits.max_events, LifecycleEvent::Failed),
            ),
            Err(_) => self.failed(
                None,
                failure(ProcgenFailureCode::InternalFailure, "generator panic"),
                lifecycle_events(self.limits.max_events, LifecycleEvent::Failed),
            ),
        }
    }
    pub fn poll(&self, id: i64) -> LifecycleResult {
        let mut s = self.shared.state.lock().unwrap();
        if id <= 0 {
            return self.failed(
                None,
                failure(ProcgenFailureCode::UnknownRequest, "unknown request"),
                vec![LifecycleEvent::Rejected],
            );
        }
        match s.entries.remove(&id) {
            Some(Entry::Terminal(mut r)) => {
                r.events = events(
                    r.events,
                    self.limits.max_events,
                    LifecycleEvent::ResultConsumed,
                );
                record_tombstone(&mut s, &self.limits, id, Tombstone::Consumed);
                r
            }
            Some(entry @ Entry::Queued(_)) => {
                s.entries.insert(id, entry);
                LifecycleResult::queued(
                    id,
                    events(
                        vec![LifecycleEvent::Admitted],
                        self.limits.max_events,
                        LifecycleEvent::Queued,
                    ),
                )
            }
            Some(Entry::Running(job)) => {
                let cancel = job.cancel_requested;
                let visible_events = job.events.clone();
                s.entries.insert(id, Entry::Running(job));
                if cancel {
                    LifecycleResult::cancel_requested(id, visible_events)
                } else {
                    LifecycleResult::running(id, visible_events)
                }
            }
            None => {
                let tombstone = s.tombstones.get(&id).copied();
                let admitted_but_aged = tombstone.is_none()
                    && s.first_admitted
                        .is_some_and(|first| id >= first && id <= s.highest_admitted);
                let code = if matches!(tombstone, Some(Tombstone::Consumed)) {
                    ProcgenFailureCode::ResultConsumed
                } else if matches!(tombstone, Some(Tombstone::Expired)) || admitted_but_aged {
                    ProcgenFailureCode::ResultExpired
                } else {
                    ProcgenFailureCode::UnknownRequest
                };
                let event = match code {
                    ProcgenFailureCode::ResultConsumed => LifecycleEvent::ResultConsumed,
                    ProcgenFailureCode::ResultExpired => LifecycleEvent::ResultExpired,
                    _ => LifecycleEvent::Rejected,
                };
                self.failed(Some(id), failure(code, "request unavailable"), vec![event])
            }
        }
    }
    pub fn cancel(&self, id: i64) -> LifecycleResult {
        let mut s = self.shared.state.lock().unwrap();
        if id <= 0 {
            return self.failed(
                None,
                failure(ProcgenFailureCode::UnknownRequest, "unknown request"),
                vec![LifecycleEvent::Rejected],
            );
        }
        match s.entries.remove(&id) {
            Some(Entry::Queued(mut job)) => {
                if let Some(p) = s.queue.iter().position(|x| *x == id) {
                    s.queue.remove(p);
                }
                job.events = events(
                    job.events,
                    self.limits.max_events,
                    LifecycleEvent::CancelRequested,
                );
                job.events = events(
                    job.events,
                    self.limits.max_events,
                    LifecycleEvent::Cancelled,
                );
                let r = self.failed(
                    Some(id),
                    failure(ProcgenFailureCode::Cancellation, "cancelled"),
                    job.events,
                );
                retain(&mut s, &self.limits, id, r.clone());
                self.shared.wake.notify_all();
                r
            }
            Some(Entry::Running(mut job)) => {
                if job.cancel_requested {
                    let out = LifecycleResult::cancel_requested(id, job.events.clone());
                    s.entries.insert(id, Entry::Running(job));
                    return out;
                }
                job.cancel_requested = true;
                job.events = events(
                    job.events,
                    self.limits.max_events,
                    LifecycleEvent::CancelRequested,
                );
                let out = LifecycleResult::cancel_requested(id, job.events.clone());
                s.entries.insert(id, Entry::Running(job));
                out
            }
            Some(Entry::Terminal(r)) => {
                if r.failure
                    .as_ref()
                    .is_some_and(|f| f.code == ProcgenFailureCode::Cancellation)
                {
                    let out = r.clone();
                    s.entries.insert(id, Entry::Terminal(r));
                    out
                } else {
                    let out = self.failed(
                        Some(id),
                        failure(ProcgenFailureCode::TooLateCancellation, "terminal result"),
                        vec![LifecycleEvent::Rejected],
                    );
                    s.entries.insert(id, Entry::Terminal(r));
                    out
                }
            }
            None => {
                let tombstone = s.tombstones.get(&id).copied();
                let admitted_but_aged = tombstone.is_none()
                    && s.first_admitted
                        .is_some_and(|first| id >= first && id <= s.highest_admitted);
                let code = if matches!(tombstone, Some(Tombstone::Consumed)) {
                    ProcgenFailureCode::ResultConsumed
                } else if matches!(tombstone, Some(Tombstone::Expired)) || admitted_but_aged {
                    ProcgenFailureCode::ResultExpired
                } else {
                    ProcgenFailureCode::UnknownRequest
                };
                let event = match code {
                    ProcgenFailureCode::ResultConsumed => LifecycleEvent::ResultConsumed,
                    ProcgenFailureCode::ResultExpired => LifecycleEvent::ResultExpired,
                    _ => LifecycleEvent::Rejected,
                };
                self.failed(Some(id), failure(code, "request unavailable"), vec![event])
            }
        }
    }
    pub fn shutdown(&self) {
        let admission = self.admission.lock().unwrap();
        #[cfg(test)]
        self.run_admission_hook(AdmissionOperation::Shutdown);
        let mut s = self.shared.state.lock().unwrap();
        if s.shutdown {
            drop(s);
            drop(admission);
            self.join_workers();
            return;
        }
        s.shutdown = true;
        while let Some(id) = s.queue.pop_front() {
            if let Some(Entry::Queued(job)) = s.entries.remove(&id) {
                retain(
                    &mut s,
                    &self.limits,
                    id,
                    self.failed(
                        Some(id),
                        failure(ProcgenFailureCode::Shutdown, "service shutdown"),
                        events(job.events, self.limits.max_events, LifecycleEvent::Shutdown),
                    ),
                );
            }
        }
        self.shared.wake.notify_all();
        drop(s);
        drop(admission);
        self.join_workers();
    }
    fn join_workers(&self) {
        let mut handles = self.workers.lock().unwrap();
        for h in handles.drain(..) {
            let _ = h.join();
        }
    }
}
fn worker(
    shared: Arc<Shared>,
    limits: Limits,
    clock: Arc<dyn MonotonicClock>,
    generator: Generator,
) {
    loop {
        let (id, job) = {
            let mut s = shared.state.lock().unwrap();
            loop {
                if s.shutdown && s.queue.is_empty() {
                    return;
                }
                if let Some(id) = s.queue.pop_front() {
                    let Some(Entry::Queued(mut job)) = s.entries.remove(&id) else {
                        continue;
                    };
                    if job.cancel_requested {
                        continue;
                    }
                    if clock.now_ms().saturating_sub(job.admitted_ms) >= limits.deadline_ms {
                        retain(
                            &mut s,
                            &limits,
                            id,
                            LifecycleResult::failed(
                                Some(id),
                                failure(ProcgenFailureCode::Timeout, "admission deadline exceeded"),
                                events(job.events, limits.max_events, LifecycleEvent::TimedOut),
                            ),
                        );
                        shared.wake.notify_all();
                        continue;
                    }
                    job.events = events(job.events, limits.max_events, LifecycleEvent::Started);
                    s.entries.insert(id, Entry::Running(job.clone()));
                    break (id, job);
                }
                s = shared.wake.wait(s).unwrap();
            }
        };
        let generated =
            std::panic::catch_unwind(AssertUnwindSafe(|| (generator)(job.request.clone())));
        let mut s = shared.state.lock().unwrap();
        let current = match s.entries.remove(&id) {
            Some(Entry::Running(j)) => j,
            _ => job.clone(),
        };
        let cancelled = current.cancel_requested;
        let result = if cancelled {
            LifecycleResult::failed(
                Some(id),
                failure(ProcgenFailureCode::Cancellation, "cancel requested"),
                events(
                    current.events.clone(),
                    limits.max_events,
                    LifecycleEvent::Cancelled,
                ),
            )
        } else if clock.now_ms().saturating_sub(job.admitted_ms) >= limits.deadline_ms {
            LifecycleResult::failed(
                Some(id),
                failure(ProcgenFailureCode::Timeout, "completion deadline exceeded"),
                events(
                    current.events.clone(),
                    limits.max_events,
                    LifecycleEvent::TimedOut,
                ),
            )
        } else {
            match generated {
                Ok(Ok(bundle)) if bundle_ok(&bundle, &limits) => LifecycleResult::completed(
                    Some(id),
                    bundle,
                    events(
                        current.events.clone(),
                        limits.max_events,
                        LifecycleEvent::Completed,
                    ),
                ),
                Ok(Ok(_)) => LifecycleResult::failed(
                    Some(id),
                    failure(ProcgenFailureCode::ValidationFailure, "invalid output"),
                    events(
                        current.events.clone(),
                        limits.max_events,
                        LifecycleEvent::Failed,
                    ),
                ),
                Ok(Err(f)) => LifecycleResult::failed(
                    Some(id),
                    sanitize_failure(f),
                    events(
                        current.events.clone(),
                        limits.max_events,
                        LifecycleEvent::Failed,
                    ),
                ),
                Err(_) => LifecycleResult::failed(
                    Some(id),
                    failure(ProcgenFailureCode::InternalFailure, "generator panic"),
                    events(
                        current.events.clone(),
                        limits.max_events,
                        LifecycleEvent::Failed,
                    ),
                ),
            }
        };
        retain(&mut s, &limits, id, result);
        shared.wake.notify_all();
    }
}
impl Drop for Service {
    fn drop(&mut self) {
        self.shutdown();
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dropping_last_service_owner_releases_worker_state() {
        let service = Service::new(
            Limits::default(),
            Arc::new(SystemClock::default()),
            "0".repeat(64),
            Arc::new(|_| Err(failure(ProcgenFailureCode::InternalFailure, "test"))),
        );
        let weak = Arc::downgrade(&service);
        drop(service);
        assert!(
            weak.upgrade().is_none(),
            "worker ownership cycle leaked Service"
        );
    }
}
