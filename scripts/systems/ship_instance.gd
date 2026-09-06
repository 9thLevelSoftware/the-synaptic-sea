extends RefCounted
class_name ShipInstance

## Lightweight per-ship handle. Bundles the identity + data + systems + scene
## root that genuinely must be per-ship for multi-ship travel/docking. Pure
## data plus a systems handle and a Node3D reference; it never adds or frees
## its own scene_root — the coordinator owns scene-tree lifecycle (single
## ownership). Phase-5 docking fields are declared now so docking attaches to
## a stable shape; they are unused this phase.

const ShipBlueprintScript := preload("res://scripts/procgen/ship_blueprint.gd")
const ThreatSaveContractScript := preload("res://scripts/systems/threat_save_contract.gd")
const ShipSystemsManagerScript := preload("res://scripts/systems/ship_systems_manager.gd")
const DerelictObjectiveControllerScript := preload("res://scripts/systems/derelict_objective_controller.gd")
const ShipAccessStateScript := preload("res://scripts/systems/ship_access_state.gd")
const HangarBayScript := preload("res://scripts/systems/hangar_bay.gd")
const ShipInventoryScript := preload("res://scripts/systems/ship_inventory.gd")
const CartStateScript := preload("res://scripts/systems/cart_state.gd")
const ItemLotLedgerScript := preload("res://scripts/systems/item_lot_ledger.gd")
const FireSuppressionStateScript := preload("res://scripts/systems/fire_suppression_state.gd")
const HullIntegrityStateScript := preload("res://scripts/systems/hull_integrity_state.gd")
const WebInfestationStateScript := preload("res://scripts/systems/web_infestation_state.gd")
const PendingOutputStoreScript := preload("res://scripts/systems/pending_output_store.gd")
const ComponentPlacementStateScript := preload("res://scripts/systems/component_placement_state.gd")

const ROOM_HALF_EXTENT: float = 4.0   # generous per-room half-box in X/Z (covers 2x1 rooms + module chains)
const ROOM_HALF_HEIGHT: float = 3.0   # half deck height + headroom

var ship_id: String = ""
var marker_id: String = ""          # "" for the starting ship; cell:cell:index for traveled ships
var blueprint                       # ShipBlueprint
var systems_manager                 # ShipSystemsManager (this ship's own systems)
var scene_root: Node3D = null       # generated/loaded tree; null when not instantiated
var built_layout: Dictionary = {}   # the layout dict scene_root was built from (for dock-port derivation)

# 5a: `ship_root` is the ship's positioned root — it IS scene_root, exposed
# under the docking-domain name. Alias so DockingManager/occupancy read
# naturally without renaming the coordinator's existing scene_root usage.
var ship_root: Node3D:
	get:
		return scene_root
	set(value):
		scene_root = value

# Phase 5 stubs — declared, unused this phase.
var parent_ship = null              # ShipInstance | null
var docked_ships: Array = []        # Array[ShipInstance]
var docking_ports: Array = []       # Array (DockingPort in Phase 5)

# Sub-project 5c: per-ship ownership/access. Lazily created; persisted under "access".
var access = null                        # ShipAccessState | null

# Sub-project 5d: per-ship hangar bay (stores other ships). Lazily created;
# persisted under "hangar" only when it actually has slots.
var hangar = null                        # HangarBay | null

# Sub-project #6 (cargo): per-ship cargo hold (stores items). Lazily created;
# persisted under "inventory" only when it actually holds something.
var inventory = null                     # ShipInventory | null

# Sub-project #6 (carts): carts parked on this ship. Persisted under "carts" only
# when non-empty. Each entry is a CartState.
var carts: Array = []                    # Array[CartState]

# P04: scene nodes for unscooped work yield are disposable projections of this
# ship-owned state. Keys are stable drop IDs and values retain exact lot metadata
# plus a ship-local Transform3D payload.
var floor_drop_sequence: int = 0
var floor_drop_descriptors: Dictionary = {}

# P08: ship-owned registry for physical station outputs and recoverable refunds.
var pending_outputs = null                # PendingOutputStore | null

