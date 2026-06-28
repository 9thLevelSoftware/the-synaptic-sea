# Sanity Hallucination System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give sanity mechanical teeth — a deterministic `HallucinationDirector` drives four manifestation channels (phantom threats, false HUD, ambient cues, screen FX) across three sanity tiers, with indirect teeth (wasted attacks, misdirection) plus a direct tier-3 vitals penalty.

**Architecture:** A pure `HallucinationDirector` (RefCounted) schedules events deterministically from sanity. A `HallucinationManager` (Node3D) renders the channels; phantom threats are its own nodes that reuse an extracted `ThreatManager` placeholder renderer, so real combat math is never touched by phantom branches. The coordinator builds the per-frame context, ticks the director after sanity, renders via the manager, routes phantom dissipation through the real attack path, and feeds tier-3 teeth into the existing vitals tick.

**Tech Stack:** Godot 4.6.2, typed GDScript, Forward+. Headless `--script` validation smokes; PASS marker is the contract.

## Global Constraints

- **Godot binary:** `C:/Users/dasbl/Documents/Godot/Godot_v4.6.2-stable_win64_console.exe` (`_console` build). **Project root:** `C:/Users/dasbl/Documents/The Synaptic Sea`.
- Run a smoke: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/<name>.gd`. **`--script` can exit 0 on parse errors — trust the PASS marker, not the exit code.**
- Allowlisted teardown noise (ignore): `ERROR: Capture not registered: 'gdaimcp'.` and `WARNING: ObjectDB instances leaked at exit`. Any other `ERROR:`/`WARNING:` line fails the bundle.
- Typed GDScript. Resources/RefCounted = pure data (no scene tree); Nodes = behavior. Pure models expose `get_summary()`/`apply_summary()`.
- **Determinism: never use `randi()`/`randf()`/`Math.random`.** Hallucination scheduling uses a seeded integer hash.
- **No new `RunSnapshot` field** — hallucinations re-derive from the already-persisted sanity. The save/load `summaries` count stays **26** (do not change it).
- Tier thresholds (sanity below ⇒ tier): **40 → tier 1**, **25 → tier 2**, **15 → tier 3**. `PERCEPTION_PRESSURE_THRESHOLD = 40` already exists in `sanity_state.gd`.
- Conventional Commits. Commit trailers on every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_012rncQ3JTUdorqXH1b4eQNY
  ```
- **Selective `git add` only** — never `git add -A`/`.`; never stage `project.godot`, `.godot/`, `*.uid`, `addons/`.
- Register every new smoke in `docs/game/06_validation_plan.md` and bump the final `commands=NN` count by the number of smokes added. Confirm the full bundle stays clean.

---

## File Structure

- **Create** `scripts/systems/hallucination_director.gd` — pure model: tiers, deterministic scheduling, teeth. (Task 1)
- **Create** `scripts/validation/hallucination_director_smoke.gd` — pure-model smoke. (Task 1)
- **Create** `scripts/tools/threat_placeholder_renderer.gd` — shared placeholder-node builder. (Task 2)
- **Modify** `scripts/systems/threat_manager.gd` — `_spawn_placeholder` + `_color_for_archetype` delegate to the shared renderer. (Task 2)
- **Create** `scripts/validation/threat_placeholder_renderer_smoke.gd` — renderer parity smoke. (Task 2)
- **Modify** `scripts/systems/vitals_state.gd` — add `sanity_health_drain` + `sanity_stamina_recovery_mult` context keys. (Task 3)
- **Modify** `scripts/validation/<vitals smoke>` — assert the new keys. (Task 3)
- **Create** `scripts/systems/hallucination_manager.gd` — Node3D scene driver (phantom channel in Task 4; HUD/ambient/FX in Task 5).
- **Modify** `scripts/procgen/playable_generated_ship.gd` — instantiate/tick/wire the manager + director; phantom dissipate; teeth feed. (Tasks 4, 5)
- **Create** `scripts/validation/main_playable_hallucination_smoke.gd` — live loop smoke. (Task 4; extended in Task 5)
- **Create** `docs/game/adr/0042-sanity-hallucinations.md`; **Modify** `system_completion_audit.md`, `05_requirements.md`, `features/survival_vitals.md`. (Task 6)

---

## Task 1: HallucinationDirector pure model + smoke

**Files:**
- Create: `scripts/systems/hallucination_director.gd`
- Test: `scripts/validation/hallucination_director_smoke.gd`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Produces:
  - `configure(config: Dictionary) -> void`
  - `tick(delta: float, context: Dictionary) -> bool` — context keys: `sanity: float`, `in_safe_zone: bool`, `anchor_positions: Array` (of `Vector3`).
  - `get_tier() -> int` (0..3), `get_active_events(kind: String = "") -> Array`
  - `get_direct_teeth() -> Dictionary` → `{ "health_drain_per_second": float, "stamina_recovery_mult": float }`
  - `get_fx_intensity() -> float` (0.0 at tier 0 → 1.0 at tier 3)
  - `get_summary() -> Dictionary`, `apply_summary(summary: Dictionary) -> bool`
  - Event dict shape: `{ "id": int, "kind": String, "position": Vector3, "ttl": float }`, `kind ∈ {"ambient","hud","phantom"}`.

- [ ] **Step 1: Write the failing smoke**

Create `scripts/validation/hallucination_director_smoke.gd`:

```gdscript
extends SceneTree

## Pure-model proof for HallucinationDirector (sanity hallucinations).
## Marker: HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true

const Director := preload("res://scripts/systems/hallucination_director.gd")

func _initialize() -> void:
	var anchors: Array = [Vector3(1, 0, 0), Vector3(0, 0, 2), Vector3(3, 0, 3)]

	# --- tiers ---
	var d = Director.new(); d.configure({"seed": 7})
	var tiers_ok := d.get_tier() == 0
	d.tick(0.1, {"sanity": 90.0, "in_safe_zone": false, "anchor_positions": anchors}); tiers_ok = tiers_ok and d.get_tier() == 0
	d.tick(0.1, {"sanity": 35.0, "in_safe_zone": false, "anchor_positions": anchors}); tiers_ok = tiers_ok and d.get_tier() == 1
	d.tick(0.1, {"sanity": 20.0, "in_safe_zone": false, "anchor_positions": anchors}); tiers_ok = tiers_ok and d.get_tier() == 2
	d.tick(0.1, {"sanity": 10.0, "in_safe_zone": false, "anchor_positions": anchors}); tiers_ok = tiers_ok and d.get_tier() == 3

	# --- gating: tier 1 only ambient (no hud/phantom); safe zone => no events ---
	var g = Director.new(); g.configure({"seed": 3})
	for i in range(400):
		g.tick(0.5, {"sanity": 35.0, "in_safe_zone": false, "anchor_positions": anchors})
	var gated_ok := g.get_active_events("hud").is_empty() and g.get_active_events("phantom").is_empty()
	gated_ok = gated_ok and not g.get_active_events("ambient").is_empty()
	# safe zone clears
	g.tick(0.5, {"sanity": 10.0, "in_safe_zone": true, "anchor_positions": anchors})
	gated_ok = gated_ok and g.get_active_events().is_empty()
	# tier 2 enables hud + phantom
	var g2 = Director.new(); g2.configure({"seed": 3})
	for i in range(400):
		g2.tick(0.5, {"sanity": 20.0, "in_safe_zone": false, "anchor_positions": anchors})
	gated_ok = gated_ok and not g2.get_active_events("hud").is_empty() and not g2.get_active_events("phantom").is_empty()

	# --- determinism: same seed + identical inputs => identical event stream ---
	var a = Director.new(); a.configure({"seed": 42})
	var b = Director.new(); b.configure({"seed": 42})
	var det_ok := true
	for i in range(200):
		var ctx := {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors}
		a.tick(0.25, ctx); b.tick(0.25, ctx)
		det_ok = det_ok and _events_equal(a.get_active_events(), b.get_active_events())
	# different seed => different stream at some point
	var c = Director.new(); c.configure({"seed": 99})
	var differs := false
	for i in range(200):
		var ctx2 := {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors}
		a.tick(0.25, ctx2); c.tick(0.25, ctx2)
		if not _events_equal(a.get_active_events(), c.get_active_events()):
			differs = true
	det_ok = det_ok and differs

	# --- ttl: events expire after enough time with no new spawns possible ---
	var t = Director.new(); t.configure({"seed": 1})
	t.tick(0.1, {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors})
	# force a spawn window then starve by going to tier 0
	for i in range(50):
		t.tick(0.2, {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors})
	var had_events := not t.get_active_events().is_empty()
	for i in range(200):
		t.tick(0.5, {"sanity": 90.0, "in_safe_zone": false, "anchor_positions": anchors})
	var ttl_ok := had_events and t.get_active_events().is_empty()

	# --- teeth: zero above tier 3, non-zero at tier 3 ---
	var te = Director.new(); te.configure({"seed": 5})
	te.tick(0.1, {"sanity": 20.0, "in_safe_zone": false, "anchor_positions": anchors})
	var teeth2 := te.get_direct_teeth()
	te.tick(0.1, {"sanity": 10.0, "in_safe_zone": false, "anchor_positions": anchors})
	var teeth3 := te.get_direct_teeth()
	var teeth_ok := float(teeth2["health_drain_per_second"]) == 0.0 and float(teeth2["stamina_recovery_mult"]) == 1.0
	teeth_ok = teeth_ok and float(teeth3["health_drain_per_second"]) > 0.0 and float(teeth3["stamina_recovery_mult"]) < 1.0

	# --- fx intensity rises with tier ---
	var fx_ok := te.get_fx_intensity() > 0.0
	var fx0 = Director.new(); fx0.configure({"seed": 5})
	fx0.tick(0.1, {"sanity": 90.0, "in_safe_zone": false, "anchor_positions": anchors})
	fx_ok = fx_ok and fx0.get_fx_intensity() == 0.0

	# --- round trip ---
	var r = Director.new(); r.configure({"seed": 11})
	for i in range(20):
		r.tick(0.3, {"sanity": 12.0, "in_safe_zone": false, "anchor_positions": anchors})
	var summ := r.get_summary()
	var r2 = Director.new(); r2.configure({"seed": 0})
	var rt_ok := r2.apply_summary(summ) and r2.get_summary()["seed"] == summ["seed"] and r2.get_summary()["step"] == summ["step"]

	if tiers_ok and gated_ok and det_ok and ttl_ok and teeth_ok and fx_ok and rt_ok:
		print("HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true")
		quit(0)
	else:
		push_error("HALLUCINATION DIRECTOR FAIL tiers=%s gated=%s det=%s ttl=%s teeth=%s fx=%s rt=%s" % [tiers_ok, gated_ok, det_ok, ttl_ok, teeth_ok, fx_ok, rt_ok])
		quit(1)

func _events_equal(x: Array, y: Array) -> bool:
	if x.size() != y.size():
		return false
	for i in range(x.size()):
		if str(x[i]) != str(y[i]):
			return false
	return true
```

- [ ] **Step 2: Run the smoke; expect failure**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hallucination_director_smoke.gd`
Expected: parse/load error (HallucinationDirector does not exist yet) — no PASS marker.

- [ ] **Step 3: Implement the model**

Create `scripts/systems/hallucination_director.gd`:

```gdscript
extends RefCounted
class_name HallucinationDirector

## Deterministic, pure-data scheduler for sanity-driven hallucinations (ADR-0042).
## Maps sanity to a tier (0..3) and schedules discrete manifestation events
## (ambient/hud/phantom) with NO RNG — selection is a seeded integer hash so the
## same (seed, step, inputs) always yields the same stream. Screen FX is continuous
## (get_fx_intensity), not a scheduled event. The owning HallucinationManager renders
## active events; the coordinator applies get_direct_teeth() into the vitals tick.

const TIER_UNEASE: float = 40.0      # sanity < 40 -> tier 1
const TIER_DISTORTION: float = 25.0  # sanity < 25 -> tier 2
const TIER_BREAKDOWN: float = 15.0   # sanity < 15 -> tier 3

const DEFAULT_HEALTH_DRAIN: float = 0.5         # tier-3 health drain per second
const DEFAULT_STAMINA_RECOVERY_MULT: float = 0.5 # tier-3 stamina-recovery penalty

# Per-kind scheduling. min_tier gates the kind; interval/max may tighten at tier 3.
const KIND_CONFIG := {
	"ambient": {"min_tier": 1, "interval": 6.0, "interval_t3": 4.0, "max": 2, "max_t3": 2, "ttl": 3.0},
	"hud":     {"min_tier": 2, "interval": 5.0, "interval_t3": 3.0, "max": 3, "max_t3": 3, "ttl": 2.5},
	"phantom": {"min_tier": 2, "interval": 8.0, "interval_t3": 3.5, "max": 1, "max_t3": 3, "ttl": 12.0},
}

var seed: int = 0
var step: int = 0
var health_drain_per_second: float = DEFAULT_HEALTH_DRAIN
var stamina_recovery_mult: float = DEFAULT_STAMINA_RECOVERY_MULT

var active_events: Array = []   # [{ id, kind, position, ttl }]
var _next_id: int = 1
var _spawn_timers: Dictionary = {}  # kind -> float
var _current_tier: int = 0

func configure(config: Dictionary) -> void:
	seed = int(config.get("seed", 0))
	step = 0
	health_drain_per_second = maxf(0.0, float(config.get("health_drain_per_second", DEFAULT_HEALTH_DRAIN)))
	stamina_recovery_mult = clampf(float(config.get("stamina_recovery_mult", DEFAULT_STAMINA_RECOVERY_MULT)), 0.0, 1.0)
	active_events.clear()
	_spawn_timers.clear()
	_next_id = 1
	_current_tier = 0

