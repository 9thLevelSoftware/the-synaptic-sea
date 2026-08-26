extends Control
class_name ProcgenSeedLab

const ControllerScript := preload("res://scripts/procgen/seed_lab/procgen_seed_lab_controller.gd")
const ConsumerScript := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const Consumer := preload("res://scripts/procgen/procgen_bundle_consumer.gd")
const ValidatorScript := preload("res://scripts/procgen/procgen_manifest_validator.gd")
const DiagnosticScript := preload("res://scripts/procgen/seed_lab/procgen_diagnostic_bundle.gd")
const DiagnosticStoreScript := preload("res://scripts/procgen/seed_lab/procgen_diagnostic_store.gd")
const PromotionStoreScript := preload("res://scripts/procgen/seed_lab/procgen_promotion_store.gd")
const GraphViewScript := preload("res://scripts/procgen/seed_lab/procgen_seed_lab_graph_view.gd")
const DOMAINS: Array[String] = ["world", "mission", "topology", "navigation", "encounter", "item", "creature"]
const REQUEST_DOMAINS: Array[String] = ["world", "site", "gameplay", "presentation"]
const LOCK_FIELDS: Array[String] = [
	"world_seed", "site.site_id", "site.x", "site.y", "site.archetype_id",
	"site.kit_id", "site.intactness_override_bp", "site.loot_richness_bp",
	"site.cause_of_loss", "difficulty_id", "player_model", "presentation.seed",
	"presentation.locale",
]

var controller: RefCounted
var generator: Object
var consumer: RefCounted
var manifest_validator: RefCounted
var diagnostic_store: RefCounted
var promotion_store: RefCounted
var build_manifest: Dictionary = {}
var runtime_manifest: Dictionary = {}
var capabilities: Dictionary = {}
var active_slot: int = 0
var active_domain: String = "world"
var requested_domains: Dictionary = {"world": true, "site": true, "gameplay": true, "presentation": true}
var controls: Dictionary = {}
var graph_view: Control
var status_label: Label
var compare_label: Label
var inspector_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(960, 640)
	consumer = ConsumerScript.new()
	manifest_validator = ValidatorScript.new()
	diagnostic_store = DiagnosticStoreScript.new()
	promotion_store = PromotionStoreScript.new()
	_build_ui()
	_configure_runtime()

func _configure_runtime() -> void:
	if not ClassDB.class_exists("DerelictGenerator"):
		_set_status("Generator unavailable")
		return
	generator = ClassDB.instantiate("DerelictGenerator") as Object
	if generator == null: _set_status("Generator unavailable"); return
	var parsed_build: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/manifests/build/win64.json"))
	build_manifest = parsed_build as Dictionary if parsed_build is Dictionary else {}
	var runtime_parsed: Variant = JSON.parse_string(str(generator.generator_manifest()))
	runtime_manifest = runtime_parsed as Dictionary if runtime_parsed is Dictionary else {}
	var caps_parsed: Variant = JSON.parse_string(str(generator.capabilities()))
	capabilities = caps_parsed as Dictionary if caps_parsed is Dictionary else {}
	var verdict: String = manifest_validator.validate(build_manifest, generator)
	if verdict != ValidatorScript.OK:
		_set_status("Manifest rejected: %s" % verdict)
		return
	controller = ControllerScript.new()
	controller.configure(generator, consumer, build_manifest, runtime_manifest, capabilities)
	_set_status("Ready: authoritative Rust bundle consumer")

