extends RefCounted
class_name WorkActionDriver

## PKG-B2.2b: pure interact-chain driver for WorkActions.
## Scene/coordinator owns hold-to-work input and range; this owns start/tick,
## completion resolve, inventory yields, noise pulse, and XP event ids.
## Never touches the scene tree.

const WorkActionCatalogScript := preload("res://scripts/systems/work_action_catalog.gd")
const WorkActionStateScript := preload("res://scripts/systems/work_action_state.gd")
const WorkActionResolverScript := preload("res://scripts/systems/work_action_resolver.gd")
const SkillEffectsResolverScript := preload("res://scripts/systems/skill_effects_resolver.gd")
const PillarPersistenceScript := preload("res://scripts/systems/pillar_persistence.gd")

var catalog: RefCounted = null
var skill_effects: RefCounted = null
var work: RefCounted = null ## WorkActionState
var last_resolve: Dictionary = {}
var last_noise_pulse: float = 0.0
var last_xp_event: String = ""
var pending_yields: Dictionary = {}
var cart_mass: float = 0.0
var cart_capacity: float = 100.0
var overloaded: bool = false


func configure(config: Dictionary = {}) -> void:
	catalog = WorkActionCatalogScript.new()
	catalog.load_default()
	skill_effects = SkillEffectsResolverScript.new()
	skill_effects.load_default()
	work = null
	last_resolve = {}
	last_noise_pulse = 0.0
	last_xp_event = ""
	pending_yields = {}
	cart_mass = float(config.get("cart_mass", 0.0))
	cart_capacity = maxf(1.0, float(config.get("cart_capacity", 100.0)))
	overloaded = cart_mass > cart_capacity


func is_working() -> bool:
	if work == null:
		return false
	return str(work.get("status")) == WorkActionStateScript.STATUS_ACTIVE


func get_status() -> String:
	if work == null:
		return WorkActionStateScript.STATUS_IDLE
	return str(work.get("status"))


func progress_ratio() -> float:
	if work == null or not work.has_method("progress_ratio"):
		return 0.0
	return float(work.call("progress_ratio"))


## Build start context from tool, skill, inventory dict, optional progression.
func build_context(
		tool_class: String,
		skill_id: String,
		skill_level: int,
		inventory: Dictionary,
		progression = null,
		class_id: String = "",
		damaged: bool = false) -> Dictionary:
	var verb: String = ""
	var ctx: Dictionary = {
		"tool_class": tool_class,
		"skill_id": skill_id,
		"skill_level": skill_level,
		"inventory": inventory.duplicate(true),
		"damaged": damaged,
		"work_speed_mult": 1.0,
	}
	if skill_effects != null and work != null:
		var def: Dictionary = {}
		if work.has_method("get_summary"):
			def = (work.call("get_summary") as Dictionary).get("definition", {})
		verb = str(def.get("verb", ""))
	if skill_effects != null and skill_effects.has_method("build_work_context"):
		var frag: Dictionary = skill_effects.call("build_work_context", progression, verb, skill_id, class_id)
		ctx["work_speed_mult"] = float(frag.get("work_speed_mult", 1.0))
		if int(frag.get("skill_level", 0)) > skill_level:
			ctx["skill_level"] = int(frag["skill_level"])
	return ctx


func start_action(action_id: String, target_id: String, context: Dictionary = {}) -> bool:
	last_resolve = {}
	last_noise_pulse = 0.0
	last_xp_event = ""
	pending_yields = {}
	if catalog == null or not catalog.has_action(action_id):
		return false
	var def: Dictionary = catalog.get_action(action_id)
	var verb: String = str(def.get("verb", ""))
	if overloaded and verb in ["unbolt", "pry", "cut"]:
		# Cart overload blocks strip/cut yields path start (still allow weld/repair).
		return false
	work = WorkActionStateScript.new()
	work.configure_action(action_id, def)
	var start_ctx: Dictionary = context.duplicate(true)
	# Inject skill work speed if progression provided
	if skill_effects != null and start_ctx.has("progression"):
		var frag: Dictionary = skill_effects.call(
			"build_work_context",
			start_ctx.get("progression"),
			verb,
			str(start_ctx.get("skill_id", "")),
			str(start_ctx.get("class_id", ""))
		)
		if not start_ctx.has("work_speed_mult"):
			start_ctx["work_speed_mult"] = float(frag.get("work_speed_mult", 1.0))
	return bool(work.call("start", target_id, start_ctx))


## Tick active work. Returns status string.
func tick(delta: float, context: Dictionary = {}) -> String:
	if work == null:
		return WorkActionStateScript.STATUS_IDLE
	var st: String = str(work.call("tick", delta, context))
	if st == WorkActionStateScript.STATUS_COMPLETED:
		# Auto-resolve is opt-in via complete() so scene can choose module_map.
		pass
	return st


