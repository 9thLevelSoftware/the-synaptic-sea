# Phase 3 — Player Progression (Class + Skills) Design

Date: 2026-06-21
Status: Approved for implementation
Parent spec: `docs/superpowers/specs/2026-06-20-synaptic-sea-core-systems-design.md` (System 3)
Relates to: ADR-0007 (save/load scope — amended by a new ADR), ADR-0008 (ship-systems), ADR-0002/0003 (meta deferral — NOT touched)

---

## Goal

Add a player-progression system: data-driven **classes** that seed starting **skills** (0–10),
**XP** that raises skills with use (modified by class affinity), and the **repair** skill flowing
into the Phase 2 `ShipSystemsManager.repair()` path. Progression is current-run state and round-trips
through `RunSnapshot`. The system is a pure model in the `scripts/systems/*` family (Resources are
data, Nodes are behavior).

## Scope

**In scope:**
- Full ~20-skill catalog across 5 categories (data).
- All **8** class definitions (data), each with complete starting skills + per-category XP multipliers.
- A `PlayerProgressionState` pure model: skills, per-skill XP, deterministic level-up, save/load round-trip.
- The `repair` skill fed into `ShipSystemsManager.repair()` — proven at the model/manager level
  (`min_skill` gating + skill-scaled repair time).
- A live XP hook: completing a repair-type objective grants `repair` XP; the player's repair skill is
  shown on the HUD.
- `player_progression_summary` added to `RunSnapshot` (`SUMMARY_FIELDS` 7→8) + a new ADR amending ADR-0007.

**Out of scope (deferred — consumers do not exist yet):**
- Learnable-ability skill tree / ability nodes (no abilities to gate).
- Training via books/mentors (needs the Phase 6 item system).
- Diagnose skill-check UI.
- Runtime effects of non-`repair` skills (medical/scanner/social/etc. systems).
- Retiring `force_repair` in the live bridge — stays until Phase 6 brings parts/tools so the full
  gated `repair()` is drivable in the live game.

---

## Architecture

```
PlayerProgressionState (RefCounted, pure model)   scripts/systems/player_progression_state.gd
    ├── class_id : String
    ├── skills    : { skill_id -> level (0..10) }
    ├── skill_xp  : { skill_id -> xp toward next level }
    └── skill_category : { skill_id -> category }   (from the skills catalog)

ClassDefinition (RefCounted, data loader)          scripts/systems/class_definition.gd
    from_dict(d) ; static load_all(path) -> { class_id -> ClassDefinition }

data/player/skills.json    skill catalog: skill_id -> { category, display_name }
data/player/classes.json   8 classes: { class_id, name, description, starting_skills, xp_multipliers }
```

The coordinator (`scripts/procgen/playable_generated_ship.gd`) owns one `PlayerProgressionState`,
configures it from a chosen class, grants `repair` XP on repair-objective completion, surfaces the
repair skill on the HUD, and includes the progression summary in the run snapshot.

### `PlayerProgressionState` interface

```gdscript
const MAX_SKILL_LEVEL := 10

func configure(class_def, skills_catalog: Dictionary) -> void
    # Seeds skills from class_def.starting_skills (others default 0), records skill->category
    # from the catalog, and resets skill_xp to 0.

func get_skill_level(skill_id: String) -> int       # 0 if unknown
func get_class_id() -> String

func grant_xp(skill_id: String, amount: int) -> bool
    # Applies the class category multiplier, accumulates skill_xp, and levels the skill up on the
    # curve (capped at MAX_SKILL_LEVEL). Returns true if the level changed. Unknown skill -> false.

static func xp_for_next_level(level: int) -> int     # (level + 1) * 100

func get_summary() -> Dictionary                      # { class_id, skills, skill_xp }
func apply_summary(summary: Dictionary) -> bool       # restores class_id/skills/skill_xp; ignores unknown keys
```

`xp_multipliers` are **per category**, not per skill. `grant_xp("repair", n)` looks up `repair`'s
category (`technical`) and multiplies `n` by the class's `technical` multiplier. Specialty categories
are >1.0 (faster); cross-training categories are <1.0 ("costs more" XP). No RNG — fully deterministic.

