# ADR-0060: Offline Meshy Evidence Rebinding

## Status

Accepted.

## Date

2026-09-05

## Context

Completed Meshy batches are governed by a protected-surface snapshot. Legitimate growth of a
protected surface, including user-imported assets, can strand an otherwise complete batch at the
offline verification gate because the journal still contains the older snapshot. The existing
resume and continue paths intentionally require the original snapshot and cannot safely refresh
approval. Re-running generation would spend provider credits and is not an evidence operation.

The read-only Meshy plan already computes resolved reference evidence, the redacted provider
request, and its payload hash. That evidence was not persisted into the tracked plan envelope,
leaving a plan with `references_resolved=false` even after the references had been resolved
locally.

## Decision

Add two offline, fail-closed subcommands to `tools/meshy_stage.py`:

- `reapprove` is allowed only for a canonically validated, `COMPLETED` batch whose task evidence
  is fully verified and has no unresolved entries. It recomputes the live protected snapshot,
  replaces only `approval.protected_snapshot`, records the UTC reapproval time and explicit
  reason/operator, and appends the original approval object to an append-only top-level
  `approval_history` array before atomic publication. The original approval is never overwritten
  without retaining that history entry.
- `resolve-plan` reuses the existing `plan` computation path offline and atomically persists only
  the plan-governed fields: `references_resolved`, `resolved_references`,
  `provider_payload_sha256`, and the redacted request/payload fields. It preserves all other plan
  envelope fields and revalidates the complete envelope before and after publication. Missing or
  mismatched references fail closed.

Neither command constructs a provider client or makes a network call. Operators must supply a
nonempty reapproval reason and operator identity explicitly.

## Consequences

- Legitimate protected-surface growth can be rebound without generating new provider tasks or
  spending credits.
- The approval audit trail is append-only, and legacy journals without `approval_history` remain
  valid.
- Resolved plan evidence is available to later governed steps without touching batch journals or
  task directories.
- Both operations retain atomic, canonical JSON publication and fail closed on invalid evidence.
- Operators must make the reason and operator identity explicit; these commands do not infer or
  silently renew approval.
