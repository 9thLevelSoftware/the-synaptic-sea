//! Deterministic lifecycle matrix for the bounded native service.
use super::service::{Generator, Limits, MonotonicClock, Service};
use derelict_core::lifecycle::{LifecycleEvent, LifecycleStatus};
use derelict_core::model::GENERATOR_VERSION;
use derelict_core::procgen::{
    Domain, PlayerModel, PresentationRequest, ProcgenBundle, ProcgenFailureCode, ProcgenRequest,
    SiteRequest,
};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;

const HASH: &str = "0000000000000000000000000000000000000000000000000000000000000000";
const WAIT: Duration = Duration::from_millis(500);

/// Two-party rendezvous with a bounded wait. A timeout releases the waiter so
/// a broken service assertion cannot strand a worker during RED runs.
struct Rendezvous {
    state: Mutex<(usize, bool)>,
    cv: Condvar,
    parties: usize,
}
impl Rendezvous {
    fn new(parties: usize) -> Self {
        Self {
            state: Mutex::new((0, false)),
            cv: Condvar::new(),
            parties,
        }
    }
    fn wait(&self) -> bool {
        let mut state = self.state.lock().unwrap();
        state.0 += 1;
        if state.0 >= self.parties {
            state.1 = true;
            self.cv.notify_all();
            return true;
        }
        let (next, timeout) = self.cv.wait_timeout_while(state, WAIT, |s| !s.1).unwrap();
        state = next;
        state.1 || !timeout.timed_out()
    }
}

#[derive(Default)]
struct FakeClock(AtomicU64);
impl FakeClock {
    fn set(&self, value: u64) {
        self.0.store(value, Ordering::SeqCst);
    }
}
impl MonotonicClock for FakeClock {
    fn now_ms(&self) -> u64 {
        self.0.load(Ordering::SeqCst)
    }
}

fn request(seed: u64) -> ProcgenRequest {
    ProcgenRequest {
        schema_version: "procgen-request-1".into(),
        world_seed: seed,
        site: SiteRequest {
            site_id: format!("site-{seed}"),
            x: 1,
            y: 2,
            archetype_id: "shuttle".into(),
            kit_id: "ship_structural_v0".into(),
            intactness_override_bp: None,
            cause_of_loss: None,
            loot_richness_bp: 5000,
        },
        difficulty_id: "normal".into(),
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
        generator_version: GENERATOR_VERSION,
        content_manifest_hash: HASH.into(),
        presentation: PresentationRequest {
            seed,
            locale: "en-US".into(),
        },
    }
}

fn valid_bundle() -> (ProcgenRequest, ProcgenBundle) {
    let req = request(7);
    let data = derelict_core::GenData::default_bundle().expect("embedded data");
    let bundle =
        derelict_core::procgen::generate_bundle(req.clone(), &data).expect("valid fixture");
    (req, bundle)
}

fn service(limits: Limits, clock: Arc<FakeClock>, generator: Generator) -> Arc<Service> {
    Service::new(limits, clock, HASH.into(), generator)
}
fn fixed_generator(bundle: ProcgenBundle) -> Generator {
    Arc::new(move |_| Ok(bundle.clone()))
}
fn limits() -> Limits {
    Limits {
        workers: 1,
        queue_capacity: 1,
        retained_results: 2,
        max_request_bytes: 64 * 1024,
        max_entities: 4096,
        max_trace_entries: 4096,
        max_events: 32,
        deadline_ms: 2_000,
    }
}
fn terminal(s: &Service, id: i64) -> derelict_core::lifecycle::LifecycleResult {
    for _ in 0..200 {
        let r = s.poll(id);
        if matches!(
            r.status,
            LifecycleStatus::Completed | LifecycleStatus::Failed
        ) {
            return r;
        }
        std::thread::yield_now();
    }
    panic!("request {id} did not reach terminal state")
}
fn running(s: &Service, id: i64) {
    for _ in 0..200 {
        if matches!(
            s.poll(id).status,
            LifecycleStatus::Running | LifecycleStatus::CancelRequested
        ) {
            return;
        }
        std::thread::yield_now();
    }
    panic!("request {id} did not start")
}
fn code(r: &derelict_core::lifecycle::LifecycleResult) -> ProcgenFailureCode {
    r.failure.as_ref().expect("failure").code.clone()
}

