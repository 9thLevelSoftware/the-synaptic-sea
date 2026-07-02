# Completion Roadmap — design spec

**Date:** 2026-06-28
**Status:** approved in brainstorming; pending written-spec review.
**Author:** completion-roadmap effort (built on the code-verified inventory, PRs #47–#49).
**Supersedes:** the quarantined Gate/M-lane roadmaps in `docs/archive/`.

## Context

The system inventory (`docs/game/inventory/system_inventory.json`, code-verified, 187 systems,
100% `confidence: "V"`) established what exists. It also graded the 18 player-facing **loops** on
whether the simulation actually *closes* them. The result:

- **7 closed** — sanity→hallucination, fire, crafting economy, loot, UI shell, HUD feedback,
  settings/accessibility.
- **8 partial** — food, ship-systems core, combat, consumables, progression, travel, save, map-reveal.
- **3 broken** — survival-vitals, audio-reactivity, tooltip.

The game is structurally far along (most systems are 90–100% built). The remaining work is **not
new systems** — it is **closing loops and wiring dead integrations**. The single highest-leverage gap
is that the game has **no terminal failure state**: `end_run('death')` is defined
(`playable_generated_ship.gd:1488`) but has zero callers, so survival, combat, and sanity all drain
into a consequence-free sink.

This spec is the deferred "vision reset → phased roadmap" artifact. It defines **the path from the
current build to every loop closed**, sequenced so we never lose track again.

## Goal

Close **all 18 loops** to `🟢 closed`, domain-by-domain, with each domain's completion **measured by
the code-verified inventory flipping that loop green** — so progress is validated, not asserted.

## Decisions locked (from brainstorming)

1. **Scope: close every loop.** Completionist. Every partial/broken loop reaches `🟢 closed`,
   including food production, meta-progression, and multi-slot save.
2. **Sequencing: domain-by-domain**, one loop fully closed before the next starts — **except**
   Survival & Stakes is mandatory **first** (it is the keystone every other domain depends on), and
   each domain owns its own away-branch wiring as part of its closure.
3. **Audio scope: bus + pipeline only.** The audio loop "closes" when the bus layout is registered,
   the stream-loading path is proven with 1–2 clips, and captions are pumped. A full curated SFX/
   music/voice asset library is **out of scope** for loop-closure (separate later content pass).

## The measurement mechanism (anti-drift)

A domain is **done** when, and only when:

1. Its loop(s) read `"closes": "closed"` in `system_inventory.json`, with `break_points` cleared or
   reduced to deliberate, documented deferrals.
2. The contributing systems' `input.live` / `output.live` booleans are flipped true with **new
   line-cited evidence**, so the generator re-derives their coupling to `🟢` and their completion %
   upward.
3. `tools/build_system_inventory.py --check` passes against freshly regenerated
   `SYSTEM_INVENTORY.md` + `system_map.html` (marker `SYSTEM INVENTORY CHECK PASS systems=N verified=N`).
4. The full regression bundle still ends `SYNAPTIC_SEA REGRESSION PASS`.

Progress is therefore **the inventory turning green**, which the `--check` smoke already guards. This
is what makes "losing track again" structurally impossible: the tracker *is* the validated source of
truth, not a hand-maintained doc.

## Global constraints (apply to every domain)

- **Validation is the definition of done.** No domain closes without fresh PASS-marker output.
- **Both `_process` branches.** Any per-frame tick/feed/refresh added MUST be wired into the
  `away_from_start` (derelict) branch *and* the home branch of
  `playable_generated_ship.gd::_process` — the away-branch early-return at **line 4808** has caused
  three shipped regressions. Every domain's smoke includes an `away_ticks=`-style assertion that
  drives `away_from_start = true`.
- **Typed GDScript** for all new systems; Resources are data, Nodes are behavior.
- **Baseline noise allowlist** (the two teardown lines + the one expected SaveLoadService rejection)
  is unchanged; any *other* `ERROR:`/`WARNING:` blocks completion.
- Each domain updates `docs/game/06_validation_plan.md` with its new smokes and expected markers.

## Non-goals (explicitly out of scope)

- **Full audio asset library** (curated SFX/music/voice). Bus+pipeline only; population is a later
  content pass.
- **New content breadth** beyond what a loop needs to close (no new enemy archetypes, derelict
  storylines, or items unless a break-point requires one to exist).
- **Engine/architecture rewrites.** This is wiring + targeted models on the existing coordinator.
- **Visual/art polish, shaders, marketing, export pipeline.**

## Domain sequence

| # | Domain | Loop(s) | Current | Depends on |
|---|---|---|---|---|
| 1 | Survival & Stakes ⭐ | `survival_vitals` | 🔴 broken | — |
| 2 | Combat | `combat` | 🟡 partial | 1 (death), loot, progression |
| 3 | Food | `food` | 🟡 partial | 1 (away-branch pattern) |
| 4 | Ship Systems | `ship_systems` | 🟡 partial | 1 |
| 5 | Consumables | `consumables` | 🟡 partial | 1, 2 (ammo→combat) |
| 6 | Progression & Meta | `progression` | 🟡 partial | 2 (kill XP), 8 (persist unlocks) |
| 7 | Travel / Procgen | `travel` | 🟢 closed | — |
| 8 | Save / Persistence | `save` | 🟡 partial | 1 (permadeath needs death) |
| 9 | Audio | `audio_reactive` | 🔴 broken | — |
| 10 | UI/UX Polish | `tooltip`, `map_reveal` | 🔴 / 🟡 | — |

> Dependency notes are advisory ordering hints; the hard rule is **Domain 1 first**. Domains 6 and 8
> have a mild circular hint (meta unlocks persist via save; permadeath needs death from D1) — D1
> resolves the hard dependency, and D6/D8 can be sequenced either order after that.

Each domain entry below uses the same template: **loop steps → verified break-points (line-cited from
the inventory) → definition of CLOSED → away-branch checklist → validation → inventory delta**.

---

### Domain 1: Survival & Stakes ⭐  [loop: `survival_vitals`, current: 🔴 broken]

**The keystone.** Establishes the terminal failure state the entire survival-horror premise needs.

**Loop steps:** radiation_state (source: health drain) · body_temperature_state (source: thirst mult)
· status_effects_state (source: stamina mult) · sanity_state (source: tier-3 teeth) → vitals_state (sink).

**Verified break-points (from inventory):**
- `end_run('death')` (`playable_generated_ship.gd:1488`) is defined and **never called** (grep: zero
  callers). No `health<=0` death/incapacitation check exists. No sprint/action gating reads vitals →
  attrition never produces a gameplay failure.
- `radiation_state.tick` (4884), `body_temperature_state.tick` (4887), `status_effects_state.tick`
  (4889) run **only in the home branch** after the away early-return at 4808 → on a boarded derelict
  (primary context) they never advance.
- `body_temperature_state.in_extreme_zone = away_from_start` is assigned at **4886 inside the home
  branch** where `away_from_start` is always false → the extreme-zone source never activates
  (temperature→thirst coupling permanently neutral 1.0).

**Definition of CLOSED:**
1. A `health<=0` (and/or incapacitation threshold) consumer calls `end_run('death')` — wired into
   **both** `_process` branches — producing a real run-ending failure with the existing run-end/save
   flow.
2. Low-vitals **action-gating**: at least one player capability (sprint/interact/attack) is gated or
   penalized by a vitals threshold, so attrition changes play before death.
3. radiation/body-temp/status ticks run on the **away branch** on a derelict.
4. The extreme-zone source is driven by a real environmental signal (not the always-false
   `away_from_start` at 4886), so temperature→thirst actually engages in hazardous zones.

**Away-branch checklist:** radiation tick · body-temp tick · status-effects tick · the death/
incapacitation check · action-gating evaluation — all live on the `away_from_start` branch.

**Validation:** `survival_stakes_smoke.gd` (pure-model: drive vitals to 0 → assert death fired;
assert action-gating engages at threshold) + a main-scene smoke with `away_ticks=` driving
`away_from_start = true` and asserting radiation/temp/status advanced and death can fire on a
derelict. Register both in `06_validation_plan.md`.

**Inventory delta:** `survival_vitals.closes → "closed"`; clear the three break-points (or reduce to
documented deferrals); flip `vitals_state.output.live` true with the death-consumer citation;
`survival_sanity`'s "no death sink" caveat auto-resolves.

---

### Domain 2: Combat  [loop: `combat`, current: 🟡 partial]

**Loop steps:** detection_state (sense) · threat_ai_state (decide) · threat_manager (resolve) ·
damage_pipeline (apply) · armor_resolver (mitigate) → vitals_state (player sink) + threat_ai_state
(threat death counter-sink).

**Verified break-points (from inventory):**
- `detection_state` computed output (detected/awareness_score/heard/seen) is **HUD-only**
  (`threat_manager.gd:181`); the AI computes a parallel awareness from raw player signals
  (`threat_ai_state.gd:88-94`) and only borrows detection's static `detect_threshold`
  (`threat_manager.gd:81`) — the detection model is **decorative**.
- Player stealth inputs feeding detection/AI are near-hardcoded literals in `_tick_threat_runtime`
  (`playable_generated_ship.gd:3901-3907`) — stealth dimension is shallow (only noise has a tiny
  live `is_moving` component).
- **Killing a threat yields no reward and never removes it:** `STATE_DEAD` threats linger in
  `threats[]` and are merely skipped by `_pick_target` (`threat_manager.gd:257`); no loot/XP closes
  the kill incentive.

**Definition of CLOSED:**
1. `detection_state`'s computed awareness is the **actual** input the AI consumes (single source of
   truth), not a parallel HUD-only calc.
