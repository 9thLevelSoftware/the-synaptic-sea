extends RefCounted
class_name CraftJobState

## Serializable pure state for one paid fabrication job (ADR-0059).

const QualityTierResolverScript := preload("res://scripts/systems/quality_tier_resolver.gd")

const PHASE_QUEUED: String = "queued"
const PHASE_RUNNING: String = "running"
const PHASE_PAUSED_POWER: String = "paused_power"
const PHASE_BLOCKED: String = "blocked"
const PHASE_OUTPUT_READY: String = "output_ready"
const PHASE_COLLECTED: String = "collected"
const PHASE_CANCELLED: String = "cancelled"
const VALID_PHASES: Array[String] = [
	PHASE_QUEUED,
	PHASE_RUNNING,
	PHASE_PAUSED_POWER,
	PHASE_BLOCKED,
	PHASE_OUTPUT_READY,
	PHASE_COLLECTED,
	PHASE_CANCELLED,
]

var job_id: String = ""
var ship_id: String = ""
var station_instance_id: String = ""
var station_kind: String = ""
var recipe_id: String = ""
var phase: String = PHASE_QUEUED
var source_holder_id: String = ""
var escrow_holder_id: String = ""
var ingredient_escrow: Array = []
var consumed_lots: Array = []
var progress_seconds: float = 0.0
var required_seconds: float = 0.0
var output_lots: Array = []
var output_receipt_id: String = ""
var sequence: int = 0
var blocked_reason: String = ""
var input_quality_score: float = -1.0
var input_skill_level: int = -1
var station_effective_tier: int = -1
var station_powered_at_start: bool = false
var receipt_emitted: bool = false


func get_summary() -> Dictionary:
	return {
		"job_id": job_id,
		"ship_id": ship_id,
		"station_instance_id": station_instance_id,
		"station_kind": station_kind,
		"recipe_id": recipe_id,
		"state": phase,
		"phase": phase,
		"source_holder_id": source_holder_id,
		"escrow_holder_id": escrow_holder_id,
		"ingredient_escrow": ingredient_escrow.duplicate(true),
		"consumed_lots": consumed_lots.duplicate(true),
		"progress": progress_seconds,
		"progress_seconds": progress_seconds,
		"required_seconds": required_seconds,
		"output_lots": output_lots.duplicate(true),
		"output_receipt_id": output_receipt_id,
		"sequence": sequence,
		"blocked_reason": blocked_reason,
		"input_quality_score": input_quality_score,
		"input_skill_level": input_skill_level,
		"station_effective_tier": station_effective_tier,
		"station_powered_at_start": station_powered_at_start,
		"receipt_emitted": receipt_emitted,
	}


## Strict and atomic: malformed current records never partially replace a job.
func apply_summary(summary: Dictionary) -> bool:
	var normalized: Dictionary = _normalize(summary)
	if normalized.is_empty():
		return false
	job_id = normalized.job_id
	ship_id = normalized.ship_id
	station_instance_id = normalized.station_instance_id
	station_kind = normalized.station_kind
	recipe_id = normalized.recipe_id
	phase = normalized.phase
	source_holder_id = normalized.source_holder_id
	escrow_holder_id = normalized.escrow_holder_id
	ingredient_escrow = normalized.ingredient_escrow
	consumed_lots = normalized.consumed_lots
	progress_seconds = normalized.progress_seconds
	required_seconds = normalized.required_seconds
	output_lots = normalized.output_lots
	output_receipt_id = normalized.output_receipt_id
	sequence = normalized.sequence
	blocked_reason = normalized.blocked_reason
	input_quality_score = normalized.input_quality_score
	input_skill_level = normalized.input_skill_level
	station_effective_tier = normalized.station_effective_tier
	station_powered_at_start = normalized.station_powered_at_start
	receipt_emitted = normalized.receipt_emitted
	return true


func is_unstarted() -> bool:
	return phase == PHASE_QUEUED or phase == PHASE_BLOCKED


func is_terminal() -> bool:
	return phase == PHASE_OUTPUT_READY or phase == PHASE_COLLECTED or phase == PHASE_CANCELLED


