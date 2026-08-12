# Feature: Vertical Slice v1 (Production Milestone A)

## Status

**Active** — productization contract for the current production path.
Pre-polish mechanical bar is complete; this slice is the active finish line before content breadth or itch demo packaging.

## Design pillar alignment

- Pillar: deep survival tension in a biomatter-web derelict sea
- Why: systems already close loops; players still cannot *feel* the fantasy because presentation, onboarding, and stakes UX are thin. This slice forces shippable face-and-feel before more systems.

## Player fantasy

You are stranded on a damaged hub ship in the Synaptic Sea. You scavenge and repair under oxygen, fire, and hull pressure, then board a hostile derelict for parts — and something in the web notices. A cold player should finish 20–40 minutes able to say: “I repair a hub, raid one derelict, and try not to die.”

## Gameplay problem

The simulation is systems-complete (18 closed loops) but product-incomplete: placeholder threats/props, ~2 audio clips, thin tutorials, and silent death. Agents and contributors keep expanding systems instead of shipping a readable run. This document locks the Milestone A cut so work cannot wander.

## Core behavior (Milestone A)

In-engine, a new run must support:

1. Title → New Game → hub (coherent home ship)
2. Move, interact, inventory, basic HUD
3. Oxygen / fire / breach pressure with audible and readable cues
4. Loot + at least one craft/repair loop on hub or derelict
5. Travel to one away derelict (`breach_field` / `standard`)
6. Encounter up to three slice threats with distinct visuals
7. Death or extraction ends in a results screen (Phase 2 delivery; required for A exit)
8. Regression bundle remains green

## Slice bounds (locked)

| Dimension | Value |
|---|---|
| Hub | `scenes/procgen/playable_coherent_ship.tscn` + golden `data/procgen/golden/coherent_ship_001/` |
| Away biome | `breach_field` |
| Difficulty | `standard` |
| Playtest seeds | `42`, `777` |
| Threats in slice | `biomatter_swarm`, `stalker`, `hull_tendril` only |
| Session length (A) | 20–40 minutes cold-player |
| Milestone B length | 60–90 minutes, hard cap 90 (see `demo_scope_v1.md`) |
| Class start (A) | Fixed default start; no title class picker required |
| Permadeath | Existing ironman/permadeath model; Phase 2 results screen explains death clearly |

## Interactables that must not be boxes

These must use non-box prop presentation on the live path (catalog + factory; silhouette-grade GLB minimum):

- loot container
- fire point
- breach seal
- hatch
- crafting station
- corpse loot
- tool pickup

## Audio minimum IDs

Pipeline exists (ADR-0044). Milestone A requires **real clips** for:

- `footstep`
- `ui_open` / `ui_close`
- `tool_pickup`
- `fire_loop`
- `breach_alarm`
- `combat_hit`
- `threat_alert`
- `door`
- `dock`
- `death_sting`
- `music_explore` / `music_tension` / `music_critical`

## 20-minute script (cold player beats)

- Title → New Game with the fixed default start; no class picker is required for Milestone A.
- Move and complete the first tutorial prompt.
- Interact with the hub station or loot container; identify the tool pickup and crafting station.
- Feel oxygen/suit or breach pressure through tutorial, HUD, and audio feedback.
- See and handle the fire point or extinguisher path, then understand the breach-seal interaction.
- Open inventory and understand the result of taking loot.
- Open scanner/travel, dock, and board the first derelict using playtest seed `42` or `777`.
- Search a loot container and hear the tool-pickup/loot feedback.
- Spot a distinct threat silhouette and receive an alert; encounter only `biomatter_swarm`, `stalker`, or `hull_tendril`.
- Survive or die with feedback, then return or reach a comprehensible results/title path; corpse loot is available after a defeated threat.

## In-scope assets

- Structural kit on **live** hub + away path (`ship_structural_v0` wrappers / imported GLBs) when shippable
- Threat visual catalog for 3 slice archetypes
- Gameplay prop catalog for listed interactables
- Slice audio pack + icon replacements for slice-critical UI
- Tutorials + run results (Phase 2 of production plan)
- First-run derelict beat contract

Art must pass [`docs/game/art_shippable_gate.md`](../art_shippable_gate.md) before runtime promotion. Hand-authored Blender/kitbash is preferred; AI-assisted textures are allowed only when they pass that gate.
`assets/tiles/synaptic_sea/` and LoRA outputs are pipeline evidence only until gated.

## Out-of-scope / cuts

