# The Synaptic Sea — Project Status (source of truth)

**Last updated:** 2026-07-23

This file is the entry point for "what is actually built and what's left." It exists
because the older roadmap docs were inaccurate and have been quarantined (see below).

## What this project actually is

A locked-isometric 3D space-horror **deep survival sim** (Godot 4.6.2, GDScript) — a
"Project Zomboid in space." It is **pre-alpha with all 18 simulation loops closed**
(completion roadmap finished 2026-07-03, PRs #50–#60); remaining work is content,
polish, and the documented deferrals below. It is **not** a shipped release, despite
what the archived "Gate 5 RC" docs claim.

- **Project root (this machine):** `C:/Users/dasbl/Documents/The Synaptic Sea`
- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- **This is a git repo** (branch `main`). Ignore any doc that says otherwise.

## Canonical status docs (trust these)

| Doc | What it tells you |
| --- | --- |
| **`docs/game/inventory/SYSTEM_INVENTORY.md`** + **`docs/game/inventory/system_map.html`** | **Canonical status doc.** Code-verified inventory of every runtime system/subsystem — model/reachable/driven/coupling grades with a derived completion %, plus a loop-closure + integration matrix. Generated from `system_inventory.json` by `tools/build_system_inventory.py`; the `--check` smoke fails if data/docs drift. Open `system_map.html` for the interactive card-grid + matrix view. |
| `docs/game/system_completion_audit.md` | **Superseded — see inventory.** The earlier narrative loop-closure pass; kept for history but no longer the canonical grade source. |
| `docs/game/integration_debt.md` | Reachability ledger — which scripts are actually mounted in the live run. |
| `docs/game/06_validation_plan.md` | The live validation/smoke contract (PASS markers, regression bundle). |
| `docs/game/adr/` | Architecture decisions (current through ADR-0045; see `adr/README.md` index). |
| `docs/superpowers/specs/` + `plans/` | Real dated design docs (the M7-A/M7-B-era work). |

## Real milestone scheme

The trustworthy work uses an **M-lane + sub-project** scheme (e.g. **M7 = Ship systems &
sustenance infrastructure**, sub-projects A = life-support→vitals, B = fire suppression).
This is the scheme in the dated specs and git PRs #41–#46 — **not** the "Gate 0–5" or
"M1–M11 Persistence" numbering in the archived docs.

## What's left (completion roadmap finished 2026-07-03)

> Source of truth for grades and completion %: **`docs/game/inventory/SYSTEM_INVENTORY.md`** (+ `system_map.html`). The rollup below is a human-readable summary; the inventory is authoritative.

**The completion roadmap (`docs/superpowers/specs/2026-06-28-completion-roadmap-design.md`)
is done.** Domains 1–10 landed as PRs #50–#60 (2026-06-29 → 2026-07-03); all 18 loops read
`closed` in the inventory (`--check` 191/191; regression bundle `commands=207 clean_output=true`
after the 2026-07-06 audit-remediation tranches — PRs #61–#64 fixed the audit's criticals plus
the away-branch and save/load clusters, Tranche 3 (PR #65) promoted 25 smokes and classified
every remaining orphan, Tranche 4 (PR #66) closed the UI-wiring cluster (audio-log panel,
difficulty label, panel menu-modal guard, voice clip_path wiring), Tranche 5 closed the
procgen/data-coherence cluster (schema 1.2.0 everywhere + drift gate, archetype constraint
enforcement, template.connections + stacked_v2 elevator, authoritative encounter tables
ADR-0047, loader fire-zone getters wired, seed_000017 pipeline-regenerated, 32 procgen smokes
promoted), and Tranche 6 wired DemoScopeGate into production at all 5 demo-manifest
enforcement points, made the unlock pipeline fire from production events (scavenge XP +
catalog retargets), replaced the phantom reachability method + false certifications in
integration_debt.md, and recomputed 732 stale inventory pins via git archaeology; see
`docs/game/audits/2026-07-06-e2e-foundation-audit.md` for dispositions).
The 2026-06-28 "open functional gaps" list that used to live here was closed by that arc
(git history has the old text).

Session 8 (2026-07-07) completed the remaining 19 `UNVERIFIED LOW/OVERFLOW` audit rows in
`docs/game/audits/2026-07-06-e2e-foundation-audit.md`: final outcomes are 15 fixed items
(including the deleted superseded `settings_schema.json` duplicate), 2 refuted-by-design
rows (`cloud_manifest_state`, `build_metadata_state`), and 2 content-pending rows
(`status_effect_icons.json`, `threat_drone_swarm.json`). The regression bundle remains
`SYNAPTIC_SEA REGRESSION PASS commands=207 clean_output=true`. Session 8 intentionally did
not recompute the 732 inventory file:line pins; small coordinator line shifts are expected,
with the documented git-archaeology recovery flow remaining the canonical refresh method
when those pins need to move.

**Stream A reachability (2026-07-21):** closed four player-facing holes that had
models/controls but no live play path — hangar bay interact, home loot containers,
organic salvage cart spawn, and achievement catalog emitters beyond `tool_acquired`.
Proven by `main_playable_reachability_smoke.gd` (bundle command count 208). See
`docs/game/integration_debt.md` § Stream A.

**Stream B survival + corpse loot + encumbrance teeth (2026-07-21):**
- Personal O2 ticks on the away branch via `field_atmosphere` (suit pressure on
  derelicts; hub life-support atmosphere bite remains home-only). Proven by
  `main_playable_survival_away_smoke` `o2_drain=true` + `oxygen_state_smoke`.
- Unsearched combat corpses persist on `ShipInstance.pending_corpse_loot` and
  re-spawn on leave/revisit/save (`combat_closure_smoke` `pending_corpse=true`).
- Overload health drain: `Encumbrance.health_drain_per_second` feeds vitals
  attrition (PZ tier breakpoints; move mult unchanged).

**Documented deferrals (deliberate, ADR-tracked — not broken / not gap work):**
- **Audio asset library** (ADR-0044) — bus + pipeline live with placeholders; full SFX/
  music/voice *asset content pass* remains a polish track (pipeline wiring complete).
- **Web-chart visual polish** (ADR-0045) — text rows + session knowledge work; graphical
  chart pass is polish, not reachability.
- ~~**AI pathfinding**~~ — **CLOSED ADR-0049:** pure `ShipNavGraph` + A* pathfollow (no wall-lerp); regression +4 smokes.
- **Cloud saves / Steamworks** — stub manifest only (ADR-0032).
- **Bespoke enemy/boss content, explorable hub scene, final art** — content tracks.

**~~Fire B2~~ CLOSED Stream F (2026-07-21):** deliberate vent (no extinguisher → vacuum
vent with decompression/hull breach teeth), fire-consumes-oxygen (`fire_oxygen_drain` on
`OxygenState.tick`), door-gated spread (sealed hatches close bulkhead links). Proven in
`unlock_trigger_stream_f_smoke` + existing fire smokes.

**Streams C–F gap closure (2026-07-21):**
- **C:** F6 quicksave, ambient zones, dead_fleet encounter table, status icons.
- **D:** scan / medicine / cook / fabricate / repair_sub / weld / travel training emits.
- **E:** ration / diagnose / discover / extract / compound_stim + junk salvage live.
- **F:** surgery (medbay), decode_signal (voice log), build_shelter (hatch/seal),
  social suite (inspire/negotiate/intimidate/transmit), Fire B2. Bundle **commands=215**.

**Unlock catalog:** every `unlock_tables.json` trigger_event now has a production
emission path. `defeat_enemy` stays intentionally unused (kill path uses `threat_killed`
to avoid double-grant; retargetable data).

**Procgen validation & coherence (2026-07-21):** quality gate (16 seeds × biome/diff,
schema/connectivity/nav/encounters/determinism), golden parity + live derelict pipeline
contract smokes; archetype role aliases; connectivity retry; default derelict archetype
on travel; extended templates when difficulty set; biome-biased room variants; encounter
table role coverage; `hazard_source=runtime` (ADR-0050). Bundle **commands=222**.

With integration gaps closed, remaining work is content/polish (audio assets, art,
cloud, hub scene, deeper kit art) — not reachability.

## Pre-polish program (started 2026-07-22; mechanical packages through #434)

Source plan: system-by-system path to content-capable state (module integrity, not voxels).
Parallel decomposition: `docs/game/build-plans/pre-polish-parallel-wave-plan.md`.
Definition of pre-polish: systems content-capable (not voxels; ADR-0051). Remaining work is authoring/polish, not core engineering.

**Landed (PRs #78–#434, 2026-07-22 → 2026-07-23):**
- **A0 / SPEC / A2 / A4:** ADR-0051, pillar feature specs, `SimKeys`, `TuningCatalog`
- **A1a–c / A3:** `ShipRuntime` advance/catch-up/snapshots; shared present-ship tick helpers; FRAME/SLOW/LAZY bands
- **B2.1–B2.5:** Module integrity + scene consequences; WorkAction catalog/state/resolve/driver; component slots + mount/dismount; craft quality/knowledge; repair unification
- **B5.1 / C5.3 / C3–C4:** Dressing consumption; encounter pacing; wounds + vitals curves; food closure; sanity manifestation pool; spatial perception + threat LOS raycast; archetype behavior modifiers
- **D2.6 / D5.4 / D6.1–3:** Ship modification pure model + **D9b panel**; templates/wreck mutator; pillar revisit persistence on `ShipInstance`; SeaGraph; hub explorable verify
- **D7–D10:** Skill effect consumers; pillar persistence + historical fuzz; UI consumers (WorkAction HUD, wounds, chart routes, ship-mod panel); audio event coverage
- **Integration seams:** WorkAction/wounds/ship-mod/sea_graph wired on playable; integrity leave/revisit flush; dual-branch work tick + threat LOS

**Regression contract:** `docs/game/06_validation_plan.md` bundle ends with
`SYNAPTIC_SEA REGRESSION PASS commands=444 clean_output=true` (marker-based; set `GODOT`/`ROOT` on Windows).

**Post-INT hardening (PRs #112–#434):**
- D6.1 pillar revisit sparse packs on ShipInstance + leave/revisit flush
- D9b ship-mod panel; dual-branch WorkAction tick + training XP on complete
- Nearest-module WorkAction interact (cut/pry); component dismount/remount interact
- ComponentPlacementState populate/restore; scene placeholder markers
- REQ-CMP-002 system links + dismount damages linked subcomponents; remount restores operational floor
- REQ-MI-004 ModuleDamageRouter (fire/decomp/threat/tool); ship-mod/wounds keys (U/O)
- Combat hits interrupt WorkActions; hull_tendril structure_damage on modules
- Work yields → inventory + cart-overload floor drops; progress strip noise; ship-mod inv sync
- Synthetic wall slots; hub components populated
- Ship-mod + pillar fields on RunSnapshot; hold-to-work interact; bandage/treat first_aid XP
- Ship-mod panel Enter install_from_inventory / uninstall; catalog `power_draw` + install restores linked hub subs
- Ship-mod installs with `station_tier_bonus` raise hub station tiers (fabricator etc.)
- Hull plating resist on hub structure damage; work stamina drain + speed mult; mount/dismount refreshes tiers
- Weld/patch damaged modules when lance + plate; plate form aliases for consume
- Ship-mod snapshot restore re-applies linked system floor + station tiers
- Hub plating also reduces fire→module damage rate
- Exhausted stamina interrupts active WorkActions; blocks new WorkAction starts
- Work interact skill context: weld/patch/splice use repair progression skill
- Ship-mod install/uninstall emit construction training XP + UI SFX (open/install/uninstall)
- Catalog `hull_plating` for plating_plate installs (bonus + zero power draw)
- Live ship-mod power budget rejection; over-budget kills hub station power
- WorkAction xp_event ids aligned to training_actions (salvage/weld_panel/repair/cooking)
- Live cut_wall / weld_patch complete emit salvage / weld_panel training XP
- UI SFX: work progress pulse, wounds open, treat wound, craft complete, repair complete
- WorkAction complete emits verb SFX via SfxEventRouter (live cut path)
- Salvage station completion emits scavenge_container training XP
- Hydroponics harvest emits cook_meal XP + harvest SFX
- Medbay surgery plays treat SFX + perform_surgery XP
- Voice log play emits decode_signal XP (+ VOICE_LOG_PLAY feedback)
- Repair start emits diagnose_fault XP + tool-use SFX
- Social suite training events catalog smoke (inspire/negotiate/intimidate/transmit)
- Stream D/E training catalog smoke (discover/extract/plot/ration/scan)
- Consumable use training smoke (first_aid_self / ration_supplies)
- Scanner panel open emits scan_derelict training XP
- Travel hop training events (plot_course + complete_astrogation) catalog smoke
- Threat kill emits threat_killed + melee intimidate_threat XP
- discover_room / extract_data training emit smoke
- Ship-mod plating install patches a damaged hub module (REQ-SMOD-001 hull work)
- build_shelter training emit smoke (hatch seal / weld construction)
- Fire extinguish emits decontaminate_zone training XP
- Breach seal emits weld_panel + build_shelter XP
- Full training_actions catalog coverage smoke (all event_ids emit)
- repair_subcomponent complete-path training emit smoke
- Cart-overload floor WorkYieldDrop routes SFX_DROP_ITEM
- Sealed hatch bypass routes SFX_DOOR_OPEN
- Combat damage routes SFX_COMBAT_HIT; engagement rising-edge SFX_COMBAT_THREAT_ALERT
- Live pry_panel salvage XP smoke; floor-yield scoop routes SFX_TOOL_PICKUP
- Web chart open refreshes extraction route + UI_CHART_ROUTE SFX
- Live mount/dismount salvage+repair XP; sanity phantom/HUD/ambient SFX channels
- META_HULL_GROAN on hull breach / emergency vent / derelict breach seed
- META_BIOMATTER_PULSE on web growth; META_REACTOR_HUM on reactor stabilize
- Dock-land SFX validation seam; live splice_conduit repair XP smoke
- Live patch_breach repair training XP smoke
- Scheduled MetaEventState events route META_* catalog ids via SfxEventRouter
- Live suppress_fire repair training XP smoke
- Live plant_crop cooking training XP smoke
- Live harvest_crop cooking training XP smoke
- Weld/pry work completion SFX multi-verb smoke
- Patch/splice work completion SFX smoke
- Plant/harvest work completion SFX smoke
- Mount/dismount complete stamps verb SFX (unbolt/mount) on live path
- Live suppress_fire work completion SFX smoke
- Live remount component SFX_WORK_MOUNT smoke
- REQ-AU-001 callsite smoke: drop/door/dock promoted from skip to live
- Loot container search routes SFX_TOOL_USE
- UI_PANEL_CLOSE on wounds/ship-mod/chart/scanner dismiss
- Equip SFX_TOOL_PICKUP / unequip SFX_DROP_ITEM
- UI_PANEL_OPEN when recipe picker opens
- Scanner panel open routes UI_PANEL_OPEN
- Cart grab routes SFX_TOOL_PICKUP
- Cargo/cart transfer panel open routes UI_PANEL_OPEN
- Panel close SFX smoke covers recipe picker dismiss
- Codex/pause menu open routes UI_PANEL_OPEN
- Pause menu open SFX smoke
- Pause menu close routes UI_PANEL_CLOSE
- Menu confirm resume/start emit panel open/close SFX
- Settings menu open SFX smoke
- Records menu open SFX smoke
- Settings menu back UI_PANEL_CLOSE smoke
- Records menu back UI_PANEL_CLOSE smoke
- Weapon reload start routes SFX_TOOL_USE
- Player attack routes SFX_COMBAT_HIT
- Dry-fire empty magazine routes SFX_TOOL_USE
- Achievement unlock plays UI_OBJECTIVE_ADVANCE SFX
- Tool pickup acquired routes SFX_TOOL_PICKUP
- Craft blocked feedback routes UI_PANEL_CLOSE
- Production station start routes SFX_TOOL_USE
- Live footstep SFX while player is moving (REQ-AU-001 footstep promoted from skip)
- Hatch re-seal restores bulkhead + routes SFX_DOOR_CLOSE (door_close promoted from skip)
- Production blocked routes UI_PANEL_CLOSE deny cue
- end_run death routes UI_VITALS_LOW; completion routes UI_OBJECTIVE_ADVANCE
- Station + field craft start routes SFX_TOOL_USE
- Inventory transfer complete routes SFX_TOOL_PICKUP
- Repair / extinguish / seal blocked routes UI_PANEL_CLOSE
- Hangar bay dock/launch routes SFX_DOCK_LAND / SFX_DOOR_OPEN
- First-time room discovery routes UI_OBJECTIVE_ADVANCE
- Cargo hold deposit/withdraw + cart load/unload route drop/pickup SFX when items move
- UI_LOAD smoke via save-then-load live path
- inspire_crew objective training routes UI_OBJECTIVE_ADVANCE
- Junction calibrator apply routes SFX_TOOL_USE
- REQ-AU-001 callsite promotes UI_LOAD to live (load=true)
- Medbay surgery emits first_aid_ally training XP (patient-care stand-in)
- download_logs extract_data routes SFX_TOOL_USE
- Field craft blocked paths route deny SFX via _on_craft_blocked
- Work interrupt cancel routes UI_PANEL_CLOSE; travel_home routes SFX_DOCK_LAND
- Travel denied soft deny SFX (UI_PANEL_CLOSE)
- Dock barrier open + bridge login/deny SFX; stamina interrupt shares cancel cue
- Field craft begin failure paths route deny SFX
- Heavy Load rising-edge encumbrance SFX (UI_VITALS_LOW)
- Ship-mod install/uninstall fail routes deny SFX
- Work start SFX + zero-stamina block deny cue
- Quicksave cooldown refuse routes deny SFX
- Rotating autosave routes UI_SAVE
- World save refuse routes deny SFX
- Tutorial trigger/dismiss + codex unlock SFX
- Chart open without web_chart routes deny SFX
- Scanner confirm with no target routes deny SFX
- Recipe picker + wounds treat deny SFX
- Empty inventory transfer selection routes deny SFX
- Manual equip fail routes deny SFX
- Empty-slot unequip routes deny SFX
- Reload refuse routes deny SFX
- Empty interact miss SFX on both process branches
- Craft-from-picker failure paths route deny SFX
- Load refuse (no compatible save) routes deny SFX
- Cart grab fail / double-grab routes deny SFX
- Hangar dock/launch refuse routes deny SFX
- Medbay surgery refuse routes deny SFX
- Work-yield floor scoop: max_stack deny leaves pile; partial residual stays tracked
- Save/load slot rows show location + play time + world seed (ADR-0046 UI)
- Work-yield stack-full scoop deny routes SFX and keeps residual pile
- Empty loot grants route deny SFX (not success tool-use)
- Already-owned tool pickup routes deny SFX
- Save slot rows also show class + objective sequence
- Empty cargo/cart/panel bulk transfers route deny SFX
- Inventory transfer_quantity empty moves route deny SFX
- Locked hatch bypass without flag routes deny SFX
- Near wall without cut/pry tools routes deny SFX
- Dock barrier mid-channel interact consumes without fall-through
- Repair/breach/fire mid-channel interact consumes
- Craft busy / hydro in-progress consume interact
- Water recycler in-progress interact consumes
- Production harvest output-full consumes interact
- Recycler no-input/power fail consume interact
- Plant crop soft-fails emit production_blocked (success API returns false)
- fix: try_plant_crop soft-fail return API (#406)
- fix: production_station_smoke CS-018 + consume semantics (#408)
- Melee reload attempt routes deny SFX
- Attack soft-fails route deny SFX
- Hazard soft-blocks consume interact; feedback smoke Fire B2 vent
- Repair validation seam false on soft-block (channeling gate)
- Fire suppression smoke soft-block consume (#418)
- Work tool missing soft-deny on away branch
- Unknown production station kind consumes interact
- Inventory key toggles self-inventory closed
- Chart key toggles web chart panel closed
- Ship-mod panel key toggles closed
- Wounds key toggles panel; validation open stays open
- Inventory toggle works with away_from_start
- Chart toggle works with away_from_start
- Regression marker contract commands=444 in 06_validation_plan.md

**Still content/polish (not mechanical pre-polish blockers):**
- Final damaged/breached kit art; audio *asset* library; narrative/balance authoring
- Full coordinator line-count strangler toward &lt;3k (ShipRuntime extract is in; file remains large)
- Cloud saves / Steamworks (ADR-0032)

**Next:** content/polish tracks + optional full-bundle CI run; inventory `--check` remains green (`systems=191`).

## Quarantined / do-not-trust docs

Moved to **`docs/archive/`** (see `docs/archive/README.md`). They invented a Gate 0–5
pipeline, a shipped RC, macOS-only paths, "not a git repo," and "all-validated" claims:
`08_milestone_gates.md`, `09_system_roadmap.md`, `PLANNING_SYNTHESIS.md`, `build-plan.md`,
`PROJECT_WORKSPACE.md`.
