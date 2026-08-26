//! Deterministic lifecycle tests. Gates are one-shot channels; no sleeps/barriers.
use super::service::{AdmissionOperation, Generator, Limits, MonotonicClock, Service};
use derelict_core::lifecycle::{LifecycleEvent, LifecycleResult, LifecycleStatus};
use derelict_core::procgen::{
    Domain, PlayerModel, PresentationRequest, ProcgenBundle, ProcgenFailure, ProcgenFailureCode,
    ProcgenRequest, SiteRequest, FAILURE_SCHEMA,
};
use derelict_core::world::PROCGEN_GENERATOR_VERSION;
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{mpsc, Arc, Condvar, Mutex};
use std::time::Duration;
const HASH: &str = "0000000000000000000000000000000000000000000000000000000000000000";
const WAIT: Duration = Duration::from_secs(2);
type GateReceivers = Arc<(Mutex<BTreeMap<u64, mpsc::Receiver<()>>>, Condvar)>;
type GatedGenerator = (Generator, mpsc::Receiver<u64>, GateReceivers);
#[derive(Default)]
struct Clock(AtomicU64);
impl Clock {
    fn set(&self, x: u64) {
        self.0.store(x, Ordering::SeqCst)
    }
    fn add(&self, x: u64) {
        self.0.fetch_add(x, Ordering::SeqCst);
    }
}
impl MonotonicClock for Clock {
    fn now_ms(&self) -> u64 {
        self.0.load(Ordering::SeqCst)
    }
}
fn req(seed: u64) -> ProcgenRequest {
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
        generator_version: PROCGEN_GENERATOR_VERSION,
        content_manifest_hash: HASH.into(),
        presentation: PresentationRequest {
            seed,
            locale: "en-US".into(),
        },
    }
}
fn bundle() -> ProcgenBundle {
    let r = req(7);
    derelict_core::procgen::generate_bundle(r, &derelict_core::GenData::default_bundle().unwrap())
        .unwrap()
}
fn lim() -> Limits {
    Limits {
        workers: 1,
        queue_capacity: 1,
        retained_results: 2,
        max_request_bytes: 65536,
        max_entities: 4096,
        max_trace_entries: 4096,
        max_events: 32,
        deadline_ms: 2000,
    }
}
fn fixed(b: ProcgenBundle) -> Generator {
    Arc::new(move |_| Ok(b.clone()))
}
fn service(l: Limits, c: Arc<Clock>, g: Generator) -> Arc<Service> {
    Service::new(l, c, HASH.into(), g)
}
fn code(r: &LifecycleResult) -> ProcgenFailureCode {
    r.failure.as_ref().unwrap().code.clone()
}
fn generated_failure(code: ProcgenFailureCode) -> ProcgenFailure {
    ProcgenFailure {
        schema_version: FAILURE_SCHEMA.into(),
        code,
        stage: "generation".into(),
        message: "generated failure".into(),
        retryable: false,
        fallback_id: None,
    }
}
fn poll_terminal(s: &Service, id: i64) -> LifecycleResult {
    assert!(
        s.wait_terminal_for_test(id, WAIT),
        "terminal state handoff timed out"
    );
    let result = s.poll(id);
    assert!(matches!(
        result.status,
        LifecycleStatus::Completed | LifecycleStatus::Failed
    ));
    result
}
fn recv<T>(r: &mpsc::Receiver<T>, what: &str) -> T {
    r.recv_timeout(WAIT)
        .unwrap_or_else(|_| panic!("timed out waiting for {what}"))
}
fn gated(b: ProcgenBundle) -> GatedGenerator {
    let (tx, started_rx) = mpsc::channel();
    let gates = Arc::new((Mutex::new(BTreeMap::new()), Condvar::new()));
    let map = gates.clone();
    let g = Arc::new(move |r: ProcgenRequest| {
        tx.send(r.world_seed).unwrap();
        let (available, ready) = &*map;
        let mut available = available.lock().unwrap();
        while !available.contains_key(&r.world_seed) {
            let (next, guard) = ready.wait_timeout(available, WAIT).unwrap();
            available = next;
            assert!(
                !guard.timed_out() || available.contains_key(&r.world_seed),
                "gate installation handoff timed out"
            );
        }
        let gate = available.remove(&r.world_seed).unwrap();
        drop(available);
        recv(&gate, "release");
        Ok(b.clone())
    }) as Generator;
    (g, started_rx, gates)
}
fn release(g: &GateReceivers, seed: u64) -> mpsc::Sender<()> {
    let (tx, rx) = mpsc::channel();
    let (available, ready) = &**g;
    available.lock().unwrap().insert(seed, rx);
    ready.notify_all();
    tx
}

