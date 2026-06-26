# Feature: Release Distribution, Store, Achievements, Demo, Localization & Post-Launch Ops

## Status

Approved for Gate 3 implementation (Task 13)

## Requirement cross-reference

- REQ-RL-001 Export preset validation (all four targets).
- REQ-RL-002 Build metadata and platform identification.
- REQ-RL-003 Achievement catalog (data-driven, real gameplay triggers).
- REQ-RL-004 Achievement state service (per-run persistence, catalog lookup).
- REQ-RL-005 Localization catalog (string lookup by id, language switching).
- REQ-RL-006 Demo scope gate (data-driven feature gating, deterministic predicates).
- REQ-RL-007 Crash report bundle (log capture, disk write, post-launch telemetry seam).
- REQ-RL-008 Release readiness ledger (evidence rows, local vs external source tags).
- REQ-RL-009 Credits / attribution data and UI screen.
- REQ-RL-010 Post-launch playbook (checklist data + telemetry categories).

## Design pillar alignment

- Runtime systems over proof artifacts: the package ships Godot services, UI hooks, and JSON catalogs — not screenshots of pages that link to Steam.
- Small vertical slices before broad systems: each subsystem is a single `RefCounted` model with a single smoke, registered in the regression bundle.
- Pure-model-first (Pillar 4): every state machine is a `RefCounted` that does not reach into the scene tree; scene nodes apply scene consequences.
- Long-tail support (Pillar 5): release ops, demo gating, and localization are first-class so future content drops slot into the catalog and the manifest without touching code.

## Player fantasy

The player launches a fully-tested build of **The Synapse Sea** on whichever storefront they chose (itch.io Web demo, Steam Windows/Linux/macOS), in their preferred language (English at launch), sees consistent credits and achievements across platforms, and gets a working demo that gates non-story content without crashing. After launch, every shipping concern (saves, achievements, demo, localization, crash bundle, release ledger) has a runtime seam rather than a hand-coded checklist.

## Gameplay problem

The Synapse Sea shipped its Gate 2 vertical slice without:

- A real export-pipeline validation (the existing `export_presets.cfg` is unvalidated; a bad preset path would only surface at release time).
- Achievements at all — Steam achievements require a real, data-driven catalog and unlock events triggered by gameplay milestones.
- Localization — every UI string is hard-coded English.
- Demo gating — there is no separate "demo build" with restricted content.
- Crash/logging telemetry — no bundle written when the engine hits an exception.
- A release readiness ledger — there is no machine-checkable manifest that distinguishes local smoke evidence from external (Steam/itch) evidence.

Gate 3 needs all six before any storefront submission.

## Core behavior