2. Player stealth inputs (noise/visibility) are driven by **real** runtime signals (movement, light,
   crouch/cover) rather than literals.
3. Threat death produces a **reward** (loot drop and/or XP via the progression bus) and the corpse is
   removed or transitioned out of the active array.

**Away-branch checklist:** threat tick, detection feed, and kill-reward path all live on the away
branch (combat happens on derelicts).

**Validation:** `combat_closure_smoke.gd` — assert AI consumes detection output; assert a kill emits
loot/XP and clears the threat; `away_ticks=` driving a derelict combat tick. Register markers.

**Inventory delta:** `combat.closes → "closed"`; flip `detection_state.output.live` (now consumed by
AI) and `threat_ai_state.output.live` (kill→reward); update break-points.

---

### Domain 3: Food  [loop: `food`, current: 🟡 partial]

**Loop steps:** consumable_state (acquire) · spoilage_state (age) · food_state (freshness) →
consumable_state (eat → vitals/sanity restore).

**Verified break-points (from inventory):**
- **Production half is fully dead:** `hydroponics_state.plant()/harvest()`,
  `synthesizer_state.start_synthesis()`, `water_recycler_state.load_input()` have **no runtime
  callers** (grep: only validation smokes) — none ever produces food/water.
- Away early-return (4808) means the food tick block (4891-4898) and sustenance/recycler reads (1359,
  1390-1394, inside `_recompute_expanded_ship_systems` called only at 4817) run **home-only** → food
  does not spoil on a derelict.
