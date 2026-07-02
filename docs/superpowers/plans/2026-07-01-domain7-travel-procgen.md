# Domain 7: Travel / Procgen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flip the `travel` loop from `partial` → `closed` by making procgen derelicts actually vary — variant-driven loot bias, state-level fire/breach hazards, observable dressing, difficulty-gated structural-template variety — and retire the orphaned legacy generator.

**Architecture:** The `RoomVariantSelector` already picks a deterministic variant string per room (written into the room dict by `RoomAssigner`, serialized by `LayoutSerializer`). This plan adds the missing *consumers*: a code-side `VARIANT_EFFECTS` table maps each variant to `{sim:{loot_bias, hazard}, dressing}`; `GameplaySliceBuilder` applies `loot_bias`; the runtime coordinator seeds live fire (`_seed_derelict_fire`) and breach (`_seed_derelict_breaches`) hazards on the boarded-derelict (away) branch for compartment-mapped rooms; `GeneratedShipLoader` surfaces dressing. `ShipGenerator` enables extended templates on high-difficulty runs. Everything stays deterministic per seed.

**Tech Stack:** Godot 4.6.2, typed GDScript. Headless `SceneTree` smokes are the test harness.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (use the `_console` build headless).
- **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- **Run one smoke:** `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd`
- **`--script` can exit 0 on parse/load errors** — never trust exit code alone; confirm the PASS marker printed and no parse error appeared.
- **Both `_process` branches.** Any per-frame or per-build system MUST work on the `away_from_start` (derelict) branch, not only home. The hazard tasks here run on the derelict build path specifically; the away-branch smoke assertion is mandatory.
- **Typed GDScript** for all new code; Resources are data, Nodes are behavior.
- **Baseline noise allowlist** (ignore, not failures): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit ...`. Any *other* `ERROR:`/`WARNING:` blocks completion.
- **Valid `loot_table` keys** (`data/items/loot_tables.json`): `generic_crate`, `generic_locker`, `salvage_engineering`, `salvage_cargo`, `repair_parts_common`, `repair_parts_starter`, `repair_tools`, `hidden_cache`, `combat_drop_common`. `loot_bias` must reference one of these.
- **Compartment universe** (fixed, both `FIRE_COMPARTMENT_SYSTEM` and `data/ship_systems/hull_compartments.json`): `bridge`, `engineering`, `hydroponics`, `cargo`. Variant hazards only bite on rooms whose role maps to one of these.
- **Conventional Commits**; commit after each task. Commit trailer: `Claude-Session: https://claude.ai/code/session_01FEKLPLRTxYaxnVhA6XWAgP`
- **Spec:** `docs/superpowers/specs/2026-07-01-domain7-travel-procgen-design.md`.

---

## File Structure

- `scripts/procgen/room_variant_selector.gd` — MODIFY: add `"breached"` variant to compartment-mapped role lists; add `VARIANT_EFFECTS` const + `effects_for()`. (Task 1)
- `scripts/procgen/gameplay_slice_builder.gd` — MODIFY: apply `loot_bias` to per-room objective + container `loot_table`. (Task 2)
- `scripts/procgen/playable_generated_ship.gd` — MODIFY: role→compartment map, fire-variant ignite in `_seed_derelict_fire`, new `_seed_derelict_breaches`. (Tasks 3, 4)
- `scripts/systems/ship_instance.gd` — MODIFY: add `breach_seeded` flag mirroring `fire_seeded`. (Task 4)
- `scripts/procgen/generated_ship_loader.gd` — MODIFY: read room `variant`, set a `variant_descriptor` room-meta / select existing dressing prop. (Task 5)
- `scripts/procgen/ship_generator.gd` — MODIFY: difficulty-gate `extended_templates`. (Task 6)
- `scripts/procgen/room_graph_generator.gd` — MODIFY: deprecation banner. (Task 7)
- `scripts/validation/room_variant_selector_smoke.gd` — MODIFY: assert `effects_for` payloads. (Task 1)
- `scripts/validation/procgen_variation_smoke.gd` — CREATE: variant variation, loot-bias, template gating, determinism. (Task 8)
- `scripts/validation/procgen_variant_hazard_smoke.gd` — CREATE: away-branch fire + breach seeding, determinism. (Task 8)
- `docs/game/06_validation_plan.md` — MODIFY: register both markers + bundle. (Task 8)
- `docs/game/inventory/system_inventory.json` (+ regenerated `SYSTEM_INVENTORY.md`, `system_map.html`) — MODIFY: `travel.closes → closed`, break-points, deprecation. (Task 9)
- `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md` — MODIFY: rewrite Domain 7 "definition of closed #1". (Task 9)

---

## Task 1: `VARIANT_EFFECTS` table + `effects_for()`

**Files:**
- Modify: `scripts/procgen/room_variant_selector.gd`
- Test: `scripts/validation/room_variant_selector_smoke.gd`

**Interfaces:**
- Produces: `func effects_for(variant: String) -> Dictionary` — returns `{}` for unmapped variants, else `{"sim": {"loot_bias": String (optional), "hazard": {"kind": String, "weight": float} (optional)}, "dressing": String (optional)}`. `hazard.kind` ∈ `{"fire","breach"}`.

- [ ] **Step 1: Add a `"breached"` variant to the two compartment-mapped role lists** so breach hazards can actually land on a compartment.

In `scripts/procgen/room_variant_selector.gd`, edit the `VARIANTS_BY_ROLE` entries for `cargo` and `engineering`:

```gdscript
	"cargo": [
		"standard", "hold", "refrigerated", "secure", "empty_hold", "breached",
	],
	# ...
	"engineering": [
		"standard", "reactor", "life_support", "propulsion", "burned_out", "breached",
	],
```

