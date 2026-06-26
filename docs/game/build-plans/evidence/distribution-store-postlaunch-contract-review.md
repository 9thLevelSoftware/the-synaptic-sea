# Distribution / Store / Achievements / Demo / Localization / Post-Launch Ops Package — Contract and Gap Review

Package: `docs/game/build-plans/13-distribution-store-postlaunch-e2e.md`
Author: synaptic_seaworker (Task 13, board `synaptic-sea-stage-gate`, card `t_3b217838`)
Date: 2026-06-25

## Existing seams to extend (not replace)

| File | Role | Action |
|---|---|---|
| `export_presets.cfg` | 4 presets (web/linux/macos/windows) keyed `[preset.N]` with `name/platform/export_path/runnable/include_filter/exclude_filter`. | **Read-only.** The new `export_presets_smoke` parses it and asserts every preset carries the required keys plus a path under `build/exports/<target>/`. No edits to the file. |
| `scripts/export/build_release.sh` | Bash pipeline that calls Godot export, packages dirs to zips, writes SHA256 ledger. | **Read-only.** The smoke asserts the script parses with bash and references the same preset names as `export_presets.cfg`. |
| `scripts/systems/save_load_service.gd` | Single-slot current-run save/load (REQ-012 / ADR-0007). | **Keep.** Achievement unlocks ride on top via a separate service; no save-schema change. ADR-0007's "no hub/meta/cross-run" rule is preserved — achievement state is per-run, not per-profile. |
| `scripts/systems/run_snapshot.gd` | Pure data, 8 SUMMARY_FIELDS. | **Keep.** No new field added. The achievement service writes to its own `user://achievements.json` slot, independent of the run snapshot. |
| `scripts/procgen/playable_generated_ship.gd` | Scene coordinator that drives objectives and owns `SaveLoadService`. | **Extend (minimal).** Emit `achievement_unlocked(id)` at real gameplay milestones (first oxygen tool pickup, first repair, reactor stabilized, run complete). The signal is a thin wrapper around existing objective events; no new gameplay behavior. |
| `scripts/validation/*_smoke.gd` | SceneTree smoke convention with `_fail()` / explicit pass markers. | **Pattern reused.** Five new smokes match the convention. |
| `docs/game/05_requirements.md` | REQ-001..014 established. | **Extend.** Add REQ-RL-001..010 with Proposed → Approved transitions as the package lands. |
| `docs/game/06_validation_plan.md` | 120-command regression bundle. | **Extend.** Add five `run_clean` entries; allowlist one expected `WARNING` from the smoke that proves the demo gate rejects an out-of-scope feature. |
| `docs/game/adr/0007-save-load-service-scope.md` | Save boundary. | **Untouched.** The release-distribution package does not touch save schema. |

## Missing files (created by this package)

- `docs/game/features/release_distribution.md`
- `docs/game/adr/0029-release-distribution-architecture.md`
- `docs/game/adr/0030-achievement-catalog-and-triggers.md`
- `docs/game/adr/0031-localization-catalog-and-routing.md`
- `scripts/systems/build_metadata_state.gd`
- `scripts/systems/achievement_state.gd`
- `scripts/systems/localization_catalog.gd`
- `scripts/systems/crash_report_bundle.gd`
- `scripts/systems/demo_scope_gate.gd`
- `scripts/systems/release_readiness_ledger.gd`
- `data/release/achievement_catalog.json`
- `data/release/credits.json`
- `data/release/demo_scope_manifest.json`
- `data/release/localization_catalog.json`
- `data/release/release_checklist.json`
- `data/release/build_metadata.json`
- `scripts/ui/release_badge_overlay.gd`
- `scripts/ui/language_selector.gd`
- `scripts/ui/credits_screen.gd`
- `scripts/ui/achievements_panel.gd`
- `scripts/validation/export_presets_smoke.gd`
- `scripts/validation/achievement_state_smoke.gd`
- `scripts/validation/localization_catalog_smoke.gd`
- `scripts/validation/demo_scope_gate_smoke.gd`
- `scripts/validation/release_readiness_ledger_smoke.gd`
- `docs/game/balance/release_distribution_tuning.md`
- `docs/game/balance/` directory itself if absent (created by write_file).

## Chosen extension seams (no conflicts with existing ADRs)

- Pure models live under `scripts/systems/`, all `RefCounted`, all implement the `configure / tick / get_summary / apply_summary / get_status_lines` shape used by the Gate 2 hazard models (ADR-0005 contract reused — pure data, scene-tree never touched).
- The achievement trigger rides through a new signal `achievement_unlocked(id)` on the scene coordinator; the service owns the catalog and the per-run state. Unlock state lives at `user://achievements.json` so a corrupted run save does not wipe achievements and vice versa.
- The localization catalog is a pure data model that takes a language id and returns a translated string. UI panels and HUD labels look up strings by id rather than embedding literals. The English strings remain in code (Godot's standard fallback) and the catalog overlays a translation dictionary.
- The release readiness ledger is a pure model that tracks evidence rows; each row tags itself `source=local` (a smoke result or checklist tick) vs `source=external` (a Steam/itch API call, the build manifest, or a human sign-off). The smoke asserts the discrimination without depending on any external network.
- Demo manifest is data-driven — pure model queries it for `is_demo_*` predicates. The smoke proves the gate returns deterministic true/false for seeded queries, and rejects unknown feature ids.
- Export presets dry-run parses `export_presets.cfg` and verifies each preset has the required keys plus the export path under `build/exports/<preset>/`. The smoke does NOT execute Godot export (which would require the export templates) — it validates the config and the script command-shape so a real release run can fail loudly only on Godot itself.
- CrashReportBundle is a pure data sink: collects log lines and writes a `user://crash/<timestamp>.bundle.json` file. The smoke asserts the round-trip and the log-cap behavior.
- BuildMetadataState reads the build manifest at boot and exposes `build_kind` (`full` / `demo` / `dev`) so the demo gate and the release ledger have a single source of truth for "what kind of build is running."

## Stop/block check

No existing ADR contradicts this package:
- ADR-0007 (current-run save) is preserved — no save schema change.
- ADR-0005 (hazard contract) is reused, not modified — non-hazard models are explicitly allowed to use the same shape.
- ADR-0002/0003 (hub/meta deferred through Gate 2) is preserved — achievements are per-run, not cross-run unlocks.

No block condition triggers. Beginning RED phase.