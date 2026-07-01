# Domain 7: Travel / Procgen — design spec

**Date:** 2026-07-01
**Status:** approved in brainstorming; pending written-spec review.
**Loop:** `travel` (`system_inventory.json`), current `closes: "partial"` → target `"closed"`.
**Parent roadmap:** `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` (Domain 7).
**Predecessor:** Domain 6 (Progression & Meta) merged via PR #55; `progression.closes = "closed"`.

## Context

The `travel` loop is the procedural derelict-generation pipeline:

```
ShipBlueprint + archetype
  → TemplateSelector   → RoomAssigner (+ RoomVariantSelector)
  → CellLayoutEngine   → WallDoorResolver
  → LayoutSerializer   → GeneratedShipLoader   (scene)
GameplaySliceBuilder populates the gameplay arrays on top.
```

It is graded `partial` because generated derelicts do not actually **vary** in ways the
player experiences. During brainstorming the three inventory break-points were traced against
the live code, and **break-point #1 was found to be described inaccurately** — that finding
reshapes the domain and is recorded here so the roadmap can be corrected.

### Verified reality of the three break-points (2026-07-01 trace)

1. **Variant selection works; the *consumer* is missing.** The roadmap said
   `room_variant_selector` is "inert because `data/procgen/room_variants/` is ABSENT." That is
   wrong on the mechanism: `room_variant_selector.gd` is **not** data-driven from any directory —
   it holds a hardcoded `VARIANTS_BY_ROLE` table and *does* deterministically pick a variant per
   room. `room_assigner.gd:85-90` writes the variant into the room dict; `layout_serializer.gd:59`
   serializes it to `layout.json`. The true gap: **nothing reads the `variant` field.**
   `generated_ship_loader.gd` never consults a room's `variant` to build anything different (its
   90+ `*_variant` locals are Godot-typing idiom, not the room field). The variant string is
   decorative metadata. → **The domain's core work is to add consumers, not variant data.**

2. **Extended structural templates are switched off (accurate).** `ship_generator.gd:40` passes
   `extended_templates = false` to `layout_generator.generate_with_options(...)`, so the five extra
   template files (`compact`, `dispersed`, `stacked_v2`, `derelict_a`, `derelict_b`) never enter
   live derelict generation. Only `spine`/`bifurcated`/`stacked` ship. `TemplateSelector`
   already has a `select_with_options(..., extended)` arm ready.

3. **Legacy `room_graph_generator.gd` is orphaned (accurate).** Referenced only by
   smokes/dumps/docs (grep-confirmed); not mounted in the live pipeline.

### Supporting facts confirmed during the trace

- `configure_run_context(biome_id, difficulty_id)` is called on every live generation path
  (`playable_generated_ship.gd:1826`, `:3745`, `:7163`), so `difficulty_id` is available inside
  `ship_generator.generate()` — difficulty-gating extended templates is a one-line change.
- The loader consumes hazard-zone arrays from the layout doc
  (`generated_ship_loader.gd:835 fire_zones`, `:880 arc_zones`, `:1044 breach_zones`), and
  `playable_generated_ship._build_fire_zones()` turns them into live hazards. So variant-seeded
  zones become **real gameplay**, not dead data. Today `gameplay_slice_builder.build()` returns
  `fire_zones`/`arc_zones`/`breach_zones` **empty** (`:105-107`) — that empty return is the hole
  variant hazard-seeding fills.

## Decisions locked (from brainstorming)

1. **Variant depth: tiered (sim + dressing).** Each variant may carry a small gameplay payload
   (`loot_bias`, `hazard {kind, weight}`) consumed by `gameplay_slice_builder`, AND a `dressing`
   hint consumed by `generated_ship_loader`.
2. **Catalog form: code selector.** The variant→effect mapping lives in code
   (`VARIANT_EFFECTS` in `room_variant_selector.gd`), **not** a JSON catalog. This overrides the
   project's data-driven-procgen convention deliberately, for speed. Consequence: the roadmap's
   literal "definition of closed #1" (a `data/procgen/room_variants/` directory) will not exist and
   **must be rewritten** (see Roadmap/Inventory reconciliation below).
3. **Extended templates: difficulty-gated on.** Enabled when `difficulty_id ∈ {deep_dive,
   hardened}`; standard difficulty keeps the 3-template pool. Precondition: validate all five
   extended template files generate a non-empty layout before enabling.
4. **Legacy generator: deprecate + document.** `room_graph_generator.gd` stays on disk, marked
   deprecated/test-only; inventory marks it deprecated and excludes it from completion %.
