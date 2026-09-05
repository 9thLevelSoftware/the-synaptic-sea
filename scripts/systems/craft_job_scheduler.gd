extends RefCounted
class_name CraftJobScheduler

## Paid per-ship/per-station fabrication authority (ADR-0059, FC-07..08).

const CraftJobStateScript := preload("res://scripts/systems/craft_job_state.gd")
const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

const SCHEMA: String = "craft-jobs-1"
const MAX_QUEUED_PER_STATION: int = 8

var _jobs: Dictionary = {} # job_id -> CraftJobState
var _owner_queues: Dictionary = {} # canonical owner key -> Array[job_id]
var _owner_sequences: Dictionary = {} # canonical owner key -> int
var _owner_descriptors: Dictionary = {} # canonical owner key -> {ship_id, station_instance_id}
var _recipe_authority_ref: WeakRef = null # CraftingState, injected; never serialized


func configure_recipe_authority(authority: RefCounted) -> bool:
	if authority == null or not authority.has_method("get_recipe") \
			or not authority.has_method("get_produces"):
		return false
	var existing: RefCounted = _get_recipe_authority()
	if existing != null and existing != authority:
		return false
	_recipe_authority_ref = weakref(authority)
	return true


func _get_recipe_authority() -> RefCounted:
	if _recipe_authority_ref == null:
		return null
	var authority: Variant = _recipe_authority_ref.get_ref()
	return authority as RefCounted if authority is RefCounted else null


func evaluate(request: Dictionary, context: Dictionary) -> Dictionary:
	var resolved: Dictionary = _resolve_request(request, context)
	if not bool(resolved.get("ok", false)):
		return resolved
	var owner_key: String = _owner_key(str(resolved.ship_id), str(resolved.station_instance_id))
	var queue: Array = _owner_queues.get(owner_key, [])
	if queue.size() >= MAX_QUEUED_PER_STATION:
		return _denied("queue_full")
	return {
		"ok": true,
		"reason": "",
		"ship_id": resolved.ship_id,
		"station_instance_id": resolved.station_instance_id,
		"station_kind": resolved.station_kind,
		"recipe_id": resolved.recipe_id,
		"source_holder_id": resolved.source_holder_id,
		"required_seconds": resolved.required_seconds,
	}


func enqueue(request: Dictionary, context: Dictionary) -> Dictionary:
	var eligibility: Dictionary = evaluate(request, context)
	if not bool(eligibility.get("ok", false)):
		return eligibility
	var inventory: RefCounted = _source_inventory(str(eligibility.source_holder_id), context)
	if inventory == null:
		return _denied("missing_source_holder")
	var crafting: RefCounted = context.get("crafting_state", null) as RefCounted
	var recipe: Dictionary = crafting.call("get_recipe", str(eligibility.recipe_id))
	var ingredients: Dictionary = recipe.get("ingredients", {}) as Dictionary
	var selected: Dictionary = request.get("selected_lot_ids", {}) as Dictionary \
		if request.get("selected_lot_ids", {}) is Dictionary else {}
	var escrow: Array = []
	var ingredient_ids: Array = ingredients.keys()
	ingredient_ids.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for item_variant in ingredient_ids:
		var item_id: String = str(item_variant)
		var preferred: PackedStringArray = _selected_ids(selected.get(item_id, []))
		var taken: Array = inventory.call("take_lots", item_id, int(ingredients[item_variant]), preferred)
		if taken.is_empty():
			_restore_lots(inventory, escrow)
			return _denied("missing_materials")
		for lot in taken:
			escrow.append((lot as Dictionary).duplicate(true))

	var ship_id: String = str(eligibility.ship_id)
	var station_id: String = str(eligibility.station_instance_id)
	var owner_key: String = _owner_key(ship_id, station_id)
	var sequence: int = int(_owner_sequences.get(owner_key, 0)) + 1
	var job_id: String = "%s/%s/job-%06d" % [ship_id, station_id, sequence]
	var job = CraftJobStateScript.new()
	var initial: Dictionary = {
		"job_id": job_id,
		"ship_id": ship_id,
		"station_instance_id": station_id,
		"station_kind": str(eligibility.station_kind),
		"recipe_id": str(eligibility.recipe_id),
		"state": CraftJobStateScript.PHASE_QUEUED,
		"phase": CraftJobStateScript.PHASE_QUEUED,
		"source_holder_id": str(eligibility.source_holder_id),
		"escrow_holder_id": "%s/%s/escrow" % [ship_id, station_id],
		"ingredient_escrow": escrow,
		"consumed_lots": [],
		"progress": 0.0,
		"progress_seconds": 0.0,
		"required_seconds": float(eligibility.required_seconds),
		"output_lots": [],
		"output_receipt_id": "",
		"sequence": sequence,
		"blocked_reason": "",
		"input_quality_score": -1.0,
		"input_skill_level": -1,
		"station_effective_tier": -1,
		"station_powered_at_start": false,
		"receipt_emitted": false,
	}
	if not job.apply_summary(initial):
		_restore_lots(inventory, escrow)
		return _denied("invalid_job_state")
	_owner_sequences[owner_key] = sequence
	_owner_descriptors[owner_key] = {"ship_id": ship_id, "station_instance_id": station_id}
	var queue: Array = _owner_queues.get(owner_key, [])
	queue.append(job_id)
	_owner_queues[owner_key] = queue
	_jobs[job_id] = job
	return {"ok": true, "reason": "", "job_id": job_id, "state": job.phase}