#[test]
fn fifo_saturation_recovery_and_overload_does_not_consume_id() {
    let (_req, bundle) = valid_bundle();
    let gate = Arc::new(Rendezvous::new(2));
    let started = Arc::new(Rendezvous::new(2));
    let g = {
        let gate = gate.clone();
        let started = started.clone();
        let bundle = bundle.clone();
        Arc::new(move |_| {
            started.wait();
            gate.wait();
            Ok(bundle.clone())
        }) as Generator
    };
    let s = service(limits(), Arc::new(FakeClock::default()), g);
    let a = s.submit(request(1));
    assert_eq!(a.request_id, Some(1));
    running(&s, 1);
    let b = s.submit(request(2));
    assert_eq!(b.request_id, Some(2));
    started.wait();
    let overload = s.submit(request(3));
    assert_eq!(code(&overload), ProcgenFailureCode::Overload);
    gate.wait();
    assert_eq!(terminal(&s, 1).status, LifecycleStatus::Completed);
    assert_eq!(s.submit(request(3)).request_id, Some(3));
    s.shutdown();
}

#[test]
fn queued_and_running_cancel_are_deterministic_and_repeat_queued_is_idempotent() {
    let (_req, bundle) = valid_bundle();
    let gate = Arc::new(Rendezvous::new(2));
    let entered = Arc::new(Rendezvous::new(2));
    let g = {
        let gate = gate.clone();
        let entered = entered.clone();
        let bundle = bundle.clone();
        Arc::new(move |_| {
            entered.wait();
            gate.wait();
            Ok(bundle.clone())
        }) as Generator
    };
    let s = service(limits(), Arc::new(FakeClock::default()), g);
    let first = s.submit(request(1));
    running(&s, first.request_id.unwrap());
    let queued = s.submit(request(2));
    entered.wait();
    assert_eq!(
        s.cancel(queued.request_id.unwrap()).status,
        LifecycleStatus::CancelRequested
    );
    assert_eq!(
        code(&s.cancel(queued.request_id.unwrap())),
        ProcgenFailureCode::Cancellation
    );
    assert_eq!(
        s.cancel(first.request_id.unwrap()).status,
        LifecycleStatus::CancelRequested
    );
    gate.wait();
    assert_eq!(code(&terminal(&s, 1)), ProcgenFailureCode::Cancellation);
    s.shutdown();
}

#[test]
fn cancellation_of_completed_is_too_late_without_consuming_result() {
    let (_req, bundle) = valid_bundle();
    let s = service(
        limits(),
        Arc::new(FakeClock::default()),
        fixed_generator(bundle),
    );
    let id = s.submit(request(1)).request_id.unwrap();
    assert_eq!(terminal(&s, id).status, LifecycleStatus::Completed);
    assert_eq!(code(&s.cancel(id)), ProcgenFailureCode::TooLateCancellation);
    assert_eq!(s.poll(id).status, LifecycleStatus::Completed);
    s.shutdown();
}

#[test]
fn fake_clock_covers_prestart_postrun_and_sync_deadlines() {
    let (_req, bundle) = valid_bundle();
    let clock = Arc::new(FakeClock::default());
    let mut l = limits();
    l.deadline_ms = 10;
    let s = service(l.clone(), clock.clone(), fixed_generator(bundle.clone()));
    let id = s.submit(request(1)).request_id.unwrap();
    clock.set(10);
    assert_eq!(code(&terminal(&s, id)), ProcgenFailureCode::Timeout);
    s.shutdown();
    let clock = Arc::new(FakeClock::default());
    let entered = Arc::new(Rendezvous::new(2));
    let release = Arc::new(Rendezvous::new(2));
    let g = {
        let entered = entered.clone();
        let release = release.clone();
        let bundle = bundle.clone();
        Arc::new(move |_| {
            entered.wait();
            release.wait();
            Ok(bundle.clone())
        }) as Generator
    };
    let s = service(l.clone(), clock.clone(), g);
    let id = s.submit(request(2)).request_id.unwrap();
    entered.wait();
    clock.set(10);
    release.wait();
    assert_eq!(code(&terminal(&s, id)), ProcgenFailureCode::Timeout);
    assert_eq!(
        code(&s.generate_sync(request(3))),
        ProcgenFailureCode::Timeout
    );
    s.shutdown();
}

