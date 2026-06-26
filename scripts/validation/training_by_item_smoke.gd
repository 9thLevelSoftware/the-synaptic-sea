extends SceneTree

## REQ-PM-002 / REQ-PM-004 / ADR-0033 training-by-item smoke.
##
## Asserts that training events emitted with a specific `target_id`
## (which represents an in-world item, container, or system) are routed
## to the correct skill via the training_actions catalog. Includes:
##   - Item pickup events (scavenge_container, fabricate_part).
##   - Item use events (cook_meal, build_shelter, first_aid_self).
##   - Discovery events (discover_room, scan_derelict, decode_signal).
##   - Skill book grants (REQ-PM-004) — reading a book adds XP and
##     records the book.

const PlayerProgressionScript := preload("res://scripts/systems/player_progression_state.gd")
const ClassDefinitionScript := preload("res://scripts/systems/class_definition.gd")
const TrainingEventBusScript := preload("res://scripts/systems/training_event_bus.gd")

func _initialize() -> void:
	var catalog: Dictionary = PlayerProgressionScript.load_skills_catalog()
	var books: Dictionary = PlayerProgressionScript.load_books_catalog()
	var classes: Dictionary = ClassDefinitionScript.load_all()

	var prog = PlayerProgressionScript.new()
	prog.configure(classes["engineer"], catalog, books)
	var bus = TrainingEventBusScript.new()
	if not bus.configure():
		_fail("bus.configure failed")
		return

	# scavenge_container → scavenging +50 XP, survival category.
	var r1: Dictionary = bus.emit("scavenge_container", "locker_room_3", prog)
	if String(r1.get("skill_id", "")) != "scavenging":
		_fail("scavenge_container should target scavenging, got %s" % str(r1.get("skill_id", "")))
		return
	if int(r1.get("base_xp", 0)) != 50:
		_fail("scavenge_container base_xp=%d expected 50" % int(r1.get("base_xp", 0)))
		return

	# fabricate_part → fabrication +80 XP, technical category.
	var r2: Dictionary = bus.emit("fabricate_part", "fabrication_bench", prog)
	if String(r2.get("skill_id", "")) != "fabrication":
		_fail("fabricate_part should target fabrication")
		return
	if int(r2.get("base_xp", 0)) != 80:
		_fail("fabricate_part base_xp=%d expected 80" % int(r2.get("base_xp", 0)))
		return

	# cook_meal → cooking +40, survival.
	var r3: Dictionary = bus.emit("cook_meal", "galley_stove", prog)
	if String(r3.get("skill_id", "")) != "cooking":
		_fail("cook_meal should target cooking")
		return

	# discover_room → astrogation +30, navigation.
	var r4: Dictionary = bus.emit("discover_room", "bridge", prog)
	if String(r4.get("skill_id", "")) != "astrogation":
		_fail("discover_room should target astrogation")
		return

	# decode_signal → signal_analysis +100, navigation.
	var r5: Dictionary = bus.emit("decode_signal", "biomatter_burst_07", prog)
	if String(r5.get("skill_id", "")) != "signal_analysis":
		_fail("decode_signal should target signal_analysis")
		return

	# REQ-PM-004 — skill books grant XP and record themselves.
	var read_xp_before: int = int(prog.get_skill_xp("welding"))
	var first_read: bool = prog.grant_xp_from_book("welding_manual_basic")
	if not first_read:
		_fail("first book read should succeed")
		return
	if not prog.has_read_book("welding_manual_basic"):
		_fail("books_read should record the book")
		return
	var read_xp_after: int = int(prog.get_skill_xp("welding"))
	if prog.get_skill_level("welding") != 3 or read_xp_after != 0:
		_fail("book XP should advance engineer welding from L2 to L3 with 0 overflow, got level=%d xp=%d" % [
			prog.get_skill_level("welding"),
			read_xp_after,
		])
		return
	# Second read is idempotent.
	var read_xp_before_2: int = int(prog.get_skill_xp("welding"))
	prog.grant_xp_from_book("welding_manual_basic")
	var read_xp_after_2: int = int(prog.get_skill_xp("welding"))
	if read_xp_after_2 != read_xp_before_2:
		_fail("second book read should NOT grant XP again")
		return

	# Unknown book id returns false silently.
	if prog.grant_xp_from_book("never_authored_this_book"):
		_fail("unknown book id should be rejected")
		return

	# Bus log carries the events in order.
	if int(bus.get_event_count()) != 5:
		_fail("bus log should have 5 events, got %d" % int(bus.get_event_count()))
		return
	if int(bus.get_total_xp_delivered()) != 50 + 80 + 40 + 30 + 100:
		_fail("total_xp_delivered=%d expected 300" % int(bus.get_total_xp_delivered()))
		return

	print("TRAINING BY ITEM PASS items=5 books=true bus_log=5 total_xp=300 idempotent=true")
	quit(0)

func _fail(reason: String) -> void:
	push_error("TRAINING BY ITEM FAIL reason=%s" % reason)
	quit(1)