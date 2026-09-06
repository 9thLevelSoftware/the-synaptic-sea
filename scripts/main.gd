extends Node3D

signal playable_instance_replaced(previous: PlayableGeneratedShip, current: PlayableGeneratedShip)

const DEFAULT_PLAYABLE_SHIP_SCENE: PackedScene = preload("res://scenes/procgen/playable_coherent_ship.tscn")

@export var playable_ship_scene: PackedScene = DEFAULT_PLAYABLE_SHIP_SCENE

var playable_instance: PlayableGeneratedShip
var _restore_failure_point_for_validation: String = ""
var _last_restore_failure_reason: String = ""

func _ready() -> void:
	print("The Synaptic Sea coherent proof ship bootstrap loaded.")
	if playable_ship_scene == null:
		push_error("MAIN BOOT FAIL reason=missing playable_ship_scene")
		return
	playable_instance = playable_ship_scene.instantiate() as PlayableGeneratedShip
	if playable_instance == null:
		push_error("MAIN BOOT FAIL reason=playable scene is not PlayableGeneratedShip")
		return
	playable_instance.name = "PlayableCoherentShip"
	add_child(playable_instance)


func replace_playable_from_prepared(requester: PlayableGeneratedShip, prepared: Dictionary) -> bool:
	if requester == null or requester != playable_instance \
			or not bool(prepared.get("ok", false)):
		_last_restore_failure_reason = "invalid_restore_request"
		return false
	var service = requester.get_save_load_service()
	var token: String = str(prepared.get("token", ""))
	var seal: String = str(prepared.get("seal", ""))
	if service == null or token.is_empty() or seal.is_empty():
		_last_restore_failure_reason = "invalid_restore_capability"
		if service != null and not token.is_empty():
			service.discard_prepared_load(token)
		return false
	var resolved: Dictionary = service.resolve_prepared_load(token, seal)
	if not bool(resolved.get("ok", false)):
		_last_restore_failure_reason = str(resolved.get("reason", "prepared_resolve_failed"))
		service.discard_prepared_load(token)
		return false
	var candidate = resolved.get("candidate", null)
	var staged = playable_ship_scene.instantiate() as PlayableGeneratedShip
	if staged == null or not staged.configure_restore_staging(
			candidate, _restore_failure_point_for_validation):
		_last_restore_failure_reason = "staging_configuration_failed"
		service.discard_prepared_load(token)
		if staged != null:
			staged.free()
		return false
	_restore_failure_point_for_validation = ""
	staged.name = "PlayableRestoreStaging"
	add_child(staged)
	if not staged.is_restore_staging_ready() \
			or not service.prepared_source_is_unchanged(token):
		_last_restore_failure_reason = staged.get_restore_staging_failure_reason() \
			if not staged.is_restore_staging_ready() else "prepared_source_changed"
		remove_child(staged)
		staged.free()
		service.discard_prepared_load(token)
		return false

	var previous: PlayableGeneratedShip = playable_instance
	var previous_process_mode: ProcessMode = previous.process_mode
	var previous_visible: bool = previous.visible
	previous.process_mode = Node.PROCESS_MODE_DISABLED
	previous.visible = false
	if not staged.activate_staged_restore():
		_last_restore_failure_reason = "staged_activation_failed"
		previous.visible = previous_visible
		previous.process_mode = previous_process_mode
		remove_child(staged)
		staged.free()
		service.discard_prepared_load(token)
		return false
	remove_child(previous)
	staged.name = "PlayableCoherentShip"
	playable_instance = staged
	if bool(resolved.get("migrated", false)):
		service.write_prepared_migration_copy(token)
	service.discard_prepared_load(token)
	_last_restore_failure_reason = ""
	playable_instance_replaced.emit(previous, staged)
	previous.queue_free()
	return true


func set_restore_failure_point_for_validation(failure_point: String) -> void:
	_restore_failure_point_for_validation = failure_point


func get_last_restore_failure_reason_for_validation() -> String:
	return _last_restore_failure_reason