- **Export preset validation.** `ExportPresetsValidator.parse(cfg_path)` reads `export_presets.cfg` and returns a list of `{name, platform, export_path, runnable, include_filter, exclude_filter}` dicts. The dry-run smoke asserts each preset has the required keys and that `export_path` starts with `build/exports/<preset_name>/`.
- **Build metadata.** `BuildMetadataState.configure(manifest_dict)` reads `data/release/build_metadata.json` (version, build_kind, store, language_defaults, achievements_supported) and exposes `get_summary()`. The demo gate and the release ledger both consume `build_metadata.get_summary()["build_kind"]` so there is one source of truth.
- **Achievement catalog.** `data/release/achievement_catalog.json` lists every achievement: `{id, display_name, description, icon_placeholder, trigger_event, trigger_target}`. `AchievementService` loads the catalog at boot and unlocks achievements when the corresponding gameplay event fires. Unlocks live at `user://achievements.json` (separate from the run snapshot, per ADR-0007).
- **Achievement state.** `AchievementState` (pure `RefCounted`) holds the per-run unlock set, exposes `unlock(id) -> bool`, `is_unlocked(id) -> bool`, `get_unlocked() -> Array`, `get_summary()`, `apply_summary()`. `unlock` returns `false` (and prints the smoke's expected `INFO` line) for unknown ids — the catalog is the only source of truth.
- **Localization catalog.** `data/release/localization_catalog.json` maps `{language_id: {string_id: translation}}`. `LocalizationCatalog` loads the file, exposes `translate(string_id, language_id)` and `translate_fallback(string_id, default_text, language_id)`. Unknown ids and missing languages fall back to the default text; unknown keys never raise.
- **Demo scope gate.** `data/release/demo_scope_manifest.json` lists every demo-restricted feature: `{feature_id, reason, hint}`. `DemoScopeGate.is_allowed(feature_id)` returns `true` when `build_kind == "full"` or when the feature id is NOT in the demo manifest; returns `false` otherwise. The smoke proves the gate is deterministic and rejects unknown ids (no silent `true`).
- **Crash report bundle.** `CrashReportBundle.capture(message, context, stack)` appends to an in-memory log; `flush(target_path)` writes `user://crash/<timestamp>.bundle.json`. The bundle caps at 256 entries; older entries are dropped FIFO. The smoke proves the round-trip and the cap.
- **Release readiness ledger.** `data/release/release_checklist.json` lists every ship-blocking check: `{check_id, description, category}`. `ReleaseReadinessLedger` records evidence rows: `{check_id, status: pass/fail/pending, source: local/external, evidence_path, captured_at}`. The smoke proves the local/external discrimination and that no `pass` row with `source=external` can be inserted without an explicit `evidence_path`.
- **Credits screen.** `data/release/credits.json` lists every attribution entry: `{role, name, license?, note?}`. `scripts/ui/credits_screen.gd` renders it as a scrolling panel; the smoke asserts the catalog parses and rolls up to ≥ 5 entries.
- **Post-launch playbook.** `data/release/release_checklist.json` doubles as the post-launch play-book skeleton: each check has a `category` of `pre_launch`, `launch_day`, or `post_launch`. The smoke asserts every check has a category and that at least one check exists per category.
- **UI seams.** `LanguageSelector`, `CreditsScreen`, `AchievementsPanel`, `ReleaseBadgeOverlay` are pure UI scripts that consume the services. The smoke proves the script files parse (loadable as Godot scripts) and the `release_badge_overlay` shows "DEMO" only when `build_kind == "demo"`.

## Inputs

- JSON catalogs under `data/release/`.
- `export_presets.cfg` (existing).
- `BuildMetadataState` consumed by `DemoScopeGate`, `ReleaseReadinessLedger`, `ReleaseBadgeOverlay`.
- Real gameplay events emitted by `PlayableGeneratedShip` (objective completion, tool pickup, reactor stabilized, run complete).

## Outputs

- `user://achievements.json` — per-run unlock set.
- `user://crash/<timestamp>.bundle.json` — captured crash bundles (≤256 entries each).
- `ReleaseReadinessLedger.get_summary()` — local/external-tagged evidence rows.
- UI overlay badge ("DEMO", "RELEASE", "DEV") in the top-left HUD during play.

## Rules

- Achievement unlocks are per-run only. A new run starts with an empty unlock set; achievements persist across saves within the same run, but a fresh run wipes them. This preserves ADR-0007's "no cross-run unlocks" boundary.
- Localization falls back to the supplied default text on any unknown id, unknown language, or missing translation. The smoke proves every unknown-id query returns the default text.
- Demo gate is data-driven — adding a feature to the manifest is a JSON edit, not a code change.
- Crash bundle caps at 256 entries FIFO so a runaway log never blows up the user data dir.
- Release ledger `source=external` rows MUST carry a non-empty `evidence_path`; the smoke asserts this contract.

## Non-goals

- No actual Steamworks SDK integration in this package — `source=external` rows are written by an explicit `record_external_evidence(...)` call that an external CI/Steam-pipeline integration would invoke. The smoke proves the schema accepts them without needing the real SDK.
- No real Steam Achievements activation in this package — achievement state lives in `user://achievements.json` only. Steam-pushing is a deferred integration seam.
- No real itch.io upload automation — `scripts/export/build_release.sh` produces the release zips; an out-of-band CI step pushes them. The smoke proves the zip naming and the SHA256 ledger exist.
- No real translation work — `localization_catalog.json` only carries an English baseline at launch. Other languages slot in later via the same catalog file.
- No real crash-report server upload — `CrashReportBundle.flush()` writes to disk only. An out-of-band step uploads.
- No Steam Deck-specific code path in this package — the README + post-launch playbook note that Steam Deck verification is a separate validation pass using `windowed_fps_capture.gd` + a controller smoke (out of scope here).

## Technical design

### New data resources

- `data/release/build_metadata.json`:
  ```json
  {
    "version": "v0.1.0",
    "build_kind": "dev",
    "store": "itch",
    "language_defaults": ["en"],
    "achievements_supported": true,
    "demo_hub_unlocked_features": ["oxygen_breach", "fire_hazard", "objective_progress"]
  }
  ```
- `data/release/achievement_catalog.json`: list of `{id, display_name, description, icon_placeholder, trigger_event, trigger_target}` entries.
- `data/release/credits.json`: list of `{role, name, license?, note?}` entries.
- `data/release/demo_scope_manifest.json`: list of `{feature_id, reason, hint}` entries.
- `data/release/localization_catalog.json`: `{language_id: {string_id: translation}}`.
- `data/release/release_checklist.json`: list of `{check_id, description, category: pre_launch|launch_day|post_launch}` entries.

### New pure models (all under `scripts/systems/`, all `RefCounted`)

- `build_metadata_state.gd` — `BuildMetadataState`. `configure(manifest: Dictionary)`, `get_summary() -> Dictionary`, `get_build_kind() -> String`, `is_achievements_supported() -> bool`.
- `achievement_state.gd` — `AchievementState`. Owns the unlock set and the catalog; `unlock(id) -> bool`, `is_unlocked(id) -> bool`, `get_unlocked() -> Array`, `get_summary()`, `apply_summary()`, `get_status_lines()`. Loads catalog from `data/release/achievement_catalog.json` by default; falls back to empty catalog on missing file (logs a `WARNING` that the allowlist covers).
- `localization_catalog.gd` — `LocalizationCatalog`. `configure(catalog: Dictionary, default_language: String = "en")`, `translate(string_id, language_id) -> String`, `translate_fallback(string_id, default_text, language_id) -> String`, `get_known_languages() -> Array`, `get_summary()`.
- `demo_scope_gate.gd` — `DemoScopeGate`. `configure(manifest: Dictionary, build_metadata: BuildMetadataState)`, `is_allowed(feature_id) -> bool`, `list_blocked() -> Array`, `get_summary()`.
- `crash_report_bundle.gd` — `CrashReportBundle`. `capture(message: String, context: Dictionary, stack: Array)`, `flush(target_path: String) -> bool`, `size() -> int`, `get_entries() -> Array`, `clear()`. Caps at 256 entries FIFO.
- `release_readiness_ledger.gd` — `ReleaseReadinessLedger`. `configure(checklist: Dictionary)`, `record_local_evidence(check_id, status, evidence_path) -> bool`, `record_external_evidence(check_id, status, evidence_path, captured_at) -> bool`, `get_rows() -> Array`, `get_summary()`, `get_status_lines()`.

### New UI seams (all under `scripts/ui/`, all `extends Control`)

- `language_selector.gd` — `LanguageSelector`. Owns a `LocalizationCatalog`; emits `language_changed(language_id)`. The HUD label shows the active language code.
- `credits_screen.gd` — `CreditsScreen`. Loads `data/release/credits.json` at boot; renders a scrolling list; emits `credits_dismissed`.
- `achievements_panel.gd` — `AchievementsPanel`. Renders the achievement catalog grouped by unlock status; reads `AchievementState.get_summary()` and the catalog.
- `release_badge_overlay.gd` — `ReleaseBadgeOverlay`. Reads `BuildMetadataState.get_build_kind()`; shows "DEMO" (orange), "RELEASE" (green), or "DEV" (gray) overlay.

### New smokes (all under `scripts/validation/`)

- `export_presets_smoke.gd` — marker `EXPORT PRESETS PASS presets=N all_runnable=true paths_under_build=true`.
- `achievement_state_smoke.gd` — marker `ACHIEVEMENT STATE PASS unlocked=N catalog=N unknown_rejected=true`.
- `localization_catalog_smoke.gd` — marker `LOCALIZATION CATALOG PASS languages=N translations=N fallback=true unknown_returns_default=true`.
- `demo_scope_gate_smoke.gd` — marker `DEMO SCOPE GATE PASS build_kind=<full|demo> blocked=<n> allowed=<n> unknown_rejected=true`.
- `release_readiness_ledger_smoke.gd` — marker `RELEASE READINESS LEDGER PASS rows=N local=N external=N external_evidence_required=true`.

All five added to `docs/game/06_validation_plan.md` regression bundle.

## Persistence / migration

- `user://achievements.json` — keyed by achievement id → `{unlocked: bool, unlocked_at: String}`. Schema version `release-achievements-1`.
- `user://crash/<timestamp>.bundle.json` — keyed list of `{message, context, stack, captured_at}`. Caps at 256 entries per file.
- `ReleaseReadinessLedger` is in-memory only — it is rebuilt at every boot from `data/release/release_checklist.json` plus the on-disk evidence rows (out of scope: a `user://release_evidence.json` seam).

## Verification

Run focused smokes:

```bash
ROOT=/Users/christopherwilloughby/the-synaptic-sea GODOT=/Users/christopherwilloughby/.local/bin/godot-4.6.2 /Users/christopherwilloughby/.local/bin/godot-4.6.2 --headless --path /Users/christopherwilloughby/the-synaptic-sea --script res://scripts/validation/export_presets_smoke.gd
# ... +4 more
```

Then run the regression bundle from `docs/game/06_validation_plan.md` with `ROOT=/Users/christopherwilloughby/the-synaptic-sea`.

## Stop/block conditions

- A required catalog file cannot be parsed (rare — all files are versioned JSON).
- `export_presets.cfg` no longer exists or no longer carries one of the four presets — block, because the dry-run smoke would silently skip the missing preset.
- Godot `ERROR:`/`WARNING:` lines outside the allowlist — block until classified.
- Cross-run achievement unlock request — block, because ADR-0007 forbids it.