- [ ] **Step 2: Add the `VARIANT_EFFECTS` const + `effects_for()`** after the `VARIANTS_BY_ROLE` const block (after line 103).

```gdscript
# Variant -> gameplay/dressing effect payload. Sparse: only variants with a
# real consequence appear; everything else resolves to {} (neutral) via
# effects_for(). `sim.loot_bias` must be a key in data/items/loot_tables.json.
# `sim.hazard.kind` is "fire" or "breach" and only bites on compartment-mapped
# rooms (bridge/engineering/hydroponics/cargo). `weight` is reserved for future
# probabilistic seeding; state-level seeding today treats presence as forced.
const VARIANT_EFFECTS: Dictionary = {
	# --- fire ---
	"burned_out":   {"sim": {"loot_bias": "salvage_engineering", "hazard": {"kind": "fire", "weight": 0.6}}, "dressing": "scorch"},
	"unstable":     {"sim": {"hazard": {"kind": "fire", "weight": 0.5}}, "dressing": "sparks"},
	# --- breach ---
	"breached":     {"sim": {"loot_bias": "salvage_cargo", "hazard": {"kind": "breach", "weight": 0.6}}, "dressing": "vacuum"},
	"collapsed":    {"sim": {"hazard": {"kind": "breach", "weight": 0.4}}, "dressing": "rubble"},
	# --- loot-bias only ---
	"refrigerated": {"sim": {"loot_bias": "salvage_cargo"}, "dressing": "frost"},
	"secure":       {"sim": {"loot_bias": "hidden_cache"}, "dressing": "locked"},
	"triage":       {"sim": {"loot_bias": "repair_parts_common"}, "dressing": "medical"},
	# --- dressing only ---
	"flooded":      {"dressing": "water_plane"},
	"biomatter_crusted": {"dressing": "biomatter"},
	"contaminated": {"dressing": "haze"},
}


# Returns the effect payload for `variant`, or an empty Dictionary for
# unmapped variants (neutral: no loot bias, no hazard, no dressing).
func effects_for(variant: String) -> Dictionary:
	var raw: Variant = VARIANT_EFFECTS.get(variant, {})
	if raw is Dictionary:
		return (raw as Dictionary).duplicate(true)
	return {}
```

- [ ] **Step 3: Add assertions to the existing selector smoke.** In `scripts/validation/room_variant_selector_smoke.gd`, insert before the final PASS print (find the `print(...PASS...)` line near the end):

```gdscript
	# --- Case 10: effects_for returns a hazard payload for a fire variant ---
	var burned: Dictionary = selector.effects_for("burned_out")
	var burned_hazard: Dictionary = (burned.get("sim", {}) as Dictionary).get("hazard", {})
	if str(burned_hazard.get("kind", "")) != "fire":
		push_error("ROOM VARIANT SELECTOR FAIL burned_out hazard kind != fire: %s" % str(burned_hazard))
		quit(1)
		return

	# --- Case 11: effects_for returns a breach payload for the breach variant ---
	var breached: Dictionary = selector.effects_for("breached")
	var breached_hazard: Dictionary = (breached.get("sim", {}) as Dictionary).get("hazard", {})
	if str(breached_hazard.get("kind", "")) != "breach":
		push_error("ROOM VARIANT SELECTOR FAIL breached hazard kind != breach: %s" % str(breached_hazard))
		quit(1)
		return

	# --- Case 12: unmapped variant returns empty effects ---
	if not selector.effects_for("standard").is_empty():
		push_error("ROOM VARIANT SELECTOR FAIL standard should have empty effects")
		quit(1)
		return

	# --- Case 13: loot_bias keys are real loot tables ---
	var loot_doc: Dictionary = _load_loot_tables()
	for v: String in ["burned_out", "breached", "refrigerated", "secure", "triage"]:
		var bias: String = str((selector.effects_for(v).get("sim", {}) as Dictionary).get("loot_bias", ""))
		if not bias.is_empty() and not loot_doc.has(bias):
			push_error("ROOM VARIANT SELECTOR FAIL loot_bias '%s' for variant '%s' not in loot_tables.json" % [bias, v])
			quit(1)
			return
```

Add this helper at the bottom of the smoke file:

```gdscript
func _load_loot_tables() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://data/items/loot_tables.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
```

- [ ] **Step 4: Run the smoke, verify PASS.**

Run:
```bash
GODOT="C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe"
ROOT="C:/Users/dasbl/Documents/The Synaptic Sea"
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_variant_selector_smoke.gd
```
Expected: prints `ROOM VARIANT SELECTOR ... PASS ...` with no `push_error` output and no non-allowlisted `ERROR:`/`WARNING:`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/procgen/room_variant_selector.gd scripts/validation/room_variant_selector_smoke.gd
git commit -m "feat: variant effect payloads (VARIANT_EFFECTS + effects_for) — Domain 7"
```

---

## Task 2: `loot_bias` consumer in `GameplaySliceBuilder`

**Files:**
- Modify: `scripts/procgen/gameplay_slice_builder.gd`
- Test: covered by `procgen_variation_smoke.gd` (Task 8)

**Interfaces:**
- Consumes: `RoomVariantSelector.effects_for(variant)` (Task 1). Reads each room's existing `variant` key.
- Produces: objectives/containers whose `loot_table` reflects the room variant's `loot_bias` when present.

- [ ] **Step 1: Add the selector + a variant-loot helper.** At the top of `scripts/procgen/gameplay_slice_builder.gd`, after the `CONNECTIVE_ROLES` const (line 12), add:

```gdscript
const RoomVariantSelectorScript := preload("res://scripts/procgen/room_variant_selector.gd")
var _variant_selector: RefCounted = RoomVariantSelectorScript.new()