#[test]
fn injected_limits_can_only_reduce_the_production_envelope() {
    let production = Limits::default();
    assert!(production.valid());

    let mut oversized = Vec::new();
    let mut limits = production.clone();
    limits.workers += 1;
    oversized.push(("workers", limits));
    let mut limits = production.clone();
    limits.queue_capacity += 1;
    oversized.push(("queue_capacity", limits));
    let mut limits = production.clone();
    limits.retained_results += 1;
    oversized.push(("retained_results", limits));
    let mut limits = production.clone();
    limits.max_request_bytes += 1;
    oversized.push(("max_request_bytes", limits));
    let mut limits = production.clone();
    limits.max_entities += 1;
    oversized.push(("max_entities", limits));
    let mut limits = production.clone();
    limits.max_trace_entries += 1;
    oversized.push(("max_trace_entries", limits));
    let mut limits = production.clone();
    limits.max_events += 1;
    oversized.push(("max_events", limits));
    let mut limits = production;
    limits.deadline_ms += 1;
    oversized.push(("deadline_ms", limits));

    for (field, limits) in oversized {
        assert!(!limits.valid(), "oversized {field} was accepted");
    }
}

#[test]
fn fifo_saturation_recovery_no_id_loss() {
    let (g, started, gates) = gated(bundle());
    let mut l = lim();
    l.queue_capacity = 2;
    let s = service(l, Arc::new(Clock::default()), g);
    assert_eq!(s.submit(req(1)).request_id, Some(1));
    assert_eq!(recv(&started, "seed1"), 1);
    assert_eq!(s.submit(req(2)).request_id, Some(2));
    assert_eq!(s.submit(req(3)).request_id, Some(3));
    assert_eq!(code(&s.submit(req(4))), ProcgenFailureCode::Overload);
    release(&gates, 1).send(()).unwrap();
    assert_eq!(recv(&started, "seed2"), 2);
    assert_eq!(poll_terminal(&s, 1).status, LifecycleStatus::Completed);
    release(&gates, 2).send(()).unwrap();
    assert_eq!(recv(&started, "seed3"), 3);
    assert_eq!(poll_terminal(&s, 2).status, LifecycleStatus::Completed);
    release(&gates, 3).send(()).unwrap();
    assert_eq!(poll_terminal(&s, 3).status, LifecycleStatus::Completed);
    assert_eq!(s.submit(req(4)).request_id, Some(4));
    assert_eq!(recv(&started, "seed4"), 4);
    release(&gates, 4).send(()).unwrap();
    assert_eq!(poll_terminal(&s, 4).status, LifecycleStatus::Completed);
    s.shutdown()
}
#[test]
fn cancel_queued_and_running_are_idempotent() {
    let (g, started, gates) = gated(bundle());
    let s = service(lim(), Arc::new(Clock::default()), g);
    s.submit(req(1));
    recv(&started, "seed1");
    let q = s.submit(req(2)).request_id.unwrap();
    let first_queued_cancel = s.cancel(q);
    assert_eq!(code(&first_queued_cancel), ProcgenFailureCode::Cancellation);
    assert_eq!(
        first_queued_cancel.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Queued,
            LifecycleEvent::CancelRequested,
            LifecycleEvent::Cancelled,
        ]
    );
    assert!(first_queued_cancel.validate().is_ok());
    let repeated_queued_cancel = s.cancel(q);
    assert_eq!(repeated_queued_cancel, first_queued_cancel);
    let queued_terminal = poll_terminal(&s, q);
    assert_eq!(code(&queued_terminal), ProcgenFailureCode::Cancellation);
    assert_eq!(
        queued_terminal.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Queued,
            LifecycleEvent::CancelRequested,
            LifecycleEvent::Cancelled,
            LifecycleEvent::ResultConsumed,
        ]
    );
    assert!(queued_terminal.validate().is_ok());
    let consumed_queued = s.poll(q);
    assert_eq!(code(&consumed_queued), ProcgenFailureCode::ResultConsumed);
    assert_eq!(consumed_queued.events, vec![LifecycleEvent::ResultConsumed]);
    assert!(consumed_queued.validate().is_ok());
    assert_eq!(s.submit(req(3)).request_id, Some(3));

    let first_running_cancel = s.cancel(1);
    assert_eq!(
        first_running_cancel.status,
        LifecycleStatus::CancelRequested
    );
    assert_eq!(
        first_running_cancel.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Queued,
            LifecycleEvent::Started,
            LifecycleEvent::CancelRequested,
        ]
    );
    assert!(first_running_cancel.validate().is_ok());
    let repeated_running_cancel = s.cancel(1);
    assert_eq!(repeated_running_cancel, first_running_cancel);
    release(&gates, 1).send(()).unwrap();
    let running_terminal = poll_terminal(&s, 1);
    assert_eq!(code(&running_terminal), ProcgenFailureCode::Cancellation);
    assert_eq!(
        running_terminal.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Queued,
            LifecycleEvent::Started,
            LifecycleEvent::CancelRequested,
            LifecycleEvent::Cancelled,
            LifecycleEvent::ResultConsumed,
        ]
    );
    assert!(running_terminal.validate().is_ok());
    assert_eq!(recv(&started, "seed3 after queue recovery"), 3);
    release(&gates, 3).send(()).unwrap();
    assert_eq!(poll_terminal(&s, 3).status, LifecycleStatus::Completed);
    s.shutdown()
}
#[test]
fn retained_terminal_cancel_does_not_consume() {
    let (g, started, gates) = gated(bundle());
    let mut l = lim();
    l.queue_capacity = 2;
    let s = service(l, Arc::new(Clock::default()), g);
    s.submit(req(1));
    recv(&started, "seed1");
    let sentinel = s.submit(req(2)).request_id.unwrap();
    release(&gates, 1).send(()).unwrap();
    assert_eq!(recv(&started, "sentinel"), 2);
    assert_eq!(code(&s.cancel(1)), ProcgenFailureCode::TooLateCancellation);
    assert_eq!(poll_terminal(&s, 1).status, LifecycleStatus::Completed);
    release(&gates, 2).send(()).unwrap();
    poll_terminal(&s, sentinel);
    s.shutdown()
}
#[test]
fn fake_clock_prestart_postrun_and_sync_deadlines() {
    let b = bundle();
    let c = Arc::new(Clock::default());
    let (g, started, gates) = gated(b.clone());
    let mut l = lim();
    l.deadline_ms = 10;
    let s = service(l.clone(), c.clone(), g);
    s.submit(req(1));
    recv(&started, "seed1");
    let q = s.submit(req(2)).request_id.unwrap();
    c.set(10);
    release(&gates, 1).send(()).unwrap();
    let postrun = poll_terminal(&s, 1);
    assert_eq!(code(&postrun), ProcgenFailureCode::Timeout);
    assert_eq!(
        postrun.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Queued,
            LifecycleEvent::Started,
            LifecycleEvent::TimedOut,
            LifecycleEvent::ResultConsumed,
        ]
    );
    assert!(postrun.validate().is_ok());
    let prestart = poll_terminal(&s, q);
    assert_eq!(code(&prestart), ProcgenFailureCode::Timeout);
    assert_eq!(
        prestart.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Queued,
            LifecycleEvent::TimedOut,
            LifecycleEvent::ResultConsumed,
        ]
    );
    assert!(prestart.validate().is_ok());
    assert!(
        started.try_recv().is_err(),
        "pre-start timeout unexpectedly invoked the generator"
    );
    s.shutdown();
    let c = Arc::new(Clock::default());
    let c2 = c.clone();
    let g = Arc::new(move |_| {
        c2.add(10);
        Ok(b.clone())
    }) as Generator;
    let s = service(l, c, g);
    let sync = s.generate_sync(req(3));
    assert_eq!(code(&sync), ProcgenFailureCode::Timeout);
    assert_eq!(
        sync.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Started,
            LifecycleEvent::TimedOut,
        ]
    );
    assert!(sync.validate().is_ok());
    s.shutdown()
}
#[test]
fn raw_cap_content_and_malformed_reject_before_admission() {
    let exact = serde_json::to_string(&req(1)).unwrap();
    let mut l = lim();
    l.max_request_bytes = exact.len();
    let s = service(l, Arc::new(Clock::default()), fixed(bundle()));
    assert_eq!(
        code(&s.submit_json("{")),
        ProcgenFailureCode::InvalidRequest
    );
    assert_eq!(
        code(&s.submit_json(&format!(" {exact} "))),
        ProcgenFailureCode::Capacity
    );
    let mut bad = req(1);
    bad.content_manifest_hash = "f".repeat(64);
    assert_eq!(
        code(&s.submit(bad)),
        ProcgenFailureCode::GeneratorContentMismatch
    );
    assert_eq!(s.submit_json(&exact).request_id, Some(1));
    s.shutdown();

    let mut unicode = req(2);
    unicode.site.site_id = "site-é".into();
    let unicode_json = serde_json::to_string(&unicode).unwrap();
    let mut l = lim();
    l.max_request_bytes = unicode_json.len();
    let s = service(l, Arc::new(Clock::default()), fixed(bundle()));
    assert_eq!(s.submit_json(&unicode_json).request_id, Some(1));
    s.shutdown()
}
#[test]
fn output_caps_reject_validated_bundles() {
    let base = bundle();
    for n in 0..7 {
        let mut b = base.clone();
        match n {
            0 => {}
            1 => {}
            2 => b.trace.candidate_decisions.extend(["x".into(), "y".into()]),
            3 => b.trace.failed_constraints.extend(["x".into(), "y".into()]),
            4 => b.trace.repairs.extend(["x".into(), "y".into()]),
            5 => b.trace.retries.extend(["x".into(), "y".into()]),
            _ => {
                b.trace.stage_timings_micros.insert("x".into(), 1);
                b.metrics.stage_timings_micros.insert("x".into(), 1);
            }
        }
        assert!(b.validate().is_ok());
        let mut l = lim();
        match n {
            0 => {
                assert!(b.site_ir.ship.entities.len() > 1);
                l.max_entities = b.site_ir.ship.entities.len() - 1;
            }
            1 => {
                assert!(b.trace.rng_channels.len() > 1);
                l.max_trace_entries = b.trace.rng_channels.len() - 1;
            }
            2 => l.max_trace_entries = b.trace.candidate_decisions.len() - 1,
            3 => l.max_trace_entries = b.trace.failed_constraints.len() - 1,
            4 => l.max_trace_entries = b.trace.repairs.len() - 1,
            5 => l.max_trace_entries = b.trace.retries.len() - 1,
            6 => l.max_trace_entries = b.trace.stage_timings_micros.len() - 1,
            _ => unreachable!(),
        }
        assert!(l.max_trace_entries > 0);
        let s = service(l, Arc::new(Clock::default()), fixed(b));
        assert_eq!(
            code(&s.generate_sync(req(1))),
            ProcgenFailureCode::ValidationFailure
        );
        s.shutdown()
    }

    let mut l = lim();
    l.max_entities = base.site_ir.ship.entities.len() - 1;
    let s = service(l, Arc::new(Clock::default()), fixed(base));
    let id = s.submit(req(8)).request_id.unwrap();
    assert_eq!(
        code(&poll_terminal(&s, id)),
        ProcgenFailureCode::ValidationFailure
    );
    s.shutdown();
}
#[test]
fn consumed_tombstones_are_bounded_and_age_to_expired() {
    let mut l = lim();
    l.retained_results = 1;
    let s = service(l, Arc::new(Clock::default()), fixed(bundle()));

    let first = s.submit(req(1)).request_id.unwrap();
    assert_eq!(poll_terminal(&s, first).status, LifecycleStatus::Completed);
    let first_consumed = s.poll(first);
    assert_eq!(code(&first_consumed), ProcgenFailureCode::ResultConsumed);
    assert_eq!(first_consumed.events, vec![LifecycleEvent::ResultConsumed]);
    assert!(first_consumed.validate().is_ok());

    let second = s.submit(req(2)).request_id.unwrap();
    assert_eq!(poll_terminal(&s, second).status, LifecycleStatus::Completed);
    let second_consumed = s.poll(second);
    assert_eq!(code(&second_consumed), ProcgenFailureCode::ResultConsumed);
    assert_eq!(second_consumed.events, vec![LifecycleEvent::ResultConsumed]);
    assert!(second_consumed.validate().is_ok());
    let first_expired = s.poll(first);
    assert_eq!(code(&first_expired), ProcgenFailureCode::ResultExpired);
    assert_eq!(first_expired.events, vec![LifecycleEvent::ResultExpired]);
    assert!(first_expired.validate().is_ok());
    assert_eq!(code(&s.poll(0)), ProcgenFailureCode::UnknownRequest);
    assert_eq!(code(&s.poll(99)), ProcgenFailureCode::UnknownRequest);
    s.shutdown();
}