## Advances every station independently. Large catch-up deltas are spent serially
## within each station and never shared across stations.
func advance(delta: float, context: Dictionary) -> Array:
	if delta < 0.0:
		return []
	var receipts: Array = []
	var owner_keys: Array = _owner_queues.keys()
	owner_keys.sort()
	for owner_variant in owner_keys:
		var owner_key: String = str(owner_variant)
		var owner_descriptor: Dictionary = _owner_descriptors.get(owner_key, {})
		var ship_filter: String = str(context.get("ship_id", ""))
		if not ship_filter.is_empty() and str(owner_descriptor.get("ship_id", "")) != ship_filter:
			continue
		var queue: Array = _owner_queues.get(owner_key, [])
		var remaining: float = delta
		while not queue.is_empty():
			var job_id: String = str(queue[0])
			var job: RefCounted = _jobs.get(job_id, null) as RefCounted
			if job == null:
				queue.pop_front()
				continue
			var local_context: Dictionary = _context_for_station(
				str(job.get("ship_id")), str(job.get("station_instance_id")), context)
			var station: RefCounted = _station_state(str(job.get("station_instance_id")), local_context)
			var owner_check: Dictionary = _validate_owner_context(
				str(job.get("ship_id")), str(job.get("station_instance_id")), station, local_context)
			if not bool(owner_check.get("ok", false)):
				break
			if job.call("is_unstarted"):
				var start_result: Dictionary = _try_start(job, station, local_context)
				if not bool(start_result.get("ok", false)):
					_sync_station_projection(station, job)
					break
			if str(job.get("phase")) == CraftJobStateScript.PHASE_PAUSED_POWER:
				if station == null or not bool(station.get("powered")):
					_sync_station_projection(station, job)
					break
				job.set("phase", CraftJobStateScript.PHASE_RUNNING)
			if str(job.get("phase")) != CraftJobStateScript.PHASE_RUNNING:
				break
			if station == null or not bool(station.get("powered")):
				job.set("phase", CraftJobStateScript.PHASE_PAUSED_POWER)
				_sync_station_projection(station, job)
				break
			if remaining <= 0.0:
				_sync_station_projection(station, job)
				break
			var needed: float = maxf(0.0, float(job.get("required_seconds")) - float(job.get("progress_seconds")))
			var step: float = minf(remaining, needed)
			job.set("progress_seconds", float(job.get("progress_seconds")) + step)
			remaining -= step
			if float(job.get("progress_seconds")) + 0.0001 < float(job.get("required_seconds")):
				_sync_station_projection(station, job)
				break
			job.set("progress_seconds", float(job.get("required_seconds")))
			job.set("phase", CraftJobStateScript.PHASE_OUTPUT_READY)
			job.set("output_receipt_id", "%s/output" % job_id)
			queue.pop_front()
			if not bool(job.get("receipt_emitted")):
				job.set("receipt_emitted", true)
				receipts.append(_completion_receipt(job))
			_sync_station_projection(station, null)
			if remaining <= 0.0:
				break
		_owner_queues[owner_key] = queue
	return receipts


