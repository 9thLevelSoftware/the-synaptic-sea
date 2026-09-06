extends RefCounted
class_name FieldCraftingState

const CraftingStateScript := preload("res://scripts/systems/crafting_state.gd")
const StationStateScript := preload("res://scripts/systems/station_state.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")
const MAX_SAFE_JSON_INTEGER: float = 9007199254740991.0
const PENDING_SCHEMA: String = "field-pending-2"

## Pure model for portable/field crafting. A subset of recipes with
## station_kind == "field_crafting" can be executed without a powered station.
## Uses the same recipe catalog as CraftingState but enforces the field-only
## restriction and skips quality bonuses from station level/power.
## Never touches the scene tree.

var _crafting_state = CraftingStateScript.new()
var _ship_id: String = ""
var _pending_output_store: WeakRef = null
var _receipt_sequence: int = 0
var _active_receipt_id: String = ""
var _bound_local_position: Vector3 = Vector3.ZERO
var _pinned_destination_ship_id: String = ""
var _pinned_local_position: Vector3 = Vector3.ZERO
var _legacy_restore_ship_id: String = ""
var _legacy_restore_source_holder_id: String = ""
## Terminal producer history binds every durable field receipt to the exact
## recipe/output that created it. It carries provenance only; the pending
## store or collected destination remains the value authority.
var _receipt_history_v1: Array = []

func _init() -> void:
	pass


func bind_pending_output_store(
		ship_id: String, store: RefCounted, local_position: Vector3 = Vector3.ZERO) -> bool:
	if ship_id.is_empty() or store == null or not store.has_method("deposit_once"):
		return false
	if not _pinned_destination_ship_id.is_empty() \
			and _pinned_destination_ship_id != ship_id:
		return false
	if not _is_finite_vector(local_position):
		return false
	if store.has_method("get_summary") \
			and str((store.call("get_summary") as Dictionary).get("ship_id", "")) != ship_id:
		return false
	_ship_id = ship_id
	_pending_output_store = weakref(store)
	_bound_local_position = local_position
	return true


func has_pending_output_store() -> bool:
	return _pending_store() != null


func configure_legacy_restore_owner(ship_id: String, source_holder_id: String) -> bool:
	if ship_id.is_empty() or source_holder_id.is_empty():
		return false
	_legacy_restore_ship_id = ship_id
	_legacy_restore_source_holder_id = source_holder_id
	return true


func bind_legacy_migration_jobs(
		inventory: RefCounted, knowledge = null, player_progression = null,
		pending_output_store = null) -> bool:
	return _crafting_state.bind_legacy_migration_jobs(
		inventory, knowledge, player_progression, pending_output_store)


func get_pinned_destination_ship_id() -> String:
	return _pinned_destination_ship_id


func get_pinned_local_position() -> Vector3:
	return _pinned_local_position


func pin_pending_destination(ship_id: String, local_position: Vector3) -> bool:
	if ship_id.is_empty() or ship_id != _ship_id or _pending_store() == null \
			or _active_receipt_id.is_empty() or _peek_completed_field_output().is_empty() \
			or not _is_finite_vector(local_position):
		return false
	if not _pinned_destination_ship_id.is_empty():
		return _pinned_destination_ship_id == ship_id \
			and _pinned_local_position.is_equal_approx(local_position)
	_pinned_destination_ship_id = ship_id
	_pinned_local_position = local_position
	return true

## Returns field-craftable recipes (station_kind == "field_crafting").
func get_field_recipes() -> Array:
	return _crafting_state.get_recipes_for_station("field_crafting")

## REQ-CS-016 field residual: listing for the portable recipe picker.
## Field crafting is intentionally skill-ungated for start (skill only affects
## quality), so entries use a high skill level for status and only report
## missing_ingredients / output_full as blockers.
func list_recipe_entries(inventory, knowledge = null, player_skill_level: int = 0) -> Array:
	return _crafting_state.list_recipe_entries(
		"field_crafting", inventory, 999, 0, knowledge, player_skill_level, false,
		_pending_store() != null)