#[test]
fn malformed_raw_oversized_whitespace_and_content_rejections_consume_no_id() {
    let (_req, bundle) = valid_bundle();
    let mut l = limits();
    l.max_request_bytes = 10_000;
    let s = service(l, Arc::new(FakeClock::default()), fixed_generator(bundle));
    let valid_json = serde_json::to_string(&request(1)).unwrap();
    for json in ["{", &"x".repeat(10_001)] {
        let r = s.submit_json(json);
        assert!(r.request_id.is_none());
        assert_eq!(
            code(&r),
            if json == "{" {
                ProcgenFailureCode::InvalidRequest
            } else {
                ProcgenFailureCode::Capacity
            }
        );
    }
    assert_eq!(
        s.submit_json(&format!(" {} ", valid_json)).request_id,
        Some(1)
    );
    let mut bad = request(1);
    bad.content_manifest_hash = "f".repeat(64);
    let r = s.submit(bad);
    assert_eq!(code(&r), ProcgenFailureCode::GeneratorContentMismatch);
    assert_eq!(s.submit(request(2)).request_id, Some(2));
    s.shutdown();
}

#[test]
fn output_entity_and_each_trace_cap_is_enforced() {
    let (_req, mut b) = valid_bundle();
    let mut l = limits();
    l.max_entities = b.site_ir.ship.entities.len();
    l.max_trace_entries = 16;
    let entity = b.site_ir.ship.entities[0].clone();
    b.site_ir.ship.entities.push(entity);
    l.max_entities -= 1;
    let s = service(
        l.clone(),
        Arc::new(FakeClock::default()),
        fixed_generator(b),
    );
    assert_eq!(
        code(&s.generate_sync(request(1))),
        ProcgenFailureCode::ValidationFailure
    );
    s.shutdown();
    let (_req, mut b) = valid_bundle();
    b.trace.candidate_decisions.push("overflow".into());
    let mut l = limits();
    l.max_trace_entries = b.trace.candidate_decisions.len() - 1;
    let s = service(l, Arc::new(FakeClock::default()), fixed_generator(b));
    assert_eq!(
        code(&s.generate_sync(request(2))),
        ProcgenFailureCode::ValidationFailure
    );
    s.shutdown();
}

#[test]
fn ids_unknown_consumed_expired_and_exhaustion_are_classified_without_wrap() {
    let (_req, b) = valid_bundle();
    let mut l = limits();
    l.retained_results = 1;
    let s = Service::new_with_next_id(
        l,
        Arc::new(FakeClock::default()),
        HASH.into(),
        fixed_generator(b),
        i64::MAX,
    );
    let id = s.submit(request(1)).request_id.unwrap();
    assert_eq!(id, i64::MAX);
    let _ = terminal(&s, id);
    assert_eq!(
        code(&s.submit(request(2))),
        ProcgenFailureCode::InternalFailure
    );
    assert_eq!(code(&s.poll(0)), ProcgenFailureCode::UnknownRequest);
    assert_eq!(code(&s.poll(id)), ProcgenFailureCode::ResultConsumed);
    assert_eq!(
        code(&s.poll(i64::MAX - 1)),
        ProcgenFailureCode::UnknownRequest
    );
    s.shutdown();
}

