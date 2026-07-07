extends SceneTree

## Tranche 6 (2026-07-06 audit HIGH, demo_scope_gate.gd:40): DemoScopeGate
## `is_allowed()` had ZERO production callsites — a demo build silently
## allowed every feature the manifest (data/release/demo_scope_manifest.json)
## says it restricts. REQ-RL-006 / ADR-0029 define the gate contract but
## delegated the enforcement sites; this smoke pins them:
##   - long_run.persistence  -> manual + auto saves refused past the authored
##                              play-time cap (existing saves kept — user
##                              decision 2026-07-07: refuse, never wipe)
##   - world_persistence.cross_run -> WorldSnapshot.visited_ships stripped in
##                              demo (per-run only)
##   - hub.meta_progression  -> hub purchase / class selection persistence
##                              blocked in menu_coordinator.meta_screen_confirm
##   - multi_hazard.run      -> derelict hazard seeding capped to
##                              params.max_hazards (seed order: breach, fire, arc)
##   - cargo_hold.full_inventory -> ship cargo hold max weight capped to
##                              params.max_weight_kg
##
## The repo ships build_kind="dev", so every enforcement is inert in normal
## builds — the smoke flips the SAME BuildMetadataState instance to "demo" at
## runtime (the gate reads build kind at call time) and asserts both sides.
##
## Pass marker: DEMO SCOPE ENFORCEMENT PASS dev_unaffected=true save_cap=true world_skip=true hub_blocked=true hazards_capped=true cargo_capped=true

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const TIMEOUT_FRAMES: int = 300

## Duck-typed stand-in for a visited ShipInstance. The snapshot builder calls
## get_summary(); dock-edge bookkeeping walks visited entries' parent_ship.
## Lets the smoke plant a NON-current visited entry — optionally one whose
## summary ship_id matches a snapshot reference (piloted/aboard/dock edge),
## which the demo strip must KEEP (PR #68 review, Codex P2).
class StubVisitedShip:
	var parent_ship = null
	var docked_ships: Array = []
	var summary_ship_id: String = ""
	func _init(p_ship_id: String = "") -> void:
		summary_ship_id = p_ship_id
	func get_summary() -> Dictionary:
		if summary_ship_id.is_empty():
			return {"stub": true}
		return {"ship_id": summary_ship_id}

var main_node: Node
var playable: PlayableGeneratedShip
var frame_count: int = 0
var finished: bool = false

func _initialize() -> void:
	main_node = MAIN_SCENE.instantiate()
	get_root().add_child(main_node)
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if finished:
		return
	frame_count += 1
	if not is_instance_valid(playable):
		playable = _find_playable(main_node)
	if not is_instance_valid(playable) or not is_instance_valid(playable.loader) \
			or not playable.loader.has_loaded_ship() or not playable.playable_started:
		if frame_count > TIMEOUT_FRAMES:
			_fail("playable not ready after %d frames" % frame_count)
		return
	_validate()

func _all_operational(mgr) -> void:
	for sid in ["power", "navigation", "scanners", "propulsion"]:
		var sys = mgr.get_system(sid)
		if sys == null:
			continue
		for sub in sys.subcomponents:
			mgr.force_repair(sid, sub.subcomponent_id)

