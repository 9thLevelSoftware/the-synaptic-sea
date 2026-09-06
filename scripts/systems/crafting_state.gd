extends RefCounted
class_name CraftingState

const StationStateScript := preload("res://scripts/systems/station_state.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")
const ItemQualityEffectsScript := preload("res://scripts/systems/item_quality_effects.gd")
const CraftJobSchedulerScript := preload("res://scripts/systems/craft_job_scheduler.gd")
const MAX_SAFE_JSON_INTEGER: float = 9007199254740991.0

## Pure model for the crafting engine. Loads recipes, validates ingredient
## availability against an InventoryState, resolves output quality via
## QualityTierResolver, and manages active craft progress via StationState.
## Never touches the scene tree.

const RECIPE_DEFINITIONS_PATH: String = "res://data/recipes/recipe_definitions.json"

var _recipes: Dictionary = {}      # recipe_id -> recipe Dictionary
var _station_states: Dictionary = {}  # station_kind -> StationState
var _active_craft: Dictionary = {}    # recipe_id, station_kind, progress tracking
var _queue_knowledge: Dictionary = {} # station_kind -> current-run knowledge owner
var _craft_job_scheduler: RefCounted = CraftJobSchedulerScript.new()
var _physical_station_states: Dictionary = {} # [ship_id, station_instance_id] -> StationState
var _job_contexts: Dictionary = {} # owner key -> paid reservation/run dependencies
var _completion_receipts: Array = []
var _legacy_restore_ship_id: String = ""
var _legacy_restore_source_holder_id: String = ""

func _init() -> void:
	_load_recipes()
	_craft_job_scheduler.call("configure_recipe_authority", self)