func _normalize(raw: Dictionary) -> Dictionary:
	if not raw.has("state") or not raw.has("phase") \
			or not raw.has("progress") or not raw.has("progress_seconds"):
		return {}
	for string_key in [
		"job_id", "ship_id", "station_instance_id", "station_kind", "recipe_id",
		"state", "phase", "source_holder_id", "escrow_holder_id",
		"output_receipt_id", "blocked_reason",
	]:
		if typeof(raw.get(string_key, null)) != TYPE_STRING:
			return {}
	if typeof(raw.get("receipt_emitted", null)) != TYPE_BOOL \
			or typeof(raw.get("station_powered_at_start", null)) != TYPE_BOOL:
		return {}
	for key in [
		"job_id", "ship_id", "station_instance_id", "station_kind", "recipe_id",
		"source_holder_id", "escrow_holder_id", "ingredient_escrow", "consumed_lots",
		"required_seconds", "output_lots", "output_receipt_id", "sequence",
		"blocked_reason", "input_quality_score", "input_skill_level",
		"station_effective_tier", "receipt_emitted",
		"station_powered_at_start",
	]:
		if not raw.has(key):
			return {}
	var next_phase: String = str(raw.get("state", raw.get("phase", "")))
	if not VALID_PHASES.has(next_phase):
		return {}
	if raw.has("phase") and str(raw.phase) != next_phase:
		return {}
	var next_sequence: int = _strict_nonnegative_int(raw.sequence)
	var next_skill: int = _strict_int(raw.input_skill_level)
	var next_tier: int = _strict_int(raw.station_effective_tier)
	if next_sequence <= 0 or next_skill < -1 or next_tier < -1:
		return {}
	var next_progress: float = _finite_number(raw.get("progress_seconds", raw.get("progress", null)))
	var progress_alias: float = _finite_number(raw.get("progress", next_progress))
	var next_required: float = _finite_number(raw.required_seconds)
	var next_quality: float = _finite_number(raw.input_quality_score)
	if next_progress < 0.0 or absf(next_progress - progress_alias) > 0.0001 \
			or next_required <= 0.0 or next_progress > next_required + 0.0001 \
			or next_quality < -1.0 or next_quality > 1.0:
		return {}
	if not raw.ingredient_escrow is Array or not raw.consumed_lots is Array \
			or not raw.output_lots is Array:
		return {}
	var escrow: Array = _normalize_lots(raw.ingredient_escrow)
	var consumed: Array = _normalize_lots(raw.consumed_lots)
	var outputs: Array = _normalize_lots(raw.output_lots)
	if escrow.size() != (raw.ingredient_escrow as Array).size() \
			or consumed.size() != (raw.consumed_lots as Array).size() \
			or outputs.size() != (raw.output_lots as Array).size():
		return {}
	for id_key in ["job_id", "ship_id", "station_instance_id", "station_kind", "recipe_id", "source_holder_id", "escrow_holder_id"]:
		if str(raw[id_key]).is_empty():
			return {}
	var expected_id: String = "%s/%s/job-%06d" % [str(raw.ship_id), str(raw.station_instance_id), next_sequence]
	if str(raw.job_id) != expected_id:
		return {}
	var receipt: String = str(raw.output_receipt_id)
	match next_phase:
		PHASE_QUEUED, PHASE_BLOCKED:
			if escrow.is_empty() or not consumed.is_empty() or not outputs.is_empty() \
					or not receipt.is_empty() or next_progress != 0.0 \
					or next_quality != -1.0 or next_skill != -1 or next_tier != -1 \
					or (next_phase == PHASE_QUEUED and not str(raw.blocked_reason).is_empty()) \
					or (next_phase == PHASE_BLOCKED and str(raw.blocked_reason).is_empty()):
				return {}
		PHASE_RUNNING, PHASE_PAUSED_POWER:
			if not escrow.is_empty() or consumed.is_empty() or outputs.is_empty() \
					or not receipt.is_empty() or next_quality < 0.0 \
					or next_skill < 0 or next_tier < 0:
				return {}
		PHASE_OUTPUT_READY, PHASE_COLLECTED:
			if not escrow.is_empty() or consumed.is_empty() or outputs.is_empty() \
					or receipt != "%s/output" % str(raw.job_id) \
					or absf(next_progress - next_required) > 0.0001 \
					or next_quality < 0.0 or next_skill < 0 or next_tier < 0 \
					or not bool(raw.receipt_emitted):
				return {}
		PHASE_CANCELLED:
			if not escrow.is_empty() or not receipt.is_empty():
				return {}
	if next_phase != PHASE_BLOCKED and not str(raw.blocked_reason).is_empty():
		return {}
	if bool(raw.receipt_emitted) and next_phase != PHASE_OUTPUT_READY and next_phase != PHASE_COLLECTED:
		return {}
	if not outputs.is_empty() and not _output_metadata_matches(
			outputs, consumed, str(raw.job_id), str(raw.recipe_id),
			next_quality, next_skill, next_tier):
		return {}
	return {
		"job_id": str(raw.job_id),
		"ship_id": str(raw.ship_id),
		"station_instance_id": str(raw.station_instance_id),
		"station_kind": str(raw.station_kind),
		"recipe_id": str(raw.recipe_id),
		"phase": next_phase,
		"source_holder_id": str(raw.source_holder_id),
		"escrow_holder_id": str(raw.escrow_holder_id),
		"ingredient_escrow": escrow,
		"consumed_lots": consumed,
		"progress_seconds": next_progress,
		"required_seconds": next_required,
		"output_lots": outputs,
		"output_receipt_id": receipt,
		"sequence": next_sequence,
		"blocked_reason": str(raw.blocked_reason),
		"input_quality_score": next_quality,
		"input_skill_level": next_skill,
		"station_effective_tier": next_tier,
		"station_powered_at_start": bool(raw.station_powered_at_start),
		"receipt_emitted": bool(raw.receipt_emitted),
	}