5. **Dressing scope: reuse existing props + scanner/HUD descriptor; no new art.** Where an existing
   structural-placement prop/kit matches a dressing hint, the loader selects it; where none exists,
   the variant surfaces as a scanner/HUD room descriptor. Stays inside the roadmap's
   "no visual/art polish" non-goal while keeping dressing observable.

## Non-goals

- No new art / prop scenes / meshes (dressing reuses existing assets or is descriptor-only).
- No JSON variant catalog (decision #2).
- No new templates authored — only enabling / validating the five that already exist.
- No changes to the deterministic layout geometry stages (TemplateSelector topology,
  CellLayoutEngine placement, WallDoorResolver) beyond turning on the extended arm.

## Design

### Component A — Variant effects get consumed (core work)

**A1. `VARIANT_EFFECTS` table + accessor (`room_variant_selector.gd`).**
A typed const mapping variant string → effect dict:

```gdscript
const VARIANT_EFFECTS: Dictionary = {
    "flooded":       {"sim": {"loot_bias": "salvage_cargo",       "hazard": {"kind": "breach", "weight": 0.6}}, "dressing": "water_plane"},
    "burned_out":    {"sim": {"loot_bias": "salvage_engineering", "hazard": {"kind": "fire",   "weight": 0.5}}, "dressing": "scorch"},
    "collapsed":     {"sim": {"loot_bias": "salvage_cargo",       "hazard": {"kind": "breach", "weight": 0.4}}, "dressing": "rubble"},
    "biomatter_crusted": {"sim": {"hazard": {"kind": "arc", "weight": 0.3}},                                    "dressing": "biomatter"},
    "contaminated":  {"sim": {"hazard": {"kind": "arc", "weight": 0.35}},                                       "dressing": "haze"},
    "refrigerated":  {"sim": {"loot_bias": "salvage_cargo"},                                                    "dressing": "frost"},
    # ... remaining mapped variants; unmapped variants → neutral no-op
}

# Returns the effect dict for `variant`, or an empty/neutral dict for unmapped variants.
func effects_for(variant: String) -> Dictionary:
    return VARIANT_EFFECTS.get(variant, {})
```

Exact variant→effect values are tuned in the plan; the *shape* is fixed here. Unmapped variants
(most cosmetic ones) resolve to `{}` = neutral, so the table stays sparse and only "dramatic"
variants carry a payload. `loot_bias` and `hazard` are each independently optional within `sim`.

**A2. Sim consumer (`gameplay_slice_builder.gd`).**
For each room, read its `variant`, call `selector.effects_for(variant)`, and apply the `sim` payload:

- **loot_bias:** when present, it overrides the role-derived `loot_table` for that room's salvage
  objective and/or loot container (today set purely by `_salvage_loot_table_for_role(role)` and
  container-index parity). Bias must reference a `loot_table` key that exists in
  `loot_tables.json` — the plan validates every referenced key.
- **hazard:** when present, a per-room RNG (seeded from `room_id` + blueprint seed) rolls against
  `weight`; on success, append one entry to the matching zone array (`fire_zones` for
  `kind:"fire"`, `breach_zones` for `kind:"breach"`, `arc_zones` for `kind:"arc"`), targeting that
  room, in the same schema the loader already consumes. This fills the arrays the builder currently
  returns empty. Seeding is deterministic → same seed produces identical zones.

The builder must be given the selector instance (or effect lookup) — inject it the same way
`RoomAssigner` receives the selector, keeping the builder pure/testable.

**A3. Dressing consumer (`generated_ship_loader.gd`).**
When materializing a room, read `variant`, look up `dressing`. If an existing structural-placement
prop/kit maps to that dressing id, select it during placement (no new asset authored). If no asset
exists, record the dressing/variant on the room's runtime metadata so the scanner/HUD can render a
room descriptor (e.g. "Flooded Corridor"). No new meshes are introduced by this domain.

### Component B — Difficulty-gated extended templates (`ship_generator.gd`)

Replace the hardcoded `false` at `ship_generator.gd:40`:

```gdscript
var extended: bool = _extended_for(difficulty_id)
var layout: Dictionary = layout_generator.generate_with_options(
    blueprint, archetype, biome_id, difficulty_id, extended)

func _extended_for(diff_id: String) -> bool:
    return diff_id in ["deep_dive", "hardened"]
```

**Precondition (done in the plan before flipping the flag):** run each of the five extended
template files (`compact`, `dispersed`, `stacked_v2`, `derelict_a`, `derelict_b`) through the full
pipeline and confirm a non-empty layout. Any malformed file is fixed or excluded in this domain —
never shipped broken. Standard difficulty keeps the current 3-template pool; danger tiers scale
structural variety, deterministically per seed.

### Component C — Legacy generator deprecation (`room_graph_generator.gd`)

Add a header banner:

```gdscript
# DEPRECATED 2026-07-01: orphaned from the live generation pipeline.
# Retained for reference / unit-test use only. Not mounted in any live path.
```

Its existing smoke (`room_graph_generator_smoke.gd`) stays green as a unit test but is labeled
test-only. Inventory marks the system deprecated and excludes it from completion %. Confirm (grep)
no live path imports it before labeling.

## Validation

New smoke `procgen_variation_smoke.gd` (pure-data; register marker in `06_validation_plan.md`):

1. **Variant variation:** two different seeds produce distinct room-variant sets; at `deep_dive`,
   distinct structural templates.
2. **Hazard seeding:** a room whose variant carries a `hazard` payload seeds the matching zone
   array in the slice (e.g. a `burned_out` room → a `fire_zones` entry); assert **determinism**
   (same seed → identical zones).
3. **Loot bias:** a room whose variant carries `loot_bias` yields a `loot_table` differing from the
   role-only baseline.
4. **Template gating:** extended templates engage at `deep_dive`/`hardened` and **stay off** at
   `standard`.
5. **Determinism:** same seed generated twice → byte-identical variant + template + zone output.

**Away-branch note:** generation is pre-run (not per-frame), so there is no `_process`
away-branch to wire. The domain's equivalent anti-regression guard is the **seed-determinism**
assertion (#2, #5) — the roadmap's `away_ticks=` requirement is satisfied in spirit by proving
generation output is stable per seed.

Full regression: run the bundle in `06_validation_plan.md`; must end `SYNAPTIC_SEA REGRESSION PASS`
with clean output. Then `tools/build_system_inventory.py --check` must pass.

## Roadmap / inventory reconciliation (anti-drift)

Because of decision #2 (code selector, no directory), update:

- **Roadmap** (`2026-06-28-completion-roadmap-design.md`, Domain 7): rewrite "definition of closed
  #1" from "`data/procgen/room_variants/` exists with real variant data the selector consumes" to
  "variant effects live in the `room_variant_selector` `VARIANT_EFFECTS` table and are consumed by
  `gameplay_slice_builder` (sim: loot_bias + hazard seeding) and `generated_ship_loader` (dressing
  + scanner descriptor)."
- **Inventory** (`system_inventory.json`): set `travel.closes = "closed"`; flip
  `room_variant_selector.output.live = true` with the consumer citations; add
  `gameplay_slice_builder` / `generated_ship_loader` as consumers; mark `room_graph_generator`
  deprecated and exclude from completion %; clear/rewrite the three `travel` break-points to the
  code-selector reality. Regenerate `SYSTEM_INVENTORY.md` + `system_map.html`.

## Definition of CLOSED (this domain)

1. Room variants produce **real** variation the player experiences: `loot_bias` changes loot and
   `hazard` seeds live zones (fire/breach/arc) consumed by the loader; dressing is observable via
   existing props or a scanner/HUD descriptor.
2. Extended structural templates are **enabled** at `deep_dive`/`hardened`, all five files validated
   to generate cleanly; determinism per seed preserved.
3. Legacy `room_graph_generator` is documented deprecated/test-only and excluded from completion %.
4. `procgen_variation_smoke.gd` passes with its registered marker; the full regression bundle ends
   `SYNAPTIC_SEA REGRESSION PASS`; `--check` passes; the inventory shows `travel` green.

## Risks

- **Loot-table key drift.** `loot_bias` must reference keys that exist in `loot_tables.json` — the
  plan validates every referenced key or the biased room silently falls back. Mitigation: smoke
  asserts the biased `loot_table` resolves to a real table.
- **Malformed extended templates.** One of the five files may not generate cleanly. Mitigation:
  the plan validates all five before flipping the flag; broken ones are fixed or excluded, never
  shipped on.
- **Hazard-zone schema mismatch.** Variant-seeded zone entries must match the exact schema the
  loader expects (`fire_zones`/`breach_zones`/`arc_zones` from the golden layouts). Mitigation:
  mirror an existing golden zone entry; smoke round-trips one through the loader.
- **Coordinator line drift.** Cited line numbers in `playable_generated_ship.gd` (~5500 lines,
  ~7600 with this trace) drift; cite `function:symbol` alongside line in the plan.
