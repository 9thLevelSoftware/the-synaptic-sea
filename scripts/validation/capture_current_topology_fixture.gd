extends SceneTree

## Reproducible current-topology capture. Requires exactly one explicit output path.
## It never writes historical focused-nine evidence.
const BP=preload("res://scripts/procgen/ship_blueprint.gd")
const SG=preload("res://scripts/procgen/ship_generator.gd")
const SV=preload("res://scripts/procgen/structural_plan_validator.gd")
func _initialize():
 var b=BP.new(BP.Size.SMALL,BP.Condition.WRECKED,17); b.room_count_range=Vector2i(5,8)
 var a=JSON.parse_string(FileAccess.get_file_as_string("res://data/procgen/archetypes/derelict.json")); a["guaranteed_roles"]=[]; a["template"]="compact"
 var g=SG.new().generate(b,a); var layout:Dictionary=g.get_layout_copy(); var plan:Dictionary=layout.get("structural_plan",{}); var vr:Dictionary=SV.new().validate(plan,layout)
 var by={}; for p in plan.get("placements",[]): by[str(p.get("placement_id",""))]=p
 var ws=[]; var errs=[]; _walk(g.get_node_or_null("StructuralRoot"),by,ws,errs)
 var expected={}; for p in plan.get("placements",[]): expected[str(p.get("placement_id",""))]=1
 var actual={}; for w in ws: actual[str(w.get("placement_id",""))]=int(actual.get(str(w.get("placement_id","")),0))+1
 if ws.size()!=expected.size(): errs.append("wrapper count mismatch expected=%d actual=%d"%[expected.size(),ws.size()])
 for id in expected: if not actual.has(id): errs.append("missing wrapper "+id)
 for id in actual: if not expected.has(id): errs.append("unexpected wrapper "+id)
 for id in actual: if actual[id]!=1: errs.append("duplicate wrapper "+id)
 var flags={"canonical_validator":bool(vr.get("ok",false)),"validator_errors":vr.get("errors",[]),"edge_keys_unique":_unique_edges(plan),"portal_endpoints_valid":_portal_valid(plan),"no_portal_wall_overlap":_no_overlap(plan),"negative_duplicate_edge_probe":_negative_duplicate_edge_probe(plan),"negative_portal_wall_probe":_negative_portal_wall_probe(plan),"negative_endpoint_probe":_negative_endpoint_probe(plan),"real_wrapper_checks":errs.is_empty(),"wrapper_errors":errs,"placement_count":plan.get("placements",[]).size(),"wrapper_count":ws.size(),"topology_portal_records":plan.get("portals",[]).size(),"structural_portal_edges":_portal_count(plan),"wrapped_portal_placements":_wrapped_portal_count(plan),"optional_unwrapped_portals":_portal_count(plan)-_wrapped_portal_count(plan)}
 if not flags.canonical_validator or not flags.edge_keys_unique or not flags.portal_endpoints_valid or not flags.no_portal_wall_overlap or not flags.negative_duplicate_edge_probe or not flags.negative_portal_wall_probe or not flags.negative_endpoint_probe or not flags.real_wrapper_checks: print("CANDIDATE FAIL "+JSON.stringify(flags)); quit(1); return
 var out={"schema":"focused_nine_current_candidate_v2","capture_id":"CurrentFocusedNine","seed":17,"size":"SMALL","condition":"WRECKED","room_count_range":[5,8],"archetype":{"template":"compact","guaranteed_roles":[]},"rooms":layout.get("rooms",[]).size(),"occupancy":plan.get("occupancy",{}),"edges":plan.get("edges",{}),"placements":_serialise_placements(plan.get("placements",[])),"wrapper_metadata":ws,"validation":flags,"source_plan_errors":plan.get("errors",[])}
 var args: PackedStringArray = OS.get_cmdline_user_args()
 if args.size() != 1 or str(args[0]).strip_edges().is_empty():
  print("CURRENT TOPOLOGY CAPTURE FAIL reason=explicit output path required")
  g.free()
  quit(1)
  return
 var requested_path: String = str(args[0]).strip_edges().replace("\\", "/")
 if requested_path.is_empty() or (not requested_path.begins_with("res://") and requested_path.is_absolute_path()) or requested_path.contains(".."):
  print("CURRENT TOPOLOGY CAPTURE FAIL reason=output path must be project-relative without traversal")
  g.free()
  quit(1)
  return
 var resource_path: String = requested_path if requested_path.begins_with("res://") else "res://" + requested_path.trim_prefix("./")
 var absolute_path: String = ProjectSettings.globalize_path(resource_path).simplify_path().replace("\\", "/")
 var project_root: String = ProjectSettings.globalize_path("res://").simplify_path().replace("\\", "/").trim_suffix("/")
 var historical_root: String = project_root + "/artifacts/validation-previews/focused-nine"
 var golden_root: String = project_root + "/data/procgen/golden"
 # Windows containment is case-insensitive; fold only comparison values.
 var compare_path: String = absolute_path.to_lower()
 var compare_project_root: String = project_root.to_lower()
 var compare_historical_root: String = historical_root.to_lower()
 var compare_golden_root: String = golden_root.to_lower()
 if not compare_path.begins_with(compare_project_root + "/") or compare_path == compare_historical_root or compare_path.begins_with(compare_historical_root + "/") or compare_path == compare_golden_root or compare_path.begins_with(compare_golden_root + "/"):
  print("CURRENT TOPOLOGY CAPTURE FAIL reason=protected historical or golden path")
  g.free()
  quit(1)
  return
 if FileAccess.file_exists(resource_path):
  print("CURRENT TOPOLOGY CAPTURE FAIL reason=refusing to overwrite existing output")
  g.free()
  quit(1)
  return
 var file: FileAccess = FileAccess.open(resource_path, FileAccess.WRITE)
 if file == null:
  print("CURRENT TOPOLOGY CAPTURE FAIL reason=output path unavailable")
  g.free()
  quit(1)
  return
 file.store_string(JSON.stringify(out, "  "))
 file.close()
 print("CURRENT TOPOLOGY CAPTURE PASS placements=%d wrappers=%d portals=%d" % [ws.size(), ws.size(), _portal_count(plan)])
 g.free()
 quit(0)
