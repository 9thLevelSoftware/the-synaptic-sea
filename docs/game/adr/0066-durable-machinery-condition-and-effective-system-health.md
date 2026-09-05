# ADR-0066: Durable machinery condition and effective ship-system health

- Status: **Accepted for implementation; governance mapping accepted and recorded.
  Runtime work waits for stable P10/P13 integration.**
- Date: 2026-09-05
- Requirements: FC-16, REQ-SMOD-001; preserves REQ-CMP-001, REQ-CMP-002, and
  REQ-CMP-003.
- Related: ADR-0059 decisions 2, 6, 10, 15, and 21; P10 save migration; P13
  per-ship work context; P19 recovered work.
- Implementation brief:
  `../../../.superpowers/sdd/2026-09-04-crafting-derelict-feature-completion/P14-implementation-brief.md`.

## Context

The current ship-modification coordinator changes logical system health as a side
effect of mounting. A linked install raises a subcomponent to `0.55`, dismount
subtracts `0.6`, and plating install repairs structural integrity by `0.15`. Restore
replays some of these effects. These values have no component-condition or system
repair source, and they make repeated mounting a free repair path.

ADR-0059 instead gives an installed component an exact source lot, makes placement
the durable occupancy authority, and requires reversible work to preserve item
identity. The component catalog gives each linked component one system/subcomponent
target, but generated ships may mount repeated instances. The catalog relation is
therefore many physical providers to one logical target:

| Component | Target | Existing paid repair requirement |
|---|---|---|
| `reactor_console` | `power.power_distribution` | `power_cell`, welder, repair 2, 10 s |
| `air_recycler_unit` | `life_support.air_recycler` | `oxygen_filter`, welder, repair 2, 12 s |
| `nav_console` | `navigation.nav_computer` | `circuit_board`, welder, repair 3, 12 s |
| `thruster_control` | `propulsion.nav_linkage` | `circuit_board`, no tool, repair 2, 8 s |
| `sensor_rack` | `scanners.signal_processor` | `circuit_board`, welder, repair 3, 11 s |

A single damage value cannot represent both removable hardware and independent
ship-side damage. It would either heal a damaged lot when remounted, make a healthy
paid replacement ineffective, or let replacement erase seeded ship damage and
bypass the authored repair BOM.

## Decision

### 1. Durable condition and link authority

`ComponentPlacementState` owns installed machinery condition. For a native entry,
`source_lot.condition` is canonical and the entry's `condition` field is an atomic
mirror. Every mutation updates both copies together. Dismount returns the exact
unchanged lot. Remount reads that lot and grants no condition floor.

Catalog links and deterministic soft links are placement associations. An explicit
catalog link on an incoming component takes precedence. A same-slot replacement whose
definition has no explicit link retains the slot's prior soft-link association. For
each system/subcomponent pair, placement reports all mounted providers in stable
`component_instance_id` order:

```text
connected = mounted_providers.size() > 0
provider_condition = max(provider.condition for mounted_providers)
```

Removing one of several providers preserves the connection. Removing the last
provider disconnects the target without damaging intrinsic health or any lot.
This preserves REQ-CMP dismantle/disables behavior through an explicit connection
state rather than a hidden destructive write.

### 2. Intrinsic and effective system health

`ShipSubcomponent.health` remains intrinsic ship-side health and remains the value
stored in the systems summary. `ShipSystemsManager` binds non-owningly to the current
ship's placement owner and derives effective health:

```text
unmapped target:
    effective_health = intrinsic_health
mapped, no mounted provider:
    effective_health = 0
mapped, at least one mounted provider:
    effective_health = min(intrinsic_health, provider_condition)

effective_functional = effective_health >= authored operational_threshold
```

The two owners never persist the derived value into each other. Restore binds both
owners and recomputes; it does not replay install effects.

