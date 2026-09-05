# ADR-0064: Version the parity fixture with the topology contract

- Status: Accepted contract, candidate and focused regression integration; full baseline pending.
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

The candidate and regression integration passed independent endpoint, occupancy,
wrapper, source-provenance, malformed-fixture and capture-path review. Fresh
positive parity passes with no diagnostics; mutation probes fail cleanly without
a PASS marker. The full canonical baseline remains pending.
Historical staged asset evidence remains historical evidence; this decision does
not claim a new visual-art acceptance or a completed feature gate.

## Position representation addendum (2026-09-05)

The independently accepted candidate hash was
`BBE71EF7B95D429EB09D6AE6F47FC4E38DF181998095A7A7668987D40CDF6E59`.
Strict fixture validation now stores placement and wrapper positions as arrays
of three numbers instead of textual Vector3 coordinates. The resulting hash is
`1B9FEB21C727679CF70BFF8246ABACB318DCC3B9A306E88E1FEA9E4A3EFD29EF`.
Independent comparison normalized only those position fields in the preserved
accepted capture and found full recursive JSON equality with the new capture.
This representation change is accepted; no topology, wrapper, occupancy, or
other metadata change is authorized by this addendum. The capture manifest
records both hashes and the reason for the change.

The reusable capture utility must refuse existing outputs and protected
historical/golden directories, including relative, traversal and Windows case
variants. Future captures remain candidates until separately reviewed.

## Connector-grown room footprint clarification (2026-09-05)

ADR-0053 and REQ-ENC-001 define room occupancy as nonempty, four-connected
integer cell sets. Since `f27c5b92`, connector growth may produce nonrectangular
sets; a room's `footprint` records their bounding-box dimensions, not a promise
that every cell in that box is occupied. For example, bifurcated seed 17 has a
five-cell corridor inside a 2-by-3 box. Generation, serialization and structural
compilation must preserve the actual occupied cells, including the unfilled cell.

The earlier stress assertion from `eec54287` equating bounding-box area with
cell count predates that contract. Its replacement must validate nonempty unique
integer cells, four-connectivity and the exact derived bounding box while
retaining floor ownership, portal and structural-compiler checks. Disconnected
cells, duplicates and false bounding boxes must fail. This authorizes a focused
fixture correction, not a change to generation or automatic acceptance of its
implementation; independent review and fresh stress validation remain required.
