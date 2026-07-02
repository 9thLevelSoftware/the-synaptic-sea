# ADR-0044: Audio bus layout registration and caption settings unification

**Status:** Accepted
**Date:** 2026-07-02
**Supersedes:** nothing — extends ADR-0029 (audio/music/spatial architecture).
**Roadmap source:** `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` Domain 9 (`audio_reactive` loop, bus + pipeline scope).

## Context

ADR-0029 built a rich audio architecture — six pure models plus an `AudioManager`
node, ticked on both `_process` branches, with a full save/load round-trip — but
it was structurally silent:

- No `AudioBusLayout` was registered in `project.godot`; `AudioServer.get_bus_index`
  returned -1 for every named bus, so every volume push was inert.
- No `AudioStream` was ever assigned and `.play()` was never called anywhere in
  the 8 audio scripts. Zero audio assets existed.
- Captions never reached the player: `pump_captions`/`drain_captions` had zero
  gameplay callers.

This ADR documents the four architectural decisions made to close that gap
(Domain 9 of the completion roadmap), without expanding scope into the full
asset library, spatial emitter population, or ambient-zone reactivity — all of
which remain explicit, documented deferrals.

## Decision 1: AudioBusLayout / AudioBusConfig split of authority

Two tables now describe the bus graph, each owning a different half:

- **`data/audio/default_bus_layout.tres`** (a real Godot `AudioBusLayout`
  resource, registered via `project.godot`'s `[audio]` section) owns
  boot-time bus **existence and hierarchy** — which buses exist, what each
  sends to, at engine startup. This is the table Godot's `AudioServer`
  actually reads.
- **`AudioBusConfig`** (the existing pure `Resource`, unchanged in shape)
  keeps owning runtime **state** — volumes, mutes — and the save/load round
  trip via `RunSnapshot.audio_summary`.

The two tables must agree (volumes mirror `AudioBusConfig.make_default()`
exactly: sfx -3, music -6, voice -3, ui -6, ambient -9, meta -6; Master is
engine bus 0 at 0 dB). Any bus add/remove/rename must update both tables in
the same PR. No engine-level cross-check enforces this automatically —
`scripts/validation/audio_pipeline_smoke.gd` is the drift guard, asserting
`AudioServer.bus_count == 7` and per-bus name/volume agreement with
`AudioBusConfig.make_default()` at boot.

`data/audio/audio_bus_config.tres` (a pre-existing, orphaned custom Resource
file that nothing loads) is kept as-is and documented here as an orphan;
building a loader for it is out of scope for this ADR.

## Decision 2: Master-name translation at the AudioServer boundary

Godot's bus 0 is immutably named `"Master"` (capital M) and cannot be
renamed; `AudioServer.get_bus_index("master")` (lowercase, matching the pure
model's `AudioEventSeam.BUS_MASTER`) always returns -1. Rather than rename
the pure model's bus id (which would ripple through save summaries, the
settings panel, and `AudioBusConfig`'s own validation), `AudioManagerScript`
gained a single private translation function, `_engine_bus_name(bus_id) ->
String`, used at the one `AudioServer` boundary call (`_apply_bus_volumes`).
The pure model keeps lowercase `master` everywhere; only the engine boundary
translates. The six child buses need no translation — their names already
match between the pure model and the engine.

## Decision 3: `load_from_file` placeholder clips + the stream registry

A probe run on this machine (headless, Godot 4.6.2) confirmed
`AudioStreamWAV.load_from_file()` is available and works at runtime, without
the editor's asset-import pipeline (no `.import`/`.uid` churn). This was
chosen over the alternative — committing clips through the editor's normal
import flow — because:

- The editor import pipeline requires opening the project in `--editor`
  mode at least once, which this machine's Godot binary is known to mutate
  (`project.godot` autoload injection) outside of controlled, surgical
  edits.
- `load_from_file()` keeps the two placeholder clips as plain committed
  `.wav` files with zero generated `.import` sidecar noise, which matches
  the "deterministic, regenerable placeholder" spirit the roadmap asked for
  (`tools/generate_placeholder_audio.py` regenerates byte-identical output
  on every run).

Two clips prove the path: `data/audio/sfx/tool_pickup.wav` (backs
`sfx.tool.pickup`, a live gameplay callsite at item pickup) and
`data/audio/music/exploration_base.wav` (backs music layer `layer.base`,
always-on in the default EXPLORATION state).

`AudioManagerScript` gained `const STREAM_CATALOG: Dictionary` (event/layer
id → `res://` path) and a path-keyed `_loaded_streams` load cache. The
catalog lives in the **manager**, not in `SfxEventRouter` — the router
stays a pure `RefCounted` per ADR-0029 (the manager remains the only
scene-aware audio object). Events not in the catalog behave exactly as
before this ADR (volume push only, no stream) — the honest, deferred-asset
fallback. A missing or corrupt file at runtime logs exactly one
`push_warning` per path (never per-frame spam) and falls back to
streamless behavior; it never crashes.

## Decision 4: SettingsState caption unification + panel bug fix

`SettingsState.captions` (already the schema-backed, save-persisted field
used by the in-game settings menu and the title screen) is now the single
source of truth for `SfxEventRouter.captions_enabled`. The push happens at
one seam, `playable_generated_ship.gd::_on_ui_settings_changed`, which all
three apply paths already funnel through via `menu_coordinator.settings_changed`:

1. In-game settings cycle (`menu_coordinator._cycle_setting` → emit)
2. Title handoff (`title_main.gd` → `apply_ui_settings_summary` →
   `apply_settings_summary` → emit)
3. Save/load restore (`_apply_run_snapshot` → `apply_settings_summary` → emit)

This also fixes a latent pre-existing bug in `AudioSettingsPanel`: the
captions checkbox gated on `audio_manager.has_method("sfx_router")`, which
is always `false` — `sfx_router` is a property, not a method — so the
checkbox never synced from or wrote back to any state. The panel now takes
a `settings_state` reference (injected by `MenuCoordinator.bind_meta_screens`,
which already owns a `settings_state` instance) and reads/writes through
`SettingsState.is_captions_enabled()` / `set_captions_enabled()`.

Final-review fix: the panel's first pass at this also wrote
`audio_manager.sfx_router.captions_enabled` directly on toggle, which was a
fourth path around the single-seam invariant below. The panel now mutates
ONLY `settings_state`, then calls a `Callable` (`set_settings_push()`,
injected by `MenuCoordinator.bind_meta_screens` alongside
`set_settings_state()`) whose implementation
(`MenuCoordinator._emit_settings_changed`) emits `settings_changed` with the
current `get_settings_summary()` — the same emit shape
`_cycle_setting()` already uses. `_on_ui_settings_changed` in
`playable_generated_ship.gd` remains the only writer of
`sfx_router.captions_enabled`.

The panel's voice-log toggle remains a known no-op stub, unchanged by this
ADR — a separate concern, explicitly out of scope here.

**Save/load restore ordering invariant.** On snapshot restore, the two
persisted summaries are applied in a fixed order:
`apply_settings_summary` (which pushes `SettingsState.captions` into
`sfx_router.captions_enabled` per path 3 above) runs **before**
`audio_manager.apply_summary(audio_summary)`, which separately overwrites
`sfx_router.captions_enabled` from the audio summary's own persisted value.
The audio-summary write always wins at restore time. This is safe — the two
persisted values can never disagree at the moment a save is written —
**only because every live write path to `sfx_router.captions_enabled`
funnels through `SettingsState` first** (paths 1–3 above); there is no
write path that sets the router flag without first updating
`SettingsState`. Any future code that writes `sfx_router.captions_enabled`
directly, bypassing `SettingsState`, would silently break this invariant by
letting the two summaries diverge before the next save — do not add one.

## Retained deferrals (explicitly out of scope)

- Full SFX/music/voice asset library (a later content pass; only two
  placeholder clips exist).
- Spatial emitter population (`play_sfx` with a `position` argument has a
  live code path, but no gameplay callsite passes one yet).
- Ambient-zone reactivity (`set_room_role`/`set_threat_level` stay uncalled
  from gameplay).
- A loader for the orphaned `data/audio/audio_bus_config.tres`.
- The `AudioSettingsPanel` voice-log toggle stub.
- Occlusion raycast (the deterministic distance/Y-band heuristic in
  `AudioManager._is_occluded` stays as a placeholder).

## Validation

`scripts/validation/audio_pipeline_smoke.gd` is the single smoke covering all
four decisions end-to-end; it is registered in the regression bundle as
`AUDIO PIPELINE PASS bus_index=true stream_playing=true caption_hud=true
captions_toggle=true away_ticks=30`. The `captions_toggle=true` stage was
added after the Task 5 review found the unified caption push (Decision 4)
had no direct regression coverage — the original smoke only asserted the HUD
line rendered once, not that the settings seam actually drove the router
flag. The stage now drives the settings seam end-to-end (toggling
`SettingsState.captions` through the same `_on_ui_settings_changed` path
gameplay uses) and asserts `sfx_router.captions_enabled` follows it in both
directions (on → off and off → on), closing that coverage gap.

## Consequences

- Bus volume pushes are no longer inert in any run mode (headless or
  windowed) — this was previously true even outside headless tests.
- Two real audio events are now audible end-to-end: picking up a tool, and
  the always-on exploration music base layer.
- Captions reach the HUD (`Caption: <text>` line in the combined system
  status lines) on both `_process` branches, gated by the same
  `SettingsState.captions` flag the settings menu already exposes.
- The dual bus-table split (Decision 1) is a structural risk without an
  engine-level cross-check; `audio_pipeline_smoke.gd` is the only guard
  against drift and must be kept current if buses are ever added, removed,
  or renamed.
- The save/load restore ordering (Decision 4) is a structural risk in the
  same vein: it stays correct only as long as `SettingsState` remains the
  sole write path to `sfx_router.captions_enabled`. Reviewers should treat
  any new direct write to that property as a regression against this ADR.