### `ClassDefinition` interface

```gdscript
var class_id: String
var display_name: String
var description: String
var starting_skills: Dictionary   # skill_id -> int
var xp_multipliers: Dictionary    # category -> float

static func from_dict(d: Dictionary) -> ClassDefinition
static func load_all(path := "res://data/player/classes.json") -> Dictionary  # class_id -> ClassDefinition
func xp_multiplier(category: String) -> float   # default 1.0 for an unlisted category
```

---

## Data

### Skill catalog (`data/player/skills.json`) — 5 categories × 4 skills

| Category | Skills |
|----------|--------|
| technical  | repair, diagnostics, fabrication, welding |
| medical    | first_aid, surgery, pharmacology, quarantine |
| navigation | piloting, astrogation, scanner_operation, signal_analysis |
| survival   | scavenging, cooking, construction, resource_management |
| social     | leadership, negotiation, intimidation, comms |

Each entry: `{ "skill_id": "...", "category": "...", "display_name": "..." }`.

### Classes (`data/player/classes.json`) — all 8

Per-category XP multipliers (technical / medical / navigation / survival / social):

| Class | tech | med | nav | surv | soc | starting skills (level) |
|-------|------|-----|-----|------|-----|--------------------------|
| engineer | 1.5 | 0.7 | 1.0 | 1.0 | 0.8 | repair 3, diagnostics 2, welding 2, fabrication 1 |
| mechanic | 1.5 | 0.7 | 0.9 | 1.1 | 0.8 | repair 4, welding 3, fabrication 1, scavenging 2 |
| medic | 0.7 | 1.5 | 0.8 | 1.0 | 1.2 | repair 1, first_aid 3, pharmacology 2, surgery 1, quarantine 2 |
| pilot | 1.0 | 0.8 | 1.5 | 1.0 | 1.0 | repair 1, piloting 3, astrogation 2, scanner_operation 1 |
| scientist | 1.2 | 1.0 | 1.2 | 0.7 | 0.9 | repair 2, diagnostics 2, signal_analysis 2, pharmacology 1 |
| cook | 0.8 | 1.0 | 0.8 | 1.5 | 1.2 | repair 0, cooking 3, resource_management 2, scavenging 1 |
| security | 0.9 | 0.9 | 1.0 | 1.2 | 1.1 | repair 1, intimidation 2, construction 1, scavenging 1, leadership 2 |
| communications | 0.9 | 0.8 | 1.3 | 0.8 | 1.5 | repair 0, comms 3, signal_analysis 2, negotiation 1 |

Skills not listed for a class start at 0 (still trainable via cross-training XP). `quarantine`
(medic) and `leadership` (security) are seeded so every skill in the catalog is a starting skill on
at least one class — `class_definitions_smoke` asserts this coverage. Any category not listed in a
class's `xp_multipliers` defaults to 1.0. The default starting class for the live slice is
**engineer** (coordinator
`@export var starting_class_id`).

---

## Leveling

- `xp_for_next_level(level) = (level + 1) * 100` — level 0→1 needs 100 XP, 9→10 needs 1000.
- `grant_xp(skill_id, amount)`:
  1. `effective = round(amount * class.xp_multiplier(category_of(skill_id)))`.
  2. `skill_xp[skill_id] += effective`.
  3. While `level < MAX_SKILL_LEVEL` and `skill_xp[skill_id] >= xp_for_next_level(level)`: subtract
     the threshold, `level += 1`.
  4. At `MAX_SKILL_LEVEL`, stop leveling; excess XP is discarded (`skill_xp` pinned to 0 at cap).
  5. Returns whether the level changed.

Deterministic and order-independent for a given XP sequence.

---

## Integration with the live coordinator

- `_build_runtime_nodes()` constructs `PlayerProgressionState`, loads the skills catalog +
  `ClassDefinition.load_all()`, and `configure(...)`s it from `starting_class_id` (default `engineer`).
- **XP hook:** in `_on_interactable_completed`, when the completed objective is a repair type
  (`restore_systems` / `stabilize_reactor`), call `progression.grant_xp("repair", REPAIR_OBJECTIVE_XP)`
  (`REPAIR_OBJECTIVE_XP := 50`). This is the only live XP source in Phase 3.