- `water_recycler` output is wired into life_support (1359) but always 0 (input never loaded).
- `sustenance_state` ticks at 1390 but is a read-only HUD/save roll-up of three dead stations — no
  consumer grants items.

**Definition of CLOSED:**
1. Hydroponics/synthesizer/water-recycler have **live player or station callers** that consume inputs
   and **produce** food/water items into inventory over time.
2. `sustenance_state`'s counts feed a real consumer (or the roll-up is removed as redundant).
3. Spoilage ages on the **away branch**.

**Away-branch checklist:** spoilage tick + (if stations operate while boarded) production ticks on the
away branch — or an explicit, documented "stations pause while away" design decision mirroring crafting.

**Validation:** `food_production_smoke.gd` — plant→harvest yields an item; synth produces; recycler
output > 0; `away_ticks=` asserting spoilage advances on a derelict. Register markers.

**Inventory delta:** `food.closes → "closed"`; flip `hydroponics_state`/`synthesizer_state`/
`water_recycler_state`/`sustenance_state` `output.live`; update break-points.

---

### Domain 4: Ship Systems  [loop: `ship_systems`, current: 🟡 partial]

**Loop steps:** ship_systems_manager (repair source) · power_grid_state (distributor) ·
propulsion_expanded_state (travel-gate sink) · life_support_expanded_state (atmosphere→vitals sink) ·
hull_integrity_state (modifier) · crafting_state (sink).