func first_ready_recipe_id(inventory, knowledge = null) -> String:
	for entry in list_recipe_entries(inventory, knowledge):
		if entry is Dictionary and bool((entry as Dictionary).get("craftable", false)):
			return str((entry as Dictionary).get("recipe_id", ""))
	return ""

func can_craft(recipe_id: String, inventory, knowledge = null) -> bool:
	var recipe: Dictionary = _crafting_state.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if str(recipe.get("station_kind", "")) != "field_crafting":
		return false
	return _crafting_state.can_craft(recipe_id, inventory, knowledge)

## Begins a field craft. Quality is resolved with station_level=0 and powered=false.
func begin_craft(recipe_id: String, inventory, material_state, player_skill_level: int, knowledge = null) -> bool:
	var recipe: Dictionary = _crafting_state.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	if str(recipe.get("station_kind", "")) != "field_crafting":
		return false
	if not can_craft(recipe_id, inventory, knowledge):
		return false
	# Use the base CraftingState logic but force a synthetic field station
	var station = StationStateScript.new()
	# Field crafting is intentionally unpowered for quality resolution, but the
	# portable craft itself must still progress without entering the station's
	# PAUSED_POWER state.
	station.configure({"station_kind": "field_crafting", "level": 0, "powered": true})
	_crafting_state._station_states["field_crafting"] = station
	_crafting_state.consume_ingredients(recipe_id, inventory)
	var avg_quality: float = 0.5
	var ingredients: Variant = recipe.get("ingredients", {})
	if ingredients is Dictionary:
		avg_quality = material_state.average_ingredient_quality(ingredients as Dictionary)
	var resolver = QualityTierResolverScript.new()
	var quality_result: Dictionary = resolver.resolve(avg_quality, player_skill_level, 0, false)
	_crafting_state._active_craft = {
		"recipe_id": recipe_id,
		"station_kind": "field_crafting",
		"quality_tier": quality_result["tier"],
		"quality_multiplier": quality_result["multiplier"],
		"quality_score": quality_result["score"],
	}
	var craft_time: float = float(recipe.get("craft_time_seconds", 0.0))
	station.start_recipe(recipe_id, craft_time)
	if _pending_store() != null and not _ship_id.is_empty():
		_receipt_sequence += 1
		# The paid portable job may cross ships before completion. Its receipt ID is
		# player-run stable; the physical destination ship is pinned separately at
		# first publication.
		_active_receipt_id = "field_crafting/job-%06d/output" % _receipt_sequence
		_pinned_destination_ship_id = ""
		_pinned_local_position = Vector3.ZERO
	else:
		# Retain direct behavior only for the explicit legacy model configuration.
		_active_receipt_id = ""
	return true

func tick(delta_seconds: float) -> bool:
	return _crafting_state.tick(delta_seconds)