#[test]
fn max_id_exhaustion_does_not_wrap_or_claim_never_admitted_ids() {
    let mut l = lim();
    l.retained_results = 1;
    let s = Service::new_with_next_id(
        l,
        Arc::new(Clock::default()),
        HASH.into(),
        fixed(bundle()),
        i64::MAX,
    );
    assert_eq!(s.submit(req(1)).request_id, Some(i64::MAX));
    poll_terminal(&s, i64::MAX);
    assert_eq!(code(&s.poll(i64::MAX)), ProcgenFailureCode::ResultConsumed);
    assert_eq!(code(&s.submit(req(2))), ProcgenFailureCode::InternalFailure);
    assert_eq!(
        code(&s.poll(i64::MAX - 1)),
        ProcgenFailureCode::UnknownRequest
    );
    assert_eq!(code(&s.poll(0)), ProcgenFailureCode::UnknownRequest);
    s.shutdown()
}
#[test]
fn panic_contained_exact_generation_count() {
    let count = Arc::new(AtomicUsize::new(0));
    let n = count.clone();
    let b = bundle();
    let g = Arc::new(move |_| {
        if n.fetch_add(1, Ordering::SeqCst) == 0 {
            panic!("boom")
        }
        Ok(b.clone())
    }) as Generator;
    let s = service(lim(), Arc::new(Clock::default()), g);
    assert_eq!(
        code(&poll_terminal(&s, s.submit(req(1)).request_id.unwrap())),
        ProcgenFailureCode::InternalFailure
    );
    assert_eq!(
        poll_terminal(&s, s.submit(req(2)).request_id.unwrap()).status,
        LifecycleStatus::Completed
    );
    assert_eq!(count.load(Ordering::SeqCst), 2);
    s.shutdown()
}
#[test]
fn reversed_completion_evicts_lowest_id() {
    let (g, started, gates) = gated(bundle());
    let mut l = lim();
    l.workers = 2;
    l.queue_capacity = 2;
    l.retained_results = 1;
    let s = service(l, Arc::new(Clock::default()), g);
    s.submit(req(1));
    s.submit(req(2));
    let a = recv(&started, "first");
    let z = recv(&started, "second");
    assert_eq!(a + z, 3);
    release(&gates, 2).send(()).unwrap();
    let sentinel_three = s.submit(req(3)).request_id.unwrap();
    assert_eq!(recv(&started, "sentinel3"), 3);

    let sentinel_four = s.submit(req(4)).request_id.unwrap();
    release(&gates, 1).send(()).unwrap();
    assert_eq!(recv(&started, "sentinel4"), 4);

    assert_eq!(code(&s.poll(1)), ProcgenFailureCode::ResultExpired);
    assert_eq!(s.poll(2).status, LifecycleStatus::Completed);

    release(&gates, 3).send(()).unwrap();
    release(&gates, 4).send(()).unwrap();
    assert_eq!(sentinel_three, 3);
    assert_eq!(sentinel_four, 4);
    s.shutdown()
}
#[test]
fn shutdown_resolves_queued_and_joins() {
    let (g, started, gates) = gated(bundle());
    let s = service(lim(), Arc::new(Clock::default()), g);
    s.submit(req(1));
    recv(&started, "running");
    let q = s.submit(req(2)).request_id.unwrap();
    let s2 = s.clone();
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        s2.shutdown();
        tx.send(()).unwrap()
    });
    assert_eq!(code(&poll_terminal(&s, q)), ProcgenFailureCode::Shutdown);
    let rejected = s.submit(req(3));
    assert!(rejected.request_id.is_none());
    assert_eq!(code(&rejected), ProcgenFailureCode::Shutdown);
    release(&gates, 1).send(()).unwrap();
    recv(&rx, "join");
    s.shutdown()
}

