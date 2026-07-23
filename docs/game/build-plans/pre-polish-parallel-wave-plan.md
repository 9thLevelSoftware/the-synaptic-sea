# Pre-Polish Parallel Wave Plan

**Source e2e plan:** developer download `synaptic-sea-dev-plan.md` (2026-07-22).  
**Canonical decomposition:** this file (hand-off units for multi-agent execution).  
**Status date:** 2026-07-23 (PKG-INT docs closeout after PRs #78–#113).

## Definition of pre-polish

Every system mechanically complete, closed-loop, and content-capable — remaining work is authoring (narrative, art, audio, balance), not engineering.

## Hard rule: ADR-0051

Module integrity is the unit of destruction. **No voxels.** See `docs/game/adr/0051-module-integrity-not-voxels.md`.

## Waves (summary)

| Wave | Goal | Max agents | Choke point |
| --- | --- | --- | --- |
| W0 | ADR + specs + SimKeys + TuningCatalog | 3 | none |
| W1 | ShipRuntime strangler + tick bands | 1 on coordinator + pure prep | `playable_generated_ship.gd` |
| W2 | ModuleIntegrity pure + dressing + wounds + perception + encounter pacing | 4–5 | loader ownership |
| W3 | WorkActions + craft quality + food closure | 3–4 | WorkAction catalog |
| W4 | Components + repair unify + archetypes + station tiers | 4 | interactables |
| W5 | Ship mod + sea graph + templates + UI/progress/audio consumers | 4–5 | snapshot schema |
| W6 | Integrator: regression + inventory + STATUS | 1 | full bundle |

## Package IDs

| ID | Title | Status |
| --- | --- | --- |
| PKG-A0 | ADR-0051 | **Done** (PR #78) |
| PKG-SPEC-PILLAR | Feature specs MI/WA/CMP/SMOD | **Done** (PR #78) |
| PKG-A2 | SimKeys pure consumers | **Done** (PR #78) |
| PKG-A4 | TuningCatalog shell | **Done** (PR #78) |
| PKG-A1a | ShipRuntime advance/catch-up | **Done** (PR #79) |
| PKG-A1b | ShipRuntime snapshots + multi-runtime | **Done** (PR #80) |
| PKG-A1c | Collapse away-branch dup | **Done** (shared `_tick_*` helpers on both branches) |
| PKG-A3 | Tick bands FRAME/SLOW/LAZY | **Done** (`ShipRuntime.poll_bands` + hub SLOW recompute) |
| PKG-B2.1a–b | Module integrity | **Done** (#84–#86) |
| PKG-B2.2a–b | WorkActions | **Done** (pure + driver #89–#90/#108; dual-branch tick #113) |
| PKG-B2.3a–b | Component slots | **Done** (a #91, b #94) |
| PKG-B2.4a–b | Crafting depth | **Done** (a #92, b #95) |
| PKG-B2.5 | Repair unification | **Done** (#93) |
| PKG-B5.1 | Dressing consumption | **Done** (earlier) |
| PKG-C3.1a–b | Wounds / vitals v2 | **Done** (a #96, b #99) |
| PKG-C3.2 | Food closure | **Done** (#104) |
| PKG-C3.3 | Sanity schema hooks | **Done** (#101) |
| PKG-C4.1a–b | Perception | **Done** (a #97, b #108 LOS) |
| PKG-C4.2 | Archetype modifiers | **Done** (#100) |
| PKG-C5.3 | Encounter pacing | **Done** (earlier) |
| PKG-D2.6 | Ship modification | **Done** (#111 pure + #113 panel) |
| PKG-D5.4 | Templates + wreck mutator | **Done** (#103) |
| PKG-D6.1–3 | Persistence verify / sea graph / hub verify | **Done** (D6.2 #102; D6.3 #111; D6.1 #112) |
| PKG-D7–D10 | Progress / save fuzz / UI / audio | **Done** (#105–#110, D9b #113) |
| PKG-INT | Integration closeout | **Done** (status/plan currency; inventory `--check` green; bundle markers=255) |

## Merge protocol

1. One package = one branch/worktree when possible.  
2. Respect Allowed files from the session plan.  
3. Never dual-edit `playable_generated_ship.gd`.  
4. Validation plan / inventory updates go through Integrator or single owner.  
5. Fresh PASS markers required; unexpected `ERROR:`/`WARNING:` blocks.

## Feature specs

- `docs/game/features/module_integrity.md`
- `docs/game/features/work_actions.md`
- `docs/game/features/component_slots.md`
- `docs/game/features/ship_modification.md`

## Wave 0 verification (landed)

```
SIM KEYS PASS hot=9 total=52 vitals_wired=true
TUNING CATALOG PASS shell=true dir_loaded=1 override=true
```

## Exit of Phase D / pre-polish mechanical bar

All package rows above are **Done**. Remaining work is content, polish, and optional UX (e.g. nearest-module hold-to-work targeting) — not missing schema or pure models.

Regression marker contract: `SYNAPTIC_SEA REGRESSION PASS commands=255 clean_output=true` in `docs/game/06_validation_plan.md`.

Inventory: `python tools/build_system_inventory.py --check` → `SYSTEM INVENTORY CHECK PASS systems=191 verified=191`.