## Complete against module map + simple inventory Dictionary. Returns resolve dict.
func complete(module_map: RefCounted = null, inventory: Dictionary = {}) -> Dictionary:
	last_resolve = {}
	last_noise_pulse = 0.0
	last_xp_event = ""
	pending_yields = {}
	if work == null:
		return {"ok": false, "reason": "no_work"}
	if str(work.get("status")) != WorkActionStateScript.STATUS_COMPLETED:
		return {"ok": false, "reason": "not_completed"}
	var target_id: String = str(work.get("target_id"))
	# Consume materials first (if any)
	var consumed: Dictionary = work.call("materials_consumed") if work.has_method("materials_consumed") else {}
	if not consumed.is_empty():
		if not WorkActionResolverScript.consume_from_inventory(inventory, consumed):
			work.call("reset")
			return {"ok": false, "reason": "consume_failed"}
	var res: Dictionary = WorkActionResolverScript.resolve_completion(work, module_map, target_id)
	if not bool(res.get("ok", false)):
		return res
	var yields: Dictionary = res.get("yields", {}) if typeof(res.get("yields", {})) == TYPE_DICTIONARY else {}
	# Cart overload: reject yields that would overfill (leave on floor as pending)
	var yield_mass: float = _estimate_yield_mass(yields)
	if cart_mass + yield_mass > cart_capacity and yield_mass > 0.0:
		pending_yields = yields.duplicate(true)
		overloaded = true
		res["cart_overload"] = true
		res["yields_applied"] = false
	else:
		WorkActionResolverScript.apply_yields_to_inventory(inventory, yields)
		cart_mass += yield_mass
		res["yields_applied"] = true
		res["cart_overload"] = false
		if cart_mass > cart_capacity:
			overloaded = true
	last_noise_pulse = float(res.get("noise", 0.0))
	last_xp_event = str(res.get("xp_event", ""))
	last_resolve = res.duplicate(true)
	return res


func interrupt() -> void:
	if work != null and work.has_method("interrupt"):
		work.call("interrupt")


func reset() -> void:
	if work != null and work.has_method("reset"):
		work.call("reset")
	work = null
	last_resolve = {}
	last_noise_pulse = 0.0
	last_xp_event = ""


## Apply noise pulse into DetectionState / ThreatManager-like object.
func apply_noise_to_detection(detection_or_manager) -> float:
	if last_noise_pulse <= 0.0 or detection_or_manager == null:
		return 0.0
	if detection_or_manager.get("player_noise") != null:
		detection_or_manager.player_noise = maxf(
			float(detection_or_manager.player_noise), last_noise_pulse)
	if detection_or_manager.has_method("set_player_signals"):
		# ThreatManager: boost noise channel
		var n: float = last_noise_pulse
		detection_or_manager.set_player_signals(
			n,
			float(detection_or_manager.get("player_light") if detection_or_manager.get("player_light") != null else 0.35),
			float(detection_or_manager.get("player_sight") if detection_or_manager.get("player_sight") != null else 0.5),
			bool(detection_or_manager.get("player_crouching") if detection_or_manager.get("player_crouching") != null else false),
			str(detection_or_manager.get("player_room_id") if detection_or_manager.get("player_room_id") != null else "")
		)
	if detection_or_manager.get("noise_level") != null:
		detection_or_manager.noise_level = maxf(float(detection_or_manager.noise_level), last_noise_pulse)
	return last_noise_pulse


## Emit XP via TrainingEventBus when last_xp_event is a known training event id,
## or via progression.grant_xp(skill, amount) fallback.
func apply_xp(training_bus = null, progression = null, amount: int = 15) -> bool:
	if last_xp_event.is_empty():
		return false
	if training_bus != null and training_bus.has_method("emit"):
		# Prefer event bus when event_id is registered (emit(event_id, target_id, progression)).
		if training_bus.has_method("is_known") and bool(training_bus.call("is_known", last_xp_event)):
			training_bus.call("emit", last_xp_event, "work_action", progression)
			return true
	if progression != null and progression.has_method("grant_xp"):
		# Map xp_event string to skill when possible
		var skill: String = last_xp_event
		if skill == "weld":
			skill = "welding"
		elif skill == "salvage":
			skill = "scavenging"
		progression.call("grant_xp", skill, amount)
		return true
	return false


func get_persistence_summary() -> Dictionary:
	return PillarPersistenceScript.pack_work_action(work)


func apply_persistence_summary(summary: Dictionary) -> bool:
	work = PillarPersistenceScript.unpack_work_action(summary)
	return work != null


## List candidate targets for a verb from module map + placement (pure ids).
func list_targets(verb: String, module_map: RefCounted = null, placement: RefCounted = null) -> Array:
	var out: Array = []
	if module_map != null and module_map.has_method("to_sparse_deltas"):
		# Prefer damaged modules for weld/patch; all for cut
		var deltas: Array = module_map.call("to_sparse_deltas")
		for d in deltas:
			if typeof(d) != TYPE_DICTIONARY:
				continue
			out.append({
				"target_id": str(d.get("module_id", "")),
				"kind": "module",
				"verb": verb,
			})
	if placement != null and placement.get("placed") != null:
		for e in placement.placed:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			if not bool((e as Dictionary).get("mounted", true)):
				continue
			out.append({
				"target_id": str((e as Dictionary).get("component_instance_id", "")),
				"kind": "component",
				"verb": verb,
			})
	return out


func _estimate_yield_mass(yields: Dictionary) -> float:
	var mass: float = 0.0
	for k in yields.keys():
		mass += 2.0 * float(yields[k])  # 2 mass units per scrap unit (simple)
	return mass
