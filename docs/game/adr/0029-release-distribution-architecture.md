# ADR-0029: Release Distribution Architecture

Date: 2026-06-25
Status: Accepted
System: 13 — Distribution, Store, Achievements, Demo, Localization & Post-Launch Ops
Relates to: ADR-0007 (save/load boundary), ADR-0012 (world persistence),
`docs/game/build-plans/13-distribution-store-postlaunch-e2e.md`,
`docs/game/features/release_distribution.md`.

## Context

The Synaptic Sea reached Gate 2 with working gameplay but no production-readiness
plumbing. Every shipping concern was implicit:

- `export_presets.cfg` had four presets but no validator — a bad path would only
  surface at release time, when fixing it costs a day.
- `BuildMetadataState` did not exist; the engine had no notion of whether a
  build was `dev`, `demo`, or `release`.
- The release-readiness posture was a markdown checklist — every gate reviewer
  eyeballed the bundle output by hand.
- Crash logs lived in the engine's stdout/stderr; a player hitting a bug
  reported "the game closed" with no data.
- Demo gating was not modeled at all — a Steam demo would either ship the full
  game or require hard-coding a `#if DEMO_BUILD` switch throughout the code.

The package requirement range `REQ-RL-001..010` and the build plan
`docs/game/build-plans/13-distribution-store-postlaunch-e2e.md` lock the scope
to **production release operations**, not new gameplay.

## Decision

Introduce six pure-model services under `scripts/systems/`:

- `BuildMetadataState` — reads `data/release/build_metadata.json`; exposes
  `get_build_kind()`, `is_achievements_supported()`, `get_summary()`. Single
  source of truth for "what kind of build is running."
- `AchievementState` — owns the unlock set and the catalog;
  per-run persistence to `user://achievements.json` (separate from the run
  snapshot, per ADR-0007). Emits `achievement_unlocked(id)` so the UI
  listens rather than polls.
- `LocalizationCatalog` — pure data; `translate(id, language)` /
  `translate_fallback(id, default, language)`. Unknown id → default text;
  unknown language → default language's text.
- `DemoScopeGate` — `configure(manifest, build_metadata)`; `is_allowed(id)`
  returns `false` for any feature in the demo manifest when
  `build_kind == "demo"`, `true` otherwise. Unknown ids are rejected (no
  silent allow).
- `CrashReportBundle` — captures `{message, context, stack}`; `flush(path)`
  writes a JSON bundle capped at 256 entries FIFO. Disk-only; upload is an
  out-of-band concern.
- `ReleaseReadinessLedger` — pure in-memory evidence tracker; every row tags
  `source=local` (smoke output, checklist tick) or `source=external` (Steam
  push, human sign-off). External rows MUST carry a non-empty
  `evidence_path`; the schema rejects empty ones.

Plus four UI seams under `scripts/ui/`:

- `LanguageSelector`, `CreditsScreen`, `AchievementsPanel`,
  `ReleaseBadgeOverlay` — all `extends Control`, all consume the services.

And six JSON catalogs under `data/release/`:

- `build_metadata.json`, `achievement_catalog.json`, `credits.json`,
  `demo_scope_manifest.json`, `localization_catalog.json`,
  `release_checklist.json`.

All services are `RefCounted`, all implement
`configure / get_summary / apply_summary / get_status_lines` (the same
contract ADR-0005 defined for hazard models; reusing the shape keeps the
project consistent).

`export_presets_smoke.gd` parses `export_presets.cfg` and asserts each
preset has the required keys (`name`, `platform`, `export_path`, `runnable`,
`include_filter`, `exclude_filter`) plus a path under
`build/exports/<preset>/`. The smoke does NOT execute Godot export (the
export templates are not always present in CI); it validates the config
shape so a real release run can fail loudly only on Godot itself.

## Consequences

- All release operations ship as runtime services that smokes can exercise
  headless, not as out-of-band scripts only humans can read.
- The demo gate is data-driven — adding a feature to the manifest is a
  JSON edit, not a code change. A future patch that wants to release a new
  feature as demo-restricted updates the manifest and rebuilds.
- Achievement unlocks are per-run only (ADR-0007 boundary preserved). The
  cross-run "achievement points" Steam shows are an external concern that
  the future Steamworks integration will reconcile against the
  `user://achievements.json` per-run state.
- The release readiness ledger lives in memory at boot; its rows are
  written by an external CI step (a deferred integration concern).
- No Steamworks, no itch API, no translation work, and no real crash
  upload in this package. The smoke proves the schema accepts the
  external-shape rows without depending on any external service.

## Deferred

- Steamworks SDK integration (Steam achievements activation, Steam Cloud
  saves, Steam Deck controller mapping).
- itch.io upload automation.
- Non-English translations (the catalog carries English only at launch).
- Crash bundle upload to a telemetry endpoint.
- Steam Deck verification (separate validation pass using
  `windowed_fps_capture.gd` + a controller smoke).