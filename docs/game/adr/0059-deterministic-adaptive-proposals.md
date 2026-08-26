# ADR-0059: Deterministic adaptive proposals before optional embedded inference

- **Status:** Accepted
- **Date:** 2026-08-26
- **Supersedes / amends:** Amends ADR-0047 encounter authority with bounded
  run-local adaptation; does not change authored encounter-table authority or
  permit post-validation mutation.
- **Related:** `docs/game/features/unified_procgen_platform.md`;
  REQ-PG-007, REQ-PG-010, REQ-PG-011; Gate 4 and Gate 5

## Context

The platform should respond to player capability and pacing without becoming a
black box, a network dependency, or an authority that can create impossible
content. An embedded model may eventually improve ranking, but adding inference
before a deterministic baseline exists would make quality gains impossible to
measure and failures difficult to replay.

## Decision

1. Ship a deterministic utility-scoring/search implementation first.
2. The candidate ranker considers only fully validated world/site candidates.
   It may rank or select; it cannot edit a candidate after validation.
3. The encounter director may adjust composition and pacing only within authored
   threat, economy, fairness, accessibility, counterplay, occupancy, navigation,
   visibility, and performance envelopes. Its accepted action is revalidated.
4. Player modeling uses a bounded, versioned snapshot of run-local signals. It
   contains no account identifier, network history, free-form text, or external
   service dependency.
5. Every decision records normalized inputs, candidates, scores, selected action,
   rationale codes, rule/model version, confidence where applicable, and
   deterministic fallback.
6. Implementations conform to `AdaptiveProposal`. A proposal is constrained data,
   never executable policy and never a validator bypass.
7. An embedded offline model may be added only as a disabled experiment after
   the classical implementation passes production gates. It uses the identical
   proposal/validation path.
8. Timeout, unsupported hardware, invalid shape/range/action, nondeterministic
   output, disabled configuration, or inference error selects the deterministic
   classical fallback. The fallback decision is traced.
9. Promotion requires a measurable, predeclared quality benefit without
   violating build-size, memory, latency, determinism, accessibility, legal,
   licensing, privacy, fairness, or platform gates.

## Consequences

- Adaptive behavior is replayable, diagnosable, and testable before any model is
  introduced.
- A later model competes against a known baseline and cannot expand the action
  space or weaken validators.
- Player modeling remains local and bounded; diagnostic bundles do not become
  personal telemetry.

## Rejected alternatives

- Let a model generate layouts, stats, or prose-driven mechanics directly:
  outputs cannot be bounded or replayed reliably.
- Network inference: violates offline operation and adds privacy/availability
  dependencies.
- Promote based on subjective samples alone: provides no evidence against the
  classical baseline or production budgets.
- Adapt by changing difficulty outside authored envelopes: undermines fairness
  and can create softlocks or economy spikes.

## Verification

- Golden score/rationale tests and deterministic tie-breaking across adapters.
- Property/metamorphic tests for threat/difficulty monotonicity, budget bounds,
  locale independence, and validated-candidate-only selection.
- Replay tests reconstruct every selected action from request, snapshot,
  versions, manifest, and trace.
- Optional model tests force timeout, invalid output, unsupported capability,
  and disabled modes and compare the selected fallback with classical output.