**Verified break-points (from inventory):**
- `sustenance_state` is HOLLOW within this loop (no live production source; HUD-text-only output) —
  resolved by Domain 3.
- `hull_integrity_state` input is **half-coupled**: live damage sources #1–3 (combat/hazard/pressure)
  are deferred; only config-injected breach + a validation seam (1422) call `damage_compartment`.
- `manager.advance` (4816) + power/propulsion/life_support/crafting recompute (4817 →
  `_recompute_expanded_ship_systems`) run **only on the home branch**; away returns at 4808 first.

**Definition of CLOSED:**
1. `hull_integrity_state` takes **live damage** from at least one real runtime source (combat hits,
   hazard, or pressure) — not just config injection.
2. `manager.advance` + the expanded-systems recompute run on the **away branch** (ship systems
   degrade/recover while the player is aboard a derelict if the design intends it; otherwise document
   the home-only choice explicitly as with crafting).

**Away-branch checklist:** manager advance + expanded recompute on the away branch (or documented
deferral); hull damage feed live.

**Validation:** `ship_systems_closure_smoke.gd` — apply a live damage source to hull and assert
compartment damage; `away_ticks=` asserting advance/recompute ran on a derelict. Register markers.

**Inventory delta:** `ship_systems.closes → "closed"`; flip `hull_integrity_state.input.live` with the
real damage-source citation; update break-points.

---

### Domain 5: Consumables  [loop: `consumables`, current: 🟡 partial]

**Loop steps:** consumable_state (entry) · effect_dispatcher (executor) · medicine_state ·
stimulant_state · addiction_state · utility_item_resolver · ammo_state.

**Verified break-points (from inventory):**
- `ammo_state` is a **dead-end sink**: ammo-pack use increments reserves no gameplay consumer reads
  (no runtime `consume()` caller; output hollow).
- 2 of 4 ammo packs (`flare_round`, `shock_probe`) reference **orphan effect ids** (`flare_burn`,
  `shock_jolt`) absent from `effect_definitions.json` → those uses return `ok:false`.
- `stimulant_state.tick` + `addiction_state.tick` run **home-only** (4830-4832); item USE works away,
  but per-frame buff/withdrawal/tolerance decay freezes on a derelict.
- `utility_flag` bypass is **hollow**: `utility_lockpick_ready`/`utility_hack_chip_ready` statuses are
  set but no gameplay system reads them for the promised hatch/terminal bypass.
- `effect_dispatcher`'s `temperature_delta → body_temperature_state` branch is never reached (no
  effect definition uses `kind temperature_delta`).

**Definition of CLOSED:**
1. `ammo_state` reserves are **consumed** by a real combat consumer (ties to Domain 2 weapons).
2. The two orphan effect ids exist in `effect_definitions.json` (or the packs are repointed to valid
   effects).
3. `stimulant_state`/`addiction_state` ticks run on the **away branch**.
4. `utility_flag`s are **consumed** by hatch/terminal bypass logic (or the flags are removed if the
   bypass is cut).
5. At least one effect uses `temperature_delta` (or that dispatcher branch is removed as dead code).

**Away-branch checklist:** stimulant tick + addiction tick on the away branch.

**Validation:** `consumables_closure_smoke.gd` — assert ammo consumed by firing; orphan effects
resolve; utility flag opens a gated object; `away_ticks=` asserting stim/addiction decay on a
derelict. Register markers.

**Inventory delta:** `consumables.closes → "closed"`; flip `ammo_state`/`utility_item_resolver`
`output.live`; update break-points.

---

### Domain 6: Progression & Meta  [loop: `progression`, current: 🟡 partial]

**Loop steps:** class_definition (config) · training_event_bus (ingest) · player_progression_state
(core, live) · meta_progression_state (meta accrual) · unlock_registry (meta sink, write-only) ·
hub_upgrade_state (spend, broken) · skill_tree_state (unlock, broken).

**Verified break-points (from inventory):**
- Inner loop is **live/closed** (earn XP → level skills → gate scan/craft/repair).
- **Outer meta loop is broken:** `hub_upgrade_state.purchase()` is never called from gameplay
  (hub_upgrade_panel is render-only) → `meta_currency` accrues with no sink.
