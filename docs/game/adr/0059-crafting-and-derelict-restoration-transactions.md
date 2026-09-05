# ADR-0059: Persistent crafting lots and transactional derelict restoration

- Status: **Accepted for the Crafting and Derelict Feature Completion program; scoped implementation underway; full acceptance pending.**
- Date: 2026-09-04
- Related: ADR-0038, ADR-0051, [ADR-0062](0062-ship-owned-pending-output-receipts.md),
  existing RunSnapshot versioning and ShipRuntime contracts.
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
   Generated lot IDs include a persistent holder namespace and sequence so separate
   holders cannot generate colliding identities. Owners supply stable source IDs
   for legacy migration; new anonymous holders allocate and retain a unique
   namespace. A metadata lot deposit is atomic; partial transfers split at the
   source before depositing a complete outgoing lot. Legacy quantity-only adds
   retain partial admission by computing capacity before generating their lot.
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
10. ComponentPlacementState owns physical slot occupancy. ShipModificationState
    derives fit, power and effects from that owner. Generated physical slots carry
    explicit authored profile IDs resolved against the current catalog; runtime
    wall/center guesses cannot grant fit permission. Restore overlays saved dynamic
    component contents onto freshly generated descriptors and never trusts saved
    socket, footprint or type policies. P11 establishes this commit path; P12 wraps
    the same path in timed work rather than introducing another mutation authority.
11. Additive summary fields and a migration revision are required for lot/job and
    replacement state. Current HEAD ends its ordered run chain at
    `gate2-current-run-4` and its world target at `world-4`
    (`scripts/systems/save_migration_service.gd`). The reserved successors are
    `gate2-current-run-5` and `world-5`. P10 must append deterministic forward
    steps, preserve every old step, and test future-version rejection before either
    identifier becomes an implemented save format. This ADR authorizes that bounded
    extension; it does not permit silent reinterpretation of existing fields.
12. Treat recoverable floor yield as a ship-owned lot holder rather than transient
    scene decoration. `ShipInstance` owns the authoritative drop descriptors and a
    persistent allocation sequence. Each descriptor carries a ship-scoped stable
    drop ID, the owning ship ID, a ship-local transform and an exact `item_lots_v1`
    summary, including the holder ledger sequence. The coordinator materializes
    descriptors only while their ship scene is attached and writes partial scoop
    results back to the owner before travel or save. Current-format malformed drop
    data fails the enclosing restore before live state changes; absence migrates as
    an empty legacy collection. P04 adds this nested holder state without changing
    the existing `world-4` outer version reserved for P10's ordered v5 migration.

13. Queued crafting escrow remains physically accounted at its source holder until
    work starts or the escrow is successfully transferred by refund. The scheduler job's
    exact `ingredient_escrow` is the sole serialized reservation authority. Inventory
    holders receive a nonserialized read-through binding and include exact unstarted
    escrow mass in raw player load and hard cargo capacity while keeping it outside the
    spendable lot ledger. Restore rebuilds this view from validated jobs; holders never
    serialize a second reservation copy. A direct refund may exclude only that job's
    authority-verified reservation while staging the return, so its own mass is not
    counted twice and every other job remains counted. Pending-output receipts transfer
    physical mass from source reservation to the ship/station store once; tombstones
    prevent restored producers from republishing the same receipt.

14. Portable field crafting is attended work owned by the active player. Its paid
    job advances only while the playable run is active, the player node is present,
    health is above the existing incapacitation threshold, and stamina is above the
    existing work-inability threshold (`0.001`). Losing attendance pauses the same
    job without spending again, refunding, or restarting it; recovery resumes that
    exact progress. Menu and UI input capture do not remove attendance, and field
    crafting gains no station-radius or hold-input requirement. Home and away runtime
    branches use the same gate, so an end-run transition cannot advance the job later
    in the same frame.

15. Ship selection and mutation authority are separate decisions. The player may
    select a known, physically reachable, unclaimed ship without first owning it;
    access is checked by the requested action. Permanent component install/remove
    requires the applicable ship access, while ordinary salvage and repair retain
    their existing action-specific rules. A new-run home ship may claim
    `player_local`; legacy restore may do so only when owner data is absent, and
    neither path may overwrite a modern foreign owner. `ComponentPlacementState`
    remains the sole durable installed-component authority and
    `ShipModificationState` remains derived, with no second serialized component
    summary. UI bindings carry a nonserialized generation token so a stale panel
    callback cannot target an earlier ship binding. P19 may recover persisted paid
    work only after explicit owner/target revalidation and rebinding to the current
    generation. The additive world-4 `home_access_v1` field carries the home
    `ShipAccessState` summary because `RunSnapshot` has no home-access authority.
    When present it is validated strictly and restored before the home load callback;
    absence alone identifies the recognized legacy bootstrap that may claim locally.
    A modern foreign owner is preserved through disk JSON and is never inferred from
    or replaced by the process-local pre-load home handle. P10 carries this field
    semantically unchanged through world-5 detached validation.

