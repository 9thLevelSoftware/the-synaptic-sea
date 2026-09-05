# ADR-0064: Version the parity fixture with the topology contract

- Status: Accepted contract; candidate validation and implementation pending.
- Date: 2026-09-05
- Requirements: FC-02; preserves structural validation and ADR-0053.

## Context

The focused-nine overlay captured at `2b4773c4` contains 51 edge placements.
The current seed-17 SMALL/WRECKED compact input produces 48. Comparing only
these counts initially concealed a larger difference: eight occupancy cells
were removed and eight added, while the total remains 29.

Commit `f27c5b92` replaced CellLayoutEngine's greedy adjacency placement with
connector growth, as required by [ADR-0053](0053-socketed-enclosed-interiors.md).
The current algorithm therefore does not promise the historical cell coordinates.
The parity smoke uses the GDScript `ShipGenerator.generate` path, not native
`generate_from_seed`. This discrepancy is not native extension drift.

## Decision

Preserve the historical focused-nine overlay and its provenance unchanged. Add a
separate, versioned fixture under `data/procgen/golden/compact_seed17_current/`
for the current connector-growth contract. The canonical parity test may select
that fixture only after its capture and independent review pass. Do not change
expected counts in place or weaken record-by-record comparison.

Capture the exact existing input: seed 17, SMALL, WRECKED, room range 5..8,
derelict archetype with compact template and empty guaranteed roles. Retain a
reproducible capture script, engine version, source commit and relevant source
hashes, full structural records, and independently inspected live wrappers.

Validation must cover all canonical edges, including unwrapped breach portals.
Portal counts come from those edges, rather than a nonexistent plan-level portal
array. Verify actual endpoint occupancy, unique edge and placement identities,
no portal/wall overlap, and the canonical structural validator. Check actual
wrapper transforms and metadata; copying expected records is insufficient proof.
Missing, duplicate and unexpected wrappers fail. Negative duplicate-edge,
portal/wall overlap and endpoint mutations must execute and fail validation;
an absent test subject is not a passing negative test.

Two isolated captures must agree. The parity regression retains exact normalized
placement and wrapper comparisons and rejects malformed fixture data. Capturing
a new fixture is not automatic approval of future topology changes: another
source-backed review is required before replacing this version's expected data.

## Acceptance boundary

The existing candidate has not yet met this contract. Deterministic output alone
does not establish semantic correctness. Approval requires the validations above
and review of the changed occupancy against the current connector-growth contract.
Historical staged asset evidence remains historical evidence; this decision does
not claim a new visual-art acceptance or a completed feature gate.
