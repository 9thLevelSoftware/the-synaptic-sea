extends RefCounted
class_name DerelictObjectiveController

## Pure-logic objective loop for a generated derelict. Composes ObjectiveProgressState
## (single-step objectives) and adds reach_goal / cleared semantics. Never touches the
## scene tree. Owned by a ShipInstance; its summary rides the per-ship slice.

const ObjectiveProgressStateScript := preload("res://scripts/systems/objective_progress_state.gd")
const REACH_GOAL_ID: String = "obj_reach_goal"
const STEP_ID: String = "done"  # single synthetic step per single-objective

var progress                       # ObjectiveProgressState
var reach_goal_sequence: int = 0
var cleared: bool = false

# Static factory via load() self-reference (class_name globals unreliable under
# --headless --script; matches ShipInstance.create).
static func create() -> DerelictObjectiveController:
	var script: GDScript = load("res://scripts/systems/derelict_objective_controller.gd")
	var c: DerelictObjectiveController = script.new()
	c.progress = ObjectiveProgressStateScript.new()
	return c

## True once the objective set has been registered (or restored).
func is_configured() -> bool:
	return reach_goal_sequence != 0 or not progress.get_summary().is_empty()

## Registers the generated objective set. First-visit only: idempotent once configured
## so re-boarding a derelict (or building interactables after a restore) preserves progress.
func configure(objective_specs: Array) -> void:
	if is_configured():
		return
	for spec_variant in objective_specs:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var sequence: int = int(spec.get("sequence", 0))
		if sequence <= 0:
			continue
		progress.register_objective(sequence, str(spec.get("type", "objective")), 1)
		if str(spec.get("id", "")) == REACH_GOAL_ID:
			reach_goal_sequence = sequence

## Completes a single-step objective by sequence. Returns true if newly completed.
## Sets `cleared` when the reach_goal sequence becomes complete.
func complete(sequence: int) -> bool:
	if progress == null:
		return false
	var changed: bool = progress.complete_step(sequence, STEP_ID)
	if reach_goal_sequence != 0 and progress.is_sequence_complete(reach_goal_sequence):
		cleared = true
	return changed

func is_objective_complete(sequence: int) -> bool:
	return progress != null and progress.is_sequence_complete(sequence)

func is_cleared() -> bool:
	return cleared

func get_summary() -> Dictionary:
	return {
		"progress": progress.get_summary() if progress != null else {},
		"reach_goal_sequence": reach_goal_sequence,
		"cleared": cleared,
	}

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	if progress == null:
		progress = ObjectiveProgressStateScript.new()
	var prog: Variant = summary.get("progress", {})
	if typeof(prog) == TYPE_DICTIONARY and not (prog as Dictionary).is_empty():
		progress.apply_summary(prog as Dictionary)
	reach_goal_sequence = int(summary.get("reach_goal_sequence", 0))
	cleared = bool(summary.get("cleared", false))
	return true
