extends RefCounted
class_name ProcgenMutationDelta
const SCHEMA:="procgen-mutation-delta-1"
const OPS:={"door_lock":"door","door_open":"door","container_inventory":"container","entity_remove":"entity","objective":"objective","hazard":"hazard","system_state":"system"}
var base_site_id: String="";var base_semantic_hash:String="";var operations:Array[Dictionary]=[]
func configure(site_id:String,semantic:String,values:Array)->bool:
	if site_id.is_empty() or semantic.length()!=64 or values.size()>128:return false
	base_site_id=site_id;base_semantic_hash=semantic;operations.clear();var seen={}
	for raw in values:
		if not _valid(raw,seen):operations.clear();return false
		var op:Dictionary=raw;operations.append(op.duplicate(true));seen[str(op.target_kind)+":"+str(op.target_id)]=true
	return JSON.stringify(to_dict()).to_utf8_buffer().size()<=16384
func _valid(raw:Variant,seen:Dictionary)->bool:
	if typeof(raw)!=TYPE_DICTIONARY:return false
	var o:Dictionary=raw;var n=str(o.get("operation",""));var k=str(o.get("target_kind",""));var id=o.get("target_id")
	if o.size()!=4 or not OPS.has(n) or OPS[n]!=k or typeof(id)!=TYPE_STRING or str(id).is_empty() or str(id).length()>128 or seen.has(k+":"+str(id)) or typeof(o.get("payload"))!=TYPE_DICTIONARY:return false
	var p:Dictionary=o.payload
	if JSON.stringify(p).to_utf8_buffer().size()>4096:return false
	match n:
		"door_lock":return p.size()==1 and typeof(p.get("locked"))==TYPE_BOOL
		"door_open":return p.size()==1 and typeof(p.get("open"))==TYPE_BOOL
		"container_inventory":
			if p.size()!=1 or typeof(p.get("items"))!=TYPE_ARRAY or p.items.size()>64:return false
			var items={}
			for i in p.items:
				if typeof(i)!=TYPE_DICTIONARY or i.size()!=2 or typeof(i.get("item_id"))!=TYPE_STRING or items.has(i.get("item_id")) or typeof(i.get("quantity"))!=TYPE_INT or i.quantity<0 or i.quantity>65535:return false
				items[i.item_id]=true
			return true
		"entity_remove":return p.size()==1 and p.get("removed",null)==true
		"objective":return p.size()==1 and typeof(p.get("completed"))==TYPE_BOOL
		"hazard":return p.size()==1 and typeof(p.get("active"))==TYPE_BOOL
		"system_state":return p.size()==1 and typeof(p.get("state"))==TYPE_STRING and str(p.state).length()<=128 and str(p.state).is_valid_identifier()
	return false
func validate_targets(targets:Array)->bool:
	var seen={}
	for t in targets:
		if typeof(t)!=TYPE_DICTIONARY or t.size()!=2 or typeof(t.get("target_kind"))!=TYPE_STRING or typeof(t.get("target_id"))!=TYPE_STRING:return false
		seen[str(t.target_kind)+":"+str(t.target_id)]=true
	for o in operations:
		if not seen.has(str(o.target_kind)+":"+str(o.target_id)):return false
	return true
func to_dict()->Dictionary:return {"schema_version":SCHEMA,"base_site_id":base_site_id,"base_semantic_hash":base_semantic_hash,"operations":operations.duplicate(true)}
static func from_dict(v:Variant):
	if typeof(v)!=TYPE_DICTIONARY:return null
	var d:Dictionary=v;if d.size()!=4 or d.get("schema_version")!=SCHEMA or typeof(d.get("operations"))!=TYPE_ARRAY:return null
	var r=load("res://scripts/systems/procgen_mutation_delta.gd").new();return r if r.configure(d.get("base_site_id",""),d.get("base_semantic_hash",""),d.operations) else null