# Sub-project #2: per-derelict objective loop state. Lazily created; null for the
# home ship (which uses the coordinator's singleton loop, not this controller).
var objective_controller = null          # DerelictObjectiveController | null

# Sub-project #3: ids of scattered loot containers already searched on this ship.
# Salvage-point loot reuses the objective `completed` flag, so it is not listed here.
var looted_container_ids: Array = []

# Domain 2 follow-up: unsearched combat corpse drops. Transient LootContainer
# nodes die with scene_root on leave; these descriptors re-spawn the drop on
# revisit / save-load until the player searches them (then they move into
# looted_container_ids and drop out of this list). Each entry:
#   {container_id, loot_table, seed_source, position: [x,y,z]}  # ship-local pos
var pending_corpse_loot: Array = []

# Domain 5: ids of sealed hatches already bypassed on this ship. Persisted so a
# revisited derelict remembers which passages are already open.
var bypassed_hatch_ids: Array = []

# Authored portal interaction state. Unlock identity is separate from open state
# so a consumed lock remains free to reopen after it is closed and rebuilt.
var authored_unlocked_portal_ids: Array = []
var authored_open_portal_ids: Array = []

# Task 06: per-ship combat/threat persistence. The live ThreatManager node belongs to
# the coordinator; this summary lets traveled ships free/rebuild scene roots without
# losing threat positions, detection memory, or the last combat result.
var combat_summary: Dictionary = {}

# Derelict-side fire: per-ship authoritative FireSuppressionState. Lazily created;
# persisted under "fire" only when a compartment is actually burning. Home fire stays
# on the coordinator (fire_suppression_state); this is for boarded derelicts.
var fire = null                          # FireSuppressionState | null
# Per-ship electrical arc summary. The live ElectricalArcState node is owned by
# the coordinator, but traveled derelicts need their cycle phase/time preserved
# while their scene_root is freed or rebuilt.
var arc_summary: Dictionary = {}
# True once the coordinator has run its one-time environmental fire pre-seed for this
# derelict. Persisted so a revisit/reload does NOT re-roll the presence gate or re-ignite
# compartments the player already extinguished. Set even when the presence gate yields no
# fire — "seeded to empty" must survive reload too.
var fire_seeded: bool = false
# True once the coordinator has run its one-time variant-driven breach pre-seed for this
# derelict. Persisted so a revisit/reload does NOT re-breach compartments the player
# already sealed. Set even when the variant scan yields no breaches.
var breach_seeded: bool = false
# Scene-level breach environment belongs to this ship; player oxygen remains
# coordinator-owned so it follows the player between hulls.
var breach_environment_summary: Dictionary = {}

# Live Persistent Ships Phase 2a: per-ship structural state, mirroring `fire`. The
# coordinator configures these from tuning before seeding/use. hull holds breach/health
# per compartment; web holds biomatter-web coverage that damages the hull over time.
var hull = null                          # HullIntegrityState | null
var web = null                           # WebInfestationState | null

# Live Persistent Ships Phase 1: world_time at which this ship's sim was last
# advanced. Catch-up on revisit (Phase 4) advances the ship by
# (world_time - last_sim_time). Persisted only when nonzero (additive).
var last_sim_time: float = 0.0

# PKG-D6.1: sparse pillar deltas that must survive leave/revisit (geometry
# regenerates from seed; these re-apply onto the fresh map/placement).
# module_integrity_summary: ModuleIntegrityMap.get_summary() shape (schema + deltas).
# component_placement_summary: ComponentPlacementState.get_summary() shape.
var module_integrity_summary: Dictionary = {}
var component_placement_summary: Dictionary = {}

# FC-15: nonserialized restoration handles. ComponentPlacementState remains the
# durable component authority; ShipModificationState is only its live derived
# projection. A changed handle invalidates in-memory callbacks through the
# monotonic binding generation.
var live_module_integrity: RefCounted = null
var live_component_placement: RefCounted = null
var live_ship_modification: RefCounted = null
var live_work_transactions: RefCounted = null
var _live_binding_generation: int = 0