func _normalize_lots(value: Variant) -> Array:
	if not value is Array:
		return []
	var result: Array = []
	var ids: Dictionary = {}
	for lot_variant in value:
		if not lot_variant is Dictionary:
			return []
		var lot: Dictionary = lot_variant
		for string_key in ["lot_id", "item_id", "quality_tier"]:
			if typeof(lot.get(string_key, null)) != TYPE_STRING:
				return []
		if typeof(lot.get("quantity", null)) != TYPE_INT:
			return []
		var lot_id: String = str(lot.get("lot_id", ""))
		var item_id: String = str(lot.get("item_id", ""))
		var quantity: int = _strict_nonnegative_int(lot.get("quantity", null))
		var score: float = _finite_number(lot.get("quality_score", null))
		var condition: float = _finite_number(lot.get("condition", null))
		var tier: String = str(lot.get("quality_tier", ""))
		if lot_id.is_empty() or item_id.is_empty() or quantity <= 0 or ids.has(lot_id) \
				or score < 0.0 or score > 1.0 or condition < 0.0 or condition > 1.0 \
				or not QualityTierResolverScript.TIER_ORDER.has(tier) \
				or QualityTierResolverScript.tier_for_score(score) != tier \
				or not lot.get("origin", null) is Dictionary:
			return []
		ids[lot_id] = true
		result.append(lot.duplicate(true))
	return result


func _output_metadata_matches(
		outputs: Array,
		consumed: Array,
		expected_job_id: String,
		expected_recipe_id: String,
		expected_quality: float,
		expected_skill: int,
		expected_tier: int) -> bool:
	if outputs.size() != 1:
		return false
	var output: Dictionary = outputs[0]
	if str(output.get("lot_id", "")) != "%s/output-1" % expected_job_id:
		return false
	var origin: Dictionary = output.get("origin", {}) as Dictionary
	for key in ["job_id", "recipe_id"]:
		if typeof(origin.get(key, null)) != TYPE_STRING:
			return false
	if str(origin.job_id) != expected_job_id or str(origin.recipe_id) != expected_recipe_id \
			or typeof(origin.get("input_skill_level", null)) != TYPE_INT \
			or int(origin.input_skill_level) != expected_skill \
			or typeof(origin.get("station_effective_tier", null)) != TYPE_INT \
			or int(origin.station_effective_tier) != expected_tier:
		return false
	var origin_quality: float = _finite_number(origin.get("input_quality_score", null))
	if origin_quality < 0.0 or absf(origin_quality - expected_quality) > 0.0001 \
			or not origin.get("input_lot_ids", null) is Array:
		return false
	var input_ids: Array = origin.input_lot_ids
	var strict_ids: Array = []
	for id_variant in input_ids:
		if typeof(id_variant) != TYPE_STRING or str(id_variant).is_empty():
			return false
		strict_ids.append(str(id_variant))
	strict_ids.sort()
	var consumed_ids: Array = []
	for lot_variant in consumed:
		consumed_ids.append(str((lot_variant as Dictionary).lot_id))
	consumed_ids.sort()
	return strict_ids == consumed_ids


func _strict_nonnegative_int(value: Variant) -> int:
	var parsed: int = _strict_int(value)
	return parsed if parsed >= 0 else -1


func _strict_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	return -2147483648


func _finite_number(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return -INF
	var number: float = float(value)
	return number if is_finite(number) else -INF
