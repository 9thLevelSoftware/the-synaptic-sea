# The Synaptic Sea — Project Status (source of truth)

**Last updated:** 2026-07-22

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

## Pre-polish program (started 2026-07-22)

Source plan: system-by-system path to content-capable state (module integrity, not voxels).
Parallel decomposition: `docs/game/build-plans/pre-polish-parallel-wave-plan.md`.

**Wave 0 landed:**
- ADR-0051 module integrity (not voxels)
- Feature specs: `module_integrity`, `work_actions`, `component_slots`, `ship_modification`
- `SimKeys` contract + pure-system hot-path consumers (`sim_keys_smoke`)
- `TuningCatalog` shell + `data/balance/` (`tuning_catalog_smoke`)

**Wave 1 in progress:**
- PKG-A1a: `ShipRuntime` owns advance/catch-up; coordinator wrappers remain for smokes.

**Next critical path:** A1b snapshot composition → A1c away-branch collapse → A3 tick bands, then pillar packages.

## Quarantined / do-not-trust docs

Moved to **`docs/archive/`** (see `docs/archive/README.md`). They invented a Gate 0–5
pipeline, a shipped RC, macOS-only paths, "not a git repo," and "all-validated" claims:
`08_milestone_gates.md`, `09_system_roadmap.md`, `PLANNING_SYNTHESIS.md`, `build-plan.md`,
`PROJECT_WORKSPACE.md`.