# Static factory via load() self-reference (class_name globals unreliable under
# --headless --script).
static func create(p_ship_id: String, p_marker_id: String, p_blueprint, p_systems_manager, p_scene_root) -> ShipInstance:
	var script: GDScript = load("res://scripts/systems/ship_instance.gd")
	var inst = script.new()
	inst.ship_id = p_ship_id
	inst.marker_id = p_marker_id
	inst.blueprint = p_blueprint
	inst.systems_manager = p_systems_manager
	inst.scene_root = p_scene_root
	return inst


func bind_live_restoration_owners(
		module_owner: RefCounted,
		placement_owner: RefCounted,
		modification_projection: RefCounted,
		transaction_owner: RefCounted) -> Dictionary:
	if ship_id.is_empty():
		return {"ok": false, "reason": "unknown_ship"}
	if transaction_owner == null:
		return {"ok": false, "reason": "missing_transaction_owner"}
	var tx_ship_id: String = _string_property(transaction_owner, "ship_id")
	if tx_ship_id.is_empty() or tx_ship_id != ship_id:
		return {"ok": false, "reason": "wrong_transaction_owner"}
	if modification_projection != null:
		var mod_ship_id: String = _string_property(modification_projection, "_ship_id")
		if not mod_ship_id.is_empty() and mod_ship_id != ship_id:
			return {"ok": false, "reason": "wrong_modification_owner"}
	var changed: bool = live_module_integrity != module_owner \
		or live_component_placement != placement_owner \
		or live_ship_modification != modification_projection \
		or live_work_transactions != transaction_owner
	live_module_integrity = module_owner
	live_component_placement = placement_owner
	live_ship_modification = modification_projection
	live_work_transactions = transaction_owner
	if changed:
		_live_binding_generation += 1
	return {"ok": true, "reason": "ok", "binding_generation": _live_binding_generation}


func get_live_binding_generation() -> int:
	return _live_binding_generation


func get_live_module_integrity() -> RefCounted:
	return live_module_integrity


func get_live_component_placement() -> RefCounted:
	return live_component_placement


func get_live_ship_modification() -> RefCounted:
	return live_ship_modification


func get_live_work_transactions() -> RefCounted:
	return live_work_transactions


func claim_home_access_for_bootstrap(
		player_id: String, is_new_run: bool, verified_legacy_absent: bool = false) -> bool:
	if player_id.is_empty():
		return false
	if access != null:
		var existing_owner: String = str(access.get("owner_id"))
		if not existing_owner.is_empty():
			return existing_owner == player_id
		if not verified_legacy_absent:
			return false
	if not is_new_run and not verified_legacy_absent:
		return false
	return get_access().claim(player_id)


static func _string_property(owner: Object, property_name: String) -> String:
	for descriptor_v in owner.get_property_list():
		if descriptor_v is Dictionary and str((descriptor_v as Dictionary).get("name", "")) == property_name:
			return str(owner.get(property_name))
	return ""

