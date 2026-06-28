# System Completion Audit — "Does the simulation close its loops?"

Date: 2026-06-26
Status: **Living document. Second pass** (survival, food, combat, loot, ship-systems,
progression traced to coordinator lines; audio/UI/save-load partial). Created to re-grade every system against
*functional / simulation-integrity* criteria rather than the unit-test "Validated"
scorecard in `09_system_roadmap.md` and `SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`.

## Why this document exists

The existing systems map marks all 14 lanes **Validated**. That is true by its own
definition — every system has a passing model/smoke — but "Validated" here means
*unit-tested in isolation*, **not** *complete* and **not** *part of a functioning
simulation*. PRs #34–#36 already proved the gap: 30 of 102 scripts were "Validated"
yet unreachable from the live game. Wiring closed that *reachability* gap
(94 reachable / 8 infra-only — see `integration_debt.md`).

But **reachable + driven ≠ functional.** A system can be mounted in the live scene and
have `tick()` called every frame and still be **hollow**: its inputs are always zero
(no live *source* feeds it) or its outputs go nowhere (no live *sink* consumes it).
For a Project-Zomboid-in-space deep sim, that hollowness — not UI polish — is the real
pre-alpha gap. This audit grades each system on whether the simulation actually closes
its cause-and-effect loops.

## The rubric

| Grade | Question it answers | Current reality |
| --- | --- | --- |
| **1. Model** | Pure logic + smoke exists? | ≈ all 112 system scripts — **done** |
| **2. Reachable** | Mounted in the live run? | 94 / 8 (see `integration_debt.md`) — **done** |
| **3. Driven** | `tick()`/mutators called in the loop? | All reachable are driven — **done** |
| **4. Coupled** | Live **input** (a source feeds it) AND live **output** (a sink consumes it)? | **THE GAP — graded below** |
| **5. Content/balance** | Enough authored data to be more than a tech demo? | Partially — graded below |

### Coupling grades (column 4)

- 🟢 **Closed-loop** — verified live input *and* live gameplay output.
- 🟡 **Half-coupled** — one side live, the other dead (or HUD-text-only / test-seam-only).
- 🔴 **Hollow** — ticked, but no live source *and* no live gameplay sink (decoration).
- ⚪ **N/A** — infra/release/audit tooling; not a simulation system, correctly uncoupled.

### Confidence

- **[V]** Verified this pass — I traced the exact coupling lines in
  `playable_generated_ship.gd` (the coordinator).
- **[P]** Probable — strong evidence (e.g. only consumer found is `get_status_lines()`)
  but not exhaustively traced.
- **[?]** Not yet traced — graded from the integration matrix / `integration_debt.md`
  driven-audit only; owed a deeper I/O trace.

> **Scope note (traced this pass):** survival, food, combat, loot, ship-systems, and
> progression are traced to exact coordinator lines (~1323–1370, ~3273–3360, ~4163–4251,
> ~2378–2410, ~3890/5535, ~1250–1271, plus consumer greps) and graded **[V]** — including the
> progression spend→effect side (hub upgrades → run setup) and the sanity/fire-suppression
> outputs. Still owed a fresh trace: **audio** (event triggers), **UI** (faithful but reflects
> upstream hollows), and whether **skill-tree node** unlocks add effects beyond hub upgrades —
> flagged **[?]/[P]** below.

---

## Lane-by-lane grades

### M1 · Survival vitals — 🟢 mostly closed-loop (the best-wired lane)

| System | Coupled | Live input → output | Conf |
| --- | --- | --- | --- |
| `vitals_state` | 🟢 | ← temp mult, radiation drain, status mult, `moving` → death + HUD + sanity feed (coord 4213) | [V] |
| `radiation_state` | 🟢 | ← in-radiation zone (away/breach, 4227) → vitals health drain (4209) | [V] |
| `body_temperature_state` | 🟢 | ← extreme zone (away, 4230) → vitals thirst mult (4206) | [V] |
| `status_effects_state` | 🟢 | ← stimulant/addiction/consumables → vitals stamina-recovery mult (4212) | [V] |
| `sanity_state` | 🟡 | ← safe-zone flag (4222) → `vitals_model.apply_sanity_summary` (4417) renders **HUD warnings only** (`_sanity_lines`: a "<40" warning + a `perception_pressure_active` text line); no mechanical consumer traced | [V] |

