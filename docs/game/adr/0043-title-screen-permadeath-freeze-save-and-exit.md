# ADR-0043: Title Screen, Permadeath Freeze, and Save & Exit

**Status:** Accepted
**Date:** 2026-07-01
**Domain:** Completion roadmap Domain 8 (save loop, closes: "partial" -> "closed")

## Context

The save subsystem's write half was live (autosave rotation, world.json via F5)
but the read half and the death-gate were dead code: load_from_slot had no
live caller, PermadeathResolver.record_death was never called, no title
screen existed anywhere, and AutosavePolicy.try_quicksave /
SaveLoadMenu.confirm_quicksave were unwired. See
docs/superpowers/specs/2026-07-01-domain8-save-persistence-design.md for
the full design.

## Decisions

### 1. Title screen is a new bootstrap wrapper; main.tscn is unchanged

scenes/title_main.tscn / scripts/title_main.gd become the new
run/main_scene. They instantiate scenes/main.tscn (unchanged) as a child
only on New Game / Continue. This means every existing main-scene smoke
(which preloads res://scenes/main.tscn directly, not via project.godot's
run/main_scene setting) is entirely unaffected by this domain's boot-
sequence change.

### 2. Permadeath freezes, it does not delete

end_run("death") now calls _freeze_run_on_death() instead of deleting
world.json/autosaves. Every slot written this run -- the active-autosave
alias, world, every AUTOSAVE_SLOT_IDS row, the quickslot if present, and
any manual slot the player saved to this run (originally tracked in a
run-local _manual_slots_written_this_run set; superseded by the run_id
index ownership in section 7) -- gets a PermadeathResolver.record_death
entry. world.json and every slot's payload file stay on disk; a
<slot_id>.death.json record gates future loads (SaveLoadService.load_world /
load_from_slot both refuse a frozen slot).

**Why freeze instead of delete:** deleting the save would destroy the epitaph
browsing UX ADR-0032 explicitly designed for
(PermadeathResolver.load_epitaph) but never wired up. Freezing costs one
extra gate check (already-proven at load_from_slot:249) and lets the slot
screen render "DEAD -- <epitaph>" rows.

**Manual slots freeze too.** A mid-run manual save is a valid save of a run
that was alive at that moment, but the user-locked decision for this domain
is that permadeath must have no escape hatch: a manual save right before a
fatal encounter must not let the player reload past their death. Every
manual slot the slot screen's Save verb wrote to during the run that just
ended freezes along with the autosave family.

**Extraction/completion is unaffected** -- that path still deletes
(delete_current_run + autosave wipe), unchanged from before this domain. A
successfully finished run has nothing to "continue"; that is not permadeath.

**_apply_meta_payout_and_persist(reason) still runs unconditionally on
death.** This is deliberate and must not be "fixed" away in a future change:
meta progression (currency, unlocks, class gates) is explicitly cross-run
state per ADR-0007/ADR-0033 and survives permadeath by design -- only the
RUN's own save freezes, not the player's meta progress.

**New Game after a death does not touch the frozen slot.** A "forget this
death" action remains explicitly out of scope (ADR-0032 already scoped this
out as a seam, not a requirement); Domain 8 wires the freeze and the
epitaph-read path only.