func get_summary() -> Dictionary:
	var bp_dict: Dictionary = {}
	if blueprint != null and blueprint.has_method("to_dict"):
		bp_dict = blueprint.to_dict()
	var sys_dict: Dictionary = {}
	if systems_manager != null and systems_manager.has_method("get_summary"):
		sys_dict = systems_manager.get_summary()
	var result: Dictionary = {
		"ship_id": ship_id,
		"marker_id": marker_id,
		"blueprint": bp_dict,
		"systems": sys_dict,
	}
	if objective_controller != null:
		result["objective"] = objective_controller.get_summary()
	if not looted_container_ids.is_empty():
		result["looted_containers"] = looted_container_ids.duplicate()
	if not pending_corpse_loot.is_empty():
		result["pending_corpse_loot"] = pending_corpse_loot.duplicate(true)
	if not bypassed_hatch_ids.is_empty():
		result["bypassed_hatches"] = bypassed_hatch_ids.duplicate()
	if not authored_unlocked_portal_ids.is_empty():
		result["authored_unlocked_portals"] = authored_unlocked_portal_ids.duplicate()
	if not authored_open_portal_ids.is_empty():
		result["authored_open_portals"] = authored_open_portal_ids.duplicate()
	if not combat_summary.is_empty():
		result["combat"] = combat_summary.duplicate(true)
	if access != null:
		result["access"] = access.get_summary()
	if hangar != null and hangar.slot_count > 0:
		result["hangar"] = hangar.get_summary()
	if has_cargo():
		result["inventory"] = inventory.get_summary()
	if not carts.is_empty():
		var cart_dicts: Array = []
		for c in carts:
			cart_dicts.append(c.get_summary())
		result["carts"] = cart_dicts
	if floor_drop_sequence > 0 or not floor_drop_descriptors.is_empty():
		result["floor_drops_v1"] = get_floor_drop_summary()
	if pending_outputs != null and pending_outputs.has_method("get_summary"):
		result["pending_outputs_v1"] = pending_outputs.get_summary()
	else:
		var empty_pending = PendingOutputStoreScript.new()
		if empty_pending.configure(ship_id):
			result["pending_outputs_v1"] = empty_pending.get_summary()
	# Persist whenever seeded or vented, not only while something still burns.
	# A vents-only / extinguished derelict keeps fire_seeded=true; omitting the
	# blob would skip seed on load and drop vented_compartments.
	if fire != null and (fire_seeded or has_fire() or not fire.vented_compartments.is_empty()):
		result["fire"] = fire.get_summary()
	if not arc_summary.is_empty():
		result["arc"] = arc_summary.duplicate(true)
	if fire_seeded:
		result["fire_seeded"] = true
	if breach_seeded:
		result["breach_seeded"] = true
	if not breach_environment_summary.is_empty():
		result["breach_environment"] = breach_environment_summary.duplicate(true)
	if has_hull():
		result["hull"] = hull.get_summary()
	if web != null and (not web.attached_to_web or web.coverage > 0.0):
		result["web"] = web.get_summary()
	if last_sim_time != 0.0:
		result["last_sim_time"] = last_sim_time
	if not module_integrity_summary.is_empty():
		result["module_integrity"] = module_integrity_summary.duplicate(true)
	if not component_placement_summary.is_empty():
		result["component_placement"] = component_placement_summary.duplicate(true)
	return result