`ShipSystemsManager` is the production query boundary. It provides effective
subcomponent health/functionality and effective system health, and uses them for
dependency resolution, status, and `advance()`. Raw `ShipSubcomponent` and
`ShipSystem` health/functionality methods remain intrinsic-only operations for
configuration, persistence, and isolated model tests.

Every production consumer that currently bypasses the manager must be routed through
effective queries: power rebalance; repair-point creation, start, and target revision;
fire seed/context damage classification; coordinator compatibility summaries; HUD and
route consequences; and objective/validation helper decisions. Lifeboat opening damage
uses an explicit manager intrinsic initializer instead of coordinator field writes.
Focused tests must reject new direct health/functionality decisions in those files.

### 3. Damage, replacement, and repair

Damage is applied once:

- a mapped target with mounted providers damages each mounted provider through the
  placement condition API and leaves intrinsic health unchanged;
- a mapped but disconnected target damages intrinsic health, because its removed
  inventory lot is no longer exposed on the ship;
- an unmapped target retains current intrinsic damage behavior;
- whole-system damage applies the same rule to each target.

A distinct healthy replacement can therefore recover component-side damage when
intrinsic health is already functional. Remounting the same damaged lot returns the
same limited effective health. A healthy replacement cannot erase seeded or
disconnected intrinsic damage.

Paid repair retains the exact current BOM, tools, skill, and duration from
`systems.json`. A mapped disconnected target is rejected with
`disconnected_component` before reservation. A successful connected repair sets
intrinsic health to `1.0` and repairs one mounted provider, the first in stable
instance-ID order, to `1.0` in the same commit. Other redundant damaged providers
stay damaged. This guarantees that a paid repair makes the selected target effective
without creating new parts or changing its BOM.

`force_repair` obeys the same authority. It may repair an unmapped intrinsic target
or a connected target plus its deterministic provider. It returns `false` for a
mapped disconnected target. Objective bridges and validation helpers may call this
API but may never fabricate, mount, or repair a missing provider.

### 4. Derived power, station tier, capacity, and plating

All machinery effects are projections of current placement and catalogs:

- A mounted ship-mod-managed component uses the existing catalog power draw divided
  by the P05 quality multiplier. A dismounted component draws zero. Condition does
  not discount draw because no authored condition-to-power curve exists.
- System capacity is the effective-health projection above. P14 adds no numeric
  capacity catalog values.
- A mounted component grants its full authored integer station-tier bonus only while
  condition meets the existing `min_operational_ratio` (`0.5`); below it grants zero.
  Existing maximum and affinity rules remain unchanged.
- Plating resistance is derived as
  `clamp(2 * sum(0.05 * mounted_plating_condition), 0, 0.5)`. Plating install/remove
  never changes module integrity.

Install preflight and timed commit use the lot's full quality-adjusted draw. Commit
revalidates the current power budget. Failure leaves escrow, placement, tier, system,
and inventory unchanged. `ShipModificationState` may summarize projections for
diagnostics, but restore cannot install entries or apply incremental effects.

### 5. Fresh and legacy lot initialization

The additive component summary fields are `condition_authority_version: 1` and
`condition_lot_sequence`. Lot IDs use the persistent
`ship:<ship-id>:components` holder namespace and a monotonic sequence.

Fresh procedural placements receive complete neutral-quality lots at initial owner
binding, with catalog default condition and generated-component origin containing the
ship ID, slot ID, and placement seed. Only a caller mode explicitly admitted by P10
as recognized legacy may initialize a saved entry with no lot. It uses the saved
entry condition when present, otherwise the catalog default, and records neutral
unknown provenance. A present malformed lot or a current-format missing lot remains
a P10 rejection.

Initialization is detached and revision-checked. Prepare clones placement and its
next sequence, visits missing lots by stable slot ID, and returns a candidate without
mutating live state. Repeating prepare on the same base returns identical IDs. Commit
rechecks the base revision and atomically replaces records plus advances the sequence
by exactly the committed allocation count. Cancelled, stale, rejected, and repeated
prepares consume no sequence values and lose no lots. Restore never allocates again
after the authority version is committed.