func finish_craft() -> Dictionary:
	var store: RefCounted = _pending_store()
	if store == null:
		# Restored/current physical state retains its COMPLETE producer until the
		# owning ShipInstance store is rebound. Only metadata-free legacy field
		# state may use the old destructive direct finish.
		if not _ship_id.is_empty() or not _active_receipt_id.is_empty():
			return {}
		return _crafting_state.finish_craft()
	if _ship_id.is_empty() or _active_receipt_id.is_empty() \
			or _pinned_destination_ship_id.is_empty() \
			or _pinned_destination_ship_id != _ship_id:
		return {}
	var preview: Dictionary = _peek_completed_field_output()
	if preview.is_empty():
		return {}
	var lot: Dictionary = {
		"lot_id": "%s/output-1" % _active_receipt_id,
		"item_id": str(preview.get("item_id", "")),
		"quantity": int(preview.get("quantity", 0)),
		"quality_score": float(preview.get("quality_score", 0.5)),
		"quality_tier": str(preview.get("quality_tier", "standard")),
		"condition": 1.0,
		"origin": {"field_receipt_id": _active_receipt_id},
	}
	var metadata: Dictionary = {
		"station_instance_id": "field_crafting",
		"producer_kind": "field_craft",
		"producer_id": _active_receipt_id.trim_suffix("/output"),
		"purpose": "output",
		"source_holder_id": "",
	}
	var store_before: Dictionary = store.call("get_summary")
	var deposited: bool = bool(store.call(
		"deposit_once", _active_receipt_id, [lot], metadata))
	if not deposited and not bool(store.call(
		"receipt_matches", _active_receipt_id, [lot], metadata)):
		return {}
	# The durable receipt now owns the value. Only after that succeeds may the
	# direct field producer clear its COMPLETE state. If that commit fails after
	# a new publication, restore the exact prior store; a replay-matched receipt
	# remains authoritative and the producer stays available to acknowledge it.
	var result: Dictionary = _crafting_state.finish_craft()
	if result.is_empty():
		if deposited:
			store.call("apply_summary", store_before)
		return {}
	result["receipt_id"] = _active_receipt_id
	result["output_lot"] = lot
	result["pending"] = true
	result["destination_ship_id"] = _pinned_destination_ship_id
	result["destination_local_position"] = _pinned_local_position
	_receipt_history_v1.append({
		"receipt_id": _active_receipt_id,
		"destination_ship_id": _pinned_destination_ship_id,
		"recipe_id": str(preview.get("recipe_id", "")),
		"original_lots": [lot.duplicate(true)],
	})
	_active_receipt_id = ""
	_pinned_destination_ship_id = ""
	_pinned_local_position = Vector3.ZERO
	return result


func _peek_completed_field_output() -> Dictionary:
	var summary: Dictionary = _crafting_state.get_summary()
	var active: Dictionary = summary.get("active_craft", {}) as Dictionary
	if active.is_empty() or not str(active.get("job_id", "")).is_empty() \
			or str(active.get("station_kind", "")) != "field_crafting":
		return {}
	var station_summaries: Dictionary = summary.get("station_summaries", {}) as Dictionary
	var station: Dictionary = station_summaries.get("field_crafting", {}) as Dictionary
	if int(station.get("status", -1)) != 3:
		return {}
	var recipe_id: String = str(active.get("recipe_id", ""))
	var produces: Dictionary = _crafting_state.get_produces(recipe_id)
	var item_id: String = str(produces.get("item_id", ""))
	var quantity: int = int(produces.get("quantity", 0))
	if item_id.is_empty() or quantity <= 0:
		return {}
	return {
		"recipe_id": recipe_id,
		"item_id": item_id,
		"quantity": quantity,
		"quality_score": float(active.get("quality_score", 0.5)),
		"quality_tier": str(active.get("quality_tier", "standard")),
	}

func is_crafting() -> bool:
	return _crafting_state.is_crafting()

func get_active_recipe_id() -> String:
	return _crafting_state.get_active_recipe_id()

func cancel_craft() -> void:
	_crafting_state.cancel_craft()
	_active_receipt_id = ""
	_pinned_destination_ship_id = ""
	_pinned_local_position = Vector3.ZERO

func get_summary() -> Dictionary:
	var inner: Dictionary = _crafting_state.get_summary()
	inner["field_pending_v1"] = {
		"schema": PENDING_SCHEMA,
		"ship_id": _ship_id,
		"receipt_sequence": _receipt_sequence,
		"active_receipt_id": _active_receipt_id,
		"pinned_destination_ship_id": _pinned_destination_ship_id,
		"pinned_local_position": _vector_summary(_pinned_local_position) \
			if not _pinned_destination_ship_id.is_empty() else [],
		"receipt_history_v1": _receipt_history_v1.duplicate(true),
	}
	return {
		"field_crafting": inner,
	}