func apply_summary(summary) -> bool:
	if typeof(summary) != TYPE_DICTIONARY or (summary as Dictionary).is_empty():
		return false
	var restored_ship_id: String = str(summary.get("ship_id", ship_id))
	if restored_ship_id.is_empty() or (not ship_id.is_empty() and restored_ship_id != ship_id):
		return false
	var restored_component_summary: Dictionary = {}
	var restored_combat_summary: Dictionary = {}
	if summary.has("combat"):
		var combat_result: Dictionary = ThreatSaveContractScript.validate_current(
			summary.get("combat", null))
		if not bool(combat_result.get("ok", false)):
			return false
		restored_combat_summary = (combat_result.summary as Dictionary).duplicate(true)
	if summary.has("component_placement"):
		var component_variant: Variant = summary.get("component_placement")
		if not component_variant is Dictionary or (component_variant as Dictionary).is_empty():
			return false
		var restored_component = ComponentPlacementStateScript.new()
		if not restored_component.apply_summary(
				component_variant as Dictionary, restored_ship_id):
			return false
		restored_component_summary = restored_component.get_summary()
	var restored_inventory = null
	if summary.has("inventory"):
		var inventory_summary: Variant = summary["inventory"]
		if not (inventory_summary is Dictionary) or (inventory_summary as Dictionary).is_empty():
			return false
		restored_inventory = ShipInventoryScript.create(ShipInventoryScript.MAX_WEIGHT_DEFAULT, _cargo_namespace(restored_ship_id))
		if not restored_inventory.apply_summary(inventory_summary as Dictionary):
			return false
	var restored_carts: Array = []
	if summary.has("carts"):
		var carts_variant: Variant = summary["carts"]
		if not (carts_variant is Array):
			return false
		var seen_cart_ids: Dictionary = {}
		for raw_cart in carts_variant as Array:
			if not (raw_cart is Dictionary):
				return false
			var cart_summary: Dictionary = raw_cart as Dictionary
			var restored_cart_id: String = str(cart_summary.get("cart_id", ""))
			if restored_cart_id.is_empty() or seen_cart_ids.has(restored_cart_id):
				return false
			var restored_cart = CartStateScript.create(restored_cart_id)
			if not restored_cart.apply_summary(cart_summary):
				return false
			seen_cart_ids[restored_cart_id] = true
			restored_carts.append(restored_cart)
	var restored_floor: Dictionary = {"ok": true, "sequence": 0, "drops": {}}
	if summary.has("floor_drops_v1"):
		restored_floor = _validated_floor_drop_summary(summary["floor_drops_v1"], restored_ship_id)
		if not bool(restored_floor.get("ok", false)):
			return false
	var restored_pending = PendingOutputStoreScript.new()
	if not restored_pending.configure(restored_ship_id):
		return false
	if summary.has("pending_outputs_v1"):
		var pending_variant: Variant = summary.get("pending_outputs_v1")
		if not pending_variant is Dictionary \
				or not restored_pending.apply_summary(pending_variant as Dictionary):
			return false
	ship_id = restored_ship_id
	marker_id = str(summary.get("marker_id", marker_id))
	var bp_dict: Variant = summary.get("blueprint", null)
	if typeof(bp_dict) == TYPE_DICTIONARY and not (bp_dict as Dictionary).is_empty():
		blueprint = ShipBlueprintScript.from_dict(bp_dict as Dictionary)
	var sys_dict: Variant = summary.get("systems", null)
	if typeof(sys_dict) == TYPE_DICTIONARY and not (sys_dict as Dictionary).is_empty():
		if systems_manager == null:
			systems_manager = ShipSystemsManagerScript.new()
			systems_manager.configure(systems_manager.load_definitions(), 0, 0)
		systems_manager.apply_summary(sys_dict)
	var obj_summary: Variant = summary.get("objective", null)
	if typeof(obj_summary) == TYPE_DICTIONARY and not (obj_summary as Dictionary).is_empty():
		if objective_controller == null:
			objective_controller = DerelictObjectiveControllerScript.create()
		objective_controller.apply_summary(obj_summary as Dictionary)
	var looted_variant: Variant = summary.get("looted_containers", null)
	if typeof(looted_variant) == TYPE_ARRAY:
		looted_container_ids = []
		for cid in (looted_variant as Array):
			looted_container_ids.append(String(cid))
	var corpse_variant: Variant = summary.get("pending_corpse_loot", null)
	if typeof(corpse_variant) == TYPE_ARRAY:
		pending_corpse_loot = []
		for entry in (corpse_variant as Array):
			if typeof(entry) == TYPE_DICTIONARY:
				pending_corpse_loot.append((entry as Dictionary).duplicate(true))
	var bypassed_variant: Variant = summary.get("bypassed_hatches", null)
	if typeof(bypassed_variant) == TYPE_ARRAY:
		bypassed_hatch_ids = []
		for hid in (bypassed_variant as Array):
			bypassed_hatch_ids.append(String(hid))
	var unlocked_portals_variant: Variant = summary.get("authored_unlocked_portals", null)
	if typeof(unlocked_portals_variant) == TYPE_ARRAY:
		authored_unlocked_portal_ids = []
		for portal_id in (unlocked_portals_variant as Array):
			authored_unlocked_portal_ids.append(String(portal_id))
	var open_portals_variant: Variant = summary.get("authored_open_portals", null)
	if typeof(open_portals_variant) == TYPE_ARRAY:
		authored_open_portal_ids = []
		for portal_id in (open_portals_variant as Array):
			authored_open_portal_ids.append(String(portal_id))
	if summary.has("combat"):
		combat_summary = restored_combat_summary
	var access_summary: Variant = summary.get("access", null)
	if typeof(access_summary) == TYPE_DICTIONARY and not (access_summary as Dictionary).is_empty():
		get_access().apply_summary(access_summary as Dictionary)
	var hangar_summary: Variant = summary.get("hangar", null)
	if typeof(hangar_summary) == TYPE_DICTIONARY and not (hangar_summary as Dictionary).is_empty():
		get_hangar().apply_summary(hangar_summary as Dictionary)
	inventory = restored_inventory
	carts = restored_carts
	floor_drop_sequence = int(restored_floor.sequence)
	floor_drop_descriptors = (restored_floor.drops as Dictionary).duplicate(true)
	pending_outputs = restored_pending
	var fire_summary: Variant = summary.get("fire", null)
	if typeof(fire_summary) == TYPE_DICTIONARY and not (fire_summary as Dictionary).is_empty():
		get_fire().apply_summary(fire_summary as Dictionary)
	var arc_variant: Variant = summary.get("arc", null)
	if typeof(arc_variant) == TYPE_DICTIONARY:
		arc_summary = (arc_variant as Dictionary).duplicate(true)
	fire_seeded = bool(summary.get("fire_seeded", fire_seeded))
	breach_seeded = bool(summary.get("breach_seeded", breach_seeded))
	var breach_environment_variant: Variant = summary.get("breach_environment", null)
	if typeof(breach_environment_variant) == TYPE_DICTIONARY:
		breach_environment_summary = (breach_environment_variant as Dictionary).duplicate(true)
	var hull_summary: Variant = summary.get("hull", null)
	if typeof(hull_summary) == TYPE_DICTIONARY and not (hull_summary as Dictionary).is_empty():
		get_hull().apply_summary(hull_summary as Dictionary)
	var web_summary: Variant = summary.get("web", null)
	if typeof(web_summary) == TYPE_DICTIONARY and not (web_summary as Dictionary).is_empty():
		get_web().apply_summary(web_summary as Dictionary)
	elif summary.has("web_attached"):
		get_web().attached_to_web = bool(summary.get("web_attached", true))
	last_sim_time = float(summary.get("last_sim_time", 0.0))
	# PKG-D6.1: pillar sparse packs (empty/missing = pristine regenerate-from-seed).
	var mi_variant: Variant = summary.get("module_integrity", null)
	if typeof(mi_variant) == TYPE_DICTIONARY:
		module_integrity_summary = (mi_variant as Dictionary).duplicate(true)
	if summary.has("component_placement"):
		component_placement_summary = restored_component_summary.duplicate(true)
	return true