- No new simulation domains or loop rewrites
- No Steam or cloud saves (ADR-0032 stub stays)
- Full tile atlas replacement from PoC pipeline
- Do not treat `assets/tiles/synaptic_sea/` PoC assets as runtime art
- All six threat archetypes fully produced (only three in A)
- Title class picker (deferred to Phase 3 content depth)
- Alien factions, huge class trees, multiplayer
- No coordinator dual-writers; do not dual-edit `scripts/procgen/playable_generated_ship.gd` across agents
- Infinite dual-branch SFX smokes without new audible assets
- Treating Gate 0–5 archive docs as status truth

## Decisions (locked 2026-08-11)

1. **Biome:** `breach_field` (public face for A/B)
2. **Difficulty:** `standard`
3. **Seeds:** `42`, `777` for playtests and first-run contract
4. **Demo length (B):** 60–90 min, hard cap 90 — not A’s exit
5. **Permadeath:** keep existing ironman model; results screen must explain death
6. **Art source:** shippable gate required; hand-authored Blender/kitbash preferred; AI-assisted only if gate passes
7. **Class select (A):** fixed default start; 2–3 distinct starts in Phase 3
8. **Platforms (B):** Windows x86_64 + macOS required; Linux optional
9. **Threats (A):** `biomatter_swarm`, `stalker`, `hull_tendril`
10. **Hub:** `scenes/procgen/playable_coherent_ship.tscn` + `data/procgen/golden/coherent_ship_001/`
11. **Explicit cuts:** no new simulation domains; no Steam/cloud; no `assets/tiles/synaptic_sea/` PoC assets as runtime art; no coordinator dual-writers
12. **Coordinator:** single-writer rule; prefer strangler extractions before stacking hooks

No ADR-0052 is required: no contested architecture or workflow conflict was found, so the optional ADR from the production plan is intentionally skipped.

## Acceptance checklist for Milestone A

- [ ] Cold player completes 20–40 min and correctly states the fantasy
- [ ] Hub + away spaces readable (not critical-path debug boxes)
- [ ] Three slice threats visually distinct on live path
- [ ] Listed interactables non-box on live path
- [ ] Audio minimum IDs present and covered by content smoke
- [ ] Tutorials cover move/loot/O2/fire/threat/travel/death meaning
- [ ] Death/extraction shows results UX (not silent instant end)
- [ ] First-run derelict beat guarantees fire-or-breach + loot + ≥1 encounter
- [ ] 5 blind/external playtests: no open P0 softlock/crash; median want-to-continue ≥ 3
- [ ] `docs/game/06_validation_plan.md` regression still ends `SYNAPTIC_SEA REGRESSION PASS`
- [ ] `python3 tools/build_system_inventory.py --check` passes if inventory citations moved
- [ ] No new unclassified Godot `ERROR:` / `WARNING:` in focused smokes

## Validation commands

```bash
# Inventory anti-drift (host)
python3 tools/build_system_inventory.py --check

# Full regression — run the documented bundle in:
# docs/game/06_validation_plan.md
# Expected tail marker pattern:
# SYNAPTIC_SEA REGRESSION PASS commands=<N> clean_output=true

# Godot binary (this machine)
# /Users/christopherwilloughby/.local/bin/godot-4.6.2
```

The authoritative regression bundle is defined in [`docs/game/06_validation_plan.md`](../06_validation_plan.md). Focused smokes land with later plan tasks (threat visual, props, audio content, tutorials, run results).

## Playtest

Protocol (planned): [`docs/game/playtests/vertical_slice_protocol.md`](../playtests/vertical_slice_protocol.md)  
Template: `docs/game/playtests/playtest_template.md`  
Results land under `docs/game/playtests/vertical_slice_results_YYYY-MM-DD.md`.

## Technical design (pointer)

Execution plan (phases/tasks):  
[`.hermes/plans/2026-08-11_215934-production-grade-e2e.md`](../../../.hermes/plans/2026-08-11_215934-production-grade-e2e.md)

Related:

- `docs/game/art_shippable_gate.md` — runtime art promotion gate
- `docs/game/features/demo_scope_v1.md` — Milestone B demo bounds
- `STATUS.md` — active milestone pointer
- Inventory truth: `docs/game/inventory/SYSTEM_INVENTORY.md`

## Risks

| Risk | Mitigation |
|---|---|
| Scope creep into new systems | This contract + reject PRs without player-visible slice delta |
| PoC tiles shipped as art | Shippable art gate |
| Coordinator choke | Single-writer + Phase 4 strangler |
| False confidence from smokes | Human playtest exit required |

## ADRs

- ADR-0044 audio bus/pipeline (content pack still owed)
- ADR-0051 module integrity (no voxels)
- ADR-0032 cloud stub (out of scope for A/B)
- ADR-0029 release/demo architecture (demo manifest)
