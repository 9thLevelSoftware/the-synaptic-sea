# The Synaptic Sea — Production-Grade E2E Plan

> **For Hermes:** Use `subagent-driven-development` (or kanban `synaptic-sea-stage-gate`) to implement phase-by-phase. Do **not** treat this as “add more systems.” Systems are largely closed; this plan is productization.

**Goal:** Move The Synaptic Sea from systems-complete pre-alpha to a production-grade public game path: Vertical Slice → itch Demo → Early Access–shaped release.

**Architecture:** Keep the existing closed-loop simulation (`docs/game/inventory/system_inventory.json`, 18 loops closed). Productize through (1) a bounded playable presentation slice, (2) authored content/balance, (3) onboarding + fail/win UX, (4) coordinator strangler so content work stays cheap, (5) human playtest gates, (6) demo-scoped export/store packaging. Art must be **shippable in-engine assets**, not pipeline demos/PoC tiles.

**Tech Stack:** Godot 4.6.2 (`godot-4.6.2`), GDScript, existing pure models + `PlayableGeneratedShip` coordinator, kit wrappers under `scenes/wrappers/structural/`, audio via `scripts/audio/` + `data/audio/`, validation via `scripts/validation/` + `docs/game/06_validation_plan.md`, inventory via `tools/build_system_inventory.py`.

**Canonical truth docs (do not revive Gate folklore):**
- `STATUS.md`
- `docs/game/inventory/SYSTEM_INVENTORY.md` + `system_inventory.json`
- `docs/game/integration_debt.md`
- `docs/game/06_validation_plan.md`
- ADRs under `docs/game/adr/`

**Non-goals until Demo ships:**
- Cloud saves / Steamworks (ADR-0032 stub stays)
- Full alien faction tree / huge class catalog
- Voxel destruction (ADR-0051)
- Infinite smoke expansion without player-facing value
- Treating ComfyUI/LoRA/tile pipeline outputs as final art unless they pass a shippable art gate

---

## Production definition (exit criteria)

### Milestone A — Vertical Slice (internal ship)
A cold player can play **20–40 minutes** and correctly describe the fantasy (“repair/survive on a hub, raid derelicts in a biomatter web”).

Must have:
- Readable ship spaces (not debug boxes for critical geometry/props/threats)
- Real audio bed for the slice (not 2 placeholder clips)
- Onboarding covering move/loot/O2/fire/threat/travel/death
- Death/results UX (not silent instant end)
- 5 external or blind playtests with no critical softlock
- Regression bundle still green

### Milestone B — Public Demo (itch.io)
Milestone A + **60–90 minutes** of variety + store page + stamped desktop builds + demo scope gate enforcing bounds.

### Milestone C — Production-grade Early Access shape
Multiple biomes/templates, deeper enemy/loot/start variety, performance targets on dressed content, polished UX, live ops basics, coordinator under maintainability budget.

**Current state (2026-08-11 audit):** past systems alpha; not yet A.

---

## Phase map

| Phase | Name | Outcome | Depends |
|---|---|---|---|
| 0 | Freeze truth + slice contract | Written DoD, cut list, art gate | — |
| 1 | Presentation vertical slice | Ship/rooms/threats/props/audio look/sound like a game | 0 |
| 2 | Onboarding + stakes UX | Player can learn and feel failure/progress | 0 |
| 3 | Content depth for one hour | Enough variety to not feel hollow | 1, 2 |
| 4 | Coordinator strangler | `playable_generated_ship.gd` no longer blocks all work | parallel after 0; hard before broad Phase 3 fan-out |
| 5 | Human playtest + balance | Fun/fair/comprehensible under real hands | 1–3 |
| 6 | Demo packaging + itch | Public downloadable demo | 5 |
| 7 | EA production hardening | Breadth, perf, polish, ops | 6 |

**Parallelism rule:** Never dual-edit `scripts/procgen/playable_generated_ship.gd`. One owner/PR at a time for that file. Prefer extracting modules (Phase 4) before stacking presentation hooks into it.

---

## Phase 0 — Freeze truth + Vertical Slice contract

### Task 0.1: Write Vertical Slice feature spec

**Objective:** Lock what “slice complete” means so agents cannot wander into new systems.