**Reclaim-on-write.** `save_world()` and `save_to_slot()` both clear the
target slot's death record (`PermadeathResolver.clear_death(slot_id)`)
*after* the write to disk is confirmed (file opened, written, and closed
successfully) — **not** before opening the file. A death record describes
the run that died in that slot; a subsequent live run's system write
legitimately reclaims the slot for its own new run, but only once that
write has actually landed. Clearing before the write (the original
implementation) left a window where a locked/unwritable path made
`FileAccess.open` fail: the death record was already gone, the stale DEAD
payload was still on disk, and the slot silently read back as alive
(PR #57 Codex round 3 P2 finding). Ordering the clear after a confirmed
write closes that window — a failed write leaves the death record intact,
so `has_died_in(slot_id)` still gates the load. Without reclaim-on-write at
all, the first death in a slot family would permanently brick Continue and
that autosave slot for the lifetime of the save directory (final-review
finding: `clear_death` had zero production callers before this fix, so
`world.death.json`/`autosave_*.death.json` outlived every later save to
those paths). This does **not** reopen save-scumming: frozen MANUAL slots
are unwritable via the UI (frozen rows offer no verbs), and the load gates
(`load_from_slot`/`load_world`) fire before any write happens — a
still-frozen slot cannot be read back mid-death, only overwritten by a
genuinely new run.

**Freeze-set ownership (lineage gate, PR #57 Codex round 3 P1; corrected
round 4 P1) — superseded by §7 below.** This paragraph documents the
original flag-based mechanism for historical context; the fields and
functions it describes (`_persisted_lineage_active`, `_mark_shared_lineage()`,
`_manual_slots_written_this_run`) were deleted and replaced by the run_id
slot-ownership rework in §7 — read that section for the current design.
`_freeze_run_on_death()` used to only freeze the shared
lineage — the active-autosave alias, `"world"`, every `AUTOSAVE_SLOT_IDS`
row, and the quickslot — when THIS run instance actually owns that
lineage. Ownership is tracked by a run-local flag,
`_persisted_lineage_active`, marked true via `_mark_shared_lineage()` at
exactly two points: (a) a successful Continue/F9 world load (the loaded
world.json and its pre-existing autosave family become this run's
lineage), or (b) this run's first successful write to world.json or an
autosave slot. A brand-new run (New Game, no load, no save yet) that dies
has the flag false, so the shared lineage is left untouched — a
*different*, still-live Continue's world.json/autosaves must never be
stamped with an epitaph from a run that never wrote a byte to them.
**Manual slots never call `_mark_shared_lineage()`** (round 4 P1 fix — an
earlier version of this fix wrongly also marked the lineage on a manual
save, so a manual-only run that died before any world/autosave write still
froze the shared lineage and bricked a prior run's Continue). The
manual-slot set (`_manual_slots_written_this_run`) is exempt from the
lineage gate entirely: it is already write-tracked per slot (a slot id
only enters the set after this run wrote to it via the slot screen), so
freezing it is always correct independent of `_persisted_lineage_active`.

### 3. _input's post-death dead-zone is fixed

playable_generated_ship.gd:7548-7550 used to hard-return from _input
whenever slice_complete was true, which meant the player could not open
ANY menu after death -- including the frozen-slot epitaph screen this domain
adds. The fix moves the menu_coordinator.handle_ui_input(event) dispatch
ahead of the slice_complete gate; only the gameplay-input tail (hotbar,
attack, reload, F5/F9) stays gated on a completed run. This is a
pre-existing bug (present since slice_complete was introduced, not
something this domain's other changes caused), fixed here because Domain 8
is the first feature that needs post-death menu access to work.

### 4. Manual-slot loads are ship-only, not full-world (ADR-0031, implemented
at last)

Loading a manual slot from the interactive slot screen restores the active
ship's RunSnapshot only (apply_manual_slot -> _apply_run_snapshot). It
does **not** touch visited_ships, dock edges, world_time, or
current_location -- exactly ADR-0031's original text, never implemented
until now. RunSnapshot.parent_world_slot stays reserved/unused; resurrecting
it to validate a manual slot against a compatible world.json (schema for
compatibility, refusal UX, location-drift edge cases) is real additional
scope, explicitly deferred.

### 5. Save & Exit repurposes the pause menu, not quicksave

A new save_and_exit pause-menu item calls request_save() (the same
guarded world.json write path F5/autosave already use) and, on success,
emits return_to_title_requested. On failure it surfaces a tutorial toast
(registered as the tutorial_triggers entry save_and_exit_failed) and does
**not** leave -- silently losing progress on an exit action is unacceptable.

Save & Exit deliberately does **not** reuse AutosavePolicy.try_quicksave's
cooldown: that cooldown exists to stop autosave-cadence thrashing during
active play, not to gate a terminal "I am leaving" action. Gating the
player's exit-save behind a cooldown that could silently skip the write
would be a correctness footgun.

**Quicksave stays dead-but-harmless.** The roadmap's original Domain 8
"definition of closed" item 4 called for wiring
AutosavePolicy.try_quicksave/SaveLoadMenu.confirm_quicksave to a
keybinding. This is superseded: the game is heading toward a
multiplayer / Project-Zomboid-like persistent-world direction where
quicksave/quickload does not fit the design (see
docs/superpowers/specs/2026-06-28-completion-roadmap-design.md's amended
item 4). try_quicksave/confirm_quicksave remain small, model-smoked, and
available if a future package ships a real quicksave key.

**F5/F9 stay as dev/debug keys**, unchanged behavior, documentation-only
comment added at DEFAULT_SAVE_RUN_BINDINGS/DEFAULT_LOAD_RUN_BINDINGS.

### 6. Title settings is its own sub-flow, not a standalone settings file

The title screen's settings entry (spec §3.7) mirrors menu_coordinator's
in-run settings handling against the same settings_menu catalog entry,
rather than introducing a second settings system: confirm on settings
opens a title-local settings screen; ui_left/ui_right (and ui_accept on
non-back rows) drive a title-local _cycle_setting(direction) mirroring
menu_coordinator._cycle_setting (:339-360), including preset cycling from
accessibility_presets.json; back closes the screen. Row rendering mirrors
_settings_line (menu_coordinator.gd:707-717) minus the difficulty-multiplier
suffix, since no AccessibilitySettings instance exists at the title (no
active run yet).

**Persistence semantics:** settings persist only inside
RunSnapshot.settings_summary -- verified, no standalone settings file
exists anywhere in the codebase. The title flow therefore hands its summary
into the session rather than owning its own save file:
PlayableGeneratedShip gains a production seam
apply_ui_settings_summary(summary) (the existing
apply_ui_settings_summary_for_validation delegates to it), and title_main.gd
calls it after playable_started on BOTH New Game and Continue -- but only
if the player changed a setting at the title (a dirty flag), so an
untouched title screen never clobbers a loaded run's saved settings.

**A standalone user://settings.json layer is explicitly deferred**, called
out here as a future multiplayer card: once saves are per-character rather
than per-machine (the multiplayer/PZ-like direction referenced in decision
5), machine-local display/audio/accessibility preferences will need to
survive independently of any specific save slot. That is out of scope for
this domain -- title settings today only ever round-trips through whichever
RunSnapshot is active.

### 7. Freeze-set ownership rework: run_id replaces the lineage-flag/manual-set pair

**Problem.** PR #57 absorbed five review findings that all traced to one
root cause: the shared slot family (world, autosave_a/b/c, autosave_active,
quickslot) was owned "by convention" rather than structurally.
`_persisted_lineage_active` had to be set via `_mark_shared_lineage()` at
four separate coordinator call sites (request_load, request_save,
_auto_save_current_run, _tick_autosave_policy), and manual slots were
tracked in a parallel, independently-maintained `_manual_slots_written_this_run`
Dictionary that then had to be mirrored through
`WorldSnapshot.manual_slots_written` just to survive a Save & Exit ->
Continue boundary. Every one of the five findings was a call site
forgetting to set a flag, or setting it in the wrong branch. A convention
enforced by scattered call sites is exactly the kind of bug class that
recurs: the fix is to stop tracking ownership by flag and start tracking it
by what was actually written.

**New fields/APIs.** `RunSnapshot.run_id`, `WorldSnapshot.run_id`, and
`SaveSlotState.run_id` are additive `String` fields (empty default, same
`.get`-default pattern as `breach_seeded`). `SaveLoadService` gains
`_active_run_id` + `set_active_run_id(id)` / `get_active_run_id()`, and
stamps `_active_run_id` onto the payload and the index row inside
`save_world()`/`save_to_slot()` themselves -- no coordinator call site can
forget to stamp it, because stamping no longer happens at the call site at
all. `slot_ids_for_run(run_id)` returns every slot_id owned by that run;
an empty run_id matches nothing, so a run that has never loaded or saved
anything can never accidentally claim a match.
`freeze_run(run_id, cause, epitaph, run_time, final_seq)` resolves
`slot_ids_for_run(run_id)` and calls
`PermadeathResolver.record_death(...)` for each.

**Ownership is payload-authoritative, index-accelerated (PR #58 Codex
P2).** `slot_ids_for_run` unions two sources: matching index rows AND a
direct disk scan (`_all_slot_ids_on_disk` + `_payload_run_id`, which reads
only the top-level `run_id` key of each slot's payload file). The index is
a derived cache -- `list_slots()` already reclassifies it against the disk,
and a corrupt/missing `index.json` parses to an EMPTY `SaveIndexState`. If
freeze ownership trusted the index alone, losing the index (corruption,
manual deletion, partial sync) while `world.json` still loaded would mean
`freeze_run` writes no `world.death.json` and a dead run stays continuable
-- exactly the bug class this rework exists to kill, reintroduced through a
side door. The payload stamp written by `save_world()`/`save_to_slot()` is
the source of truth; the index row is a fast path, never the gate.

**Why `freeze_run` lives on `SaveLoadService`, not `PermadeathResolver`.**
`PermadeathResolver` is deliberately index-blind pure file I/O (death
records live at `<slot_id>.death.json`, resolved by slot_id alone, with no
knowledge of which run wrote what). `SaveLoadService` already owns the
index (`_load_index`/`_save_index`, `SaveIndexState`), so it is the only
place that can answer "which slots does this run_id own" without either
duplicating the index-reading logic on the resolver or making the resolver
reach back into service internals. Keeping the resolver index-blind also
keeps its contract simple for anything that only needs `has_died_in`/
`load_epitaph`/`record_death` on a single slot_id, independent of ownership
semantics.

**Coordinator side.** `PlayableGeneratedShip._run_id: String` replaces both
deleted fields. It is generated once per session
(`_generate_run_id() -> "%d-%04x" % [Time.get_ticks_usec(), randi() % 0x10000]`)
at the same point `save_load_service` itself is constructed, and stamped
into the service immediately via `set_active_run_id`. `_freeze_run_on_death()`
collapses to a single call:
`save_load_service.freeze_run(_run_id, "death", _build_epitaph_text(), world_time, current_objective_sequence)`.

**Legacy assign-on-load-fails-open rule (and the rejected alternative).**
On a successful Continue/F9 load (`request_load()`), `_run_id` is restored
from the loaded `WorldSnapshot.run_id` if non-empty, or a fresh id is
generated if the loaded save predates this field (`ws.run_id == ""`).
**Nothing is written to disk on load** -- the freshly generated id is only
stamped on this run's *next* save, exactly like every other save-time
stamp. This fail-open rule covers the ENTIRE pre-rework slot family, not
just `world.json`: every legacy row -- world, autosave_a/b/c,
autosave_active, quickslot, and any manual slot_NN -- carries
`run_id = ""` in both its payload and its index row, so
`slot_ids_for_run()` cannot match any of them under the fresh id. If the
player dies before making a single save under the new id, nothing (world
OR legacy manual slots) freezes. This fails OPEN and is an accepted,
documented gap (see "Known migration behavior" below) -- it is the direct
legacy-data analogue of the old "New Game with no load/save owns nothing"
case, and is no worse than what the flag-based design already accepted for
a brand-new run. Each slot re-enters ownership individually on its first
post-rework write.
**Rejected alternative: write-on-read.** An earlier draft considered
backfilling the id onto `world.json` immediately on load (so a legacy save
would freeze correctly even before its first post-rework save). This was
rejected: reads must not have write side effects on the save directory --
a load path that mutates disk state complicates every other assumption
about when saves change (corruption backups, cloud manifests, the
reclaim-on-write ordering) for a benefit that only matters for the single
run that first loads a pre-rework save. Do not reintroduce this.

**Deletions and why they are safe.** `_persisted_lineage_active`,
`_mark_shared_lineage()` (and its four call sites),
`_manual_slots_written_this_run` (and its population line in
`_dispatch_save_load_confirm_result`), and `WorldSnapshot.manual_slots_written`
are all deleted with zero remaining references (grep-verified). Every
behavior they implemented is now a direct consequence of
`slot_ids_for_run`/`freeze_run` reading what `save_world`/`save_to_slot`
already stamped -- there is no remaining call site that needs to "remember"
ownership, because ownership is no longer a separate piece of state to
forget.

**`.corrupt` interplay.** A slot quarantined to `user://saves/.corrupt/`
(via `_backup_corrupt_file`) keeps its `run_id` on the index row (only the
payload file moves; the index row is separately flagged `corrupt=true`, not
removed). If a dying run's own corrupt slot is still indexed under its
`run_id`, `freeze_run` still freezes it -- deliberate: a corrupted slot
belonging to a dead run should still read as dead, not silently become
loadable again because its payload happened to fail migration/parsing
before the death.

## Known migration behavior

Pre-Domain-7 ShipInstance summaries lack breach_seeded/fire_seeded
fields (default false on load -> benign re-seed on revisit), and Domain 7's
variant-list additions shift deterministic pick() results, so a
pre-Domain-7 world.json loaded through Title-Continue may re-roll room
variants on ships it had already visited. This is expected and
cosmetic-only -- cross-ref scripts/systems/ship_instance.gd:213-214. Domain
8 does not attempt to freeze historical variant rolls or force *_seeded
flags true on legacy loads.

## Consequences

- save.closes flips from "partial" to "closed" in
  docs/game/inventory/system_inventory.json.
- The roadmap's Domain 8 definition-of-closed item 4 is amended from
  "Quicksave keybinding/UI fires try_quicksave/confirm_quicksave" to
  "Save & Exit (pause menu) fires request_save and returns to the title
  screen; quicksave stays intentionally unwired per the multiplayer/PZ-like
  direction."
- main_playable_death_clears_autosave_smoke.gd is deleted (its
  cleared=true contract inverted) and replaced by
  permadeath_freeze_smoke.gd.
- Title settings ships as a sixth new smoke (title_settings_smoke.gd),
  registered in the regression bundle alongside the other five Domain 8
  smokes; no standalone settings file is introduced by this domain.