#[test]
fn dropping_last_owner_waits_for_and_joins_running_worker() {
    let (g, started, gates) = gated(bundle());
    let s = service(lim(), Arc::new(Clock::default()), g);
    s.submit(req(1));
    assert_eq!(recv(&started, "running before drop"), 1);

    let (dropped_tx, dropped_rx) = mpsc::channel();
    std::thread::spawn(move || {
        drop(s);
        dropped_tx.send(()).unwrap();
    });
    assert!(
        dropped_rx.try_recv().is_err(),
        "drop returned before worker exit"
    );
    release(&gates, 1).send(()).unwrap();
    recv(&dropped_rx, "service drop join");
}
#[test]
fn events_bounded_and_valid() {
    let mut l = lim();
    l.max_events = 3;
    let s = service(l, Arc::new(Clock::default()), fixed(bundle()));
    let r = s.generate_sync(req(1));
    assert_eq!(
        r.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Started,
            LifecycleEvent::Completed
        ]
    );
    assert!(r.events.len() <= 3);
    assert!(r.validate().is_ok());
    let bad = s.submit_json("not json");
    assert!(bad.events.len() <= 3);
    assert!(bad.validate().is_ok());
    s.shutdown();

    let (g, started, gates) = gated(bundle());
    let mut l = lim();
    l.max_events = 1;
    let s = service(l, Arc::new(Clock::default()), g);
    let accepted = s.submit(req(1));
    assert_eq!(accepted.events.len(), 1);
    assert_eq!(accepted.events.last(), Some(&LifecycleEvent::Queued));
    assert!(accepted.validate().is_ok());
    assert_eq!(recv(&started, "event-running"), 1);
    let running = s.poll(1);
    assert_eq!(running.status, LifecycleStatus::Running);
    assert_eq!(running.events.len(), 1);
    assert_eq!(running.events.last(), Some(&LifecycleEvent::Started));
    assert!(running.validate().is_ok());

    let queued_id = s.submit(req(2)).request_id.unwrap();
    let queued = s.poll(queued_id);
    assert_eq!(queued.status, LifecycleStatus::Queued);
    assert_eq!(queued.events.len(), 1);
    assert_eq!(queued.events.last(), Some(&LifecycleEvent::Queued));
    assert!(queued.validate().is_ok());
    let queued_cancel = s.cancel(queued_id);
    assert_eq!(code(&queued_cancel), ProcgenFailureCode::Cancellation);
    assert_eq!(queued_cancel.events.len(), 1);
    assert_eq!(
        queued_cancel.events.last(),
        Some(&LifecycleEvent::Cancelled)
    );
    assert!(queued_cancel.validate().is_ok());

    let running_cancel = s.cancel(1);
    assert_eq!(running_cancel.status, LifecycleStatus::CancelRequested);
    assert_eq!(running_cancel.events.len(), 1);
    assert_eq!(
        running_cancel.events.last(),
        Some(&LifecycleEvent::CancelRequested)
    );
    assert!(running_cancel.validate().is_ok());
    release(&gates, 1).send(()).unwrap();
    let cancelled = poll_terminal(&s, 1);
    assert_eq!(code(&cancelled), ProcgenFailureCode::Cancellation);
    assert_eq!(cancelled.events.len(), 1);
    assert_eq!(
        cancelled.events.last(),
        Some(&LifecycleEvent::ResultConsumed)
    );
    assert!(cancelled.validate().is_ok());
    s.shutdown();

    let clock = Arc::new(Clock::default());
    let clock_for_generator = clock.clone();
    let b = bundle();
    let g = Arc::new(move |_| {
        clock_for_generator.set(10);
        Ok(b.clone())
    }) as Generator;
    let mut l = lim();
    l.max_events = 3;
    l.deadline_ms = 10;
    let s = service(l, clock, g);
    let timed_out = s.generate_sync(req(3));
    assert_eq!(code(&timed_out), ProcgenFailureCode::Timeout);
    assert_eq!(
        timed_out.events,
        vec![
            LifecycleEvent::Admitted,
            LifecycleEvent::Started,
            LifecycleEvent::TimedOut
        ]
    );
    assert!(timed_out.validate().is_ok());
    s.shutdown()
}
#[test]
fn sync_bypasses_async_queue() {
    let b = bundle();
    let (started_tx, started_rx) = mpsc::channel();
    let (release_tx, release_rx) = mpsc::channel();
    let release_rx = Arc::new(Mutex::new(release_rx));
    let g = {
        let release_rx = release_rx.clone();
        Arc::new(move |request: ProcgenRequest| {
            if request.world_seed == 1 {
                started_tx.send(()).unwrap();
                recv(&release_rx.lock().unwrap(), "release async seed1");
            }
            Ok(b.clone())
        }) as Generator
    };
    let s = service(lim(), Arc::new(Clock::default()), g);
    s.submit(req(1));
    recv(&started_rx, "async1");
    s.submit(req(3));
    assert_eq!(s.generate_sync(req(99)).status, LifecycleStatus::Completed);
    assert_eq!(code(&s.submit(req(4))), ProcgenFailureCode::Overload);
    release_tx.send(()).unwrap();
    s.shutdown()
}