**Files:**
- Create: `docs/game/features/vertical_slice_v1.md`
- Modify: `STATUS.md` (add “Active milestone: Vertical Slice v1” section at top)
- Create: `docs/game/adr/0052-vertical-slice-before-breadth.md` (optional if contested; otherwise feature spec only)

**Slice bounds (author into the spec exactly):**
- **Hub:** current coherent home ship path (`scenes/procgen/playable_coherent_ship.tscn` / golden `data/procgen/golden/coherent_ship_001/`)
- **Away:** 1 biome (`breach_field` **or** `dead_fleet` — pick one in spec), 1 difficulty (`standard`), 2 seeds fixed for playtests
- **Threats in slice:** 3 of 6 archetypes max (recommend `biomatter_swarm`, `stalker`, `hull_tendril`)
- **Interactables that must not be boxes:** loot container, fire point, breach seal, hatch, crafting station, corpse loot, tool pickup
- **Audio minimum IDs** (map to existing SFX router catalog where possible): footstep, UI open/close, tool pickup, fire loop, breach alarm, combat hit, threat alert, door, dock, death sting, music explore/tension/critical
- **Explicit cuts:** no new simulation domains; no Steam; no full tile atlas replacement unless shippable

**Step 1:** Draft `vertical_slice_v1.md` with sections: Player fantasy, 20-minute script, In-scope assets, Out-of-scope, Acceptance checklist, Validation commands, Playtest rubric link.

**Step 2:** Add STATUS blurb pointing to the spec as active milestone; mark pre-polish mechanical bar as complete and productization as current.

**Step 3:** Commit

```bash
git add docs/game/features/vertical_slice_v1.md STATUS.md
git commit -m "docs: lock Vertical Slice v1 production milestone contract"
```

---

### Task 0.2: Shippable art gate (kill PoC-as-content)

**Objective:** Define when an asset may enter the live playable path.

**Files:**
- Create: `docs/game/art_shippable_gate.md`
- Modify: `docs/game/features/vertical_slice_v1.md` (link gate)

**Gate checklist (must all pass):**
1. Correct scale vs `CELL_SIZE` / kit socket contract
2. Collision/nav-friendly (no invisible snags; floors walkable)
3. Readable in locked-iso camera at gameplay distance
4. Triangle budget documented (structural module target already ~700 tris class is fine)
5. Named, versioned path under `assets/imported/...` or `assets/game/...` (not `assets/tiles/...` PoC dumps)
6. Used by a **live** loader/placer path (not only validation harness)
7. Human visual sign-off note in PR

**Rule:** `assets/tiles/synaptic_sea/` and LoRA training outputs are **pipeline evidence**, not runtime content, until promoted through this gate.

**Step 1:** Write gate doc.  
**Step 2:** Commit `docs: add shippable art gate for runtime promotion`.

---

### Task 0.3: Demo scope inventory snapshot

**Objective:** Know what `DemoScopeGate` already enforces before expanding content.

**Files:**
- Read: `data/release/demo_scope_manifest.json`
- Read: `scripts/systems/demo_scope_gate.gd`
- Read: `data/release/build_metadata.json`
- Create: `docs/game/features/demo_scope_v1.md` (what demo allows/forbids)

**Step 1:** Document current enforcement points (saves, world snapshot, hub meta, derelict hazards, cargo cap — from STATUS/integration debt).  
**Step 2:** Propose demo bounds for Milestone B (max derelicts, max meta unlocks, disabled cloud, build_kind=`demo`).  
**Step 3:** Commit docs only.

---

## Phase 1 — Presentation vertical slice

### Task 1.1: Threat visual contract + catalog

**Objective:** Replace anonymous placeholders with archetype-specific readable visuals.

**Files:**
- Create: `data/combat/threat_visual_catalog.json`
- Modify: `scripts/tools/threat_placeholder_renderer.gd` → evolve into `scripts/tools/threat_visual_renderer.gd` (keep `class_name` stable **or** update all refs)
- Modify: `scripts/systems/threat_manager.gd` (spawn/update paths ~381–511)
- Create: `scripts/validation/threat_visual_catalog_smoke.gd`
- Modify: `docs/game/06_validation_plan.md`

