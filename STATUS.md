# The Synaptic Sea — Project Status (source of truth)

**Last updated:** 2026-06-28

This file is the entry point for "what is actually built and what's left." It exists
because the older roadmap docs were inaccurate and have been quarantined (see below).

## What this project actually is

A locked-isometric 3D space-horror **deep survival sim** (Godot 4.6.2, GDScript) — a
"Project Zomboid in space." It is **mid-development / pre-alpha**, actively closing the
last simulation loops before a real vertical slice. It is **not** a shipped release,
despite what the archived "Gate 5 RC" docs claim.

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
| `docs/game/adr/` | Architecture decisions (current: ADR-0041 fire-as-persistent-hazard, ADR-0042 sanity). |
| `docs/superpowers/specs/` + `plans/` | Real dated design docs (the M7-A/M7-B-era work). |

## Real milestone scheme

The trustworthy work uses an **M-lane + sub-project** scheme (e.g. **M7 = Ship systems &
sustenance infrastructure**, sub-projects A = life-support→vitals, B = fire suppression).
This is the scheme in the dated specs and git PRs #41–#46 — **not** the "Gate 0–5" or
"M1–M11 Persistence" numbering in the archived docs.

## What's left (from the canonical inventory, 2026-06-28)

> Source of truth for grades and completion %: **`docs/game/inventory/SYSTEM_INVENTORY.md`** (+ `system_map.html`). The rollup below is a human-readable summary; the inventory is authoritative.

**Recently closed (verified closed-loop):** sanity hallucinations (ADR-0042),
food eat→vitals, shields cut, procgen biome/encounter injection (PR #38), authoritative
fire hazard (M7-B / ADR-0041), derelict-side fire (PR #46), extinguisher/sealant
acquisition (PR #45).

**Open functional gaps:**
1. **Hull damage sources #1–3** (M7, 🟡) — `damage_compartment()` seam exists but combat
   hits / hazard cascades / deep-dive pressure don't call it yet (breaches are config-injected only).
2. **Sustenance is HUD-only** (M7, 🔴) — consumes the farm/cook chain but feeds no real player vital.
3. **Hydroponics / synthesizer / water-recycler** (M2, 🔴) — no live start/harvest; per-item
   spoilage stage not threaded into eating.
4. **Loot biome modifier** (M4) — `loot_quality_modifier` not applied to rolls (fast-follow).
5. **Skill-tree node effects** (M10, unverified) — do node unlocks do anything beyond hub upgrades?
6. **Audio triggers** (M9, unverified) — SFX/music fired by real events, or idle ambience?
7. **Fire B2 deferred** — deliberate-vent control + decompression danger, fire-consumes-oxygen, door-gated spread.

**Content/polish (known-future, not gaps):** bespoke enemy behaviors + bosses, real audio
assets, derelict structural-template variety, explorable hub scene, real cloud saves.

The audit's own framing: the build-order decision (vertical-slice vs. horizontal) is the
next call, waiting on this gap rollup.

## Quarantined / do-not-trust docs

Moved to **`docs/archive/`** (see `docs/archive/README.md`). They invented a Gate 0–5
pipeline, a shipped RC, macOS-only paths, "not a git repo," and "all-validated" claims:
`08_milestone_gates.md`, `09_system_roadmap.md`, `PLANNING_SYNTHESIS.md`, `build-plan.md`,
`PROJECT_WORKSPACE.md`.