## Returns this ship's DerelictObjectiveController, creating it on first access.
func get_objective_controller():
	if objective_controller == null:
		objective_controller = DerelictObjectiveControllerScript.create()
	return objective_controller

## Returns this ship's ShipAccessState, creating it on first access.
func get_access():
	if access == null:
		access = ShipAccessStateScript.create()
	return access

## Returns this ship's HangarBay, creating an empty (0-slot) one on first access.
func get_hangar():
	if hangar == null:
		hangar = HangarBayScript.create(0, 0)
	return hangar

## True iff this ship has a configured bay (at least one slot).
func has_hangar() -> bool:
	return hangar != null and hangar.slot_count > 0

## Returns this ship's ShipInventory cargo hold, creating an empty one on first access.
func get_inventory():
	if inventory == null:
		inventory = ShipInventoryScript.create(ShipInventoryScript.MAX_WEIGHT_DEFAULT, _cargo_namespace(ship_id))
	return inventory


func get_pending_output_store():
	if pending_outputs == null:
		pending_outputs = PendingOutputStoreScript.new()
		pending_outputs.configure(ship_id)
	return pending_outputs

## True iff this ship's hold exists and holds at least one item.
func has_cargo() -> bool:
	return inventory != null and not inventory.items.is_empty()

## Returns this ship's FireSuppressionState, creating a bare one on first access.
## The coordinator configures it from tuning before seeding/use.
func get_fire():
	if fire == null:
		fire = FireSuppressionStateScript.new()
	return fire

## True iff this ship has at least one burning compartment.
func has_fire() -> bool:
	return fire != null and not fire.get_burning_compartments().is_empty()