**Catalog shape:**
```json
{
  "version": "threat-visual-1",
  "archetypes": {
    "biomatter_swarm": {
      "mesh_path": "res://assets/imported/threats/biomatter_swarm/biomatter_swarm.glb",
      "y_offset": 0.0,
      "scale": 1.0,
      "albedo_fallback": "#5cff7a"
    }
  }
}
```

**Step 1: Failing smoke** — load catalog, assert 3 slice archetypes resolve paths, assert renderer builds node with MeshInstance3D (or MultiMesh) not unnamed BoxMesh-only for those ids.

**Step 2:** Implement catalog load + renderer fallback (colored silhouette mesh OK if GLB missing, but must be archetype-distinct).

**Step 3:** For slice, author **at least silhouette-grade** meshes (even simple kitbashed GLBs) under `assets/imported/threats/<id>/`. Do not ship identical grey capsules.

**Step 4:** Run:
```bash
GODOT=${GODOT:-godot-4.6.2}
$GODOT --headless --path . -s res://scripts/validation/threat_visual_catalog_smoke.gd
```
Expected marker: `THREAT VISUAL CATALOG PASS`

**Step 5:** Commit `feat(combat): archetype threat visuals via catalog`.

---

### Task 1.2: Interactable prop catalog (kill critical boxes)

**Objective:** Loot/stations/hazards use prop meshes in the slice.

**Files:**
- Create: `data/kits/gameplay_prop_v0.json`
- Create: `assets/imported/props/...` (loot_crate, extinguisher_station, breach_patch_panel, hatch_wheel, workbench, corpse_bag, tool_case)
- Modify: `scripts/tools/loot_container.gd`
- Modify: `scripts/tools/fire_suppression_point.gd`
- Modify: `scripts/tools/breach_seal_point.gd`
- Modify: `scripts/tools/crafting_station.gd`
- Modify: `scripts/tools/tool_pickup.gd`
- Modify: sealed hatch builder path in `scripts/procgen/playable_generated_ship.gd` **or** extracted helper (prefer helper)
- Create: `scripts/validation/gameplay_prop_visual_smoke.gd`

**Step 1:** Define prop ids + socket/height conventions in kit JSON.  
**Step 2:** Add shared `GameplayPropFactory` (`scripts/placement/gameplay_prop_factory.gd`) that instances PackedScene/GLB by id with fallback mesh.  
**Step 3:** Wire each interactable to factory.  
**Step 4:** Smoke instantiates each slice interactable and asserts non-box mesh when catalog present.  
**Step 5:** Commit `feat(presentation): gameplay prop catalog for slice interactables`.

---

### Task 1.3: Structural kit on live derelict path

**Objective:** Generated/away ships use structural modules, not only lifeboat/demo.

**Files:**
- `scripts/procgen/generated_ship_loader.gd`
- `scripts/procgen/structural_placer.gd`
- `scripts/procgen/structural_edge_compiler.gd`
- `data/kits/ship_structural_v0.json`
- `scenes/wrappers/structural/ship_structural_v0/*.tscn`
- `assets/imported/structural/ship_structural_v0/**`
- Smoke: `scripts/validation/procgen_loader_playable_contract_smoke.gd` (+ new visual assert smoke)

**Steps:**
1. Trace current loader mesh path; list where `BoxMesh` still builds walls/floors.
2. Ensure loader consumes structural plan / kit modules for slice biome ships.
3. Add smoke: for seed fixed in slice spec, count MeshInstances from kit wrappers > 0 and box-floor ratio below threshold.
4. Human screenshot evidence path: `artifacts/vertical_slice/structural_seed_<n>.png` (optional automation later).
5. Commit `feat(procgen): structural kit on live generated ship loader path`.

**Stop if:** collision breaks walkability — fix collision first; do not merge pretty-but-unwalkable geometry.

---

### Task 1.4: Lighting + atmosphere pass (slice only)

**Objective:** Rooms read as derelict/horror, not default grey.

**Files:**
- Create: `scripts/procgen/slice_atmosphere_applier.gd`
- Modify: loader or playable ship post-load hook (single call site)
- Data: `data/procgen/biomes/<slice_biome>.json` (add `atmosphere` block: ambient color, exposure, fog, light temperature)