func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	var root_box := VBoxContainer.new()
	root_box.custom_minimum_size = Vector2(1180, 0)
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root_box)
	var title := Label.new(); title.text = "Synaptic Sea — Procedural Seed Laboratory"; title.add_theme_font_size_override("font_size", 22); root_box.add_child(title)
	status_label = Label.new(); status_label.text = "Starting…"; root_box.add_child(status_label)
	var slots := HBoxContainer.new(); root_box.add_child(slots)
	for slot: int in [0, 1]:
		var panel := VBoxContainer.new(); panel.custom_minimum_size = Vector2(250, 0); slots.add_child(panel)
		var heading := Label.new(); heading.text = "Slot %s" % ("A" if slot == 0 else "B"); panel.add_child(heading)
		var seed_edit := LineEdit.new(); seed_edit.text = str(424242 + slot); seed_edit.placeholder_text = "World seed"; panel.add_child(seed_edit); controls["seed_%d" % slot] = seed_edit
		var site_edit := LineEdit.new(); site_edit.text = "lab-site-%d" % slot; site_edit.placeholder_text = "Site identity"; panel.add_child(site_edit); controls["site_%d" % slot] = site_edit
		var x_edit := LineEdit.new(); x_edit.text = str(slot); x_edit.placeholder_text = "Site X"; panel.add_child(x_edit); controls["x_%d" % slot] = x_edit
		var y_edit := LineEdit.new(); y_edit.text = str(-slot); y_edit.placeholder_text = "Site Y"; panel.add_child(y_edit); controls["y_%d" % slot] = y_edit
		var kit_edit := LineEdit.new(); kit_edit.text = "ship_structural_v0"; kit_edit.placeholder_text = "Kit"; panel.add_child(kit_edit); controls["kit_%d" % slot] = kit_edit
		var intact_edit := LineEdit.new(); intact_edit.text = "9500"; intact_edit.placeholder_text = "Intactness bp"; panel.add_child(intact_edit); controls["intactness_%d" % slot] = intact_edit
		var cause_edit := LineEdit.new(); cause_edit.text = ""; cause_edit.placeholder_text = "Cause of loss"; panel.add_child(cause_edit); controls["cause_%d" % slot] = cause_edit
		var loot_edit := LineEdit.new(); loot_edit.text = "5000"; loot_edit.placeholder_text = "Loot richness bp"; panel.add_child(loot_edit); controls["loot_%d" % slot] = loot_edit
		var presentation_edit := LineEdit.new(); presentation_edit.text = str(424242 + slot); presentation_edit.placeholder_text = "Presentation seed"; panel.add_child(presentation_edit); controls["presentation_seed_%d" % slot] = presentation_edit
		var locale_edit := LineEdit.new(); locale_edit.text = "en-US"; locale_edit.placeholder_text = "Locale"; panel.add_child(locale_edit); controls["locale_%d" % slot] = locale_edit
		for signal_kind: String in ["combat_mastery", "damage_pressure", "resource_pressure", "objective_pace"]:
			var signal_edit := LineEdit.new(); signal_edit.text = "5000"; signal_edit.placeholder_text = signal_kind + " bp"; panel.add_child(signal_edit); controls["%s_%d" % [signal_kind, slot]] = signal_edit
		var archetype := OptionButton.new()
		for value: String in ["shuttle", "corvette", "freighter", "frigate"]:
			archetype.add_item(value)
		archetype.select(3)
		panel.add_child(archetype)
		controls["archetype_%d" % slot] = archetype
		var difficulty := OptionButton.new()
		for value: String in ["standard", "hardened", "deep_dive"]:
			difficulty.add_item(value)
		panel.add_child(difficulty)
		controls["difficulty_%d" % slot] = difficulty
		var generate := Button.new(); generate.text = "Generate Slot %s" % ("A" if slot == 0 else "B"); generate.pressed.connect(_on_generate.bind(slot, false)); panel.add_child(generate)
		var regenerate := Button.new(); regenerate.text = "Regenerate selected domains"; regenerate.pressed.connect(_on_generate.bind(slot, true)); panel.add_child(regenerate)
	var request_bar := HBoxContainer.new(); root_box.add_child(request_bar)
	for field: String in LOCK_FIELDS:
		var lock := CheckButton.new(); lock.text = "Lock %s" % field; lock.toggled.connect(func(value: bool, f: String = field) -> void: if controller != null: controller.get_model().set_lock(f, value)); request_bar.add_child(lock); controls["lock_%s" % field] = lock
	var domain_bar := HBoxContainer.new(); root_box.add_child(domain_bar)
	for domain: String in REQUEST_DOMAINS:
		var toggle := CheckButton.new(); toggle.text = "Request %s" % domain; toggle.button_pressed = true; toggle.toggled.connect(func(value: bool, d: String = domain) -> void: requested_domains[d] = value); domain_bar.add_child(toggle); controls["request_%s" % domain] = toggle
	var tabs := HBoxContainer.new(); root_box.add_child(tabs)
	for domain: String in DOMAINS:
		var tab := Button.new(); tab.text = domain.capitalize(); tab.pressed.connect(select_graph.bind(domain)); tabs.add_child(tab)
	graph_view = GraphViewScript.new(); graph_view.custom_minimum_size = Vector2(0, 300); graph_view.node_selected.connect(_on_graph_node_selected); root_box.add_child(graph_view)
	var actions := HBoxContainer.new(); root_box.add_child(actions)
	var compare := Button.new(); compare.text = "Compare A / B"; compare.pressed.connect(compare_slots); actions.add_child(compare)
	for classification: String in ["approved_candidate", "failure_seed", "authored_fallback"]:
		var save := Button.new(); save.text = "Save %s" % classification; save.pressed.connect(save_pending_promotion.bind(classification)); actions.add_child(save)
	var diagnostic := Button.new(); diagnostic.text = "Save diagnostic"; diagnostic.pressed.connect(save_diagnostic); actions.add_child(diagnostic)
	compare_label = Label.new(); compare_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root_box.add_child(compare_label)
	inspector_label = Label.new(); inspector_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; root_box.add_child(inspector_label)