#[test]
fn shutdown_sync_and_nonpositive_cancel_return_valid_stable_failures() {
    let s = service(lim(), Arc::new(Clock::default()), fixed(bundle()));
    s.shutdown();

    let sync = s.generate_sync(req(1));
    assert_eq!(code(&sync), ProcgenFailureCode::Shutdown);
    assert!(sync.validate().is_ok());

    for id in [0, -1] {
        let cancelled = s.cancel(id);
        assert_eq!(code(&cancelled), ProcgenFailureCode::UnknownRequest);
        assert!(cancelled.request_id.is_none());
        assert!(cancelled.validate().is_ok());
    }
}

#[test]
fn consumed_poll_and_cancel_use_consumed_code_and_event() {
    let s = service(lim(), Arc::new(Clock::default()), fixed(bundle()));
    let id = s.submit(req(1)).request_id.unwrap();
    assert_eq!(poll_terminal(&s, id).status, LifecycleStatus::Completed);

    let consumed_poll = s.poll(id);
    assert_eq!(code(&consumed_poll), ProcgenFailureCode::ResultConsumed);
    assert_eq!(
        consumed_poll.events.last(),
        Some(&LifecycleEvent::ResultConsumed)
    );
    assert!(consumed_poll.validate().is_ok());

    let consumed_cancel = s.cancel(id);
    assert_eq!(code(&consumed_cancel), ProcgenFailureCode::ResultConsumed);
    assert!(consumed_cancel.validate().is_ok());
    s.shutdown();
}