- `unlocked_hub_upgrade_ids` never populates → `compose_*()` at run-start (1275/1290) always returns
  base values → cross-run upgrade-bonus loop is dead.
- `skill_tree_state.unlock()/can_unlock()` never called → skill tree is display-only.
- `unlock_registry` accrues to disk at run-end (6017) but has **no live reader** (write-only).
- `emit_training_event` seam (1503) is dead; tool nodes bypass the bus.

**Definition of CLOSED:**
1. `hub_upgrade_state.purchase()` is **called** from the hub-upgrade UI, spending `meta_currency`;
   purchased ids persist and `compose_*()` applies real bonuses next run.
2. `skill_tree_state.unlock()` is **called** from the skill-tree UI and gates/grants real gameplay.
3. `unlock_registry` has a **live reader** that surfaces unlocked codex/scenes/classes in-game.
4. Tool-node XP flows **through** `training_event_bus` (seam 1503 live) — single ingest path.

**Away-branch checklist:** XP grant path live on the away branch (kills/objectives on derelicts grant
XP); meta accrual at run-end is branch-agnostic.

**Validation:** `progression_meta_smoke.gd` — purchase a hub upgrade and assert it applies next run;
unlock a skill-tree node and assert its gameplay effect; assert registry read surfaces an unlock;
tool XP routes through the bus. Register markers.

**Inventory delta:** `progression.closes → "closed"`; flip `hub_upgrade_state`/`skill_tree_state`/
`unlock_registry`/`training_event_bus` `output.live`; update break-points.

---

### Domain 7: Travel / Procgen  [loop: `travel`, current: 🟢 closed]

**Loop steps:** the full layout pipeline (template_selector → … → generated_ship_loader) plus
biome/difficulty tuning and the encounter injector.