func cancel(job_id: String, context: Dictionary) -> Dictionary:
	var job: RefCounted = _jobs.get(job_id, null) as RefCounted
	if job == null:
		return _denied("unknown_job")
	var job_ship_id: String = str(job.get("ship_id"))
	var job_station_id: String = str(job.get("station_instance_id"))
	var ship_filter: String = str(context.get("ship_id", ""))
	if not ship_filter.is_empty() and ship_filter != job_ship_id:
		return _denied("wrong_ship")
	var owner_context: Dictionary = _context_for_station(job_ship_id, job_station_id, context)
	var owner_station: RefCounted = _station_state(job_station_id, owner_context)
	var owner_check: Dictionary = _validate_owner_context(
		job_ship_id, job_station_id, owner_station, owner_context)
	if not bool(owner_check.get("ok", false)):
		return owner_check
	var phase: String = str(job.get("phase"))
	if phase == CraftJobStateScript.PHASE_CANCELLED:
		return _denied("already_cancelled")
	if phase == CraftJobStateScript.PHASE_OUTPUT_READY or phase == CraftJobStateScript.PHASE_COLLECTED:
		return _denied("already_completed")
	if bool(job.call("is_unstarted")):
		var inventory: RefCounted = _source_inventory(str(job.get("source_holder_id")), context)
		if inventory == null:
			return _denied("missing_source_holder")
		if inventory.has_method("get_holder_namespace") \
				and str(inventory.call("get_holder_namespace")) != str(job.get("source_holder_id")):
			return _denied("source_holder_mismatch")
		var escrow: Array = job.get("ingredient_escrow") as Array
		if not _can_restore_all(inventory, escrow):
			return {
				"ok": false,
				"reason": "refund_destination_full",
				"recoverable_refund": escrow.duplicate(true),
			}
		if not _restore_lots(inventory, escrow):
			return _denied("refund_failed")
		job.set("ingredient_escrow", [])
		job.set("blocked_reason", "")
		job.set("phase", CraftJobStateScript.PHASE_CANCELLED)
		_remove_from_owner_queue(job)
		_sync_station_projection(owner_station, null)
		return {"ok": true, "reason": "", "result": "refunded", "refunded_lots": escrow.duplicate(true)}
	job.set("phase", CraftJobStateScript.PHASE_CANCELLED)
	job.set("blocked_reason", "")
	job.set("output_lots", [])
	_remove_from_owner_queue(job)
	_sync_station_projection(owner_station, null)
	return {"ok": true, "reason": "", "result": "cancelled", "warning": "inputs_forfeited"}


func claim_output(job_id: String) -> Dictionary:
	var job: RefCounted = _jobs.get(job_id, null) as RefCounted
	if job == null:
		return _denied("unknown_job")
	if str(job.get("phase")) == CraftJobStateScript.PHASE_COLLECTED:
		return {"ok": false, "reason": "already_collected", "receipt_id": str(job.get("output_receipt_id"))}
	if str(job.get("phase")) != CraftJobStateScript.PHASE_OUTPUT_READY:
		return _denied("output_not_ready")
	job.set("phase", CraftJobStateScript.PHASE_COLLECTED)
	return _completion_receipt(job).merged({"ok": true, "reason": ""}, true)


func get_job(job_id: String) -> Dictionary:
	var job: RefCounted = _jobs.get(job_id, null) as RefCounted
	return job.call("get_summary") if job != null else {}


func get_active_job_id(ship_id: String, station_instance_id: String) -> String:
	var queue: Array = _owner_queues.get(_owner_key(ship_id, station_instance_id), [])
	return str(queue[0]) if not queue.is_empty() else ""


func get_ready_receipts() -> Array:
	var receipts: Array = []
	var job_ids: Array = _jobs.keys()
	job_ids.sort()
	for job_id in job_ids:
		var job: RefCounted = _jobs[job_id]
		if str(job.get("phase")) == CraftJobStateScript.PHASE_OUTPUT_READY:
			receipts.append(_completion_receipt(job))
	return receipts


func get_summary() -> Dictionary:
	var jobs: Array = []
	var job_ids: Array = _jobs.keys()
	job_ids.sort()
	for job_id in job_ids:
		jobs.append((_jobs[job_id] as RefCounted).call("get_summary"))
	var owners: Array = []
	var owner_keys: Array = _owner_descriptors.keys()
	owner_keys.sort()
	for owner_key in owner_keys:
		var descriptor: Dictionary = _owner_descriptors[owner_key]
		owners.append({
			"ship_id": str(descriptor.ship_id),
			"station_instance_id": str(descriptor.station_instance_id),
			"sequence": int(_owner_sequences.get(owner_key, 0)),
			"job_ids": (_owner_queues.get(owner_key, []) as Array).duplicate(),
		})
	return {"schema": SCHEMA, "jobs": jobs, "owners": owners}


func get_summary_for_ship(ship_id: String) -> Dictionary:
	var all: Dictionary = get_summary()
	var jobs: Array = []
	for job_variant in all.jobs:
		if job_variant is Dictionary and str((job_variant as Dictionary).get("ship_id", "")) == ship_id:
			jobs.append((job_variant as Dictionary).duplicate(true))
	var owners: Array = []
	for owner_variant in all.owners:
		if owner_variant is Dictionary and str((owner_variant as Dictionary).get("ship_id", "")) == ship_id:
			owners.append((owner_variant as Dictionary).duplicate(true))
	return {"schema": SCHEMA, "jobs": jobs, "owners": owners}