**Minimum:**
- Dim key + cool fill
- Warm emergency accent in breach/fire rooms
- Slight fog denser on away ships
- No expensive GI requirement for demo

**Validation:** windowed smoke or harness scene `scenes/validation/vertical_slice_lookdev.tscn` loads hub+derelict.

**Commit:** `feat(presentation): slice atmosphere/lighting from biome data`.

---

### Task 1.5: Audio content pack (pipeline already exists)

**Objective:** Close the **content** side of ADR-0044.

**Files:**
- `data/audio/sfx/*.wav` (or `.ogg`)
- `data/audio/music/*.wav`
- `scripts/audio/` catalog / `STREAM_CATALOG` (find in `audio_manager.gd` / sfx router)
- `scripts/systems/sfx_event_router.gd`
- Existing smokes: `scripts/validation/audio_pipeline_smoke.gd`, `audio_spatial_playback_smoke.gd`
- Create: `scripts/validation/audio_content_coverage_smoke.gd`

**Minimum clip set (slice):**

| Logical id | Example path |
|---|---|
| `sfx.footstep` | `data/audio/sfx/footstep_metal.ogg` |
| `sfx.tool.pickup` | already exists — replace if placeholder quality |
| `sfx.ui.panel_open` | `data/audio/sfx/ui_panel_open.ogg` |
| `sfx.ui.panel_close` | `data/audio/sfx/ui_panel_close.ogg` |
| `sfx.combat.hit` | `data/audio/sfx/combat_hit.ogg` |
| `sfx.combat.threat_alert` | `data/audio/sfx/threat_alert.ogg` |
| `sfx.hazard.fire` | `data/audio/sfx/fire_loop.ogg` |
| `sfx.hazard.breach_alarm` | `data/audio/sfx/breach_alarm.ogg` |
| `sfx.door.open` / `.close` | door pair |
| `sfx.dock.land` | dock |
| `sfx.ui.vitals_low` | vitals warning |
| `sfx.meta.death` | death sting |
| `music.explore` | exists `exploration_base.wav` — keep or upgrade |
| `music.tension` | new |
| `music.critical` | new |

**Steps:**
1. Inventory router event ids vs files (script grep of `SFX_` / catalog keys).
2. Add missing files (license-clean; record provenance in `data/audio/SOURCES.md`).
3. Wire paths in catalog; no silent missing stream.
4. Smoke: every slice-required id loads and has non-zero stream length.
5. Commit `content(audio): slice audio pack + coverage smoke`.

**Do not:** add more dual-branch SFX smokes without new audible assets.

---

### Task 1.6: HUD/icon non-placeholder pass (slice)

**Objective:** Status/achievements/hotbar do not look like temp rectangles.

**Files:**
- `assets/placeholder/status_*.png` → promote or replace under `assets/ui/status/`
- `data/ui/status_effect_icons.json`
- Achievement icons referenced in `data/release/achievement_catalog.json`
- Hotbar/tool icons as needed

**Steps:** Replace slice-visible icons; keep JSON keys stable; smoke path-exists check.

**Commit:** `content(ui): replace slice-critical placeholder icons`.

---

## Phase 2 — Onboarding + stakes UX

### Task 2.1: Expand tutorial trigger catalog

**Objective:** Teach the real game in the first run.

**Files:**
- Modify: `data/ui/tutorial_triggers.json`
- Modify: `data/ui/codex_entries.json` (matching entries)
- Possibly emit events from coordinator / systems if missing:
  - `oxygen_low`, `fire_nearby`, `threat_spotted`, `first_travel`, `first_death_near_miss`, `breach_open`
- `scripts/systems/tutorial_state.gd`
- `scripts/ui/menu_coordinator.gd` (already wired)
- Create: `scripts/validation/tutorial_slice_coverage_smoke.gd`

**Required tutorials (slice):**
1. Movement (exists)
2. Interact (exists)
3. Inventory (exists)
4. Oxygen / suit pressure when O2 drops or away boarding
5. Fire hazard + extinguisher
6. Breach/seal
7. Threat spotted / combat basics
8. Loot search
9. Travel/scanner open
10. Save/death meaning

**Steps:**
1. Extend JSON; keep schema `tutorial-triggers-1`.
2. Ensure each `trigger_event` has a production emitter (grep like unlock catalog work).
3. Smoke: catalog validates; each slice tutorial id present; emitter map complete.
4. Commit `feat(ui): vertical slice tutorial coverage`.