# Returns the loot_table key a room should use: the variant's loot_bias when
# present and non-empty, otherwise the supplied role-derived default.
func _loot_table_for_room(room: Dictionary, role_default: String) -> String:
	var variant: String = str(room.get("variant", "standard"))
	var bias: String = str((_variant_selector.effects_for(variant).get("sim", {}) as Dictionary).get("loot_bias", ""))
	return bias if not bias.is_empty() else role_default
```

- [ ] **Step 2: Apply the bias to the salvage objective.** In `build()`, change the objective append (line 59) from:

```gdscript
			"loot_table": _salvage_loot_table_for_role(role),
```
to:
```gdscript
			"loot_table": _loot_table_for_room(room, _salvage_loot_table_for_role(role)),
```

- [ ] **Step 3: Apply the bias to the loot container.** In the container loop, change (line 96) from:

```gdscript
			"loot_table": kind2,
```
to:
```gdscript
			"loot_table": _loot_table_for_room(room, kind2),
```

- [ ] **Step 4: Parse-check via a one-off.** Run the existing gameplay smoke to confirm no regression:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_ship_gameplay_smoke.gd
```
Expected: its existing PASS marker prints, no new `ERROR:`/`WARNING:`.

- [ ] **Step 5: Commit.**

```bash
git add scripts/procgen/gameplay_slice_builder.gd
git commit -m "feat: variant loot_bias overrides room loot_table in slice builder — Domain 7"
```

---

## Task 3: Fire-variant state wiring in `_seed_derelict_fire`

**Files:**
- Modify: `scripts/procgen/playable_generated_ship.gd`
- Test: `procgen_variant_hazard_smoke.gd` (Task 8)

**Interfaces:**
- Consumes: `current_ship.built_layout` / `loader.get_layout_copy()` rooms (each has `room_role` + `variant`); `RoomVariantSelector.effects_for`; `FIRE_COMPARTMENT_SYSTEM`.
- Produces: `func _variant_hazard_compartments(kind: String) -> Array` (returns compartment ids for rooms whose variant hazard kind matches); fire-variant compartments ignited in `_seed_derelict_fire`.

- [ ] **Step 1: Add the role→compartment map + variant-hazard scanner.** In `scripts/procgen/playable_generated_ship.gd`, after the `FIRE_COMPARTMENT_SYSTEM` const (line 274), add:

```gdscript
# Maps a room ROLE to the hull/fire compartment it belongs to. Only these
# compartments exist (data/ship_systems/hull_compartments.json + FIRE_COMPARTMENT_SYSTEM),
# so variant hazards on other roles are loot/dressing-only.
const COMPARTMENT_FOR_ROLE := {
	"bridge": "bridge",
	"cockpit": "bridge",
	"engineering": "engineering",
	"reactor": "engineering",
	"engine_bay": "engineering",
	"hydroponics": "hydroponics",
	"cargo": "cargo",
	"storage": "cargo",
}
const RoomVariantSelectorHazardScript := preload("res://scripts/procgen/room_variant_selector.gd")
```

Then add this helper near `_seed_derelict_fire` (before line 2770):

```gdscript
## Scans the boarded derelict's built layout for rooms whose variant carries a
## hazard of `kind` ("fire" or "breach") AND whose role maps to a real
## compartment. Returns the deterministic, de-duplicated, sorted compartment id
## list. Empty when no such variant landed on a mapped role.
func _variant_hazard_compartments(kind: String) -> Array:
	var out: Dictionary = {}
	if current_ship == null:
		return []
	var layout: Dictionary = current_ship.built_layout
	if layout.is_empty() and loader != null and loader.has_method("get_layout_copy"):
		layout = loader.get_layout_copy()
	var rooms_variant: Variant = layout.get("rooms", [])
	if not (rooms_variant is Array):
		return []
	var selector := RoomVariantSelectorHazardScript.new()
	for room_variant in (rooms_variant as Array):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var role: String = str(room.get("room_role", room.get("role", "")))
		var compartment: String = str(COMPARTMENT_FOR_ROLE.get(role, ""))
		if compartment.is_empty():
			continue
		var variant: String = str(room.get("variant", "standard"))
		var hazard: Dictionary = (selector.effects_for(variant).get("sim", {}) as Dictionary).get("hazard", {})
		if str(hazard.get("kind", "")) == kind:
			out[compartment] = true
	var result: Array = out.keys()
	result.sort()
	return result
```

- [ ] **Step 2: Ignite fire-variant compartments in `_seed_derelict_fire`.** In `_seed_derelict_fire()` (line 2770), the current body returns early when the presence gate fails (line 2784-2785). Replace the presence-gate early-return block:

```gdscript
	# Presence gate — most derelicts board fire-free.
	if (abs(hash("%d:fire_presence" % seed_int)) % 100) >= FIRE_PRESENCE_PERCENT:
		return
```
with:
```gdscript
	# Variant-forced fire: a fire-kind variant on a compartment-mapped room
	# means that derelict burns there regardless of the presence roll.
	var forced_fire: Array = _variant_hazard_compartments("fire")
	for cid in forced_fire:
		fs.ignite(str(cid), 1.0)
	# Presence gate — most derelicts board fire-free (variant fires already lit).
	if (abs(hash("%d:fire_presence" % seed_int)) % 100) >= FIRE_PRESENCE_PERCENT:
		return
```

(The existing damaged-system candidate loop below still runs when the presence gate passes; variant fires are additive and deterministic.)