## Strictly replaces one ship slice while preserving all other ship owners/jobs.
func merge_summary_for_ship(ship_id: String, summary: Dictionary) -> bool:
	if ship_id.is_empty():
		return false
	var slice_candidate = get_script().new()
	var recipe_authority: RefCounted = _get_recipe_authority()
	if recipe_authority != null:
		slice_candidate.configure_recipe_authority(recipe_authority)
	if not slice_candidate.apply_summary(summary):
		return false
	var slice: Dictionary = slice_candidate.get_summary()
	for job_variant in slice.jobs:
		if str((job_variant as Dictionary).get("ship_id", "")) != ship_id:
			return false
	for owner_variant in slice.owners:
		if str((owner_variant as Dictionary).get("ship_id", "")) != ship_id:
			return false
	var combined: Dictionary = {"schema": SCHEMA, "jobs": [], "owners": []}
	for job_variant in get_summary().jobs:
		if str((job_variant as Dictionary).get("ship_id", "")) != ship_id:
			combined.jobs.append((job_variant as Dictionary).duplicate(true))
	for owner_variant in get_summary().owners:
		if str((owner_variant as Dictionary).get("ship_id", "")) != ship_id:
			combined.owners.append((owner_variant as Dictionary).duplicate(true))
	combined.jobs.append_array(slice.jobs)
	combined.owners.append_array(slice.owners)
	var combined_candidate = get_script().new()
	if recipe_authority != null:
		combined_candidate.configure_recipe_authority(recipe_authority)
	if not combined_candidate.apply_summary(combined):
		return false
	_jobs = combined_candidate._jobs
	_owner_queues = combined_candidate._owner_queues
	_owner_sequences = combined_candidate._owner_sequences
	_owner_descriptors = combined_candidate._owner_descriptors
	return true


## Strict and atomic current-summary restore.
func apply_summary(summary: Dictionary) -> bool:
	var payload: Variant = summary.get("craft_jobs_v1", summary)
	if not payload is Dictionary:
		return false
	var data: Dictionary = payload
	if typeof(data.get("schema", null)) != TYPE_STRING or str(data.get("schema", "")) != SCHEMA \
			or not data.get("jobs", null) is Array \
			or not data.get("owners", null) is Array:
		return false
	var next_jobs: Dictionary = {}
	for raw_job in data.jobs:
		if not raw_job is Dictionary:
			return false
		var job = CraftJobStateScript.new()
		if not job.apply_summary(raw_job):
			return false
		if _get_recipe_authority() == null or not _job_matches_recipe_authority(job):
			return false
		var job_id: String = str(job.get("job_id"))
		if next_jobs.has(job_id):
			return false
		next_jobs[job_id] = job
	var next_queues: Dictionary = {}
	var next_sequences: Dictionary = {}
	var next_descriptors: Dictionary = {}
	var queued_seen: Dictionary = {}
	for raw_owner in data.owners:
		if not raw_owner is Dictionary:
			return false
		var owner: Dictionary = raw_owner
		if typeof(owner.get("ship_id", null)) != TYPE_STRING \
				or typeof(owner.get("station_instance_id", null)) != TYPE_STRING:
			return false
		var ship_id: String = str(owner.get("ship_id", ""))
		var station_id: String = str(owner.get("station_instance_id", ""))
		var sequence: int = _strict_nonnegative_int(owner.get("sequence", null))
		var ids_v: Variant = owner.get("job_ids", null)
		if ship_id.is_empty() or station_id.is_empty() or sequence < 0 or not ids_v is Array:
			return false
		var ids: Array = ids_v
		if ids.size() > MAX_QUEUED_PER_STATION:
			return false
		var owner_key: String = _owner_key(ship_id, station_id)
		if next_descriptors.has(owner_key):
			return false
		var previous_sequence: int = 0
		for job_id_variant in ids:
			if typeof(job_id_variant) != TYPE_STRING:
				return false
			var job_id: String = str(job_id_variant)
			var job: RefCounted = next_jobs.get(job_id, null) as RefCounted
			if job == null or queued_seen.has(job_id) \
					or str(job.get("ship_id")) != ship_id \
					or str(job.get("station_instance_id")) != station_id \
					or bool(job.call("is_terminal")) \
					or int(job.get("sequence")) <= previous_sequence:
				return false
			previous_sequence = int(job.get("sequence"))
			queued_seen[job_id] = true
		if not _sequence_covers_jobs(sequence, ship_id, station_id, next_jobs):
			return false
		next_queues[owner_key] = ids.duplicate()
		next_sequences[owner_key] = sequence
		next_descriptors[owner_key] = {"ship_id": ship_id, "station_instance_id": station_id}
	for job_id in next_jobs:
		var job: RefCounted = next_jobs[job_id]
		var job_owner_key: String = _owner_key(
			str(job.get("ship_id")), str(job.get("station_instance_id")))
		if not next_descriptors.has(job_owner_key) \
				or (not bool(job.call("is_terminal")) and not queued_seen.has(job_id)):
			return false
	_jobs = next_jobs
	_owner_queues = next_queues
	_owner_sequences = next_sequences
	_owner_descriptors = next_descriptors
	return true