**Gap (CONFIRMED cosmetic):** sanity has a live *source* (safe-zone) but its *output* is HUD
warning text — low sanity causes no traced damage / hallucination / control effect. A
`perception_pressure_active` flag is published in the summary but nothing mechanical consumes
it within the vitals model. **Give sanity teeth (or accept it as a cosmetic meter).** Content:
vitals tuning exists.

### M2 · Food / cooking / spoilage — 🟡 eat→vitals loop CLOSED; production via crafting; standalone duplicates removed

*Corrected framing (like the procgen lane): production already worked and the real break was
consumption, not production.*

| System | Coupled | Live input → output | Conf |
| --- | --- | --- | --- |
| food eat path (`consumable_state` food/drink) | 🟢 | ← eat a food/drink item → **applies hunger/thirst/sanity to `vitals_state` via `FoodState`** (was a no-op; fixed). Production: the **kitchen crafting station** (ADR-0038, `recipe_definitions.json`) makes `cooked_meal` into inventory. | [V] |
| `hydroponics_state` / `synthesizer_state` | 🔴 | ticked only when already active; no live plant/synth start → `sustenance_state` summary (HUD only). Orphaned passive growers (option 3). | [V] |
| `water_recycler_state` | 🟡 | ticked only when `RECYCLING`; `recycled_water` read by life-support (1340), but life-support output is HUD-only → dead-ends. | [V] |
| `spoilage_state` | 🟡 | ticked unconditionally; per-item spoilage stage not yet threaded into the live eat (eat uses the FRESH baseline). | [P] |

