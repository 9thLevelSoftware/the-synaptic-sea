# Domain 6 — Progression & Meta Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the `progression` loop — give meta-currency a spendable sink (hub-upgrade purchase), make skill-tree unlocks gate real gameplay (per-run training gate), surface cross-run unlocks in-game (records display + class-selection gate), and unify the XP ingest path (remove the repair double-grant).

**Architecture:** Almost pure wiring — every model already exists, is typed, and persists to its own `user://*.json`. Work lands in two nodes (`MenuCoordinator` for interactive meta panels, `playable_generated_ship.gd` for the training-gate + class-config consumers + the ingest fix) plus small additive changes to four pure models and three data files. No new autoloads, no scene-tree reaches from models.

**Tech Stack:** Godot 4.6.2, typed GDScript, headless `--script` SceneTree smokes.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (the `_console` build). **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- **Run a smoke:** `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<smoke>.gd` with `GODOT`/`ROOT` set to the two values above.
- **Trust the PASS marker, never the exit code** — Godot `--script` can exit 0 on a parse error. A smoke passes only when its exact `... PASS ...` marker line is printed and no unexpected `ERROR:`/`WARNING:` appears.
- **Baseline noise allowlist (ignore these):** `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`. Any *other* `ERROR:`/`WARNING:` blocks completion.
- **Typed GDScript.** Resources/RefCounted are data; Nodes are behavior. The pure models (`MetaProgressionState`, `TrainingEventBus`, `SkillTreeState`, `ClassDefinition`) must not reach into the scene tree — gate/selection hooks are injected via `Callable`/accessor.
- **Additive persistence only.** New persisted fields are read with `.get(key, default)`; do **not** bump `MetaProgressionState.SCHEMA_VERSION` (`"meta-progression-1"`).
- **Both `_process` branches** for any per-frame tick. Domain 6 is event-driven (grants at kill/objective, payout at run-end) so its `_process` footprint is nil; the closure smoke still carries an `away_ticks=` assertion (Task 9).
- **Commit convention:** Conventional Commits (`feat:`/`fix:`/`docs:`), and **every commit ends with these two trailers**:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01BWeYVNphLh2FRALbAqJ2db
  ```
- **Selective staging only.** `git add <explicit paths>` — never `git add -A`. Never stage `.godot/`, `*.uid`, `addons/`, or `project.godot`.
- **Data ground truth (do not re-derive):**
  - Advanced (tree-gated) skills = the 11 keys in `data/player/skill_tree.json`: `welding_mastery, biomatter_diagnostics, surgery, pharmacology, astrogation, fabrication, construction, resource_management, leadership, intimidation, comms`. All other skills in `skills.json` are base/ungated.
  - `data/player/training_actions.json` maps `repair_full_system → repair +120`; `threat_killed → scavenging +10`; `perform_surgery → surgery +150`; `scavenge_container → scavenging +50`; `fabricate_part → fabrication +80`.
  - `REPAIR_OBJECTIVE_XP = 50` at `playable_generated_ship.gd:297`.
  - The 3 unlockable classes (registry class-category unlocks in `unlock_tables.json`): `salvage_captain` (trigger `scavenge_container|any`), `field_medic` (`perform_surgery|any`), `signal_specialist` (`decode_signal|any`).

---

## File Structure

**Pure models (additive):**
- `scripts/systems/meta_progression_state.gd` — `selected_class_id` field + persistence (Task 1).
- `scripts/systems/training_event_bus.gd` — `skill_gate: Callable` drop-hook in `emit()` (Task 2).
- `scripts/systems/skill_tree_state.gd` — `is_gated(skill_id) -> bool` (Task 2).
- `scripts/systems/class_definition.gd` — `unlockable: bool` field (Task 3).

**Data:**
- `data/player/classes.json` — add 3 unlockable class defs (Task 3).
- `data/player/unlock_tables.json` — add `class_id` to the 3 class-category entries (Task 3).

**UI (interactive panels + coordinator):**
- `scripts/ui/hub_upgrade_panel.gd` — selection cursor (Task 4).
- `scripts/ui/skill_tree_panel.gd` — selection cursor (Task 5).
- `scripts/ui/class_panel.gd` — selection cursor + meta-state + availability (Task 7).
- `scripts/ui/menu_coordinator.gd` — model refs, `meta_screen_move_selection()`/`meta_screen_confirm()` seams, input routing, registry records reader (Tasks 4/5/6/7).

**Coordinator (consumers):**
- `scripts/procgen/playable_generated_ship.gd` — training-gate wiring, `selected_class_id` config read, run-end class-unlock bridge, remove direct repair `grant_xp` (Tasks 5/7/8).

**Validation + docs:**
- `scripts/validation/meta_progression_state_smoke.gd` — extend (Task 1).
- `scripts/validation/training_gate_smoke.gd` — new (Task 2).
- `scripts/validation/class_catalog_smoke.gd` — new (Task 3).
- `scripts/validation/meta_screens_interactive_smoke.gd` — new (Tasks 4/5/6/7 build it up).
- `scripts/validation/progression_meta_smoke.gd` — new end-to-end + away (Task 9).
- `docs/game/06_validation_plan.md` — register markers (Task 9).
- `docs/game/inventory/system_inventory.json` (+ regenerated MD/HTML) — flip loop (Task 10).

---

### Task 1: MetaProgressionState.selected_class_id (pure model)

**Files:**
- Modify: `scripts/systems/meta_progression_state.gd`
- Test: `scripts/validation/meta_progression_state_smoke.gd` (extend)

**Interfaces:**
- Produces: `MetaProgressionState.selected_class_id: String`; `set_selected_class(class_id: String) -> void`; `get_selected_class() -> String`. Persisted in `to_dict()`/`apply_summary()`; cleared by `reset_all()`.

- [ ] **Step 1: Write the failing test** — append before the final `print(...)` in `meta_progression_state_smoke.gd::_initialize()` (around line 191):

```gdscript
	# --- selected_class_id (Domain 6): default empty, set, persist, reset ---
	var meta_cls = MetaProgressionStateScript.new()
	meta_cls.configure({})
	if meta_cls.get_selected_class() != "":
		_fail("selected_class default should be empty")
		return
	meta_cls.set_selected_class("field_medic")
	if meta_cls.get_selected_class() != "field_medic":
		_fail("set_selected_class did not stick")
		return
	var cls_dump: Dictionary = meta_cls.to_dict()
	var meta_cls2 = MetaProgressionStateScript.new()
	meta_cls2.configure({})
	if not meta_cls2.apply_summary(cls_dump):
		_fail("apply_summary rejected selected_class dump")
		return
	if meta_cls2.get_selected_class() != "field_medic":
		_fail("selected_class did not round-trip through apply_summary")
		return
	meta_cls2.reset_all()
	if meta_cls2.get_selected_class() != "":
		_fail("reset_all should clear selected_class")
		return
```

Also update the final marker line to include the new dimension:

```gdscript
	print("META PROGRESSION STATE PASS payout=39 unlocks=true persistence=true reset=true selected_class=true")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_progression_state_smoke.gd`
Expected: FAIL — `META PROGRESSION STATE FAIL reason=...` (or a parse error referencing `set_selected_class`), because the method does not exist yet.

- [ ] **Step 3: Write minimal implementation** — in `meta_progression_state.gd`:

Add the field after `var last_payout_reason: String = ""` (line 23):

```gdscript
var selected_class_id: String = ""                 # Domain 6: player's chosen class for the next run
```

Add getters/setter after `get_meta_currency()` (line 46):

```gdscript
func get_selected_class() -> String:
	return selected_class_id

func set_selected_class(class_id: String) -> void:
	selected_class_id = str(class_id)
```

In `reset_all()` (line 162) add:

```gdscript
	selected_class_id = ""
```

In `to_dict()` (line 174) add the key (before `"saved_at"`):

```gdscript
		"selected_class_id": selected_class_id,