- [ ] **Step 3: Run the hazard smoke (created in Task 8) — deferred.** Note: this task's assertion lives in `procgen_variant_hazard_smoke.gd`. For now, parse-check by running any main-scene smoke to confirm no parse error:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_closure_smoke.gd
```
Expected: `SHIP SYSTEMS CLOSURE PASS ...` still prints (no parse regression in the coordinator).

- [ ] **Step 4: Commit.**

```bash
git add scripts/procgen/playable_generated_ship.gd
git commit -m "feat: fire-variant rooms force live derelict ignition — Domain 7"
```

---

## Task 4: Breach-variant state wiring (`_seed_derelict_breaches` + `breach_seeded`)

**Files:**
- Modify: `scripts/systems/ship_instance.gd`, `scripts/procgen/playable_generated_ship.gd`
- Test: `procgen_variant_hazard_smoke.gd` (Task 8)

**Interfaces:**
- Consumes: `_variant_hazard_compartments("breach")` (Task 3); `hull_integrity_state.damage_compartment(id, amount, force_breach)`.
- Produces: `func _seed_derelict_breaches() -> void`; `ShipInstance.breach_seeded: bool`.

- [ ] **Step 1: Add the `breach_seeded` flag.** In `scripts/systems/ship_instance.gd`, find the `fire_seeded` var declaration and add next to it:

```gdscript
var breach_seeded: bool = false
```

(If `fire_seeded` is included in `get_summary()`/`apply_summary()` in that file, add `breach_seeded` to both in the same shape so save/load round-trips it. Grep `fire_seeded` in the file and mirror every occurrence.)

- [ ] **Step 2: Add `_seed_derelict_breaches()`.** In `scripts/procgen/playable_generated_ship.gd`, add after `_seed_derelict_fire()` (after line 2810):

```gdscript
## Away-branch only: force-breaches compartments of rooms carrying a breach-kind
## variant on the boarded derelict — on the DERELICT'S OWN hull model
## (current_ship.get_hull()), mirroring _seed_derelict_fire's use of
## current_ship.get_fire(). NOT the bare hull_integrity_state member: that is the
## coordinator's home/hub hull singleton (see _active_hull()). Deterministic;
## guarded by breach_seeded so revisits/restores don't re-seed (restored breaches
## come from the derelict instance's applied hull summary).
func _seed_derelict_breaches() -> void:
	if not away_from_start or current_ship == null:
		return
	if current_ship.breach_seeded:
		return
	current_ship.breach_seeded = true
	var hull = current_ship.get_hull()
	if hull == null:
		return
	for cid in _variant_hazard_compartments("breach"):
		if hull.compartments.has(str(cid)):
			hull.damage_compartment(str(cid), 1.0, true)
```

- [ ] **Step 3: Call it on the derelict build path.** In the derelict build block (line 1952, right after `_seed_derelict_fire()`), add the breach seed before `_build_fire_zones()`:

```gdscript
	# Derelict-side fire: per-ship pre-seeded environmental fire (presence-gated, capped).
	_seed_derelict_fire()
	# Derelict-side breaches: variant-driven hull breaches (deterministic per seed).
	_seed_derelict_breaches()
	_build_fire_zones()
```

- [ ] **Step 4: Parse-check.** Run:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_systems_closure_smoke.gd
```
Expected: `SHIP SYSTEMS CLOSURE PASS ...` prints (no parse regression).

- [ ] **Step 5: Commit.**

```bash
git add scripts/systems/ship_instance.gd scripts/procgen/playable_generated_ship.gd
git commit -m "feat: breach-variant rooms force live derelict hull breach — Domain 7"
```

---

## Task 5: Dressing consumer + scanner descriptor in `GeneratedShipLoader`

**Files:**
- Modify: `scripts/procgen/generated_ship_loader.gd`
- Test: covered by `procgen_variation_smoke.gd` (Task 8)

**Interfaces:**
- Consumes: `RoomVariantSelector.effects_for(variant)` (Task 1); each room's `variant`.
- Produces: `func get_room_variant_descriptors() -> Dictionary` — `{room_id: {variant, dressing}}` for rooms with a mapped variant. Used by scanner/HUD to render "Flooded Corridor"-style labels; no new meshes.

- [ ] **Step 1: Add descriptor storage + accessor.** Near the top of `scripts/procgen/generated_ship_loader.gd` (with the other member vars around line 39), add:

```gdscript
var room_variant_descriptors: Dictionary = {}  # room_id -> {"variant": String, "dressing": String}
const RoomVariantSelectorDressScript := preload("res://scripts/procgen/room_variant_selector.gd")
```

Add the accessor near the other `get_*` methods (e.g. after `get_fire_zone_markers`, line 831):

```gdscript
func get_room_variant_descriptors() -> Dictionary:
	return room_variant_descriptors.duplicate(true)
```

- [ ] **Step 2: Populate descriptors when rooms are read.** In `load_from_paths` (line 59), after `layout_doc` is assigned (line 73), add a call:

```gdscript
	_build_room_variant_descriptors()
```

Add the builder method:

```gdscript
## Records the dressing descriptor for each room whose variant carries dressing
## (or a hazard/loot effect). No new meshes are created — this is metadata the
## scanner/HUD reads to label rooms (e.g. "flooded"). Reuses existing structural
## placement props; unmapped variants are skipped.
func _build_room_variant_descriptors() -> void:
	room_variant_descriptors.clear()
	var rooms_variant: Variant = layout_doc.get("rooms", [])
	if not (rooms_variant is Array):
		return
	var selector := RoomVariantSelectorDressScript.new()
	for room_variant in (rooms_variant as Array):
		if not (room_variant is Dictionary):
			continue
		var room: Dictionary = room_variant
		var variant: String = str(room.get("variant", "standard"))
		var effects: Dictionary = selector.effects_for(variant)
		if effects.is_empty():
			continue
		var rid: String = str(room.get("id", ""))
		if rid.is_empty():
			continue
		room_variant_descriptors[rid] = {
			"variant": variant,
			"dressing": str(effects.get("dressing", "")),
		}
```