16. Recipe-economy closure uses authored identities and quantity balance. Similar
    IDs are never implicit aliases. A crafted tool may satisfy timed work only
    through an action-specific compatibility row; the coordinator selects the
    concrete compatible lot while WorkActionState continues to validate the
    work-action catalog's required class. This preserves lot quality as the effect
    source without making every item in one broad tool class satisfy every verb.
    Component inventory forms are explicit item definitions whose weight matches
    the component catalog mass. Repair `plating` and mountable `plating_plate`
    remain distinct and are connected by an authored one-way conversion. Economy
    validation computes fixed-point acquisition through real bootstrapped sources
    and reports every zero-power conversion group. It rejects only a proven firing
    combination with no net item deficit and a positive item gain; neutral cycles
    remain valid and visible. Production systems such as hydroponics and water
    recycling count only when their actual input, system, power, seed and station
    prerequisites are reachable.

### P10 migration addendum accepted for implementation

The coordinator accepted the following source-backed P10 decisions on 2026-09-05.
They authorize the bounded P10 implementation, preserve the payload names above,
and preserve the P19 recovery boundary. Acceptance evidence remains pending.

17. Implement the reserved versions as one ordered forward step:
    `gate2-current-run-4` to `gate2-current-run-5`, and `world-4` to `world-5`.
    World migration must migrate and validate its embedded home run through the
    run chain before producing `world-5`; it may not relabel an unvalidated inner
    snapshot. Missing fields in an older recognized version use that migration
    step's documented defaults. A present malformed current field, an unknown
    version, or a future version is rejected before live state changes. Rejection
    leaves the original save bytes and path unchanged and writes no migrated
    sidecar. A migrated sidecar may be written only after the complete detached
    v5 snapshot has passed outer and nested validation.
18. `gate2-current-run-5` adds the current player's exact
    `recipe_knowledge_v1` summary and makes the crafting, field-crafting and
    component-placement summaries strict when present. `recipe_knowledge_v1`
    carries `owner_id`, `known_recipe_ids`, `event_receipt_ids`,
    `event_sequence`, and `dismantle_counts`. A recognized older run that has no
    knowledge payload seeds only recipes authored as starter knowledge and records
    `migration_origin: "legacy_unrecorded"`; it cannot infer book, codex,
    reverse-engineering progress, or event receipts that the old save never held.
19. Historical single-active crafting is converted as paid history because the
    old implementation consumed recipe quantities before serializing
    `active_craft`. The converted job carries `legacy_consumed_history_v1` with
    its source version, historical quality decision, required ingredient item IDs
    and quantities, and `lot_metadata_reconstructable: false`. Deterministic
    history-only lot IDs use neutral migration provenance and the documented
    default quality/condition; they are never returned to inventory, counted as
    escrow, or exposed as newly acquired lots. The job preserves its historical
    progress, required time, quality score/tier/multiplier, and paid status and
    completes without another inventory charge. Legacy station queue IDs were not
    paid; each becomes an ordered `blocked_unreserved` job with no escrow, no
    reserved mass and no refund value. Only current admission may reserve its exact
    lots and make it runnable. This P10 conversion is not P19's player-facing paid
    work recovery policy.
20. Migration must not guess a current physical station from a historical station
    kind. A converted paid active job receives a deterministic migration-only
    station identity under its ship owner, retains the historical station kind,
    and may finish through the bounded legacy executor. That identity cannot admit
    new work. Current v5 jobs retain their authored stable physical station IDs and
    must agree with their restored current station projection. Conflicting active
    craft/station records, duplicate owners or job IDs, and invalid current owner
    projections reject the snapshot rather than selecting a home or same-kind
    station implicitly.