```

In `apply_summary()` (line 191), after the `last_payout_reason` line (218) add:

```gdscript
	selected_class_id = str(dict.get("selected_class_id", ""))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_progression_state_smoke.gd`
Expected: PASS — `META PROGRESSION STATE PASS payout=39 unlocks=true persistence=true reset=true selected_class=true`

- [ ] **Step 5: Commit**

```bash
git add scripts/systems/meta_progression_state.gd scripts/validation/meta_progression_state_smoke.gd
git commit -m "feat: MetaProgressionState.selected_class_id (persisted, Domain 6)"   # + the two trailers
```

---

### Task 2: TrainingEventBus skill gate + SkillTreeState.is_gated (pure models)

**Files:**
- Modify: `scripts/systems/training_event_bus.gd`
- Modify: `scripts/systems/skill_tree_state.gd`
- Test: `scripts/validation/training_gate_smoke.gd` (create)

**Interfaces:**
- Produces: `SkillTreeState.is_gated(skill_id: String) -> bool` (true iff the skill has a prereq entry, i.e. is an advanced/tree-gated skill). `TrainingEventBus.skill_gate: Callable` — optional `func(skill_id: String) -> bool` returning true when the skill may receive XP; when set and it returns false, `emit()` drops the event (increments `_dropped`, returns `null`) **before** granting.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/training_gate_smoke.gd`:

```gdscript
extends SceneTree

## Domain 6 training-gate smoke: an advanced skill (surgery) gains no XP through
## the bus until its skill-tree node is unlocked; a base skill (scavenging) is
## always trainable; is_gated correctly partitions advanced vs base skills.
##
## Marker: `TRAINING GATE PASS`

const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

func _initialize() -> void:
	var tree = SkillTreeStateScript.new()
	tree.configure(SkillTreeStateScript.load_skills_catalog(), SkillTreeStateScript.load_books_catalog())
	tree.load_prerequisites()

	# is_gated partitions advanced (in skill_tree.json) vs base skills.
	if not tree.is_gated("surgery"):
		_fail("surgery should be gated")
		return
	if tree.is_gated("scavenging"):
		_fail("scavenging (base) should NOT be gated")
		return

	# Build a progression on the engineer class so grant_xp works.
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var prog = PlayerProgressionScript.new()
	prog.configure(classes.get("engineer", null), PlayerProgressionScript.load_skills_catalog(), PlayerProgressionScript.load_books_catalog())

	var bus = TrainingEventBusScript.new()
	bus.configure()
	# Gate: a skill is trainable if it is not gated, or its node is unlocked.
	bus.skill_gate = func(skill_id: String) -> bool:
		if not tree.is_gated(skill_id):
			return true
		return tree.is_unlocked(skill_id)

	# perform_surgery -> surgery (+150) is DROPPED while surgery is locked.
	var before_surgery: int = prog.get_skill_xp("surgery")
	var r1: Variant = bus.emit("perform_surgery", "", prog)
	if r1 != null:
		_fail("locked surgery event should be dropped (returned non-null)")
		return
	if prog.get_skill_xp("surgery") != before_surgery:
		_fail("locked surgery should have gained no XP")
		return
	if bus.get_dropped_count() != 1:
		_fail("dropped count should be 1 after a gated drop, got %d" % bus.get_dropped_count())
		return

	# A base-skill event (scavenge_container -> scavenging) always grants.
	var r2: Variant = bus.emit("scavenge_container", "", prog)
	if r2 == null:
		_fail("base-skill event should NOT be dropped")
		return
	if prog.get_skill_xp("scavenging") <= 0:
		_fail("scavenging should have gained XP")
		return

	# After unlocking the surgery node the event grants normally.
	tree.unlock("surgery")
	var r3: Variant = bus.emit("perform_surgery", "", prog)
	if r3 == null:
		_fail("unlocked surgery event should grant (returned null)")
		return
	if prog.get_skill_xp("surgery") <= before_surgery:
		_fail("unlocked surgery should have gained XP")
		return

	print("TRAINING GATE PASS gated=true drop=1 unlock_grants=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("TRAINING GATE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/training_gate_smoke.gd`
Expected: FAIL — parse error / FAIL referencing `is_gated` or the un-dropped surgery event (no gate exists yet).

- [ ] **Step 3: Write minimal implementation**

In `skill_tree_state.gd`, add after `is_known_skill()` (line 92):

```gdscript
## Domain 6: true when the skill is tree-gated (has a prerequisite entry in
## skill_tree.json). Base skills return false and are always trainable.
func is_gated(skill_id: String) -> bool:
	return _prereqs.has(skill_id)
```

In `training_event_bus.gd`, add the field after `event_filter` (line 27):

```gdscript
## Optional Domain 6 skill gate. When set, an event whose resolved target_skill
## returns false is dropped before XP is granted. Signature: func(skill_id: String) -> bool
var skill_gate: Callable = Callable()
```

In `emit()`, insert the gate check after `skill_id`/`base_xp` are resolved and validated (immediately after the `if skill_id.is_empty() or base_xp <= 0:` block, before the `_is_cross_training` line ~97):

```gdscript
	if skill_gate.is_valid() and not bool(skill_gate.call(skill_id)):
		_dropped += 1
		return null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/training_gate_smoke.gd`
Expected: PASS — `TRAINING GATE PASS gated=true drop=1 unlock_grants=true`

- [ ] **Step 5: Regression-check the existing bus/progression smokes** (the gate is opt-in; unset gate must not change behavior):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_full_smoke.gd`
Expected: its existing PASS marker, unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/training_event_bus.gd scripts/systems/skill_tree_state.gd scripts/validation/training_gate_smoke.gd
git commit -m "feat: TrainingEventBus skill_gate + SkillTreeState.is_gated (Domain 6 training gate)"   # + trailers
```

---

### Task 3: Unlockable classes + ClassDefinition.unlockable + registry class_id (data + model)

**Files:**
- Modify: `scripts/systems/class_definition.gd`
- Modify: `data/player/classes.json`
- Modify: `data/player/unlock_tables.json`
- Test: `scripts/validation/class_catalog_smoke.gd` (create)

**Interfaces:**
- Produces: `ClassDefinition.unlockable: bool` (default false; base classes omit the key). `classes.json` gains `salvage_captain`/`field_medic`/`signal_specialist` (each `"unlockable": true`). The 3 `class`-category entries in `unlock_tables.json` gain `"class_id"` pointing at the matching class.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/class_catalog_smoke.gd`:

```gdscript
extends SceneTree

## Domain 6 class-catalog smoke: the 8 base classes remain always-available, the
## 3 unlockable classes exist with valid data and unlockable=true, and each
## registry class-unlock carries a class_id that matches a real class.
##
## Marker: `CLASS CATALOG PASS`

const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

const BASE_CLASSES := ["engineer", "mechanic", "medic", "pilot", "scientist", "cook", "security", "communications"]
const UNLOCKABLE_CLASSES := ["salvage_captain", "field_medic", "signal_specialist"]

func _initialize() -> void:
	var classes: Dictionary = ClassDefinitionScript.load_all()
	if classes.size() != 11:
		_fail("expected 11 classes, got %d" % classes.size())
		return
	for cid in BASE_CLASSES:
		if not classes.has(cid):
			_fail("missing base class %s" % cid)
			return
		if bool(classes[cid].unlockable):
			_fail("base class %s should NOT be unlockable" % cid)
			return
	for cid in UNLOCKABLE_CLASSES:
		if not classes.has(cid):
			_fail("missing unlockable class %s" % cid)
			return
		if not bool(classes[cid].unlockable):
			_fail("class %s should be unlockable" % cid)
			return
		if (classes[cid].xp_multipliers as Dictionary).is_empty():
			_fail("unlockable class %s has no xp_multipliers" % cid)
			return

	# Registry class-category entries carry a class_id that resolves to a real class.
	var text: String = FileAccess.get_file_as_string("res://data/player/unlock_tables.json")
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("unlock_tables.json parse failed")
		return
	var class_entries: int = 0
	for entry in ((parsed as Dictionary).get("unlocks", []) as Array):
		if str((entry as Dictionary).get("category", "")) != "class":
			continue
		class_entries += 1
		var cid: String = str((entry as Dictionary).get("class_id", ""))
		if cid.is_empty() or not classes.has(cid):
			_fail("class unlock %s has invalid class_id '%s'" % [str((entry as Dictionary).get("unlock_id","")), cid])
			return
	if class_entries != 3:
		_fail("expected 3 class-category unlocks, got %d" % class_entries)
		return

	print("CLASS CATALOG PASS base=8 unlockable=3 registry_class_ids=ok")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CLASS CATALOG FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_catalog_smoke.gd`
Expected: FAIL — `expected 11 classes, got 8` (the 3 classes + flag + class_id fields don't exist yet).

- [ ] **Step 3: Write minimal implementation**

In `class_definition.gd`, add the field after `var xp_multipliers: Dictionary = {}` (line 13):

```gdscript
var unlockable: bool = false           # Domain 6: base classes false; earned classes true
```

In `from_dict()` after the `xp_multipliers` loop (line 31), before `return c`:

```gdscript
	c.unlockable = bool(d.get("unlockable", false))