func _resolve_request(request: Dictionary, context: Dictionary) -> Dictionary:
	for key in ["ship_id", "station_instance_id", "station_kind", "recipe_id", "source_holder_id"]:
		if typeof(request.get(key, null)) != TYPE_STRING or str(request.get(key, "")).is_empty():
			return _denied("invalid_request")
	var ship_filter: String = str(context.get("ship_id", ""))
	if context.has("ship_id") and typeof(context.get("ship_id")) != TYPE_STRING:
		return _denied("invalid_context")
	if not ship_filter.is_empty() and ship_filter != str(request.ship_id):
		return _denied("wrong_ship")
	var crafting: RefCounted = context.get("crafting_state", null) as RefCounted
	if crafting == null or not crafting.has_method("get_recipe"):
		return _denied("missing_crafting_state")
	if not configure_recipe_authority(crafting):
		return _denied("recipe_authority_mismatch")
	var recipe_id: String = str(request.recipe_id)
	var recipe: Dictionary = crafting.call("get_recipe", recipe_id)
	if recipe.is_empty():
		return _denied("unknown_recipe")
	var station_kind: String = str(request.station_kind)
	if str(recipe.get("station_kind", "")) != station_kind:
		return _denied("wrong_station")
	var local_context: Dictionary = _context_for_station(
		str(request.ship_id), str(request.station_instance_id), context)
	var station: RefCounted = _station_state(str(request.station_instance_id), local_context)
	if station == null:
		return _denied("missing_station")
	var owner_check: Dictionary = _validate_owner_context(
		str(request.ship_id), str(request.station_instance_id), station, local_context)
	if not bool(owner_check.get("ok", false)):
		return owner_check
	if str(station.get("station_kind")) != station_kind:
		return _denied("wrong_station")
	var inventory: RefCounted = _source_inventory(str(request.source_holder_id), context)
	if inventory == null:
		return _denied("missing_source_holder")
	if inventory.has_method("get_holder_namespace") \
			and str(inventory.call("get_holder_namespace")) != str(request.source_holder_id):
		return _denied("source_holder_mismatch")
	var eligibility: Dictionary = _revalidate_recipe(recipe_id, station, local_context)
	if not bool(eligibility.get("ok", false)):
		return eligibility
	var ingredients: Variant = recipe.get("ingredients", null)
	if not ingredients is Dictionary or (ingredients as Dictionary).is_empty():
		return _denied("invalid_recipe")
	var selected_variant: Variant = request.get("selected_lot_ids", {})
	if not selected_variant is Dictionary:
		return _denied("invalid_request")
	var selected: Dictionary = selected_variant
	for selected_item_variant in selected:
		if typeof(selected_item_variant) != TYPE_STRING \
				or not (ingredients as Dictionary).has(selected_item_variant) \
				or not _selected_ids_are_strict(selected[selected_item_variant]):
			return _denied("invalid_request")
	for item_variant in (ingredients as Dictionary).keys():
		var item_id: String = str(item_variant)
		var need: int = int((ingredients as Dictionary)[item_variant])
		if need <= 0 or int(inventory.call("get_quantity", item_id)) < need:
			return _denied("missing_materials")
		var preferred: PackedStringArray = _selected_ids(selected.get(item_id, []))
		if not preferred.is_empty() and _selected_quantity(inventory, item_id, preferred) < need:
			return _denied("missing_materials")
	var required_seconds: float = float(recipe.get("craft_time_seconds", 0.0))
	if required_seconds <= 0.0:
		return _denied("invalid_recipe")
	return {
		"ok": true,
		"reason": "",
		"ship_id": str(request.ship_id),
		"station_instance_id": str(request.station_instance_id),
		"station_kind": station_kind,
		"recipe_id": recipe_id,
		"source_holder_id": str(request.source_holder_id),
		"required_seconds": required_seconds,
	}


