# Phase 3 Player Progression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a data-driven player-progression system (8 classes, ~20 skills, XP/level-up) whose `repair` skill feeds the Phase 2 `ShipSystemsManager.repair()` path, with a live XP hook + HUD line and current-run save/load.

**Architecture:** A pure `RefCounted` model `PlayerProgressionState` (skills + per-skill XP + skill→category map) and a `ClassDefinition` data loader, both in the `scripts/systems/*` family (Resources are data, Nodes are behavior). Two JSON data files define skills and classes. The coordinator owns one progression model, grants `repair` XP on repair-objective completion, shows the repair skill on the HUD, and round-trips it through `RunSnapshot`.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless validation smokes (each "test" is a `SceneTree`/`--script` smoke printing a `PASS` marker — the marker is the contract).

## Global Constraints

- Godot binary (headless console): `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe`
- Project root: `C:/Users/dasbl/Documents/The Synaptic Sea`
- Smoke run pattern (Git Bash):
  ```bash
  GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
  ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
  "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd
  ```
- **`--script` exits 0 on parse/load errors** — proof is the literal `PASS` marker line in stdout AND no `Parse Error`/`SCRIPT ERROR`/unexpected `ERROR:`/`WARNING:`. Allowlisted noise: `ERROR: Capture not registered: 'gdaimcp'.`, `WARNING: ObjectDB instances leaked at exit ...`, and (save smoke only) `WARNING: SaveLoadService: save file rejected by from_dict ...`.
- In a `SceneTree` smoke, `quit()` does NOT halt the frame loop — every failure path must `return` after `quit(1)`.
- `class_name` globals are unreliable under `--headless --script`; reference cross-file scripts via `preload(...)` const Script vars; avoid `class_name` return-type annotations on cross-file calls.
- Typed GDScript for new code. Conventional Commits. Branch: `phase3-player-progression`.
- Skill levels are ints in `[0, 10]` (`MAX_SKILL_LEVEL = 10`). XP curve: `xp_for_next_level(level) = (level + 1) * 100`. XP multipliers are per **category** (technical/medical/navigation/survival/social); an unlisted category defaults to `1.0`. No RNG anywhere — fully deterministic.
- Categories and their skills are fixed: technical{repair,diagnostics,fabrication,welding}, medical{first_aid,surgery,pharmacology,quarantine}, navigation{piloting,astrogation,scanner_operation,signal_analysis}, survival{scavenging,cooking,construction,resource_management}, social{leadership,negotiation,intimidation,comms}.

---

## File Structure

- **Create** `data/player/skills.json` — skill catalog: `skill_id -> {category, display_name}`.
- **Create** `data/player/classes.json` — 8 classes: `{class_id, name, description, starting_skills, xp_multipliers}`.
- **Create** `scripts/systems/class_definition.gd` — `ClassDefinition` RefCounted: `from_dict`, `load_all`, `xp_multiplier`.
- **Create** `scripts/systems/player_progression_state.gd` — `PlayerProgressionState` pure model.
- **Modify** `scripts/systems/run_snapshot.gd` — add `player_progression_summary` (8th `SUMMARY_FIELDS` entry).
- **Modify** `scripts/procgen/playable_generated_ship.gd` — own/configure progression, XP hook, HUD line, snapshot build/apply, reload reconfigure.
- **Modify** `scripts/validation/save_load_service_smoke.gd` — `summaries=7` → `8`.
- **Create** 4 smokes: `class_definitions_smoke.gd`, `player_progression_state_smoke.gd`, `progression_repair_integration_smoke.gd`, `main_playable_slice_progression_smoke.gd`.
- **Create** `docs/game/adr/0010-player-progression-current-run-persistence.md`.
- **Modify** `docs/game/06_validation_plan.md` — register 4 smokes, `commands=50` → `54`.

---

## Task 1: Skill catalog, class data, and ClassDefinition loader

**Files:**
- Create: `data/player/skills.json`, `data/player/classes.json`, `scripts/systems/class_definition.gd`
- Test: `scripts/validation/class_definitions_smoke.gd`

**Interfaces:**
- Produces: `ClassDefinition` with fields `class_id:String`, `display_name:String`, `description:String`, `starting_skills:Dictionary`, `xp_multipliers:Dictionary`; methods `static from_dict(d:Dictionary)->ClassDefinition`, `static load_all(path:String="res://data/player/classes.json")->Dictionary` (`class_id -> ClassDefinition`), `xp_multiplier(category:String)->float` (1.0 default).

- [ ] **Step 1: Create the skill catalog**

Create `data/player/skills.json`:

```json
{
  "schema_version": "1.0.0",
  "skills": [
    {"skill_id": "repair", "category": "technical", "display_name": "Repair"},
    {"skill_id": "diagnostics", "category": "technical", "display_name": "Diagnostics"},
    {"skill_id": "fabrication", "category": "technical", "display_name": "Fabrication"},
    {"skill_id": "welding", "category": "technical", "display_name": "Welding"},
    {"skill_id": "first_aid", "category": "medical", "display_name": "First Aid"},
    {"skill_id": "surgery", "category": "medical", "display_name": "Surgery"},
    {"skill_id": "pharmacology", "category": "medical", "display_name": "Pharmacology"},
    {"skill_id": "quarantine", "category": "medical", "display_name": "Quarantine"},
    {"skill_id": "piloting", "category": "navigation", "display_name": "Piloting"},
    {"skill_id": "astrogation", "category": "navigation", "display_name": "Astrogation"},
    {"skill_id": "scanner_operation", "category": "navigation", "display_name": "Scanner Operation"},
    {"skill_id": "signal_analysis", "category": "navigation", "display_name": "Signal Analysis"},
    {"skill_id": "scavenging", "category": "survival", "display_name": "Scavenging"},
    {"skill_id": "cooking", "category": "survival", "display_name": "Cooking"},
    {"skill_id": "construction", "category": "survival", "display_name": "Construction"},
    {"skill_id": "resource_management", "category": "survival", "display_name": "Resource Management"},
    {"skill_id": "leadership", "category": "social", "display_name": "Leadership"},
    {"skill_id": "negotiation", "category": "social", "display_name": "Negotiation"},
    {"skill_id": "intimidation", "category": "social", "display_name": "Intimidation"},
    {"skill_id": "comms", "category": "social", "display_name": "Comms"}
  ]
}
```

- [ ] **Step 2: Create the class definitions**

Create `data/player/classes.json`:

```json
{
  "schema_version": "1.0.0",
  "classes": [
    {"class_id": "engineer", "name": "Engineer", "description": "Repair bonuses, system diagnostics, fabrication.",
     "starting_skills": {"repair": 3, "diagnostics": 2, "welding": 2, "fabrication": 1},
     "xp_multipliers": {"technical": 1.5, "medical": 0.7, "navigation": 1.0, "survival": 1.0, "social": 0.8}},
    {"class_id": "mechanic", "name": "Mechanic", "description": "Physical repair, tool proficiency, salvage expertise.",
     "starting_skills": {"repair": 4, "welding": 3, "fabrication": 1, "scavenging": 2},
     "xp_multipliers": {"technical": 1.5, "medical": 0.7, "navigation": 0.9, "survival": 1.1, "social": 0.8}},
    {"class_id": "medic", "name": "Medic", "description": "Healing, biological hazard resistance, medical crafting.",
     "starting_skills": {"repair": 1, "first_aid": 3, "pharmacology": 2, "surgery": 1},
     "xp_multipliers": {"technical": 0.7, "medical": 1.5, "navigation": 0.8, "survival": 1.0, "social": 1.2}},
    {"class_id": "pilot", "name": "Pilot", "description": "Navigation bonuses, scanner range, travel efficiency.",
     "starting_skills": {"repair": 1, "piloting": 3, "astrogation": 2, "scanner_operation": 1},
     "xp_multipliers": {"technical": 1.0, "medical": 0.8, "navigation": 1.5, "survival": 1.0, "social": 1.0}},
    {"class_id": "scientist", "name": "Scientist", "description": "Analysis, research speed, alien tech compatibility.",
     "starting_skills": {"repair": 2, "diagnostics": 2, "signal_analysis": 2, "pharmacology": 1},
     "xp_multipliers": {"technical": 1.2, "medical": 1.0, "navigation": 1.2, "survival": 0.7, "social": 0.9}},
    {"class_id": "cook", "name": "Cook", "description": "Food crafting, morale bonuses, supply efficiency.",
     "starting_skills": {"repair": 0, "cooking": 3, "resource_management": 2, "scavenging": 1},
     "xp_multipliers": {"technical": 0.8, "medical": 1.0, "navigation": 0.8, "survival": 1.5, "social": 1.2}},
    {"class_id": "security", "name": "Security", "description": "Combat bonuses, threat detection, defensive systems.",
     "starting_skills": {"repair": 1, "intimidation": 2, "construction": 1, "scavenging": 1},
     "xp_multipliers": {"technical": 0.9, "medical": 0.9, "navigation": 1.0, "survival": 1.2, "social": 1.1}},
    {"class_id": "communications", "name": "Communications", "description": "Scanner range, signal analysis, distress calls.",
     "starting_skills": {"repair": 0, "comms": 3, "signal_analysis": 2, "negotiation": 1},
     "xp_multipliers": {"technical": 0.9, "medical": 0.8, "navigation": 1.3, "survival": 0.8, "social": 1.5}}
  ]
}
```

- [ ] **Step 3: Write the failing smoke**

Create `scripts/validation/class_definitions_smoke.gd`:

```gdscript
extends SceneTree

const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

func _initialize() -> void:
	var classes: Dictionary = ClassDefinitionScript.load_all()
	if classes.size() != 8:
		_fail("expected 8 classes, got %d" % classes.size())
		return
	for cid in ["engineer", "mechanic", "medic", "pilot", "scientist", "cook", "security", "communications"]:
		if not classes.has(cid):
			_fail("missing class %s" % cid)
			return

	var eng = classes["engineer"]
	if eng.display_name != "Engineer":
		_fail("engineer display_name=%s" % eng.display_name)
		return
	if int(eng.starting_skills.get("repair", -1)) != 3:
		_fail("engineer starting repair=%d expected 3" % int(eng.starting_skills.get("repair", -1)))
		return
	if absf(eng.xp_multiplier("technical") - 1.5) > 0.0001:
		_fail("engineer technical mult=%f expected 1.5" % eng.xp_multiplier("technical"))
		return
	# Unlisted category defaults to 1.0.
	if absf(eng.xp_multiplier("nonexistent_category") - 1.0) > 0.0001:
		_fail("unlisted category should default to 1.0")
		return

	print("CLASS DEFINITIONS PASS classes=8 engineer_repair=3 technical=1.5 default=1.0")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CLASS DEFINITIONS FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 4: Run it to verify it fails**

```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_definitions_smoke.gd
```
Expected: FAIL — `class_definition.gd` does not exist yet (load error / no PASS marker).

- [ ] **Step 5: Implement ClassDefinition**

Create `scripts/systems/class_definition.gd`:

```gdscript
extends RefCounted
class_name ClassDefinition

