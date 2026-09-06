# Feature program: Crafting and derelict restoration completion

Status: **Source accounting frozen 2026-09-05; ADR-0059 accepted; runtime implementation underway; full acceptance pending.**
The detailed contracts below are the reviewable implementation proposal.
Baseline: `main` at `f4a65669`. No implementation completion is asserted here.
Plan: [implementation program](../../superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md).
Architecture: [ADR-0059](../adr/0059-crafting-and-derelict-restoration-transactions.md), accepted for implementation.

## Purpose and scope

Close the identified gaps between implemented models, player-reachable behavior,
and the intended salvage -> craft -> repair -> rebuild -> own -> fly loop.
Preserve existing gameplay while making quality, machinery, structural restoration,
and persistent ship ownership meaningful.

This program has three explicit completion claims:

1. **Crafting feature complete:** requirements FC-04 through FC-12 pass model,
   production-path, persistence, and player acceptance checks.
2. **Derelict restoration feature complete:** FC-13 through FC-22 pass those checks.
3. **Designed systems feature complete:** all active requirements across every
   domain pass the comprehensive inventory/acceptance gate FC-23. Completing the
   first two does not imply the third or release readiness.

New work is restoration within the existing module/slot architecture. Restoring
destroyed modules is included. Arbitrary room creation, moving structural walls to
new coordinates, voxel construction, and a freeform exterior editor are not
introduced by this program. Any such capability already required by an active
design must remain an explicit open row in the whole-game acceptance register;
it cannot disappear into a parent percentage or a newly invented exclusion.

## Existing contracts to preserve

- `crafting_materials_recipes.md`: REQ-CS-001..015, station/field crafting and economy.
- `crafting_recipe_picker.md`: player-selected recipes and denial explanations.
- `work_actions.md`: catalog-driven physical work, interruption, noise, XP, persistence.
- `module_integrity.md`: REQ-MI-001..004, real collision/nav/atmosphere consequences.
- `component_slots.md`: REQ-CMP-001..003, physical machinery and salvage/remount.
- `ship_modification.md`: REQ-SMOD-001..003, powered machinery and persistent hull work.
- `../../superpowers/specs/2026-06-21-ship-repair-loop-design.md`: parts-gated
  repair, dependency recovery, and safe return in the player's ride.
- ADR-0051: structural modules, not voxels; generation plus persistent deltas.
- Existing native generator/document contracts and authored wrapper authority.

## Observed baseline and evidence limits

The recorded crafting model entries score 100%; repair-point and crafting-station
entries score 90%. These are inventory annotations, not fresh design acceptance.
The consistency check passed 191 records; the coverage check omitted 53 scripts,
including recipe knowledge, component mounting, module integrity, WorkActions,
and ship modification. Some omitted files may be tooling: classify individually.

The preceding investigation ran Godot 4.7.2 mono, whereas the current validation
contract requests 4.7.1. Four focused smokes had clean output. Six scene smokes
printed PASS alongside errors/warnings for imported doorway damage visuals and
other diagnostics. A 120-second import attempt timed out. These are not accepted
clean baseline results. Import-generated changes were removed from the checkout;
an implementation must establish its own clean, isolated baseline.

Confirmed code/probe findings:

- Live `begin_craft` passes null to optional recipe knowledge validation.
- Craft completion adds item ID/quantity; calculated quality is only logged.
- Queue advancement starts another recipe without paying its ingredient cost.
  A temporary probe produced two plating items from one recipe's ingredients;
  no production `enqueue_craft` callers were found.
- The ship-mod panel accepted `purified_water` as an installed component.
- Destroyed modules reject ordinary repair and are skipped by work targeting.
- Ship-mod installs are immediate; plating repairs the first damaged/breached
  module by 0.15 rather than a selected physical repair target.
- Output can be lost when a stack fills during a craft.

Risks needing tests rather than assumed verdicts: repeated plating install/remove
repair gains, current-ship versus home-ship targeting, source quality loss on
transfer/salvage, deconstruction output races, and completion duplication across
save/load or repeated callbacks.

## Proposed gameplay rules

### Crafting economy

- Every recipe uses one eligibility result for list display and execution:
  knowledge, skill, station identity/tier, power policy, ingredients, job capacity.