- [ ] **Step 3: Parse-check via an existing loader smoke.** Run:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_playable_ship_smoke.gd
```
Expected: its existing PASS marker prints, no new `ERROR:`/`WARNING:`.

- [ ] **Step 4: Commit.**

```bash
git add scripts/procgen/generated_ship_loader.gd
git commit -m "feat: room variant dressing descriptors for scanner/HUD — Domain 7"
```

---

## Task 6: Difficulty-gated extended templates

**Files:**
- Modify: `scripts/procgen/ship_generator.gd`
- Test: covered by `procgen_variation_smoke.gd` (Task 8)

**Interfaces:**
- Produces: extended templates active in live generation when `difficulty_id ∈ {deep_dive, hardened}`.

- [ ] **Step 1: Validate all five extended template files generate cleanly BEFORE flipping the flag.** Run this one-off check script:

```bash
cat > /tmp/tmpl_check.gd <<'EOF'
extends SceneTree
const LayoutGen := preload("res://scripts/procgen/ship_layout_generator.gd")
const Blueprint := preload("res://scripts/procgen/ship_blueprint.gd")
func _initialize() -> void:
	var ok := true
	for seed_v in [11, 22, 33, 44, 55, 66]:
		var bp = Blueprint.new(1, 1, seed_v)
		var gen = LayoutGen.new()
		var layout: Dictionary = gen.generate_with_options(bp, {}, "dead_fleet", "deep_dive", true)
		if layout.is_empty() or (layout.get("rooms", []) as Array).is_empty():
			push_error("EXTENDED TEMPLATE FAIL seed=%d produced empty layout" % seed_v)
			ok = false
	if ok:
		print("EXTENDED TEMPLATE CHECK PASS all seeds non-empty")
	quit(0 if ok else 1)
EOF
"$GODOT" --headless --path "$ROOT" --script /tmp/tmpl_check.gd
```
Expected: `EXTENDED TEMPLATE CHECK PASS all seeds non-empty`. If any seed fails, open the offending template JSON under `data/procgen/templates/` (`compact`, `dispersed`, `stacked_v2`, `derelict_a`, `derelict_b`), fix the malformed zone/role_pool, and re-run until clean. Do not proceed until this passes.

- [ ] **Step 2: Add the gate helper + use it.** In `scripts/procgen/ship_generator.gd`, replace line 40:

```gdscript
	var layout: Dictionary = layout_generator.generate_with_options(blueprint, archetype, biome_id, difficulty_id, false)
```
with:
```gdscript
	var layout: Dictionary = layout_generator.generate_with_options(blueprint, archetype, biome_id, difficulty_id, _extended_for(difficulty_id))
```

Add the helper after `generate()` (after line 45):

```gdscript
# Extended structural templates unlock on the more dangerous run tiers so
# structural variety scales with difficulty. Deterministic per seed downstream.
func _extended_for(diff_id: String) -> bool:
	return diff_id in ["deep_dive", "hardened"]
```

- [ ] **Step 3: Verify no regression on standard generation.** Run:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/ship_generator_smoke.gd
```
Expected: its existing PASS marker prints (standard difficulty still uses the legacy 3-template pool), no new `ERROR:`/`WARNING:`.

- [ ] **Step 4: Commit.**

```bash
git add scripts/procgen/ship_generator.gd
git commit -m "feat: difficulty-gate extended structural templates (deep_dive/hardened) — Domain 7"
```

---

## Task 7: Deprecate legacy `room_graph_generator`

**Files:**
- Modify: `scripts/procgen/room_graph_generator.gd`

- [ ] **Step 1: Confirm no live import.** Run:

```bash
grep -rn "room_graph_generator" scripts/ --include=*.gd | grep -v "validation/" | grep -v "room_graph_generator.gd:"
```
Expected: no output (only its own file, smokes, and dumps reference it). If a live script appears, STOP and report — the deprecation assumption is wrong.

- [ ] **Step 2: Add the deprecation banner.** At the top of `scripts/procgen/room_graph_generator.gd`, immediately after the `extends`/`class_name` lines, insert:

```gdscript
# DEPRECATED 2026-07-01 (Domain 7): orphaned from the live generation pipeline.
# The live path is TemplateSelector -> RoomAssigner -> CellLayoutEngine ->
# WallDoorResolver -> LayoutSerializer -> GeneratedShipLoader. This graph
# generator is retained for reference / unit-test use only and is excluded from
# the system-inventory completion %. Do not wire into live generation.
```

- [ ] **Step 3: Parse-check.** Run its own smoke to confirm the file still loads:

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/room_graph_generator_smoke.gd
```
Expected: its existing PASS marker still prints.

- [ ] **Step 4: Commit.**

```bash
git add scripts/procgen/room_graph_generator.gd
git commit -m "docs: deprecate orphaned room_graph_generator (test-only) — Domain 7"
```

---

## Task 8: Validation smokes + registration

**Files:**
- Create: `scripts/validation/procgen_variation_smoke.gd`
- Create: `scripts/validation/procgen_variant_hazard_smoke.gd`
- Modify: `docs/game/06_validation_plan.md`

- [ ] **Step 1: Create `procgen_variation_smoke.gd`** (pure-data generation layer):

```gdscript
extends SceneTree