func _on_generate(slot: int, selective: bool) -> void:
	active_slot = slot
	var request := request_for_slot(slot)
	if request.is_empty(): return
	var ok: bool = controller.regenerate(slot, request, _selected_request_domains()) if selective else controller.generate(slot, request)
	_set_status("Slot %s generated" % ("A" if slot == 0 else "B") if ok else "Generation failed: %s" % controller.last_error)
	_refresh_slot()

func request_for_slot(slot: int) -> Dictionary:
	if consumer == null: return {}
	var seed: int = int(str((controls.get("seed_%d" % slot) as LineEdit).text))
	var site_id := str((controls.get("site_%d" % slot) as LineEdit).text)
	var archetype := str((controls.get("archetype_%d" % slot) as OptionButton).get_item_text((controls.get("archetype_%d" % slot) as OptionButton).selected))
	var difficulty := str((controls.get("difficulty_%d" % slot) as OptionButton).get_item_text((controls.get("difficulty_%d" % slot) as OptionButton).selected))
	var signals: Array[Dictionary] = []
	for signal_kind: String in ["combat_mastery", "damage_pressure", "resource_pressure", "objective_pace"]:
		signals.append({"kind": signal_kind, "value_bp": clampi(int(str((controls["%s_%d" % [signal_kind, slot]] as LineEdit).text)), 0, 10000)})
	var request: Dictionary = consumer.build_request(seed, 0, 0, runtime_manifest, difficulty, archetype, site_id, int(str((controls["x_%d" % slot] as LineEdit).text)), int(str((controls["y_%d" % slot] as LineEdit).text)), signals, int(str((controls["presentation_seed_%d" % slot] as LineEdit).text)), str((controls["locale_%d" % slot] as LineEdit).text))
	if request.is_empty(): _set_status("Request rejected: %s" % consumer.last_error); return {}
	request.site.kit_id = str((controls["kit_%d" % slot] as LineEdit).text)
	request.site.intactness_override_bp = clampi(int(str((controls["intactness_%d" % slot] as LineEdit).text)), 0, 10000)
	var cause: String = str((controls["cause_%d" % slot] as LineEdit).text)
	request.site.cause_of_loss = null if cause.is_empty() else cause
	request.site.loot_richness_bp = clampi(int(str((controls["loot_%d" % slot] as LineEdit).text)), 0, 10000)
	request.requested_domains = _selected_request_domains()
	return request