- `starter`, `book`, `reverse_engineer`, and `codex` remain recognized knowledge
  sources. Learning is current-run player state, survives saves, and is awarded
  once by the corresponding real event. Repeated load/events do not duplicate it.
- Jobs belong to a **ship ID and station instance ID**, not just station kind.
  Two workbenches can progress independently; each individual station is serial.
  Queues retain the current default limit of eight queued jobs per station.
- Enqueue reserves exact ingredient lots. Reserved lots are removed from available
  inventory but remain owned escrow; their mass still counts at their physical
  holder. Reservation fails atomically if any required ingredient is unavailable.
- Cancelling an unstarted job returns its exact lots. A started job consumes its
  reserved ingredients once; cancelling it forfeits them with a clear UI warning.
  Power loss pauses progress and never consumes ingredients again.
- Completion creates one durable output record per job. Collection can be partial;
  uncollected output stays at that station and is saved. No output is discarded
  merely because the player's per-item stack is full. A destroyed station exposes
  its escrow/output through a salvageable persistent container.
- Attended field work pauses when the player cannot work. Powered autonomous
  stations use the existing bounded ShipRuntime catch-up rules, including power
  state changes; elapsed wall-clock time alone cannot finish an unpowered job.
- Queue reservation is not automated transport: materials must already be in the
  player's inventory or the explicitly selected local station input holder.

### Quality, condition, and transfers

- Preserve exact material/item lots with stable lot IDs and metadata; retain
  existing `item_id -> quantity` accessors as aggregate compatibility APIs.
- Quality and condition are separate. Quality expresses manufactured capability;
  condition expresses current damage/wear. Repair does not reroll quality.
- Metadata fields: `lot_id`, `item_id`, `quantity`, `quality_score` in [0,1],
  `quality_tier`, `condition` in [0,1], and `origin` (source ship/job when known).
  Identical metadata may merge; unlike metadata must not silently merge.
- Existing per-item stack ceilings and soft player encumbrance remain unchanged.
  Quality lots must not multiply the aggregate stack cap. Cargo keeps its own
  hard-cap policy. Compatibility removal chooses standard-quality lots first,
  then stable lot-ID order; the new picker permits explicit lot selection.
- Old saves become standard-quality/full-condition lots unless an existing
  material-quality summary provides a better value. Never invent provenance.
- Every item category declares a quality consumer or an explicit quantity-only
  policy. Initial consumers: tool work speed, component output/power efficiency,
  repair material restored integrity, and consumable potency. Existing balance
  curves are the starting point; fixed-seed tests assert their chosen values.
- Splitting, cargo/cart transfer, drops, corpse loot, equipment, salvage, and saves
  preserve lot identity/metadata without minting quantity or rerolling quality.

### Atomic persistence closure

- FC-12 and REQ-012 apply to every production entry path: manual, quick, auto,
  and title-initiated load. A successful load publishes one fully validated
  replacement world; a rejected load leaves the current playable instance,
  owner graph, lots, escrow, receipts, audio buses/playback, current camera,
  source bytes, slot index, and migration sidecars unchanged.
- Current present audio, settings, ship-system, oxygen, combat, crafting,
  knowledge, component, and access payloads are strict. Old schemas migrate only
  through their declared version boundary, and a migrated sidecar is published
  only after the detached candidate commits successfully.
- Current v6 captures require exact String `combat_hotbar_text`. Recognized
  pre-v6 absence becomes the explicit empty runtime default before sealing;
  present historical text remains byte-for-byte.
- Exact numeric authority survives serialization and two restores, including
  lot quality and electrical-arc phase timers. The sole staged recapture
  exception is `home_ship.oxygen_summary.player_in_breach_zone`, which is a
  boolean projection derived from the activated scene overlap or active field
  atmosphere. No other oxygen, timer, combat, or subsystem field is normalized
  or omitted from comparison.
- Restored owners bind before tick, collection, station interaction, or inactive
  catch-up is enabled. Same-ship and cross-ship component moves preserve their
  immutable source lots, and stale coordinator or selected-ship pointers fail
  closed rather than mutating another owner.

### Repair and installation

