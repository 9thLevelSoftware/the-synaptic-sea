extends SceneTree
const TooltipPresenterScript := preload("res://scripts/systems/tooltip_presenter.gd")
func _init() -> void:
	var presenter = TooltipPresenterScript.new()
	var catalog: Dictionary = {"version": "tooltip-catalog-1", "entries": [{"id": "item_circuit_board", "subject_kind": "item", "subject_id": "circuit_board", "title": "Circuit Board", "body": "Repair part.", "footer": "[E] Pick up"}]}
	assert(presenter.configure(catalog))
	var payload = presenter.resolve({"subject_kind": "item", "subject_id": "circuit_board"})
	assert(payload != null)
	assert(String(payload.title) == "Circuit Board")
	print("TOOLTIP PRESENTER PASS title=%s footer=%s" % [String(payload.title), String(payload.footer)])
	quit()