**Closed break-points (Domain 7):**
- Variant effects live in `room_variant_selector.VARIANT_EFFECTS` (code, per Domain-7 spec decision #2)
  and are consumed: `gameplay_slice_builder` applies `loot_bias`; `playable_generated_ship` drives live
  fire/breach hazard state for compartment-mapped variant rooms; `generated_ship_loader` records
  dressing descriptors → rooms vary.
- Extended structural templates enabled at `deep_dive`/`hardened` difficulty tiers
  (`ship_generator.gd:_extended_for`), producing visible structural variety.
- Legacy `room_graph_generator` carries a DEPRECATED banner (line 4); excluded from the travel loop
  steps and completion % (`loops: []`, `reachable: false`, `driven: false`).

**Definition of CLOSED:**
1. Variant effects live in `room_variant_selector.VARIANT_EFFECTS` (code, per Domain-7 spec decision #2) and are consumed: `gameplay_slice_builder` applies `loot_bias`; `playable_generated_ship` drives live fire/breach hazard state for compartment-mapped variant rooms; `generated_ship_loader` records dressing descriptors → rooms vary.
2. Extended structural templates are **enabled** on live generation at `deep_dive`/`hardened` tiers
   (`ship_generator.gd:_extended_for`), producing visible structural variety.
3. Legacy `room_graph_generator` is explicitly documented as deprecated/test-only (DEPRECATED banner
   at line 4, excluded from travel loop and completion %).

**Away-branch checklist:** N/A (generation is pre-run, not per-frame), but the slice's encounter/loot
injection must remain deterministic per seed. Fire/breach hazard seeding runs away-branch only
(`_seed_derelict_fire`/`_seed_derelict_breaches` check `away_from_start`), guarded by
`fire_seeded`/`breach_seeded` flags on `ShipInstance`.

**Validation:** `procgen_variation_smoke.gd` (marker `PROCGEN VARIATION PASS variants_vary=true
loot_biased=true tmpl_gated=true deterministic=true`) + `procgen_variant_hazard_smoke.gd` (marker
`PROCGEN VARIANT HAZARD PASS away_ticks=1 fire_lit=true breach_open=true home_clean=true
guarded=true`). All three registered in the regression bundle (`commands=107`).

**Inventory delta:** `travel.closes → "closed"`; `room_variant_selector.output.live → true`; break-points
replaced with closure evidence; `room_graph_generator` name/content_note/gaps updated to document
deprecation.

---

### Domain 8: Save / Persistence  [loop: `save`, current: 🟡 partial]

**Loop steps:** run_snapshot/world_snapshot (capture) · autosave_policy (driver) · save_load_service
(persist) · save_index/slot (index) · save_load_menu (present) · save_migration (migrate) ·
cloud_manifest (integrity) · permadeath_resolver (death-gate).

**Verified break-points (from inventory):**
- Multi-slot **LOAD path** (`load_from_slot`) has **no live caller**: `request_load` uses `load_world`
  (world.json) only; `SaveLoadMenu.select_slot_for_load` is never dispatched. Slots are write-only in
  practice.
- Permadeath sub-loop is **hollow & doubly dead**: `record_death` has no live caller, and its only
  consume site (`load_from_slot:249`) is itself never reached.
- No boot-time auto-resume (`request_load` is manual, F9 at 7065-7066).
- Cloud manifest is a stub; its tamper-gate read side (`load_from_slot:289-302`) is never reached.
- Quicksave guards (`AutosavePolicy.try_quicksave` + `SaveLoadMenu.confirm_quicksave`) are unwired.
- `SaveLoadMenu` load/save/delete dispatch methods have no live caller.

**Definition of CLOSED:**
1. `SaveLoadMenu.select_slot_for_load` is **wired** so the multi-slot LOAD path runs in real play.
2. `record_death` is **called** on player death (ties to Domain 1) and freezes the run's slot;
   `load_from_slot` honors the permadeath gate.
3. Boot-time auto-resume offers the latest autosave (or an explicit "continue" entry).
4. **Amended 2026-07-01 (ADR-0043):** the game is heading multiplayer / Project-Zomboid-like, where
   quicksave/quickload doesn't fit the design. Item 4 is satisfied instead by **Save & Exit** (a
   new pause-menu action that calls `request_save()` and returns to the title screen).
   `AutosavePolicy.try_quicksave`/`SaveLoadMenu.confirm_quicksave` stay intentionally unwired --
   dead-but-harmless, model-smoked, available if a future package ships a real quicksave key.

**Away-branch checklist:** autosave triggers fire on the away branch (don't lose a derelict run on
crash); death→permadeath gate fires on the away branch.

**Validation:** `permadeath_freeze_smoke.gd`, `title_save_query_smoke.gd`, `title_screen_flow_smoke.gd`,
`title_settings_smoke.gd`, `save_load_slot_screen_smoke.gd`, `save_and_exit_smoke.gd` — write to a
slot, load it back through the **live** path; death freezes every slot written this run and load
respects the freeze; the title screen offers New Game/Continue/Settings and Save & Exit round-trips
through `request_save()`. Registered in the regression bundle (`06_validation_plan.md`,
`commands=112`).

**Inventory delta:** `save.closes → "closed"`; flip `save_load_menu`/`permadeath_resolver`
`output.live`/`input.live`; update break-points.

---

### Domain 9: Audio  [loop: `audio_reactive`, current: 🔴 broken — bus+pipeline scope]

**Loop steps:** audio_manager (source/router) · dynamic_music_state · sfx_event_router ·
meta_event_state.

**Verified break-points (from inventory):**
- **TERMINAL BREAK:** no `AudioStream` assets exist; grep confirms no `.play()` call or `.stream=`
  assignment in any of the 8 audio scripts — every model sets `volume_db` on a **streamless** player,
  so nothing is audible.
- Captions never reach the player: `pump_captions`/`drain_captions` have zero gameplay callers.
- Ambient zone never reacts: `set_room_role`/`set_threat_level` have zero coordinator callers.
- Spatial audio is dead: every `play_sfx` is single-arg (no position).
- Bus volume push is inert: the `.tres` is a custom Resource (not an `AudioBusLayout`) and no bus
  layout is registered in `project.godot`, so `AudioServer.get_bus_index` always returns -1.
- Voice logs reference missing `res://data/audio/voice/*.ogg` clips.

**Definition of CLOSED (bus+pipeline scope):**
1. A real Godot `AudioBusLayout` is registered in `project.godot` so `get_bus_index` resolves and the
   volume_db pushes are no longer inert.
2. The stream-loading path is **proven** with 1–2 real clips that actually `.play()` through a player
   with an assigned `.stream` (at least one SFX event and one music layer audible).
3. Captions are **pumped** to the HUD in real play (`pump_captions`/`drain_captions` called from the
   gameplay refresh, both branches).
4. *(Explicitly out of scope: full SFX/music/voice library, spatial emitter population, ambient-zone
   reactivity — documented as deferred deferrals, not break-points.)*

**Away-branch checklist:** audio refresh already ticks on both branches (4806 away / 4904 home);
caption pump must be added to **both**.

**Validation:** `audio_pipeline_smoke.gd` — assert bus index resolves; assert at least one stream
plays (stream assigned + playing); assert a caption reaches the HUD queue; `away_ticks=` asserting
caption pump on a derelict. Register markers.

**Inventory delta:** `audio_reactive.closes → "closed"`; flip `audio_manager.output.live` (real bus +
stream) and the caption path; **retain** documented deferrals for the asset library so the map shows
audio closed-but-thin honestly.

---

### Domain 10: UI/UX Polish  [loops: `tooltip` 🔴, `map_reveal` 🟡]

**Verified break-points (from inventory):**
- `tooltip`: `set_tooltip_query` has **no live gameplay caller** (only two smokes) → tooltip never
  appears in real play.
- `map_reveal`: reveal only fires on `objective_completed` (3364) / critical-room track (4033) /
  `ui_open_map` tracked-room reveal (7036); **no per-step proximity discovery** wired.

**Definition of CLOSED:**
1. `set_tooltip_query` is **called** from real hover/focus interaction (interactables, inventory,
   HUD) so tooltips appear in play.
2. Map fog reveals on **player proximity** as they move through the derelict (per-step discovery), not
   only on objective completion.

**Away-branch checklist:** tooltip queries + proximity reveal both live on the away branch (the
derelict is where exploration happens).

**Validation:** `ui_polish_smoke.gd` — assert a hover query surfaces a tooltip; assert moving near an
undiscovered room reveals it on the minimap; `away_ticks=` on a derelict. Register markers.

**Inventory delta:** `tooltip.closes → "closed"` and `map_reveal.closes → "closed"`; flip
`tooltip_presenter.input.live` and `map_fog_state.input.live`; update break-points.

---

## Already-closed loops (no work; re-verify on touch)

`survival_sanity`, `fire`, `crafting`, `loot`, `ui_shell`, `hud_feedback`, `settings_accessibility`.
The `survival_sanity` caveat ("terminal vitals drain has no death consumer") **auto-resolves** when
Domain 1 lands; re-confirm its break-point note then.

## Execution model

- This spec is the **master roadmap**. The immediate next artifact is the **Domain 1 (Survival &
  Stakes) implementation plan** via `writing-plans`.
- Domains 2–10 stay indexed here; each gets its own brainstorm→spec→plan when reached, executed **one
  green loop at a time**.
- After each domain: regenerate the inventory, confirm the loop flipped green, run the regression
  bundle, commit (`feat:`/`fix:` per loop), and update this roadmap's status table.

## Risks

- **Coordinator churn.** `playable_generated_ship.gd` (~5500 lines) is the hub; cited line numbers
  drift. Mitigated by the inventory `--check` smoke and by citing `function:symbol` alongside line.
- **Away-branch regressions.** The single most common failure mode (3 shipped). Mitigated by the
  mandatory `away_ticks=` assertion in every domain's smoke.
- **Domain-by-domain dependency leakage.** Closing a later domain may reveal a missing earlier
  prerequisite. Mitigated by Domain 1 first and the advisory dependency column; if a domain is
  blocked, surface it rather than building on a dead prerequisite.
- **Audio "closed-but-thin."** Bus+pipeline scope means audio is mechanically closed yet mostly
  silent until the deferred asset pass. Documented honestly via retained deferrals so the map does not
  imply finished audio.

## Definition of done (whole roadmap)

All 18 loops read `"closes": "closed"` in `system_inventory.json`; `--check` and the full regression
bundle pass; `system_map.html` shows zero 🔴 loops; the audio asset library is the only documented,
deliberate deferral.
