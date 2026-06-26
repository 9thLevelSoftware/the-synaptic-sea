# Save/Load Persistence — Tuning Notes (Task 11)

Authored by sargassoworker on 2026-06-25 as part of Task 11
(Save/Load, Persistence, Multi-Slot, Auto-Save & Cloud Readiness).

These numbers are picked to keep the persistence layer cheap (no
per-frame autosave thrash) and forgiving (corruption never silently
destroys a run).

## Autosave cadence

| Knob | Default | Rationale |
|---|---|---|
| `AutosavePolicy.cadence_seconds` | `90.0` (in-game seconds) | Long enough that the player can complete a meaningful section between autosaves, short enough that no more than ~90 s of progress is at risk. Tuned for a 5-minute derelict run: ~3 autosaves per run is acceptable. |
| `AutosavePolicy.cadence_events` | `8` events | Event-count trigger fires when the player is interacting heavily (looting, repairing, opening dock ports) so a busy minute still captures state. |
| `AutosavePolicy.min_real_interval_seconds` | `5.0` (wall-clock seconds) | Budget guard so a pathological tick rate (e.g. a 1000-Hz physics step) does not produce a save storm on disk. |
| `AutosavePolicy.slot_rotation` | `["autosave_a", "autosave_b", "autosave_c"]` | REQ-SL-006 caps autosaves at 3 per save family. The previous autosave is preserved as `autosave_b` so the player always has at least the two most recent autosaves available after a third save fires. |

## Quicksave cooldown

| Knob | Default | Rationale |
|---|---|---|
| `AutosavePolicy.quicksave_cooldown_seconds` | `10.0` (wall-clock seconds) | Prevents quicksave spam from wearing out the disk. The 10 s value matches industry convention (Project Zomboid, Darkest Dungeon). |

## Slot retention

| Family | Slot ids | Count |
|---|---|---|
| Manual | `slot_01`..`slot_06` | 6 |
| Autosave | `autosave_a`..`autosave_c` | 3 |
| Quicksave | `quicksave` | 1 (overwritten) |
| World | `world` | 1 (ADR-0012 multi-ship) |
| Death | `<slot_id>.death.json` | 1 per frozen slot (cleared manually or via future menu) |

Six manual slots is a deliberate compromise: enough for save-scumming
across the 4-base-derelict+home configuration without bloating the
saves directory. If a future UX study shows players want more, the
cap is `MANUAL_SLOT_IDS` in `save_slot_state.gd` — change one line and
the migration step is a no-op (slot ids are data, not paths).

## Corruption backup retention

| Knob | Default | Rationale |
|---|---|---|
| `.corrupt/` retention | 1 backup per slot (overwritten on next corruption) | We keep the most recent corrupt file for that slot so the player (or a reviewer) can diagnose. Older corruptions for the same slot are overwritten when the slot fails again. This keeps `.corrupt/` from growing unbounded. |
| `user://saves/.cloud/<slot_id>.manifest.json` | overwritten every save | The manifest's `payload_sha256` is the source of truth for "this file is exactly what I wrote". Re-uploading to a cloud adapter is a future concern; today the manifest is the contract the adapter will read. |

## Difficulty presets

Difficulty currently affects save-validity through the in-game systems
manager, not through the save layer itself. The persistence layer
treats all difficulty presets identically (the slot payload is a
full snapshot; the live state is restored verbatim). Future work
might add a `difficulty` field on `RunSnapshot` — that change is
covered by the migration chain (v3 -> v4 will add it as an optional
default).

## Tuning feedback

If any of these defaults feel wrong in playtest, change them on the
class default (e.g. `AutosavePolicy.cadence_seconds = 60.0`) — no ADR
required, no migration required, no smoke changes required. The
existing smokes assert the *behavior* (cadence triggers at the
configured value, rotation advances, cooldown rejects the second
quicksave) so they will keep passing as long as the behavior holds.