## One player class: starting skill levels and per-category XP multipliers.
## Pure data; loaded from data/player/classes.json.

const DEFAULT_CLASSES_PATH := "res://data/player/classes.json"

var class_id: String = ""
var display_name: String = ""
var description: String = ""
var starting_skills: Dictionary = {}   # skill_id -> int
var xp_multipliers: Dictionary = {}    # category -> float

static func from_dict(d: Dictionary) -> ClassDefinition:
	var c := ClassDefinition.new()
	c.class_id = str(d.get("class_id", ""))
	c.display_name = str(d.get("name", ""))
	c.description = str(d.get("description", ""))
	var skills_variant: Variant = d.get("starting_skills", {})
	if typeof(skills_variant) == TYPE_DICTIONARY:
		for k in (skills_variant as Dictionary):
			c.starting_skills[str(k)] = int((skills_variant as Dictionary)[k])
	var mult_variant: Variant = d.get("xp_multipliers", {})
	if typeof(mult_variant) == TYPE_DICTIONARY:
		for k in (mult_variant as Dictionary):
			c.xp_multipliers[str(k)] = float((mult_variant as Dictionary)[k])
	return c

## Returns { class_id -> ClassDefinition }. Empty dict on a malformed file.
static func load_all(path: String = DEFAULT_CLASSES_PATH) -> Dictionary:
	var out: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var classes_variant: Variant = (parsed as Dictionary).get("classes", [])
	if typeof(classes_variant) != TYPE_ARRAY:
		return out
	for entry in (classes_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var c := from_dict(entry as Dictionary)
		if not c.class_id.is_empty():
			out[c.class_id] = c
	return out

func xp_multiplier(category: String) -> float:
	return float(xp_multipliers.get(category, 1.0))
```

- [ ] **Step 6: Run it to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_definitions_smoke.gd
```
Expected: PASS — `CLASS DEFINITIONS PASS classes=8 engineer_repair=3 technical=1.5 default=1.0`.

- [ ] **Step 7: Commit**

```bash
git add data/player/skills.json data/player/classes.json scripts/systems/class_definition.gd scripts/validation/class_definitions_smoke.gd
git commit -m "feat(progression): add skill catalog, 8 class definitions, and ClassDefinition loader"
```

---

## Task 2: PlayerProgressionState model

**Files:**
- Create: `scripts/systems/player_progression_state.gd`
- Test: `scripts/validation/player_progression_state_smoke.gd`

**Interfaces:**
- Consumes: `ClassDefinition` (Task 1).
- Produces: `PlayerProgressionState` with `const MAX_SKILL_LEVEL := 10`; methods `configure(class_def, skills_catalog:Dictionary)->void`, `get_skill_level(skill_id:String)->int`, `get_class_id()->String`, `grant_xp(skill_id:String, amount:int)->bool`, `static xp_for_next_level(level:int)->int`, `get_summary()->Dictionary`, `apply_summary(summary:Dictionary)->bool`. `skills_catalog` is `{ skill_id -> {category, display_name} }` (the parsed `skills.json` "skills" array reshaped to a dict — Task 2 loads it via a helper `load_skills_catalog(path)`).

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/player_progression_state_smoke.gd`:

```gdscript
extends SceneTree

const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const ProgressionScript := preload("res://scripts/systems/player_progression_state.gd")

func _initialize() -> void:
	var catalog: Dictionary = ProgressionScript.load_skills_catalog()
	if catalog.get("repair", {}).get("category", "") != "technical":
		_fail("repair category should be technical")
		return

	var eng = ClassDefinitionScript.load_all()["engineer"]
	var prog = ProgressionScript.new()
	prog.configure(eng, catalog)

	if prog.get_class_id() != "engineer":
		_fail("class_id=%s" % prog.get_class_id())
		return
	if prog.get_skill_level("repair") != 3:
		_fail("seeded repair=%d expected 3" % prog.get_skill_level("repair"))
		return
	# Unseeded skill defaults to 0.
	if prog.get_skill_level("surgery") != 0:
		_fail("unseeded surgery should be 0")
		return

	# XP curve: level L -> L+1 needs (L+1)*100.
	if ProgressionScript.xp_for_next_level(3) != 400:
		_fail("xp_for_next_level(3)=%d expected 400" % ProgressionScript.xp_for_next_level(3))
		return

	# Engineer technical multiplier 1.5: granting 100 raw -> 150 effective.
	# repair is level 3 (needs 400 to reach 4); 150 < 400 so no level change yet.
	if prog.grant_xp("repair", 100):
		_fail("grant_xp 100 should not have leveled repair from 3")
		return
	if prog.get_skill_level("repair") != 3:
		_fail("repair changed unexpectedly")
		return
	# Grant enough to cross: 150 already banked; +250 raw *1.5 = 375 -> 525 total >= 400 -> level 4.
	if not prog.grant_xp("repair", 250):
		_fail("grant_xp 250 should have leveled repair to 4")
		return
	if prog.get_skill_level("repair") != 4:
		_fail("repair=%d expected 4 after level up" % prog.get_skill_level("repair"))
		return

	# Unknown skill -> false, no crash.
	if prog.grant_xp("not_a_skill", 100):
		_fail("grant_xp on unknown skill should return false")
		return

	# Round-trip.
	var summary: Dictionary = prog.get_summary()
	var prog2 = ProgressionScript.new()
	prog2.configure(eng, catalog)
	if not prog2.apply_summary(summary):
		_fail("apply_summary returned false")
		return
	if prog2.get_skill_level("repair") != 4:
		_fail("round-trip repair=%d expected 4" % prog2.get_skill_level("repair"))
		return

	print("PLAYER PROGRESSION PASS class=engineer repair_start=3 leveled=4 round_trip=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("PLAYER PROGRESSION FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_state_smoke.gd
```
Expected: FAIL — `player_progression_state.gd` does not exist.

- [ ] **Step 3: Implement PlayerProgressionState**

Create `scripts/systems/player_progression_state.gd`:

```gdscript
extends RefCounted
class_name PlayerProgressionState

## Pure player-progression model: skill levels (0..MAX), per-skill XP toward the
## next level, and the skill->category map used to apply class XP multipliers.
## No scene tree, no RNG. Deterministic per XP sequence.

const MAX_SKILL_LEVEL := 10
const DEFAULT_SKILLS_PATH := "res://data/player/skills.json"

var class_id: String = ""
var skills: Dictionary = {}          # skill_id -> int level
var skill_xp: Dictionary = {}        # skill_id -> int xp toward next level
var _xp_multipliers: Dictionary = {} # category -> float (from the class)
var _skill_category: Dictionary = {} # skill_id -> category (from the catalog)

## Loads skills.json into { skill_id -> {category, display_name} }.
static func load_skills_catalog(path: String = DEFAULT_SKILLS_PATH) -> Dictionary:
	var out: Dictionary = {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var skills_variant: Variant = (parsed as Dictionary).get("skills", [])
	if typeof(skills_variant) != TYPE_ARRAY:
		return out
	for entry in (skills_variant as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var sid: String = str((entry as Dictionary).get("skill_id", ""))
		if sid.is_empty():
			continue
		out[sid] = {
			"category": str((entry as Dictionary).get("category", "")),
			"display_name": str((entry as Dictionary).get("display_name", sid)),
		}
	return out

static func xp_for_next_level(level: int) -> int:
	return (level + 1) * 100

## Seeds skills from class_def.starting_skills (every catalog skill present, default 0),
## records skill->category and the class multipliers, resets all XP to 0.
func configure(class_def, skills_catalog: Dictionary) -> void:
	skills.clear()
	skill_xp.clear()
	_skill_category.clear()
	_xp_multipliers = {}
	class_id = ""
	if class_def != null:
		class_id = str(class_def.class_id)
		_xp_multipliers = (class_def.xp_multipliers as Dictionary).duplicate()
	for sid in skills_catalog:
		_skill_category[sid] = str((skills_catalog[sid] as Dictionary).get("category", ""))
		skills[sid] = 0
		skill_xp[sid] = 0
	if class_def != null:
		for sid in (class_def.starting_skills as Dictionary):
			if skills.has(sid):
				skills[sid] = clampi(int(class_def.starting_skills[sid]), 0, MAX_SKILL_LEVEL)

func get_class_id() -> String:
	return class_id

func get_skill_level(skill_id: String) -> int:
	return int(skills.get(skill_id, 0))

## Applies the class category multiplier to `amount`, banks it, and levels the
## skill up on the curve (capped at MAX_SKILL_LEVEL). Returns true if the level
## changed. Unknown skill -> false.
func grant_xp(skill_id: String, amount: int) -> bool:
	if not skills.has(skill_id):
		return false
	var category: String = str(_skill_category.get(skill_id, ""))
	var mult: float = float(_xp_multipliers.get(category, 1.0))
	var effective: int = int(round(float(amount) * mult))
	var level: int = int(skills[skill_id])
	if level >= MAX_SKILL_LEVEL:
		skill_xp[skill_id] = 0
		return false
	skill_xp[skill_id] = int(skill_xp[skill_id]) + effective
	var changed: bool = false
	while level < MAX_SKILL_LEVEL and int(skill_xp[skill_id]) >= xp_for_next_level(level):
		skill_xp[skill_id] = int(skill_xp[skill_id]) - xp_for_next_level(level)
		level += 1
		changed = true
	skills[skill_id] = level
	if level >= MAX_SKILL_LEVEL:
		skill_xp[skill_id] = 0
	return changed

func get_summary() -> Dictionary:
	return {
		"class_id": class_id,
		"skills": skills.duplicate(),
		"skill_xp": skill_xp.duplicate(),
	}

## Restores class_id/skills/skill_xp from a get_summary() dict. Skills/xp are
## overwritten per-key (unknown keys ignored). Returns true if anything changed.
func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var changed: bool = false
	var new_class: String = str(summary.get("class_id", class_id))
	if new_class != class_id:
		class_id = new_class
		changed = true
	var skills_variant: Variant = summary.get("skills", {})
	if typeof(skills_variant) == TYPE_DICTIONARY:
		for sid in (skills_variant as Dictionary):
			if skills.has(sid):
				var lvl: int = clampi(int((skills_variant as Dictionary)[sid]), 0, MAX_SKILL_LEVEL)
				if lvl != int(skills[sid]):
					skills[sid] = lvl
					changed = true
	var xp_variant: Variant = summary.get("skill_xp", {})
	if typeof(xp_variant) == TYPE_DICTIONARY:
		for sid in (xp_variant as Dictionary):
			if skill_xp.has(sid):
				var xp: int = maxi(0, int((xp_variant as Dictionary)[sid]))
				if xp != int(skill_xp[sid]):
					skill_xp[sid] = xp
					changed = true
	return changed
```

- [ ] **Step 4: Run it to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_state_smoke.gd
```
Expected: PASS — `PLAYER PROGRESSION PASS class=engineer repair_start=3 leveled=4 round_trip=true`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/player_progression_state.gd scripts/validation/player_progression_state_smoke.gd
git commit -m "feat(progression): add PlayerProgressionState model with class-multiplier XP leveling"
```

---

## Task 3: Skill → ShipSystemsManager.repair() integration smoke

**Files:**
- Test: `scripts/validation/progression_repair_integration_smoke.gd`

**Interfaces:**
- Consumes: `PlayerProgressionState.get_skill_level` (Task 2); existing `ShipSystemsManager.configure/get_system/repair`, `ShipSystem.get_subcomponent`, `ShipSubcomponent.repair(parts, tools, skill_level)`.

Background facts (from `scripts/systems/ship_subcomponent.gd`, do not re-derive): `repair()` returns `{success, reason, seconds}`; returns `already_functional` if `health >= operational_threshold`; `missing_parts`/`missing_tools` if requirements unmet; `insufficient_skill` if `skill_level < min_skill`; on success sets `health = 1.0` and `seconds = repair_seconds / (1.0 + 0.1 * max(0, skill_level - min_skill))` — so a higher skill yields a SMALLER `seconds`. `power/power_distribution` has `required_parts=["power_cell"]`, `required_tools=["welder"]`, `min_skill=2`, `repair_seconds=10.0`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/progression_repair_integration_smoke.gd`:

```gdscript
extends SceneTree

const ManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const ProgressionScript := preload("res://scripts/systems/player_progression_state.gd")

const PARTS := ["power_cell"]
const TOOLS := ["welder"]

func _break(mgr) -> void:
	mgr.get_system("power").get_subcomponent("power_distribution").health = 0.0

func _initialize() -> void:
	var catalog: Dictionary = ProgressionScript.load_skills_catalog()
	var classes: Dictionary = ClassDefinitionScript.load_all()

	# Cook starts repair 0 -> below power_distribution.min_skill (2): rejected.
	var prog_low = ProgressionScript.new()
	prog_low.configure(classes["cook"], catalog)
	var mgr = ManagerScript.new()
	mgr.configure(mgr.load_definitions(), 0, 1)  # PRISTINE so only our break matters
	_break(mgr)
	var r_low: Dictionary = mgr.repair("power", "power_distribution", PARTS, TOOLS, prog_low.get_skill_level("repair"))
	if bool(r_low.get("success", true)) or str(r_low.get("reason", "")) != "insufficient_skill":
		_fail("low skill should be insufficient_skill, got %s" % str(r_low))
		return

	# Engineer starts repair 3 (>= min_skill 2): success.
	var prog_hi = ProgressionScript.new()
	prog_hi.configure(classes["engineer"], catalog)
	_break(mgr)
	var r_hi: Dictionary = mgr.repair("power", "power_distribution", PARTS, TOOLS, prog_hi.get_skill_level("repair"))
	if not bool(r_hi.get("success", false)):
		_fail("engineer repair should succeed, got %s" % str(r_hi))
		return
	var seconds_skill3: float = float(r_hi.get("seconds", 0.0))

	# Raise engineer repair to a higher level via grant_xp, repair again: faster.
	while prog_hi.get_skill_level("repair") < 6:
		prog_hi.grant_xp("repair", 1000)
	_break(mgr)
	var r_faster: Dictionary = mgr.repair("power", "power_distribution", PARTS, TOOLS, prog_hi.get_skill_level("repair"))
	if not bool(r_faster.get("success", false)):
		_fail("higher-skill repair should succeed, got %s" % str(r_faster))
		return
	if float(r_faster.get("seconds", 999.0)) >= seconds_skill3:
		_fail("higher skill should repair faster: %f !< %f" % [float(r_faster.get("seconds", 999.0)), seconds_skill3])
		return

	print("PROGRESSION REPAIR INTEGRATION PASS rejected_low=true success_hi=true faster_at_higher_skill=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("PROGRESSION REPAIR INTEGRATION FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails, then passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/progression_repair_integration_smoke.gd
```
First run (before Tasks 1–2 are present this would error). Since Tasks 1–2 are done, this smoke should PASS immediately — it is an integration assertion over existing APIs, no new production code. If it FAILS, the failure identifies a real wiring gap to fix in the model (not the smoke). Expected on success: `PROGRESSION REPAIR INTEGRATION PASS rejected_low=true success_hi=true faster_at_higher_skill=true`.

> Note: this task adds no production code — it is a guard proving the progression→repair contract. TDD's red phase is satisfied by the smoke not existing before this task; do not weaken the assertions to force green.

- [ ] **Step 3: Commit**

```bash
git add scripts/validation/progression_repair_integration_smoke.gd
git commit -m "test(progression): assert repair skill gates and scales ShipSystemsManager.repair()"
```

---

## Task 4: RunSnapshot field + save-smoke count bump

**Files:**
- Modify: `scripts/systems/run_snapshot.gd`
- Modify: `scripts/validation/save_load_service_smoke.gd`

**Interfaces:**
- Produces: `RunSnapshot.player_progression_summary: Dictionary`, added as the 8th entry of `SUMMARY_FIELDS`, serialized in `to_dict`/`from_dict`. `get_summary_count()` returns 8.

- [ ] **Step 1: Update the save smoke (RED on count)**

In `scripts/validation/save_load_service_smoke.gd`:
- Change the assertion at line 117 from `if loaded.get_summary_count() != 7:` to `if loaded.get_summary_count() != 8:` and its message `expected 7` → `expected 8`.
- Change the marker print (line 181) `summaries=7` → `summaries=8`.
- Add, alongside the other `original.<x>_summary = ...` assignments (near line 84), a populated progression summary so the round-trip covers it:
  ```gdscript
  	var progression := preload("res://scripts/systems/player_progression_state.gd").new()
  	progression.configure(preload("res://scripts/systems/class_definition.gd").load_all()["engineer"], progression.load_skills_catalog())
  	progression.grant_xp("repair", 100)
  	original.player_progression_summary = progression.get_summary()
  ```
- After the existing round-trip field assertions (near line 118), add:
  ```gdscript
  	if str(loaded.player_progression_summary.get("class_id", "")) != "engineer":
  		_fail("player_progression_summary class_id not restored")
  		return
  ```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
```
Expected: FAIL — `summary_count=7 expected 8` (field not on RunSnapshot yet).

- [ ] **Step 3: Add the field to RunSnapshot**

In `scripts/systems/run_snapshot.gd`:
- After `var objective_progress_summary: Dictionary = {}` (line 24) add:
  ```gdscript
  var player_progression_summary: Dictionary = {}
  ```
- In `SUMMARY_FIELDS` (line 32) add `"player_progression_summary",` as the last entry.
- In `to_dict()` add (after the `objective_progress_summary` line ~58):
  ```gdscript
  		"player_progression_summary": player_progression_summary.duplicate(true),
  ```
- In `from_dict()` add (after the `objective_progress_summary` line ~93):
  ```gdscript
  	snapshot.player_progression_summary = _deep_copy_dict(dict.get("player_progression_summary", {}))
  ```

- [ ] **Step 4: Run it to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/save_load_service_smoke.gd
```
Expected: PASS — `SAVE LOAD SERVICE PASS round_trip=true version_match=true summaries=8`.

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/run_snapshot.gd scripts/validation/save_load_service_smoke.gd
git commit -m "feat(progression): persist player_progression_summary in RunSnapshot (summaries 7->8)"
```

---

## Task 5: Coordinator integration — build, XP hook, HUD, save/load

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/main_playable_slice_progression_smoke.gd`

**Interfaces:**
- Consumes: `PlayerProgressionState` (Task 2), `ClassDefinition.load_all` (Task 1), `RunSnapshot.player_progression_summary` (Task 4).
- Produces (on `PlayableGeneratedShip`): `var player_progression`, `@export var starting_class_id := "engineer"`, `func get_player_progression()`, `const REPAIR_OBJECTIVE_XP := 50`, and a `Repair Skill: N` HUD line.

- [ ] **Step 1: Write the failing main-scene smoke**

Create `scripts/validation/main_playable_slice_progression_smoke.gd`:

```gdscript
extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 600

var main_node: Node
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	var bootstrap := SaveLoadService.new()
	bootstrap.delete_current_run()
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	var playable: PlayableGeneratedShip = _find_playable(main_node)
	if playable == null:
		if frame_count > TIMEOUT_FRAMES:
			_fail("no PlayableGeneratedShip found")
		return
	if playable.loader == null or not playable.loader.has_loaded_ship():
		if frame_count > TIMEOUT_FRAMES:
			_fail("loader did not finish")
		return
	_validate(playable)

func _validate(playable: PlayableGeneratedShip) -> void:
	var prog = playable.get_player_progression()
	if prog == null:
		_fail("player_progression null")
		return
	if prog.get_class_id() != "engineer":
		_fail("default class=%s expected engineer" % prog.get_class_id())
		return
	var repair_xp_before: int = int(prog.get_summary().get("skill_xp", {}).get("repair", 0))

	# Complete objective 1 (no repair XP) then objective 2 (restore_systems -> repair XP).
	if not playable.complete_objective_sequence_for_validation(1):
		_fail("complete obj1 failed")
		return
	if not playable.complete_objective_sequence_for_validation(2):
		_fail("complete obj2 failed")
		return

	var repair_xp_after: int = int(prog.get_summary().get("skill_xp", {}).get("repair", 0))
	if repair_xp_after <= repair_xp_before:
		_fail("repair XP did not increase after restore_systems (%d -> %d)" % [repair_xp_before, repair_xp_after])
		return
	if not playable.get_combined_system_status_lines_contains("Repair Skill:"):
		_fail("HUD missing 'Repair Skill:' line")
		return

	# Save/load round-trips progression.
	if not playable.request_save():
		_fail("request_save failed")
		return
	if not playable.request_load():
		_fail("request_load failed")
		return
	var prog_after_load = playable.get_player_progression()
	var xp_loaded: int = int(prog_after_load.get_summary().get("skill_xp", {}).get("repair", 0))
	if xp_loaded != repair_xp_after:
		_fail("repair XP not restored after load (%d != %d)" % [xp_loaded, repair_xp_after])
		return

	finished = true
	print("MAIN PLAYABLE PROGRESSION PASS class=engineer repair_xp_gained=true hud=true round_trip=true")
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	var svc := SaveLoadService.new()
	svc.delete_current_run()
	quit(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE PROGRESSION FAIL reason=%s" % reason)
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(1)
```

- [ ] **Step 2: Run it to verify it fails**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_progression_smoke.gd
```
Expected: FAIL — `get_player_progression` missing.

- [ ] **Step 3: Add preload, fields, and accessor**

In `scripts/procgen/playable_generated_ship.gd`:

(a) Near the other `const ...Script :=` preloads (after the `ShipBlueprintScript` line from Phase 2):
```gdscript
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
```
(b) Near the other `@export` paths:
```gdscript
@export var starting_class_id: String = "engineer"
```
(c) Near `var ship_systems_manager`:
```gdscript
var player_progression   # PlayerProgressionState (untyped: class_name unreliable headless)
const REPAIR_OBJECTIVE_XP: int = 50
```
(d) Add the accessor near `get_ship_systems_manager()`:
```gdscript
## Validation seam: the live PlayerProgressionState (null before _build_runtime_nodes()).
func get_player_progression():
	return player_progression

## Validation seam: true if any combined status line contains `token`.
func get_combined_system_status_lines_contains(token: String) -> bool:
	for line in _combined_system_status_lines():
		if String(line).contains(token):
			return true
	return false
```

- [ ] **Step 4: Build + configure progression, and reconfigure on reload**

(a) In `_build_runtime_nodes()` (right after the `ship_systems_manager` build block from Phase 2):
```gdscript
	player_progression = PlayerProgressionScript.new()
	_configure_player_progression()
```
(b) Add the helper near `_load_blueprint_for_systems()`:
```gdscript
## Configures the progression model from starting_class_id (defaults to engineer
## when the id is unknown). Idempotent: re-callable on reload.
func _configure_player_progression() -> void:
	if player_progression == null:
		return
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var class_def = classes.get(starting_class_id, classes.get("engineer", null))
	player_progression.configure(class_def, PlayerProgressionScript.load_skills_catalog())
```
(c) In `_reset_runtime_for_reload()` (near the `ship_systems_manager` reconfigure):
```gdscript
	_configure_player_progression()
```

- [ ] **Step 5: Grant repair XP on repair-objective completion + HUD line**

(a) In `_on_interactable_completed`, inside the `if ship_systems_manager != null:` block (right after the `force_repair` loop over `OBJECTIVE_REPAIR_MAP`), add:
```gdscript
		if player_progression != null and (objective_type == "restore_systems" or objective_type == "stabilize_reactor"):
			player_progression.grant_xp("repair", REPAIR_OBJECTIVE_XP)
```
(b) In `_combined_system_status_lines()`, after the `ship_systems_manager` HUD block, add:
```gdscript
	if player_progression != null:
		lines.append("Repair Skill: %d" % player_progression.get_skill_level("repair"))
```

- [ ] **Step 6: Save/load the progression summary**

(a) In `_build_run_snapshot()` (near the `ship_systems_manager` snapshot write):
```gdscript
	if player_progression != null:
		snapshot.player_progression_summary = player_progression.get_summary()
```
(b) In `_apply_run_snapshot()` (near the manager apply block):
```gdscript
	if player_progression != null and not snapshot.player_progression_summary.is_empty():
		player_progression.apply_summary(snapshot.player_progression_summary)
```

- [ ] **Step 7: Run the main-scene smoke to verify it passes**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_progression_smoke.gd
```
Expected: PASS — `MAIN PLAYABLE PROGRESSION PASS class=engineer repair_xp_gained=true hud=true round_trip=true`.

- [ ] **Step 8: Run the existing save/load + integration smokes (no regression)**

```bash
for s in main_playable_slice_save_load_smoke main_playable_slice_ship_systems_smoke req012_autosave_sequence_smoke main_playable_slice_reload_affordance_smoke; do
  "$GODOT" --headless --path "$ROOT" --script "res://scripts/validation/$s.gd" 2>&1 | grep -E "PASS|FAIL" | grep -v gdaimcp | head -1
done
```
Expected: all four print their PASS markers.

- [ ] **Step 9: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_slice_progression_smoke.gd
git commit -m "feat(progression): wire progression into coordinator — XP hook, HUD, save/load"
```

---

## Task 6: ADR + validation-plan registration + full regression

**Files:**
- Create: `docs/game/adr/0010-player-progression-current-run-persistence.md`
- Modify: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Write ADR-0010**

Create `docs/game/adr/0010-player-progression-current-run-persistence.md`:

```markdown
# ADR-0010: Player progression is current-run state in RunSnapshot

Date: 2026-06-21
Status: Accepted
Amends: ADR-0007 (save/load service scope)
Relates to: ADR-0002 / ADR-0003 (hub/meta progression deferral — NOT reopened)

## Context
Phase 3 adds player progression (classes + skills + XP). It must survive
save/load within a sandbox session. ADR-0007 restricts RunSnapshot to current-run
state and requires a new ADR to add a field.

## Decision
Player progression is current-run state: a `player_progression_summary` field is
added to RunSnapshot (SUMMARY_FIELDS count 7 -> 8), round-tripped via
get_summary/apply_summary like the other models. It does NOT introduce a cross-run
meta-progression store; ADR-0002/0003's deferral of hub/meta progression stands.
The "run" is one continuous sandbox session (the player keeps ship, skills, and
inventory while travelling between derelicts; death/restart is undefined).

## Consequences
- Save-smoke count contracts move from summaries=7 to summaries=8.
- Skills/XP persist across save/load within a session.
- force_repair remains the live repair mechanism until Phase 6 supplies parts/tools
  to drive the gated repair() path that consumes the repair skill.
```

- [ ] **Step 2: Register the four smokes in the regression bundle**

In `docs/game/06_validation_plan.md`, inside the `run_clean` block (the bash fence ending in `SYNAPTIC_SEA REGRESSION PASS`), add these four lines (place the model/data ones near the other ship-systems model smokes, the main-scene one near the other `main_playable_slice_*` smokes):

```bash
run_clean 'class definitions smoke' 'CLASS DEFINITIONS PASS classes=8 engineer_repair=3 technical=1.5 default=1.0' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_definitions_smoke.gd
run_clean 'player progression model smoke' 'PLAYER PROGRESSION PASS class=engineer repair_start=3 leveled=4 round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_state_smoke.gd
run_clean 'progression repair integration smoke' 'PROGRESSION REPAIR INTEGRATION PASS rejected_low=true success_hi=true faster_at_higher_skill=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/progression_repair_integration_smoke.gd
run_clean 'main progression smoke' 'MAIN PLAYABLE PROGRESSION PASS class=engineer repair_xp_gained=true hud=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_progression_smoke.gd
```

Then change the final line `echo 'SYNAPTIC_SEA REGRESSION PASS commands=50 clean_output=true'` to `commands=54`.

- [ ] **Step 3: Run the full regression bundle + Gate-1 playtest**

Extract the bundle bash block (fence at lines ~29–115) and run it with the Windows paths substituted (do NOT edit the doc's hardcoded macOS paths):
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
sed -n '30,115p' docs/game/06_validation_plan.md \
  | sed "s#^ROOT=.*#ROOT=\"$ROOT\"#; s#^GODOT=.*#GODOT=\"$GODOT\"#" > /tmp/reg.sh
bash /tmp/reg.sh 2>&1 | tail -2
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/gate1_automated_playtest.gd 2>&1 | grep -E "GATE 1 AUTOMATED PLAYTEST PASS|FAIL"
```
Expected: bundle ends `SYNAPTIC_SEA REGRESSION PASS commands=54 clean_output=true`; Gate-1 prints `GATE 1 AUTOMATED PLAYTEST PASS`. If the bundle reports a count mismatch or an unexpected ERROR/WARNING, fix the registration/marker (or the real regression) and re-run — do not adjust the count to paper over a missing smoke.

- [ ] **Step 4: Commit**

```bash
git add docs/game/adr/0010-player-progression-current-run-persistence.md docs/game/06_validation_plan.md
git commit -m "docs(progression): ADR-0010 + register Phase 3 smokes (commands 50->54)"
```

---

## Self-Review

**Spec coverage:**
- Skill catalog (20 skills, 5 categories) → Task 1 (`skills.json`) ✓
- 8 classes with starting skills + per-category multipliers → Task 1 (`classes.json`) ✓
- `ClassDefinition` loader (`from_dict`/`load_all`/`xp_multiplier`) → Task 1 ✓
- `PlayerProgressionState` (configure/get_skill_level/grant_xp/xp_for_next_level/summary) → Task 2 ✓
- Deterministic level curve + category multiplier + cap → Task 2 ✓
- Skill → `repair()` gating + time scaling proof → Task 3 ✓
- `RunSnapshot` field, summaries 7→8 → Task 4 ✓
- Coordinator build/configure, XP hook (restore_systems/stabilize_reactor), HUD line, reload reconfigure, snapshot build/apply → Task 5 ✓
- Default class engineer via `starting_class_id` → Task 5 ✓
- ADR-0010 + register 4 smokes (commands 50→54) → Task 6 ✓
- Out-of-scope items (ability tree, training items, non-repair effects, force_repair retirement) → not built ✓

**Placeholder scan:** No TBD/TODO. All code blocks complete. `commands=54` is the concrete total (50 + 4); Step 3 says to fix-and-re-run rather than fudge if the count mismatches.

**Type consistency:** `configure(class_def, skills_catalog)`, `get_skill_level(id)->int`, `grant_xp(id, amount)->bool`, `xp_for_next_level(level)->int`, `get_summary/apply_summary`, `load_skills_catalog`, `load_all`, `xp_multiplier` are used identically across Tasks 2–5 and the smokes. `player_progression` field + `get_player_progression()` defined Task 5, used by the main smoke. `player_progression_summary` defined Task 4, used Task 5. `REPAIR_OBJECTIVE_XP` defined and used in Task 5. Skill ids and class ids match `skills.json`/`classes.json` from Task 1.
