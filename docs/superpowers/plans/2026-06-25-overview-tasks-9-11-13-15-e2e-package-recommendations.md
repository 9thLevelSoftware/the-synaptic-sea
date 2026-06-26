# Synaptic Sea — Production-Grade Additions for Tasks 9–11, 13–15 (Overview → Standalone E2E Packages)

**Generated:** 2026-06-25
**Source review:** `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md` §3.2 / §4.2 / §4.3 / §4.7 / §4.11 / §C; `docs/PLANNING_SYNTHESIS.md` §5 / §6 / §11; `docs/game/09_system_roadmap.md`; `docs/game/05_requirements.md`; reference plans `2026-06-19-current-run-save-load.md`, `2026-06-24-phase7-player-vitals-hud.md`, `2026-06-23-phase5d-hangar-nesting.md`; existing scripts in `scripts/ui/`, `scripts/systems/`.
**Goal:** turn each overview task into a Goal / Architecture / Tech Stack / Global Constraints / File Structure / Contract / Tasks (RED→GREEN) / Bundle / Risks / Acceptance package — matching the format of the existing plan family — instead of the current spec-only bullets.
**Scope of this document:** concise bullet recommendations only; no file edits; no plan authoring. The agent picks this up and writes the actual plans.

---

## Cross-cutting recommendations (apply to all 6 packages)

- **Pattern anchor.** Each package mirrors `2026-06-24-phase7-player-vitals-hud.md`: Goal / Architecture / Tech Stack / Global Constraints → ASCII/HUD-style contract hard-pinned (e.g. exact bus names, exact save JSON shape, exact smoke PASS marker strings) → File Structure (Create / Modify / Stub / `*.uid` policy) → TDD Tasks with checkbox steps and a RED→GREEN shape (`extends SceneTree`, `quit(1)` + `push_error`, never `assert`) → Validation bundle registration with explicit `commands=N` bump → ADR link → Risks → Acceptance.
- **HARD gate:** every package must produce at least one pure-model smoke + one main-scene smoke + (where applicable) one save/load round-trip smoke — registered in `06_validation_plan.md` before claiming Done. REQ-004/005 already lock this; the plans must enumerate the smoke files in the File Structure table, not defer them to "as needed".
- **ASCII-only constraint** must be restated for every UI/Audio/HUD-touching plan (existing rule from vitals HUD plan). Audio packages must fix exact bus names; UI packages must fix exact status-line strings; save packages must fix the on-disk JSON schema in a code block.
- **Predecessor gate.** Every plan must list the predecessor review-card IDs (e.g. `t_c98c338d`) on its title page, in the same style `2026-06-19-current-run-save-load.md` uses — this is what stops "stubs pretending to be implementations".
- **No `git commit`** assumption — every plan documents the no-git ledger path (`/tmp/synapse_sea_<feature>_no_git_changes.log`) since `AGENTS.md` flags the workspace as `GIT_INSIDE=false` and the roadmap's own §C confirms it.
- **Bundle bump + smoke registration is a task step, not an afterthought.** Every plan needs an explicit Task "Register smokes in `06_validation_plan.md` and bump `commands=`" with the exact diff shown — the existing vitals-HUD plan's Task 3 split is the precedent for not gating Task 1 on registration.
- **Each plan produces an ADR** under `docs/game/adr/0XXX-*.md` (the existing numbering rolls past 0028; pick the next free index and note it in the plan). Audio/Multi-slot/Distribution will each need their own because they cross the existing system map.
- **Assets boundary.** All six packages are explicitly non-art — per the systems map §1 ("excludes game assets"). The plans must explicitly call out the audio assets the Audio package will eventually need (a placeholder `data/audio/manifest.json` referenced, not generated) and the distribution assets the Distribution package requires (capsule art placeholder list), so reviewers don't ask "where's the music?" mid-implementation.

---

## Task 9 — UI/UX (Section 4.2, items U-01…U-16)