func _load_recipes() -> void:
	if not FileAccess.file_exists(RECIPE_DEFINITIONS_PATH):
		return
	var file := FileAccess.open(RECIPE_DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var recipes_array: Variant = (parsed as Dictionary).get("recipes", [])
		if recipes_array is Array:
			for recipe_variant in (recipes_array as Array):
				if recipe_variant is Dictionary:
					var recipe: Dictionary = recipe_variant as Dictionary
					var rid: String = str(recipe.get("recipe_id", ""))
					if not rid.is_empty():
						_recipes[rid] = recipe

func recipe_count() -> int:
	return _recipes.size()

func get_recipe(recipe_id: String) -> Dictionary:
	var r: Variant = _recipes.get(recipe_id, {})
	return r if r is Dictionary else {}

func get_recipe_catalog() -> Dictionary:
	return _recipes.duplicate(true)

func get_recipes_for_station(station_kind: String) -> Array:
	var out: Array = []
	for rid in _recipes:
		var recipe: Dictionary = _recipes[rid]
		if str(recipe.get("station_kind", "")) == station_kind:
			out.append(recipe.duplicate(true))
	return out

func get_recipes_by_category(category: String) -> Array:
	var out: Array = []
	for rid in _recipes:
		var recipe: Dictionary = _recipes[rid]
		if str(recipe.get("category", "")) == category:
			out.append(recipe.duplicate(true))
	return out

func get_all_recipe_ids() -> Array:
	var ids: Array = _recipes.keys()
	ids.sort()
	return ids

func has_recipe(recipe_id: String) -> bool:
	return _recipes.has(recipe_id)

# --- ingredient validation ---

## Returns true if the inventory has enough of every ingredient.
## PKG-B2.4a: optional knowledge gate — pass knowledge state as third arg.
## PKG-B2.4b: optional station_tier gate (4th arg); defaults to 0 (base stations).
func can_craft(recipe_id: String, inventory, knowledge = null, station_tier: int = 0) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if not is_recipe_known(recipe_id, knowledge):
		return false
	var need_tier: int = int(recipe.get("station_tier_min", 0))
	if station_tier < need_tier:
		return false
	var ingredients: Variant = recipe.get("ingredients", {})
	if not (ingredients is Dictionary):
		return false
	for mat_id in (ingredients as Dictionary):
		var need: int = int((ingredients as Dictionary)[mat_id])
		if inventory.get_quantity(str(mat_id)) < need:
			return false
	return true


## Locked authored recipes require the current-run knowledge owner. Starters keep
## their established compatibility behavior when legacy callers omit that owner.
func is_recipe_known(recipe_id: String, knowledge = null) -> bool:
	var source: String = get_knowledge_source(recipe_id)
	if source.is_empty() or source == "starter":
		return true
	return knowledge != null and knowledge.has_method("is_known") and bool(knowledge.call("is_known", recipe_id))


func recipe_knowledge_hint(recipe_id: String) -> String:
	var recipe: Dictionary = get_recipe(recipe_id)
	match get_knowledge_source(recipe_id):
		"book": return "Read %s" % str(recipe.get("knowledge_book_id", "a matching schematic"))
		"codex": return "Discover codex entry %s" % str(recipe.get("knowledge_codex_id", "unknown"))
		"reverse_engineer": return "Reverse engineer %s" % str(recipe.get("reverse_engineer_component", "a matching component"))
	return ""

## Consumes ingredients from inventory. Returns true if successful.
func consume_ingredients(recipe_id: String, inventory) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	var ingredients: Variant = recipe.get("ingredients", {})
	if not (ingredients is Dictionary):
		return false
	# Verify first
	for mat_id in (ingredients as Dictionary):
		var need: int = int((ingredients as Dictionary)[mat_id])
		if inventory.get_quantity(str(mat_id)) < need:
			return false
	# Consume
	for mat_id in (ingredients as Dictionary):
		var need: int = int((ingredients as Dictionary)[mat_id])
		inventory.remove_item(str(mat_id), need)
	return true

## Returns the produced item_id and base quantity for a recipe.
func get_produces(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = get_recipe(recipe_id)
	var produces: Variant = recipe.get("produces", {})
	if produces is Dictionary:
		return (produces as Dictionary).duplicate()
	return {}

## Returns the required skill level for a recipe.
func get_required_skill_level(recipe_id: String) -> int:
	return int(get_recipe(recipe_id).get("required_skill_level", 0))

## Returns the station kind for a recipe.
func get_station_kind(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("station_kind", ""))

## Returns the craft time in seconds for a recipe.
func get_craft_time(recipe_id: String) -> float:
	return float(get_recipe(recipe_id).get("craft_time_seconds", 0.0))

## Returns the power cost for a recipe.
func get_power_cost(recipe_id: String) -> float:
	return float(get_recipe(recipe_id).get("power_cost", 0.0))


## PKG-B2.4b schema accessors
func get_station_tier_min(recipe_id: String) -> int:
	return int(get_recipe(recipe_id).get("station_tier_min", 0))


func get_knowledge_source(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("knowledge_source", "starter"))


func get_work_verb(recipe_id: String) -> String:
	return str(get_recipe(recipe_id).get("work_verb", "craft"))


## PKG-B2.4b: derive station tier from placed components that declare station_tier_bonus
## and optional station_kind affinity.
static func derive_tier_from_components(station_kind: String, placed: Array, catalog: RefCounted = null) -> int:
	var best: int = 0
	for entry in placed:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = entry
		if not bool(e.get("mounted", true)):
			continue
		var bonus: int = int(e.get("station_tier_bonus", 0))
		var affinity: String = str(e.get("station_affinity", ""))
		if bonus <= 0 and catalog != null and catalog.has_method("get_component"):
			var def: Dictionary = catalog.call("get_component", str(e.get("component_id", "")))
			bonus = int(def.get("station_tier_bonus", 0))
			if affinity.is_empty():
				affinity = str(def.get("station_affinity", ""))
		if bonus <= 0:
			continue
		if not affinity.is_empty() and affinity != station_kind and affinity != "any":
			continue
		if bonus > best:
			best = bonus
	return best

## Headless listing for the station recipe picker (REQ-CS-016).
## Returns Array[Dictionary] sorted by recipe_id. Excludes deconstruction recipes
## (those belong to the salvage bench / DeconstructionResolver).
## Each entry:
##   recipe_id, display_name, category, required_skill_level, ingredients, produces,
##   craft_time_seconds, station_tier_min, work_verb, knowledge_source,
##   status ("ready"|"missing_ingredients"|"insufficient_skill"|"insufficient_tier"|"output_full"),
##   craftable:bool
## station_tier optional (default 0) for PKG-B2.4b tier gating.
func list_recipe_entries(
		station_kind: String,
		inventory,
		player_skill_level: int,
		station_tier: int = 0,
		knowledge = null,
		quality_skill_level: int = -1,
		station_powered: bool = true,
		allow_pending_output: bool = false) -> Array:
	var out: Array = []
	var recipes: Array = get_recipes_for_station(station_kind)
	recipes.sort_custom(func(a, b): return str(a.get("recipe_id", "")) < str(b.get("recipe_id", "")))
	for recipe in recipes:
		if not (recipe is Dictionary):
			continue
		var rid: String = str(recipe.get("recipe_id", ""))
		if rid.is_empty():
			continue
		if str(recipe.get("category", "")) == "deconstruction":
			continue
		var required_skill: int = int(recipe.get("required_skill_level", 0))
		var tier_min: int = int(recipe.get("station_tier_min", 0))
		var produces: Dictionary = {}
		var produces_raw: Variant = recipe.get("produces", {})
		if produces_raw is Dictionary:
			produces = (produces_raw as Dictionary).duplicate()
		var ingredients: Dictionary = {}
		var ingredients_raw: Variant = recipe.get("ingredients", {})
		if ingredients_raw is Dictionary:
			ingredients = (ingredients_raw as Dictionary).duplicate()
		var status: String = "ready"
		if not is_recipe_known(rid, knowledge):
			status = "missing_recipe_knowledge"
		elif player_skill_level < required_skill:
			status = "insufficient_skill"
		elif station_tier < tier_min:
			status = "insufficient_tier"
		elif not can_craft(rid, inventory, knowledge, station_tier):
			status = "missing_ingredients"
		elif not allow_pending_output and inventory != null and inventory.has_method("can_accept"):
			var out_id: String = str(produces.get("item_id", ""))
			var out_qty: int = int(produces.get("quantity", 0))
			if not out_id.is_empty() and out_qty > 0 and not inventory.can_accept(out_id, out_qty):
				status = "output_full"
		var entry: Dictionary = {
			"recipe_id": rid,
			"display_name": str(recipe.get("display_name", rid)),
			"category": str(recipe.get("category", "")),
			"required_skill_level": required_skill,
			"station_tier_min": tier_min,
			"work_verb": str(recipe.get("work_verb", "craft")),
			"knowledge_source": str(recipe.get("knowledge_source", "starter")),
			"knowledge_hint": recipe_knowledge_hint(rid),
			"ingredients": ingredients,
			"produces": produces,
			"craft_time_seconds": float(recipe.get("craft_time_seconds", 0.0)),
			"status": status,
			"craftable": status == "ready",
		}
		entry["quality_preview"] = _quality_preview(
			ingredients, produces, inventory,
			player_skill_level if quality_skill_level < 0 else quality_skill_level,
			station_tier, station_powered)
		out.append(entry)
	return out


## Read-only prediction from the same stable lot order used by ItemLotLedger.
## Missing exact lot metadata produces no estimate rather than falling back to a
## stale MaterialState average.
func _quality_preview(
		ingredients: Dictionary,
		produces: Dictionary,
		inventory,
		skill_level: int,
		station_tier: int,
		station_powered: bool) -> Dictionary:
	var selected_lots: Array = _preview_ingredient_lots(ingredients, inventory)
	if selected_lots.is_empty() and not ingredients.is_empty():
		return {}
	var weighted: float = 0.0
	var quantity: int = 0
	for lot_v in selected_lots:
		if not lot_v is Dictionary:
			return {}
		var lot: Dictionary = lot_v as Dictionary
		var lot_quantity: int = maxi(0, int(lot.get("quantity", 0)))
		weighted += clampf(float(lot.get("quality_score", 0.5)), 0.0, 1.0) * float(lot_quantity)
		quantity += lot_quantity
	var input_quality: float = weighted / float(quantity) if quantity > 0 else 0.5
	var resolved: Dictionary = QualityTierResolverScript.new().resolve(
		input_quality, skill_level, station_tier, station_powered)
	var item_id: String = str(produces.get("item_id", ""))
	var output_lot: Dictionary = {
		"quality_score": float(resolved.get("score", 0.5)),
		"quality_tier": str(resolved.get("tier", "standard")),
	}
	var effects = ItemQualityEffectsScript.new()
	var input_lot_ids: Array[String] = []
	for selected_lot_v in selected_lots:
		if selected_lot_v is Dictionary:
			input_lot_ids.append(str((selected_lot_v as Dictionary).get("lot_id", "")))
	return {
		"input_quality_score": input_quality,
		"score": float(resolved.get("score", 0.5)),
		"tier": str(resolved.get("tier", "standard")),
		"multiplier": float(resolved.get("multiplier", 1.0)),
		"consumer": effects.consumer_for(item_id),
		"effect_text": effects.effect_text_for_lot(item_id, output_lot),
		"input_lot_ids": input_lot_ids,
	}


func _preview_ingredient_lots(ingredients: Dictionary, inventory) -> Array:
	if ingredients.is_empty():
		return []
	if inventory == null or not inventory.has_method("get_lot_summary"):
		return []
	var lots_v: Variant = inventory.get_lot_summary().get("lots", [])
	if not lots_v is Array:
		return []
	var selected: Array = []
	var item_ids: Array = ingredients.keys()
	item_ids.sort()
	for item_v in item_ids:
		var item_id: String = str(item_v)
		var candidates: Array = []
		for lot_v in lots_v as Array:
			if lot_v is Dictionary and str((lot_v as Dictionary).get("item_id", "")) == item_id:
				candidates.append((lot_v as Dictionary).duplicate(true))
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_standard: bool = str(a.get("quality_tier", "")) == "standard"
			var b_standard: bool = str(b.get("quality_tier", "")) == "standard"
			return a_standard if a_standard != b_standard \
				else str(a.get("lot_id", "")) < str(b.get("lot_id", ""))
		)
		var remaining: int = int(ingredients[item_v])
		for candidate_v in candidates:
			if remaining <= 0:
				break
			var candidate: Dictionary = candidate_v as Dictionary
			var amount: int = mini(remaining, int(candidate.get("quantity", 0)))
			if amount <= 0:
				continue
			candidate["quantity"] = amount
			selected.append(candidate)
			remaining -= amount
		if remaining > 0:
			return []
	return selected

# --- station management ---

func get_or_create_station(station_kind: String):
	if _station_states.has(station_kind):
		return _station_states[station_kind]
	var station = StationStateScript.new()
	station.configure({"station_kind": station_kind, "level": 0, "powered": true})
	_station_states[station_kind] = station
	return station

func get_station(station_kind: String):
	return _station_states.get(station_kind, null)

func get_station_tier(station_kind: String) -> int:
	var station = get_or_create_station(station_kind)
	return int(station.effective_tier()) if station.has_method("effective_tier") else int(station.get("level"))


func get_station_powered(station_kind: String) -> bool:
	return bool(get_or_create_station(station_kind).get("powered"))


func get_or_create_station_instance(ship_id: String, station_instance_id: String, station_kind: String):
	if ship_id.is_empty() or station_instance_id.is_empty():
		return get_or_create_station(station_kind)
	var key: String = _owner_key(ship_id, station_instance_id)
	if _physical_station_states.has(key):
		var existing = _physical_station_states[key]
		_sync_legacy_station_alias(ship_id, station_instance_id, station_kind, existing)
		return existing
	var inherited = get_or_create_station(station_kind)
	var station = StationStateScript.new()
	station.configure({
		"ship_id": ship_id,
		"station_instance_id": station_instance_id,
		"station_kind": station_kind,
		"level": int(inherited.get("level")),
		# The generic station is a picker compatibility projection. Its derived
		# component tier belongs to no physical owner and must not seed a station
		# created later on another ship.
		"tier": int(inherited.get("level")),
		"powered": bool(inherited.get("powered")),
	})
	_physical_station_states[key] = station
	return station


## The pre-P07 direct API exposes one station per kind. Its synthetic paid owner
## remains an alias of that model so a legacy tier/power change made after a
## denied attempt is visible on retry. Real physical owners retain independent
## component-derived tier and power.
func _sync_legacy_station_alias(
		ship_id: String,
		station_instance_id: String,
		station_kind: String,
		station: RefCounted) -> void:
	if ship_id != "legacy-crafting" or station_instance_id != "legacy:%s" % station_kind:
		return
	var inherited = get_or_create_station(station_kind)
	station.set("level", int(inherited.get("level")))
	station.set("tier", int(inherited.get("tier")))
	if station.has_method("set_power"):
		station.call("set_power", bool(inherited.get("powered")))
	else:
		station.set("powered", bool(inherited.get("powered")))


func get_station_instance(ship_id: String, station_instance_id: String):
	return _physical_station_states.get(_owner_key(ship_id, station_instance_id), null)


func get_station_instance_tier(ship_id: String, station_instance_id: String, station_kind: String) -> int:
	var station = get_or_create_station_instance(ship_id, station_instance_id, station_kind)
	return int(station.effective_tier()) \
		if station.has_method("effective_tier") else int(station.get("level"))


func get_craft_job_scheduler() -> RefCounted:
	return _craft_job_scheduler


func configure_legacy_restore_owner(ship_id: String, source_holder_id: String) -> bool:
	if ship_id.is_empty() or source_holder_id.is_empty():
		return false
	_legacy_restore_ship_id = ship_id
	_legacy_restore_source_holder_id = source_holder_id
	return true


func receive_completion_receipts(receipts: Array) -> int:
	return _collect_completion_receipts(receipts)


func has_completion_receipts() -> bool:
	return not _completion_receipts.is_empty()


func completion_receipt_count() -> int:
	return _completion_receipts.size()


## Reattaches non-serializable live dependencies after a station scene is built
## or rebuilt around restored scheduler state.
func bind_station_runtime_context(
		ship_id: String,
		station_instance_id: String,
		station_kind: String,
		inventory,
		knowledge = null,
		player_progression = null,
		pending_output_store = null) -> bool:
	if ship_id.is_empty() or station_instance_id.is_empty() or not inventory is RefCounted:
		return false
	var station = get_or_create_station_instance(ship_id, station_instance_id, station_kind)
	_job_contexts[_owner_key(ship_id, station_instance_id)] = {
		"ship_id": ship_id,
		"station_instance_id": station_instance_id,
		"station_state": station,
		"source_inventory": inventory,
		"knowledge": knowledge,
		"player_progression": player_progression,
		"pending_output_store": pending_output_store,
	}
	if inventory.has_method("bind_craft_reservation_authority"):
		inventory.call("bind_craft_reservation_authority", _craft_job_scheduler)
	return true


## Reattaches the live holder services required by migration-only station jobs.
## These stations have no scene node and therefore are not covered by the normal
## station rebuild. They remain isolated from generic enqueue APIs below.
func bind_legacy_migration_jobs(
		inventory: RefCounted, knowledge = null, player_progression = null,
		pending_output_store = null) -> bool:
	if inventory == null:
		return false
	var bound_any: bool = false
	var summary: Dictionary = _craft_job_scheduler.call("get_summary")
	for owner_variant in summary.get("owners", []) as Array:
		if not owner_variant is Dictionary:
			return false
		var owner: Dictionary = owner_variant
		var ship_id: String = str(owner.get("ship_id", ""))
		var station_id: String = str(owner.get("station_instance_id", ""))
		if not _is_migration_station(ship_id, station_id):
			continue
		var station = get_station_instance(ship_id, station_id)
		if station == null:
			return false
		if not bind_station_runtime_context(
				ship_id, station_id, str(station.get("station_kind")), inventory,
				knowledge, player_progression, pending_output_store):
			return false
		bound_any = true
	return bound_any

func remove_station(station_kind: String) -> void:
	_station_states.erase(station_kind)

# --- crafting execution ---

## Begins a paid job at its designated station. Legacy callers receive a stable
## synthetic owner; spatial stations pass their physical ship and placement IDs.
func begin_craft(
		recipe_id: String,
		inventory,
		_material_state,
		player_skill_level: int,
		knowledge = null,
		ship_id: String = "legacy-crafting",
		station_instance_id: String = "",
		selected_lot_ids: Dictionary = {}) -> bool:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty() or not inventory is RefCounted:
		return false
	var station_kind: String = str(recipe.get("station_kind", ""))
	if station_kind.is_empty():
		return false
	var stable_station_id: String = station_instance_id
	if stable_station_id.is_empty():
		stable_station_id = "legacy:%s" % station_kind
	if _is_migration_station(ship_id, stable_station_id):
		return false
	if is_station_busy(ship_id, stable_station_id):
		return false
	var station = get_or_create_station_instance(ship_id, stable_station_id, station_kind)
	var owner_key: String = _owner_key(ship_id, stable_station_id)
	var local_context: Dictionary = (_job_contexts.get(owner_key, {}) as Dictionary).duplicate(false)
	local_context["ship_id"] = ship_id
	local_context["station_instance_id"] = stable_station_id
	local_context["station_state"] = station
	local_context["source_inventory"] = inventory
	local_context["knowledge"] = knowledge
	local_context["player_skill_level"] = player_skill_level
	_job_contexts[owner_key] = local_context
	if inventory.has_method("bind_craft_reservation_authority"):
		inventory.call("bind_craft_reservation_authority", _craft_job_scheduler)
	var holder_id: String = str(inventory.call("get_holder_namespace")) \
		if inventory.has_method("get_holder_namespace") else ""
	var result: Dictionary = _craft_job_scheduler.call("enqueue", {
		"ship_id": ship_id,
		"station_instance_id": stable_station_id,
		"station_kind": station_kind,
		"recipe_id": recipe_id,
		"source_holder_id": holder_id,
		"selected_lot_ids": selected_lot_ids,
	}, _scheduler_context())
	if not bool(result.get("ok", false)):
		return false
	var job_id: String = str(result.get("job_id", ""))
	_active_craft = {
		"job_id": job_id,
		"ship_id": ship_id,
		"station_instance_id": stable_station_id,
		"recipe_id": recipe_id,
		"station_kind": station_kind,
	}
	_collect_completion_receipts(_craft_job_scheduler.call("advance", 0.0, _scheduler_context()))
	return true


## PKG-B2.4b: queue a recipe (or batch) on its station without starting craft.
## Returns accepted queue count (0 if full / invalid).
func enqueue_craft(
		recipe_id: String,
		count: int = 1,
		knowledge = null,
		inventory = null,
		_material_state = null,
		player_skill_level: int = 0,
		ship_id: String = "legacy-crafting",
		station_instance_id: String = "",
		selected_lot_ids: Dictionary = {}) -> int:
	var recipe: Dictionary = get_recipe(recipe_id)
	if recipe.is_empty() or count <= 0 or not inventory is RefCounted:
		return 0
	var station_kind: String = str(recipe.get("station_kind", ""))
	if station_kind.is_empty():
		return 0
	var stable_station_id: String = station_instance_id if not station_instance_id.is_empty() \
		else "legacy:%s" % station_kind
	if _is_migration_station(ship_id, stable_station_id):
		return 0
	var station = get_or_create_station_instance(ship_id, stable_station_id, station_kind)
	var owner_key: String = _owner_key(ship_id, stable_station_id)
	var local_context: Dictionary = (_job_contexts.get(owner_key, {}) as Dictionary).duplicate(false)
	local_context["ship_id"] = ship_id
	local_context["station_instance_id"] = stable_station_id
	local_context["station_state"] = station
	local_context["source_inventory"] = inventory
	local_context["knowledge"] = knowledge
	local_context["player_skill_level"] = player_skill_level
	_job_contexts[owner_key] = local_context
	if inventory.has_method("bind_craft_reservation_authority"):
		inventory.call("bind_craft_reservation_authority", _craft_job_scheduler)
	var holder_id: String = str(inventory.call("get_holder_namespace")) \
		if inventory.has_method("get_holder_namespace") else ""
	var accepted: int = 0
	for _i in range(count):
		var result: Dictionary = _craft_job_scheduler.call("enqueue", {
			"ship_id": ship_id,
			"station_instance_id": stable_station_id,
			"station_kind": station_kind,
			"recipe_id": recipe_id,
			"source_holder_id": holder_id,
			"selected_lot_ids": selected_lot_ids,
		}, _scheduler_context())
		if not bool(result.get("ok", false)):
			break
		accepted += 1
	return accepted


## Refresh a generic picker projection or one explicitly owned physical station.
## An unscoped call never broadcasts across ships.
func refresh_station_tier(
		station_kind: String,
		placed: Array,
		catalog: RefCounted = null,
		ship_id: String = "",
		station_instance_id: String = "") -> int:
	if ship_id.is_empty() != station_instance_id.is_empty():
		return -1
	var derived: int = derive_tier_from_components(station_kind, placed, catalog)
	var station = get_or_create_station(station_kind) if ship_id.is_empty() \
		else get_or_create_station_instance(ship_id, station_instance_id, station_kind)
	if station.has_method("apply_component_tier"):
		station.apply_component_tier(derived)
	return int(station.effective_tier()) if station.has_method("effective_tier") else derived

## Ticks the active station. Returns true when the craft completes.
func tick(delta_seconds: float) -> bool:
	if _active_craft.is_empty():
		var background_receipts: Variant = _craft_job_scheduler.call("advance", delta_seconds, _scheduler_context())
		_collect_completion_receipts(background_receipts)
		return not _completion_receipts.is_empty()
	if not str(_active_craft.get("job_id", "")).is_empty():
		var receipts: Variant = _craft_job_scheduler.call("advance", delta_seconds, _scheduler_context())
		_collect_completion_receipts(receipts)
		return not _completion_receipts.is_empty()
	# FieldCraftingState retains its portable direct station authority.
	var station_kind: String = str(_active_craft.get("station_kind", ""))
	var station = get_station(station_kind)
	if station == null:
		return false
	var completed: bool = station.tick(delta_seconds)
	if completed:
		return true
	return false

## Call after tick returns true to collect the finished product.
## Returns {item_id, quantity, quality_tier, quality_multiplier} or empty dict.
func finish_craft() -> Dictionary:
	if _active_craft.is_empty() and _completion_receipts.is_empty():
		return {}
	var job_id: String = ""
	if not _completion_receipts.is_empty() and _completion_receipts[0] is Dictionary:
		job_id = str((_completion_receipts[0] as Dictionary).get("job_id", ""))
	if job_id.is_empty():
		job_id = str(_active_craft.get("job_id", ""))
	if not job_id.is_empty():
		var claimed: Dictionary = _settle_job_output(job_id)
		if not bool(claimed.get("ok", false)):
			return {}
		_remove_completion_receipt(job_id)
		var lots: Array = claimed.get("output_lots", []) as Array
		if lots.is_empty() or not lots[0] is Dictionary:
			return {}
		var lot: Dictionary = lots[0]
		var result: Dictionary = {
			"item_id": str(lot.get("item_id", "")),
			"quantity": int(lot.get("quantity", 0)),
			"quality_tier": str(lot.get("quality_tier", "standard")),
			"quality_multiplier": QualityTierResolverScript.new().multiplier_for_tier(
				str(lot.get("quality_tier", "standard"))),
			"quality_score": float(lot.get("quality_score", 0.5)),
			"station_kind": str(claimed.get("station_kind", "")),
			"ship_id": str(claimed.get("ship_id", "")),
			"station_instance_id": str(claimed.get("station_instance_id", "")),
			"recipe_id": str(claimed.get("recipe_id", "")),
			"job_id": job_id,
			"receipt_id": str(claimed.get("receipt_id", "")),
			"output_lot": lot.duplicate(true),
			"pending": bool(claimed.get("pending", false)),
		}
		if str(_active_craft.get("job_id", "")) == job_id:
			var ship_id: String = str(_active_craft.get("ship_id", ""))
			var station_id: String = str(_active_craft.get("station_instance_id", ""))
			var next_id: String = str(_craft_job_scheduler.call("get_active_job_id", ship_id, station_id))
			if next_id.is_empty():
				_active_craft.clear()
			else:
				_set_active_from_job(next_id)
		return result
	var station_kind: String = str(_active_craft.get("station_kind", ""))
	var station = get_station(station_kind)
	if station == null:
		return {}
	if int(station.status) != 3:
		return {}
	var recipe_id: String = str(_active_craft.get("recipe_id", ""))
	var produces: Dictionary = get_produces(recipe_id)
	var result: Dictionary = {
		"item_id": str(produces.get("item_id", "")),
		"quantity": int(produces.get("quantity", 0)),
		"quality_tier": str(_active_craft.get("quality_tier", "standard")),
		"quality_multiplier": float(_active_craft.get("quality_multiplier", 1.0)),
		"quality_score": float(_active_craft.get("quality_score", 0.5)),
		# Stream D: station_kind/recipe_id survive finish so the coordinator can
		# route training emissions (cook_meal vs fabricate_part) without racing
		# _active_craft.clear().
		"station_kind": station_kind,
		"recipe_id": recipe_id,
	}
	var next_recipe: String = station.finish_and_advance()
	if next_recipe.is_empty():
		_active_craft.clear()
	else:
		# Auto-start next queued recipe if possible (simplified: just start it)
		var queued_knowledge = _queue_knowledge.get(station_kind, null)
		if not is_recipe_known(next_recipe, queued_knowledge):
			_active_craft.clear()
		else:
			var next_time: float = get_craft_time(next_recipe)
			station.start_recipe(next_recipe, next_time)
			_active_craft["recipe_id"] = next_recipe
			_active_craft["station_kind"] = station_kind
	return result

func is_crafting() -> bool:
	return not _active_craft.is_empty() or not _completion_receipts.is_empty()


func is_station_busy(ship_id: String, station_instance_id: String) -> bool:
	return not str(_craft_job_scheduler.call(
		"get_active_job_id", ship_id, station_instance_id)).is_empty()

func get_active_recipe_id() -> String:
	return str(_active_craft.get("recipe_id", ""))

func get_active_station_kind() -> String:
	return str(_active_craft.get("station_kind", ""))

func cancel_craft() -> Dictionary:
	var job_id: String = str(_active_craft.get("job_id", ""))
	if not job_id.is_empty():
		var context: Dictionary = _scheduler_context()
		context["ship_id"] = str(_active_craft.get("ship_id", ""))
		context["station_instance_id"] = str(
			_active_craft.get("station_instance_id", ""))
		var result: Dictionary = _craft_job_scheduler.call("cancel", job_id, context)
		if not bool(result.get("ok", false)) and str(result.get("reason", "")) == "refund_destination_full":
			result = _recover_job_refund(job_id, context)
		if bool(result.get("ok", false)):
			_active_craft.clear()
		return result
	_active_craft.clear()
	for station_kind in _station_states:
		var station = _station_states[station_kind]
		if station.is_crafting():
			station.status = 0
			station.active_recipe_id = ""
			station.progress_seconds = 0.0
			station.required_seconds = 0.0
	return {"ok": true, "reason": "", "result": "cancelled"}


func cancel_job(job_id: String, ship_id: String = "", station_instance_id: String = "") -> Dictionary:
	if ship_id.is_empty() or station_instance_id.is_empty():
		return {"ok": false, "reason": "missing_owner"}
	var context: Dictionary = _scheduler_context()
	context["ship_id"] = ship_id
	context["station_instance_id"] = station_instance_id
	var result: Dictionary = _craft_job_scheduler.call("cancel", job_id, context)
	if not bool(result.get("ok", false)) and str(result.get("reason", "")) == "refund_destination_full":
		result = _recover_job_refund(job_id, context)
	if bool(result.get("ok", false)) and str(_active_craft.get("job_id", "")) == job_id:
		_active_craft.clear()
	return result


func admit_legacy_unreserved(
		job_id: String, inventory: RefCounted, knowledge = null,
		player_skill_level: int = 0, selected_lot_ids: Dictionary = {}) -> Dictionary:
	var job: Dictionary = _craft_job_scheduler.call("get_job", job_id)
	if job.is_empty() or str(job.get("state", "")) != "blocked_unreserved" \
			or not str(job.get("station_instance_id", "")).begins_with(
				"legacy:%s:" % str(job.get("ship_id", ""))):
		return {"ok": false, "reason": "not_blocked_unreserved"}
	var ship_id: String = str(job.ship_id)
	var station_id: String = str(job.station_instance_id)
	var station_kind: String = str(job.station_kind)
	bind_station_runtime_context(
		ship_id, station_id, station_kind, inventory, knowledge,
		null, _pending_store_for_job(job))
	var owner_key: String = _owner_key(ship_id, station_id)
	var context: Dictionary = (_job_contexts.get(owner_key, {}) as Dictionary).duplicate(false)
	context["player_skill_level"] = player_skill_level
	_job_contexts[owner_key] = context
	return _craft_job_scheduler.call(
		"admit_blocked_unreserved", job_id, selected_lot_ids, _scheduler_context())

# --- save/load ---

func get_summary() -> Dictionary:
	var station_summaries: Dictionary = {}
	for sk in _station_states:
		station_summaries[str(sk)] = _station_states[sk].get_summary()
	var physical_summaries: Dictionary = {}
	for owner_key in _physical_station_states:
		physical_summaries[str(owner_key)] = _physical_station_states[owner_key].get_summary()
	return {
		"recipe_count": recipe_count(),
		"active_craft": _active_craft.duplicate(true),
		"station_summaries": station_summaries,
		"physical_station_summaries": physical_summaries,
		"craft_jobs_v1": _craft_job_scheduler.call("get_summary"),
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	if summary.has("legacy_craft_migration_v1"):
		return _apply_legacy_bridge_summary(summary)
	if summary.has("craft_jobs_v1"):
		return _apply_current_summary(summary)
	return _apply_legacy_summary(summary)


func _apply_legacy_bridge_summary(summary: Dictionary) -> bool:
	if _legacy_restore_ship_id.is_empty() or _legacy_restore_source_holder_id.is_empty() \
			or not summary.get("legacy_craft_migration_v1", null) is Dictionary:
		return false
	var bridge_result: Dictionary = _craft_job_scheduler.call(
		"build_legacy_migration_summary", summary.legacy_craft_migration_v1,
		_legacy_restore_ship_id, _legacy_restore_source_holder_id)
	if bridge_result.is_empty():
		return false
	var current: Dictionary = summary.duplicate(true)
	current.erase("legacy_craft_migration_v1")
	current["craft_jobs_v1"] = bridge_result.craft_jobs_v1
	current["physical_station_summaries"] = bridge_result.physical_station_summaries
	current["active_craft"] = {}
	return _apply_current_summary(current)


## Parses the complete current envelope into detached models and commits only
## after every nested scheduler, station, and compatibility projection agrees.
func _apply_current_summary(summary: Dictionary) -> bool:
	for key in [
		"recipe_count", "active_craft", "station_summaries",
		"physical_station_summaries", "craft_jobs_v1",
	]:
		if not summary.has(key):
			return false
	if not _is_nonnegative_json_integer(summary.recipe_count) \
			or not summary.active_craft is Dictionary \
			or not summary.station_summaries is Dictionary \
			or not summary.physical_station_summaries is Dictionary \
			or not summary.craft_jobs_v1 is Dictionary:
		return false
	var next_scheduler = CraftJobSchedulerScript.new()
	next_scheduler.call("configure_recipe_authority", self)
	if not next_scheduler.apply_summary(summary.craft_jobs_v1):
		return false
	var next_stations: Dictionary = {}
	for kind_variant in (summary.station_summaries as Dictionary):
		if typeof(kind_variant) != TYPE_STRING:
			return false
		var kind: String = str(kind_variant)
		var station_variant: Variant = summary.station_summaries[kind_variant]
		if not station_variant is Dictionary:
			return false
		var station = StationStateScript.new()
		if not station.apply_strict_summary(station_variant) \
				or str(station.get("station_kind")) != kind \
				or not str(station.get("ship_id")).is_empty() \
				or not str(station.get("station_instance_id")).is_empty():
			return false
		next_stations[kind] = station
	var next_physical: Dictionary = {}
	for owner_variant in (summary.physical_station_summaries as Dictionary):
		if typeof(owner_variant) != TYPE_STRING:
			return false
		var station_variant: Variant = summary.physical_station_summaries[owner_variant]
		if not station_variant is Dictionary:
			return false
		var station = StationStateScript.new()
		if not station.apply_strict_summary(station_variant):
			return false
		var ship_id: String = str(station.get("ship_id"))
		var station_id: String = str(station.get("station_instance_id"))
		if ship_id.is_empty() or station_id.is_empty() \
				or str(owner_variant) != _owner_key(ship_id, station_id) \
				or not _station_projection_matches(station, next_scheduler):
			return false
		next_physical[str(owner_variant)] = station
	var scheduler_summary: Dictionary = next_scheduler.get_summary()
	for owner_row_variant in scheduler_summary.owners:
		var owner_row: Dictionary = owner_row_variant
		if not next_physical.has(_owner_key(
				str(owner_row.ship_id), str(owner_row.station_instance_id))):
			return false
	var next_active: Dictionary = (summary.active_craft as Dictionary).duplicate(true)
	if not _active_projection_matches(next_active, next_scheduler):
		return false
	if not next_active.is_empty() and not next_active.has("job_id"):
		var field_station: RefCounted = next_stations.get("field_crafting", null) as RefCounted
		if field_station == null \
				or str(field_station.get("active_recipe_id")) != str(next_active.recipe_id) \
				or not bool(field_station.call("is_crafting")) \
					and int(field_station.get("status")) != StationStateScript.Status.COMPLETE:
			return false
	_craft_job_scheduler = next_scheduler
	_station_states = next_stations
	_physical_station_states = next_physical
	_active_craft = next_active
	_job_contexts.clear()
	_completion_receipts.clear()
	_collect_completion_receipts(_craft_job_scheduler.call("get_ready_receipts"))
	return true


func _settle_job_output(job_id: String) -> Dictionary:
	var peeked: Dictionary = _craft_job_scheduler.call("peek_output", job_id)
	if not bool(peeked.get("ok", false)):
		return peeked
	var store: RefCounted = _pending_store_for_job(peeked)
	if store == null:
		# Only the synthetic default owner used by isolated pre-P07 model callers
		# may retain destructive claim compatibility. A physical or restored owner
		# without its ShipInstance store binding must keep output_ready intact.
		if _is_explicit_legacy_job(peeked):
			return _craft_job_scheduler.call("claim_output", job_id)
		return {"ok": false, "reason": "missing_pending_output_store"}
	var receipt_id: String = str(peeked.get("receipt_id", ""))
	var lots: Array = peeked.get("output_lots", []) as Array
	var metadata: Dictionary = {
		"station_instance_id": str(peeked.get("station_instance_id", "")),
		"producer_kind": "craft_job",
		"producer_id": job_id,
		"purpose": "output",
		"source_holder_id": "",
	}
	var deposited: bool = bool(store.call("deposit_once", receipt_id, lots, metadata))
	if not deposited and not bool(store.call("receipt_matches", receipt_id, lots, metadata)):
		return {"ok": false, "reason": "pending_receipt_conflict"}
	var acknowledged: Dictionary = _craft_job_scheduler.call(
		"acknowledge_output", job_id, receipt_id)
	if not bool(acknowledged.get("ok", false)):
		return acknowledged
	return peeked.merged({"ok": true, "reason": "", "pending": true}, true)


func _recover_job_refund(job_id: String, context: Dictionary) -> Dictionary:
	var peeked: Dictionary = _craft_job_scheduler.call(
		"peek_recoverable_refund", job_id, context)
	if not bool(peeked.get("ok", false)):
		return peeked
	var store: RefCounted = _pending_store_for_job(peeked)
	if store == null:
		return {"ok": false, "reason": "missing_pending_output_store"}
	var receipt_id: String = str(peeked.get("receipt_id", ""))
	var lots: Array = peeked.get("refund_lots", []) as Array
	var metadata: Dictionary = {
		"station_instance_id": str(peeked.get("station_instance_id", "")),
		"producer_kind": "craft_job",
		"producer_id": job_id,
		"purpose": "refund",
		"source_holder_id": str(peeked.get("source_holder_id", "")),
	}
	var deposited: bool = bool(store.call("deposit_once", receipt_id, lots, metadata))
	if not deposited and not bool(store.call("receipt_matches", receipt_id, lots, metadata)):
		return {"ok": false, "reason": "pending_receipt_conflict"}
	return _craft_job_scheduler.call(
		"acknowledge_refund_recovery", job_id, receipt_id, context)


func _pending_store_for_job(job_or_receipt: Dictionary) -> RefCounted:
	var owner_key: String = _owner_key(
		str(job_or_receipt.get("ship_id", "")),
		str(job_or_receipt.get("station_instance_id", "")))
	var context: Dictionary = _job_contexts.get(owner_key, {}) as Dictionary
	var store: Variant = context.get("pending_output_store", null)
	return store as RefCounted if store is RefCounted else null


static func _is_explicit_legacy_job(job_or_receipt: Dictionary) -> bool:
	return str(job_or_receipt.get("ship_id", "")) == "legacy-crafting" \
		and str(job_or_receipt.get("station_instance_id", "")).begins_with("legacy:")


static func _is_migration_station(ship_id: String, station_instance_id: String) -> bool:
	return not ship_id.is_empty() \
		and station_instance_id.begins_with("legacy:%s:" % ship_id)


func settle_station_pending(ship_id: String, station_instance_id: String) -> Dictionary:
	var settled_outputs: int = 0
	var settled_refunds: int = 0
	var scheduler_summary: Dictionary = _craft_job_scheduler.call("get_summary")
	for job_variant in scheduler_summary.get("jobs", []) as Array:
		var job: Dictionary = job_variant
		if str(job.get("ship_id", "")) != ship_id \
				or str(job.get("station_instance_id", "")) != station_instance_id:
			continue
		var phase: String = str(job.get("state", ""))
		if phase == "output_ready":
			var output_result: Dictionary = _settle_job_output(str(job.get("job_id", "")))
			if not bool(output_result.get("ok", false)):
				return output_result
			settled_outputs += 1
		elif phase in ["queued", "blocked"]:
			var context: Dictionary = _scheduler_context()
			context["ship_id"] = ship_id
			context["station_instance_id"] = station_instance_id
			var refund_result: Dictionary = _craft_job_scheduler.call(
				"cancel", str(job.get("job_id", "")), context)
			if not bool(refund_result.get("ok", false)) \
					and str(refund_result.get("reason", "")) == "refund_destination_full":
				refund_result = _recover_job_refund(str(job.get("job_id", "")), context)
			if not bool(refund_result.get("ok", false)):
				return refund_result
			settled_refunds += 1
		elif phase in ["running", "paused_power"]:
			# A started job has already consumed its escrow and cannot be moved to
			# another physical owner. Keep the station until the player completes
			# or explicitly cancels it; otherwise its eventual receipt is orphaned
			# behind a removed station ID.
			return {"ok": false, "reason": "station_busy"}
	return {
		"ok": true, "reason": "", "settled_outputs": settled_outputs,
		"settled_refunds": settled_refunds,
	}


func _apply_legacy_summary(summary: Dictionary) -> bool:
	var accepted: bool = false
	var changed: bool = false
	var ac: Variant = summary.get("active_craft", {})
	if ac is Dictionary:
		accepted = true
		var d: Dictionary = ac as Dictionary
		if d != _active_craft:
			_active_craft = d.duplicate()
			changed = true
	var ss: Variant = summary.get("station_summaries", {})
	if ss is Dictionary:
		accepted = true
		for sk in (ss as Dictionary):
			var station_summary: Variant = (ss as Dictionary)[sk]
			if station_summary is Dictionary:
				var station = get_or_create_station(str(sk))
				if station.apply_summary(station_summary as Dictionary):
					changed = true
	return changed or accepted


func _active_projection_matches(active: Dictionary, scheduler: RefCounted) -> bool:
	if active.is_empty():
		return true
	# Portable FieldCraftingState deliberately uses the direct station model. Its
	# projection is valid only with an empty paid scheduler and exact field shape.
	if not active.has("job_id"):
		for key in ["recipe_id", "station_kind", "quality_tier"]:
			if typeof(active.get(key, null)) != TYPE_STRING or str(active.get(key, "")).is_empty():
				return false
		for key in ["quality_multiplier", "quality_score"]:
			var value: Variant = active.get(key, null)
			if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) \
					or not is_finite(float(value)):
				return false
		var direct_score: float = float(active.quality_score)
		var direct_tier: String = str(active.quality_tier)
		if direct_score < 0.0 or direct_score > 1.0 \
				or not QualityTierResolverScript.TIER_ORDER.has(direct_tier) \
				or QualityTierResolverScript.tier_for_score(direct_score) != direct_tier \
				or absf(float(active.quality_multiplier) \
					- QualityTierResolverScript.new().multiplier_for_tier(direct_tier)) > 0.0001:
			return false
		var scheduler_summary: Dictionary = scheduler.call("get_summary")
		return str(active.station_kind) == "field_crafting" \
			and get_station_kind(str(active.recipe_id)) == "field_crafting" \
			and (scheduler_summary.jobs as Array).is_empty() \
			and (scheduler_summary.owners as Array).is_empty()
	for key in ["job_id", "ship_id", "station_instance_id", "recipe_id", "station_kind"]:
		if typeof(active.get(key, null)) != TYPE_STRING or str(active.get(key, "")).is_empty():
			return false
	var job: Dictionary = scheduler.call("get_job", str(active.job_id))
	return not job.is_empty() \
		and str(job.get("ship_id", "")) == str(active.ship_id) \
		and str(job.get("station_instance_id", "")) == str(active.station_instance_id) \
		and str(job.get("recipe_id", "")) == str(active.recipe_id) \
		and str(job.get("station_kind", "")) == str(active.station_kind) \
		and str(job.get("state", "")) not in ["collected", "cancelled"]


func _station_projection_matches(station: RefCounted, scheduler: RefCounted) -> bool:
	var job_id: String = str(station.get("active_job_id"))
	if job_id.is_empty():
		return int(station.get("status")) == StationStateScript.Status.IDLE \
			and str(station.get("active_recipe_id")).is_empty() \
			and float(station.get("progress_seconds")) == 0.0 \
			and float(station.get("required_seconds")) == 0.0
	var job: Dictionary = scheduler.call("get_job", job_id)
	if job.is_empty() \
			or str(job.get("ship_id", "")) != str(station.get("ship_id")) \
			or str(job.get("station_instance_id", "")) != str(station.get("station_instance_id")) \
			or str(job.get("station_kind", "")) != str(station.get("station_kind")) \
			or str(job.get("recipe_id", "")) != str(station.get("active_recipe_id")) \
			or absf(float(job.get("progress_seconds", -1.0)) - float(station.get("progress_seconds"))) > 0.0001 \
			or absf(float(job.get("required_seconds", -1.0)) - float(station.get("required_seconds"))) > 0.0001:
		return false
	var expected_status: int = StationStateScript.Status.IDLE
	match str(job.get("state", "")):
		"queued", "running": expected_status = StationStateScript.Status.CRAFTING
		"paused_power": expected_status = StationStateScript.Status.PAUSED_POWER
		"blocked": expected_status = StationStateScript.Status.PAUSED_NO_MATERIALS
		"output_ready", "collected": expected_status = StationStateScript.Status.COMPLETE
		_: return false
	return int(station.get("status")) == expected_status


## ShipRuntime provider: filtering by ship prevents two per-ship runtimes from
## advancing a shared scheduler's owners in the same world step.
func get_scheduler_context_for_ship(ship_id: String) -> Dictionary:
	var context: Dictionary = _scheduler_context()
	context["ship_id"] = ship_id
	return context


func _scheduler_context() -> Dictionary:
	var inventories: Dictionary = {}
	var stations: Dictionary = {}
	var station_contexts: Dictionary = {}
	for owner_key_variant in _job_contexts:
		var owner_key: String = str(owner_key_variant)
		var local: Dictionary = _job_contexts[owner_key]
		var inventory: Variant = local.get("source_inventory", null)
		if inventory is RefCounted:
			var holder_id: String = str(inventory.call("get_holder_namespace")) \
				if inventory.has_method("get_holder_namespace") else ""
			if not holder_id.is_empty():
				inventories[holder_id] = inventory
		var station: Variant = local.get("station_state", null)
		if station is RefCounted:
			_sync_legacy_station_alias(
				str(local.get("ship_id", "")),
				str(local.get("station_instance_id", "")),
				str((station as RefCounted).get("station_kind")),
				station as RefCounted)
			stations[owner_key] = station
		var progression: Variant = local.get("player_progression", null)
		if progression is RefCounted and progression.has_method("get_skill_level"):
			local["player_skill_level"] = int(progression.call("get_skill_level", "fabrication"))
		station_contexts[owner_key] = local
	return {
		"crafting_state": self,
		"source_inventories": inventories,
		"stations": stations,
		"station_contexts": station_contexts,
	}


func _collect_completion_receipts(receipts_variant: Variant) -> int:
	if not receipts_variant is Array:
		return 0
	var added: int = 0
	for receipt_variant in receipts_variant:
		if not receipt_variant is Dictionary:
			continue
		var receipt: Dictionary = receipt_variant
		var receipt_id: String = str(receipt.get("receipt_id", ""))
		var duplicate: bool = false
		for existing_variant in _completion_receipts:
			if existing_variant is Dictionary \
					and str((existing_variant as Dictionary).get("receipt_id", "")) == receipt_id:
				duplicate = true
				break
		if duplicate:
			continue
		_completion_receipts.append(receipt.duplicate(true))
		added += 1
	return added


func _remove_completion_receipt(job_id: String) -> void:
	for index in range(_completion_receipts.size() - 1, -1, -1):
		var receipt: Variant = _completion_receipts[index]
		if receipt is Dictionary and str((receipt as Dictionary).get("job_id", "")) == job_id:
			_completion_receipts.remove_at(index)


func _set_active_from_job(job_id: String) -> void:
	var job: Dictionary = _craft_job_scheduler.call("get_job", job_id)
	if job.is_empty():
		_active_craft.clear()
		return
	_active_craft = {
		"job_id": job_id,
		"ship_id": str(job.get("ship_id", "")),
		"station_instance_id": str(job.get("station_instance_id", "")),
		"recipe_id": str(job.get("recipe_id", "")),
		"station_kind": str(job.get("station_kind", "")),
	}


func _owner_key(ship_id: String, station_instance_id: String) -> String:
	return JSON.stringify([ship_id, station_instance_id], "", true)


static func _is_nonnegative_json_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 \
		and number <= MAX_SAFE_JSON_INTEGER and number == floor(number)

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Recipes: %d" % recipe_count())
	if is_crafting():
		lines.append("Crafting: %s @ %s" % [get_active_recipe_id(), get_active_station_kind()])
	for sk in _station_states:
		for line in _station_states[sk].get_status_lines():
			lines.append(line)
	return lines