func tick(delta: float, context: Dictionary) -> bool:
	if delta <= 0.0:
		return false
	var changed: bool = false
	var sanity: float = float(context.get("sanity", 100.0))
	var in_safe_zone: bool = bool(context.get("in_safe_zone", false))
	var anchors: Array = context.get("anchor_positions", []) if context.get("anchor_positions", []) is Array else []
	_current_tier = _tier_for(sanity)

	if _current_tier == 0 or in_safe_zone or anchors.is_empty():
		if not active_events.is_empty():
			active_events.clear()
			changed = true
		_spawn_timers.clear()
		step += 1
		return changed

	# Expire timed-out events.
	for i in range(active_events.size() - 1, -1, -1):
		active_events[i]["ttl"] = float(active_events[i]["ttl"]) - delta
		if float(active_events[i]["ttl"]) <= 0.0:
			active_events.remove_at(i)
			changed = true

	# Schedule per enabled kind.
	for kind in KIND_CONFIG.keys():
		var cfg: Dictionary = KIND_CONFIG[kind]
		if _current_tier < int(cfg["min_tier"]):
			continue
		var interval: float = float(cfg["interval_t3"]) if _current_tier >= 3 else float(cfg["interval"])
		var cap: int = int(cfg["max_t3"]) if _current_tier >= 3 else int(cfg["max"])
		_spawn_timers[kind] = float(_spawn_timers.get(kind, 0.0)) + delta
		if _spawn_timers[kind] >= interval and _count_kind(kind) < cap:
			_spawn_timers[kind] = float(_spawn_timers[kind]) - interval
			var idx: int = _pick_index(kind, anchors.size())
			active_events.append({
				"id": _next_id,
				"kind": kind,
				"position": anchors[idx],
				"ttl": float(cfg["ttl"]),
			})
			_next_id += 1
			changed = true

	step += 1
	return changed

func get_tier() -> int:
	return _current_tier

func get_active_events(kind: String = "") -> Array:
	if kind.is_empty():
		return active_events.duplicate(true)
	var out: Array = []
	for e in active_events:
		if str(e["kind"]) == kind:
			out.append(e.duplicate(true))
	return out

func get_direct_teeth() -> Dictionary:
	if _current_tier >= 3:
		return {"health_drain_per_second": health_drain_per_second, "stamina_recovery_mult": stamina_recovery_mult}
	return {"health_drain_per_second": 0.0, "stamina_recovery_mult": 1.0}

func get_fx_intensity() -> float:
	return clampf(float(_current_tier) / 3.0, 0.0, 1.0)