func _try_start(job: RefCounted, station: RefCounted, context: Dictionary) -> Dictionary:
	var eligibility: Dictionary = _revalidate_recipe(str(job.get("recipe_id")), station, context)
	if not bool(eligibility.get("ok", false)):
		job.set("phase", CraftJobStateScript.PHASE_BLOCKED)
		job.set("blocked_reason", str(eligibility.get("reason", "blocked")))
		return eligibility
	var escrow: Array = job.get("ingredient_escrow") as Array
	if escrow.is_empty():
		job.set("phase", CraftJobStateScript.PHASE_BLOCKED)
		job.set("blocked_reason", "missing_escrow")
		return _denied("missing_escrow")
	var crafting: RefCounted = context.get("crafting_state", null) as RefCounted
	var produces: Dictionary = crafting.call("get_produces", str(job.get("recipe_id")))
	var input_quality: float = _weighted_quality(escrow)
	var skill: int = int(context.get("player_skill_level", 0))
	var effective_tier: int = int(station.call("effective_tier")) \
		if station.has_method("effective_tier") else int(station.get("level"))
	var resolver = QualityTierResolverScript.new()
	var quality: Dictionary = resolver.resolve(input_quality, skill, effective_tier, bool(station.get("powered")))
	var output_lot: Dictionary = {
		"lot_id": "%s/output-1" % str(job.get("job_id")),
		"item_id": str(produces.get("item_id", "")),
		"quantity": int(produces.get("quantity", 0)),
		"quality_score": float(quality.get("score", 0.0)),
		"quality_tier": str(quality.get("tier", "poor")),
		"condition": 1.0,
		"origin": {
			"job_id": str(job.get("job_id")),
			"recipe_id": str(job.get("recipe_id")),
			"input_quality_score": input_quality,
			"input_lot_ids": _lot_ids(escrow),
			"input_skill_level": skill,
			"station_effective_tier": effective_tier,
		},
	}
	if str(output_lot.item_id).is_empty() or int(output_lot.quantity) <= 0:
		job.set("phase", CraftJobStateScript.PHASE_BLOCKED)
		job.set("blocked_reason", "invalid_recipe")
		return _denied("invalid_recipe")
	job.set("consumed_lots", escrow.duplicate(true))
	job.set("ingredient_escrow", [])
	job.set("output_lots", [output_lot])
	job.set("input_quality_score", input_quality)
	job.set("input_skill_level", skill)
	job.set("station_effective_tier", effective_tier)
	job.set("station_powered_at_start", bool(station.get("powered")))
	job.set("blocked_reason", "")
	job.set("phase", CraftJobStateScript.PHASE_RUNNING if bool(station.get("powered")) else CraftJobStateScript.PHASE_PAUSED_POWER)
	return {"ok": true, "reason": ""}


func _revalidate_recipe(recipe_id: String, station: RefCounted, context: Dictionary) -> Dictionary:
	var crafting: RefCounted = context.get("crafting_state", null) as RefCounted
	if crafting == null or station == null:
		return _denied("missing_station")
	var knowledge: Variant = context.get("knowledge", null)
	if not bool(crafting.call("is_recipe_known", recipe_id, knowledge)):
		return _denied("missing_recipe_knowledge")
	var skill: int = int(context.get("player_skill_level", 0))
	if skill < int(crafting.call("get_required_skill_level", recipe_id)):
		return _denied("insufficient_skill")
	var tier: int = int(station.call("effective_tier")) \
		if station.has_method("effective_tier") else int(station.get("level"))
	if tier < int(crafting.call("get_station_tier_min", recipe_id)):
		return _denied("insufficient_tier")
	return {"ok": true, "reason": ""}