---

### Task 2.2: Run results / death screen

**Objective:** Failure and extraction feel intentional.

**Files:**
- Create: `scripts/ui/run_results_panel.gd`
- Create: `data/ui/run_results_copy.json` (epitaph lines by cause)
- Modify: `scripts/title_main.gd` (already tracks `_last_run_outcome` — finish the UX)
- Modify: `scripts/procgen/playable_generated_ship.gd` `end_run()` (~1741) to emit structured summary
- Modify: `scripts/ui/menu_coordinator.gd` if in-run end flows there
- Create: `scripts/validation/run_results_smoke.gd`

**Results panel shows:**
- Outcome: death | extraction | abort
- Cause (fire, oxygen, combat, sanity, other)
- Time survived, rooms discovered, threats killed, loot value
- Unlocks gained this run
- Buttons: Return to Title, New Run

**Steps:**
1. Define summary dict contract in smoke first.
2. Build panel; title shows it after `playable_slice_completed` / death.
3. Replace instant bare return with panel.
4. Commit `feat(ui): run results and death epitaph screen`.

---

### Task 2.3: First-run directed beat (soft script)

**Objective:** Guarantee the player sees fire or breach + loot + one threat within 10 minutes without hard railroad.

**Files:**
- `data/procgen/golden/` or slice seed configs
- `data/procgen/encounter_tables/` (slice table)
- Possibly `data/release/demo_scope_manifest.json` for forced first derelict markers
- `scripts/systems/marker_generator.gd` / travel first-target bias

**Steps:**
1. Author `data/procgen/slice/first_run_contract.json` (required beat flags).
2. On new game, first away derelict uses fixed seed satisfying contract.
3. Smoke: generate first derelict → asserts fire_zone or breach + ≥1 encounter + ≥1 loot container.
4. Commit `feat(procgen): first-run derelict beat contract`.

---

## Phase 3 — Content depth (one-hour demo spine)

### Task 3.1: Threat fantasy pack (behavior + telegraphs)

**Objective:** 3 slice threats play differently, not just different HP.

**Files:**
- `data/combat/threat_archetypes.json`
- `scripts/systems/threat_ai_state.gd`
- `scripts/systems/detection_state.gd`
- Balance notes: `docs/game/balance/combat_threat_ai.md`
- Smokes under `scripts/validation/*threat*`

**Per archetype minimum:**
- Unique detect profile (noise/light/sight weights)
- Unique attack interval/damage type
- Unique telegraph (audio + optional material pulse already in renderer)
- Loot table on corpse

**Commit:** `content(combat): differentiate slice threat fantasies`.

---

### Task 3.2: Loot / repair economy tuning pass

**Objective:** Scarcity supports tension; junk doesn’t brick progression.

**Files:**
- `data/items/loot_tables.json`
- `data/items/item_definitions.json`
- `data/items/junk_items.json`
- `data/recipes/recipe_definitions.json`
- `data/ship_systems/*.json`
- `docs/game/balance/` new `vertical_slice_economy.md`
- Prefer `TuningCatalog` / data over code constants where seams exist (`scripts/systems` + pre-polish A4)

**Targets (write into balance doc):**
- First derelict always contains path to extinguisher charge **or** sealant
- Cart/encumbrance bites by minute 15 if greed-looting
- Hub repair parts gated but not impossible

**Validation:** headless economy sim smoke if present; else playtest checklist + deterministic seed assertions on loot rolls.

**Commit:** `balance: slice loot/repair economy targets`.

---

### Task 3.3: Starts that matter (2–3 classes)

**Objective:** Progression machinery shows player-facing difference.

**Files:**
- `data/player/classes.json`
- `data/player/skills.json` / `skill_tree.json` / `skill_effects.json`
- `scripts/systems/class_definition.gd` / progression wiring
- Title/new-game class pick UI if missing (`scripts/title_main.gd`, `scripts/ui/class_panel.gd`)

**Ship 3 starts max for demo:** e.g. Engineer, Scavenger, Medic — distinct starting tools/skills only.

**Commit:** `content(progression): three distinct demo starts`.

---

