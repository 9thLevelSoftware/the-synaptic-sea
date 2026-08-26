//! Bounded, target-neutral native generation service.
use derelict_core::lifecycle::{LifecycleEvent, LifecycleResult};
use derelict_core::procgen::{ProcgenBundle, ProcgenFailure, ProcgenFailureCode, ProcgenRequest};
use std::collections::{BTreeMap, VecDeque};
use std::panic::AssertUnwindSafe;
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::Instant;

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
    fn valid(&self) -> bool {
        self.workers > 0
            && self.queue_capacity > 0
            && self.retained_results > 0
            && self.max_request_bytes > 0
            && self.max_entities > 0
            && self.max_trace_entries > 0
            && self.max_events > 0
            && self.max_events <= 32
            && self.max_trace_entries <= 4096
            && self.deadline_ms > 0
    }
}
pub type Generator =
    Arc<dyn Fn(ProcgenRequest) -> Result<ProcgenBundle, ProcgenFailure> + Send + Sync + 'static>;
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
    if max == 0 {
        return e;
    }
    if e.len() >= max {
        e.remove(0);
    }
    e.push(x);
    e
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
            s.tombstones.insert(old, Tombstone::Expired);
        }
    }
    while s.tombstones.len() > l.retained_results {
        if let Some(old) = s.tombstones.keys().next().copied() {
            s.tombstones.remove(&old);
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
        LifecycleResult::failed(id, f, e)
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
    #[allow(clippy::needless_as_bytes)]
    pub fn submit_json(&self, json: &str) -> LifecycleResult {
        if json.as_bytes().len() > self.limits.max_request_bytes {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Capacity, "request too large"),
                vec![LifecycleEvent::Rejected],
            );
        }
        match ProcgenRequest::from_json(json) {
            Ok(r) => self.admit(r, json.as_bytes().len()),
            Err(e) => self.failed(
                None,
                failure(ProcgenFailureCode::InvalidRequest, e.to_string()),
                vec![LifecycleEvent::Rejected],
            ),
        }
    }
    pub fn submit(&self, request: ProcgenRequest) -> LifecycleResult {
        let raw_len = serde_json::to_vec(&request)
            .map(|v| v.len())
            .unwrap_or(usize::MAX);
        self.admit(request, raw_len)
    }
    #[allow(clippy::needless_as_bytes)]
    pub fn generate_sync_json(&self, json: &str) -> LifecycleResult {
        if json.as_bytes().len() > self.limits.max_request_bytes {
            return self.failed(
                None,
                failure(ProcgenFailureCode::Capacity, "request too large"),
                vec![LifecycleEvent::Rejected],
            );
        }
        match ProcgenRequest::from_json(json) {
            Ok(r) => self.generate_sync_with_len(r, json.as_bytes().len()),
            Err(e) => self.failed(
                None,
                failure(ProcgenFailureCode::InvalidRequest, e.to_string()),
                vec![LifecycleEvent::Rejected],
            ),
        }
    }
    pub fn generate_sync(&self, request: ProcgenRequest) -> LifecycleResult {
        let raw_len = serde_json::to_vec(&request)
            .map(|v| v.len())
            .unwrap_or(usize::MAX);
        self.generate_sync_with_len(request, raw_len)
    }
    fn generate_sync_with_len(&self, request: ProcgenRequest, raw_len: usize) -> LifecycleResult {
        if let Err(f) = self.validate_request(&request, raw_len) {
            return self.failed(None, f, vec![LifecycleEvent::Rejected]);
        }
        let start = self.clock.now_ms();
        let result = std::panic::catch_unwind(AssertUnwindSafe(|| (self.generator)(request)));
        match result {
            Ok(Ok(bundle)) => {
                if !bundle_ok(&bundle, &self.limits) {
                    self.failed(
                        None,
                        failure(ProcgenFailureCode::ValidationFailure, "invalid output"),
                        lifecycle_events(self.limits.max_events, LifecycleEvent::Failed),
                    )
                } else if self.clock.now_ms().saturating_sub(start) >= self.limits.deadline_ms {
                    self.failed(
                        None,
                        failure(ProcgenFailureCode::Timeout, "completion deadline exceeded"),
                        lifecycle_events(self.limits.max_events, LifecycleEvent::TimedOut),
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
                f,
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
                s.tombstones.insert(id, Tombstone::Consumed);
                prune_tombstones(&mut s, &self.limits);
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
                    LifecycleResult::cancel_requested(
                        id,
                        events(
                            visible_events,
                            self.limits.max_events,
                            LifecycleEvent::CancelRequested,
                        ),
                    )
                } else {
                    LifecycleResult::running(id, visible_events)
                }
            }
            None => {
                let tombstone = s.tombstones.get(&id).copied();
                let expired = tombstone.is_some()
                    || s.first_admitted
                        .is_some_and(|first| id >= first && id <= s.highest_admitted);
                self.failed(
                    Some(id),
                    failure(
                        if matches!(tombstone, Some(Tombstone::Consumed)) {
                            ProcgenFailureCode::ResultConsumed
                        } else if expired {
                            ProcgenFailureCode::ResultExpired
                        } else {
                            ProcgenFailureCode::UnknownRequest
                        },
                        "request unavailable",
                    ),
                    vec![if expired {
                        LifecycleEvent::ResultExpired
                    } else {
                        LifecycleEvent::Rejected
                    }],
                )
            }
        }
    }
    pub fn cancel(&self, id: i64) -> LifecycleResult {
        let mut s = self.shared.state.lock().unwrap();
        if id <= 0 {
            return self.failed(
                Some(id),
                failure(
                    if matches!(s.tombstones.get(&id), Some(Tombstone::Consumed)) {
                        ProcgenFailureCode::ResultConsumed
                    } else if s.tombstones.contains_key(&id) {
                        ProcgenFailureCode::ResultExpired
                    } else {
                        ProcgenFailureCode::UnknownRequest
                    },
                    "unknown request",
                ),
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
            None => self.failed(
                Some(id),
                failure(
                    if s.tombstones.contains_key(&id) {
                        ProcgenFailureCode::ResultExpired
                    } else {
                        ProcgenFailureCode::UnknownRequest
                    },
                    "unknown request",
                ),
                vec![LifecycleEvent::Rejected],
            ),
        }
    }
    pub fn shutdown(&self) {
        let mut s = self.shared.state.lock().unwrap();
        if s.shutdown {
            drop(s);
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
                    f,
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