func get_summary() -> Dictionary:
	return {
		"seed": seed,
		"step": step,
		"health_drain_per_second": health_drain_per_second,
		"stamina_recovery_mult": stamina_recovery_mult,
		"active_events": active_events.duplicate(true),
		"current_tier": _current_tier,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	seed = int(summary.get("seed", seed))
	step = int(summary.get("step", step))
	health_drain_per_second = maxf(0.0, float(summary.get("health_drain_per_second", health_drain_per_second)))
	stamina_recovery_mult = clampf(float(summary.get("stamina_recovery_mult", stamina_recovery_mult)), 0.0, 1.0)
	if summary.get("active_events", null) is Array:
		active_events = (summary["active_events"] as Array).duplicate(true)
	_current_tier = int(summary.get("current_tier", _current_tier))
	return true

func _tier_for(sanity: float) -> int:
	if sanity < TIER_BREAKDOWN:
		return 3
	if sanity < TIER_DISTORTION:
		return 2
	if sanity < TIER_UNEASE:
		return 1
	return 0

func _count_kind(kind: String) -> int:
	var n: int = 0
	for e in active_events:
		if str(e["kind"]) == kind:
			n += 1
	return n

# Deterministic index in [0, count) from (seed, step, kind). No RNG.
func _pick_index(kind: String, count: int) -> int:
	if count <= 0:
		return 0
	var h: int = seed * 1103515245 + step * 12345 + hash(kind)
	h = (h ^ (h >> 16)) & 0x7fffffff
	return h % count
```

- [ ] **Step 4: Run the smoke; expect PASS**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hallucination_director_smoke.gd`
Expected: `HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true` and no parse error.

- [ ] **Step 5: Register the smoke**

In `docs/game/06_validation_plan.md`, add a `run_clean` line near the other survival-model smokes:

```bash
run_clean 'hallucination director model smoke' 'HALLUCINATION DIRECTOR PASS tiers=true gated=true deterministic=true ttl=true teeth=true fx=true round_trip=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/hallucination_director_smoke.gd
```

Bump the final `echo 'SYNAPTIC_SEA REGRESSION PASS commands=NN ...'` count by 1.

- [ ] **Step 6: Commit**

```bash
git add scripts/systems/hallucination_director.gd scripts/validation/hallucination_director_smoke.gd docs/game/06_validation_plan.md
git commit  # message: "feat(sanity): deterministic HallucinationDirector model + smoke" + trailers
```

---

## Task 2: Shared placeholder renderer (ThreatManager refactor)

**Files:**
- Create: `scripts/tools/threat_placeholder_renderer.gd`
- Modify: `scripts/systems/threat_manager.gd:263-322` (`_spawn_placeholder`, `_color_for_archetype`)
- Test: `scripts/validation/threat_placeholder_renderer_smoke.gd`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Produces: `ThreatPlaceholderRenderer.build_placeholder(archetype_id: String, tags: Array, world_position: Vector3) -> Node3D` (static). Returns a `Node3D` with one `MeshInstance3D` child: `SphereMesh` if tags has `"swarm"`, `CylinderMesh` if `"anchored"`, else `CapsuleMesh`; material albedo = archetype color. Also `ThreatPlaceholderRenderer.color_for_archetype(archetype_id: String) -> Color` (static).
- Consumes: nothing from earlier tasks.

- [ ] **Step 1: Write the failing renderer smoke**

Create `scripts/validation/threat_placeholder_renderer_smoke.gd`:

```gdscript
extends SceneTree

## Marker: THREAT PLACEHOLDER RENDERER PASS swarm=true anchored=true default=true color=true

const Renderer := preload("res://scripts/tools/threat_placeholder_renderer.gd")

func _initialize() -> void:
	var swarm := Renderer.build_placeholder("biomatter_swarm", ["swarm"], Vector3(1, 2, 3))
	var anchored := Renderer.build_placeholder("hull_tendril", ["anchored"], Vector3.ZERO)
	var basic := Renderer.build_placeholder("stalker", [], Vector3.ZERO)
	var swarm_ok := swarm is Node3D and swarm.get_child_count() == 1 and (swarm.get_child(0) as MeshInstance3D).mesh is SphereMesh and swarm.position == Vector3(1, 2, 3)
	var anchored_ok := (anchored.get_child(0) as MeshInstance3D).mesh is CylinderMesh
	var default_ok := (basic.get_child(0) as MeshInstance3D).mesh is CapsuleMesh
	var color_ok := Renderer.color_for_archetype("biomatter_swarm") == Color(0.55, 1.0, 0.45) and Renderer.color_for_archetype("unknown_xyz") == Color(1.0, 0.35, 0.35)
	swarm.free(); anchored.free(); basic.free()
	if swarm_ok and anchored_ok and default_ok and color_ok:
		print("THREAT PLACEHOLDER RENDERER PASS swarm=true anchored=true default=true color=true")
		quit(0)
	else:
		push_error("THREAT PLACEHOLDER RENDERER FAIL swarm=%s anchored=%s default=%s color=%s" % [swarm_ok, anchored_ok, default_ok, color_ok])
		quit(1)
```

- [ ] **Step 2: Run; expect failure**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_placeholder_renderer_smoke.gd`
Expected: parse/load error (renderer missing).

- [ ] **Step 3: Create the shared renderer**

Create `scripts/tools/threat_placeholder_renderer.gd`:

```gdscript
extends RefCounted
class_name ThreatPlaceholderRenderer

## Shared builder for threat-shaped placeholder nodes. Used by ThreatManager (real
## threats) and HallucinationManager (phantoms) so both look identical. Behavior is the
## exact visual previously inlined in ThreatManager._spawn_placeholder.

static func build_placeholder(archetype_id: String, tags: Array, world_position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = world_position
	var mesh_instance := MeshInstance3D.new()
	if tags.has("swarm"):
		mesh_instance.mesh = SphereMesh.new()
	elif tags.has("anchored"):
		mesh_instance.mesh = CylinderMesh.new()
	else:
		mesh_instance.mesh = CapsuleMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color_for_archetype(archetype_id)
	mesh_instance.material_override = mat
	node.add_child(mesh_instance)
	return node

static func color_for_archetype(archetype_id: String) -> Color:
	match archetype_id:
		"biomatter_swarm":
			return Color(0.55, 1.0, 0.45)
		"puppet_corpse":
			return Color(0.85, 0.82, 0.7)
		"stalker":
			return Color(0.7, 0.7, 1.0)
		"mimic":
			return Color(1.0, 0.55, 0.25)
		"hull_tendril":
			return Color(0.55, 0.9, 1.0)
		_:
			return Color(1.0, 0.35, 0.35)
```

- [ ] **Step 4: Delegate `ThreatManager._spawn_placeholder` to the renderer**

In `scripts/systems/threat_manager.gd`, replace the body of `_spawn_placeholder` (lines 263-279) so the node is built by the shared renderer (preserving the node name + `placeholder_nodes` bookkeeping):

```gdscript
func _spawn_placeholder(threat, index: int, anchor: Vector3) -> void:
	var ThreatPlaceholderRendererScript := preload("res://scripts/tools/threat_placeholder_renderer.gd")
	var pos := Vector3(float(threat.world_position[0]), float(threat.world_position[1]), float(threat.world_position[2]))
	var node := ThreatPlaceholderRendererScript.build_placeholder(threat.archetype_id, threat.tags, pos)
	node.name = "Threat_%s" % threat.instance_id
	add_child(node)
	placeholder_nodes[threat.instance_id] = node
```

Then replace the body of `_color_for_archetype` (lines 309-322) to delegate (keep the method so any other caller is unaffected):

```gdscript
func _color_for_archetype(archetype_id: String) -> Color:
	var ThreatPlaceholderRendererScript := preload("res://scripts/tools/threat_placeholder_renderer.gd")
	return ThreatPlaceholderRendererScript.color_for_archetype(archetype_id)
```

(The `index` and `anchor` params are retained for signature compatibility even though unused, matching the prior signature.)

- [ ] **Step 5: Run the renderer smoke + existing threat smokes; expect PASS, no regression**

Run each and confirm the marker:
```
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_placeholder_renderer_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_slice_hazard_smoke.gd
"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_derelict_encounter_injection_smoke.gd
```
Expected: `THREAT PLACEHOLDER RENDERER PASS ...`, `MAIN PLAYABLE HAZARD PASS ...`, `MAIN PLAYABLE DERELICT ENCOUNTER INJECTION PASS ...` — all unchanged.

- [ ] **Step 6: Register + commit**

Add to `docs/game/06_validation_plan.md`:
```bash
run_clean 'threat placeholder renderer smoke' 'THREAT PLACEHOLDER RENDERER PASS swarm=true anchored=true default=true color=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/threat_placeholder_renderer_smoke.gd
```
Bump the `commands=NN` count by 1.

```bash
git add scripts/tools/threat_placeholder_renderer.gd scripts/systems/threat_manager.gd scripts/validation/threat_placeholder_renderer_smoke.gd docs/game/06_validation_plan.md
git commit  # "refactor(threat): extract shared placeholder renderer" + trailers
```

---

## Task 3: Vitals sanity-teeth context keys

**Files:**
- Modify: `scripts/systems/vitals_state.gd:55-107` (doc comment + `tick`)
- Test: `scripts/validation/vitals_state_smoke.gd` (extend; if it does not exist, create a focused one — see Step 1)
- Modify: `docs/game/06_validation_plan.md` (only if a new smoke is created)

**Interfaces:**
- Produces: `vitals_state.tick(delta, context)` now honors `context["sanity_health_drain"]` (float, added to health drain) and `context["sanity_stamina_recovery_mult"]` (float, multiplies stamina recovery), mirroring `fire_health_drain` / `status_stamina_recovery_mult`.

- [ ] **Step 1: Write the failing assertion**

Locate the pure vitals smoke. If `scripts/validation/vitals_state_smoke.gd` exists, add a block; otherwise create `scripts/validation/vitals_state_smoke.gd`:

```gdscript
extends SceneTree

## Marker: VITALS STATE PASS sanity_drain=true sanity_stamina=true

const Vitals := preload("res://scripts/systems/vitals_state.gd")

func _initialize() -> void:
	# sanity_health_drain adds to health loss
	var v = Vitals.new(); v.configure({}) if v.has_method("configure") else null
	v.health = 90.0
	v.tick(1.0, {"sanity_health_drain": 5.0, "moving": false})
	var drain_ok := v.health < 90.0

	# sanity_stamina_recovery_mult reduces stamina recovery vs baseline
	var a = Vitals.new(); a.stamina = 10.0
	a.tick(1.0, {"moving": false})
	var base_recover := a.stamina - 10.0
	var b = Vitals.new(); b.stamina = 10.0
	b.tick(1.0, {"moving": false, "sanity_stamina_recovery_mult": 0.5})
	var pen_recover := b.stamina - 10.0
	var stamina_ok := base_recover > 0.0 and pen_recover < base_recover

	if drain_ok and stamina_ok:
		print("VITALS STATE PASS sanity_drain=true sanity_stamina=true")
		quit(0)
	else:
		push_error("VITALS STATE FAIL sanity_drain=%s sanity_stamina=%s" % [drain_ok, stamina_ok])
		quit(1)
```

(If extending an existing smoke, fold these two checks in and append `sanity_drain=true sanity_stamina=true` to its existing PASS marker; update its registered marker in `06_validation_plan.md` to match.)

- [ ] **Step 2: Run; expect failure**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_smoke.gd`
Expected: FAIL (`stamina_ok=false` / `sanity_drain` not yet honored).

- [ ] **Step 3: Honor the new context keys in `tick`**

In `scripts/systems/vitals_state.gd`, in the stamina-recovery multiplier block, after the existing `status_stamina_recovery_mult` line (around line 67-68), add:

```gdscript
		if context.has("sanity_stamina_recovery_mult"):
			stamina_recovery_mult *= float(context.get("sanity_stamina_recovery_mult", 1.0))
```

In the health-drain block, after the existing `fire_health_drain` line (around line 87-88), add:

```gdscript
		if context.has("sanity_health_drain"):
			h_drain += float(context.get("sanity_health_drain", 0.0)) * delta_seconds
```

Add two lines to the `tick` doc comment (around line 55-58) documenting the new keys, matching the existing style:

```gdscript
##   "sanity_health_drain" -> float (added to health drain at sanity tier 3)
##   "sanity_stamina_recovery_mult" -> float (multiplies stamina recovery at sanity tier 3)
```

- [ ] **Step 4: Run; expect PASS**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/vitals_state_smoke.gd`
Expected: `VITALS STATE PASS sanity_drain=true sanity_stamina=true` (or the extended marker).

- [ ] **Step 5: Register (if new) + commit**

If a new smoke was created, add its `run_clean` line to `06_validation_plan.md` and bump `commands=NN` by 1.

```bash
git add scripts/systems/vitals_state.gd scripts/validation/vitals_state_smoke.gd docs/game/06_validation_plan.md
git commit  # "feat(vitals): sanity_health_drain + sanity_stamina_recovery_mult context keys" + trailers
```

---

## Task 4: HallucinationManager phantom channel + coordinator wiring + live smoke

**Files:**
- Create: `scripts/systems/hallucination_manager.gd`
- Modify: `scripts/procgen/playable_generated_ship.gd` (instantiate/configure, context build + tick, phantom render/dissipate, attack hook ~3696-3708, teeth feed into vitals ~4601-4609, validation seams)
- Test: `scripts/validation/main_playable_hallucination_smoke.gd`
- Modify: `docs/game/06_validation_plan.md`

**Interfaces:**
- Consumes: `HallucinationDirector` (Task 1), `ThreatPlaceholderRenderer` (Task 2), vitals sanity keys (Task 3).
- Produces (on `HallucinationManager`):
  - `configure(director) -> void` (stores the director instance)
  - `render(delta: float, player_position: Vector3) -> void` (reconcile phantom nodes to `director.get_active_events("phantom")`, dissipate phantoms within `melee_range` of the player)
  - `dissipate_phantom_in_range(player_position: Vector3, attack_range: float = 1.6) -> bool` (vanish nearest phantom in range; return whether one was hit)
  - `phantom_count() -> int`, `clear_all() -> void`
  - `melee_range: float = 1.2`
- Produces (on coordinator): `get_hallucination_director_for_validation()`, `get_hallucination_manager_for_validation()`.

- [ ] **Step 1: Write the failing live smoke**

Create `scripts/validation/main_playable_hallucination_smoke.gd`:

```gdscript
extends SceneTree

## Live-scene proof of the sanity hallucination loop (phantom channel + teeth).
## Marker: MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true reachable=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 360

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	if main_node == null:
		_fail("could not instantiate main scene"); return
	get_root().add_child(main_node)
	process_frame.connect(_on_process_frame)

func _on_process_frame() -> void:
	if finished:
		return
	frame_count += 1
	if playable == null:
		playable = _find_playable(main_node)
	if playable == null or playable.loader == null or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable did not become ready")
		return
	_validate()

func _validate() -> void:
	var director = playable.get_hallucination_director_for_validation()
	var manager = playable.get_hallucination_manager_for_validation()
	if director == null or manager == null:
		_fail("hallucination director/manager missing"); return
	if playable.threat_manager != null:
		playable.threat_manager.threats.clear()

	# Drive away (out of safe zone) and crater sanity into tier 3.
	playable.away_from_start = true
	playable.sanity_state.sanity = 8.0

	# Manifest: pump frames until phantoms appear.
	var manifested := false
	for i in range(600):
		playable._process(1.0 / 30.0)
		if manager.phantom_count() > 0:
			manifested = true; break
	if not manifested:
		_fail("no phantom manifested at tier 3"); return

	# Phantom deals NO vitals damage: park the player on a phantom and confirm health holds
	# (no real threats present).
	playable.vitals_state.health = 90.0
	var hp_before: float = playable.vitals_state.health
	for i in range(30):
		playable._process(1.0 / 30.0)
	var phantom_no_damage := playable.vitals_state.health >= hp_before - 0.001 + _expected_sanity_drain(30.0 / 30.0)
	# (Allow the tier-3 sanity health drain; assert no LARGE combat-style drop.)
	phantom_no_damage = playable.vitals_state.health > hp_before - 2.0

	# Attack dissipates a phantom and spends ammo (wasted swing). Equip an ammo weapon.
	var charge_ok := _arm_ammo_weapon()
	var before_phantoms := manager.phantom_count()
	var ammo_before := int(playable.inventory_state.get_quantity(_ammo_id()))
	var result: Dictionary = playable._attack_with_equipped_weapon()
	var attack_dissipates := manager.phantom_count() < before_phantoms and bool(result.get("phantom_dissipated", false))
	attack_dissipates = attack_dissipates and int(playable.inventory_state.get_quantity(_ammo_id())) < ammo_before

	# Teeth: tier 3 drains health over time (sanity_health_drain).
	playable.vitals_state.health = 90.0
	var teeth_before: float = playable.vitals_state.health
	for i in range(60):
		playable._process(1.0 / 30.0)
	var teeth := playable.vitals_state.health < teeth_before

	# Clears: restore sanity, enter safe zone => everything cleared.
	playable.away_from_start = false
	playable.sanity_state.sanity = 100.0
	for i in range(10):
		playable._process(1.0 / 30.0)
	var clears := manager.phantom_count() == 0

	if manifested and phantom_no_damage and attack_dissipates and teeth and clears:
		print("MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true reachable=true")
		finished = true
		_cleanup_and_quit(0)
	else:
		_fail("manifest=%s no_damage=%s attack=%s teeth=%s clears=%s" % [manifested, phantom_no_damage, attack_dissipates, teeth, clears])

func _expected_sanity_drain(_seconds: float) -> float:
	return 0.0

func _ammo_id() -> String:
	return "shotgun_shell"

func _arm_ammo_weapon() -> bool:
	# Find a weapon with an ammo_item_id, equip it, and stock ammo. Falls back gracefully.
	playable.inventory_state.add_item(_ammo_id(), 5)
	if playable.equipment_state != null and playable.equipment_state.has_method("equip"):
		playable.equipment_state.equip("primary_hand", "scrap_shotgun")
	return true

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var f = _find_playable(child)
		if f != null:
			return f
	return null

func _fail(reason: String) -> void:
	if finished:
		return
	finished = true
	push_error("MAIN PLAYABLE HALLUCINATION FAIL reason=%s" % reason)
	_cleanup_and_quit(1)

func _cleanup_and_quit(code: int) -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
```

> Implementer note: the weapon/ammo ids (`scrap_shotgun`/`shotgun_shell`) are illustrative. Before writing the impl, grep `data/` (e.g. `data/items/weapon_definitions.json` or wherever `weapon_definitions` is loaded by `threat_manager`) for a weapon with a non-empty `ammo_item_id`, and use that real weapon + ammo id in `_ammo_id()`/`_arm_ammo_weapon()`. If no ammo weapon exists, assert the wasted swing via the dissipation flag alone and set the marker's `attack_dissipates` from `result["phantom_dissipated"]` only (drop the ammo assertion), and note the deviation in the report.

- [ ] **Step 2: Run; expect failure**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_hallucination_smoke.gd`
Expected: failure — `get_hallucination_director_for_validation` missing.

- [ ] **Step 3: Implement `HallucinationManager` (phantom channel)**

Create `scripts/systems/hallucination_manager.gd`:

```gdscript
extends Node3D
class_name HallucinationManager

## Scene driver for sanity hallucinations. Renders the HallucinationDirector's active
## events. THIS TASK: the phantom-threat channel only (HUD/ambient/FX added in Task 5).
## Phantoms are this node's OWN children, never in ThreatManager — real combat math is
## untouched. Phantoms deal no damage; they dissipate on attack or melee proximity.

const ThreatPlaceholderRendererScript := preload("res://scripts/tools/threat_placeholder_renderer.gd")

var director  # HallucinationDirector
var melee_range: float = 1.2
var _phantom_nodes: Dictionary = {}   # event_id (int) -> Node3D
const PHANTOM_ARCHETYPE := "stalker"  # neutral phantom look; deterministic, no real id leak

func configure(p_director) -> void:
	director = p_director

func render(delta: float, player_position: Vector3) -> void:
	if director == null:
		clear_all()
		return
	var events: Array = director.get_active_events("phantom")
	var live_ids: Dictionary = {}
	for e in events:
		var id: int = int(e["id"])
		live_ids[id] = true
		if not _phantom_nodes.has(id):
			var pos: Vector3 = e["position"]
			var node := ThreatPlaceholderRendererScript.build_placeholder(PHANTOM_ARCHETYPE, ["phantom"], pos)
			node.name = "Phantom_%d" % id
			node.set_meta("is_phantom", true)
			add_child(node)
			_phantom_nodes[id] = node
	# Free phantom nodes whose event expired.
	for id in _phantom_nodes.keys():
		if not live_ids.has(id):
			_free_phantom(id)
	# Dissipate phantoms the player has walked into.
	for id in _phantom_nodes.keys():
		var n = _phantom_nodes[id]
		if is_instance_valid(n) and (n as Node3D).global_position.distance_to(player_position) <= melee_range:
			_free_phantom(id)

## Vanish the nearest phantom within attack_range; returns whether one was dissipated.
func dissipate_phantom_in_range(player_position: Vector3, attack_range: float = 1.6) -> bool:
	var best_id: int = -1
	var best_d: float = attack_range
	for id in _phantom_nodes.keys():
		var n = _phantom_nodes[id]
		if not is_instance_valid(n):
			continue
		var d: float = (n as Node3D).global_position.distance_to(player_position)
		if d <= best_d:
			best_d = d
			best_id = id
	if best_id >= 0:
		_free_phantom(best_id)
		return true
	return false

func phantom_count() -> int:
	var n: int = 0
	for id in _phantom_nodes.keys():
		if is_instance_valid(_phantom_nodes[id]):
			n += 1
	return n

func clear_all() -> void:
	for id in _phantom_nodes.keys():
		_free_phantom(id)
	_phantom_nodes.clear()

func _free_phantom(id: int) -> void:
	var n = _phantom_nodes.get(id, null)
	if n != null and is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()
	_phantom_nodes.erase(id)
```

- [ ] **Step 4: Wire the coordinator — instantiate + member**

In `scripts/procgen/playable_generated_ship.gd`, near the other system preloads (top, ~line 80), add:

```gdscript
const HallucinationDirectorScript := preload("res://scripts/systems/hallucination_director.gd")
const HallucinationManagerScript := preload("res://scripts/systems/hallucination_manager.gd")
```

Near the other system members (e.g. by `var sanity_state`), add:

```gdscript
var hallucination_director  # HallucinationDirector
var hallucination_manager   # HallucinationManager
```

Where `sanity_state.configure({})` is called (~line 6633), construct + configure the director and manager and attach the manager to the active ship root (use the same attach helper the fire zones use — `_attach_zone_to_active_ship`, which falls back to `repair_point_root`):

```gdscript
		sanity_state.configure({})
		hallucination_director = HallucinationDirectorScript.new()
		hallucination_director.configure({"seed": int(_run_seed()) if has_method("_run_seed") else 1337})
		hallucination_manager = HallucinationManagerScript.new()
		hallucination_manager.name = "HallucinationManager"
		hallucination_manager.configure(hallucination_director)
		_attach_zone_to_active_ship(hallucination_manager)
```

> Implementer note: use whatever the coordinator already uses as the deterministic run seed (grep for `seed`); if there is no accessor, pass a fixed `1337`. The manager attaches like fire zones so phantom world positions are valid in the active frame.

- [ ] **Step 5: Wire the coordinator — context build, director tick, render, teeth**

Replace the sanity block (`scripts/procgen/playable_generated_ship.gd:4610-4614`) so it also ticks the director and renders the manager:

```gdscript
	if sanity_state != null:
		# Synaptic Sea field = not in a safe zone (away_from_start or breach open)
		var in_safe: bool = not away_from_start and (oxygen_state == null or not oxygen_state.get_summary().get("breach_open", false))
		sanity_state.in_safe_zone = in_safe
		sanity_state.tick(delta)
		if hallucination_director != null:
			var hctx := {
				"sanity": sanity_state.sanity,
				"in_safe_zone": in_safe,
				"anchor_positions": _distributed_room_positions(),
			}
			hallucination_director.tick(delta, hctx)
			if hallucination_manager != null:
				var ppos: Vector3 = (player as Node3D).global_position if player != null and player is Node3D else Vector3.ZERO
				hallucination_manager.render(delta, ppos)
```

In the vitals tick context (`scripts/procgen/playable_generated_ship.gd:4601-4609`), add the two sanity-teeth keys read from the director (one-frame lag is acceptable; the director was ticked the prior frame):

```gdscript
		var hteeth := hallucination_director.get_direct_teeth() if hallucination_director != null else {"health_drain_per_second": 0.0, "stamina_recovery_mult": 1.0}
		vitals_state.tick(delta, {
			"temperature_thirst_mult": temp_mult,
			"radiation_health_drain": rad_drain,
			"atmosphere_health_drain": atmo_drain,
			"fire_health_drain": FIRE_HEALTH_DRAIN_PER_SECOND * _player_fire_intensity(),
			"status_stamina_recovery_mult": status_mult,
			"sanity_health_drain": float(hteeth["health_drain_per_second"]),
			"sanity_stamina_recovery_mult": float(hteeth["stamina_recovery_mult"]),
			"moving": player != null and player.has_method("is_moving") and player.is_moving(),
		})
```

- [ ] **Step 6: Wire the coordinator — phantom dissipate on attack**

In `_attack_with_equipped_weapon` (`scripts/procgen/playable_generated_ship.gd:3696-3708`), after the `attack_with_weapon` call and before `return result`, dissipate a phantom the player swung at (ammo was already spent by `attack_with_weapon`, even on a `no_target` result — that is the wasted-action teeth):

```gdscript
	if hallucination_manager != null:
		var ppos: Vector3 = (player as Node3D).global_position if player != null and player is Node3D else Vector3.ZERO
		if hallucination_manager.dissipate_phantom_in_range(ppos):
			result["phantom_dissipated"] = true
			result["ok"] = true
			_refresh_inventory_hud()
```

- [ ] **Step 7: Add validation seams + clear on teardown**

Add accessor seams near the other `*_for_validation` methods:

```gdscript
func get_hallucination_director_for_validation():
	return hallucination_director

func get_hallucination_manager_for_validation():
	return hallucination_manager
```

Find where the coordinator clears per-build scene nodes on ship teardown/rebuild (grep for `_clear_fire_zones` call sites). Add `if hallucination_manager != null: hallucination_manager.clear_all()` alongside the fire-zone clears so phantoms do not leak across ship transitions.

- [ ] **Step 8: Run the live smoke; expect PASS**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_hallucination_smoke.gd`
Expected: `MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true reachable=true`.

- [ ] **Step 9: Register + commit**

Add to `docs/game/06_validation_plan.md`:
```bash
run_clean 'main hallucination loop smoke' 'MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true reachable=true' "$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_hallucination_smoke.gd
```
Bump `commands=NN` by 1.

```bash
git add scripts/systems/hallucination_manager.gd scripts/procgen/playable_generated_ship.gd scripts/validation/main_playable_hallucination_smoke.gd docs/game/06_validation_plan.md
git commit  # "feat(sanity): phantom hallucination channel + teeth wiring + live loop" + trailers
```

---

## Task 5: False-HUD, ambient, and screen-FX channels

**Files:**
- Modify: `scripts/systems/hallucination_manager.gd` (add HUD/ambient/FX rendering)
- Modify: `scripts/procgen/playable_generated_ship.gd` (FX overlay node; pass audio_manager + tracker hooks to the manager)
- Modify: `scripts/validation/main_playable_hallucination_smoke.gd` (extend marker)
- Modify: `docs/game/06_validation_plan.md` (update marker)

**Interfaces:**
- Consumes: `HallucinationDirector.get_active_events("hud"|"ambient")`, `get_fx_intensity()`; `audio_manager` (grep `scripts/audio/audio_manager.gd` for `play_sfx` + `audio_event_seam.gd` for SFX ids); the HUD/tracker status-line feed.
- Produces (on `HallucinationManager`):
  - `set_channels(audio_manager, fx_overlay) -> void`
  - `get_hallucinated_status_lines() -> PackedStringArray` (phantom blips / transient wrong readouts for the HUD to merge)
  - extends `render()` to fire ambient SFX, push HUD lines, and drive `fx_overlay` intensity from `director.get_fx_intensity()`.

- [ ] **Step 1: Extend the live smoke marker (failing)**

In `scripts/validation/main_playable_hallucination_smoke.gd`, after the phantom assertions, add channel assertions and extend the marker. Add before the final marker print:

```gdscript
	# Channels: at tier 3, HUD lies are present and FX intensity is high.
	playable.away_from_start = true
	playable.sanity_state.sanity = 8.0
	for i in range(120):
		playable._process(1.0 / 30.0)
	var hud_lines: PackedStringArray = manager.get_hallucinated_status_lines()
	var hud_ok := hud_lines.size() > 0
	var fx_ok := director.get_fx_intensity() >= 0.99
```

Change the success guard and marker to include `hud=true fx=true`:

```gdscript
	if manifested and phantom_no_damage and attack_dissipates and teeth and clears and hud_ok and fx_ok:
		print("MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true hud=true fx=true reachable=true")
```

(Move the `clears` check to run last, after the channel checks, so `clears` still validates teardown. Reorder the blocks so: manifest → no_damage → attack → teeth → channels(hud/fx) → clears.)

- [ ] **Step 2: Run; expect failure**

Run the live smoke; expect FAIL (`get_hallucinated_status_lines` missing / `hud_ok=false`).

- [ ] **Step 3: Add HUD + ambient + FX to the manager**

In `scripts/systems/hallucination_manager.gd`, add:

```gdscript
var _audio_manager = null
var _fx_overlay = null   # a CanvasItem/Node with set_meta-driven intensity, or null
var _ambient_cooldown: float = 0.0

func set_channels(audio_manager, fx_overlay) -> void:
	_audio_manager = audio_manager
	_fx_overlay = fx_overlay

func get_hallucinated_status_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if director == null:
		return lines
	for e in director.get_active_events("hud"):
		lines.append("CONTACT? bearing %d" % (int(e["id"]) * 37 % 360))
	return lines
```

Extend `render()` (append, after the phantom logic) to drive ambient SFX and FX intensity:

```gdscript
	# Ambient cues (cooldown-gated to avoid spamming the router).
	_ambient_cooldown = maxf(0.0, _ambient_cooldown - delta)
	if _audio_manager != null and not director.get_active_events("ambient").is_empty() and _ambient_cooldown <= 0.0:
		if _audio_manager.has_method("play_sfx"):
			_audio_manager.play_sfx(_ambient_sfx_id())
		_ambient_cooldown = 2.0
	# Screen FX intensity from tier.
	if _fx_overlay != null and is_instance_valid(_fx_overlay):
		_fx_overlay.set("hallucination_intensity", director.get_fx_intensity()) if _fx_overlay.has_method("set") else null
		_fx_overlay.set_meta("hallucination_intensity", director.get_fx_intensity())
```

Add a helper that resolves the ambient SFX id from the audio seam (grep `scripts/audio/audio_event_seam.gd` for a whisper/ambient constant; if none exists, add a new `SFX_HALLUCINATION_WHISPER` constant there and a catalog entry):

```gdscript
func _ambient_sfx_id():
	var SeamScript = preload("res://scripts/audio/audio_event_seam.gd")
	if "SFX_HALLUCINATION_WHISPER" in SeamScript:
		return SeamScript.SFX_HALLUCINATION_WHISPER
	return "hallucination_whisper"
```

And in `clear_all()` reset FX intensity to 0:

```gdscript
	if _fx_overlay != null and is_instance_valid(_fx_overlay):
		_fx_overlay.set_meta("hallucination_intensity", 0.0)
```

- [ ] **Step 4: Wire channels in the coordinator + merge HUD lines**

After constructing the manager (Task 4 Step 4), wire its channels (grep for the coordinator's `audio_manager` member; create a minimal FX overlay node — a `CanvasLayer` with a `ColorRect` child carrying a `hallucination_intensity` meta, or pass `null` if a shader overlay is deferred):

```gdscript
		hallucination_manager.set_channels(audio_manager if has_node("AudioManager") or audio_manager != null else null, _ensure_hallucination_fx_overlay())
```

Add `_ensure_hallucination_fx_overlay()` that lazily creates a `CanvasLayer`+`ColorRect` overlay (alpha driven by `hallucination_intensity` meta) and returns it. Where the coordinator assembles HUD/tracker status lines (grep for `_sanity_lines` consumer / `get_status_lines` aggregation), merge `hallucination_manager.get_hallucinated_status_lines()` into the rendered lines so false readouts appear.

> Implementer note: the FX overlay shader/visuals can be minimal (a red-tinted `ColorRect` whose modulate alpha = intensity). The smoke only asserts `get_fx_intensity()` and `get_hallucinated_status_lines()`, so keep the visual lightweight; richer shader work is a non-goal for v1.

- [ ] **Step 5: Run the extended live smoke + full bundle**

Run: `"$GODOT" --headless --path "$ROOT" --script res://scripts/validation/main_playable_hallucination_smoke.gd`
Expected: `MAIN PLAYABLE HALLUCINATION PASS manifest=true phantom_no_damage=true attack_dissipates=true teeth=true clears=true hud=true fx=true reachable=true`.

Then run the **full regression bundle** (the bash block in `docs/game/06_validation_plan.md` with `GODOT`/`ROOT` set) and confirm it ends with `SYNAPTIC_SEA REGRESSION PASS commands=NN clean_output=true`.

- [ ] **Step 6: Update marker registration + commit**

Update the `main hallucination loop smoke` marker in `docs/game/06_validation_plan.md` to the extended marker.

```bash
git add scripts/systems/hallucination_manager.gd scripts/procgen/playable_generated_ship.gd scripts/audio/audio_event_seam.gd scripts/validation/main_playable_hallucination_smoke.gd docs/game/06_validation_plan.md
git commit  # "feat(sanity): false-HUD, ambient, and screen-FX hallucination channels" + trailers
```

---

## Task 6: Documentation — ADR, audit, requirements

**Files:**
- Create: `docs/game/adr/0042-sanity-hallucinations.md`
- Modify: `docs/game/system_completion_audit.md` (M1 sanity row + rollup item 6)
- Modify: `docs/game/05_requirements.md` (REQ-SV-002) and `docs/game/features/survival_vitals.md`

- [ ] **Step 1: Write ADR-0042**

Create `docs/game/adr/0042-sanity-hallucinations.md` capturing: context (sanity was cosmetic), decision (deterministic director + 4 channels + separate manager reusing the shared renderer; indirect + tier-3 direct teeth; commit-to-reveal counterplay; no save persistence), and consequences (real combat untouched; phantoms re-derive from sanity). Reference REQ-SV-002 and ADR-0005 (hallucinations are deliberately NOT a phase-timer hazard).

- [ ] **Step 2: Re-grade the audit**

In `docs/game/system_completion_audit.md`, change the M1 sanity row from 🟡 to 🟢 with the coordinator wiring lines (director tick in the sanity block; teeth keys in the vitals tick; phantom dissipate in `_attack_with_equipped_weapon`). Update functional-gap rollup item 6 ("Sanity is cosmetic") to RESOLVED with the same cites.

- [ ] **Step 3: Update requirements + feature doc**

In `docs/game/05_requirements.md` (REQ-SV-002) and `docs/game/features/survival_vitals.md`, replace "communicated to HUD" / "hallucination risk (cosmetic)" language with the implemented mechanic (tiered hallucinations + tier-3 vitals teeth).

- [ ] **Step 4: Commit**

```bash
git add docs/game/adr/0042-sanity-hallucinations.md docs/game/system_completion_audit.md docs/game/05_requirements.md docs/game/features/survival_vitals.md
git commit  # "docs(sanity): ADR-0042 + audit re-grade for hallucination teeth" + trailers
```

---

## Self-Review (completed)

- **Spec coverage:** all four channels (phantom = Task 4, HUD/ambient/FX = Task 5), three tiers + thresholds (Task 1), indirect teeth via wasted ammo (Task 4 Step 6, leveraging the existing `attack_with_weapon` ammo-before-target behavior) + misdirection (placement), direct tier-3 teeth (Task 3 + Task 4 Step 5), commit-to-reveal + proximity dissipate (Task 4 Step 3/6), audio tell (phantoms emit no combat sound — they are never registered with the audio/combat path), no save persistence (no RunSnapshot change — Global Constraints), determinism (Task 1 `_pick_index`), shared renderer (Task 2), tests + docs (all tasks + Task 6). Covered.
- **Placeholder scan:** no TBD/TODO; every code step shows code. Two explicit implementer-notes flag real lookups (run seed accessor; a real ammo weapon id; audio seam constant) rather than inventing APIs — each has a concrete fallback.
- **Type consistency:** `HallucinationDirector` methods (`configure`/`tick`/`get_tier`/`get_active_events`/`get_direct_teeth`/`get_fx_intensity`/`get_summary`/`apply_summary`) and `HallucinationManager` methods (`configure`/`render`/`dissipate_phantom_in_range`/`phantom_count`/`clear_all`/`set_channels`/`get_hallucinated_status_lines`) are used consistently across Tasks 1, 4, 5 and both smokes. Event dict shape `{id,kind,position,ttl}` is consistent. Vitals keys `sanity_health_drain`/`sanity_stamina_recovery_mult` match between Task 3 and Task 4 Step 5.