- Repair/system patch, component install/remove, and structural replacement use
  WorkActions. UI emits a request; UI never mutates installation state directly.
- Resolve the target from explicit ship ID plus stable component/module/slot ID.
  The selected ship can differ from the original hub; no implicit global-home edit.
- Work reserves materials on start and commits them only when the scene change
  can succeed. Interruption retains progress/escrow while paused; explicit cancel
  returns escrow. These physical-work semantics intentionally differ from an
  already-started fabrication recipe.
- Revalidate range, target revision, occupancy, tools, skill, access, slot fit,
  power, and safety at commit. Unchanged retry of a committed work ID is a no-op.
- Ordinary repairs on derelict machinery remain permitted by existing salvage
  rules. Permanent fleet upgrades require ownership/access; no unauthorized edits
  to another owned ship. Denials explain the exact blocker.
- Only catalogued machinery compatible with the real physical slot can install.
  No arbitrary-item fallback, synthetic hub-slot fallback, or default generic
  machinery mass/power for an unknown item.
- Removing an upgrade reverses that upgrade's effect once. Installing/removing
  plating cannot act as a free repeatable repair; patch materials are consumed
  by explicit hull work, while durable armor upgrades affect future resilience.

### Structural replacement and ship use

- `repair()` continues to reject destroyed modules. A separate `replace_module`
  WorkAction restores a compatible structural wrapper in the same footprint.
- Keep a tombstone descriptor after destruction: stable module ID, source layout
  revision, wrapper/catalog ID, transform, footprint, sockets, room/edge bindings,
  and relevant system links. A selectable damage marker remains at the location.
- Validate replacement type/footprint/sockets, actor/cargo overlap, docking portal
  occupancy, and required egress. Do not build through a player, cart, component,
  or active docking connection. A blocked completion spends no materials.
  ADR-0065 sections 3A/3B define the P17 foundation: canonical authored physical
  profiles and exact isolated candidate shape queries. These preparatory checks
  do not satisfy FC-19 until real scene bindings, existing-world clearance and
  registered exit/connection routes are verified. Interaction radii and imported
  visual bounds never authorize structural placement.
  A bounded pure navigation helper may evaluate explicit edge, base-clearance,
  portal, endpoint, and local connection-side projections, but its inputs are not
  owner-authenticated and its result is never scene authorization. Closed portals
  remain blocked; an exterior structural boundary is not a registered exit; and
  each connected ship's local side must be evaluated against that ship's graph.
  Exterior-edge replacement and floor/ceiling support topology remain outside
  that preparatory helper and must stay visibly unsupported until integrated.
- A successful replacement restores geometry, collision, navigable edge state,
  atmosphere enclosure, component-slot availability, and structural health as one
  committed operation. Intact restoration must close the hole it replaces.
- Displaced or incompatible mounted components become explicit recoverable lots;
  they cannot vanish or become duplicated by geometry regeneration.
- Store replacement descriptors separately from damage deltas: a fully repaired
  replacement must persist even when ordinary pristine integrity deltas disappear.
- Preserve claim/access and pilot-switch semantics. Show a readiness checklist
  based on live propulsion/dependencies, navigation, power, hull/atmosphere policy,
  and docking constraints. Ownership is not proof of flight readiness.
- Travel reads the selected piloted ship's actual state. Preserve the documented
  safe-return rule; do not fabricate operational status to make a test pass.

## Acceptance register

IDs below are new proposed program requirements, cross-referenced to existing
requirements rather than silently replacing their text. Execution task P01
registers them in `05_requirements.md` and resolves conflicts before code changes.