func _walk(n,by,ws,errs):
 if n==null:return
 if n.has_meta("structural_placement_id"):
  var id=str(n.get_meta("structural_placement_id","")); if not by.has(id): errs.append("unexpected wrapper "+id)
  else:
   var p:Dictionary=by[id]; var pos=_pos(p.get("position",[])); var ok=true
   if pos.size()!=3 or not (n as Node3D).position.is_equal_approx(Vector3(pos[0],pos[1],pos[2])): errs.append("position mismatch "+id); ok=false
   if not is_equal_approx(float((n as Node3D).rotation_degrees.y),float(p.get("yaw_degrees",0.0))): errs.append("yaw mismatch "+id); ok=false
   if str(n.get_meta("module_kind",""))!=str(p.get("module_id","")): errs.append("module mismatch "+id); ok=false
   if str(n.get_meta("structural_edge_key",""))!=str(p.get("edge_key","")): errs.append("edge mismatch "+id); ok=false
   if str(n.get_meta("structural_kind",""))!=str(p.get("kind","")): errs.append("kind mismatch "+id); ok=false
   if not _arr_eq(n.get_meta("structural_room_ids",[]),p.get("room_ids",[])): errs.append("room ids mismatch "+id); ok=false
   if ok: ws.append({"placement_id":id,"edge_key":str(p.get("edge_key","")),"kind":str(p.get("kind","")),"state":str(p.get("state","")),"module_id":str(p.get("module_id","")),"position":pos,"yaw_degrees":p.get("yaw_degrees",0.0),"room_ids":p.get("room_ids",[])})
 for c in n.get_children(): _walk(c,by,ws,errs)