## Returns this ship's HullIntegrityState, creating a bare one on first access.
## The coordinator configures it from tuning before seeding/use.
func get_hull():
	if hull == null:
		hull = HullIntegrityStateScript.new()
	return hull

## True iff this ship has a configured hull (at least one compartment).
func has_hull() -> bool:
	return hull != null and not hull.compartments.is_empty()

## Returns this ship's WebInfestationState, creating a bare one on first access.
## The coordinator configures it from tuning before seeding/use.
func get_web():
	if web == null:
		web = WebInfestationStateScript.new()
	return web

## True iff this ship is still in contact with the biomatter web (web model is authoritative).
func is_web_attached() -> bool:
	return get_web().attached_to_web

## Returns this ship's live carts array (parked carts).
func get_carts() -> Array:
	return carts

func allocate_floor_drop_id() -> String:
	floor_drop_sequence += 1
	return "%s/work-yield-%06d" % [ship_id, floor_drop_sequence]

func upsert_floor_drop_descriptor(descriptor: Dictionary) -> bool:
	var validated: Dictionary = _validated_floor_drop_descriptor(descriptor, ship_id)
	var descriptor_sequence: int = _drop_sequence_from_id(str(validated.get("drop_id", "")), ship_id)
	if validated.is_empty() or descriptor_sequence <= 0 or descriptor_sequence > floor_drop_sequence:
		return false
	floor_drop_descriptors[str(validated.drop_id)] = validated
	return true

func remove_floor_drop(drop_id: String) -> void:
	floor_drop_descriptors.erase(drop_id)

func get_floor_drop_summary() -> Dictionary:
	var ids: Array = floor_drop_descriptors.keys()
	ids.sort()
	var drops: Array = []
	for drop_id in ids:
		drops.append((floor_drop_descriptors[drop_id] as Dictionary).duplicate(true))
	return {
		"schema": "ship-floor-drops-1",
		"ship_id": ship_id,
		"sequence": floor_drop_sequence,
		"drops": drops,
	}


func apply_floor_drop_summary(summary: Dictionary) -> bool:
	var restored: Dictionary = _validated_floor_drop_summary(summary, ship_id)
	if not bool(restored.get("ok", false)):
		return false
	floor_drop_sequence = int(restored.sequence)
	floor_drop_descriptors = (restored.drops as Dictionary).duplicate(true)
	return true

static func transform_to_summary(value: Transform3D) -> Array:
	return [
		value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
		value.origin.x, value.origin.y, value.origin.z,
	]

static func transform_from_summary(value: Variant) -> Transform3D:
	var v: Array = value as Array
	return Transform3D(
		Basis(
			Vector3(float(v[0]), float(v[1]), float(v[2])),
			Vector3(float(v[3]), float(v[4]), float(v[5])),
			Vector3(float(v[6]), float(v[7]), float(v[8]))),
		Vector3(float(v[9]), float(v[10]), float(v[11])))

static func _cargo_namespace(owner_ship_id: String) -> String:
	return "ship:%s:cargo" % owner_ship_id

static func _validated_floor_drop_summary(raw: Variant, owner_ship_id: String) -> Dictionary:
	if not (raw is Dictionary):
		return {"ok": false}
	var d: Dictionary = raw as Dictionary
	var raw_sequence: Variant = d.get("sequence", null)
	var raw_drops: Variant = d.get("drops", null)
	if str(d.get("schema", "")) != "ship-floor-drops-1" \
			or str(d.get("ship_id", "")) != owner_ship_id \
			or not _is_nonnegative_integer(raw_sequence) \
			or not (raw_drops is Array):
		return {"ok": false}
	var drops: Dictionary = {}
	for raw_drop in raw_drops as Array:
		if not (raw_drop is Dictionary):
			return {"ok": false}
		var descriptor: Dictionary = _validated_floor_drop_descriptor(raw_drop as Dictionary, owner_ship_id)
		var drop_id: String = str(descriptor.get("drop_id", ""))
		var drop_sequence: int = _drop_sequence_from_id(drop_id, owner_ship_id)
		if descriptor.is_empty() or drops.has(drop_id) or drop_sequence <= 0 or drop_sequence > int(raw_sequence):
			return {"ok": false}
		drops[drop_id] = descriptor
	return {"ok": true, "sequence": int(raw_sequence), "drops": drops}