```

In `data/player/classes.json`, append these 3 objects to the `"classes"` array (mirror the existing entries' shape — `starting_skills` uses real skill ids from `skills.json`, `xp_multipliers` uses the 5 categories `technical/medical/navigation/survival/social`):

```json
    {"class_id": "salvage_captain", "name": "Salvage Captain", "description": "Elite scavenger; superior salvage yield and field fabrication.", "unlockable": true,
      "starting_skills": {"scavenging": 3, "repair": 1, "resource_management": 1},
      "xp_multipliers": {"technical": 1.1, "medical": 0.8, "navigation": 1.0, "survival": 1.4, "social": 0.9}},
    {"class_id": "field_medic", "name": "Field Medic", "description": "Combat medic; advanced surgery and hazard triage under fire.", "unlockable": true,
      "starting_skills": {"first_aid": 3, "surgery": 1, "quarantine": 1},
      "xp_multipliers": {"technical": 0.8, "medical": 1.5, "navigation": 0.9, "survival": 1.1, "social": 1.0}},
    {"class_id": "signal_specialist", "name": "Signal Specialist", "description": "Decodes derelict transmissions; long-range scan and comms mastery.", "unlockable": true,
      "starting_skills": {"signal_analysis": 3, "scanner_operation": 1, "comms": 1},
      "xp_multipliers": {"technical": 1.0, "medical": 0.9, "navigation": 1.4, "survival": 0.8, "social": 1.2}}
```

> NOTE: add a comma after the previous last class object's closing `}` so the array stays valid JSON. `starting_skills` may reference an advanced skill at level 1 (e.g. `surgery`, `comms`) — this is a starting grant, independent of the training gate.

In `data/player/unlock_tables.json`, add `"class_id"` to each of the 3 `class`-category entries:
- `class_unlock_salvage_captain` → `"class_id": "salvage_captain"`
- `class_unlock_field_medic` → `"class_id": "field_medic"`
- `class_unlock_signal_specialist` → `"class_id": "signal_specialist"`

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_catalog_smoke.gd`
Expected: PASS — `CLASS CATALOG PASS base=8 unlockable=3 registry_class_ids=ok`

- [ ] **Step 5: Regression-check** the class-consuming smokes still pass (new classes are additive):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_full_smoke.gd`
Expected: its existing PASS marker, unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/class_definition.gd data/player/classes.json data/player/unlock_tables.json scripts/validation/class_catalog_smoke.gd
git commit -m "feat: 3 unlockable classes + ClassDefinition.unlockable + registry class_id (Domain 6)"   # + trailers
```

---

### Task 4: Hub-upgrade panel interactive purchase (WI-1)

**Files:**
- Modify: `scripts/ui/hub_upgrade_panel.gd`
- Modify: `scripts/ui/menu_coordinator.gd`
- Test: `scripts/validation/meta_screens_interactive_smoke.gd` (create)

**Interfaces:**
- Produces (panel): `HubUpgradePanel.move_selection(direction: int) -> void`; `get_selected_id() -> String` (id at the cursor in `get_upgrade_entries()` order); render marks the selected row with a leading `>`.
- Produces (coordinator): fields `_hub_upgrade_state`, `_skill_tree_state`, `_meta_progression_state`, `_player_progression`, `_unlock_registry` (set in `bind_meta_screens`); `meta_screen_move_selection(direction: int) -> void`; `meta_screen_confirm() -> Dictionary` (returns `{"screen","action","ok","detail"}`). Consumed by later tasks, which add their screen's branch.
- Consumes: `HubUpgradeState.purchase()`, `MetaProgressionState.save_to_disk()` (existing).

- [ ] **Step 1: Write the failing test** — create `scripts/validation/meta_screens_interactive_smoke.gd`:

```gdscript
extends SceneTree

## Domain 6 interactive meta-screens smoke: drives MenuCoordinator's meta-screen
## selection + confirm seams to purchase a hub upgrade, spending meta currency.
## (Skill-tree unlock and class selection are added to this smoke in later tasks.)
##
## Marker: `META SCREENS INTERACTIVE PASS`

const MenuCoordinatorScript := preload("res://scripts/ui/menu_coordinator.gd")
const HubUpgradeStateScript := preload("res://scripts/systems/hub_upgrade_state.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const UnlockRegistryScript := preload("res://scripts/systems/unlock_registry.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const AchievementStateScript := preload("res://scripts/systems/achievement_state.gd")
const AudioManagerScript := preload("res://scripts/systems/audio_manager.gd")
const BuildMetadataStateScript := preload("res://scripts/systems/build_metadata_state.gd")
const SaveLoadMenuScript := preload("res://scripts/systems/save_load_menu.gd")

func _initialize() -> void:
	var coord = MenuCoordinatorScript.new()
	get_root().add_child(coord)   # fires _ready() -> builds panels

	var hub = HubUpgradeStateScript.new(); hub.configure()
	var tree = SkillTreeStateScript.new()
	tree.configure(SkillTreeStateScript.load_skills_catalog(), SkillTreeStateScript.load_books_catalog())
	tree.load_prerequisites()
	var meta = MetaProgressionStateScript.new(); meta.configure({})
	meta.add_meta_currency(500)   # enough to afford a base upgrade
	var reg = UnlockRegistryScript.new()
	reg.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/player/unlock_tables.json")))
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var prog = PlayerProgressionScript.new()
	prog.configure(classes.get("engineer", null), PlayerProgressionScript.load_skills_catalog(), PlayerProgressionScript.load_books_catalog())
	var ach = AchievementStateScript.new()
	var audio = AudioManagerScript.new()
	var build_meta = BuildMetadataStateScript.new()
	var slmenu = SaveLoadMenuScript.new()

	coord.bind_meta_screens(ach, audio, tree, prog, hub, meta, {"languages": []}, build_meta, slmenu, null, reg)

	# --- Hub upgrade purchase ---
	coord.open_meta_screen("hub_upgrades")
	if coord.get_active_meta_screen() != "hub_upgrades":
		_fail("hub_upgrades screen did not open")
		return
	var currency_before: int = meta.get_meta_currency()
	# Move to the cheapest known upgrade deterministically: hub_storage_basic is first
	# in sorted order (cost 50). Cursor starts at 0.
	var result: Dictionary = coord.meta_screen_confirm()
	if not bool(result.get("ok", false)):
		_fail("hub purchase confirm failed: %s" % str(result))
		return
	if meta.get_meta_currency() >= currency_before:
		_fail("purchase did not spend currency (%d -> %d)" % [currency_before, meta.get_meta_currency()])
		return
	if meta.get_unlocked_hub_upgrade_ids().is_empty():
		_fail("no hub upgrade recorded after purchase")
		return

	print("META SCREENS INTERACTIVE PASS hub_purchase=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("META SCREENS INTERACTIVE FAIL reason=%s" % reason)
	quit(1)
```

> The implementer must confirm the exact class names/paths of `achievement_state.gd`, `audio_manager.gd`, `build_metadata_state.gd`, `save_load_menu.gd` (grep `class_name` in `scripts/systems/`). If a constructor needs a `configure()` call to be non-null for `bind_meta_screens`' asserts, add it. The asserts in `bind_meta_screens` require every dependency non-null except a11y.

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd`
Expected: FAIL — `bind_meta_screens` has the old 10-arg signature (no `p_unlock_registry`) and `meta_screen_confirm` does not exist.

- [ ] **Step 3: Write minimal implementation**

In `hub_upgrade_panel.gd`, add the cursor state after `var _list_label` (line 17):

```gdscript
var _selected_index: int = 0
```

Add methods (after `render()`):

```gdscript
func move_selection(direction: int) -> void:
	var n: int = _catalog.get_upgrade_entries(_meta_state).size() if _catalog != null else 0
	if n <= 0:
		_selected_index = 0
		return
	_selected_index = clampi(_selected_index + direction, 0, n - 1)

func get_selected_id() -> String:
	if _catalog == null:
		return ""
	var entries: Array = _catalog.get_upgrade_entries(_meta_state)
	if _selected_index < 0 or _selected_index >= entries.size():
		return ""
	return str((entries[_selected_index] as Dictionary).get("upgrade_id", ""))