func _serialise_placements(source: Array) -> Array:
 var records: Array = []
 for placement_variant in source:
  if not (placement_variant is Dictionary):
   continue
  var placement: Dictionary = (placement_variant as Dictionary).duplicate(true)
  placement["position"] = _pos(placement.get("position", []))
  records.append(placement)
 return records

func _pos(v):
 if v is Array:return v
 var s=str(v).strip_edges().trim_prefix("(").trim_suffix(")"); var a=s.split(","); return [float(a[0]),float(a[1]),float(a[2])] if a.size()>=3 else []
func _arr_eq(a,b):
 if not a is Array or not b is Array or a.size()!=b.size():return false
 for i in a.size(): if str(a[i])!=str(b[i]):return false
 return true
func _unique_edges(plan: Dictionary) -> bool:
 var seen: Dictionary = {}
 for placement_variant in plan.get("placements", []):
  if not placement_variant is Dictionary:
   return false
  var edge_key: String = str((placement_variant as Dictionary).get("edge_key", ""))
  if edge_key.is_empty() or seen.has(edge_key):
   return false
  seen[edge_key] = true
 return true

func _portal_valid(plan: Dictionary) -> bool:
 var edges: Dictionary = plan.get("edges", {})
 var occupancy: Dictionary = plan.get("occupancy", {})
 var wrapped: Dictionary = {}
 for placement_variant in plan.get("placements", []):
  if placement_variant is Dictionary:
   wrapped[str((placement_variant as Dictionary).get("edge_key", ""))] = true
 var portal_seen: Dictionary = {}
 for key_variant in edges.keys():
  var key: String = str(key_variant)
  var edge_variant: Variant = edges[key_variant]
  if not (edge_variant is Dictionary):
   return false
  var edge: Dictionary = edge_variant
  if not bool(edge.get("portal", false)):
   continue
  if portal_seen.has(key) or str(edge.get("edge_key", "")) != key or str(edge.get("key", "")) != key:
   return false
  portal_seen[key] = true
  var owner: String = str(edge.get("owner_room", ""))
  var other: String = str(edge.get("other_room", ""))
  if owner.is_empty() or other.is_empty() or owner == other:
   return false
  var cells_variant: Variant = edge.get("source_cells", [])
  if not (cells_variant is Array):
   return false
  var cells: Array = cells_variant
  if cells.size() != 2:
   return false
  var first: Array = _cell_coords(cells[0])
  var second: Array = _cell_coords(cells[1])
  if first.size() != 3 or second.size() != 3:
   return false
  var first_deck: int = int(first[2])
  var second_deck: int = int(second[2])
  var dx: int = abs(int(first[0]) - int(second[0]))
  var dy: int = abs(int(first[1]) - int(second[1]))
  if first_deck != second_deck or dx + dy != 1:
   return false
  var first_owner: String = _occupancy_owner(occupancy, first)
  var second_owner: String = _occupancy_owner(occupancy, second)
  if not ((first_owner == owner and second_owner == other) or (first_owner == other and second_owner == owner)):
   return false
  if _edge_key_for_cells(first, second) != key:
   return false
  if bool(edge.get("wrapper_required", false)) and not wrapped.has(key):
   return false
 return not portal_seen.is_empty()

func _cell_coords(value: Variant) -> Array:
 if value is Vector2i:
  var vector: Vector2i = value
  return [vector.x, vector.y, 0]
 if value is Array:
  var values: Array = value
  if values.size() >= 3:
   return [int(values[0]), int(values[1]), int(values[2])]
  if values.size() == 2:
   return [int(values[0]), int(values[1]), 0]
 return []

