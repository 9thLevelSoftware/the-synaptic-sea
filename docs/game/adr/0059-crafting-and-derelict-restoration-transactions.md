# ADR-0059: Persistent crafting lots and transactional derelict restoration

- Status: **Proposed; no implementation authorized by this record alone.**
- Date: 2026-09-04
- Related: ADR-0038, ADR-0051, existing RunSnapshot versioning and ShipRuntime contracts.
- Spec: [feature completion contract](../features/crafting_derelict_feature_completion.md).

## Context

The current inventory stores aggregate item quantities. Crafting calculates quality
without delivering it, queues can start unpaid jobs, and ship-mod UI can install
arbitrary items. Repair models cannot rebuild destroyed structure. Extending these
paths without explicit ownership and persistence would create duplication, loss,
and cross-ship mutations. Existing saves and module-based generation must survive.

## Alternatives considered

1. **Patch individual callbacks only.** Fastest for narrow defects, but quality,
   job identity, chosen ship/slot and replacement persistence remain inconsistent.
2. **Extend existing models through bounded transaction and metadata seams
   (proposed).** Retain IDs, aggregate APIs, generated structures and WorkActions;
   introduce persistent lots/jobs and explicit replacement transactions.
3. **Replace inventory, crafting and construction with a new framework.** Offers
   a clean slate but creates an unnecessary cross-cutting migration and threatens
   the already working gameplay. Not selected.

## Proposed decisions

1. Keep gameplay state in RefCounted/Resource models. Scene nodes enact visual,
   collision, nav and atmosphere effects. The coordinator binds them; it does not
   gain another independent economy implementation.
2. Add a lot ledger behind existing inventory APIs. Aggregate quantities remain
   compatible views; all mutators update the ledger, and old direct-dictionary
   writes are routed through these APIs. Quality, condition and provenance are
   separate fields. Legacy saves migrate deterministically without quantity loss.
3. Give each fabrication job a stable job ID, source ship/station IDs, ingredient
   escrow, state, progress, resolved output and collection receipt. Enqueue reserves;
   start consumes; completion records output once. Pending output is persistent.
4. Use one pure eligibility result for presentation and execution. Revalidate at
   commit. Knowledge belongs to the current run's player; jobs belong to ships.
5. Route physical repair/install/replace through WorkActions with explicit ship and
   target IDs and revision checks. Material commitment and scene consequences form
   one logical operation. Scene preflight precedes commitment; failed staging rolls
   back, does not emit completion/XP, and preserves recoverable escrow.
6. Separate permanent machinery/armor installation from consumable patching.
   Install/remove cannot repeatedly heal a structure for free.
7. Retain module-based structure. A destroyed-module descriptor remains after the
   wrapper disappears. Replacement operates within the original footprint/socket
   contract; it does not author a new room graph or alter generator authority.
8. Persist structural replacement records independently of non-pristine damage
   deltas. Apply generation, replacements, integrity, components, system state,
   then derived scene/nav/atmosphere state in a defined reconstruction order.
9. Snapshot only coherent transaction boundaries. Persist escrow and receipts with
   their owners. Restoring a completed receipt cannot award output, materials or XP
   a second time. Unsupported future save versions are rejected without overwrite.
10. Additive summary fields and a migration revision are required for lot/job and
    replacement state. Exact next schema identifiers are allocated from current
    HEAD by P01/P03; this ADR is the required authorization record for extending
    RunSnapshot, not permission to silently reinterpret existing save fields.

## Consequences and controls

- More metadata and migration tests are necessary; stack and cargo semantics remain.
- Job and repair material policies differ deliberately and must be visible in UI.
- Current-ship binding becomes mandatory for mutation APIs and tests.
- Complete scene staging can fail; no material commit is permitted until resource,
  footprint, occupancy and target revision checks pass.
- Existing native generation output and authored assets remain authoritative.
- Core crafting/repair can ship before broader structural layout editing; no
  claim about unimplemented editor-style construction is implied.
- Every decision above is covered by the feature contract and implementation tasks.
  Acceptance of this ADR is an execution gate; authoring this proposal changes no
  runtime behavior or existing Accepted ADR status.