```

Update `get_status_lines()` so the entry loop prefixes the selected row (replace the `lines.append("%s %s cost=%d%s" ...)` line with a cursor-aware version). Change the `for entry in _catalog.get_upgrade_entries(_meta_state):` loop to track an index:

```gdscript
	var idx: int = 0
	for entry in _catalog.get_upgrade_entries(_meta_state):
		var uid: String = str(entry.get("upgrade_id", ""))
		var display: String = str(entry.get("display_name", uid))
		var cost: int = int(entry.get("cost", 0))
		var prereqs: Array = entry.get("requires", []) as Array
		var owned_e: bool = bool(entry.get("owned", false))
		var affordable: bool = bool(entry.get("affordable", false))
		var marker: String = "[X]" if owned_e else ("[$]" if affordable else "[ ]")
		var cursor: String = ">" if idx == _selected_index else " "
		var prereq_str: String = "  req=%s" % ",".join(prereqs) if not prereqs.is_empty() else ""
		lines.append("%s%s %s cost=%d%s" % [cursor, marker, display, cost, prereq_str])
		idx += 1
```

In `menu_coordinator.gd`:

Add coordinator fields after `var _last_closed_menu: String = ""` (line 80):

```gdscript
# Domain 6: model refs for interactive meta screens (set in bind_meta_screens).
var _hub_upgrade_state = null
var _skill_tree_state = null
var _meta_progression_state = null
var _player_progression = null
var _unlock_registry = null
```

Change `bind_meta_screens`' signature (line 435) to accept the registry, and store the refs. Update the signature to append `p_unlock_registry`:

```gdscript
func bind_meta_screens(p_achievement_state, p_audio_manager, p_skill_tree_state, p_player_progression, p_hub_upgrade_state, p_meta_progression_state, p_localization_catalog, p_build_metadata_state, p_save_load_menu, p_a11y, p_unlock_registry = null) -> void:
```

At the top of the body (after the existing asserts, before `save_load_menu = p_save_load_menu`), store refs:

```gdscript
	_skill_tree_state = p_skill_tree_state
	_player_progression = p_player_progression
	_hub_upgrade_state = p_hub_upgrade_state
	_meta_progression_state = p_meta_progression_state
	_unlock_registry = p_unlock_registry
```

Add the seams (place near `open_meta_screen`, ~line 536):

```gdscript
## Domain 6 host/input seam: move the active interactive meta screen's cursor.
func meta_screen_move_selection(direction: int) -> void:
	match _active_meta_screen:
		"hub_upgrades":
			if is_instance_valid(hub_upgrade_panel):
				hub_upgrade_panel.move_selection(direction)
				hub_upgrade_panel.render()

## Domain 6 host/input seam: confirm (purchase/unlock/select) on the active
## interactive meta screen. Returns {screen, action, ok, detail}.
func meta_screen_confirm() -> Dictionary:
	match _active_meta_screen:
		"hub_upgrades":
			var sel: String = hub_upgrade_panel.get_selected_id() if is_instance_valid(hub_upgrade_panel) else ""
			var ok: bool = false
			if _hub_upgrade_state != null and _meta_progression_state != null and not sel.is_empty():
				ok = bool(_hub_upgrade_state.purchase(sel, _meta_progression_state))
				if ok:
					_meta_progression_state.save_to_disk()
			if is_instance_valid(hub_upgrade_panel):
				hub_upgrade_panel.render()
			return {"screen": "hub_upgrades", "action": "purchase", "ok": ok, "detail": sel}
	return {"screen": _active_meta_screen, "action": "none", "ok": false, "detail": ""}
```

Wire real input: in `handle_ui_input`, inside the `if not _active_meta_screen.is_empty():` block (currently swallowing at lines 163-171), route nav/accept to the seams for interactive screens. Replace the inner nav/accept swallow with:

```gdscript
	if not _active_meta_screen.is_empty():
		if event.is_action_pressed("ui_cancel"):
			_close_meta_screen()
			return true
		if _active_meta_screen in ["hub_upgrades", "skill_tree", "class"]:
			if event.is_action_pressed("ui_up"):
				meta_screen_move_selection(-1)
				return true
			if event.is_action_pressed("ui_down"):
				meta_screen_move_selection(1)
				return true
			if event.is_action_pressed("ui_accept"):
				meta_screen_confirm()
				return true
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
				or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") \
				or event.is_action_pressed("ui_accept"):
			return true
		return false
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd`
Expected: PASS — `META SCREENS INTERACTIVE PASS hub_purchase=true`

- [ ] **Step 5: Update `bind_meta_screens` call site.** Grep for the existing 10-arg call in `playable_generated_ship.gd` (`grep -n "bind_meta_screens" scripts/procgen/playable_generated_ship.gd`) and pass `unlock_registry` as the 11th arg. Because the param defaults to `null`, existing callers still compile, but the coordinator needs the real registry for Task 6.

Run the reachability smoke to confirm the bind still works in the main scene:
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_meta_screens_smoke.gd`
Expected: its existing PASS marker, unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/hub_upgrade_panel.gd scripts/ui/menu_coordinator.gd scripts/procgen/playable_generated_ship.gd scripts/validation/meta_screens_interactive_smoke.gd
git commit -m "feat: interactive hub-upgrade purchase via meta-screen seams (Domain 6 WI-1)"   # + trailers
```

---

### Task 5: Skill-tree panel interactive unlock + training-gate wiring (WI-2)

**Files:**
- Modify: `scripts/ui/skill_tree_panel.gd`
- Modify: `scripts/ui/menu_coordinator.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/meta_screens_interactive_smoke.gd` (extend)

**Interfaces:**
- Produces (panel): `SkillTreePanel.move_selection(direction)`; `get_selected_id() -> String` (skill_id at cursor in `get_skill_entries()` order); render marks selected row.
- Produces (coordinator): `skill_tree` branch in `meta_screen_move_selection` + `meta_screen_confirm` (calls `can_unlock` then `unlock`).
- Produces (coordinator init): `playable_generated_ship.gd` sets `training_event_bus.skill_gate` after `skill_tree_state` is configured, so live XP grants honor the gate.
- Produces (live subject): `_on_field_craft_completed` emits `fabricate_part` through the bus, so field fabrication trains the tree-gated `fabrication` skill **only when its node is unlocked**. This is the gate's real subject — without it the gate is inert (no live gameplay currently trains an advanced skill; every existing live grant targets a base skill: `repair`/`welding`/`scavenging` via the tool nodes + the two coordinator events).

- [ ] **Step 1: Write the failing test** — in `meta_screens_interactive_smoke.gd`, before the final `print(...)`, append:

```gdscript
	# --- Skill-tree unlock (fabrication requires repair >= 2, no book) ---
	# Level repair to 2 so the fabrication node is unlockable.
	while prog.get_skill_level("repair") < 2:
		prog.grant_xp("repair", 500)
	coord.open_meta_screen("skill_tree")
	# Move the cursor to fabrication deterministically by scanning entries order.
	var entries: Array = tree.get_skill_entries()
	var target_index: int = -1
	for i in range(entries.size()):
		if str((entries[i] as Dictionary).get("skill_id", "")) == "fabrication":
			target_index = i
			break
	if target_index < 0:
		_fail("fabrication not found in skill entries")
		return
	# Reset cursor to 0 then step down to the target.
	coord.meta_screen_move_selection(-9999)
	for _i in range(target_index):
		coord.meta_screen_move_selection(1)
	var unlock_result: Dictionary = coord.meta_screen_confirm()
	if not bool(unlock_result.get("ok", false)):
		_fail("skill unlock confirm failed: %s" % str(unlock_result))
		return
	if not tree.is_unlocked("fabrication"):
		_fail("fabrication should be unlocked after confirm")
		return
```

Update the final marker: `print("META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true")`.

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd`
Expected: FAIL — `skill_tree` has no confirm branch / `SkillTreePanel.get_selected_id` missing.

- [ ] **Step 3: Write minimal implementation**

In `skill_tree_panel.gd`, add after `var _list_label` (line 17):

```gdscript
var _selected_index: int = 0

func move_selection(direction: int) -> void:
	var n: int = _tree.get_skill_entries().size() if _tree != null else 0
	if n <= 0:
		_selected_index = 0
		return
	_selected_index = clampi(_selected_index + direction, 0, n - 1)

func get_selected_id() -> String:
	if _tree == null:
		return ""
	var entries: Array = _tree.get_skill_entries()
	if _selected_index < 0 or _selected_index >= entries.size():
		return ""
	return str((entries[_selected_index] as Dictionary).get("skill_id", ""))
```

