extends RefCounted
class_name ShipWorkContext

## Session-local binding for one explicit ship owner. This object contains no
## durable state: ShipInstance and the pillar models remain authoritative.

var ship_id: String = ""
var ship: RefCounted = null
var binding_generation: int = 0
var module_integrity: RefCounted = null
var component_placement: RefCounted = null
var ship_modification: RefCounted = null
var work_transactions: RefCounted = null
## P09: CraftingState remains one shared, owner-keyed scheduler. The context
## carries its exact live reference so station nodes cannot silently use an
## unrelated coordinator/home alias.
var crafting_state: RefCounted = null
var is_attached: bool = false
var is_occupied: bool = false
var is_piloted: bool = false
var has_access: bool = false


func configure(ship_owner: RefCounted, bindings: Dictionary) -> Dictionary:
	if ship_owner == null:
		return {"ok": false, "reason": "unknown_ship"}
	var owner_id: String = str(ship_owner.get("ship_id"))
	if owner_id.is_empty():
		return {"ok": false, "reason": "unknown_ship"}
	var generation_v: Variant = bindings.get("binding_generation", 0)
	if typeof(generation_v) != TYPE_INT or int(generation_v) < 0:
		return {"ok": false, "reason": "invalid_binding_generation"}
	var owners: Dictionary = {}
	for key: String in ["module_integrity", "component_placement", "ship_modification", "work_transactions", "crafting_state"]:
		var value: Variant = bindings.get(key, null)
		if value != null and not (value is RefCounted):
			return {"ok": false, "reason": "invalid_%s" % key}
		owners[key] = value
	ship_id = owner_id
	ship = ship_owner
	binding_generation = int(generation_v)
	module_integrity = owners.module_integrity
	component_placement = owners.component_placement
	ship_modification = owners.ship_modification
	work_transactions = owners.work_transactions
	crafting_state = owners.crafting_state
	is_attached = bool(bindings.get("is_attached", false))
	is_occupied = bool(bindings.get("is_occupied", false))
	is_piloted = bool(bindings.get("is_piloted", false))
	has_access = bool(bindings.get("has_access", false))
	return {"ok": true, "reason": "ok"}


func preflight_physical_mutation(expected_ship_id: String, require_access: bool) -> Dictionary:
	if ship == null or ship_id.is_empty():
		return {"ok": false, "reason": "unknown_ship"}
	if expected_ship_id.is_empty() or expected_ship_id != ship_id:
		return {"ok": false, "reason": "wrong_ship"}
	if not _has_exact_work_transaction_authority():
		return {"ok": false, "reason": "missing_work_authority"}
	if not matches_binding(ship):
		return {"ok": false, "reason": "stale_binding"}
	if not is_attached:
		return {"ok": false, "reason": "target_not_attached"}
	if not is_occupied:
		return {"ok": false, "reason": "not_attending_target"}
	if require_access and not has_access:
		return {"ok": false, "reason": "no_access"}
	return {"ok": true, "reason": "ok"}


func matches_binding(ship_owner: RefCounted) -> bool:
	return ship_owner != null and ship_owner == ship \
		and str(ship_owner.get("ship_id")) == ship_id \
		and ship_owner.has_method("get_live_binding_generation") \
		and int(ship_owner.call("get_live_binding_generation")) == binding_generation \
		and ship_owner.call("get_live_module_integrity") == module_integrity \
		and ship_owner.call("get_live_component_placement") == component_placement \
		and ship_owner.call("get_live_ship_modification") == ship_modification \
		and ship_owner.call("get_live_work_transactions") == work_transactions


func _has_exact_work_transaction_authority() -> bool:
	return ship != null and work_transactions != null \
		and ship.has_method("get_live_work_transactions") \
		and ship.call("get_live_work_transactions") == work_transactions \
		and str(work_transactions.get("ship_id")) == ship_id


func target_revision(local_revision: String) -> String:
	if local_revision.is_empty() or ship_id.is_empty():
		return ""
	return "%s|binding:%d|%s" % [ship_id, binding_generation, local_revision]


static func revision_for(ship_owner: RefCounted, local_revision: String) -> String:
	if ship_owner == null or local_revision.is_empty() \
			or not ship_owner.has_method("get_live_binding_generation"):
		return ""
	var owner_id: String = str(ship_owner.get("ship_id"))
	if owner_id.is_empty():
		return ""
	return "%s|binding:%d|%s" % [
		owner_id, int(ship_owner.call("get_live_binding_generation")), local_revision]
