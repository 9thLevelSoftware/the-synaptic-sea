extends RefCounted
class_name GeneratedWorldSiteIdentity
const SCHEMA := "generated-world-site-1"
const MAX_SEED := 9007199254740991
var site_id := ""; var x := 0; var y := 0; var derived_site_seed := 0; var structural_generator_version := 2; var base_bundle_semantic_hash := ""
static func _num(v:Variant,e:int)->bool:return typeof(v)!=TYPE_BOOL and (typeof(v)==TYPE_INT or typeof(v)==TYPE_FLOAT) and is_finite(float(v)) and float(v)==e
static func _hash(v:String)->bool:
	if v.length()!=64:return false
	for c in v:
		if not c in "0123456789abcdef":return false
	return true
func configure(id:String,px:int,py:int,seed:int,structural:Variant,semantic:String)->bool:
	if id.is_empty() or id.length()>128 or px< -2147483648 or px>2147483647 or py< -2147483648 or py>2147483647 or seed<0 or seed>MAX_SEED or not _num(structural,2) or not _hash(semantic):return false
	site_id=id;x=px;y=py;derived_site_seed=seed;base_bundle_semantic_hash=semantic;return true
func to_dict()->Dictionary:return {"schema_version":SCHEMA,"site_id":site_id,"x":x,"y":y,"derived_site_seed":derived_site_seed,"structural_generator_version":2,"base_bundle_semantic_hash":base_bundle_semantic_hash}
static func from_dict(v:Variant):
	if typeof(v)!=TYPE_DICTIONARY:return null
	var d:Dictionary=v;var r=load("res://scripts/systems/generated_world_site_identity.gd").new()
	return r if d.size()==7 and d.get("schema_version")==SCHEMA and typeof(d.get("site_id"))==TYPE_STRING and typeof(d.get("x"))==TYPE_INT and typeof(d.get("y"))==TYPE_INT and typeof(d.get("derived_site_seed"))==TYPE_INT and r.configure(d.site_id,d.x,d.y,d.derived_site_seed,d.get("structural_generator_version"),d.get("base_bundle_semantic_hash")) else null
