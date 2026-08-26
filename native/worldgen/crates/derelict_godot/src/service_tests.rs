//! Deterministic lifecycle tests. Gates are one-shot channels; no sleeps/barriers.
use super::service::{Generator, Limits, MonotonicClock, Service};
use derelict_core::lifecycle::{LifecycleEvent, LifecycleResult, LifecycleStatus};
use derelict_core::model::GENERATOR_VERSION;
use derelict_core::procgen::{
    Domain, PlayerModel, PresentationRequest, ProcgenBundle, ProcgenFailureCode, ProcgenRequest,
    SiteRequest,
};
use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::time::{Duration, Instant};
const HASH: &str = "0000000000000000000000000000000000000000000000000000000000000000";
const WAIT: Duration = Duration::from_secs(2);
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
        generator_version: GENERATOR_VERSION,
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
fn poll_terminal(s: &Service, id: i64) -> LifecycleResult {
    let until = Instant::now() + WAIT;
    loop {
        let r = s.poll(id);
        if matches!(
            r.status,
            LifecycleStatus::Completed | LifecycleStatus::Failed
        ) {
            return r;
        }
        assert!(Instant::now() < until, "terminal poll timed out");
        std::thread::yield_now()
    }
}
fn recv<T>(r: &mpsc::Receiver<T>, what: &str) -> T {
    r.recv_timeout(WAIT)
        .unwrap_or_else(|_| panic!("timed out waiting for {what}"))
}
fn gated(
    b: ProcgenBundle,
) -> (
    Generator,
    mpsc::Receiver<u64>,
    Arc<Mutex<BTreeMap<u64, mpsc::Receiver<()>>>>,
) {
    let (tx, started_rx) = mpsc::channel();
    let gates = Arc::new(Mutex::new(BTreeMap::new()));
    let map = gates.clone();
    let g = Arc::new(move |r: ProcgenRequest| {
        tx.send(r.world_seed).unwrap();
        let until = Instant::now() + WAIT;
        let gate = loop {
            if let Some(rx) = map.lock().unwrap().remove(&r.world_seed) {
                break rx;
            }
            assert!(Instant::now() < until, "gate was not installed");
            std::thread::yield_now()
        };
        recv(&gate, "release");
        Ok(b.clone())
    }) as Generator;
    (g, started_rx, gates)
}
fn release(g: &Arc<Mutex<BTreeMap<u64, mpsc::Receiver<()>>>>, seed: u64) -> mpsc::Sender<()> {
    let (tx, rx) = mpsc::channel();
    g.lock().unwrap().insert(seed, rx);
    tx
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
    let repeated_queued_cancel = s.cancel(q);
    assert_eq!(repeated_queued_cancel, first_queued_cancel);
    assert_eq!(
        code(&poll_terminal(&s, q)),
        ProcgenFailureCode::Cancellation
    );
    assert_eq!(code(&s.poll(q)), ProcgenFailureCode::ResultConsumed);
    assert_eq!(s.submit(req(3)).request_id, Some(3));

    let first_running_cancel = s.cancel(1);
    assert_eq!(
        first_running_cancel.status,
        LifecycleStatus::CancelRequested
    );
    let repeated_running_cancel = s.cancel(1);
    assert_eq!(repeated_running_cancel, first_running_cancel);
    release(&gates, 1).send(()).unwrap();
    assert_eq!(
        code(&poll_terminal(&s, 1)),
        ProcgenFailureCode::Cancellation
    );
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
    assert_eq!(code(&poll_terminal(&s, 1)), ProcgenFailureCode::Timeout);
    assert_eq!(code(&poll_terminal(&s, q)), ProcgenFailureCode::Timeout);
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
    assert_eq!(code(&s.generate_sync(req(3))), ProcgenFailureCode::Timeout);
    s.shutdown()
}
#[test]
fn raw_cap_content_and_malformed_reject_before_admission() {
    let exact = serde_json::to_string(&req(1)).unwrap();
    let mut l = lim();
    l.max_request_bytes = exact.as_bytes().len();
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
    l.max_request_bytes = unicode_json.as_bytes().len();
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
    assert_eq!(code(&s.poll(first)), ProcgenFailureCode::ResultConsumed);

    let second = s.submit(req(2)).request_id.unwrap();
    assert_eq!(poll_terminal(&s, second).status, LifecycleStatus::Completed);
    assert_eq!(code(&s.poll(second)), ProcgenFailureCode::ResultConsumed);
    assert_eq!(code(&s.poll(first)), ProcgenFailureCode::ResultExpired);
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