21. Restore is a detached prepare/commit transaction. Validate run/world envelopes,
    inventories and exact lots, job/station projections, pending-output stores,
    field receipt pins, recipe knowledge, equipment and component placement for
    every ship before mutating a live owner or enabling tick/collection. A field
    receipt already pinned to a destination ship remains there across reload; an
    unpublished completed field job has no destination until the current attached
    occupancy supplies one. A present `source_lot` in component placement must be
    a strict valid lot for the installed item or the enclosing restore fails
    atomically. Only absence in a recognized legacy record means unknown source
    identity; a malformed present value is never normalized away.
22. P10 acceptance uses checked-in historical and current JSON fixtures read and
    written through `SaveLoadService`, not dictionary-only model probes. It covers
    the old paid active/unpaid queue distinction, recipe knowledge receipts,
    current station and field pin identity, partial pending collection, nested
    world restore, double reload, malformed-present rejection, and unknown/future
    version rejection. Rejection checks the original file byte for byte and proves
    no live owner changed. Runtime work remains limited to the files approved on
    the P10 card; P09 presentation and P13 selection/binding changes are excluded.

23. Modern player-loadable manual, rotating-auto and quicksave slots persist a
    coherent WorldSnapshot under their existing filenames and slot IDs. This
    supersedes only the ship-only modern-write policy in ADR-0031
    `0031-multi-slot-save-architecture.md` and decision 4 of ADR-0043
    `0043-title-screen-permadeath-freeze-save-and-exit.md`. A field output pinned
    to an away ship requires that ship and its pending store after a fresh-process
    load. World v5 owns the canonical `home_pending_outputs_v1`; visited ships own
    their stores. Do not add a duplicate pending authority to the embedded run.
    Current run v5 is an internal world member, not an independently loadable slot;
    reject a standalone current run as `unclosed_owner_graph`. Recognized run
    v1-v4 slots remain readable through detached legacy adaptation only when their
    owner graph is closed. Preserve originals, slot families and permadeath rules.
24. All slot routes share one detached restore candidate with source hash/token,
    effective target run ID, validated owner models and staged scene consequences.
    The loaded world run ID determines `player:<run-id>` during preparation;
    recognized missing legacy IDs receive one explicit candidate ID. Bound legacy
    knowledge retains its evidence marker and remains valid after two resaves.
    Adopt the live run ID only on successful commit. Validate every inventory,
    equipment holder, component against the actual layout, station, job, escrow,
    pending receipt and field pin across home and visited ships before mutation.
    Reject duplicate authoritative lots, incompatible job/store states, missing or
    conflicting receipts and orphan craft records; consumed history is not escrow.
25. Restore commit must stage scene roots before swapping, or provide complete
    whole-world rollback demonstrated by an injected post-rebuild failure. Merely
    returning false after partially changing live owners is insufficient. Keep
    ticks, output publication, collection and station input disabled through the
    transaction. Recheck source identity before commit; publish a migrated sidecar
    only after successful commit. No failed candidate may alter original bytes,
    live quantities, ownership, scene state or receipts.
26. P10 uses ADR-0066's component lot initialization contract:
    `condition_authority_version: 1`, `condition_lot_sequence`, and the persistent
    `ship:<ship-id>:components` holder namespace. Fresh generated components gain
    exact neutral lots with `generated_component` origin through explicit owner
    initialization. Only trusted pre-v5 migration provenance permits missing
    historical lots to become `legacy_unrecorded_component` lots. A source already
    labeled v5 receives no such privilege; present malformed lots always reject.
    Prepare missing lots detached in stable slot order and advance the sequence
    only when the candidate commits. Do not add a second provenance flag or
    relabel fresh generated components as legacy. Current capture and second reload
    retain the same exact lot identities and conditions.

27. The P10 atomic scene boundary may stage a replacement PlayableGeneratedShip
    from the same authored scene, then swap the owning main/title instance and
    reconnect signals only after validation. Explicit restore-staging mode must
    suppress startup writes, meta run/death/unlock counters, service identity
    mutation, global input/audio registration and visible HUD/CanvasLayers, as
    well as ticks and collection. Disabled processing alone does not suppress
    `_ready` side effects. Failure frees only the staged candidate and leaves the
    existing playable world and shared services intact. Verify an injected failure
    after staged scene rebuilding before accepting this boundary.
28. Physical crafting stations retain their actual attached ship owner and stable
    station identity across player occupancy changes. ShipWorkContext may inject
    the existing shared owner-keyed CraftingState reference; it does not introduce
    per-ship duplicate schedulers. UI and interaction validate the exact owner key,
    current binding generation, selection, occupancy, action-specific access and
    spatial range. An off-board home station cannot act as an away fallback.
