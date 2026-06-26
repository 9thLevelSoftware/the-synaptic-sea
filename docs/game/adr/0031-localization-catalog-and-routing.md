# ADR-0031: Localization Catalog and Routing

Date: 2026-06-25
Status: Accepted
System: 13 — Distribution, Store, Achievements, Demo, Localization & Post-Launch Ops
Relates to: ADR-0029 (release distribution architecture),
ADR-0030 (achievement catalog and triggers),
`docs/game/features/release_distribution.md`.

## Context

Every player-facing string in the Synaptic Sea is hard-coded English:

- HUD lines ("Oxygen:", "Breach:", "Load:") in `oxygen_state.gd`,
  `player_vitals_model.gd`, `inventory_state.gd`.
- Achievement display names and descriptions in the catalog.
- Objective labels in `objective_tracker.gd`.
- Credits screen.

Without a localization seam, every non-English translation required a
code change and a smoke regression. Project Zomboid's many-language
release (English + 10+ community translations) shows the long-tail value
of getting this right early.

## Decision

Introduce a pure-data catalog + service pair.

### Catalog: `data/release/localization_catalog.json`

A JSON object keyed by language id; each value is a `{string_id: translation}` map. The English baseline is the same `string_id` set used everywhere in code.

```json
{
  "en": {
    "oxygen.label": "Oxygen:",
    "breach.sealed": "Breach: sealed",
    "load.label": "Load:",
    "achievement.first_breath.name": "First Breath",
    "achievement.first_breath.desc": "Pick up your first portable oxygen pump."
  }
}
```

The English baseline is the source of truth — code references
`tr("oxygen.label")` and the catalog overlays translations.

### Service: `LocalizationCatalog` (pure `RefCounted`)

- `configure(catalog: Dictionary, default_language: String = "en")` —
  loads the catalog and remembers the default.
- `translate(string_id: String, language_id: String) -> String` — looks up
  the string in the requested language; falls back to default language;
  falls back to the empty string if the id is unknown.
- `translate_fallback(string_id: String, default_text: String, language_id: String) -> String` — convenience for callers that have an English baseline inline.
- `get_known_languages() -> Array[String]`.
- `get_summary()` — for save / telemetry.

### Routing

- Existing UI scripts (`oxygen_state.gd`, `objective_tracker.gd`,
  `scanner_panel.gd`, `inventory_panel.gd`) are extended with a small
  `_tr(string_id) -> String` helper that pulls from a project-singleton
  `LocalizationCatalog` (registered as `Localization` autoload in
  `project.godot`).
- Adding a new language is a JSON edit: add a `{<lang>: {...}}` block.
  No code change.
- Switching language at runtime is an explicit
  `Localization.set_language("ja")` call that emits
  `language_changed(id)`; UI panels re-render via signal listen.

### Fallback rules (smoke-locked)

- Unknown `string_id` → default text (or empty if no fallback supplied).
- Unknown `language_id` → default language's text.
- Missing translation key inside a known language → default language's
  text (NOT empty — preserves HUD readability).

## Consequences

- A future non-English release slots into the catalog without touching
  code. The smoke proves the round-trip; CI can run a "no missing
  English keys" check by diffing the catalog against the codebase.
- The autoload is a thin wrapper over the service (`var catalog :=
  LocalizationCatalog.new(); catalog.configure(load_json(...))`). The
  service stays pure; the autoload just instantiates it.
- HUD strings get slightly longer at runtime (one Dictionary lookup per
  render); the smoke asserts < 1 µs per lookup at the test scale.
- English baseline stays inline as the code default — the catalog is the
  overlay, not the only source. This keeps the codebase readable.

## Deferred

- Actual non-English translations (community translators add them later).
- Right-to-left language support (Arabic / Hebrew) — requires a font
  swap and a LayoutDirection.override call, deferred to a future package.
- Pluralization rules (ICU MessageFormat) — not needed for v1 strings.
- A `LocalizationEditor` UI for translators — out of scope; the JSON
  file is the editor surface.