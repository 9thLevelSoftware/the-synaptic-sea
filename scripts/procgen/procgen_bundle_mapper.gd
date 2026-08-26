extends RefCounted
class_name ProcgenBundleMapper

var last_error: String = ""

## Mechanical bridge: Rust may carry checked migration documents in the IR
## envelope. No records are synthesized here; absent documents are rejected.
func map_to_loader_documents(bundle: Dictionary) -> Dictionary:
	last_error = ""
	var site: Dictionary = bundle.get("site_ir", {})
	var gameplay_ir: Dictionary = bundle.get("gameplay_ir", {})
	var layout: Variant = site.get("legacy_layout", site.get("layout", null))
	var gameplay: Variant = gameplay_ir.get("legacy_slice", null)
	if not layout is Dictionary or not gameplay is Dictionary:
		last_error = "migration_documents_missing"
		return {}
	var presentation: Dictionary = bundle.get("presentation_ir", {})
	return {"layout": (layout as Dictionary).duplicate(true), "kit_id": str(presentation.get("kit_id", "")), "gameplay_slice": (gameplay as Dictionary).duplicate(true)}