func apply_summary(summary: Dictionary) -> bool:
	if summary == null or summary.is_empty():
		return false
	var fc: Variant = summary.get("field_crafting", {})
	if fc is Dictionary:
		var pending_v: Variant = (fc as Dictionary).get("field_pending_v1", {})
		if not pending_v is Dictionary:
			return false
		var pending: Dictionary = pending_v
		var next_ship_id: String = ""
		var next_receipt_sequence: int = 0
		var next_active_receipt_id: String = ""
		var next_pinned_ship_id: String = ""
		var next_pinned_position: Vector3 = Vector3.ZERO
		var next_history: Array = []
		var pending_keys: Array = pending.keys()
		pending_keys.sort()
		if pending_keys != [
				"active_receipt_id", "pinned_destination_ship_id",
				"pinned_local_position", "receipt_history_v1", "receipt_sequence",
				"schema", "ship_id"]:
			return false
		if not pending.is_empty():
			if typeof(pending.get("schema", null)) != TYPE_STRING \
					or str(pending.get("schema", "")) != PENDING_SCHEMA \
					or typeof(pending.get("ship_id", null)) != TYPE_STRING \
					or not _is_nonnegative_json_integer(
						pending.get("receipt_sequence", null)) \
					or typeof(pending.get("active_receipt_id", null)) != TYPE_STRING \
					or typeof(pending.get("pinned_destination_ship_id", null)) != TYPE_STRING \
					or not pending.get("pinned_local_position", null) is Array:
				return false
			next_ship_id = str(pending.ship_id)
			next_receipt_sequence = int(pending.receipt_sequence)
			next_active_receipt_id = str(pending.active_receipt_id)
			next_pinned_ship_id = str(pending.pinned_destination_ship_id)
			var pinned_position_values: Array = pending.pinned_local_position as Array
			if next_pinned_ship_id.is_empty():
				if not pinned_position_values.is_empty():
					return false
			elif next_active_receipt_id.is_empty() or next_ship_id != next_pinned_ship_id \
					or pinned_position_values.size() != 3 \
					or not _summary_vector_is_finite(pinned_position_values):
				return false
			if not next_pinned_ship_id.is_empty():
				next_pinned_position = Vector3(
					float(pinned_position_values[0]), float(pinned_position_values[1]),
					float(pinned_position_values[2]))
		var candidate = CraftingStateScript.new()
		if (fc as Dictionary).has("legacy_craft_migration_v1") \
				and not candidate.configure_legacy_restore_owner(
					_legacy_restore_ship_id, _legacy_restore_source_holder_id):
			return false
		if not candidate.apply_summary(fc as Dictionary):
			return false
		var history_v: Variant = pending.get("receipt_history_v1", null)
		if not history_v is Array:
			return false
		var history_ids: Dictionary = {}
		for history_entry_v in history_v as Array:
			if not history_entry_v is Dictionary:
				return false
			var history_entry: Dictionary = history_entry_v
			if not _valid_receipt_history_entry(
					history_entry, next_receipt_sequence, candidate, history_ids):
				return false
			next_history.append(history_entry.duplicate(true))
		if not next_active_receipt_id.is_empty():
			var active_sequence: int = _receipt_id_sequence(next_active_receipt_id)
			if active_sequence <= 0 or active_sequence > next_receipt_sequence \
					or history_ids.has(next_active_receipt_id):
				return false
		_crafting_state = candidate
		_ship_id = next_ship_id
		_receipt_sequence = next_receipt_sequence
		_active_receipt_id = next_active_receipt_id
		_pinned_destination_ship_id = next_pinned_ship_id
		_pinned_local_position = next_pinned_position
		_receipt_history_v1 = next_history
		return true
	return false


func get_receipt_history_v1() -> Array:
	return _receipt_history_v1.duplicate(true)


