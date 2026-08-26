# ADR-0067: Version Gate 4 adaptive decisions and wrapper contracts

- **Status:** Accepted
- **Date:** 2026-08-26
- **Related:** ADR-0057, ADR-0058, ADR-0059, ADR-0064, ADR-0065,
  ADR-0066; `docs/game/features/unified_procgen_platform.md`;
  REQ-PG-002..004, REQ-PG-007, REQ-PG-010, REQ-PG-012; Gate 4 card
  `t_fdf4962a`

## Context

Gate 3 exports a complete gameplay bundle, but `adaptive-proposal-1` remains a
standalone data-transfer object. `procgen-bundle-4` and `generation-trace-3`
have no typed location for normalized adaptive inputs, the candidate score set,
the selected action, deterministic tie-breaking, or fallback. Mutating those
checked schemas would violate the immutable-contract rule established by
ADR-0058 and ADR-0065.

The current encounter generator already consumes the bounded run-local player
snapshot, but its budget adjustment is not represented as an
`AdaptiveProposal`. Site generation also returns the first buildable mission
template rather than ranking a closed set of fully validated alternatives.

## Decision

1. Gate 4 ships only the deterministic classical implementation described by
   ADR-0059. It adds no embedded-model runtime, provider, inference dependency,
   or experimental promotion path.
2. `adaptive-proposal-2` keeps the proposal envelope constrained to a score,
   typed rationale codes, confidence, rule version, and either a candidate
   selection, a bounded encounter pacing adjustment, or no-op. Identifier,
   collection, score, confidence, and pacing ranges are closed and bounded.
   `adaptive-proposal-1` remains byte-immutable.
3. `adaptive-decision-trace-1` records the decision kind, normalized
   `player-model-2` inputs, ordered candidate features/scores/actions, selected
   proposal, whether the action was applied, and a typed deterministic fallback.
   The trace contains no account identity, free-form personal data, network
   history, or unbounded text.
4. The classical ranker receives only candidates that completed
   `validate -> bounded repair -> revalidate` without selecting an authored
   fallback. It borrows candidate data, returns an identifier, and never edits a
   candidate after validation. The world path uses the same ranker for its
   currently singular validated world candidate; the site path ranks every
   fully validated compatible mission candidate. Authored fallback remains
   outside the candidate set and is selected only when the set is empty.
5. The encounter director chooses among authored pacing deltas expressed in
   basis points. The accepted delta may adjust only the authored threat limit;
   economy, fairness, accessibility, counterplay, occupancy, navigation,
   visibility, group, instance, and performance limits remain authoritative.
   The complete encounter is revalidated after the action is applied.
6. `generation-trace-4` embeds the ordered world-ranker, site-ranker, and
   encounter-director decision traces while retaining Gate 3's exact 37 named
   RNG channels. The ranker and director introduce no additional RNG stream.
7. Because the nested mechanical contract changes, Gate 4 adds and makes
   current `gameplay-ir-3`, `procgen-bundle-5`,
   `procgen-lifecycle-result-5`, `procgen-capabilities-4`,
   `procgen-generator-manifest-4`, and `procgen-build-manifest-4`.
   `player-model-2`, `procgen-request-2`, `world-ir-2`, `site-ir-2`,
   `presentation-ir-2`, `generation-metrics-1`, platform generator version 3,
   and structural ship version 2 remain unchanged.
8. Native, Web, Godot, schema exporters, parity corpora, build manifests, and
   save-envelope mismatch checks advance as one fail-closed transition. Every
   prior schema file remains byte-immutable.

## Consequences

- Every production adaptive action can be replayed from the request, bounded
  snapshot, content/version identity, and typed trace.
- Site selection becomes meaningfully adaptive without allowing the ranker to
  repair or mutate topology, missions, or mechanics.
- Encounter pressure can respond within a small authored envelope while all
  previously validated fairness and performance constraints remain binding.
- Any future embedded experiment must introduce its own separately approved
  implementation and use the same proposal validator; this ADR does not grant
  that promotion.

## Rejected alternatives

- Add strings to `generation-trace-3`: cannot provide a closed replay contract
  and would mutate a checked schema.
- Put model/provider state into the request: expands the offline run-local
  snapshot and creates identity/privacy drift.
- Rank buildable but unvalidated candidates: permits a high score to outrank a
  safety validator.
- Let pacing alter performance, economy, spawn legality, or visibility rules:
  turns a proposal into a validator bypass.
- Scaffold embedded inference before the classical gate passes: conflicts with
  ADR-0059's evidence order and the Gate 4 card's non-goals.

## Verification

- Golden utility scores, rationale codes, confidence, and tie-break order.
- Invalid candidates never enter a rank trace; input candidates remain
  byte-identical after selection.
- Trace replay regenerates the exact selected proposal and rejects any input,
  candidate, score, action, version, or fallback mutation.
- Encounter actions remain inside the authored pacing/threat envelope and the
  post-action encounter validator passes for deterministic and adversarial
  corpora.
- Difficulty does not systematically lower expected threat; locale and
  presentation seeds cannot change adaptive mechanics.
- Prior-schema hashes remain unchanged and every mixed Gate 3/Gate 4 wrapper
  substitution fails in Rust, native, Web, Godot, and manifest validation.