# procgen_variation_smoke — Domain 7 (travel loop closure), generation layer.
# Asserts:
#   1. Two different seeds produce distinct room-variant multisets.
#   2. A variant with loot_bias changes a room's loot_table vs role baseline,
#      and the biased key is a real loot table.
#   3. Extended templates engage at deep_dive and stay off at standard.
#   4. Same seed generated twice -> identical variant + template output.
# Marker: PROCGEN VARIATION PASS variants_vary=true loot_biased=true tmpl_gated=true deterministic=true

const LayoutGen := preload("res://scripts/procgen/ship_layout_generator.gd")
const Blueprint := preload("res://scripts/procgen/ship_blueprint.gd")
const SliceBuilder := preload("res://scripts/procgen/gameplay_slice_builder.gd")

func _initialize() -> void:
	# --- Case 1: variants vary across seeds ---
	var variants_a: Array = _room_variants(101, "dead_fleet", "standard")
	var variants_b: Array = _room_variants(202, "dead_fleet", "standard")
	if variants_a.is_empty() or variants_a == variants_b:
		push_error("PROCGEN VARIATION FAIL variants did not vary across seeds: %s vs %s" % [str(variants_a), str(variants_b)])
		quit(1)
		return

	# --- Case 2: loot_bias changes a container/objective loot_table ---
	var loot_biased: bool = _has_biased_loot(303, "dead_fleet", "standard")
	if not loot_biased:
		push_error("PROCGEN VARIATION FAIL no room's loot_table reflected a variant loot_bias across sampled seeds")
		quit(1)
		return

	# --- Case 3: template gating ---
	var tmpl_std: String = _template_id(404, "dead_fleet", "standard")
	var extended_seen: bool = false
	for s in range(10):
		var tid: String = _template_id(500 + s, "dead_fleet", "deep_dive")
		if tid in ["compact", "dispersed", "stacked_v2", "derelict_a", "derelict_b"]:
			extended_seen = true
			break
	var std_is_legacy: bool = tmpl_std in ["spine", "bifurcated", "stacked"]
	if not (extended_seen and std_is_legacy):
		push_error("PROCGEN VARIATION FAIL template gating: extended_seen=%s std=%s" % [str(extended_seen), tmpl_std])
		quit(1)
		return

	# --- Case 4: determinism ---
	if _room_variants(777, "dead_fleet", "deep_dive") != _room_variants(777, "dead_fleet", "deep_dive"):
		push_error("PROCGEN VARIATION FAIL generation not deterministic for a fixed seed")
		quit(1)
		return

	print("PROCGEN VARIATION PASS variants_vary=true loot_biased=true tmpl_gated=true deterministic=true")
	quit(0)

func _gen_layout(seed_v: int, biome: String, difficulty: String) -> Dictionary:
	var bp = Blueprint.new(1, 1, seed_v)
	var gen = LayoutGen.new()
	var extended: bool = difficulty in ["deep_dive", "hardened"]
	return gen.generate_with_options(bp, {}, biome, difficulty, extended)

func _room_variants(seed_v: int, biome: String, difficulty: String) -> Array:
	var out: Array = []
	for room in (_gen_layout(seed_v, biome, difficulty).get("rooms", []) as Array):
		if room is Dictionary:
			out.append(str((room as Dictionary).get("variant", "standard")))
	return out

func _template_id(seed_v: int, biome: String, difficulty: String) -> String:
	# The layout has no dedicated template_id field; the id is embedded in
	# design_intent ("procedurally generated <template_id> ship"). Parse it out.
	var intent: String = str(_gen_layout(seed_v, biome, difficulty).get("design_intent", ""))
	var prefix: String = "procedurally generated "
	var suffix: String = " ship"
	if intent.begins_with(prefix) and intent.ends_with(suffix):
		return intent.substr(prefix.length(), intent.length() - prefix.length() - suffix.length())
	return intent

func _has_biased_loot(seed_v: int, biome: String, difficulty: String) -> bool:
	var loot_doc: Dictionary = _load_loot_tables()
	for s in range(seed_v, seed_v + 12):
		var layout: Dictionary = _gen_layout(s, biome, difficulty)
		var slice: Dictionary = SliceBuilder.new().build(layout)
		for c in (slice.get("loot_containers", []) as Array):
			if not (c is Dictionary):
				continue
			var lt: String = str((c as Dictionary).get("loot_table", ""))
			# a bias-only table (not the two generic container kinds) proves a variant bias applied
			if lt in ["salvage_cargo", "salvage_engineering", "hidden_cache", "repair_parts_common"] and loot_doc.has(lt):
				return true
	return false