func _occupancy_owner(occupancy: Dictionary, coords: Array) -> String:
 if coords.size() != 3:
  return ""
 var lookup: String = "%d|%d|%d" % [int(coords[2]), int(coords[0]), int(coords[1])]
 if not occupancy.has(lookup) or not (occupancy[lookup] is Dictionary):
  return ""
 return str((occupancy[lookup] as Dictionary).get("room_id", ""))

func _edge_key_for_cells(first: Array, second: Array) -> String:
 var deck: int = int(first[2])
 var x: int = int(first[0])
 var y: int = int(first[1])
 if x == int(second[0]):
  return "%d|h|%d|%d" % [deck, mini(y, int(second[1])), x]
 return "%d|v|%d|%d" % [deck, y, mini(x, int(second[0]))]

func _portal_count(plan: Dictionary) -> int:
 var count: int = 0
 var edges: Dictionary = plan.get("edges", {})
 for edge_variant in edges.values():
  if edge_variant is Dictionary and bool((edge_variant as Dictionary).get("portal", false)):
   count += 1
 return count

func _wrapped_portal_count(plan: Dictionary) -> int:
 var count: int = 0
 for placement_variant in plan.get("placements", []):
  if placement_variant is Dictionary and bool((placement_variant as Dictionary).get("portal", false)):
   count += 1
 return count

func _no_overlap(plan: Dictionary) -> bool:
 var seen_edges: Dictionary = {}
 for placement_variant in plan.get("placements", []):
  if not placement_variant is Dictionary:
   return false
  var placement: Dictionary = placement_variant
  var edge_key: String = str(placement.get("edge_key", ""))
  var is_portal: bool = bool(placement.get("portal", false))
  if seen_edges.has(edge_key):
   var previous_portal: bool = bool(seen_edges[edge_key])
   if previous_portal or is_portal:
    return false
  seen_edges[edge_key] = is_portal
 return true

func _negative_duplicate_edge_probe(plan: Dictionary) -> bool:
 var duplicate_plan: Dictionary = plan.duplicate(true)
 var placements: Array = duplicate_plan.get("placements", [])
 if placements.is_empty():
  return false
 placements.append((placements[0] as Dictionary).duplicate(true))
 duplicate_plan["placements"] = placements
 return not _unique_edges(duplicate_plan)

func _negative_portal_wall_probe(plan: Dictionary) -> bool:
 var overlap_plan: Dictionary = plan.duplicate(true)
 var placements: Array = overlap_plan.get("placements", [])
 var portal_index: int = -1
 for index in placements.size():
  if bool((placements[index] as Dictionary).get("portal", false)):
   portal_index = index
   break
 if portal_index < 0:
  return false
 var wall: Dictionary = (placements[portal_index] as Dictionary).duplicate(true)
 wall["portal"] = false
 wall["kind"] = "SOLID"
 wall["state"] = "SOLID"
 placements.append(wall)
 overlap_plan["placements"] = placements
 return not _no_overlap(overlap_plan)
func _negative_endpoint_probe(plan: Dictionary) -> bool:
 var bad: Dictionary = plan.duplicate(true)
 var edges: Dictionary = bad.get("edges", {})
 for key_variant in edges.keys():
  var edge_variant: Variant = edges[key_variant]
  if edge_variant is Dictionary and bool((edge_variant as Dictionary).get("portal", false)):
   var source_cells: Array = (edge_variant as Dictionary).get("source_cells", []).duplicate(true)
   if source_cells.size() != 2:
    return false
   var original: Array = _cell_coords(source_cells[1])
   if original.size() != 3:
    return false
   # Mutate an endpoint coordinate outside occupancy; room labels stay intact so the
   # probe proves endpoint ownership/geometry validation rather than string checks.
   source_cells[1] = [int(original[0]) + 100000, int(original[1]), int(original[2])]
   (edge_variant as Dictionary)["source_cells"] = source_cells
   return not _portal_valid(bad)
 return false