**RESOLVED (eat→vitals) + cleanup:** the survival food loop now closes. The kitchen crafting
station already produced `cooked_meal` into inventory, and **eating it now restores
hunger/thirst/sanity** on the live `vitals_state` — the consumable food/drink branch was a no-op
because food items carry `hunger_restore`/etc. but no `effects` array; it now routes through
`FoodState`. The superseded standalone `cooking_state` (galley `cooking_recipes.json`) duplicate
of the kitchen station was **removed** (`CookingState` retained only as `SynthesizerState`'s
internal machine; its `RunSnapshot` field dropped, `summaries` 27→26). Proven by
`scripts/validation/main_playable_food_consumption_smoke.gd`. **Remaining (out of scope here):**
live start/harvest for hydroponics/synthesizer/water-recycler (a second, *passive* production
source — option 3); per-item spoilage-stage scaling on eat (FoodState supports it; the live stage
isn't threaded yet); the HUD-only `sustenance_state` output (M7).

### M3 · Combat / threat AI / damage — 🟢 closed-loop both directions (designed injection now wired, PR #38)

| System | Coupled | Live input → output | Conf |
| --- | --- | --- | --- |
| `threat_manager` / `threat_ai_state` | 🟢 | ← player signals + `tick_threats(vitals, status, armor, pos)` (3357) → drains player vitals | [V] |
| `detection_state` | 🟢 | ← player move/noise signals (3350) → threat awareness | [V] |
| `damage_pipeline` / `armor_resolver` | 🟢 | ← player `attack_with_weapon(weapon, inventory, equipment)` (3338) → damages threats; the player armor profile mediates incoming threat damage to the player | [V] |

**Threats DO spawn:** `configure_for_layout` falls back to `_fallback_markers_from_layout`
(threat_manager 221) when the layout has no `encounters`, spawning a fixed 5-archetype set
(`biomatter_swarm, puppet_corpse, stalker, mimic, hull_tendril`). So combat has a live source
and sink even with no injected encounters.

**Gap (corrected — RESOLVED by PR #38):** the designed encounter system was *defaulted off*,
not bypassed (a deeper trace by Codex corrected my first-pass framing). Traveled-to derelicts
**are** procgen — `travel_to` → `ShipGenerator` → `ShipLayoutGenerator` already runs the
pipeline; golden layouts are only the *home/start* ship (intentionally a safe hub). But
`ShipGenerator` called the layout generator with **empty biome/difficulty ids**, so the Stage-6
`EncounterInjector` was skipped and `layout.encounters` stayed empty → threats fell back to the
fixed 5. **PR #38 threads a deterministic per-derelict biome+difficulty into that call**, so
live derelicts now spawn injected, biome/difficulty-tuned encounters (`enc_*` threat ids).
Content: 5 archetypes exist; bespoke behaviors/bosses are future.

### M4 · Loot ecosystem — 🟢 closed-loop (source→sink wired)

| System | Coupled | Live input → output | Conf |
| --- | --- | --- | --- |
| `loot_container` (tool) | 🟢 | ← container specs from layout via `get_loot_container_specs_copy()` (`_build_loot_containers` 2378) → `container_searched` → `_on_loot_container_searched` grants into inventory (2792) | [V] |
| `loot_roller` / `loot_distribution` / `rarity_tier` | 🟢 | ← search roll context → rolled items into the grant | [V] |
| `unique_item_state` | 🟡 | unique-find path wired to rolls; **uniqueness-dedup-across-runs not traced** | [P] |

**Gap:** the loot loop closes — layouts define container specs, searching grants real items into
inventory. Remaining: the biome's `loot_quality_modifier` isn't yet applied to rolls. The
per-derelict biome is now resolved (PR #38, same seam as combat), so the hook exists; wiring it
into the loot roll is a fast-follow. Content: loot/unique/junk definitions exist.

### M7 · Ship systems & sustenance infrastructure — 🟡 partial progress (M7-A: life-support closed; hull source partly wired; shields cut)

*Resolved by M7-A: `shield_state` removed; `life_support_expanded_state` closed-loop (hull breach_count → atmosphere drain → vitals health while aboard); `hull_integrity_state` sink-side mechanically 🟢 (BreachSealPoint channel + `hull_sealant` consumption proven by smoke); `hull_sealant` is not yet a defined or obtainable item (no loot/craft/starting-inventory path), so player-facing loop completion is deferred. Live damage source is config-only #4, sources #1–3 deferred.*

| System | Coupled | Live input → output | Conf |
| --- | --- | --- | --- |
| `power_grid_state` | 🟢 | ← `ship_systems_manager.power.health()` + broken systems (1327) → allocation ratios feeding 5 subsystems (shields channel removed) | [V] |
| `propulsion_expanded_state` | 🟢 | ← power + hull penalty + manager (1331) → **gates travel via `can_propel()`** (1716) | [V] |
| `crafting_state` / `station_state` | 🟢 | ← stations power channel (1353) → `_on_craft_completed` (materials/inventory) | [V] |
| `fire_suppression_state` | 🟢 | **Authoritative fire hazard (M7-B / ADR-0041).** ← live ignition as a *symptom of damage*: a damaged mapped ship system + oxygen re-ignites a compartment each tick; plus electrical-arc cascade and deterministic spread to adjacent compartments. → real teeth: drains `vitals_state.health` while the player stands in a burning zone (`fire_health_drain`) AND degrades the burning compartment's ship system via `ship_systems_manager.damage_system()`. Three extinguish paths: manual `FireSuppressionPoint` (consumes `ExtinguisherState` charge, refilled at a powered `ExtinguisherRechargePort`), powered auto-suppression, and breach/vacuum vent. `fire_state` (the old timer hazard) is **deleted**. | [V] |
| ~~`shield_state`~~ | cut | **Removed by M7-A** — model and tuning deleted; orphaned power channel (`power → shield allocation slot`) **cleaned up** (removed from `DEFAULT_SUBSYSTEM_ORDER`, `power_budget_tables.json`, and smoke). 18-unit budget slot reclaimed. | [V] |
| `life_support_expanded_state` | 🟢 | ← power + hull `breach_count` (1342) → `get_health_drain_per_second()` → drains `vitals_state.health` while aboard (coordinator M7-A wiring); drain is zero while away on a derelict. **Closed-loop by M7-A.** | [V] |
| `hull_integrity_state` | 🟡 | **sink** 🟢 breach_count → life-support drain → vitals; sealing mechanism mechanically proven (BreachSealPoint channel + `hull_sealant` consumption); `hull_sealant` is not yet a defined or obtainable item (no loot/craft/starting-inventory path) — player-facing loop completion deferred. **source** 🟡 live damage source is config-only `#4` (initial breach set at load via `hull_compartments.json`); sources `#1–3` (combat / hazard / pressure) deferred. | [V] |
| `sustenance_state` | 🔴 | ← power + hydroponics/synth/water summaries (1364) → **only `get_status_lines()` (4064); does not feed player hunger/thirst** | [P] |

**Gap (remaining after M7-A):** power + propulsion + crafting form a real coupled core.
Life-support is now a real atmospheric-vitals source. Remaining hollow systems:
1. **Hull damage sources #1–3 deferred** — config-injected breach (source #4) is live; player
   can seal via `BreachSealPoint`. But combat hits, hazard cascades, and deep-dive pressure do
   not yet call `damage_compartment()`. The seam exists; it needs live callers.
2. **Fire-suppression — RESOLVED (M7-B / ADR-0041).** Now the authoritative fire
   hazard: live symptom-of-damage ignition, vitals + ship-system teeth, and three
   extinguish paths; `fire_state` deleted. (Was: a HUD shadow of the real hazard.)
3. **Sustenance produces HUD text only** — `sustenance_state` consumes the farm/cook chain
   but its output feeds no player vital. The `water_recycler_state` output feeds life-support,
   but life-support now actually gates vitals, so this chain is closer to live.

**Pattern (partially resolved):** of the original "expanded ship systems" tier, `life_support_expanded`
is now authoritative (drives real vitals). `shield_state` is cut. `hull_integrity` has a real
sink but still needs live damage callers. `fire_suppression` is now authoritative (M7-B /
ADR-0041 — real fire hazard with vitals + system teeth and a full extinguish loop); only
`sustenance` remains HUD-only.

### M5 · Consumables / medicine / stimulants / ammo — 🟢 closed-loop

| System | Coupled | Live input → output | Conf |
| --- | --- | --- | --- |
| `consumable_state` + `effect_dispatcher` | 🟢 | ← `use_item` from input → routes to vitals/sanity/radiation/temp/status via `_consumable_pipeline_context()` (3361) | [V] |
| `medicine_state` / `stimulant_state` / `addiction_state` | 🟢 | ← use actions; stimulant/addiction ticked (4199) → status effects + vitals | [V] |
| `ammo_state` | 🟡 | ← consumable pipeline; **spend-on-fire coupling tied to the player-attack path (see M3) not traced** | [P] |

**Gap:** thin and well-built — this is the pipeline that actually closes the
item→player-effect loop. Content: medicine/stimulant/ammo definitions exist.

### M6 · UI / HUD / accessibility — 🟢 driven (it's the *sink*, by nature)

`menu_state`, `settings_state`, `tutorial_state`, `map_fog_state`, `controller_glyph_state`,
`tooltip_presenter`, hotbar/panels — all driven by `menu_coordinator`. UI is inherently an
*output sink*; "hollow output" doesn't apply. **Gap:** the **inputs feeding the HUD are only
as real as the systems behind them** — e.g. the ship-systems panel faithfully renders the
hollow sustenance numbers from M7. Fixing M7 makes the HUD meaningful. [?]

### M8 / M12 · Procgen expansion & world variety — 🟢 wired (lifeboat PR #36, derelicts PR #38)

`kit_catalog` skins the **lifeboat** (PR #36). **`encounter_injector` / `room_variant_selector`
/ `biome_profile` / `difficulty_profile` — RESOLVED (PR #38).** My first-pass framing here was
wrong (corrected by a deeper trace): traveled-to derelicts are **not** bypassed — `travel_to` →
`ShipGenerator` → `ShipLayoutGenerator` already runs the procgen pipeline; golden layouts are
only the *home* ship. The dormant part was that `ShipGenerator` called the generator with
**empty biome/difficulty ids**, so Stage-6 injection + room-variant selection + biome/difficulty
stamping were all skipped. PR #38 threads a deterministic per-derelict biome+difficulty into that
call, so all four now drive live derelicts (proven by
`main_playable_derelict_encounter_injection_smoke.gd`). `seed_determinism_contract` stays a test
contract, not a runtime system. Remaining known-future: full derelict *structural*-template
variety (layout.json template expansion). (The EncounterInjector density-clamp balance bug is
now fixed — see the rollup.)

### M9 · Audio / music / spatial — 🟡 driven, source-coupling [?]

`audio_manager` ticks `ambient_zone_state`, `sfx_event_router`, `dynamic_music_state`,
`meta_event_state`, `spatial_audio_resolver` every frame (4250). **Gap:** whether SFX/music
*triggers* are fired by real game events (combat, damage, loot) vs. idle ambience — [?],
owed a trace. Content: real audio assets are known-future.

### M10 · Progression / meta / hub — 🟡 input live, output (effect-on-run) [?]

| System | Coupled | Live input → output | Conf |
| --- | --- | --- | --- |
| `training_event_bus` → `player_progression_state` | 🟢 (input) | ← real gameplay events (`emit("repair_full_system", …)` 3890; generic `emit` 1469) → progression XP | [V] |
| `meta_progression_state` | 🟢 (input) | ← run completion `apply_meta_payout(run_summary)` (5535) → meta currency, persisted to disk | [V] |
| `hub_upgrade_state` | 🟢 | bought upgrades apply at run setup: starting-skill bonuses → `player_progression.skills` (1256-1260) + XP multipliers → `_xp_multipliers` (1263-1271) | [V] |
| `skill_tree_state` | 🟡 | reachable + buyable; **whether a skill-tree *node* unlock (distinct from hub upgrades) yields a gameplay effect** not separately traced | [P] |

**Gap (mostly closed):** the meta loop pays off both ways — earn (repair→progression,
run→meta currency, persisted) and **spend→effect** (hub upgrades inject starting skills + XP
multipliers into the next run). Minor remaining: confirm `skill_tree` node unlocks have an
effect beyond the hub-upgrade bonuses. Explorable hub scene is known-future.

### M11 · Save / load / persistence — 🟢 closed-loop (infra, but genuinely functional)

`save_load_service`, `save_slot_state`, `save_index_state`, `autosave_policy` (PR #35),
`save_migration_service`, `permadeath_resolver`, `cloud_manifest_state`. Round-trips the live
`RunSnapshot`; autosave loop wired and ticked (5475). Cloud is local-manifest-only (known-future).

### Infra / release / audit tooling — ⚪ N/A (correctly uncoupled)

`automated_playtest_rubric`, `balance_ledger`, `crash_report_bundle`, `dependency_validator`,
`integration_matrix`, `product_audit_report`, `seed_determinism_contract`, `build_metadata_state`,
`localization_catalog`, `demo_scope_gate`, `release_readiness_ledger`, `junk_yield_resolver`.
These are release/audit/dev tooling — not simulation systems. Correctly not in the gameplay loop.

---

## Functional-gap rollup (prioritized)

The pre-alpha question isn't "what's missing a model" — it's "where does the simulation fail
to close a loop." Ordered by how much each breaks *the game functioning as a whole*.
**Verified hollows (fix or cut):**

1. **✅ RESOLVED (PR #38) — procgen biome/difficulty/encounter injection.** *Corrected framing
   (Codex):* the lane was **not** bypassed — traveled-to derelicts run `ShipGenerator` →
   `ShipLayoutGenerator` (golden is only the *home* ship). It was simply called with **empty
   biome/difficulty ids**, so `EncounterInjector` + `room_variant_selector` + biome/difficulty
   stamping were skipped and combat fell back to the fixed 5. PR #38 threads a deterministic
   per-derelict biome+difficulty into that call → live derelicts now spawn injected,
   biome/difficulty-tuned encounters. **Follow-up (DONE):** `encounter_injector.gd` previously
   clamped combined encounter density to `[0,1]`, neutering biome/difficulty density > 1.0
   (`deep_dive`/`breach_field` could only *lower* the rate). Now floored at 0 with no upper cap
   (per-room probability is still capped at 1.0 downstream), so high-density biomes/difficulties
   actually raise spawn rate (encounter_injector_smoke `deep_markers` 1→2). *(M8/M12)*
2. **🟡 Hull source partly addressed (M7-A).** Source #4 (config-injected breach via
   `hull_compartments.json`) is now live — initial hull damage is set at load time. The
   breach→life-support→vitals drain loop is **closed** (see M7 table). Sealing mechanism is
   mechanically proven (`BreachSealPoint` channel + `hull_sealant` consumption) but `hull_sealant`
   is not yet a defined or obtainable item (no loot/craft/starting-inventory path) — player-facing
   loop completion is deferred. Sources #1–3 (combat hits, hazard cascades, deep-dive
   pressure) remain deferred — `damage_compartment()` seam is future-proof but not wired to live
   events. *(M7, Resolved by M7-A)*
3. **✅ RESOLVED (M7-A + cleanup) — `shield_state` cut and orphaned power slot removed.** Model, tuning, and power-channel allocation all removed. `shields` channel deleted from `DEFAULT_SUBSYSTEM_ORDER`, `power_budget_tables.json`, and the power-grid smoke; 18-unit budget slot reclaimed. *(M7)*
4. **✅ RESOLVED — food eat→vitals loop closed (+ dead duplicate removed).** *Corrected framing:*
   production already worked (the kitchen crafting station makes `cooked_meal`); the real break was
   that **eating food was a no-op** (food items have `hunger_restore` but no `effects` array, so the
   consumable pipeline dispatched nothing). Now the food/drink branch applies restores to vitals via
   `FoodState`. The superseded standalone `cooking_state` (galley) duplicate was deleted. **Follow-up
   (option 3, not done):** live start/harvest for hydroponics/synthesizer/water-recycler as a passive
   production source; per-item spoilage-stage scaling on eat. *(M2)*
5. **🟢 Fire-suppression — RESOLVED (M7-B / ADR-0041); 🔴 sustenance still HUD-only.**
   Fire-suppression is now the **authoritative** fire hazard (it *replaced* the old
   `fire_state` timer hazard, which is deleted): ignition is a live symptom of unrepaired
   system damage (+ arc cascade + spread), it has real teeth (player vitals drain + ship-
   system degradation), and a full player loop (manual extinguisher with charge/recharge
   port, powered auto-suppression, breach vent). **Deferred follow-ups:** B2 deliberate-vent
   control, fire-consumes-oxygen, `fire_extinguisher`/`hull_sealant` acquisition paths,
   derelict-side fire points/recharge ports, and door-gated spread. **Sustenance** remains a
   HUD shadow — it consumes the farm/cook chain but feeds no player vital. (**Life-support is
   no longer in this list — RESOLVED by M7-A.**) *(M7)*
6. **🔴 Sanity is cosmetic** — live source (safe-zone) but output is HUD warning text only; no
   damage / hallucination / control effect consumes low sanity. Give it teeth or accept it as a
   meter. *(M1)*

**Unverified couplings the next pass must trace:**

7. **🟡 Do `skill_tree` node unlocks have a gameplay effect** beyond the (verified) hub-upgrade
   bonuses? *(M10)*
8. **🟡 Audio triggers** — are SFX/music fired by real events (combat/damage/loot) or idle? *(M9)*

**Resolved this pass (were unknowns, now confirmed live):** combat both directions (threats
spawn via fallback + `attack_with_weapon`), loot source→inventory, progression **both** sides
(earn *and* hub-upgrade spend→effect at run setup).

**Resolved after this audit:** procgen biome/difficulty/encounter injection for live derelicts
(PR #38 — see rollup item 1; the audit's original "lane bypassed" framing was corrected to
"extended generator options defaulted off", then wired).

## How to extend this audit (next pass)

1. Trace outputs for every **[?]** / **[P]** row by grepping the coordinator + sub-coordinators
   (`audio_manager`, `threat_manager`, `menu_coordinator`) for each system's getter consumers.
2. Promote each verified loop to 🟢 with the exact coordinator line; demote confirmed hollows
   to 🔴 with the missing-source/sink named.
3. Cross-check against `data/integration/cross_system_integration_matrix.json` `dependencies`
   — every declared dependency should map to a 🟢 here, or be flagged as intended-but-unwired.
4. Feed the rollup into the build-order decision (vertical-slice vs. horizontal) the roadmap
   pivot is waiting on.