#[test]
fn effective_event_cap_covers_overload_and_shutdown_rejections() {
    let (g, started, gates) = gated(bundle());
    let mut l = lim();
    l.max_events = 1;
    let s = service(l, Arc::new(Clock::default()), g);
    s.submit(req(1));
    assert_eq!(recv(&started, "event-cap running"), 1);
    s.submit(req(2));

    let overload = s.submit(req(3));
    assert_eq!(code(&overload), ProcgenFailureCode::Overload);
    assert_eq!(overload.events, vec![LifecycleEvent::Overloaded]);
    assert!(overload.validate().is_ok());

    let s_for_shutdown = s.clone();
    let (joined_tx, joined_rx) = mpsc::channel();
    std::thread::spawn(move || {
        s_for_shutdown.shutdown();
        joined_tx.send(()).unwrap();
    });
    assert_eq!(code(&poll_terminal(&s, 2)), ProcgenFailureCode::Shutdown);
    let shutdown = s.submit(req(4));
    assert_eq!(code(&shutdown), ProcgenFailureCode::Shutdown);
    assert_eq!(shutdown.events, vec![LifecycleEvent::Shutdown]);
    assert!(shutdown.validate().is_ok());
    release(&gates, 1).send(()).unwrap();
    recv(&joined_rx, "event-cap shutdown join");
}