- **HUD:** add a `Repair Skill: N` line to `_combined_system_status_lines()` sourced from
  `progression.get_skill_level("repair")`.
- **Reload:** `_reset_runtime_for_reload()` reconfigures progression from `starting_class_id`;
  `_apply_run_snapshot()` then restores it from the snapshot.
- `force_repair` is unchanged and remains the live repair mechanism (Phase 6 retires it).

### Skill → `repair()` (model-level proof)

`ShipSystemsManager.repair(system_id, sub_id, parts, tools, skill_level)` already gates on
`min_skill` (`insufficient_skill`) and scales returned `seconds` by `1 + 0.1*(skill_level-min_skill)`.
Phase 3 proves the wiring by passing `progression.get_skill_level("repair")` into `repair()` in a
smoke: below `min_skill` → rejected; at/above → succeeds with higher skill yielding shorter `seconds`.
The live game cannot run `repair()` end-to-end until Phase 6 supplies parts/tools.

---

## Persistence

- New field `player_progression_summary: Dictionary` on `RunSnapshot`, appended to `SUMMARY_FIELDS`
  (count 7→8). Serialized in `to_dict`/`from_dict` like the other summaries.
- `_build_run_snapshot()` writes `progression.get_summary()`; `_apply_run_snapshot()` restores via
  `progression.apply_summary(...)`.
- **ADR-0010** (new) amends ADR-0007 to record the added current-run field. Progression is current-run
  state; the deferred meta layer (ADR-0002/0003) is untouched.
- Save-smoke contracts that assert `summaries=7` move to `summaries=8`
  (`save_load_service_smoke.gd`, and any model that asserts the count).

---

## Testing

1. **Model smoke** `player_progression_state_smoke.gd`: configure from `engineer` seeds repair 3;
   `grant_xp` applies the class category multiplier (engineer technical 1.5: 100 raw → 150 effective);
   crossing `xp_for_next_level` raises the level; cap holds at 10; `get_summary/apply_summary`
   round-trips class_id + skills + skill_xp.
2. **Class data smoke** `class_definitions_smoke.gd`: `load_all` returns all 8 classes; each has the
   expected `xp_multiplier` category keys and starting skills; unknown category defaults to 1.0.
3. **Skill→repair smoke** `progression_repair_integration_smoke.gd`: a low repair level below a
   subcomponent's `min_skill` → `repair()` returns `insufficient_skill`; raising the level via
   `grant_xp` to ≥ `min_skill` → `repair()` succeeds and a higher skill returns a smaller `seconds`.
4. **Main-scene smoke** `main_playable_slice_progression_smoke.gd`: completing a repair objective
   raises `repair` XP (and the HUD shows `Repair Skill:`); save/load round-trips the progression
   summary (loaded skills/xp equal saved).
5. Register all four in the regression bundle (`docs/game/06_validation_plan.md`), `commands=50`→`54`.
   Full bundle must end `SYNAPTIC_SEA REGRESSION PASS ... clean_output=true`; Gate-1 playtest still passes.

---

## File structure

- Create: `data/player/skills.json`, `data/player/classes.json`
- Create: `scripts/systems/class_definition.gd`, `scripts/systems/player_progression_state.gd`
- Modify: `scripts/systems/run_snapshot.gd` (add field + SUMMARY_FIELDS), `scripts/procgen/playable_generated_ship.gd` (own/configure/XP-hook/HUD/save-load), `scripts/validation/save_load_service_smoke.gd` (summaries 7→8)
- Create: `docs/game/adr/0010-player-progression-current-run-persistence.md`
- Modify: `docs/game/06_validation_plan.md` (register 4 smokes, bump count)
- Create: the 4 validation smokes above

## Risk

Low. The model is pure and additive; the only live-runtime touch points are an XP hook on objective
completion, one HUD line, and the snapshot field — all guarded for a null progression model. The
`summaries=7→8` change ripples to save-smoke assertions (enumerated above) and is ADR-recorded.