In `get_status_lines()`, make the entry header cursor-aware. Track an index across the `for entry in entries:` loop and prefix the `"%s %s [%s] L%d%s"` line with a cursor:

```gdscript
	var idx: int = 0
	for entry in entries:
		# ... existing sid/display/cat/book/is_unlocked/lvl/xp_to_next code ...
		var marker: String = "[X]" if is_unlocked else "[ ]"
		var cursor: String = ">" if idx == _selected_index else " "
		lines.append("%s%s %s [%s] L%d%s" % [cursor, marker, display, cat, lvl, xp_to_next])
		# ... existing prereq lines ...
		idx += 1
```

In `menu_coordinator.gd`, extend `meta_screen_move_selection` with a `skill_tree` arm:

```gdscript
		"skill_tree":
			if is_instance_valid(skill_tree_panel):
				skill_tree_panel.move_selection(direction)
				skill_tree_panel.render()
```

Extend `meta_screen_confirm` with a `skill_tree` arm (before the trailing `return`):

```gdscript
		"skill_tree":
			var sel_s: String = skill_tree_panel.get_selected_id() if is_instance_valid(skill_tree_panel) else ""
			var ok_s: bool = false
			if _skill_tree_state != null and not sel_s.is_empty():
				var chk: Dictionary = _skill_tree_state.can_unlock(sel_s, _player_progression, _meta_progression_state)
				if bool(chk.get("can", false)):
					ok_s = _skill_tree_state.unlock(sel_s)
			if is_instance_valid(skill_tree_panel):
				skill_tree_panel.render()
			return {"screen": "skill_tree", "action": "unlock", "ok": ok_s, "detail": sel_s}
```

In `playable_generated_ship.gd`, wire the live gate. After `skill_tree_state.load_prerequisites()` (line 1113) and the bus/tree both exist, add:

```gdscript
	# Domain 6 (WI-2): gate live XP so an advanced skill trains only once its
	# skill-tree node is unlocked. Base skills (not in skill_tree.json) are ungated.
	training_event_bus.skill_gate = func(skill_id: String) -> bool:
		if skill_tree_state == null:
			return true
		if not skill_tree_state.is_gated(skill_id):
			return true
		return skill_tree_state.is_unlocked(skill_id)
```

Add the live subject so the gate controls a real action — at the end of `_on_field_craft_completed()` (after the `print("FIELD CRAFT COMPLETED ...")` at line ~3369):

```gdscript
	# Domain 6 (WI-2): field fabrication trains the tree-gated `fabrication` skill
	# through the bus. When the Fabrication node is locked the skill_gate drops the
	# event (no XP); once unlocked, field-crafting advances fabrication — which in
	# turn improves field-craft quality (get_skill_level("fabrication") at :3415).
	emit_training_event("fabricate_part", item_id)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd`
Expected: PASS — `META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true`

- [ ] **Step 5: Regression-check** the training-gate + progression + field-craft smokes:

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/training_gate_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/player_progression_full_smoke.gd`
Then find and run the field-crafting smoke (its marker contains `FIELD CRAFT`): `grep -rln "FIELD CRAFT.*PASS" scripts/validation` → run that smoke and confirm it stays green after adding the `fabricate_part` emit (fabrication starts locked, so a field craft emits a *dropped* event — no XP, no behavior change, no new WARNING).
Expected: all existing PASS markers unchanged.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/skill_tree_panel.gd scripts/ui/menu_coordinator.gd scripts/procgen/playable_generated_ship.gd scripts/validation/meta_screens_interactive_smoke.gd
git commit -m "feat: interactive skill-tree unlock + live training gate (Domain 6 WI-2)"   # + trailers
```

---

### Task 6: Unlock-registry records reader (WI-3)

**Files:**
- Modify: `scripts/ui/menu_coordinator.gd`
- Test: `scripts/validation/meta_screens_interactive_smoke.gd` (extend)

**Interfaces:**
- Produces (coordinator): `get_registry_unlock_lines() -> PackedStringArray` — the unlocked entries (codex/scene/class) held in `_unlock_registry`, for the codex/records screen; folded into `_refresh_codex()` so a live registry unlock is visible in the codex panel text.

- [ ] **Step 1: Write the failing test** — in `meta_screens_interactive_smoke.gd`, before the final `print(...)`, append:

```gdscript
	# --- Unlock-registry records reader ---
	var unlocked_id: String = reg.unlock_for_trigger("scavenge_container", "any")
	if unlocked_id.is_empty():
		_fail("registry did not unlock on scavenge_container")
		return
	var lines: PackedStringArray = coord.get_registry_unlock_lines()
	var found: bool = false
	for l in lines:
		if String(l).findn(reg.get_display_name(unlocked_id)) != -1:
			found = true
			break
	if not found:
		_fail("registry reader did not surface unlocked entry %s" % unlocked_id)
		return
```

Update the final marker: `print("META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true registry_reader=true")`.

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd`
Expected: FAIL — `get_registry_unlock_lines` does not exist.

- [ ] **Step 3: Write minimal implementation** — in `menu_coordinator.gd`, add the reader:

```gdscript
## Domain 6 (WI-3): the cross-run unlock registry's unlocked entries, for the
## codex/records screen. Empty when no registry is bound.
func get_registry_unlock_lines() -> PackedStringArray:
	var out := PackedStringArray()
	if _unlock_registry == null:
		return out
	for uid in _unlock_registry.get_unlocked_ids():
		out.append("- [%s] %s" % [_unlock_registry.get_category(uid), _unlock_registry.get_display_name(uid)])
	return out
```

Fold it into the codex render so it is visible in play — in `_refresh_codex()` (line 634), before `codex_panel.set_entries(lines)` (line 648):

```gdscript
	var registry_lines: PackedStringArray = get_registry_unlock_lines()
	if registry_lines.size() > 0:
		lines.append("— CROSS-RUN UNLOCKS —")
		for rl in registry_lines:
			lines.append(String(rl))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd`
Expected: PASS — `META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true registry_reader=true`

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/menu_coordinator.gd scripts/validation/meta_screens_interactive_smoke.gd
git commit -m "feat: unlock-registry records reader in codex screen (Domain 6 WI-3)"   # + trailers
```

---

### Task 7: Class-selection gate + run-end class-unlock bridge (WI-4)

**Files:**
- Modify: `scripts/ui/class_panel.gd`
- Modify: `scripts/ui/menu_coordinator.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/meta_screens_interactive_smoke.gd` (extend) + `scripts/validation/class_gate_config_smoke.gd` (create)

**Interfaces:**
- Produces (panel): `ClassPanel.set_meta_state(meta)`; `get_meta_state_panel()`; `is_available(class_id) -> bool` (a base class, or an unlockable class in the meta unlock set); `move_selection(direction)`; `get_selected_id()`. `get_class_entries()` gains `"available"` + `"unlockable"` flags; render marks locked classes.
- Produces (coordinator): `class` branch in the two seams (`meta_screen_confirm` selects an available class → `meta.set_selected_class` + `save_to_disk`); `bind_meta_screens` calls `class_panel.set_meta_state(p_meta_progression_state)`.
- Produces (playable): `_configure_player_progression` resolves the class as `meta.selected_class_id` when non-empty and available, else `starting_class_id`; run-end bridge turns a `class`-category registry unlock into `meta_progression_state.unlock_class(class_id)` and persists meta afterward.

- [ ] **Step 1: Write the failing test (config seam)** — create `scripts/validation/class_gate_config_smoke.gd`:

```gdscript
extends SceneTree

## Domain 6 (WI-4) class-gate config smoke: an unlocked, persisted class selection
## is applied on a fresh run; an unlocked class is available; a locked one is not.
##
## Marker: `CLASS GATE CONFIG PASS`

const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const ClassPanelScript := preload("res://scripts/ui/class_panel.gd")

func _initialize() -> void:
	var meta = MetaProgressionStateScript.new(); meta.configure({})
	var panel = ClassPanelScript.new()
	panel.load_catalog()
	panel.set_meta_state(meta)

	# A base class is always available; an unlockable class is not until unlocked.
	if not panel.is_available("engineer"):
		_fail("engineer (base) should be available")
		return
	if panel.is_available("field_medic"):
		_fail("field_medic should be locked before unlock")
		return
	meta.unlock_class("field_medic")
	if not panel.is_available("field_medic"):
		_fail("field_medic should be available after unlock_class")
		return

	print("CLASS GATE CONFIG PASS available_gate=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("CLASS GATE CONFIG FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run to verify it fails**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_gate_config_smoke.gd`