func _validate() -> void:
	finished = true

	# --- The coordinator must own a configured gate (the audit's core gap) ---
	if not ("demo_scope_gate" in playable) or playable.demo_scope_gate == null:
		_fail("coordinator does not own a configured demo_scope_gate (zero production callsites)")
		return
	var gate = playable.demo_scope_gate
	# Dev build: every manifest feature allowed.
	for fid in ["cargo_hold.full_inventory", "multi_hazard.run", "long_run.persistence",
			"world_persistence.cross_run", "hub.meta_progression"]:
		if not gate.is_allowed(String(fid)):
			_fail("dev build must allow %s" % fid)
			return

	# --- dev_unaffected: saving far past the demo cap succeeds in dev ---
	playable.run_play_time_seconds = 99999.0
	if not playable.request_save():
		_fail("dev build refused a save past the demo play-time cap")
		return
	playable.run_play_time_seconds = 0.0

	# --- Flip the live BuildMetadataState to demo (gate reads kind at call time) ---
	playable.build_metadata_state.configure({
		"build_kind": "demo", "version": "v0.1.0", "store": "itch",
	})
	if gate.is_allowed("long_run.persistence"):
		_fail("demo flip did not take (gate still allows long_run.persistence)")
		return

	# --- save_cap: refused past the cap (with player feedback), allowed under it ---
	playable.run_play_time_seconds = 1201.0
	if playable.request_save():
		_fail("demo build allowed a manual save past max_play_seconds")
		return
	if not ("demo" in playable.get_last_loot_feedback_line_for_validation().to_lower()):
		_fail("save refusal produced no demo feedback line (got '%s')" % playable.get_last_loot_feedback_line_for_validation())
		return
	if playable._auto_save_current_run():
		_fail("demo build allowed an auto-save past max_play_seconds")
		return
	playable.run_play_time_seconds = 10.0
	if not playable.request_save():
		_fail("demo build refused a save UNDER the cap (over-blocking)")
		return

	# --- hub_blocked: meta progression persistence refused in demo ---
	var ui = playable.menu_coordinator
	if not is_instance_valid(ui):
		_fail("no menu_coordinator")
		return
	ui._active_meta_screen = "hub_upgrades"
	var hub_result: Dictionary = ui.meta_screen_confirm()
	if bool(hub_result.get("ok", true)) or str(hub_result.get("detail", "")) != "demo_blocked":
		_fail("demo hub purchase not blocked (got %s)" % str(hub_result))
		return
	ui._active_meta_screen = "class"
	var class_result: Dictionary = ui.meta_screen_confirm()
	if bool(class_result.get("ok", true)) or str(class_result.get("detail", "")) != "demo_blocked":
		_fail("demo class selection not blocked (got %s)" % str(class_result))
		return
	ui._active_meta_screen = ""

	# --- Board a derelict while in demo: hazard seeding capped, cargo capped ---
	_all_operational(playable.get_ship_systems_manager())
	var world = playable.get_synaptic_sea_world()
	var in_range: Array = world.markers_in_range(playable.scanner_state.range_radius)
	if in_range.is_empty():
		_fail("no markers in range")
		return
	var boarded: bool = false
	for m in in_range.slice(0, 4):
		if bool(playable.travel_to_marker_id(String(m.marker_id)).get("success", false)):
			boarded = true
			break
	if not boarded:
		_fail("travel_to_marker_id failed for the first 4 markers")
		return
	if not playable.away_from_start:
		_fail("travel succeeded but away_from_start is false")
		return
	if not ("_last_derelict_hazard_budget" in playable):
		_fail("coordinator records no derelict hazard budget (multi_hazard.run unenforced)")
		return
	if int(playable._last_derelict_hazard_budget) != 1:
		_fail("demo hazard budget should be 1, got %d" % int(playable._last_derelict_hazard_budget))
		return
	var seeded: Array = playable._last_derelict_hazards_seeded
	if "fire" in seeded or "arc" in seeded:
		_fail("demo derelict seeded beyond the hazard budget: %s" % str(seeded))
		return
	if not ("breach" in seeded):
		_fail("demo derelict skipped the first budgeted hazard: %s" % str(seeded))
		return
	var hold = playable.get_current_ship().get_inventory()
	if hold == null or absf(hold.get_max_weight() - 6.0) > 0.001:
		_fail("demo cargo hold not capped to 6.0 kg (got %s)" % (str(hold.get_max_weight()) if hold != null else "null"))
		return

	# --- world_skip: cross-run world state stripped from demo snapshots.
	# The currently-boarded ship's entry is deliberately KEPT (a same-run
	# away-save must still restore the derelict the player is standing in);
	# every OTHER visited ship must be stripped. A synthetic second entry
	# discriminates demo (stripped) from dev (persisted). ---
	var current_marker: String = String(playable.get_current_ship().marker_id)
	playable.visited_ships["synthetic_marker"] = StubVisitedShip.new()
	# PR #68 review (Codex P2): a visited ship the snapshot still REFERENCES
	# (piloted/aboard/dock edge — e.g. a claimed mobile derelict) must survive
	# the demo strip, or _apply_docking_snapshot cannot rebuild it on load.
	if playable.piloted_ship == null:
		_fail("no piloted ship while boarded (cannot exercise the referenced-ship keep)")
		return
	var piloted_id: String = String(playable.piloted_ship.ship_id)
	playable.visited_ships["synthetic_piloted_marker"] = StubVisitedShip.new(piloted_id)
	var ws_demo = playable._build_world_snapshot()
	if ws_demo == null:
		_fail("could not build a world snapshot")
		return
	if ws_demo.visited_ships.has("synthetic_marker"):
		_fail("demo world snapshot still carries a non-current visited ship (cross-run state persisted)")
		return
	if not ws_demo.visited_ships.has(current_marker):
		_fail("demo world snapshot dropped the CURRENT ship entry (away-save no longer restorable)")
		return
	if not ws_demo.visited_ships.has("synthetic_piloted_marker"):
		_fail("demo strip dropped a visited ship referenced by piloted_ship_id — docking unreconstructable after a demo load (Codex P2)")
		return

	# --- dev_unaffected (2): flip back to dev — all visited_ships persist again ---
	playable.build_metadata_state.configure({
		"build_kind": "dev", "version": "v0.1.0", "store": "itch",
	})
	var ws_dev = playable._build_world_snapshot()
	if ws_dev == null or not ws_dev.visited_ships.has("synthetic_marker") \
			or not ws_dev.visited_ships.has(current_marker):
		_fail("dev world snapshot lost visited_ships (strip is not demo-conditional)")
		return
	playable.visited_ships.erase("synthetic_marker")
	playable.visited_ships.erase("synthetic_piloted_marker")

	print("DEMO SCOPE ENFORCEMENT PASS dev_unaffected=true save_cap=true world_skip=true hub_blocked=true hazards_capped=true cargo_capped=true")
	_cleanup(0)

func _find_playable(node: Node) -> PlayableGeneratedShip:
	if node is PlayableGeneratedShip:
		return node as PlayableGeneratedShip
	for child in node.get_children():
		var found: PlayableGeneratedShip = _find_playable(child)
		if found != null:
			return found
	return null

func _fail(reason: String) -> void:
	push_error("DEMO SCOPE ENFORCEMENT FAIL reason=%s" % reason)
	finished = true
	_cleanup(1)

func _cleanup(code: int) -> void:
	if is_instance_valid(main_node):
		main_node.queue_free()
	quit(code)