### Task 3.4: Room dressing + landmarks

**Objective:** Players can navigate by sight.

**Files:**
- `scripts/procgen/readability_prop_factory.gd` (upgrade from primitives gradually)
- Dressing data used by loader/gameplay slice builder
- Biome kit variants: `data/kits/ship_structural_industrial.json`, `ship_structural_hazard.json` if live

**Rule:** Dressing must not break nav/collision (existing dressing consumption rules).

**Commit:** `feat(procgen): role-readable room dressing for slice biome`.

---

### Task 3.5: Narrative texture pack (thin but real)

**Objective:** Horror tone without branching epic.

**Files:**
- `data/ui/codex_entries.json`
- Audio logs under `data/audio/voice/` (paths already referenced in `scripts/audio/audio_log.gd`)
- Unique items flavor: `data/items/unique_items.json`

**Ship:** 8–12 codex entries, 4 voice logs with **real** ogg files (refs currently point at missing voice paths).

**Commit:** `content(narrative): slice codex + voice logs`.

---

## Phase 4 — Coordinator strangler (engineering enabler)

> Goal from STATUS: drive `scripts/procgen/playable_generated_ship.gd` toward **&lt;3k lines**. Current ~**11,456**. Do this in vertical slices of extraction, each with smokes green.

### Task 4.1: Map ownership boundaries

**Objective:** Produce extraction order without coding yet.

**Files:**
- Create: `docs/game/architecture/playable_coordinator_strangler.md`

**Extract candidates (suggested order):**
1. `_tick_survival_attrition` + vitals death → `scripts/systems/survival_runtime_driver.gd`
2. Threat tick + combat input → `combat_runtime_driver.gd`
3. Audio refresh / SFX → already partial; finish `audio_runtime_driver.gd`
4. Interact dispatch → `interaction_router.gd`
5. Travel/dock/hangar → `travel_runtime_driver.gd`
6. UI panel open bindings stay in menu coordinator

**Commit:** docs only.

---

### Task 4.2: Extract survival runtime driver

**Objective:** First real strangler bite.

**Files:**
- Create: `scripts/systems/survival_runtime_driver.gd`
- Modify: `playable_generated_ship.gd` (delegate both branches)
- Move/adapt smokes: vitals/oxygen/fire drain away/home
- Update inventory driven_at citations via `tools/build_system_inventory.py` after merge

**TDD loop:**
1. Smoke that driver.tick(delta, ctx) applies same drains as current on fixture ctx.
2. Switch coordinator to driver.
3. Full survival-related smokes + regression subset.
4. Commit `refactor: extract survival runtime driver from playable coordinator`.

---

### Task 4.3: Extract interaction router

**Objective:** Stop growing interact match/if forests in coordinator.

**Files:**
- Create: `scripts/interaction/interaction_router.gd`
- Move nearest-target dispatch for loot/fire/breach/craft/work/hatch
- Keep side effects via injected callbacks/services
- Smokes: existing interact/consume-path smokes must stay green

**Commit:** `refactor: interaction router extraction`.

---

### Task 4.4: Extract combat runtime driver

**Objective:** Threat tick, attack, corpse loot spawn leave coordinator.

**Files:**
- `scripts/systems/combat_runtime_driver.gd`
- Wire detection + threat_manager + player attack
- Preserve away/home parity smokes

**Commit:** `refactor: combat runtime driver extraction`.

---

### Task 4.5: Line-count gate

**Objective:** Prevent regressions.

**Files:**
- Create: `scripts/validation/coordinator_linecount_smoke.gd`
- Budget stages: after 4.2–4.4 expect ≤ 9k; track toward 3k in later EA phase

**Marker:** `COORDINATOR LINECOUNT PASS lines=N budget=9000`

**Commit:** `test: coordinator linecount budget smoke`.

---

## Phase 5 — Human playtest + balance gate

### Task 5.1: Playtest protocol for product (not Gate-1 systems)

**Files:**
- Create: `docs/game/playtests/vertical_slice_protocol.md`
- Create: `docs/game/playtests/vertical_slice_rubric.json`
- Template already: `docs/game/playtests/playtest_template.md`

**Rubric dimensions (1–5):** comprehension, tension, unfairness, navigation, audio clarity, UI overload, want-to-continue.