func _job_matches_recipe_authority(job: RefCounted) -> bool:
	var recipe_authority: RefCounted = _get_recipe_authority()
	if recipe_authority == null:
		return false
	var recipe_id: String = str(job.get("recipe_id"))
	var recipe: Dictionary = recipe_authority.call("get_recipe", recipe_id)
	var produces: Dictionary = recipe_authority.call("get_produces", recipe_id)
	if recipe.is_empty() or produces.is_empty() \
			or str(recipe.get("station_kind", "")) != str(job.get("station_kind")) \
			or absf(float(recipe.get("craft_time_seconds", -1.0)) \
				- float(job.get("required_seconds"))) > 0.0001:
		return false
	var phase: String = str(job.get("phase"))
	var escrow: Array = job.get("ingredient_escrow") as Array
	var consumed: Array = job.get("consumed_lots") as Array
	var authoritative_inputs: Array = escrow if bool(job.call("is_unstarted")) else consumed
	if phase == CraftJobStateScript.PHASE_CANCELLED and authoritative_inputs.is_empty():
		# An unstarted cancellation has already returned its exact escrow.
		pass
	elif not _lots_match_ingredients(authoritative_inputs, recipe.get("ingredients", {})):
		return false
	var outputs: Array = job.get("output_lots") as Array
	if phase == CraftJobStateScript.PHASE_CANCELLED:
		return outputs.is_empty()
	if bool(job.call("is_unstarted")):
		return outputs.is_empty()
	if outputs.size() != 1:
		return false
	var output: Dictionary = outputs[0]
	if str(output.get("item_id", "")) != str(produces.get("item_id", "")) \
			or int(output.get("quantity", 0)) != int(produces.get("quantity", 0)):
		return false
	var input_quality: float = _weighted_quality(consumed)
	if absf(input_quality - float(job.get("input_quality_score"))) > 0.0001:
		return false
	var expected: Dictionary = QualityTierResolverScript.new().resolve(
		input_quality,
		int(job.get("input_skill_level")),
		int(job.get("station_effective_tier")),
		bool(job.get("station_powered_at_start")))
	return absf(float(output.get("quality_score", -1.0)) \
			- float(expected.get("score", -2.0))) <= 0.0001 \
		and str(output.get("quality_tier", "")) == str(expected.get("tier", ""))


func _lots_match_ingredients(lots: Array, ingredients_variant: Variant) -> bool:
	if not ingredients_variant is Dictionary or (ingredients_variant as Dictionary).is_empty():
		return false
	var totals: Dictionary = {}
	for lot_variant in lots:
		var lot: Dictionary = lot_variant
		var item_id: String = str(lot.get("item_id", ""))
		totals[item_id] = int(totals.get(item_id, 0)) + int(lot.get("quantity", 0))
	var ingredients: Dictionary = ingredients_variant
	if totals.size() != ingredients.size():
		return false
	for item_variant in ingredients:
		var required: Variant = ingredients[item_variant]
		if typeof(item_variant) != TYPE_STRING \
				or (typeof(required) != TYPE_INT and typeof(required) != TYPE_FLOAT) \
				or not is_finite(float(required)) or float(required) != floorf(float(required)) \
				or int(required) <= 0 \
				or int(totals.get(str(item_variant), -1)) != int(required):
			return false
	return true


func _context_for_station(ship_id: String, station_id: String, context: Dictionary) -> Dictionary:
	var result: Dictionary = context.duplicate(false)
	var owner_key: String = _owner_key(ship_id, station_id)
	var station_contexts: Variant = context.get("station_contexts", {})
	if station_contexts is Dictionary:
		var station_context: Variant = (station_contexts as Dictionary).get(owner_key, null)
		if station_context is Dictionary:
			for key in (station_context as Dictionary):
				result[key] = (station_context as Dictionary)[key]
	var stations: Variant = context.get("stations", {})
	if stations is Dictionary:
		var station: Variant = (stations as Dictionary).get(owner_key, null)
		if station is RefCounted:
			result["station_state"] = station
	return result


func _validate_owner_context(
		ship_id: String,
		station_id: String,
		station: RefCounted,
		context: Dictionary) -> Dictionary:
	if station == null:
		return _denied("missing_station")
	if str(station.get("ship_id")) != ship_id \
			or str(station.get("station_instance_id")) != station_id:
		return _denied("owner_mismatch")
	if context.has("ship_id"):
		if typeof(context.get("ship_id")) != TYPE_STRING or str(context.ship_id) != ship_id:
			return _denied("wrong_ship")
	if context.has("station_instance_id"):
		if typeof(context.get("station_instance_id")) != TYPE_STRING \
				or str(context.station_instance_id) != station_id:
			return _denied("owner_mismatch")
	return {"ok": true, "reason": ""}


func _station_state(station_id: String, context: Dictionary) -> RefCounted:
	var direct: Variant = context.get("station_state", null)
	if direct is RefCounted:
		return direct
	var stations: Variant = context.get("stations", {})
	if stations is Dictionary and (stations as Dictionary).get(station_id, null) is RefCounted:
		return (stations as Dictionary)[station_id]
	return null


func _source_inventory(holder_id: String, context: Dictionary) -> RefCounted:
	var inventories: Variant = context.get("source_inventories", {})
	if inventories is Dictionary and (inventories as Dictionary).get(holder_id, null) is RefCounted:
		return (inventories as Dictionary)[holder_id]
	var direct: Variant = context.get("source_inventory", null)
	return direct as RefCounted if direct is RefCounted else null


