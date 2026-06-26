extends RefCounted
class_name AutosavePolicy

## Autosave policy (ADR-0031, ADR-0032).
##
## Pure model. `tick(seconds, event_count)` returns true when the
## service should fire an autosave. Tracks the last autosave wall-clock
## (`_last_real_time`), in-game time (`_last_game_seconds`), and event
## counter so the policy is stateless from the coordinator's perspective.
##
## Tunables (set on the instance, not magic constants):
## - `cadence_seconds`: how often in-game time should fire an autosave.
## - `cadence_events`: how many events should accumulate before firing.
## - `min_real_interval_seconds`: budget guard between autosaves.
## - `force`: a one-shot flag set by the coordinator (e.g. objective
##   completion) that triggers a save on the next tick.
## - `slot_rotation`: ordered list of slot_ids the policy rotates through.
##
## The default slot_rotation = ["autosave_a", "autosave_b", "autosave_c"]
## matches REQ-SL-006's "at most 3 autosave slots" cap.

const DEFAULT_CADENCE_SECONDS: float = 90.0
const DEFAULT_CADENCE_EVENTS: int = 8
const DEFAULT_MIN_REAL_INTERVAL_SECONDS: float = 5.0
const DEFAULT_QUICKSAVE_COOLDOWN_SECONDS: float = 10.0

var cadence_seconds: float = DEFAULT_CADENCE_SECONDS
var cadence_events: int = DEFAULT_CADENCE_EVENTS
var min_real_interval_seconds: float = DEFAULT_MIN_REAL_INTERVAL_SECONDS
var quicksave_cooldown_seconds: float = DEFAULT_QUICKSAVE_COOLDOWN_SECONDS

var force: bool = false
var _last_real_time: float = -1.0      # Time.get_ticks_msec() / 1000.0; -1 = never saved
var _last_game_seconds: float = 0.0    # cumulative in-game seconds
var _last_event_count: int = 0
var _last_autosave_slot_index: int = 0
var slot_rotation: Array = ["autosave_a", "autosave_b", "autosave_c"]
var _last_quicksave_real_time: float = -1.0

func reset() -> void:
	_last_real_time = -1.0
	_last_game_seconds = 0.0
	_last_event_count = 0
	_last_autosave_slot_index = 0
	_last_quicksave_real_time = -1.0
	force = false

func tick(game_seconds: float, event_count: int) -> Dictionary:
	# Returns {should_save:bool, slot_id:String, reason:String}.
	var now_real: float = float(Time.get_ticks_msec()) / 1000.0
	var result: Dictionary = {"should_save": false, "slot_id": "", "reason": "no_trigger"}
	if _last_real_time < 0.0:
		# First invocation: do not fire on tick 0; just seed the counters.
		_last_real_time = now_real
		_last_game_seconds = game_seconds
		_last_event_count = event_count
		return result
	if force:
		force = false
		_advance_rotation()
		_last_real_time = now_real
		_last_game_seconds = game_seconds
		_last_event_count = event_count
		return {"should_save": true, "slot_id": slot_rotation[_last_autosave_slot_index % slot_rotation.size()], "reason": "forced"}
	if (now_real - _last_real_time) < min_real_interval_seconds:
		return result  # budget guard
	if (game_seconds - _last_game_seconds) >= cadence_seconds:
		_advance_rotation()
		_last_real_time = now_real
		_last_game_seconds = game_seconds
		_last_event_count = event_count
		return {"should_save": true, "slot_id": slot_rotation[_last_autosave_slot_index % slot_rotation.size()], "reason": "cadence"}
	if (event_count - _last_event_count) >= cadence_events:
		_advance_rotation()
		_last_real_time = now_real
		_last_game_seconds = game_seconds
		_last_event_count = event_count
		return {"should_save": true, "slot_id": slot_rotation[_last_autosave_slot_index % slot_rotation.size()], "reason": "events"}
	return result

func _advance_rotation() -> void:
	_last_autosave_slot_index = (_last_autosave_slot_index + 1) % slot_rotation.size()

## Quicksave guard. Returns true when the quicksave should fire; false
## (and a warning reason) when the cooldown is still active.
func try_quicksave() -> Dictionary:
	var now_real: float = float(Time.get_ticks_msec()) / 1000.0
	if _last_quicksave_real_time >= 0.0 and (now_real - _last_quicksave_real_time) < quicksave_cooldown_seconds:
		return {"should_save": false, "slot_id": SaveSlotState.QUICKSAVE_SLOT_ID, "reason": "cooldown"}
	_last_quicksave_real_time = now_real
	return {"should_save": true, "slot_id": SaveSlotState.QUICKSAVE_SLOT_ID, "reason": "manual"}

## Direct quicksave guard for test scenarios where Time.get_ticks_msec
## is not the right clock. Test-only.
func _set_last_quicksave_real_time(value: float) -> void:
	_last_quicksave_real_time = value