extends Resource
class_name ModularAssetSpec

@export var schema_version: String = "1.0.0"
@export var document_kind: String = "modular_asset_spec"
@export var asset_id: String = ""
@export var module_id: String = ""
@export var category: String = ""
@export var kit_id: String = ""
@export var module_family: String = ""
@export var grid_step_m: float = 4.0
@export var footprint_cells: Array[int] = []
@export var bounds: Dictionary = {}
@export var sockets: Array[Dictionary] = []
@export var collision: Dictionary = {}
@export var provenance: Dictionary = {}
@export var source_asset_path: String = ""
@export var wrapper_scene: String = ""
@export var contract_path: String = ""
@export var inspection_path: String = ""
@export var asset: Dictionary = {}