### 6. Audited REQ-SMOD-001 supersession

The frozen acceptance register cannot accept raw text drift merely because the leaf
count remains constant. The accepted metadata window records this exact one-for-one
mapping:

| Field | Original frozen leaf | Replacement leaf |
|---|---|---|
| Text | `Catalog-linked installs restore hub ship-system sub floor; uninstall damages the sub.` | `Catalog-linked installs connect the installed lot's preserved condition to the hub ship-system subcomponent; dismounting the last provider disconnects it without changing intrinsic health or item condition.` |
| Natural ID | `REQ-SMOD-001::acceptance-cc93b99b2016` | `REQ-SMOD-001::acceptance-24253a746be5` |
| Fingerprint | `ca2c7292b2639e65d66a3ccb3f6dfeda65a924a1b16c6f411f33b4b6454996cc` | `a4d1e10d64d29fbfe185be8cb8fac3cf95c98f2748a943f453739001caa1fea2` |

The replacement registry row keeps the original ID as its stable identity. Its
current `criterion` and `criterion_fingerprint` store the replacement text and hash;
an additive `criterion_supersession_review` record preserves both original fields,
the replacement natural ID/hash, source path and heading, this ADR, reviewer/date,
and the `one_for_one_active_leaf` disposition with denominator delta zero. Changed
semantic evidence resets to `not_verified`.

`build_feature_acceptance.py` owns a reviewed constant keyed by the stable original
ID. After ordinary source extraction and before duplicate-ID/equivalence accounting,
it must find the exact replacement natural ID and replace only that emitted ID with
the stable original ID. It also changes that source-coverage leaf to the stable ID.
The generated registry review record has this exact shape:

```json
{
  "stable_criterion_id": "REQ-SMOD-001::acceptance-cc93b99b2016",
  "source": {
    "path": "docs/game/05_requirements.md",
    "heading": "REQ-SMOD-001"
  },
  "original": {
    "criterion": "Catalog-linked installs restore hub ship-system sub floor; uninstall damages the sub.",
    "natural_id": "REQ-SMOD-001::acceptance-cc93b99b2016",
    "criterion_fingerprint": "ca2c7292b2639e65d66a3ccb3f6dfeda65a924a1b16c6f411f33b4b6454996cc"
  },
  "replacement": {
    "criterion": "Catalog-linked installs connect the installed lot's preserved condition to the hub ship-system subcomponent; dismounting the last provider disconnects it without changing intrinsic health or item condition.",
    "natural_id": "REQ-SMOD-001::acceptance-24253a746be5",
    "criterion_fingerprint": "a4d1e10d64d29fbfe185be8cb8fac3cf95c98f2748a943f453739001caa1fea2"
  },
  "review": {
    "status": "accepted",
    "adr": "docs/game/adr/0066-durable-machinery-condition-and-effective-system-health.md",
    "reviewer": "root_coordinator",
    "reviewed_on": "2026-09-05"
  },
  "accounting": {
    "metric_disposition": "one_for_one_active_leaf",
    "acceptance_kind": "requirement",
    "deferred": false,
    "counts_toward_proposed_denominator": true,
    "representative_id": "REQ-SMOD-001::acceptance-cc93b99b2016",
    "denominator_delta": 0
  }
}
```

The generator may use the original ID/fingerprint only as the normalized pair for
the frozen scope-contract computation, and only after the complete approved mapping
matches. The ordinary row fingerprint validator continues to recompute the current
replacement fingerprint. The original row is not deleted, deferred, or excluded;
the replacement is not an additional row. Source coverage points to the stable ID.
The frozen source fingerprint remains
`8041e481680152f85fe2d3617491880a5268d89dcb63a59608590711edef48d0`, and the active
metric denominator remains 622.