static func _valid_receipt_history_entry(
		entry: Dictionary,
		receipt_sequence: int,
		crafting: RefCounted,
		seen_ids: Dictionary) -> bool:
	var keys: Array = entry.keys()
	keys.sort()
	if keys != ["destination_ship_id", "original_lots", "receipt_id", "recipe_id"]:
		return false
	for key in ["receipt_id", "destination_ship_id", "recipe_id"]:
		if typeof(entry.get(key, null)) != TYPE_STRING or str(entry.get(key, "")).is_empty():
			return false
	var receipt_id: String = str(entry.receipt_id)
	var sequence: int = _receipt_id_sequence(receipt_id)
	if sequence <= 0 or sequence > receipt_sequence or seen_ids.has(receipt_id):
		return false
	var lots_v: Variant = entry.get("original_lots", null)
	if not lots_v is Array or (lots_v as Array).size() != 1:
		return false
	var lot_v: Variant = (lots_v as Array)[0]
	if not lot_v is Dictionary:
		return false
	var lot: Dictionary = lot_v
	var lot_keys: Array = lot.keys()
	lot_keys.sort()
	if lot_keys != [
			"condition", "item_id", "lot_id", "origin", "quality_score",
			"quality_tier", "quantity"]:
		return false
	for string_key in ["lot_id", "item_id", "quality_tier"]:
		if typeof(lot.get(string_key, null)) != TYPE_STRING \
				or str(lot.get(string_key, "")).is_empty():
			return false
	var recipe_id: String = str(entry.recipe_id)
	var produces: Dictionary = crafting.call("get_produces", recipe_id)
	var origin_v: Variant = lot.get("origin", null)
	if produces.is_empty() or not origin_v is Dictionary \
			or (origin_v as Dictionary) != {"field_receipt_id": receipt_id} \
			or str(lot.get("lot_id", "")) != "%s/output-1" % receipt_id \
			or str(lot.get("item_id", "")) != str(produces.get("item_id", "")) \
			or not _is_positive_json_integer(lot.get("quantity", null)) \
			or int(lot.quantity) != int(produces.get("quantity", 0)):
		return false
	var score_v: Variant = lot.get("quality_score", null)
	var condition_v: Variant = lot.get("condition", null)
	if typeof(score_v) not in [TYPE_INT, TYPE_FLOAT] \
			or typeof(condition_v) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var score: float = float(score_v)
	var condition: float = float(condition_v)
	if not is_finite(score) or score < 0.0 or score > 1.0 \
			or not is_finite(condition) or condition < 0.0 or condition > 1.0 \
			or not is_equal_approx(condition, 1.0) \
			or str(lot.get("quality_tier", "")) != QualityTierResolverScript.tier_for_score(score):
		return false
	seen_ids[receipt_id] = true
	return true


static func _receipt_id_sequence(receipt_id: String) -> int:
	var prefix: String = "field_crafting/job-"
	var suffix: String = "/output"
	if not receipt_id.begins_with(prefix) or not receipt_id.ends_with(suffix):
		return -1
	var digits: String = receipt_id.substr(
		prefix.length(), receipt_id.length() - prefix.length() - suffix.length())
	if digits.length() != 6 or not digits.is_valid_int():
		return -1
	return int(digits)


func _pending_store() -> RefCounted:
	if _pending_output_store == null:
		return null
	var store: Variant = _pending_output_store.get_ref()
	return store as RefCounted if store is RefCounted else null


static func _vector_summary(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _summary_vector_is_finite(values: Array) -> bool:
	for value in values:
		if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) \
				or not is_finite(float(value)):
			return false
	return true


static func _is_nonnegative_json_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= 0.0 \
		and number <= MAX_SAFE_JSON_INTEGER and number == floor(number)


static func _is_positive_json_integer(value: Variant) -> bool:
	return _is_nonnegative_json_integer(value) and int(value) > 0


static func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func get_status_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("Field Crafting")
	for line in _crafting_state.get_status_lines():
		lines.append(line)
	return lines