static func _validated_floor_drop_descriptor(raw: Dictionary, owner_ship_id: String) -> Dictionary:
	var drop_id: String = str(raw.get("drop_id", ""))
	var transform_summary: Variant = raw.get("transform", null)
	var lots: Variant = raw.get("item_lots_v1", null)
	if owner_ship_id.is_empty() or not drop_id.begins_with("%s/work-yield-" % owner_ship_id) \
			or str(raw.get("ship_id", "")) != owner_ship_id \
			or not _is_transform_summary(transform_summary) or not (lots is Dictionary):
		return {}
	var ledger = ItemLotLedgerScript.new({}, "floor:%s" % drop_id)
	if not ledger.apply_summary(lots as Dictionary, "floor:%s" % drop_id) \
			or ledger.get_quantities().is_empty():
		return {}
	var result: Dictionary = {
		"drop_id": drop_id,
		"ship_id": owner_ship_id,
		"transform": (transform_summary as Array).duplicate(),
		"item_lots_v1": ledger.get_summary(),
	}
	var pending_receipt_id: String = str(raw.get("pending_receipt_id", ""))
	if not pending_receipt_id.is_empty():
		result["pending_receipt_id"] = pending_receipt_id
	return result

static func _is_transform_summary(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 12:
		return false
	for component in value as Array:
		if (typeof(component) != TYPE_INT and typeof(component) != TYPE_FLOAT) \
				or not is_finite(float(component)):
			return false
	return true

static func _is_nonnegative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 \
			or typeof(value) == TYPE_FLOAT and is_finite(float(value)) \
				and float(value) == floorf(float(value)) and float(value) >= 0.0

static func _drop_sequence_from_id(drop_id: String, owner_ship_id: String) -> int:
	var prefix: String = "%s/work-yield-" % owner_ship_id
	if not drop_id.begins_with(prefix):
		return -1
	var suffix: String = drop_id.substr(prefix.length())
	return int(suffix) if suffix.is_valid_int() else -1

## A "working vessel" can be piloted: its own propulsion system is operational.
func is_working_vessel() -> bool:
	return systems_manager != null and systems_manager.is_operational("propulsion")

## Validation/runtime seam: the layout dict this ship's scene_root was built from.
func blueprint_layout_for_validation() -> Dictionary:
	return built_layout

## World-space AABB enclosing this ship's interior, derived from the built
## ShipStructure's room-node LOCAL positions (robust off-tree / headless, where
## VisualInstance3D world AABBs are unresolved). The merged local AABB is
## transformed by scene_root's world transform.
##
## Null/empty scene_root or no room nodes -> zero-size AABB at the root origin
## (the "unbuilt retained instance" fallback).
func interior_aabb() -> AABB:
	if not is_instance_valid(scene_root):
		return AABB()
	var structure: Node = scene_root.get_node_or_null("ShipStructure")
	if structure == null:
		for c in scene_root.get_children():
			if c.get_child_count() > 0:
				structure = c
				break
	var local := AABB()
	var seeded := false
	if structure != null:
		for room_node in structure.get_children():
			if not (room_node is Node3D):
				continue
			var p: Vector3 = (room_node as Node3D).position
			var box := AABB(p - Vector3(ROOM_HALF_EXTENT, ROOM_HALF_HEIGHT, ROOM_HALF_EXTENT),
				Vector3(ROOM_HALF_EXTENT, ROOM_HALF_HEIGHT, ROOM_HALF_EXTENT) * 2.0)
			if not seeded:
				local = box
				seeded = true
			else:
				local = local.merge(box)
	if not seeded:
		var o: Vector3 = scene_root.global_position if scene_root.is_inside_tree() else scene_root.position
		return AABB(o, Vector3.ZERO)
	var xform: Transform3D = scene_root.global_transform if scene_root.is_inside_tree() else Transform3D(Basis(), scene_root.position)
	return xform * local