#[test]
fn sync_deadline_precedes_generator_error_or_panic() {
    for panic_after_deadline in [false, true] {
        let clock = Arc::new(Clock::default());
        let generator_clock = clock.clone();
        let generator = Arc::new(move |_| {
            generator_clock.set(10);
            if panic_after_deadline {
                panic!("late panic");
            }
            Err(generated_failure(ProcgenFailureCode::GenerationFailure))
        }) as Generator;
        let mut l = lim();
        l.deadline_ms = 10;
        let s = service(l, clock, generator);
        let result = s.generate_sync(req(1));
        assert_eq!(code(&result), ProcgenFailureCode::Timeout);
        assert!(result.validate().is_ok());
        s.shutdown();
    }
}

#[test]
fn async_failure_panic_and_deadline_precedence_have_exact_events_and_recover() {
    let cases = [
        (false, false, ProcgenFailureCode::GenerationFailure),
        (false, true, ProcgenFailureCode::InternalFailure),
        (true, false, ProcgenFailureCode::Timeout),
        (true, true, ProcgenFailureCode::Timeout),
    ];
    for (late, panics, expected_code) in cases {
        let clock = Arc::new(Clock::default());
        let generator_clock = clock.clone();
        let calls = Arc::new(AtomicUsize::new(0));
        let generator_calls = calls.clone();
        let valid_bundle = bundle();
        let generator = Arc::new(move |_| {
            if generator_calls.fetch_add(1, Ordering::SeqCst) == 0 {
                if late {
                    generator_clock.set(10);
                }
                if panics {
                    panic!("async fixture panic");
                }
                return Err(generated_failure(ProcgenFailureCode::GenerationFailure));
            }
            Ok(valid_bundle.clone())
        }) as Generator;
        let mut limits = lim();
        limits.deadline_ms = 10;
        let s = service(limits, clock, generator);

        let first_id = s.submit(req(1)).request_id.unwrap();
        let first = poll_terminal(&s, first_id);
        assert_eq!(code(&first), expected_code);
        assert_eq!(
            first.events,
            vec![
                LifecycleEvent::Admitted,
                LifecycleEvent::Queued,
                LifecycleEvent::Started,
                if late {
                    LifecycleEvent::TimedOut
                } else {
                    LifecycleEvent::Failed
                },
                LifecycleEvent::ResultConsumed,
            ]
        );
        assert!(first.validate().is_ok());

        let recovery_id = s.submit(req(2)).request_id.unwrap();
        let recovery = poll_terminal(&s, recovery_id);
        assert_eq!(recovery.status, LifecycleStatus::Completed);
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        s.shutdown();
    }
}

