extends Node3D

@export var marker_path: String = "user://biomass_predelete_probe.marker"

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or marker_path.is_empty():
		return
	var temporary_path: String = marker_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("freed\n")
	file.flush()
	file.close()
	var marker_absolute: String = ProjectSettings.globalize_path(marker_path)
	var temporary_absolute: String = ProjectSettings.globalize_path(temporary_path)
	if FileAccess.file_exists(marker_path):
		DirAccess.remove_absolute(marker_absolute)
	DirAccess.rename_absolute(temporary_absolute, marker_absolute)