func _load_loot_tables() -> Dictionary:
	var f: FileAccess = FileAccess.open("res://data/items/loot_tables.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
```

> Note: `_template_id` parses the id out of `design_intent` (there is no dedicated `template_id` key in the layout — confirmed against `layout_serializer.gd:99`). Confirm each template file's `id` field actually equals its filename stem (`spine`/`bifurcated`/`stacked` for legacy; `compact`/`dispersed`/`stacked_v2`/`derelict_a`/`derelict_b` for extended); if any `id` differs, update the membership arrays in Case 3 to match.

- [ ] **Step 2: Run it, verify PASS.**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_variation_smoke.gd
```
Expected: `PROCGEN VARIATION PASS variants_vary=true loot_biased=true tmpl_gated=true deterministic=true`.

- [ ] **Step 3: Create `procgen_variant_hazard_smoke.gd`** (main-scene, away branch). This mirrors the Domain 4 pattern (`ship_systems_closure_smoke.gd`): reach a boarded derelict, inject a known fire + breach variant into `current_ship.built_layout`, reset the seed guards, run the seeding on the away branch, and assert live hazard state.

```gdscript
extends SceneTree

# procgen_variant_hazard_smoke — Domain 7 (travel loop closure), state layer.
# Drives away_from_start = true, injects a fire variant on the engineering room
# and a breach variant on the bridge room of the boarded derelict, then asserts:
#   - _seed_derelict_fire ignites the engineering compartment (forced by variant),
#   - _seed_derelict_breaches force-breaches the bridge compartment on the
#     DERELICT's hull (current_ship.get_hull()) while the HOME hull's bridge
#     stays clean (wrong-target regression guard, Task 4 review),
#   - re-running does NOT re-seed (fire_seeded / breach_seeded guards),
#   - the ignited/breached set is deterministic (same on a second identical run).
# (bridge, not cargo: hull_compartments.json ships cargo pre-breached, so a cargo
# assertion would be vacuous.)
# Marker: PROCGEN VARIANT HAZARD PASS away_ticks=<n> fire_lit=true breach_open=true home_clean=true guarded=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene")
		return
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _validate() -> void:
	finished = true

	# Force the away (derelict) branch and ensure a current_ship exists.
	playable.away_from_start = true
	if playable.current_ship == null:
		_fail("no current_ship on away branch")
		return

	# Inject a fire variant on an engineering room and a breach variant on a
	# bridge room of the derelict's built layout (deterministic test fixture).
	var layout: Dictionary = playable.current_ship.built_layout
	if layout.is_empty() and playable.loader.has_method("get_layout_copy"):
		layout = playable.loader.get_layout_copy()
	var set_fire: bool = _set_room_variant(layout, "engineering", "burned_out")
	var set_breach: bool = _set_room_variant(layout, "bridge", "breached")
	if not set_fire or not set_breach:
		_fail("could not inject variants: fire_room=%s breach_room=%s" % [str(set_fire), str(set_breach)])
		return
	playable.current_ship.built_layout = layout

	# Reset seed guards and hull, then seed on the away branch.
	playable.current_ship.fire_seeded = false
	playable.current_ship.breach_seeded = false
	var n: int = 0
	playable._seed_derelict_fire()
	playable._seed_derelict_breaches()
	n += 1

	var fs = playable.current_ship.get_fire()
	var fire_lit: bool = fs != null and str("engineering") in fs.get_burning_compartments()
	# Breach must land on the DERELICT's hull (current_ship.get_hull()), and the
	# home hull (playable.hull_integrity_state) must be untouched by the seeding.
	# IMPORTANT: hull_compartments.json ships `cargo` ALREADY breached (health 0.3,
	# breach_open true) — asserting on cargo would be vacuous. Use `bridge`, which
	# starts health 1.0 / breach_open false in both hulls.
	var derelict_hull = playable.current_ship.get_hull()
	var breach_open: bool = derelict_hull != null \
		and derelict_hull.compartments.has("bridge") \
		and bool((derelict_hull.compartments["bridge"] as Dictionary).get("breach_open", false))
	var home_bridge_clean: bool = playable.hull_integrity_state == null \
		or not bool(((playable.hull_integrity_state.compartments.get("bridge", {}) as Dictionary)).get("breach_open", false))

	# Guard: second seed call must not change the set (guards flip true on first run).
	var burning_before: int = fs.get_burning_compartments().size() if fs != null else 0
	playable._seed_derelict_fire()
	playable._seed_derelict_breaches()
	var guarded: bool = (fs.get_burning_compartments().size() == burning_before)

	if fire_lit and breach_open and home_bridge_clean and guarded:
		print("PROCGEN VARIANT HAZARD PASS away_ticks=%d fire_lit=true breach_open=true home_clean=true guarded=true" % n)
		_cleanup_and_quit(0)
	else:
		_fail("fire_lit=%s breach_open=%s home_clean=%s guarded=%s" % [str(fire_lit), str(breach_open), str(home_bridge_clean), str(guarded)])

func _set_room_variant(layout: Dictionary, role: String, variant: String) -> bool:
	var rooms_variant: Variant = layout.get("rooms", [])
	if not (rooms_variant is Array):
		return false
	for room in (rooms_variant as Array):
		if not (room is Dictionary):
			continue
		if str((room as Dictionary).get("room_role", (room as Dictionary).get("role", ""))) == role:
			(room as Dictionary)["variant"] = variant
			return true
	return false

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node
	for child in node.get_children():
		var found = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(msg: String) -> void:
	push_error("PROCGEN VARIANT HAZARD FAIL " + msg)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null:
		main_node.queue_free()
	quit(code)
```

> Note: verify at implementation time that the boarded derelict's `built_layout` actually contains an `engineering` and a `bridge` room. If the default start derelict lacks one, either (a) drive the smoke to a derelict seed that has both (log its rooms first), or (b) inject a synthetic room dict with `room_role` + `id` into `layout.rooms` (the derelict hull's compartments come from `hull_compartments.json`, so `bridge`/`engineering` always exist on the hull side). Adjust `_set_room_variant` accordingly. Do not fake the assertion — the compartment must genuinely ignite/breach through the real seeding code.

- [ ] **Step 4: Run the hazard smoke, verify PASS.**

```bash
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/procgen_variant_hazard_smoke.gd
```
Expected: `PROCGEN VARIANT HAZARD PASS away_ticks=1 fire_lit=true breach_open=true guarded=true`, no non-allowlisted `ERROR:`/`WARNING:`.