func _selected_quantity(inventory: RefCounted, item_id: String, ids: PackedStringArray) -> int:
	if not inventory.has_method("get_lot_summary"):
		return 0
	var summary: Dictionary = inventory.call("get_lot_summary")
	var selected: Dictionary = {}
	for lot_id in ids:
		selected[lot_id] = true
	var total: int = 0
	for lot_variant in summary.get("lots", []):
		if lot_variant is Dictionary:
			var lot: Dictionary = lot_variant
			if selected.has(str(lot.get("lot_id", ""))) and str(lot.get("item_id", "")) == item_id:
				total += int(lot.get("quantity", 0))
	return total


func _selected_ids(value: Variant) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	if value is Array or value is PackedStringArray:
		for item in value:
			var lot_id: String = str(item)
			if not lot_id.is_empty() and not ids.has(lot_id):
				ids.append(lot_id)
	return ids


func _selected_ids_are_strict(value: Variant) -> bool:
	if not value is Array and not value is PackedStringArray:
		return false
	var seen: Dictionary = {}
	for item in value:
		if typeof(item) != TYPE_STRING or str(item).is_empty() or seen.has(str(item)):
			return false
		seen[str(item)] = true
	return true


func _can_restore_all(inventory: RefCounted, lots: Array) -> bool:
	var totals: Dictionary = {}
	for lot_variant in lots:
		var lot: Dictionary = lot_variant
		var item_id: String = str(lot.item_id)
		totals[item_id] = int(totals.get(item_id, 0)) + int(lot.quantity)
	for item_id in totals:
		if inventory.has_method("can_accept") and not bool(inventory.call("can_accept", str(item_id), int(totals[item_id]))):
			return false
	return true


func _restore_lots(inventory: RefCounted, lots: Array) -> bool:
	if lots.is_empty():
		return true
	var restored: Array = []
	for lot_variant in lots:
		var lot: Dictionary = (lot_variant as Dictionary).duplicate(true)
		if int(inventory.call("add_lot", lot)) != int(lot.quantity):
			for restored_variant in restored:
				var restored_lot: Dictionary = restored_variant
				inventory.call("take_lots", str(restored_lot.item_id), int(restored_lot.quantity), PackedStringArray([str(restored_lot.lot_id)]))
			return false
		restored.append(lot)
	return true


func _weighted_quality(lots: Array) -> float:
	var weighted: float = 0.0
	var count: int = 0
	for lot_variant in lots:
		var lot: Dictionary = lot_variant
		weighted += float(lot.quality_score) * float(lot.quantity)
		count += int(lot.quantity)
	return weighted / float(count) if count > 0 else 0.5


func _completion_receipt(job: RefCounted) -> Dictionary:
	return {
		"job_id": str(job.get("job_id")),
		"receipt_id": str(job.get("output_receipt_id")),
		"ship_id": str(job.get("ship_id")),
		"station_instance_id": str(job.get("station_instance_id")),
		"station_kind": str(job.get("station_kind")),
		"recipe_id": str(job.get("recipe_id")),
		"output_lots": (job.get("output_lots") as Array).duplicate(true),
	}


func _remove_from_owner_queue(job: RefCounted) -> void:
	var owner_key: String = _owner_key(str(job.get("ship_id")), str(job.get("station_instance_id")))
	var queue: Array = _owner_queues.get(owner_key, [])
	queue.erase(str(job.get("job_id")))
	_owner_queues[owner_key] = queue


func _sync_station_projection(station: RefCounted, job: RefCounted) -> void:
	if station != null and station.has_method("set_scheduler_projection"):
		station.call("set_scheduler_projection", job.call("get_summary") if job != null else {})


func _sequence_covers_jobs(sequence: int, ship_id: String, station_id: String, jobs: Dictionary) -> bool:
	for job_variant in jobs.values():
		var job: RefCounted = job_variant
		if str(job.get("ship_id")) == ship_id and str(job.get("station_instance_id")) == station_id \
				and int(job.get("sequence")) > sequence:
			return false
	return true


func _lot_ids(lots: Array) -> Array:
	var ids: Array = []
	for lot_variant in lots:
		ids.append(str((lot_variant as Dictionary).get("lot_id", "")))
	ids.sort()
	return ids


func _owner_key(ship_id: String, station_instance_id: String) -> String:
	return JSON.stringify([ship_id, station_instance_id], "", true)


func _denied(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}


func _strict_nonnegative_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value) if int(value) >= 0 else -1
	return -1