### Recommended additions
- **Sub-decompose into 3 plan packages** so each is end-to-end on its own rather than a 16-item sprawl: **9a — Menu stack** (U-01/02/03: main/pause/settings), **9b — In-game HUD** (U-04/05/06/07 + crosshair, hotbar, threat indicator, damage direction), **9c — World/Codex/Onboarding** (U-08/09/10/11/12/13 + minimap, map, codex, ship-status, tooltip, tutorial). One mega-plan will collapse back into the spec-only shape the user is calling out.
- **Adopt the vitals-HUD constraint style:** ASCII-only label strings, no Unicode dashes/ellipsis; `extends SceneTree` smokes; `quit(1) + push_error` failure shape; preload-not-class_name construction; allowlist the two baseline Godot teardown lines.
- **Add an interaction/inventory-context seam ADR** before 9b/9c: the existing single-verb `Interactable` (`scripts/interaction/`) needs an extension point (U-04 hotbar, U-05 context crosshair, U-06 threat indicator all read it). Add as Task 0 of 9b — an `InteractableContextProvider` interface plus a smoke. Otherwise the hotbar will be a one-off special case in `inventory_panel.gd`.
- **Settings menu (U-03) MUST wire every existing `AccessibilitySettings` field, every audio bus, every input action.** List each field-by-field as acceptance criteria (mirroring REQ-012's "all keys restored" acceptance). Plan must include a "settings round-trip" smoke (`SETTINGS ROUND-TRIP PASS ...`) that loads defaults → mutates each field → asserts `apply_summary`-equivalent returns identical.
- **Minimap (U-08)** must derive from existing `procgen layout` data — call out the exact `RoomGraph` / `CellLayoutEngine` JSON shape it reads and assert in the smoke. Threat that this becomes a screenshot of the camera frame; add acceptance: "minimap is NOT a viewport mirror; it is a graph projection".
- **Map screen (U-09)** must hook into existing `Synapse SeaWorld` + `TravelController`; declare the seam explicitly so it doesn't fork a parallel world model. Include a smoke that asserts the map screen refuses to render without scanner detail ≥ 3 (current scanner `detail_level` cap).
- **Codex (U-10)** must declare the discovery event bus first. Existing codebase has no event bus by design (per `docs/superpowers/specs/architecture-map.md` "No global event bus — direct signal wiring from coordinator"). Plan must either (a) introduce a per-coordinator signal set + a smoke asserting it, or (b) extend an existing owner (item_defs, scanner, oxygen_state). Pick (b) for first pass to avoid the global bus ADR.
- **Tutorial popups (U-13)** must integrate with the existing `ObjectiveProgressState` "first-encounter" hooks — the sequence-of-4 in the golden ship is the natural teaching spine. Smoke must assert a popup fires on first `apply_objective` per kind and is suppressed thereafter.

### Must-have acceptance
- 3 plans × ≥3 smokes each = ≥9 new smoke files (`scripts/validation/ui_menu_*.gd`, `ui_hud_*.gd`, `ui_world_*.gd`), each with a unique PASS marker line, all registered in `06_validation_plan.md` and the bundle ends `SYNAPSE_SEA REGRESSION PASS commands=<N+9> clean_output=true`.
- One ADR per sub-package (3 new ADRs) under `docs/game/adr/0029..0031`.
- REQ additions: REQ-015 (UI menu stack: load/save integration, no-flicker resume), REQ-016 (HUD scalability under text-scale 1.0–2.0 from existing `AccessibilitySettings`), REQ-017 (map derives from world/procgen, not camera). Add rows to `05_requirements.md` with explicit Verification paths to the new smokes.
- Non-goals: full localization keys, controller glyph swap, gamepad-only navigation. Those are Task 13 (Distribution) and ADR-pending.

---

## Task 10 — Audio (Section 4.3, items A-01…A-08)

### Recommended additions
- **All 8 items land in ONE package** (this is the smallest of the 6 and the only one with a true greenfield directory). Use `scripts/audio/` (does not exist — confirm and create in Task 1), `data/audio/manifest.json` (placeholder only — see assets boundary above), `docs/game/adr/0029-audio-bus-and-mixer.md`.
- **ADR first.** Before any code, write ADR-0029 covering: bus layout (Master → Music/SFX/Voice/UI/Ambient with explicit sub-buses for Music.base, Music.tension, Music.combat), default bus volumes, 3D vs 2D player rules, listener position binding (locked to `IsoCameraRig`), `AudioStreamPlayer3D` attenuation model, occlusion raycast contract, save-serialization shape (bus volumes + SFX/music state), and a hard "no Panner/HRTF in Godot 4.6.2 Forward+" note. The systems map §4.3 lists "spatial, ambient, SFX, music" — the ADR must commit to Godot's `AudioListener3D` + `AudioStreamPlayer3D` baseline and reject the temptation to roll a custom mixer.
- **Bus layout contract is the load-bearing piece.** Plan must specify every bus name as a constant and a smoke (`AUDIO BUS LAYOUT PASS buses=N buses_match=true master_db=-6 ...`) that introspects the project's `AudioServer` and asserts the bus tree. No "trust the .tres file" — verify at runtime so editor drift fails the bundle.
- **Spatial audio (A-02) MUST bind the listener to `IsoCameraRig`** explicitly; add a smoke that asserts the listener position tracks camera position across a programmatic camera move. Listener-rig decoupling is a perennial Godot bug source.
- **Ambient (A-03) MUST use `Area3D` zones** that flip `AudioStreamPlayer` enabled state — derive zones from existing `breach_zones` / `fire_zones` JSON in the procgen loader so the audio layout piggybacks the already-validated gameplay zones. Reuse, do not duplicate.
- **Dynamic music (A-05) MUST hook existing AI state hooks** (per systems map §3.2 Critical Path note). Plan must declare the signal/coordinator call — e.g. `combat_state_changed` on `playable_generated_ship.gd` — and assert in a smoke that `Music.combat` bus gain ramps from 0→1 within N seconds of the trigger without clipping the `Music.base` bus. This is where the systems-map cross-system dependency lives.
- **Audio occlusion (A-06) MUST use a raycast from `AudioStreamPlayer3D` to listener** with a re-cast throttle (every 200 ms is the existing forward+ sweet spot). Define the re-cast cadence in the ADR and add a smoke that asserts occlusion flips when a wall is procedurally inserted between player and emitter mid-frame.
- **Voice/dialog (A-07) + Stingers (A-08) are stub-first.** No TTS engine, no voice acting assets. Plan must ship a `VoiceCueManifest` Resource that names the barks/log files that *will* exist, with a `voice_cue_missing` smoke that logs a known WARNING and the regression bundle's existing `WARNING:` filter rejects nothing new. This prevents A-07 from becoming a "TODO" tail.
- **Save-serialization of audio state** (bus volumes + mute toggles) MUST plug into existing `RunSnapshot` shape — extend `RunSnapshot` with `audio_state` field, bump `slice_version`, add migration code (existing `RunSnapshot.from_dict` rejects mismatched versions; add an upgrader for the new key). Smoke: round-trip a bus volume of -12.0 dB and assert equality.
- **Cross-system tie-in to PlayerVitalsPanel (ADR-0027) for the suit-O2-drain chirp** and to `FireState` for the fire crackle (already 3D-positioned in the loader) — both are listed as J-uice in the systems map §4.10; the audio plan must call this out so the polish pass does not duplicate them.

### Must-have acceptance
- ≥4 smoke files (`audio_bus_layout_smoke`, `audio_spatial_listener_smoke`, `audio_dynamic_music_smoke`, `audio_occlusion_smoke`) each with a unique PASS marker, plus the voice-cue-missing smoke if A-07 lands in this package.
- `scripts/audio/` directory created (verify it's gitignored for `.uid` sidecars per the existing pattern in `scripts/systems/`).
- ADR-0029 authored and accepted *before* any implementation code.
- REQ-018: Audio bus layout + listener + save round-trip (pure model smoke + main-scene smoke).
- REQ-019: Dynamic music state machine (combat/tension crossfade, locked to combat AI hooks — even if those hooks are placeholder signals in this package, the smoke asserts the contract).
- Bundle ends `commands=N+<count>` clean_output=true.

---

## Task 11 — Save / Persistence expansion (Section 4.7, items S-01…S-05)

### Recommended additions
- **Two sub-packages** so each ships end-to-end: **11a — Multi-slot + UI + quicksave confirm** (S-01, S-03, S-05) and **11b — Auto-save + Steam Cloud sync** (S-02, S-04). Auto-save depends on safe-room semantics that need an ADR; Steam Cloud is platform-gated and should not block 11a's local completeness.
- **11a MUST extend `RunSnapshot`** (current `scripts/systems/run_snapshot.gd`, 4625 bytes) to carry a `slot_id` field and version-bump `slice_version`. The ADR must define the on-disk layout: `user://saves/slot_<NN>_<iso_ts>.json` plus `user://saves/slot_<NN>.json` (rolling). Plan must specify the file naming + retention rule + cap (6–10 slots per systems map).
- **11a MUST add a `SaveSlotManager`** (pure model) that enumerates slots, parses metadata without loading full state, returns `[{slot_id, saved_at, objective_seq, ship_name, screenshot_path?}, ...]`. Pure-model smoke (`SAVE SLOT MANAGER PASS slots=N ordering=desc corrupt_rejected=true`) — the manager rejects corrupt JSON and slots with version mismatch without raising.
- **11a MUST add a `SaveSlotUI`** (Control, not CanvasLayer) under `scripts/ui/`. Cover the locked-isometric readability constraints from `docs/game/locked-iso-readability-harness.md`: TextScale-aware, high-contrast-on, fade-not-flicker on open/close. Smoke asserts the UI rejects input while `is_busy=true` (during save).
- **11a quicksave confirm dialog (S-03)** must show a "this overwrites your current slot" prompt with `OK / Cancel` — the F5/F9 keys currently bypass any confirm. Plan must add a `confirm_quicksave` setting default-on; smoke asserts the confirm fires when overwriting a non-empty slot.
- **11b auto-save (S-02)** MUST author a NEW ADR (`0030-auto-save-semantics`) BEFORE writing code. The ADR must define: trigger conditions (safe-room entry, objective completion, interval-timer with player-stationary guard), file rotation, the autosave `slot_id=autosave` reserved slot, recovery UX ("continue from autosave?"), and the hard rule that auto-save NEVER fires inside a fire/arc hazard zone (the existing `PhaseTimer` cycle would make autosaves themselves phase-flapping). Smoke asserts: (a) autosave fires on safe-room `Area3D.body_entered`, (b) autosave does NOT fire while `FireState.is_burning==true`, (c) autosave file is rotated, (d) the autosave slot is hidden from the picker UI by default.
- **11b Steam Cloud sync (S-04)** must use **GodotSteam's `RemoteStorage`** (per systems map §4.11) — plan must declare the Steamworks App ID slot, the conflict-resolution rule (local wins on newer `saved_at`), the bandwidth cap, and an offline-mode smoke that asserts the entire Steam path no-ops when `Steam.restartAppIfNecessary()` returns false. Steam Cloud must be feature-flagged behind a project setting `cloud_sync_enabled=true` default-on; smoke toggles it off and asserts the file-write still completes locally.
- **Save-slot UI (S-05)** MUST show a visual preview (per systems map §4.7). Plan must define the preview data shape — a 256×256 thumbnail captured at save time as `user://saves/previews/slot_<NN>.png`. Capture smoke asserts the PNG is non-empty, non-zero-alpha, and matches the slice's `Label3D` rendering at save time within a pixel tolerance. Don't ship if the thumbnail capture adds >30 ms to the save call (perf budget); smoke measures and asserts.
- **Cross-system consequence** — must update `docs/game/06_validation_plan.md` baseline WARNING allowlist if the `RunSnapshot.from_dict` rejection WARNING count changes (currently allowlisted per §6_validation_plan lines 44–46).
- **Migration safety.** Plan must include a `RunSnapshotMigrator` (pure) that bumps `gate2-current-run-1` → `gate2-multi-slot-1` → `gate2-steam-cloud-1` (or whatever the new versions land on). Smoke: feed an old-shape dict, assert upgraded shape, assert missing fields reject with the known WARNING marker.

### Must-have acceptance
- 11a: ≥3 smokes (`save_slot_manager_smoke`, `save_slot_ui_smoke`, `save_quicksave_confirm_smoke`); 11b: ≥3 smokes (`auto_save_smoke`, `auto_save_hazard_blocked_smoke`, `steam_cloud_offline_smoke`).
- 2 ADRs: `0029-save-multi-slot-ui.md`, `0030-auto-save-semantics.md`. (Note: 0029 likely collides with the Audio ADR numbering — keep a shared next-free index list in the plans and bump sequentially.)
- REQ-020: Multi-slot save (round-trip + UI reject-on-busy); REQ-021: Auto-save (interval + safe-room + hazard-blocked); REQ-022: Save preview capture budget.
- Bundle ends `commands=N+6` clean_output=true; the existing 120-command baseline must stay green.

---

## Task 13 — Distribution / Post-launch (Section 4.11, items R-01…R-12)

### Recommended additions
- **Two sub-packages by dependency tier:** **13a — itch.io + crash reporting** (R-01, R-09, R-07, R-12 — non-Steam-gated, can ship independently), **13b — Steam + Achievements + Deck** (R-02, R-03, R-04, R-05, R-06, R-08, R-10, R-11 — Steam-gated, contingent on App ID). 13a unblocks the existing export pipeline today.
- **13a MUST add a `crash_dump_writer.gd`** (RefCounted + autoload-free per `AGENTS.md`) that hooks `Engine.get_main_loop().process_frame` to detect a "stuck" frame (no input change for N seconds + no `RenderingServer.frame_post_draw` signal for M seconds — the actual thresholds are platform-specific; define them in the ADR) and writes a JSON crash blob to `user://crashes/<iso_ts>.json` with the last-known state summaries (oxygen, inventory, ship_systems, route_control, current_objective_sequence, scene tree path). Smoke runs a synthetic "stuck" frame and asserts the file appears with the expected shape.
- **13a MUST add an `IARC questionnaire`** output as a JSON file under `tools/iarc/` with the answer keys documented — the actual IARC submission is a browser step, not a runtime artifact, but the data file is auditable.
- **13a Mac export testing (R-07)** must define code-signing + notarization acceptance as a checklist (Apple Developer ID required, notarization ticket ID captured in `export_presets.cfg` note, Gatekeeper passes). Add an `export_checklist.md` under `docs/` that lists every checkbox; the smoke itself is human-gated but the checklist is auditable per REQ-005.
- **13b GodotSteam integration (R-02) MUST vendor the addon's API contract first.** Plan must declare the exact GodotSteam version, the `SteamInit`/`SteamShutdown` lifecycle hooks, and the AchievementManager / CloudManager / InputManager surface used. ADR must commit to GodotSteam (over alternative GodotSteamworks/Steamworks.NET bindings) because it's the existing reference in the systems map.
- **13b Achievement list design (R-04)** must enumerate the 25–50 achievements as a `data/achievements.json` (not a `.gd`) so design can edit without recompile. Each row: `id`, `name`, `description`, `icon_path_placeholder`, `trigger_event`, `trigger_threshold`, `hidden`. Smoke asserts every `trigger_event` exists as a signal/method on the model that emits it; reject if any are dangling.
- **13b Achievement implementation (R-05)** must add a `SteamAchievementsAdapter` (RefCounted) that the coordinator calls after each gameplay event. Smoke must use the Steamworks SDK mock to assert `StoreStats()` is called exactly once per achievement and that double-firing is rejected by `SetAchievement`'s idempotent return.
- **13b Steam Deck verification (R-06)** is hardware-gated and cannot ship a runtime smoke. Plan must define a `steam_deck_checklist.md` (controller glyphs per ADR-pending, 1280×800 confirmed, 40–60 FPS target with on-screen overlay off, 15 W TDP sustained). The plan's acceptance is "checklist complete + at least one human session log on hardware" — declare this honestly so it doesn't pretend to be validated by smoke.
- **13b Localization (R-08)** MUST scope to English + 1 (Japanese or Spanish — pick by existing user-base, not here). Plan must use Godot's built-in `tr()` + a `Locale` autoload-equivalent (since autoloads are services-only per `AGENTS.md`, this becomes a `LocaleService` RefCounted owned by `playable_generated_ship.gd`). Acceptance: every player-facing string passes through `tr()`; smoke asserts no hard-coded English survives in `scripts/ui/`.
- **13b Demo build (R-10)** must declare the gate (separate Steam App ID, separate `demo.tres` export preset, separate save directory `user://saves_demo/`). Smoke asserts the demo binary refuses to load non-demo saves (forward-compat protected).
- **13b Trailer (R-11) + store page assets (R-03)** are content work, not code. Plan must define the asset manifest `data/store_assets/manifest.json` with required filenames and dimensions (capsule 616×353, header 460×215, screenshot 1920×1080 × 5+, trailer 1920×1080 × 60 s). Acceptance is "all files present in `dist/`" — auditable, not automatable.
- **Cross-cutting.** All distribution work must NOT alter gameplay data shape (per `docs/game/store_requirements.md` "Save paths must be user-scope and never hardcoded"); any new save namespace (demo, cloud) is additive.
- **Telemetry boundary.** Crash dump writer must be **off by default in dev builds** and on in export builds (use `OS.has_feature("editor")` negation). Smoke toggles and asserts the file does/does not appear.

### Must-have acceptance
- 13a: ≥3 smokes (`crash_dump_writer_smoke`, `crash_dump_shape_smoke`, `export_presets_smoke`).
- 13b: ≥4 smokes (`steam_init_offline_smoke`, `achievements_adapter_smoke`, `locale_service_smoke`, `demo_save_isolation_smoke`).
- 2 ADRs: `0031-distribution-export-and-crash.md`, `0032-steam-and-achievements.md`.
- REQ-023: Crash dump capture + opt-out; REQ-024: Achievement event hooks (signal→adapter); REQ-025: Locale passthrough (no hard-coded English in `scripts/ui/`); REQ-026: Demo save isolation.
- Hard acceptance: `tools/iarc/questionnaire.json`, `data/achievements.json`, `data/store_assets/manifest.json` exist and parse cleanly. Bundle ends `commands=N+7` clean_output=true.

---

## Task 14 — Cross-system integration (Phase 7 in `09_system_roadmap.md`)

### Recommended additions
- **Single package, but split into 4 sub-plans by dependency order** so each closes a seam before the next integrates it:
  - **14a — Wire System 6 remaining carry containers + EquipmentSlots + transfer UI seam closure.** `09_system_roadmap.md` §A explicitly lists these as the remaining System 6 work. Add a `CarryContainer` Resource, an `EquipmentSlot` extension of `EquipmentState`, and a transfer UI seam test that asserts the inventory panel + cargo hold + equipment + carry container all read from the same `EquipmentState.get_summary()` (no duplicates — ADR-0027 just fixed a vitals duplication; don't reintroduce).
  - **14b — Status-effect + armor + damage pipeline cross-system.** Status effects must emit a `status_effect_applied` signal that PlayerVitalsPanel, damage direction indicator (U-07), threat indicator (U-06), and the new audio stingers (A-08) all subscribe to via the coordinator. Plan must define the signal contract and add a smoke that asserts each subscriber receives the same payload (no transform/drift).
  - **14c — Loot rarity + distribution curve + feedback loop cross-system.** Must derive rarity drop rates from the run's current difficulty preset (X-04 deferred), tie visual rarity feedback (LE-06) to existing `LootRoller`, and assert in a smoke that the rarity tints match the audio cue (rare loot = `Music.tension` 3 s sting). Cross-team.
  - **14d — Final wire-together + balance + perf pass.** End-to-end run scripted from start (lifeboat launch) to finish (jump-drive escape deferred, so to a hub-ship scene or save-and-quit). Smoke asserts the run completes within the perf budget (existing `PERFORMANCE BASELINE PASS templates=3` from §06_validation_plan line 99 becomes the seed; add `PERFORMANCE FULL RUN PASS ...` with framerate histogram and memory ceiling).
- **Adapter pattern.** Where integration crosses existing systems (e.g. combat AI music hooks — systems map §4.3 A-05), the package must introduce a named adapter (e.g. `CombatMusicAdapter`) rather than calling `AudioServer.set_bus_volume_db` directly from the AI script. ADR-0029's bus layout work gives the hook; this package writes the wire. Smoke asserts the adapter is reachable from the AI without a hard `class_name` reference.
- **Equivalence table** — package must produce `docs/game/cross_system_signal_table.md` listing every signal name, emitter owner, subscriber owners, payload schema, and the smoke that asserts it. This is the single artifact that proves "we wired it together" without per-team hand-waving. Format the table as a code block so diffs are reviewable.
- **Balance pass — give it its own ADR.** Balance is not "feel"; it's a set of tunable Resources with documented ranges. Plan must enumerate the 8–12 tunables (oxygen drain, fire cycle, repair skill XP, loot rarity weights, hunger/thirst when those land, encumbrance curve, scanner detail thresholds, accessibility text-scale) and require each to be a `Resource` loaded from `data/balance/<name>.tres` — no magic numbers in code (existing systems-map convention from `OxygenTuning Resource`, §6.2 R2). Smoke asserts no `Vector3(...)`/`float = N.NN` literals exist outside `data/balance/` for the listed tunables.
- **Perf budget + framerate histogram** — concrete numbers, not vibes. Plan must specify: 60 FPS at 1080p on a Steam Deck baseline, frame-time histogram <16.6 ms for 95th percentile, GC pause budget <2 ms/frame, max draw calls per room ≤1500. Smoke uses existing `scripts/validation/performance_profiler.gd` (already in the bundle) — extend it, don't fork.
- **Demo build path through Phase 7.** Task 13 demo (R-10) is contingent on this landing. Plan must declare the run-scriptable slice that the demo exports (lifeboat → 1 derelict → return; no meta). Cross-link.
- **Human playtest protocol update.** Existing `docs/game/playtests/gate-1-playtest-protocol.md` covers the 4-objective slice. Add `docs/game/playtests/integration-playtest-protocol.md` for the full loop: 30 min sessions, fresh-player observation, 5-dimension rubric (existing from §6.5) extended with "cross-system feedback" dimension (e.g. "did you hear the rare-loot audio sting?"). Acceptance: protocol authored + one session log written; smoke-equivalent (the existing automated playtest `automated-playtest-protocol.md`) extended with a "full run" script.

### Must-have acceptance
- ≥4 sub-plans × ≥2 smokes each = ≥8 new smokes (`cross_system_wire_*.gd`, `status_effect_signal_smoke`, `loot_rarity_audio_smoke`, `performance_full_run_smoke`, etc.).
- ≥2 ADRs: `0033-cross-system-adapter-pattern.md`, `0034-balance-resource-convention.md`.
- `docs/game/cross_system_signal_table.md` exists and is referenced from `09_system_roadmap.md`.
- REQ-027: Cross-system signal table integrity (smoke asserts every emitter/subscriber pair is in the table and round-trips a payload).
- REQ-028: Balance tunables as Resources (smoke greps for forbidden literal patterns).
- REQ-029: Performance budget — concrete framerate, draw call, GC numbers asserted in `performance_full_run_smoke`.
- Bundle ends `commands=N+8` clean_output=true; no regression of the 120-command baseline.

---

## Task 15 — Systems map / build plan update (`docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md` + `docs/game/09_system_roadmap.md`)

### Recommended additions
- **Not an implementation package** — explicitly. This is the documentation package that **closes the loop** after Tasks 9–14 land. Its plan must say, in the Global Constraints section, "this plan produces ZERO new code; its only artifacts are doc updates, ADR cross-references, and a refreshed `09_system_roadmap.md`. Reviewer should reject any commit that adds a `.gd` file to this plan's File Structure."
- **Concrete update list — every row from the systems map status matrix gets either ✅ BUILT (with smoke marker evidence), ⚠️ PARTIAL (with the specific gap), 📋 SPEC'D (with the spec path), or ❌ MISSING (with the new plan package that will own it).** No more "we'll get to it". The map is the contract.
- **For each "PARTIAL" row, list the residual gap and the Task 9–14 package that closes it.** Example: "Scanner: PARTIAL — long-range/motion-tracker remains; closed by 14c loot-rarity or by a new scan-detail sub-package; new ADR-pending". This makes the map a living dashboard.
- **For each "MISSING" row in §4.11 (Distribution), reference the Task 13 plan package and ADR by name.** No loose ends.
- **`09_system_roadmap.md` (Phase 7) needs an explicit "What this phase produces" table** mirroring Phase 6's "Inventory & Equipment ~88%" format — but with the exact post-Tasks-9–14 breakdown by sub-system (UI/UX, Audio, Persistence, Distribution, Integration). Replace the current "Phase 7 — Integration & Polish (the 'wire it all together' step)" prose with a structured table per sub-system: status, primary evidence (file paths + smoke marker), residual gap, owning package.
- **Critical Path diagram** (§3.2 of the systems map) needs an update: add a third parallel stream for Distribution (alongside Audio + Polish from §3.3). Mark the existing "Combat → Meta → Ship" critical path explicitly as "post-Phase-7", and add a new critical path for the commercial ship: "Audio + Persistence + Distribution + Integration → Production".
- **Dependency Map (Tier 0–4)** must reflect the actual current Tier 0 status. Today, Tier 0 lists "Multi-slot save system" as buildable — it is not, because 11a/b and 13b do not exist. Replace with a new Tier 0 that lists the 6 packages above (9, 10, 11a, 11b, 13a, 13b, 14a-d, 15) plus their hard cross-deps (e.g. 14c depends on 10 + 11a).
- **Estimated Remaining Effort table** (§5) — replace the "32–42 weeks" estimate with a per-package estimate derived from each sub-plan's Task checkboxes. The estimates are not the deliverable; the per-package Task count and the smoke count are.
- **Cross-Reference Index (PLANNING_SYNTHESIS §15)** must add the new ADRs and the new REQs.
- **Add a "How to verify the systems map is current" runbook** at the end of `09_system_roadmap.md`: a single command (or short sequence) that an agent can run to confirm every "BUILT" row in the matrix is backed by a smoke that still passes. This is the closing of the loop — without it, the map drifts on the next non-trivial change.
- **Predecessor gate** — Task 15 cannot claim Done until ALL of Tasks 9, 10, 11a, 11b, 13a, 13b, 14a, 14b, 14c, 14d are Done (their final plan's "Acceptance" section is signed). Add as the first Acceptance bullet of Task 15's plan.

### Must-have acceptance
- ONE smoke only: `systems_map_currency_smoke.gd` — pure-data smoke that loads `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`, parses the status matrix, asserts every ✅ BUILT row references at least one smoke in `06_validation_plan.md` that is still in the bundle (by name), every ⚠️ PARTIAL row references an open issue or owning sub-package, every 📋 SPEC'D row references a file under `docs/game/features/`, every ❌ MISSING row references a Task 9–14 plan or an ADR-pending note. This is the only acceptable way to keep the map honest.
- Doc-only file changes, audited via the no-git ledger: `docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md`, `docs/game/09_system_roadmap.md`, `docs/PLANNING_SYNTHESIS.md` §15, `docs/game/05_requirements.md` (new REQ rows for 15–29), and an entry under `docs/game/accessibility_review.md` if any a11y-relevant change lands.
- No `.gd` files created or modified by this plan. Any `.gd` diff in the PR blocks completion.
- ADR-0035 `systems-map-as-source-of-truth.md` — single ADR asserting that the systems map matrix is the contract, that every BUILT row must be backed by a smoke, and that drift fails the bundle. (Or amend an existing ADR; the existing pattern is per-decision so a new one is cleaner.)
- REQ-030: Systems map currency (the smoke above is the verification).
- Bundle ends `commands=N+1` clean_output=true.

---

## Summary of net deliverables across Tasks 9–11, 13–15

- **6 plan packages** authored in the format of `2026-06-24-phase7-player-vitals-hud.md` (Task 9 as 3 sub-plans, Task 11 as 2, Task 13 as 2, Task 14 as 4 sub-plans, Task 15 as 1 = 12 sub-plan files total, all under `docs/superpowers/plans/`).
- **≥32 new smoke files** registered in `docs/game/06_validation_plan.md` with unique PASS markers and an explicit `commands=N+<count>` bundle bump each.
- **≥10 new ADRs** under `docs/game/adr/0029..0038` (Audio bus, Multi-slot UI, Auto-save semantics, Distribution/export/crash, Steam/achievements, Cross-system adapter, Balance-resource convention, Systems-map-as-source-of-truth, plus 2 from Task 9 menu/HUD/world if those split lands).
- **≥16 new REQ rows** in `docs/game/05_requirements.md` (REQ-015…REQ-030, each with explicit Verification command).
- **`scripts/audio/`** directory created with `audio_bus_layout.gd`, `audio_listener_rig.gd`, `audio_dynamic_music.gd`, `audio_occlusion.gd`, `voice_cue_manifest.gd`, `crash_dump_writer.gd`, `save_slot_manager.gd`, `save_slot_ui.gd`, `steam_achievements_adapter.gd`, `locale_service.gd`, plus the carry-container and equipment-slot extensions for 14a.
- **One docs-only smoke (`systems_map_currency_smoke.gd`)** that locks the map as the contract.
- **All plans** explicitly forbid git-commit reliance (use the no-git ledger path), explicitly forbid proof-only artifacts (per REQ-005), explicitly enumerate the smoke files in File Structure (not as a "TBD"), and explicitly call out the predecessor review-card IDs at the top.

This converts the 6 spec-only stubs into 12 standalone end-to-end design + implementation + review packages, each independently validatable in the existing 120+ command regression bundle.
