# The Synaptic Sea — Project Status (source of truth)

**Last updated:** 2026-07-03

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

**Documented deferrals (deliberate, ADR-tracked — not broken):**
- **Audio asset library** (ADR-0044) — bus + pipeline are live with 2 placeholder clips;
  the full SFX/music/voice content pass is the roadmap's one sanctioned deferral. Also
  deferred there: spatial emitter population, ambient-zone reactivity, occlusion raycast.
- **Web-chart follow-ons** (ADR-0045) — chart visual/graphical pass (text rows today),
  chart-knowledge persistence (session-only by decision), hazard tooltips (catalog
  entries exist, smoke-only).
- **Fire B2** — deliberate-vent control + decompression danger, fire-consumes-oxygen,
  door-gated spread (deferred since M7-B).

**Content/polish (known-future, not gaps):** bespoke enemy behaviors + bosses, real audio
assets, derelict structural-template variety, explorable hub scene, real cloud saves,
visual/art pass.

With the loops closed, the next call is the one the audit anticipated: vertical-slice
content pass vs. horizontal polish — now unblocked.

## Quarantined / do-not-trust docs

Moved to **`docs/archive/`** (see `docs/archive/README.md`). They invented a Gate 0–5
pipeline, a shipped RC, macOS-only paths, "not a git repo," and "all-validated" claims:
`08_milestone_gates.md`, `09_system_roadmap.md`, `PLANNING_SYNTHESIS.md`, `build-plan.md`,
`PROJECT_WORKSPACE.md`.