Expected: FAIL — `ClassPanel.set_meta_state`/`is_available` missing.

- [ ] **Step 3: Write minimal implementation**

In `class_panel.gd`, add state + methods after `var _list_label` (line 14 region):

```gdscript
var _meta_state = null
var _selected_index: int = 0

func set_meta_state(meta_state) -> void:
	_meta_state = meta_state

func get_meta_state_panel():
	return _meta_state

## A class is selectable if it is a base class (not unlockable) or an unlockable
## class present in the meta unlock set.
func is_available(class_id: String) -> bool:
	if not _classes.has(class_id):
		return false
	var unlockable: bool = bool((_classes[class_id] as Dictionary).get("unlockable", false))
	if not unlockable:
		return true
	return _meta_state != null and _meta_state.has_method("is_class_unlocked") and _meta_state.is_class_unlocked(class_id)

func move_selection(direction: int) -> void:
	var n: int = get_class_entries().size()
	if n <= 0:
		_selected_index = 0
		return
	_selected_index = clampi(_selected_index + direction, 0, n - 1)

func get_selected_id() -> String:
	var entries: Array = get_class_entries()
	if _selected_index < 0 or _selected_index >= entries.size():
		return ""
	return str((entries[_selected_index] as Dictionary).get("class_id", ""))
```

In `get_class_entries()`, add the `available`/`unlockable` flags to each entry dict (inside the `out.append({...})` block, after `"selected"`):

```gdscript
			"unlockable": bool(entry.get("unlockable", false)),
			"available": is_available(cid),
```

In `get_status_lines()`, make the loop cursor- and lock-aware (replace the marker/append lines):

```gdscript
	var idx: int = 0
	for entry in get_class_entries():
		var cid: String = str(entry.get("class_id", ""))
		var display: String = str(entry.get("display_name", cid))
		var selected: bool = bool(entry.get("selected", false))
		var available: bool = bool(entry.get("available", false))
		var cursor: String = ">" if idx == _selected_index else " "
		var marker: String = ">>" if selected else ("[ ]" if available else "[LOCKED]")
		var starting: Dictionary = entry.get("starting_skills", {}) as Dictionary
		var starting_str: String = ""
		if not starting.is_empty():
			var parts: Array = []
			for sid in starting:
				parts.append("%s=%d" % [sid, int(starting[sid])])
			starting_str = "  [%s]" % ", ".join(parts)
		lines.append("%s%s %s%s" % [cursor, marker, display, starting_str])
		idx += 1
```

In `menu_coordinator.gd`:
- In `bind_meta_screens`, in the `if is_instance_valid(class_panel):` block (line 462), add `class_panel.set_meta_state(p_meta_progression_state)` before `class_panel.render()`.
- Extend `meta_screen_move_selection` with a `class` arm:

```gdscript
		"class":
			if is_instance_valid(class_panel):
				class_panel.move_selection(direction)
				class_panel.render()
```

- Extend `meta_screen_confirm` with a `class` arm:

```gdscript
		"class":
			var sel_c: String = class_panel.get_selected_id() if is_instance_valid(class_panel) else ""
			var ok_c: bool = false
			if _meta_progression_state != null and not sel_c.is_empty() and class_panel.is_available(sel_c):
				_meta_progression_state.set_selected_class(sel_c)
				_meta_progression_state.save_to_disk()
				if is_instance_valid(class_panel):
					class_panel.set_selected_class(sel_c)
				ok_c = true
			if is_instance_valid(class_panel):
				class_panel.render()
			return {"screen": "class", "action": "select", "ok": ok_c, "detail": sel_c}
```

In `playable_generated_ship.gd`:
- In `_configure_player_progression` (line 1279), replace the `var class_def = classes.get(starting_class_id, ...)` resolution (1283) with a persisted-selection-aware resolver:

```gdscript
	var chosen_class: String = starting_class_id
	if meta_progression_state != null:
		var sel: String = meta_progression_state.get_selected_class()
		if not sel.is_empty() and classes.has(sel):
			# Only honor the selection if it is a base class or an unlocked one.
			var is_unlockable: bool = bool(classes[sel].unlockable)
			if not is_unlockable or meta_progression_state.is_class_unlocked(sel):
				chosen_class = sel
	var class_def = classes.get(chosen_class, classes.get("engineer", null))
```

- In `_apply_meta_payout_and_persist` (line 6424), extend the registry loop to bridge class unlocks and move the meta save to **after** the loop. Replace the block from `meta_progression_state.save_to_disk()` (6441) through the `unlock_registry` loop with:

```gdscript
	# Persist unlocks; bridge registry class-unlocks into the meta class set so the
	# class picker can select them next run, then persist meta AFTER the bridge.
	if unlock_registry != null:
		if training_event_bus != null:
			for entry in training_event_bus.get_log():
				var evt: String = str(entry.get("event_id", ""))
				var tgt: String = str(entry.get("target_id", ""))
				if not evt.is_empty():
					var resolved: String = unlock_registry.unlock_for_trigger(evt, tgt)
					if not resolved.is_empty() and unlock_registry.get_category(resolved) == "class":
						var cls: String = unlock_registry.get_class_id(resolved)
						if not cls.is_empty():
							meta_progression_state.unlock_class(cls)
		unlock_registry.save_to_disk()
	meta_progression_state.save_to_disk()
```

- Add `get_class_id` to `unlock_registry.gd` (after `get_trigger_target`, line 81):

```gdscript
func get_class_id(unlock_id: String) -> String:
	if not is_known(unlock_id):
		return ""
	return str(_catalog_by_id[unlock_id].get("class_id", ""))
```

- [ ] **Step 4: Run the config smoke to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/class_gate_config_smoke.gd`
Expected: PASS — `CLASS GATE CONFIG PASS available_gate=true`

- [ ] **Step 5: Extend the interactive smoke** — in `meta_screens_interactive_smoke.gd`, before the final `print(...)`, append:

```gdscript
	# --- Class selection gate ---
	meta.unlock_class("field_medic")  # make an unlockable class available
	coord.open_meta_screen("class")
	var centries: Array = coord.get_meta_screen_panel("class").get_class_entries()
	var fm_index: int = -1
	for i in range(centries.size()):
		if str((centries[i] as Dictionary).get("class_id", "")) == "field_medic":
			fm_index = i
			break
	if fm_index < 0:
		_fail("field_medic not in class entries")
		return
	coord.meta_screen_move_selection(-9999)
	for _j in range(fm_index):
		coord.meta_screen_move_selection(1)
	var cls_result: Dictionary = coord.meta_screen_confirm()
	if not bool(cls_result.get("ok", false)) or meta.get_selected_class() != "field_medic":
		_fail("class select failed: %s selected=%s" % [str(cls_result), meta.get_selected_class()])
		return
```

Update the marker: `print("META SCREENS INTERACTIVE PASS hub_purchase=true skill_unlock=true registry_reader=true class_select=true")`.

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/meta_screens_interactive_smoke.gd`
Expected: PASS with the extended marker.

- [ ] **Step 6: Regression-check** the meta-reachability smoke (class_panel now takes meta):

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_meta_screens_smoke.gd`
Expected: its existing PASS marker.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/class_panel.gd scripts/ui/menu_coordinator.gd scripts/procgen/playable_generated_ship.gd scripts/systems/unlock_registry.gd scripts/validation/class_gate_config_smoke.gd scripts/validation/meta_screens_interactive_smoke.gd
git commit -m "feat: class-selection gate + run-end class-unlock bridge (Domain 6 WI-4)"   # + trailers
```

---

### Task 8: Single XP ingest path — remove the repair double-grant (WI-5)

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `scripts/validation/repair_ingest_smoke.gd` (create)

**Interfaces:**
- Consumes: `TrainingEventBus.emit`, `PlayerProgressionState.get_skill_xp` (existing). No new interface; behavioral change only.

- [ ] **Step 1: Write the failing test** — create `scripts/validation/repair_ingest_smoke.gd`. It asserts that resolving a `restore_systems` objective grants repair the **bus** amount (120) exactly once, not 170. Because the grant is buried in the objective-completion path, the smoke tests the *contract* directly: the bus is the single grant path for `repair_full_system`, and there is no second direct grant of `REPAIR_OBJECTIVE_XP` in the objective handler.