**Critical fail criteria:** hard softlock, unrecovered crash, cannot figure move/interact in 2 minutes, death with zero feedback.

---

### Task 5.2: Run 5 blind sessions + write

**Objective:** Evidence pack before demo packaging.

**Files:**
- Create: `docs/game/playtests/vertical_slice_results_YYYY-MM-DD.md`
- Bug list → kanban or `docs/game/playtests/findings/`

**Process:**
1. Build stamped local export.
2. 5 players; no coaching beyond “new game.”
3. Log timestamps of firsts: loot, fire, threat, travel, death.
4. File P0/P1 only for Milestone A exit.

**Exit A only if:** no open P0; ≤2 P1 with workarounds; median “want-to-continue” ≥3.

---

### Task 5.3: Balance patch from findings

**Objective:** Turn playtest notes into data changes, not new systems.

**Files:** primarily `data/**` tuning + copy in tutorials.

**Commit:** `balance: playtest pass 1 retune`.

---

## Phase 6 — Public demo packaging (itch)

### Task 6.1: Enforce demo build_kind

**Files:**
- `data/release/build_metadata.json` (`build_kind: demo`)
- `data/release/demo_scope_manifest.json` (finalize limits)
- `scripts/systems/demo_scope_gate.gd`
- `scripts/export/build_release.sh`
- `export_presets.cfg`

**Steps:**
1. Demo manifest caps: N derelicts, disabled cloud, feature flags aligned to slice+spine.
2. Export script stamps `synaptic-sea-demo-vX.Y.Z-{os}`.
3. Smoke exported binary boots title (platform-specific).
4. Commit `feat(release): demo build_kind + scope enforcement`.

---

### Task 6.2: Store package assets

**Files:**
- Create: `docs/game/store/itch_page_draft.md`
- Create: `artifacts/store/cover_630x500.png`
- Create: `artifacts/store/screenshot_{1-5}.png` (real in-engine)
- `docs/game/release_notes/DEMO_v0.1.0.md`
- Player `CHANGELOG.txt` copied by export script

**Use:** `docs/game/store_requirements.md` checklist IDs ITCH-001… but mark honestly; complete blockers only.

---

### Task 6.3: Export regression on demo content

**Files:**
- `docs/game/06_validation_plan.md`
- `docs/game/export_regression_report.md` (refresh date)

**Commands:**
```bash
# Editor regression (from validation plan tail)
bash -lc 'source docs/game/06_validation_plan.md'  # ONLY if plan is executable script section — else run the documented bundle runner

# Prefer project’s real runner if present:
ls scripts/export/
./scripts/export/build_release.sh demo
```

**Expected:** `SYNAPTIC_SEA REGRESSION PASS` on editor; demo export launches; save path works (`user://`).

**Manual:** New Game → tutorial → first derelict → save/load → death or extract → results → title.

---

### Task 6.4: itch upload dry-run

**Objective:** Butler channels ready (`win-demo`, `mac-demo`).

**Files/docs:** `docs/game/export_pipeline.md` update with actual commands used.

**Stop if:** secrets would enter git — keys stay outside repo.

---

## Phase 7 — Early Access production hardening

Do **not** start until Milestone B is public or explicitly waived.

### Task 7.1: Content breadth roadmap
- Biomes: enable `abyssal_synaptic_sea` + remaining with art kits
- Threats: finish all 6 + 2 new signatures
- Templates: ensure stacked/bifurcated/etc. dressed
- Classes: expand only after demo telemetry/play feedback

### Task 7.2: Finish coordinator strangler to &lt;3k
Continue Phase 4 extractions until budget smoke `budget=3000`.

### Task 7.3: Performance budget on dressed ships
- Refresh `docs/game/performance_baseline.md` with content-heavy scenes
- Targets: 60 fps desktop target machine; define min spec

### Task 7.4: Accessibility + settings polish
- Execute remaining items in `docs/game/accessibility_review.md` that are still open
- Colorblind hazard cues, subtitle scale already partial — verify with humans

### Task 7.5: Live ops lite
- Crash report bundle path real enough for EA
- Known issues manifest `data/integration/known_issue_fix_manifest.json` maintained
- Versioning + migration discipline on save (`save_migration_service.gd`)

