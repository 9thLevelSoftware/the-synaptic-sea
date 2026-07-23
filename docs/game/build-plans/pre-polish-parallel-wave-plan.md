# Pre-Polish Parallel Wave Plan

**Source e2e plan:** developer download `synaptic-sea-dev-plan.md` (2026-07-22).  
**Canonical decomposition:** this file (hand-off units for multi-agent execution).  
**Session plan mirror:** Grok session `plan.md` (same content family).

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
| PKG-A1c | Collapse away-branch dup | Pending |
| PKG-A3 | Tick bands FRAME/SLOW/LAZY | Pending |
| PKG-B2.1a–b | Module integrity | **Done** (#84–#86) |
| PKG-B2.2a–b | WorkActions | **Partial** (pure a/b #89–#90; scene driver open) |
| PKG-B2.3a–b | Component slots | **Done** (a #91, b #94) |
| PKG-B2.4a–b | Crafting depth | **Done** (a #92, b #95) |
| PKG-B2.5 | Repair unification | **Done** (#93) |
| PKG-B5.1 | Dressing consumption | **Done** (earlier) |
| PKG-C3.1a–b | Wounds / vitals v2 | **Partial** (a pure #96; b open) |
| PKG-C3.2 | Food closure | Pending |
| PKG-C3.3 | Sanity schema hooks | Pending |
| PKG-C4.1a–b | Perception | **Partial** (a pure #97; b raycast open) |
| PKG-C4.2 | Archetype modifiers | Pending |
| PKG-C5.3 | Encounter pacing | **Done** (earlier) |
| PKG-D2.6 | Ship modification | Pending |
| PKG-D5.4 | Templates + wreck mutator | Pending |
| PKG-D6.1–3 | Persistence verify / sea graph / hub verify | **Done** (D6.2 #102; D6.3 #111; D6.1 pillar revisit) |
| PKG-D7–D10 | Progress / save fuzz / UI / audio | **Done** (D7–D10 #105–#110; D9b ship-mod panel) |
| PKG-INT | Integration closeout | Pending |

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

Related pure smokes still green after SimKeys consumer migration: vitals, threat AI, life support, fire suppression, hallucination director, sustenance.

## Next

1. PKG-A1a — extract `ShipRuntime` shell (serial coordinator owner).  
2. Parallel early wins once A1a gate optional: B5.1 dressing, C5.3 encounter pacing, C3.3 sanity schema.  
3. Hold module destruction coding until A0 (done) + A1b snapshot extension points.