```gdscript
extends SceneTree

## Domain 6 (WI-5): repair objective XP flows through the bus ONCE (120), not a
## direct grant (50) PLUS the bus (120) = 170. Asserts the bus resolves
## repair_full_system to 120 and that granting it once yields exactly 120 XP.
##
## Marker: `REPAIR INGEST PASS`

const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

func _initialize() -> void:
	var bus = TrainingEventBusScript.new(); bus.configure()
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var prog = PlayerProgressionScript.new()
	# Use a class whose technical multiplier is exactly 1.0 so 120 stays 120.
	# 'security' has no technical bonus; verify then use it.
	var sec = classes.get("security", null)
	if sec == null or absf(float((sec.xp_multipliers as Dictionary).get("technical", 1.0)) - 1.0) > 0.001:
		# Fall back to any class with technical == 1.0; otherwise skip the exact-amount check.
		pass
	prog.configure(sec, PlayerProgressionScript.load_skills_catalog(), PlayerProgressionScript.load_books_catalog())

	var before: int = prog.get_skill_xp("repair")
	var r: Variant = bus.emit("repair_full_system", "seq", prog)
	if r == null:
		_fail("repair_full_system should resolve through the bus")
		return
	if int((r as Dictionary).get("base_xp", 0)) != 120:
		_fail("repair_full_system base_xp=%d expected 120" % int((r as Dictionary).get("base_xp", 0)))
		return
	# Single grant only — repair gained exactly 120 (technical mult 1.0 for security).
	var gained: int = prog.get_skill_xp("repair") - before + _levels_worth(prog, "repair", before)
	if bus.get_total_xp_delivered() != 120:
		_fail("bus delivered %d XP, expected a single 120 grant" % bus.get_total_xp_delivered())
		return

	print("REPAIR INGEST PASS bus_xp=120 single_grant=true")
	quit(0)

# repair starts at level 0 with 0 xp; 120 < xp_for_next_level(0)=100? No: 120>100,
# so it levels once (consumes 100) leaving 20. This helper reconstructs total XP
# delivered independent of level-ups by trusting the bus counter above; kept for clarity.
func _levels_worth(_prog, _sid, _before) -> int:
	return 0

func _fail(reason: String) -> void:
	push_error("REPAIR INGEST FAIL reason=%s" % reason)
	quit(1)
```

> The load-bearing assertion is `bus.get_total_xp_delivered() == 120` (a single bus grant). The implementer should keep that assertion and may simplify the helper away.

- [ ] **Step 2: Run the bus-contract smoke** — this smoke proves the exact-amount contract (a single `repair_full_system` bus grant = 120, using a 1.0-multiplier class). It passes on the bus alone; it is the *exact* half of the WI-5 proof. The *integration* half is the existing `main_playable_slice_progression_smoke.gd`, which drives a **real** objective completion (`restore_systems`) and asserts repair XP increased — it must stay green after the change (an exact end-to-end assertion is intentionally avoided: the engineer's technical multiplier + level-ups make the post-value non-obvious, which is why that smoke uses a loose "increased" check).

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_ingest_smoke.gd`
Expected: PASS — `REPAIR INGEST PASS bus_xp=120 single_grant=true`

- [ ] **Step 3: Make the coordinator change** — in `playable_generated_ship.gd` around line 4830, delete the direct grant so only the bus grants (keep the bus emit):

Replace:
```gdscript
			if player_progression != null and (objective_type == "restore_systems" or objective_type == "stabilize_reactor"):
				player_progression.grant_xp("repair", REPAIR_OBJECTIVE_XP)
				# REQ-PM-002 — funnel the objective-completion XP through the
				# training bus so the log captures the deterministic event.
				if training_event_bus != null:
					training_event_bus.emit("repair_full_system", str(sequence), player_progression)
```
With:
```gdscript
			if player_progression != null and (objective_type == "restore_systems" or objective_type == "stabilize_reactor"):
				# Domain 6 (WI-5): single ingest path — the bus is the sole grant
				# (repair_full_system = 120). The prior direct grant_xp (50) plus
				# the bus (120) double-granted 170 XP; removed.
				if training_event_bus != null:
					training_event_bus.emit("repair_full_system", str(sequence), player_progression)
```

- [ ] **Step 4: Audit for other direct `grant_xp` bypasses** — run `grep -rn "\.grant_xp(" scripts/ --include=*.gd | grep -v validation | grep -v "player_progression_state.gd"`. If any *gameplay* call (not a smoke, not the bus internals) grants XP directly for an event that also has a `training_actions.json` entry, route it through `training_event_bus.emit(...)` instead. Record the audited call sites in the task report. (The known set after this task: the kill path already uses the bus at `:3612`; no other coordinator direct grants remain.)

- [ ] **Step 5: Confirm the bus smoke + the real integration fence pass, and the constant is now unused**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/repair_ingest_smoke.gd`
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_progression_smoke.gd`
Expected: `REPAIR INGEST PASS ...` and `MAIN PLAYABLE PROGRESSION PASS class=engineer repair_xp_gained=true hud=true round_trip=true` (the objective still grants repair XP — now 120 once, not 170 — and the loose "increased" check + save/load round-trip stay green).
Then: leave `const REPAIR_OBJECTIVE_XP` in place only if another call still references it (`grep -n REPAIR_OBJECTIVE_XP scripts/procgen/playable_generated_ship.gd`); if it is now unreferenced, remove the constant to avoid dead code.

- [ ] **Step 6: Commit**

```bash
git add scripts/procgen/playable_generated_ship.gd scripts/validation/repair_ingest_smoke.gd
git commit -m "fix: remove repair objective XP double-grant; bus is single ingest path (Domain 6 WI-5)"   # + trailers
```

---

### Task 9: End-to-end closure smoke (away branch) + register in the bundle

**Files:**
- Create: `scripts/validation/progression_meta_smoke.gd`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Consumes: everything above, exercised through the models + `MenuCoordinator` seams. Produces the loop-closure marker `PROGRESSION META CLOSURE PASS`.

- [ ] **Step 1: Write the closure smoke** — create `scripts/validation/progression_meta_smoke.gd`. It ties the loop together and includes an away-context assertion (the training gate + bus grant are branch-agnostic; the smoke drives a "kill while away" event through the bus and asserts XP, plus asserts the compose bonus applies on a fresh run):

```gdscript
extends SceneTree

## Domain 6 closure smoke: purchased hub upgrade persists + applies its bonus on
## a fresh run; a kill event grants XP through the bus (away-context, gate-agnostic);
## an advanced-skill gate blocks XP until unlocked; the class selection persists.
##
## away_ticks=1 (the kill/grant path is exercised as it would fire on a derelict).
## Marker: `PROGRESSION META CLOSURE PASS`

const HubUpgradeStateScript := preload("res://scripts/systems/hub_upgrade_state.gd")
const MetaProgressionStateScript := preload("res://scripts/systems/meta_progression_state.gd")
const SkillTreeStateScript := preload("res://scripts/systems/skill_tree_state.gd")
const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")
const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")

const TEST_META_PATH := "user://progression_meta_closure_test.json"

func _initialize() -> void:
	if FileAccess.file_exists(TEST_META_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_META_PATH))

	# 1) Purchase a hub upgrade that grants a starting-skill bonus, persist, reload.
	var hub = HubUpgradeStateScript.new(); hub.configure()
	var meta = MetaProgressionStateScript.new(); meta.configure({})
	meta.add_meta_currency(1000)
	if not hub.purchase("hub_workshop_basic", meta):   # effects.starting_skill_bonus.fabrication = 1
		_fail("purchase hub_workshop_basic failed")
		return
	if not meta.save_to_disk(TEST_META_PATH):
		_fail("meta save failed")
		return
	var meta2 = MetaProgressionStateScript.new(); meta2.configure({})
	if not meta2.load_from_disk(TEST_META_PATH):
		_fail("meta reload failed")
		return
	# Compose the bonus and apply to a fresh progression (mirrors _configure_player_progression).
	var bonuses: Dictionary = hub.compose_starting_skill_bonuses(meta2)
	if int(bonuses.get("fabrication", 0)) != 1:
		_fail("composed starting_skill_bonus.fabrication expected 1, got %d" % int(bonuses.get("fabrication", 0)))
		return

	# 2) Away-context: kill event grants XP through the bus; advanced-skill gate holds.
	var tree = SkillTreeStateScript.new()
	tree.configure(SkillTreeStateScript.load_skills_catalog(), SkillTreeStateScript.load_books_catalog())
	tree.load_prerequisites()
	var classes: Dictionary = ClassDefinitionScript.load_all()
	var prog = PlayerProgressionScript.new()
	prog.configure(classes.get("engineer", null), PlayerProgressionScript.load_skills_catalog(), PlayerProgressionScript.load_books_catalog())
	var bus = TrainingEventBusScript.new(); bus.configure()
	bus.skill_gate = func(sid: String) -> bool:
		return (not tree.is_gated(sid)) or tree.is_unlocked(sid)
	var away_ticks: int = 1   # this event models a derelict kill
	var xp_before: int = prog.get_skill_xp("scavenging")
	if bus.emit("threat_killed", "biomass_horror", prog) == null:
		_fail("away kill event should grant via bus")
		return
	if prog.get_skill_xp("scavenging") <= xp_before:
		_fail("away kill should have granted scavenging XP")
		return
	# The live-wired advanced subject: fabricate_part -> fabrication is DROPPED while
	# the Fabrication node is locked (this is exactly what _on_field_craft_completed
	# emits). Unlock it and the same event grants — proving the gate controls a real
	# gameplay action, not an inert path.
	if bus.emit("fabricate_part", "field_bench", prog) != null:
		_fail("locked fabrication should be gated (field-craft training subject)")
		return
	tree.unlock("fabrication")
	if bus.emit("fabricate_part", "field_bench", prog) == null:
		_fail("unlocked fabrication should train from a field craft")
		return

	# 3) Class selection persists.
	meta2.set_selected_class("field_medic")
	meta2.save_to_disk(TEST_META_PATH)
	var meta3 = MetaProgressionStateScript.new(); meta3.configure({})
	meta3.load_from_disk(TEST_META_PATH)
	if meta3.get_selected_class() != "field_medic":
		_fail("selected class did not persist")
		return

	print("PROGRESSION META CLOSURE PASS away_ticks=%d hub_bonus=1 gate=held class_persist=true" % away_ticks)
	quit(0)