| ID | Required observable outcome | Acceptance evidence |
|---|---|---|
| FC-01 | Every runtime file and active design requirement is classified; missing features remain visible | Inventory coverage + requirement-to-feature report |
| FC-02 | Supported engine and native extension boot with complete runtime imports and accepted diagnostics only | Fresh isolated baseline log |
| FC-03 | Acceptance runner rejects false PASS, nonzero exit, timeout, errors, and missing markers | Runner negative tests |
| FC-04 | Knowledge, skill, tier and ingredients gate both picker and execution identically | Locked recipe cannot craft through either path |
| FC-05 | Quantity and quality survive all relevant holders and transfers | Lot conservation and transfer smokes |
| FC-06 | Quality changes the declared live item effect and is visible to the player | Two-quality comparison through real consumer |
| FC-07 | Every queued job pays once and has independent identity and station ownership | One paid recipe cannot yield two jobs |
| FC-08 | Power/cancel/retry preserve correct escrow, progress and quantities | Interrupted/resumed job matrix |
| FC-09 | Finished outputs and salvage yields remain recoverable when destinations fill | Full-stack completion + revisit + collect |
| FC-10 | Recipes and repair BOMs form reachable, non-profitable conversion chains | Catalog graph + acquisition route evidence |
| FC-11 | Crafting/field/salvage UI exposes choice, costs, quality, queue and blocked reasons | Mouse/keyboard and controller scenario |
| FC-12 | Jobs, knowledge, output and quality survive old/new save paths | Migration + save at each transaction boundary |
| FC-13 | Only compatible catalogued parts install into physical slots | Water/unknown/wrong-size/wrong-ship denied |
| FC-14 | Physical repair/install is timed, interruptible and exactly-once | No effect before commit; retry no duplicate |
| FC-15 | Selected derelict edits never modify the home ship accidentally | Two-ship state comparison |
| FC-16 | Power/tier/system effects match installed condition and reverse once | Install/remove and damaged-upgrade comparison |
| FC-17 | Patch targets a chosen damaged module and costs materials | Unrelated module unchanged; no plating cycle gain |
| FC-18 | Destroyed structures remain inspectable and replaceable | Actual destroyed wall selected in-engine |
| FC-19 | Replacement enforces footprint/sockets/occupancy/egress | Unsafe placements denied without resource loss |
| FC-20 | Replacement restores visible, collision, nav and atmosphere behavior | Player/threat route and oxygen probes |
| FC-21 | Claimed repaired ship becomes a usable ride under real readiness rules | Repair -> claim -> pilot -> undock -> travel |
| FC-22 | Repairs/replacements/machinery survive revisit, docking and save/load | Two ships, moved transforms, migrated saves |
| FC-23 | Every active designed system passes its own player acceptance criteria | Whole-game domain closure review |
| FC-24 | Core loop works in an offline native export without dev tools | Clean-machine exported-build playthrough |

R04 records the existing FC-10 obligations without changing this frozen
criterion: validate recipe/deconstruction/BOM/knowledge/tier/component edges;
reject missing IDs, mandatory prerequisite cycles, and sinkless profitable
cycles; and capture Title-authored starter, donor, and advanced routes through
normal controls, inventory Use, paid work, collection, and an output consumer.

## Final player scenarios

Run both seeds 42 and 777 in `breach_field`/`standard`, with home and away branches:

1. Start normally; obtain ingredients and tools through actual loot/salvage.
2. Encounter a locked recipe; acquire its book/knowledge event; craft it normally.
3. Compare two qualities in inventory and perform their declared different effect.
4. Queue two paid jobs, interrupt power, restore it, collect after an output stack
   fills, leave and return. Quantities and progress remain correct.
5. Diagnose a derelict; remove usable machinery; carry it via inventory/cart/cargo;
   install it into a compatible claimed-ship slot through timed work.
6. Patch a selected breach; replace a destroyed structural module; observe oxygen,
   passability and threat navigation change. Attempt an unsafe replacement first.
7. Repair dependencies, claim/switch pilot, dock/undock and travel in that ship.
8. Save during queued crafting and interrupted repair, reload, finish, revisit both
   ships, and verify no lost/duplicated resources or cross-ship state contamination.

No console spawning, `force_repair`, validation teleport, or test-only completion
method is permitted in the final player acceptance run. Automated fixtures may
use controlled setup, but must label that evidence separately.

## Completion accounting (P01)

The program register is [feature_acceptance.json](../inventory/feature_acceptance.json).
It records scope, owner card, source/provenance, and evidence independently. A
recorded inventory confidence or a historical `Validated` requirement status is
not fresh FC evidence. At scope freeze, all FC evidence states are
`not_verified`; implementation and acceptance counts are therefore zero for this
program. Existing deferred and expected-unbuilt design scope remains in the
whole-game register and is assigned to FC-23/P23 rather than excluded.
