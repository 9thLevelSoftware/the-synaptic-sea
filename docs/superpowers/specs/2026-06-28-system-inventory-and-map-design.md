# System Inventory & Map — design spec

**Date:** 2026-06-28
**Status:** approved in brainstorming; pending written-spec review.
**Author:** code-verified inventory effort (post doc-quarantine, PR #47).

## Context

The project's roadmap/status documentation was found to be largely fictional and was
quarantined to `docs/archive/` (PR #47); `/STATUS.md` now points at
`docs/game/system_completion_audit.md` as the canonical, code-anchored status. But that
audit is explicitly a **partial second pass** — several systems carry unverified
`[?]`/`[P]` confidence flags, it covers only the simulation lanes it had time to trace,
and it is hand-maintained prose that can drift again.

The user's directive: **stop and do a full, accurate inventory so we can identify gaps and
build the proper systems/integrations without losing track again.** This spec defines that
inventory — a code-verified foundation that the subsequent vision reset and phased roadmap
will be built on.

## Goal

Produce a **complete, code-verified inventory** of every runtime system and subsystem,
graded on whether the simulation actually closes its loops, with a **derived completion %**
per system, rendered as both a human-diffable markdown document and a **legible interactive
HTML system map** — all generated from a single structured source so the map, the docs, and
the code can never silently disagree.

### Non-goals (explicitly deferred)

- **Vision/scope reset** — its own downstream spec, written against this inventory.
- **The phased roadmap** — its own downstream spec, sequenced from this inventory's gaps.
- **Fixing the gaps** — this effort *measures*; it does not wire/repair systems.
- Re-opening the (accurate) recent design docs under `docs/superpowers/specs/`.

## Decomposition

Three artifacts, built strictly in order; each only trustworthy if the prior is:

1. **System Inventory & Map** ← *this spec* (the code-verified foundation)
2. **Vision / scope reset** (north star, pillars, in/out of scope)
3. **Phased roadmap** (path to playable alpha → release)

## Architecture: single source of truth → generated views

```
docs/game/inventory/system_inventory.json   ← the ONLY maintained file (code-verified)
        │
        ▼   tools/build_system_inventory.py
        ├──► docs/game/inventory/system_map.html      (self-contained interactive map)
        └──► docs/game/inventory/SYSTEM_INVENTORY.md  (catalog + loops + matrix, for diffs)
```

- **Source of truth:** `docs/game/inventory/system_inventory.json`. Hand/code-maintained.
- **Generator:** `tools/build_system_inventory.py` (Python; matches existing `tools/` +
  Python smoke convention). Reads the JSON, emits both outputs. Has a `--check` mode (below).
- **Outputs are generated, never hand-edited.** A banner in each says so.
- **`system_map.html` is a single self-contained file** — vanilla JS with the inventory JSON
  embedded at build time, no CDN and no build step, so it opens offline by double-click.

### Anti-drift validator

`tools/build_system_inventory.py --check` exits non-zero (and is registered as a validation
smoke in `docs/game/06_validation_plan.md`) when:

1. The JSON cites a `file` that does not exist on disk.
2. A `simulation`-kind system still has `confidence: "?"` (inventory not actually finished).
3. A loop step or integration edge references a system `id` not in the catalog.
4. The committed `SYSTEM_INVENTORY.md` / `system_map.html` are stale vs. a fresh render
   (regenerate-and-diff). Marker: `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>`.

## Data model

`system_inventory.json` has two top-level arrays: `systems` and `loops`. Integration edges
are authored structurally inside each system's `integrations` array (the prose `input`/`output`
fields are human-readable detail; the structured `integrations` edges are what the generator
flattens into the matrix and any graph — they reference real system `id`s, not prose).

### System entry

One per runtime script under `scripts/systems/`, `scripts/procgen/`, `scripts/tools/`,
`scripts/ui/`, etc. Systems may nest `subsystems` (same shape).

```jsonc
{
  "id": "vitals_state",
  "file": "scripts/systems/vitals_state.gd",
  "name": "Player Vitals",
  "domain": "survival",          // survival|food|combat|loot|ship_systems|progression|
                                 // ui|audio|save|procgen|infra
  "kind": "simulation",          // simulation|ui|infra|tooling
  "model_exists": true,
  "smoke": "scripts/validation/vitals_state_smoke.gd",
  "reachable": true,
  "driven": true,
  "driven_at": "playable_generated_ship.gd:4213",
  "coupling": "closed",          // closed | half | hollow | na
  "input":  { "desc": "temp mult, radiation drain, status mult, moving",
              "at": "playable_generated_ship.gd:4206-4212" },
  "output": { "desc": "death + HUD + sanity feed", "at": "playable_generated_ship.gd:4213" },
  "confidence": "V",             // V verified | P probable | ? untraced
  "loops": ["survival_vitals"],
  "integrations": [              // structured directed edges OUT of this system
    { "to": "hallucination_director", "via": "sanity feed",
      "at": "playable_generated_ship.gd:4213", "health": "healthy" }
  ],
  "content": "partial",          // none | partial | sufficient
  "content_note": "vitals tuning exists",
  "gaps": [],
  "subsystems": []               // optional nested system entries
}
```

### Loop entry

One per player-facing loop (survival, food, combat, repair/ship-systems, loot, travel,
progression, fire, sanity, save).

```jsonc
{
  "id": "survival_vitals",
  "name": "Survival / Vitals",
  "closes": "closed",            // closed | partial | broken
  "steps": [
    { "system": "radiation_state",        "role": "source" },
    { "system": "vitals_state",           "role": "core" },
    { "system": "hallucination_director", "role": "sink" }
  ],
  "break_points": []             // prose: where the loop fails, if it does
}
```

### Integration edge

Authored inside each system's `integrations` array as a directed edge **out** of that system
(`to` references another system's `id`). The generator flattens all systems' `integrations`
into the global edge set that drives the matrix view and any graph rendering.

```jsonc
{ "to": "vitals_state", "via": "health drain",
  "at": "playable_generated_ship.gd:4209", "health": "healthy" }
  // health: healthy | weak | broken   (broken = declared/intended but no live data flows)
```

## Grading rubric & completion %

Five layers (extends the existing audit's rubric, which is sound):

| Layer | Question | Weight | Score |
|---|---|---|---|
| 1 Model | Pure model + smoke exists? | 15 | 0 / 1 |
| 2 Reachable | Mounted in the live run? | 15 | 0 / 1 |
| 3 Driven | `tick()`/mutators called in the loop? | 15 | 0 / 1 |
| 4 **Coupled** | Live **input** AND live **output**? | 35 | input 17.5 + output 17.5 |
| 5 Content | Enough authored data to exceed a tech demo? | 20 | none 0 / partial 0.5 / sufficient 1 |

`completion_pct = round( Σ(weight × score) )`, computed by the generator — **never hand-typed.**

**Coupling grade** (column 4, the gap dimension, drives node/card color):

- 🟢 `closed` — live input **and** live output verified.
- 🟡 `half` — one side live, the other dead (HUD-text-only / test-seam-only).
- 🔴 `hollow` — ticked, but no live source **and** no live gameplay sink.
- ⚪ `na` — infra/release/tooling; excluded from completion math, carries `functional: y/n`.

**Hollow-output cap (decided):** while a system's output is hollow (🔴), its
`completion_pct` is **capped at 50%**, so color and % never tell contradictory stories. The
cap is applied by the generator, not authored.

**Parent rollup:** a system with `subsystems` takes `completion_pct = mean(subsystem %)`.
Leaves use the layer formula.

**Confidence** is first-class. `V` = traced to cited lines this pass; `P` = strong evidence,
not exhaustively traced; `?` = not yet traced (must not survive into a "done" inventory for
any simulation system). The generator surfaces confidence in every view so "we haven't
checked this yet" is visible, never implied.

## Views (rendered in `system_map.html`)

1. **Card grid (primary).** Domains as sections; each system a card with name, coupling dot,
   completion bar + %, and subsystem count. Filter chips (coupling, `<50%`, infra, show
   subsystems); sort by completion. The everyday "what's incomplete" view.
2. **Integration matrix (tab).** Systems × systems DSM; each cell an integration colored by
   health (healthy/weak/broken); empty = no dependency; diagonal blocks = loop clusters.
   The "trace what-feeds-what" view. Scales to 100+.
3. **Detail panel (on card/cell click).** File path, the five-layer breakdown with cited
   lines, integration in/out lists, and confidence flag.

Markdown (`SYSTEM_INVENTORY.md`) mirrors the same data as tables: per-domain catalog, loop
closure summary, and the integration matrix — chosen for clean PR diffs.

## Methodology — the deep code-verified pass

The coordinator `scripts/procgen/playable_generated_ship.gd` is the hub; almost every live
coupling is a cited line there (or in a sub-coordinator: `audio_manager`, `threat_manager`,
`menu_coordinator`). For each system:

1. Locate the script; confirm model + smoke (layer 1).
2. Find where the coordinator constructs and ticks/mutates it → `driven_at` (layers 2–3).
3. Trace its live **input** source and live **output** sink to cited lines (layer 4).
4. Judge content from the backing `data/` files (layer 5), conservatively.
5. Record subsystems and integration edges; set `confidence`.

Run in **checkpointed batches by domain**: survival → food → ship-systems → combat → loot →
consumables → progression → procgen → audio → save → ui → infra. ~110+ scripts; this is a
multi-session effort. **Every `simulation` system must reach `confidence: "V"`** before the
inventory is "done"; anything unverifiable stays `?` and visible, never guessed. The existing
`system_completion_audit.md` `[V]` rows are a starting hypothesis to re-confirm against code,
not trusted blindly.

## Relationship to existing docs

- `system_completion_audit.md` is **superseded** once this inventory is populated and every
  simulation system is `V`. At that point its prose is folded in / it is archived, and
  `/STATUS.md` + project `CLAUDE.md` repoint to `docs/game/inventory/`.
- Until then, the audit remains canonical (this inventory is "under construction").
- `data/integration/cross_system_integration_matrix.json` (the older declared-dependency
  matrix) is cross-checked during the pass: every declared dependency should map to a real
  edge here or be flagged `broken` (declared-but-unwired).

## Definition of done

1. `system_inventory.json` lists **every** runtime script (proven complete by a count check
   against the `scripts/` tree); every `simulation` system is `confidence: "V"`.
2. `tools/build_system_inventory.py` renders `system_map.html` + `SYSTEM_INVENTORY.md`; the
   `--check` smoke passes and is registered in `06_validation_plan.md`.
3. The HTML map opens offline, defaults to the card grid, and the matrix tab + detail panel
   work.
4. `/STATUS.md` and project `CLAUDE.md` repoint to the new inventory; the audit is folded/archived.

## Risks

- **Scale/time.** ~110+ scripts traced to cited lines is large; mitigated by domain batching
  and the `?`-blocks-done rule (partial inventory is honestly partial, not silently complete).
- **Coordinator churn.** Cited line numbers drift as `playable_generated_ship.gd` changes;
  mitigated by the `--check` smoke (file-existence + staleness) and by citing
  `function:symbol` alongside line where practical.
- **Content score subjectivity.** The one soft input; kept to none/partial/sufficient,
  cited, and conservative, and it cannot inflate a hollow system past the 50% cap.

## Out of scope

Vision reset, phased roadmap, and any system repair/wiring. This spec delivers the
measurement instrument only.