Generation fails before writing for a missing target, third wording, simultaneous
old/new leaves, duplicate or cyclic mapping, source/heading mismatch, any ID/hash
mismatch, or an active/deferred/kind/equivalence change. Registry validation checks
the review record, current fingerprint, stable coverage, one row, and zero denominator
delta. `tests/test_feature_acceptance_registry.py` adds focused cases for stable
identity/frozen accounting, evidence reset, unreviewed third wording, duplicate/cyclic
or tampered mappings, and pre-write byte preservation. The real-source accounting
test continues to assert denominator 622 and the existing frozen fingerprint.

The approved governance window includes the requirement, reviewed mapping data,
generator, registry, registry tests, tracked P14 plan scope, and generated P14 card
metadata. Runtime and validation-marker migrations remain pending P10/P13 stability.

### 7. Validation marker migration

Markers whose literal text claims the removed `.55` heal, `.6` damage, or `.15`
plating repair are retired. Their positive and away smokes, the validation plan,
requirement verification, and card references move together to condition-preserving
connection/resilience markers. Neutral component round-trip, station-tier, and run-
snapshot markers may remain only when their assertions still prove their literal
claims. A legacy PASS string may not hide the semantic change.

The P14 scene proof runs ten real timed install/dismount cycles of the same lot and
verifies exact identity, condition, provenance, intrinsic health, derived baseline,
and once-only receipts. It additionally proves damaged remount, healthy replacement,
paid intrinsic-plus-provider repair, multiple-provider connection, condition-gated
tier, unchanged full power draw, commit-time overbudget rollback, condition-weighted
plating, detached lot initialization/retry, and disk save/load without effect replay.

## Boundaries

- P10 owns outer save versions, recognized-legacy admission, strict malformed-present
  rejection, and detached save prepare/commit.
- P13 owns exact selected-ship context, attendance/access, binding generation, and
  manager-to-placement binding. P14 uses that context without singleton fallbacks.
- P19 owns persisted paid-work recovery. Its target revision includes mounted state
  and component condition; P14 adds no second condition to work transactions.
- P15/P17 structural repair/rebuild policies remain unchanged. P14 plating never
  repairs or resurrects structure.

Runtime implementation is limited to component placement/mount resolution, ship
systems effective queries and mutations, intrinsic model labeling, ship-mod/crafting
projections, repair-point routing, the coordinator call sites listed above, and the
focused P14/legacy semantic smokes. No component, power, system-repair, or structural
BOM catalog changes are authorized.

## Rejected alternatives

1. **Keep install/remove health deltas for compatibility.** This retains an unpriced
   repair loop, makes restore replay unsafe, and contradicts exact-lot condition.
2. **Make system intrinsic health the only condition.** This heals a returned damaged
   lot or makes a distinct healthy replacement ineffective.
3. **Let replacement repair intrinsic damage.** This bypasses the authored system
   repair BOM and makes repair gameplay unnecessary.
4. **Repair only intrinsic health.** With a damaged mounted provider, paid work can
   consume resources without changing effective functionality.
5. **Scale power draw by condition or add capacity values.** No current catalog or
   accepted balance authority defines those curves or values.
6. **Change criterion text and manually replace the frozen fingerprint.** This erases
   the prior reviewed claim and allows unreviewed scope drift under a stable count.

## Consequences and controls

- Healthy replacement repairs only removable component damage; system-side damage
  still requires paid repair.
- Multiple providers add connection redundancy while deterministic max aggregation
  and repair ordering avoid array-order behavior.
- The placement summary gains additive fields but no outer run/world version.
- The effective-health manager API becomes mandatory for production decisions; raw
  health remains available only as explicitly intrinsic state.
- The registry retains historical identity and hash provenance while current text
  remains independently integrity-checked. Accounting stays at the frozen 622
  denominator only for the exact approved one-for-one mapping.
- Runtime implementation remains blocked until P10 and P13 are stable.