func _selected_request_domains() -> Array[String]:
	var result: Array[String] = []
	for domain: String in REQUEST_DOMAINS:
		if bool(requested_domains.get(domain, false)): result.append(domain)
	return result if not result.is_empty() else REQUEST_DOMAINS.duplicate()

func select_graph(domain: String) -> bool:
	if not DOMAINS.has(domain): return false
	active_domain = domain
	_refresh_slot()
	return true

func toggle_lock(field: String, locked: bool) -> bool:
	return controller != null and controller.get_model().set_lock(field, locked)

func compare_slots() -> Dictionary:
	if controller == null: return {}
	var result: Dictionary = controller.get_model().compare()
	compare_label.text = "Compare: " + JSON.stringify(result)
	return result

func save_diagnostic() -> Dictionary:
	if controller == null: return {}
	var document: Dictionary = _diagnostic_for_active_slot()
	if document.is_empty(): return {}
	var result: Dictionary = diagnostic_store.save(document)
	_set_status("Diagnostic saved" if bool(result.get("saved", false)) else "Diagnostic rejected")
	return result

func save_pending_promotion(classification: String) -> Dictionary:
	var diagnostic: Dictionary = _diagnostic_for_active_slot()
	if diagnostic.is_empty(): return {}
	var slot: Dictionary = controller.get_model().get_slot(active_slot)
	var candidate: Dictionary = controller.get_model().build_promotion_candidate(classification, diagnostic, slot.get("request", {}))
	if candidate.is_empty(): _set_status("Promotion rejected: %s" % controller.get_model().last_error); return {}
	var result: Dictionary = promotion_store.save_pending(candidate)
	_set_status("Pending promotion saved" if bool(result.get("saved", false)) else "Promotion rejected")
	return result

func _diagnostic_for_active_slot() -> Dictionary:
	if controller == null: return {}
	var slot: Dictionary = controller.get_model().get_slot(active_slot)
	var builder: RefCounted = DiagnosticScript.new()
	if bool(slot.get("valid", false)):
		return builder.build_success(slot.bundle, build_manifest, runtime_manifest, capabilities)
	if slot.get("request", null) is Dictionary and slot.get("failure", null) is Dictionary \
			and str((slot.failure as Dictionary).get("schema_version", "")) == "procgen-failure-1":
		return builder.build_failure(slot.request, slot.failure)
	return {}

func _refresh_slot() -> void:
	if controller == null or graph_view == null: return
	var slot: Dictionary = controller.get_model().get_slot(active_slot)
	var graph: Dictionary = slot.get("graphs", {}).get(active_domain, {})
	if graph.is_empty(): graph = {"domain": active_domain, "nodes": [], "edges": [], "truncated": false}
	graph["domain"] = active_domain
	graph_view.set_graph(graph)
	var trace: Dictionary = controller.inspect(active_slot)
	inspector_label.text = "Inspector %s: %s" % [active_domain, JSON.stringify({"metrics": slot.get("metrics", {}), "validation_failures": slot.get("validation_failures", []), "trace": trace, "semantic_hash": slot.get("semantic_hash", ""), "build_manifest": build_manifest.get("manifest_schema", ""), "runtime_manifest": runtime_manifest.get("schema_version", "")})]

func _set_status(value: String) -> void:
	if status_label != null: status_label.text = value

func _on_graph_node_selected(id: String, payload: Dictionary) -> void:
	if inspector_label != null:
		inspector_label.text = "Selected %s / %s: %s" % [active_domain, id, JSON.stringify(payload)]