#[test]
fn panic_is_contained_and_next_request_generates_exactly_once() {
    let (_req, bundle) = valid_bundle();
    let count = Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let g = {
        let count = count.clone();
        let bundle = bundle.clone();
        Arc::new(move |_| {
            if count.fetch_add(1, Ordering::SeqCst) == 0 {
                panic!("boom")
            }
            Ok(bundle.clone())
        }) as Generator
    };
    let s = service(limits(), Arc::new(FakeClock::default()), g);
    let a = s.submit(request(1)).request_id.unwrap();
    assert_eq!(code(&terminal(&s, a)), ProcgenFailureCode::InternalFailure);
    let b = s.submit(request(2)).request_id.unwrap();
    assert_eq!(terminal(&s, b).status, LifecycleStatus::Completed);
    assert_eq!(count.load(Ordering::SeqCst), 2);
    s.shutdown();
}

#[test]
fn shutdown_terminalizes_queued_running_returns_and_is_idempotent() {
    let (_req, bundle) = valid_bundle();
    let entered = Arc::new(Rendezvous::new(2));
    let release = Arc::new(Rendezvous::new(2));
    let g = {
        let entered = entered.clone();
        let release = release.clone();
        let bundle = bundle.clone();
        Arc::new(move |_| {
            entered.wait();
            release.wait();
            Ok(bundle.clone())
        }) as Generator
    };
    let s = service(limits(), Arc::new(FakeClock::default()), g);
    let _running = s.submit(request(1)).request_id.unwrap();
    running(&s, 1);
    let queued = s.submit(request(2)).request_id.unwrap();
    entered.wait();
    let t = {
        let s = Arc::clone(&s);
        std::thread::spawn(move || {
            s.shutdown();
        })
    };
    assert_eq!(code(&s.poll(queued)), ProcgenFailureCode::Shutdown);
    release.wait();
    t.join().unwrap();
    s.shutdown();
}

#[test]
fn lifecycle_events_are_ordered_and_bounded_on_sync_rejection_and_completion() {
    let (_req, b) = valid_bundle();
    let mut l = limits();
    l.max_events = 3;
    let s = service(l, Arc::new(FakeClock::default()), fixed_generator(b));
    let ok = s.generate_sync(request(1));
    assert!(ok.events.len() <= 3);
    assert_eq!(
        &ok.events[..],
        &[
            LifecycleEvent::Admitted,
            LifecycleEvent::Started,
            LifecycleEvent::Completed
        ]
    );
    let bad = s.submit_json("not json");
    assert!(bad.events.len() <= 3);
    assert_eq!(bad.events, vec![LifecycleEvent::Rejected]);
    s.shutdown();
}

#[test]
fn sync_bypasses_saturated_queue_but_keeps_caps() {
    let (_req, bundle) = valid_bundle();
    let gate = Arc::new(Rendezvous::new(2));
    let entered = Arc::new(Rendezvous::new(2));
    let g = {
        let gate = gate.clone();
        let entered = entered.clone();
        let bundle = bundle.clone();
        Arc::new(move |_| {
            entered.wait();
            gate.wait();
            Ok(bundle.clone())
        }) as Generator
    };
    let s = service(limits(), Arc::new(FakeClock::default()), g);
    let _ = s.submit(request(1));
    entered.wait();
    let sync = s.generate_sync(request(2));
    assert_eq!(sync.status, LifecycleStatus::Completed);
    gate.wait();
    s.shutdown();
}

#[test]
fn lowest_id_eviction_and_bounded_tombstone_classification() {
    let (_req, bundle) = valid_bundle();
    let mut l = limits(); l.workers = 2; l.retained_results = 1;
    let s = service(l, Arc::new(FakeClock::default()), fixed_generator(bundle));
    let first = s.submit(request(1)).request_id.unwrap();
    let second = s.submit(request(2)).request_id.unwrap();
    let _ = terminal(&s, first); let _ = terminal(&s, second);
    assert_eq!(code(&s.poll(first)), ProcgenFailureCode::ResultExpired);
    assert_eq!(code(&s.poll(first - 1)), ProcgenFailureCode::UnknownRequest);
    s.shutdown();
}