#[test]
fn admission_and_shutdown_ordering_is_serialized_for_every_entry_path() {
    let admission_operations = [
        AdmissionOperation::Submit,
        AdmissionOperation::SubmitJson,
        AdmissionOperation::GenerateSync,
        AdmissionOperation::GenerateSyncJson,
    ];

    for operation in admission_operations {
        let calls = Arc::new(AtomicUsize::new(0));
        let generator_calls = calls.clone();
        let valid_bundle = bundle();
        let generator = Arc::new(move |_| {
            generator_calls.fetch_add(1, Ordering::SeqCst);
            Ok(valid_bundle.clone())
        }) as Generator;
        let s = service(lim(), Arc::new(Clock::default()), generator);
        let (entered_tx, entered_rx) = mpsc::sync_channel(1);
        let (release_tx, release_rx) = mpsc::sync_channel(0);
        let release_rx = Arc::new(Mutex::new(release_rx));
        let armed = Arc::new(std::sync::atomic::AtomicBool::new(true));
        let hook_armed = armed.clone();
        s.set_admission_hook(Arc::new(move |observed| {
            if observed == operation && hook_armed.swap(false, Ordering::SeqCst) {
                entered_tx.send(()).unwrap();
                recv(&release_rx.lock().unwrap(), "admission winner release");
            }
        }));

        let request_json = serde_json::to_string(&req(1)).unwrap();
        let service_for_operation = s.clone();
        let (result_tx, result_rx) = mpsc::channel();
        let operation_handle = std::thread::spawn(move || {
            let result = match operation {
                AdmissionOperation::Submit => service_for_operation.submit(req(1)),
                AdmissionOperation::SubmitJson => service_for_operation.submit_json(&request_json),
                AdmissionOperation::GenerateSync => service_for_operation.generate_sync(req(1)),
                AdmissionOperation::GenerateSyncJson => {
                    service_for_operation.generate_sync_json(&request_json)
                }
                AdmissionOperation::Shutdown => unreachable!(),
            };
            result_tx.send(result).unwrap();
        });
        recv(&entered_rx, "admission winner entered");

        let service_for_shutdown = s.clone();
        let (attempted_tx, attempted_rx) = mpsc::channel();
        let (shutdown_tx, shutdown_rx) = mpsc::channel();
        let shutdown_handle = std::thread::spawn(move || {
            attempted_tx.send(()).unwrap();
            service_for_shutdown.shutdown();
            shutdown_tx.send(()).unwrap();
        });
        recv(&attempted_rx, "shutdown contender started");
        release_tx.send(()).unwrap();

        let admitted = recv(&result_rx, "admission winner result");
        match operation {
            AdmissionOperation::Submit | AdmissionOperation::SubmitJson => {
                assert_eq!(admitted.status, LifecycleStatus::Accepted);
                assert_eq!(admitted.request_id, Some(1));
            }
            AdmissionOperation::GenerateSync | AdmissionOperation::GenerateSyncJson => {
                assert_eq!(admitted.status, LifecycleStatus::Completed);
                assert_eq!(calls.load(Ordering::SeqCst), 1);
            }
            AdmissionOperation::Shutdown => unreachable!(),
        }
        recv(&shutdown_rx, "shutdown after admission");
        operation_handle.join().unwrap();
        shutdown_handle.join().unwrap();
        let after_shutdown = s.submit(req(99));
        assert_eq!(code(&after_shutdown), ProcgenFailureCode::Shutdown);
        assert!(after_shutdown.request_id.is_none());
    }

    let calls = Arc::new(AtomicUsize::new(0));
    let generator_calls = calls.clone();
    let valid_bundle = bundle();
    let generator = Arc::new(move |_| {
        generator_calls.fetch_add(1, Ordering::SeqCst);
        Ok(valid_bundle.clone())
    }) as Generator;
    let s = service(lim(), Arc::new(Clock::default()), generator);
    let (entered_tx, entered_rx) = mpsc::sync_channel(1);
    let (release_tx, release_rx) = mpsc::sync_channel(0);
    let release_rx = Arc::new(Mutex::new(release_rx));
    let armed = Arc::new(std::sync::atomic::AtomicBool::new(true));
    let hook_armed = armed.clone();
    s.set_admission_hook(Arc::new(move |observed| {
        if observed == AdmissionOperation::Shutdown && hook_armed.swap(false, Ordering::SeqCst) {
            entered_tx.send(()).unwrap();
            recv(&release_rx.lock().unwrap(), "shutdown winner release");
        }
    }));

    let service_for_shutdown = s.clone();
    let (shutdown_tx, shutdown_rx) = mpsc::channel();
    let shutdown_handle = std::thread::spawn(move || {
        service_for_shutdown.shutdown();
        shutdown_tx.send(()).unwrap();
    });
    recv(&entered_rx, "shutdown winner entered");

    let request_json = serde_json::to_string(&req(1)).unwrap();
    let (attempted_tx, attempted_rx) = mpsc::channel();
    let (result_tx, result_rx) = mpsc::channel();
    let mut operation_handles = Vec::new();
    for operation in admission_operations {
        let service = s.clone();
        let request_json = request_json.clone();
        let attempted_tx = attempted_tx.clone();
        let result_tx = result_tx.clone();
        operation_handles.push(std::thread::spawn(move || {
            attempted_tx.send(operation).unwrap();
            let result = match operation {
                AdmissionOperation::Submit => service.submit(req(1)),
                AdmissionOperation::SubmitJson => service.submit_json(&request_json),
                AdmissionOperation::GenerateSync => service.generate_sync(req(1)),
                AdmissionOperation::GenerateSyncJson => service.generate_sync_json(&request_json),
                AdmissionOperation::Shutdown => unreachable!(),
            };
            result_tx.send(result).unwrap();
        }));
    }
    for _ in admission_operations {
        recv(&attempted_rx, "blocked admission contender");
    }
    release_tx.send(()).unwrap();
    recv(&shutdown_rx, "winning shutdown");
    for _ in admission_operations {
        let rejected = recv(&result_rx, "post-shutdown rejection");
        assert_eq!(code(&rejected), ProcgenFailureCode::Shutdown);
        assert!(rejected.request_id.is_none());
        assert!(rejected.validate().is_ok());
    }
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    for handle in operation_handles {
        handle.join().unwrap();
    }
    shutdown_handle.join().unwrap();
}

#[test]
fn malformed_generator_failures_are_sanitized_sync_and_async() {
    let invalid_failure = ProcgenFailure {
        schema_version: FAILURE_SCHEMA.into(),
        code: ProcgenFailureCode::GenerationFailure,
        stage: String::new(),
        message: String::new(),
        retryable: false,
        fallback_id: None,
    };
    let generator = Arc::new(move |_| Err(invalid_failure.clone())) as Generator;
    let s = service(lim(), Arc::new(Clock::default()), generator);

    let sync = s.generate_sync(req(1));
    assert_eq!(code(&sync), ProcgenFailureCode::InternalFailure);
    assert!(sync.validate().is_ok());

    let id = s.submit(req(2)).request_id.unwrap();
    let asynchronous = poll_terminal(&s, id);
    assert_eq!(code(&asynchronous), ProcgenFailureCode::InternalFailure);
    assert!(asynchronous.validate().is_ok());
    s.shutdown();
}
