# ADR-0060: Deterministic bounded procgen lifecycle

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0057; ADR-0058; `docs/game/features/unified_procgen_platform.md`;
  REQ-PG-002..004; Gate 1 card `t_9c775122`

## Context

The native bridge currently creates one thread per request and stores pending
receivers inside each Godot generator instance. It has no queue or result bound,
no cancellation or deadline contract, and no target-neutral lifecycle result.
That cannot provide deterministic overload behavior or match a cooperative Web
adapter. Passing Godot objects through the worker boundary would also couple the
authoritative core to a target runtime.

## Decision

1. The adapter boundary is UTF-8 JSON. Native exposes `generate_bundle`,
   `generate_bundle_async`, `poll`, `cancel`, `capabilities`, and
   `generator_manifest` with the same versioned DTOs used by Web. Godot objects
   never cross a worker thread.
2. Lifecycle results use explicit `accepted`, `queued`, `running`,
   `cancel_requested`, `completed`, or `failed` states. A completed result has
   exactly one `ProcgenBundle`; a failed result has exactly one stable
   `ProcgenFailure`; nonterminal results have neither. Every response also has a
   bounded ordered list of stable lifecycle-event codes, so rejection,
   admission, start, cancellation, timeout, completion, and failure paths are
   replayable without parsing messages or depending on wall-clock timings.
3. Native uses one process-wide service shared by every `DerelictGenerator`.
   The production defaults are two workers, eight queued jobs, sixteen retained
   terminal results, a 64 KiB request document, 4,096 entities, 4,096 entries per
   bundle trace list, 32 lifecycle events, and a 2,000 ms
   admission-to-completion budget. Capabilities report the effective values.
   Tests create isolated services with injected limits, clocks, and generators.
4. Admission parses and validates the request and caps before allocating an ID.
   Positive IDs increase monotonically through signed 64-bit maximum. Calls are
   serialized under the service lock; the first admitted calls win. A full queue
   returns `overload` without consuming an ID.
5. Cancelling a queued job immediately makes it a retained cancellation result.
   Cancelling a running job records `cancel_requested`; the pure generator may
   finish, but its output is discarded. Repeated cancellation is idempotent.
   Cancelling a terminal job returns `too_late` without consuming that result.
6. The time budget begins at admission. Expiration before execution and
   over-budget completion both return `timeout`; worker threads are never
   force-killed. Synchronous generation applies the same request, entity, and
   elapsed-time caps without entering the async queue.
7. `poll` consumes a terminal bundle/failure exactly once. Retention evicts the
   lowest accepted terminal ID, independent of worker completion order. Bounded
   tombstones distinguish recent consumed and expired IDs; once a tombstone is
   retired, any older admitted ID reports `result_expired`. Nonpositive, future,
   or never-admitted IDs report `unknown_request`.
8. Shutdown rejects new work, resolves queued work with `shutdown`, wakes the
   workers, waits for running pure generation to return, and joins every worker.
   No background thread is detached or leaked.
9. Adapter-neutral capabilities and generator-manifest DTOs live with the Rust
   contracts. Compile-time metadata reports source commit, generator/content
   identity, export schemas, target, and dirty-development status. Target
   artifact path/hash remain in the externally checked build manifest to avoid
   a self-hash cycle.
10. Legacy native method names remain temporary migration APIs. Their outputs
    derive from one `ProcgenBundle`; no compatibility method may run layout and
    gameplay generation separately.

## Consequences

- Load is finite and observable; overload, cancellation, timeout, and retention
  outcomes no longer depend on an unbounded number of OS threads.
- Native and Web can share contracts while using a worker pool and cooperative
  polling respectively.
- A running cancellation or timeout cannot stop pure CPU work immediately, but
  its output cannot escape and bounded worker count prevents resource explosion.
- Callers must handle explicit lifecycle failures instead of inferring state
  from null variants or error strings.

## Rejected alternatives

- Thread per request: unbounded and incompatible with Web parity.
- Godot dictionaries as the authoritative ABI: target-specific and lossy for
  versioned nested contracts.
- Force-killing timed-out workers: unsafe and capable of leaving shared state in
  an unknown condition.
- Completion-order eviction: nondeterministic when workers finish in a different
  order.
- Unbounded consumed-result history: turns a bounded service into a memory leak.

## Verification

- Native lifecycle tests cover admission order, saturation/recovery, queued and
  running cancellation, timeout before/after execution, unknown/consumed/expired
  IDs, lowest-ID eviction, shutdown/join, malformed/oversized requests, entity
  caps, bounded/replayable event sequences, and exact-once completion.
- GDExtension tests cover all six methods, JSON round trips, shared service
  behavior, capabilities/manifest reporting, and migration routing.
- Task 4 replays the same contract vectors through the cooperative Web adapter.