### Task 7.6: Production release candidate
- Flip `build_kind: release`
- Full store page
- Windows/macOS (±Linux) evidence
- Postmortem template filled after launch week

---

## Cross-cutting validation standard (every implementation task)

1. Focused smoke with explicit `PASS` marker string.
2. No new unclassified Godot `ERROR:` / `WARNING:`.
3. If inventory driven_at lines move: run
   ```bash
   python3 tools/build_system_inventory.py --check
   ```
   Expected: `SYSTEM INVENTORY CHECK PASS`
4. If coordinator touched: run dual-branch relevant smokes (away_from_start).
5. Update `STATUS.md` only for milestone-level landings (not every SFX).
6. Art must pass `docs/game/art_shippable_gate.md`.

---

## Files most likely to change (summary)

| Area | Paths |
|---|---|
| Coordinator | `scripts/procgen/playable_generated_ship.gd` (minimize; extract) |
| Combat visuals | `scripts/tools/threat_placeholder_renderer.gd`, `scripts/systems/threat_manager.gd`, `data/combat/*` |
| Props | `scripts/tools/*.gd`, `scripts/placement/gameplay_prop_factory.gd`, `data/kits/*`, `assets/imported/**` |
| Procgen present | `scripts/procgen/generated_ship_loader.gd`, `structural_placer.gd`, biomes/kits |
| Audio | `data/audio/**`, `scripts/audio/**`, `scripts/systems/sfx_event_router.gd` |
| UI/onboarding | `data/ui/tutorial_triggers.json`, `scripts/ui/*`, `scripts/title_main.gd` |
| Release | `data/release/*`, `scripts/export/build_release.sh`, `export_presets.cfg` |
| Validation | `scripts/validation/*`, `docs/game/06_validation_plan.md` |
| Truth docs | `STATUS.md`, `docs/game/features/vertical_slice_v1.md`, inventory if citations move |

---

## Risks and tradeoffs

| Risk | Mitigation |
|---|---|
| Agents keep adding systems/smokes instead of product | Phase 0 contract + reject PRs without player-visible delta |
| PoC tiles treated as ship art | Shippable art gate; tiles dir non-runtime |
| Coordinator choke | Phase 4 parallel after slice hooks stabilized; single-writer rule |
| Scope explosion past demo | `DemoScopeGate` + manifest hard caps |
| False confidence from 627 smokes | Milestone exits require human playtest rubric |
| Audio/legal | `data/audio/SOURCES.md` provenance required |
| Beauty breaks collision | Walkability smokes before art merge |
| Doc drift | STATUS + inventory only; archive gate myths stay quarantined |

---

## Open questions (resolve in Task 0.1 before implementation fan-out)

1. **Slice biome pick:** `breach_field` vs `dead_fleet` as first public face?
2. **Demo length target:** 45 vs 90 minutes hard cap?
3. **Permadeath messaging:** ironman-only demo or optional easier mode for critics?
4. **Art production source of truth:** hand-authored Blender kitbash vs promoted AI-assisted textures behind shippable gate?
5. **Class select at title:** required for demo or fixed default + unlock later?
6. **Platform priority for demo:** Windows-only first, or Win+Mac mandatory?

Record answers in `docs/game/features/vertical_slice_v1.md` Decisions section.

---

## Suggested execution order (first 10 working days)

| Day | Focus |
|---|---|
| 1 | Tasks 0.1–0.3 (contract) |
| 2–3 | 1.5 audio pack + 2.1 tutorials (high leverage, less art blocked) |
| 3–5 | 1.1 threats + 1.2 props (silhouette-grade OK) |
| 5–7 | 1.3 structural live path + 1.4 lighting |
| 7–8 | 2.2 results screen + 2.3 first-run beat |
| 8–9 | 4.2 survival extraction (unblock future) |
| 10 | Internal playtest dry-run; file P0s |

Then Phase 3 depth → Phase 5 formal playtests → Phase 6 itch.

---

## Done means

**This plan is complete when Milestone B (Public Demo) is uploadable and Milestone A criteria are met with evidence.** Milestone C is roadmap, not a single sprint.

**Immediate next action after plan approval:** implement Task 0.1 only; do not start asset spam until slice contract answers the open questions.
