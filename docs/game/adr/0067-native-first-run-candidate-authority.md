# ADR-0067: Validate first-away candidates through the production generator

Status: accepted for implementation; validation pending.

## Problem

The first-run contract previews `ShipLayoutGenerator` output but boarding uses
`ShipGenerator` and native worldgen. The preferred seed 777 therefore passes the
preview while its actual native shuttle has a LOCKED critical crossing between
corridor_02 and corridor_03. The generated boarded slice requires a standing route
from start to goal, and standing navigation must not cross LOCKED or BREACH edges.
Native integration also omits the deterministic room variants consumed by the
existing runtime hazard contract. A fallback preview cannot certify that content.

## Decision

Use the production ShipGenerator route for every first-away contract candidate,
with the exact marker size/condition and contract biome/difficulty. Apply the
existing RoomVariantSelector authority to native rooms before encounter injection
and gameplay-slice construction, including the existing runtime hazard-source
metadata. Preserve structural placements, portals, locked/breached edges, intactness
and wreck overlays. This is an integration correction, not a native binary change.

Require a standing start-to-goal route in the first-run contract in addition to
its existing biome, difficulty, loot, encounter and hazard predicates. The pure
contract builds ShipNavGraph and uses actual structural standing positions and
ThreatPathfinder semantics; no unlock shortcut or blocked-edge cost override is
permitted. Validate and free detached candidates in authored preferred-seed order.
Select the first fully valid candidate. Do not hardcode a replacement seed.

If no candidate qualifies, return an explicit first_run_contract_unsatisfied
result before travel cost, marker mutation, world/scanner mutation or attachment.
Distinguish failure from a contract that is not applicable. Mutate the marker only
after successful selection. Regeneration must use identical resolved context and
remain deterministic; persist that context through the existing ADR-0061 path.
Ordinary subsequent generation retains its existing wreck and lock policy.

## Verification

Exercise native WRECKED candidates through the actual production route. Verify
that a locked critical crossing rejects, noncritical locks and wreck damage remain,
the first qualifying authored candidate wins, repeated selection/layouts agree,
and no-candidate denial leaves player resources, marker and world unchanged.
Retain all hazard/loot/encounter predicates. Run first_run_contract_smoke and the
real generated_seed_boarded_slice_smoke with their reviewed markers and clean
output, followed by the canonical bundle. Preserve RED evidence for the original
native seed-777 failure; a changed assertion alone does not establish repair.

## Scope

P00 permits the first-run contract data/model, native ShipGenerator variant seam,
coordinator first-run candidate/travel preflight only, their two existing smokes,
feature design explanation and corresponding validation markers. No unrelated
travel policy, native binary, free unlock, or gameplay requirement is changed.
