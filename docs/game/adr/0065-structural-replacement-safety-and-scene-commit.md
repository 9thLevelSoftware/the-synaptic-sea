# ADR-0065: Structural replacement safety and scene commit boundary

- Status: **Accepted for implementation; runtime validation and all-15 BOM acquisition proof remain pending.**
- Date: 2026-09-05
- Requirements: FC-18, FC-19, FC-20, FC-22.
- Related: ADR-0051, ADR-0053, ADR-0056, ADR-0059, ADR-0061, ADR-0062.
- Feature spec and acceptance register: [`crafting_derelict_feature_completion.md`](../features/crafting_derelict_feature_completion.md#acceptance-register), especially FC-18 and FC-19.
- Design review: `../../../.superpowers/sdd/2026-09-04-crafting-derelict-feature-completion/P17-design-review.md`.

## Context

ADR-0059 establishes that destroyed structural modules retain immutable original
identity, paid replacement stays inside the original footprint/socket contract,
scene preflight occurs before material commitment, and geometry/navigation/
atmosphere effects commit as one logical operation. P16 now captures original
descriptors and P12 owns exact-lot work escrow and receipts. P13 binds mutations
to an explicit live ship owner.

The remaining safety contract is not representable through the existing APIs:

- `ShipOccupancy` identifies which ship contains the actor, not whether the
  actor's collision body intersects a candidate wrapper;
- parked cart summaries and component slot IDs are not authoritative world
  collision geometry;
- active docking relationships retain transforms but no stable structural
  module/edge identity;
- preview path probes do not define required gameplay egress;
- `SliceAtmosphereApplier` applies fog and light, not structural enclosure;
- `ModularSocketCatalog.load_kit()` may fall back to v0, which is unsafe as an
  authorization decision;
- P12 currently discards the result of its stage callback and has no explicit
  staged-resource cleanup callback.

Kit identity also has two layers. Generated layouts name the selected biome kit,
but the active hazard and industrial layouts currently resolve their structural
contract through v0, as does the lifeboat. Biomatter is an active authored hive
template whose module records explicitly name v0 contract resources. The ithappy
catalog is supported catalog data, not an active replacement layout. These are
source observations, not proof that every tuple is reachable in production. A
replacement check must preserve the authored layout identity while authorizing
against the exact wrapper/socket contract actually captured for that module.

## Decision

### 1. Replacement coverage and economy authority

P17 covers all 15 active structural module IDs across every active layout/contract
combination. An unknown custom module or contract remains visibly unsupported.
No catalog fallback grants replacement permission.

`data/construction/structural_rebuild_catalog.json` is the sole replacement
policy/BOM authority. Every active row names an exact original module, exact
structural contract identity, same-module replacement, wrapper, footprint,
socket mapping, work action, materials, tool, skill and duration. The initial
policy authorizes only replacement with the same original structural module ID,
at the original transform, with no arbitrary rotation or topology change.

The existing `ship_structural_v0.materials.json` default is not a BOM. It is not
loaded by the replacement runtime and may not be used to fill missing rows.
P09's economy graph must prove that every referenced material and compatible
tool has a real acquisition route. Runtime uses only explicit rows below; no inferred aliases or defaults.


### 1A. Root-selected initial rebuild balance

This is root-selected initial gameplay balance, accepted for implementation and
subject to later explicit data review. Acquisition verification remains pending.
Every active exact contract tuple carries the explicit row below: runtime uses
only explicit rows below, with no inferred aliases or defaults.

| Module | Seconds | Consumptive BOM |
|---|---:|---|
| floor_1x1 | 8 | plating:1, scrap_metal:1 |
| floor_2x1 | 14 | plating:2, scrap_metal:2 |
| corridor_floor_1x1 | 8 | plating:1, scrap_metal:1 |
| corridor_floor_1x2 | 14 | plating:2, scrap_metal:2 |
| wall_straight_1x1 | 10 | plating:1, scrap_metal:2 |
| wall_end_cap | 6 | plating:1, scrap_metal:1 |
| wall_inner_corner | 12 | plating:2, scrap_metal:2 |
| wall_outer_corner | 12 | plating:2, scrap_metal:2 |
| wall_t_junction | 16 | plating:3, scrap_metal:3 |
| doorway_frame_open_1x1 | 12 | plating:1, scrap_metal:3 |
| doorway_frame_blocked_1x1 | 16 | plating:2, scrap_metal:3 |
| bulkhead_portal_2x1 | 22 | plating:3, scrap_metal:4, wiring_spool:1, circuit_board:1 |
| ramp_up_1x2 | 16 | plating:2, scrap_metal:3 |
| pillar_support_1x1 | 8 | plating:1, scrap_metal:2 |
| ceiling_cap_1x1 | 8 | plating:1, scrap_metal:1 |

All rows use `rebuild_structure`, repair skill minimum 0, and the required
`welding_lance` class. `welder` is compatible with `rebuild_structure` and
`weld_patch`; `plasma_cutter` is not compatible with rebuild. Replacement is
same-module only, has no yields, denies intact originals, and preserves current
portal open/unlocked state without granting unlocks.

### 2. Immutable structural identity

Every P16 original descriptor and its structural fingerprint carry:

- `layout_kit_id`: the exact kit ID authored on the generated layout;
- `structural_kit_id`: the exact kit that owns the captured wrapper/socket
  contract used for this module;
- `structural_contract_id`: the exact contract resource identity when the
  layout kit delegates to another kit;
- the existing module, wrapper, transform, footprint, socket/binding,
  room/edge/component/system and layout revision/fingerprint fields.

If the current layout kit and resolved structural contract differ, both values
remain explicit. Socket authorization loads `structural_contract_id` directly
or requires an exact no-fallback load of `structural_kit_id`. Failure returns
`missing_socket_contract`; it never retries v0 implicitly.

P19 may reconstruct these fields for a legacy save only by regenerating the
verified current baseline and matching the saved stable module ID, wrapper,
transform, footprint, sockets and layout identity. A mismatch rejects restore;
it does not guess a kit or rewrite the save.

Rebuild authorization is separate from loading existing structure. A wrapper-valid
placement with absent or conflicting rebuild contract metadata must retain its
physical wrapper and P16 original descriptor from the actual authored placement
and kit fields. Record the unavailable contract explicitly and deny replacement;
do not abort the whole ship load or invent a fallback contract. Invalid geometry
and invalid placement data still follow the existing loader rejection policy.
Regression tests must exercise `load_from_documents()` for these unsupported
contract cases, not only the contract-resolution helper.

#### 2A. Exact integrity ownership

Each `StructuralRebuildState` binds once to the exact `ModuleIntegrityMap` that
created it and retains that identity through a `WeakRef`, avoiding an ownership
cycle. Replacement evaluation rejects every other object, including a
method-compatible adapter that returns the real rebuild registry. The rebuild
state resolves the immutable original descriptor from its own `_originals`
registry; the bound map supplies only the corresponding live integrity state.
Caller-provided inspection dictionaries never grant replacement authority.

The binding seam verifies the concrete production script and object identity.
It has no home/current-map fallback and cannot be rebound after construction.

#### 2B. Canonical runtime catalog authority

P17 adds a concrete `StructuralRebuildCatalog` service that reads only
`res://data/construction/structural_rebuild_catalog.json`. It strictly validates
the document and every active row before publishing a recursively read-only,
service-owned row registry. Failed validation publishes no partial registry.
There is no runtime alternate-path loader, balance default, module-name
derivation, or code copy of the catalog BOM.

Replacement evaluation accepts a row ID and resolves it from that exact concrete
catalog authority. It never accepts an arbitrary caller dictionary, even when
that dictionary has the right schema and structural identity. Material IDs and
amounts, tool class, skill ID and threshold, and duration therefore remain equal
to the shipped canonical row. Tests mutate each of those fields while preserving
valid JSON types and prove the mutation cannot authorize a plan.

#### 2C. Independent loader/contract identity evidence

The 60 active policy tuples are checked with independent actual and expected
sides. The actual descriptor side comes from the production layout, the exact
structural kit/module record chosen by generation, the loader's no-fallback
contract resolution seam, and the loaded contract `Resource` properties. The
catalog supplies only the expected policy side.

The proof explicitly covers v0, hazard-layout-to-v0-structure,
industrial-layout-to-v0-structure, and biomatter-layout/biomatter-kit-to-v0-
contract paths. Missing or mismatched contract resource, wrapper, footprint,
socket, and layout/kit/contract identity deny before policy admission. This is
preparatory identity and pure-policy evidence; it is not the live FC-19 safety
preflight or an `FC P17 PASS` claim.

### 3. P17 policy and live preflight

`StructuralRebuildState` remains pure. It evaluates a replacement request,
original descriptor, exact catalog row/socket contracts, P13 ship binding and a
read-only safety snapshot, producing an immutable `ReplacementPlan` or a stable
denial reason. It never reads the scene tree or removes inventory lots.

P17 adds a scene-owned `StructuralRebuildPreflight` node. The selected ship's
coordinator adapter supplies the exact `ShipInstance`, loader, player body, live
cart controls, component placement/markers, active docking relationships and
navigation authority. The node stages candidate collision geometry only for
read-only queries; it performs no live structural, component, docking, nav or
air mutation.

Preflight checks the candidate wrapper against actual actor, parked/grabbed cart,
mounted component and physical cargo geometry. Abstract cargo inventory contents
have mass but no spatial volume and are not geometry blockers. Mounted component
displacement is allowed only when an exact source lot and an authored P18 recovery
policy exist; otherwise it returns `component_recovery_unavailable`.

P17 revalidates the live snapshot in P12's completion stage. Start-time success
does not authorize completion after an actor, cart, component or docking change.
A monotonically changing, session-local safety revision and P13 binding/target
revision bind the plan. Scene nodes, physics RIDs and safety snapshots are never
serialized.

#### 3A. Explicit physical-volume authority

`data/physics/runtime_physical_volume_profiles.json` is the sole runtime
authority for cart, floor-drop, and mounted-component gameplay solids used by
P17. Each strict row owns its shape kind, dimensions, local transform, collision
layer/mask, and blocking purposes. Runtime may not infer dimensions from an
interaction radius, marker or imported mesh, visual bounds, or a default. The
collision-free imported-visual boundary remains unchanged.

The initial rounded gameplay boxes, in metres as width, height, depth, are:

| Profile | W | H | D | Mount | Local position [x,y,z] | Local yaw degrees |
|---|---:|---:|---:|---|---|---:|
| cart | 0.75 | 0.56 | 0.50 | floor | [0,0.28,0] | 0 |
| floor_drop | 0.35 | 0.25 | 0.35 | floor | [0,0.20,0] | 0 |
| air_recycler | 0.80 | 0.56 | 0.60 | deck | [0,0.28,0] | 0 |
| conduit | 0.30 | 1.00 | 0.22 | wall | [0,0.50,0.11] | 0 |
| console_generic_wall | 0.60 | 0.54 | 0.34 | wall | [0,0.27,0.17] | 0 |
| console_generic_deck | 0.60 | 0.54 | 0.34 | deck | [0,0.27,0] | 0 |
| hull_plating | 1.00 | 1.00 | 0.08 | wall | [0,0.50,0.04] | 0 |
| locker_wall | 0.60 | 0.75 | 0.34 | wall | [0,0.375,0.17] | 0 |
| machinery_block | 0.80 | 0.90 | 0.60 | deck | [0,0.45,0] | 0 |
| nav_console | 0.90 | 0.71 | 0.36 | wall | [0,0.355,0.18] | 0 |
| pump | 0.40 | 0.52 | 0.40 | deck | [0,0.26,0] | 0 |
| reactor_console | 0.60 | 0.75 | 0.35 | wall | [0,0.375,0.175] | 0 |
| sensor_rack | 0.40 | 0.78 | 0.28 | wall | [0,0.39,0.14] | 0 |
| thruster_control | 0.68 | 0.48 | 0.37 | wall | [0,0.24,0.185] | 0 |

These are explicit authored values, including zero coordinates and yaw; absent
fields never default to them. Compose `world = ship * mount_anchor * profile_local`.
The mount anchor lies on the deck surface or wall/deck intersection; its +Y is
ship up and its +Z is the registered wall interior normal (deck +Z is its authored
forward). Foundation rows declare only `structural_rebuild` as their blocking
purpose. A later reviewed integration may add player-motion capability.

Except for `floor_drop`, a floor/deck profile uses local Y equal to half its
height and local Z zero. A wall profile uses local Y equal to half its height and
local Z equal to half its depth toward the registered interior normal. The two
console variants prevent runtime wall/deck inference. The current project layer
inventory uses only layer bit 1. The foundation reserves layer bit 2 with mask 0
for passive physical projections; the isolated candidate body uses private-space
layer bit 1. A later player-motion slice must explicitly add projection bit 2 to
the player mask together with swept cart behavior. These initial dimensions
require real scene clearance verification; they are not illustrative fixture
boxes or a final-art acceptance claim.

The foundation slice adds only the strict catalog, primitive builder, and exact
query helper. It does not add or change cart movement. A later cart integration
may make the projection block player motion only after it specifies deterministic
swept/clamped push-follow, actor/cart exclusions, and blocked-motion behavior.
Until then it may provide truthful scene-owned obstruction geometry for P17
queries without claiming push physics.

#### 3B. Incremental candidate query and base-world clearance

P17 creates one private `PhysicsServer3D` space containing only the detached
candidate wrapper's exact authored shapes on a dedicated query layer. It uses
`PhysicsDirectSpaceState3D.intersect_shape()` for blocker overlap and
`cast_motion()` for continuous capsule sweep with zero margin. The query preserves
shape rotation and local offset and cleans every temporary RID. A missing direct
state returns pending/unsupported through the stable P13 token/context
revalidation path; it never falls back to AABBs or sampled points.

One path-clear operation must first check exact start and final poses with
`intersect_shape()`, then sweep each nonzero segment with `cast_motion()`.
Initial overlap must never be accepted from a clear sweep fraction. A zero-length
segment still requires the pose-overlap check. Foundation tests cover start/end
overlap, zero-length clear/blocked poses and a thin rotated obstacle mid-segment.

This private query proves only obstruction newly introduced by the candidate.
Every accepted route must also pass an independent existing-world clearance
query against authoritative unchanged solids, closed portals, and dynamic
blockers, excluding only the attending actor's own body and the destroyed
target's already-disabled shapes. Candidate safety is the conjunction of pure
candidate topology, existing-world clearance, and candidate-only continuous
sweep. No candidate-only result may be described as full path clearance.

### 4. Docking and registered exits

Every boarding/docking port used by production receives stable authored identity:

- `port_id`;
- owning `ship_id` when bound live;
- stable `target_module_id`, structural module kind and `structural_edge_key`
  when the endpoint is edge-owned;
- endpoint ID and local/world transform;
- distinct `threshold_nav_node_id` and `interior_nav_node_id`, each resolving a
  real clearance-sized point rather than near-identical samples of one location;
- type, size and current condition/usable state.

The loader registers the existing production `DockPorts` position/facing once
against its exact structural plan. Registration must resolve one stable floor or
edge target and, where applicable, one authored portal; missing or ambiguous
mapping fails. This preserves current docking geometry while preventing P17 from
repeating `DockPorts` room-role/name-prefix guesses as authorization. The loader
then exposes registered boarding/airlock endpoint descriptors.

`DockingManager` retains the exact host and mobile port identities in one
connection record, and both `parent_ship` and `docked_ships` views resolve that
same connection. Replacing a module/edge that owns an active connection is
denied. Replacement never auto-undocks a ship.

### 5. Candidate-result egress policy

Egress is evaluated against the candidate result, not only the destroyed scene
before replacement. The candidate must provide a path from the attending actor
to at least one registered boarding/airlock endpoint that is usable in the
candidate state.

Before candidate evaluation, the scene snapshot freezes one connected-side
obligation for each endpoint side of every active docking connection. A usable
endpoint record must resolve distinct stable threshold and interior anchors. The
interior anchor is the deterministic first authored navigation node strictly
inside the owning ship beyond the endpoint-owned edge/footprint. It must have a
traversable neighbor other than the threshold, and the baseline path must contain
at least one real graph edge and separate the two world points by at least the
current traversal-capsule diameter. The existing-world authority must prove
continuous clearance along that path into the ship's interior route network.
Missing, ambiguous, near-identical, dead-end, or disconnected anchors on an
endpoint marked usable make live safety unsupported; they do not erase the
obligation. The candidate must retain the same stable threshold-to-interior
anchor path on each previously usable side.

This preserves the path on both connected ships without requiring every docking
endpoint to be reachable from the attending actor. An endpoint that was already
sealed or unusable creates no preservation obligation, but it cannot satisfy the
actor's candidate exit rule. Replacing the exact module or edge that owns either
side of an active connection remains `active_dock_connection` and never
auto-undocks the ships.

A target may itself restore a registered exit from unusable to usable. Therefore
having no usable exit before work does not automatically reject the replacement;
the candidate result must prove that it creates a valid path. Conversely, if the
candidate result has no usable registered exit, preflight returns
`egress_blocked`. Tests must include the accessible wreck/starter restoration
path so the rule cannot deadlock the feature.

`ShipNavGraph` gains a pure candidate-path query over copied topology and explicit
stable threshold/interior endpoint anchors. P17 uses it for policy. The scene
preflight separately checks existing-world clearance and candidate-only
continuous collision sweep for each returned segment. Neither path query mutates
the live graph.

The first navigation slice is deliberately a pure, untrusted, per-ship helper.
It classifies each authored record as an internal pair, vertical pair, exterior
boundary, or unresolved record, then combines live structural eligibility with
base clearance that excludes only the destroyed target and detached candidate.
It retains independent blockers and momentary portal state, so a closed portal
blocks even when unlocked. A target overlay cannot turn false base clearance
true. The helper returns `scene_authorized: false`; later scene preflight binds
the exact ship/map/layout/graph/portal/clearance revisions before using it.

The native seed-17 fixture has four legitimate non-solid exterior boundaries:
`0|h|3|5`, `0|h|7|6`, `0|v|3|4`, and `0|v|3|9`. They have one occupied side and
must classify as exterior boundaries without manufacturing an internal node.
Conversely, coherent fixture 002 edge `0|h|-1|2` is non-exterior and unresolved;
the helper reports it as unsupported internal data rather than silently passing.

An exterior boundary record does not register an exit. Actor egress requires a
separate exact registered endpoint DTO; missing registration remains
`missing_registered_exit`. The bounded helper denies an exterior target and
floor/ceiling target as unsupported. It checks only connection sides local to its
one graph; a remote ship/endpoint identity is required but never resolved against
local nodes. The coordinator must evaluate the remote ship's graph separately
and require both local-side results. Its standalone preparatory smoke cannot emit
or satisfy `FC P17 PASS`.

### 6. P18 APPLYING/finalize scene lifecycle

Detached preparation remains outside P12. Existing simple P12 actions retain
their synchronous behavior. The proposed P18 interface is scene-owned and
explicit: `begin_stage(plan, snapshot)`, `poll_stage(token)`,
`discard_stage(token, reason)`, `begin_apply(token, context)`,
`finalize_success(token, context)`, and `finalize_rollback(token, reason)`.
These names specify the future interface; they do not claim implementation.

Only a READY, fully prepared token may enter APPLYING. P12's synchronous stage
callback claims that token, revalidates access/revisions, retains escrow and
returns `applying` with no receipt; it never awaits or reports structural
success. The coordinator establishes a short barrier over the affected ship and
every connected docked ship: structural movement, WorkActions, actor/cart
simulation, and save capture pause while the physics server continues to sync.
The barrier is established only after the final P17/P13 checks.

`begin_apply` journals every mutable authority before exposing the candidate:
the wrapper and integrity/rebuild record; one shared edge and both room bindings;
exact-lot component recovery; current portal open/unlocked state; navigation;
structural enclosure/air; and rebuild markers. It must preserve the current
portal state, rebuild both affected rooms and the shared edge exactly once, and
must not seal an unrelated hull breach, scripted breach-zone objective, or grant
an unlock. The coordinator polls real collision, navigation-server and air
coherence before `finalize_success`.

Only `finalize_success` disposes the token, emits the one P12 receipt, and
releases the barrier. `finalize_success`, `finalize_rollback`, cancel, restore,
and token disposal are each single-entry operations: duplicate or re-entrant
calls are denied. An APPLYING failure uses `finalize_rollback`, restores the
full journal, waits for and verifies old collision/navigation/air coherence,
then returns P12 to READY with retained escrow and its reason before releasing
the barrier. Rollback assets survive until that finalization completes.

P19 never serializes tokens or APPLYING: save capture waits or returns busy.
Crash recovery restores the last committed snapshot's recorded inventory and
escrow ownership without inferring completion, double-charging, or duplicating
output.

### 7. Persistence boundary

P19 remains the owner of `structural_rebuild_v1`, interrupted transaction
recovery and reconstruction order. Generation creates originals; verified
replacements apply; integrity, components and systems restore; derived nav and
air recompute; only then may active simulation tick. P17/P18 add no separate save
schema and never serialize scene handles.

## Rejected alternatives

1. **Use module families, name prefixes or socket-catalog fallback.** Rejected
   because same-family and same-kind sockets are not automatically compatible,
   and fallback can authorize against a contract that was not captured.
2. **Use room occupancy, positions or AABBs alone.** Rejected because actors,
   carts, components and candidate wrappers have real collision volumes and a
   grabbed cart can make its parked summary stale.
3. **Require a usable exit before replacement starts.** Rejected because the
   target replacement can be the operation that restores the exit and would
   otherwise be permanently deadlocked.
4. **Auto-undock or alter topology to make safety pass.** Rejected because it
   changes existing docking/layout rules and can strand or move live ships.
5. **Let the pure rebuild model mutate scene/nav/air state.** Rejected because it
   violates ADR-0059's model/scene ownership boundary and prevents reliable
   rollback testing.

## Consequences and controls

- P17's production scope is larger than its original brief: it needs a read-only
  scene preflight, exact loader/port/endpoint identity, docking relationship
  fields, a candidate path query and narrow coordinator request wiring.
- P17 first lands a bounded foundation slice for the canonical physical-volume
  catalog, primitive builder, and private candidate-only query. The existing P17
  card remains the sole FC-19 owner and cannot claim FC-19 from foundation proof.
  Cart/drop/component/dock/coordinator integration follows in separately reviewed
  windows after shared P10/P13 source ownership is released.
- P18's scope must include the P12 staged-token callback extension.
- P18 staging is an explicit asynchronous preparation state outside synchronous
  P12 commit. Pending/failed preparation retains READY escrow; a commit receipt
  is withheld until nav/physics/air readiness is proven.
- All 15 active module IDs require explicit catalog rows and P09 reachability
  evidence before P17 acceptance; unknown future/custom rows stay blocked.
- Descriptor fingerprint expectations change when kit/contract identity is
  added. P16 and current-layout deterministic tests must be updated together.
- Docking summaries may gain additive stable identity fields; existing movement
  math and compatibility rules remain unchanged.
- Live FC-19 acceptance requires actual player/cart/component/docking/egress
  paths. Synthetic safety dictionaries are unit tests only.
- Any unexpected Godot warning/error, partial scene state, consumed escrow without
  a receipt, or first tick observing mixed air/nav state blocks acceptance.