- [ ] **Step 5: Register both smokes in `06_validation_plan.md`.** Add each new smoke to the smoke list with its expected marker, and add both `--script` invocations to the regression bundle bash block (increment the `commands=` count in the final `SYNAPTIC_SEA REGRESSION PASS commands=<N>` accordingly — bump by 2). Follow the exact format of the neighboring entries (e.g. the Domain 4/5/6 closure smokes).

- [ ] **Step 6: Run the full regression bundle.** Extract the bash block from `docs/game/06_validation_plan.md` with `GODOT`/`ROOT` set to the Windows values (see how prior commits ran it), and run it.
Expected final line: `SYNAPTIC_SEA REGRESSION PASS commands=<N+2> clean_output=true`.

- [ ] **Step 7: Commit.**

```bash
git add scripts/validation/procgen_variation_smoke.gd scripts/validation/procgen_variant_hazard_smoke.gd docs/game/06_validation_plan.md
git commit -m "test: Domain 7 procgen variation + variant-hazard away smokes; register in bundle"
```

---

## Task 9: Inventory + roadmap reconciliation (anti-drift)

**Files:**
- Modify: `docs/game/inventory/system_inventory.json` (+ regenerated `SYSTEM_INVENTORY.md`, `system_map.html`)
- Modify: `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md`

**Interfaces:**
- Consumes: all prior tasks' line-cited evidence.

- [ ] **Step 1: Flip the `travel` loop closed.** In `system_inventory.json`, find the `travel` loop object (the one with `"closes": "partial"` and the three room_variant/extended_templates/room_graph break-points) and:
  - Set `"closes": "closed"`.
  - Replace the three break-point strings with the closure evidence:
    - `"Variant effects live in room_variant_selector.VARIANT_EFFECTS (effects_for); gameplay_slice_builder applies loot_bias to room loot_table (gameplay_slice_builder.gd:_loot_table_for_room); generated_ship_loader records dressing descriptors (generated_ship_loader.gd:get_room_variant_descriptors)."`
    - `"Fire/breach variants on compartment-mapped rooms drive live derelict hazard state: _seed_derelict_fire forces ignition (playable_generated_ship.gd) and _seed_derelict_breaches force-breaches hull (playable_generated_ship.gd), away-branch, guarded by fire_seeded/breach_seeded."`
    - `"Extended structural templates enabled at deep_dive/hardened (ship_generator.gd:_extended_for); legacy room_graph_generator deprecated/test-only (excluded from completion %)."`

- [ ] **Step 2: Flip system `output.live` booleans.** In `system_inventory.json`, set `room_variant_selector.output.live = true` with a citation to the consumers (slice builder + loader + coordinator hazard seeding). Mark `room_graph_generator` deprecated (add `"deprecated": true` per that file's schema, or the nearest existing field) and exclude it from completion % per the generator's convention. Match the exact JSON shape of neighboring systems — read two sibling entries first.

- [ ] **Step 3: Rewrite the roadmap's Domain 7 "definition of closed #1".** In `docs/superpowers/specs/2026-06-28-completion-roadmap-design.md`, Domain 7 section, replace:

```
1. `data/procgen/room_variants/` exists with real variant data the selector consumes → rooms vary.
```
with:
```
1. Variant effects live in `room_variant_selector.VARIANT_EFFECTS` (code, per Domain-7 spec decision #2) and are consumed: `gameplay_slice_builder` applies `loot_bias`; `playable_generated_ship` drives live fire/breach hazard state for compartment-mapped variant rooms; `generated_ship_loader` records dressing descriptors → rooms vary.
```

- [ ] **Step 4: Regenerate the inventory docs + run `--check`.**

```bash
python tools/build_system_inventory.py
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<the --check smoke name>.gd
```
(Use the actual inventory `--check` smoke referenced in `06_validation_plan.md`.)
Expected: `SYSTEM INVENTORY CHECK PASS systems=<N> verified=<N>` and the regenerated `SYSTEM_INVENTORY.md` / `system_map.html` show `travel` green with zero remaining 🔴 for this loop.

- [ ] **Step 5: Re-run the full regression bundle** (as in Task 8 Step 6) to confirm nothing drifted.
Expected: `SYNAPTIC_SEA REGRESSION PASS commands=<N> clean_output=true`.

- [ ] **Step 6: Commit.**

```bash
git add docs/game/inventory/system_inventory.json docs/game/inventory/SYSTEM_INVENTORY.md docs/game/inventory/system_map.html docs/superpowers/specs/2026-06-28-completion-roadmap-design.md
git commit -m "docs: close travel loop in inventory + reconcile roadmap definition — Domain 7"
```

---

## Self-Review notes (for the executor)

- **Template id source (Task 8 Case 3):** `_template_id` parses `design_intent` (no `template_id` field exists). Confirm each template file's `id` matches its filename stem, or adjust the membership arrays.
- **Derelict room availability (Task 8 Step 3 note):** confirm the boarded derelict has `engineering` + `bridge` rooms, or inject synthetic rooms. Never fake the assertion. Breach asserts on `bridge` (starts clean); `cargo` ships pre-breached in `hull_compartments.json` and would be a vacuous assertion.
- **Hull-target regression guard (Task 4 review):** the breach seed targets `current_ship.get_hull()` (derelict), never the bare `hull_integrity_state` (home hull singleton). The smoke asserts both sides: derelict bridge breached AND home bridge clean.
- **`ship_instance.gd` summary round-trip (Task 4 Step 1):** if `fire_seeded` is persisted in `get_summary`/`apply_summary`, mirror `breach_seeded` there too, or a save/load mid-derelict will re-seed breaches on restore.
- **Away-branch coverage:** the hazard smoke drives `away_from_start = true` before seeding — this is the mandatory away-branch assertion. Do not let it pass on the home branch.