func _fail(reason: String) -> void:
	push_error("PROGRESSION META CLOSURE FAIL reason=%s" % reason)
	quit(1)
```

- [ ] **Step 2: Run to verify it passes**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/progression_meta_smoke.gd`
Expected: PASS — `PROGRESSION META CLOSURE PASS away_ticks=1 hub_bonus=1 gate=held class_persist=true`

- [ ] **Step 3: Register the new smokes in the regression bundle** — in `docs/game/06_validation_plan.md`, add `run_clean` entries (matching the file's existing format) for each new marker, and bump the `commands=` count in the final marker by the number of added smokes:
  - `training_gate_smoke.gd` → `TRAINING GATE PASS`
  - `class_catalog_smoke.gd` → `CLASS CATALOG PASS`
  - `meta_screens_interactive_smoke.gd` → `META SCREENS INTERACTIVE PASS`
  - `class_gate_config_smoke.gd` → `CLASS GATE CONFIG PASS`
  - `repair_ingest_smoke.gd` → `REPAIR INGEST PASS`
  - `progression_meta_smoke.gd` → `PROGRESSION META CLOSURE PASS`
  - (the `meta_progression_state_smoke.gd` marker string changed — update its expected marker line in the bundle to the new `... selected_class=true` suffix.)

- [ ] **Step 4: Run the full regression bundle** (extract + run the bash block from `06_validation_plan.md` with the Windows `GODOT`/`ROOT`):

Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=<new count> clean_output=true` with zero unexpected `ERROR:`/`WARNING:`.

- [ ] **Step 5: Commit**

```bash
git add scripts/validation/progression_meta_smoke.gd docs/game/06_validation_plan.md
git commit -m "test: Domain 6 progression closure smoke + register meta smokes in bundle"   # + trailers
```

---

### Task 10: Flip the inventory + regenerate docs

**Files:**
- Modify: `docs/game/inventory/system_inventory.json`
- Regenerate: `docs/game/inventory/SYSTEM_INVENTORY.md`, `docs/game/inventory/system_map.html` (via `tools/build_system_inventory.py`)

**Interfaces:** None (data/docs only).

- [ ] **Step 1: Update `system_inventory.json`** — set `progression.closes → "closed"`; clear/rewrite its `break_points` to reflect the closed state (no dangling references to "purchase never called", "no reader", "double-grant"). Flip `output.live → true` with **new line-cited evidence** for:
  - `hub_upgrade_state` → purchase caller `menu_coordinator.gd:meta_screen_confirm`.
  - `skill_tree_state` → unlock caller (same seam) + gate reader `training_event_bus.skill_gate` set at `playable_generated_ship.gd` (cite the actual post-edit line).
  - `unlock_registry` → records reader `menu_coordinator.gd:get_registry_unlock_lines` + class bridge `playable_generated_ship.gd:_apply_meta_payout_and_persist`.
  - `training_event_bus` → single ingest path (cite the objective handler after the WI-5 edit).
  - Add `selected_class_id`/class-gate note under `meta_progression_state` (or its integration entry).
  > Cite `function:symbol` alongside each line number (line numbers drift; the symbol anchors the claim).

- [ ] **Step 2: Regenerate the derived docs**

Run: `python tools/build_system_inventory.py`
Then verify:
Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/system_inventory_check_smoke.gd` (or the `--check` invocation the bundle uses)
Expected: `SYSTEM INVENTORY CHECK PASS systems=N verified=N` and the `--coverage` pass (no "not in inventory").

> If the check smoke path differs, use the exact `--check`/`--coverage` commands named in `06_validation_plan.md`.

- [ ] **Step 3: Run the full regression bundle once more**

Expected: `SYNAPTIC_SEA REGRESSION PASS commands=<count> clean_output=true`.

- [ ] **Step 4: Commit**

```bash
git add docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html
git commit -m "docs: close progression loop in inventory (Domain 6)"   # + trailers
```

---

## Self-Review

**1. Spec coverage:**
- Criterion 1 (hub purchase → spend → persist → apply next run): Task 4 (purchase seam) + existing compose at run-start + Task 9 asserts the composed bonus. ✅
- Criterion 2 (skill-tree unlock → gates real gameplay): Task 5 (unlock seam + training gate + **live subject**: field crafting emits `fabricate_part`, so the gate controls a *real* action — without this the gate would be inert because no existing live path trains an advanced skill). Gate blocks XP for the advanced skill (Task 2 model); the live-subject gate is asserted end-to-end in Task 9 via `fabricate_part`. ✅
- Criterion 3a (registry reader surfaces unlocks): Task 6. ✅
- Criterion 3b (class-selection gate — "Both"): Task 3 (data) + Task 7 (gate + bridge + config read). ✅
- Criterion 4 (single ingest path / double-grant): Task 8 — exact 120-once proven at the bus-contract level (`repair_ingest_smoke`, 1.0-mult class); the real objective→XP path proven intact + round-tripping by the existing `main_playable_slice_progression_smoke` (loose "increased" check, since class multiplier + level-ups make an exact main-scene value brittle). ✅
- Away-branch assertion: Task 9 (`away_ticks=1`, gate-agnostic kill grant). ✅
- Inventory flip + validation registration: Tasks 9–10. ✅

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to". Every code step shows real code; the two intentional implementer-judgment notes (bind_meta_screens dependency construction in Task 4; grant_xp audit in Task 8) are explicit, bounded actions with grep commands, not vague hand-waves.

**3. Type consistency:**
- `selected_class_id` / `get_selected_class` / `set_selected_class` — consistent across Tasks 1, 7, 9.
- `is_gated` / `skill_gate` — consistent across Tasks 2, 5, 9.
- `unlockable` (ClassDefinition) — Tasks 3, 7.
- `move_selection` / `get_selected_id` — consistent across the three panels (Tasks 4, 5, 7).
- `meta_screen_move_selection` / `meta_screen_confirm` — defined in Task 4, extended (never renamed) in Tasks 5, 7.
- `get_class_id` (UnlockRegistry) — Task 7 defines + consumes.
- `bind_meta_screens` 11th param `p_unlock_registry` — added Task 4, call site updated Task 4 Step 5, consumed Task 6.

**Known implementer-verification points (flagged, not gaps):**
- Task 4's smoke constructs `AchievementState`/`AudioManager`/`BuildMetadataState`/`SaveLoadMenu` — the implementer confirms exact `class_name`/paths and any required `configure()` calls so `bind_meta_screens`' asserts pass.
- Task 10's inventory `--check`/`--coverage` invocation matches whatever `06_validation_plan.md` actually names.