29. Staged restore must successfully apply every persisted authoritative subsystem
    summary and recapture the complete prepared world before publication. Reject
    malformed present summaries and any authoritative mismatch; valid defaults in
    a recaptured candidate do not excuse discarded saved values. Normalization is
    limited to explicitly documented derived fields, never inventory, progression,
    settings, system condition, ownership or receipt content. Prove nondefault
    roundtrips and malformed audio, settings and ship-system denials.
30. Recoverable terminal receipts retain exact producer history after escrow is
    released. Validate original lots, producer identity, terminal outcome and
    sequence against that history, including field outputs and cancellation
    refunds. Syntactically valid forged content or future receipt sequences must
    reject before publication. Historical unmounted component records are not
    additional live lot authorities; immutable lot origin describes creation,
    while current placement describes its present slot. Legitimate same-ship and
    cross-ship moves preserve that origin and survive two reloads.
31. Restore each visited crafting owner's exact inventory, station and pending
    bindings before its first elapsed-time catch-up. An unavailable context must
    not silently advance the owner's last simulation timestamp and discard work.
    Verify a restored inactive derelict's first revisit completes due work once,
    retains its pending output, and permits exact-once player collection across
    two reloads.
32. Mandatory terminal history uses nested `craft-jobs-2` and `field-pending-2`
    contracts; it must not silently change the meaning of an existing v1 payload.
    Migrate recognized `craft-jobs-1` and prior unversioned field-pending summaries
    in detached copies, preserving exact paid, consumed and output lots. A prior
    cancelled job with consumed lots records forfeiture. A cancelled job without
    reconstructable refund history retains an explicit
    `legacy_unrecorded_cancelled_v1` history-only tombstone, which can never
    authorize a refund. Surviving refund receipts may supply exact history only
    after complete job, owner, station, ingredient and receipt reconciliation.
    An old field receipt without reconstructable terminal producer history rejects
    with a specific diagnostic and leaves the source untouched; migration must
    not discard it or invent a producer. Empty prior field history is permitted
    only without an extant field receipt. Missing mandatory fields in a v2 record
    are malformed, never a request for legacy migration. Verify valid prior-v5
    terminal-state resave and two reloads alongside v2 history-deletion mutants.
    The prior v1 cancelled-job format retains no independent refunded-lot identity
    or quality evidence. A matching pending refund therefore rejects with
    `legacy_refund_history_unavailable`; its own lot records cannot be copied into
    newly invented producer history to make the pair appear validated. The original
    save remains untouched. Without a pending refund, the inert terminal tombstone
    remains loadable and survives resave. Normal started-work cancellation retains
    exact consumed history as forfeiture and must remain loadable without a refund.

## Locked transaction payloads

The following additive payload names are the inter-card contract. They are
serialized only at coherent transaction boundaries and are owned by the holder
named below. P03/P07/P10 may add nested fields needed for validation, but may not
rename these keys without a superseding ADR.

| Payload | Owner | Required identity / exactly-once fields |
|---|---|---|
| `item_lots_v1` | inventory or holder | `lot_id`, `item_id`, `quantity`, `quality_score`, `quality_tier`, `condition`, `origin` |
| `craft_jobs_v1` | ship/station scheduler | `job_id`, `ship_id`, `station_instance_id`, `recipe_id`, `state`, `progress`, `ingredient_escrow`, `output_receipt_id` |
| `pending_outputs_v1` | ShipInstance / physical station holder | Superseded for this row by [ADR-0062](0062-ship-owned-pending-output-receipts.md): `schema`, `ship_id`, and receipt records containing station/producer/purpose/source identity, immutable `original_lots`, `remaining_lots`, `collected_quantities`, and terminal state |
| `recipe_knowledge_v1` | current-run player | `owner_id`, `known_recipe_ids`, `event_receipt_ids` |
| `work_transactions_v1` | selected ship | `work_id`, `ship_id`, `target_id`, `target_revision`, `state`, `escrow`, `commit_receipt_id` |
| `structural_rebuild_v1` | ShipInstance/pillar persistence | `replacement_id`, `module_id`, `layout_revision`, `wrapper_id`, `transform`, `footprint`, `sockets`, `state` |
| `floor_drops_v1` | ShipInstance | `ship_id`, `sequence`, and drop records containing `drop_id`, ship-local `transform`, and exact `item_lots_v1` summaries |

`job_id`, `work_id`, and every receipt ID are idempotency keys. Retrying an already
committed ID is a no-op; an incomplete transaction retains recoverable escrow.

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
