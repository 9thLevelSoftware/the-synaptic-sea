"""Fail-closed validation for the P17 structural-rebuild policy catalog."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

CATALOG_PATH = "data/construction/structural_rebuild_catalog.json"
CATALOG_KEYS = frozenset(("schema", "rows"))
ROW_KEYS = frozenset(("row_id", "active", "layout_kit_id", "structural_kit_id", "structural_contract_id", "original_structural_module_id", "replacement_structural_module_id", "replacement_wrapper_id", "footprint_cells", "socket_mapping", "action_id", "requirements"))
REQUIREMENT_KEYS = frozenset(("materials", "tool_class", "skill_id", "min_skill", "duration_seconds"))
SOCKET_MAPPING_KEYS = frozenset(("original_socket", "replacement_socket"))
BALANCE = {
    "floor_1x1": (8, {"plating": 1, "scrap_metal": 1}), "floor_2x1": (14, {"plating": 2, "scrap_metal": 2}), "corridor_floor_1x1": (8, {"plating": 1, "scrap_metal": 1}), "corridor_floor_1x2": (14, {"plating": 2, "scrap_metal": 2}), "wall_straight_1x1": (10, {"plating": 1, "scrap_metal": 2}), "wall_end_cap": (6, {"plating": 1, "scrap_metal": 1}), "wall_inner_corner": (12, {"plating": 2, "scrap_metal": 2}), "wall_outer_corner": (12, {"plating": 2, "scrap_metal": 2}), "wall_t_junction": (16, {"plating": 3, "scrap_metal": 3}), "doorway_frame_open_1x1": (12, {"plating": 1, "scrap_metal": 3}), "doorway_frame_blocked_1x1": (16, {"plating": 2, "scrap_metal": 3}), "bulkhead_portal_2x1": (22, {"plating": 3, "scrap_metal": 4, "wiring_spool": 1, "circuit_board": 1}), "ramp_up_1x2": (16, {"plating": 2, "scrap_metal": 3}), "pillar_support_1x1": (8, {"plating": 1, "scrap_metal": 2}), "ceiling_cap_1x1": (8, {"plating": 1, "scrap_metal": 1}),
}
MAPPING_SOURCE_HASHES = {
    "scripts/procgen/ship_layout_generator.gd": "a5b2f68680bf5c4d01527d350c2a7d778fcc82a1f130bbad6a6486b983cfdeb6", "scripts/procgen/ship_generator.gd": "551e4595142aee34981457a58a83dc48baa21b5839ca1f1db3552052952f2450", "data/procgen/templates/hive.json": "e728c75910f37e09c02727cf2542630bcdbd9032323ac51facd0308b94f2fdac", "data/kits/ship_structural_hazard.json": "02fe3d3f5d3334b9f663439900dfc42af698d5eb5d4781ace87e6b014f79c0f7", "data/kits/ship_structural_industrial.json": "c6aa22823a4c39885ec2a8b47109dcddf353b2eff4ac8b2c118ac50da9b9d474", "data/kits/ship_structural_biomatter.json": "1b5442c9bc5d2eb51bd1c3e60ef1583ac74fe0af677833cdb9dd06d710713f95",
}
# Frozen resource versions keep a live contract or wrapper drift from silently
# changing replacement authority.  The parser below also checks the live top-level fields.
RESOURCE_HASHES = {
    "data/placement/contracts/structural/ship_structural_v0/bulkhead_portal_2x1_contract.tres":"71b3fe6d8f0b43c38d70ee84427f747d088117f844a28be143ec1672784cfee6", "data/placement/contracts/structural/ship_structural_v0/ceiling_cap_1x1_contract.tres":"dab1d65bd02485d8410b5580c36e9805b7ec50a526af960859c93365a5276c90", "data/placement/contracts/structural/ship_structural_v0/corridor_floor_1x1_contract.tres":"e905001048ea7b8eb670b064e285b5c05ab45a3a45a35b5cf2bfc75fce0e5724", "data/placement/contracts/structural/ship_structural_v0/corridor_floor_1x2_contract.tres":"2167fec8df31b89befba214992aee013c2740664c04a1966947ea67eb04f5458", "data/placement/contracts/structural/ship_structural_v0/doorway_frame_blocked_1x1_contract.tres":"5f55b93048c976b5b0f3bd53f5c3f9781c87813dd23eb5f58386e6c7cdc83161", "data/placement/contracts/structural/ship_structural_v0/doorway_frame_open_1x1_contract.tres":"a5f2eab6fea40aec2194c9d1ad42c9b2e6178435779283613d8a3eedd1bb36b0", "data/placement/contracts/structural/ship_structural_v0/floor_1x1_contract.tres":"45245962ff9d8f07f9e2b233f73fccabd0d6c34273583ddc8761212678389a67", "data/placement/contracts/structural/ship_structural_v0/floor_2x1_contract.tres":"dc491fec35dafb5f1de9622d7178904061de699360fc5d2db52fecc361481d4c", "data/placement/contracts/structural/ship_structural_v0/pillar_support_1x1_contract.tres":"2915378ac306d7d1f4a108039cbfc0f91779eeb447f244da3b40c2d68874ea14", "data/placement/contracts/structural/ship_structural_v0/ramp_up_1x2_contract.tres":"53092546f9e006deff61efce63623d4dfaee586b09c86b6a4dd957faa381a568", "data/placement/contracts/structural/ship_structural_v0/wall_end_cap_contract.tres":"dcbb4c497c81ecd413b1dbb666da103b6c698c8401c01d61b77925be57198e93", "data/placement/contracts/structural/ship_structural_v0/wall_inner_corner_contract.tres":"74e0ab345f36ab87358b493e3c06f1d7904fe24d79053b981e36078f9aa270f9", "data/placement/contracts/structural/ship_structural_v0/wall_outer_corner_contract.tres":"77ee9629ff7bbe2a3095d9920e8cf903caba4d086d3b49886e16c1cd9e469c08", "data/placement/contracts/structural/ship_structural_v0/wall_straight_1x1_contract.tres":"275e64f944acf19a9b6dcb277403a3928a613135b421540c3183e26dfab2fac5", "data/placement/contracts/structural/ship_structural_v0/wall_t_junction_contract.tres":"f466503667981f5d626563c907ea4e7bff929a3f787057938409422a1f265500",
    "scenes/wrappers/structural/ship_structural_v0/bulkhead_portal_2x1.tscn":"298a11c3d9f2f7521275853466e59f49c052e813745c04862e37d53d2b0c4f3d", "scenes/wrappers/structural/ship_structural_v0/ceiling_cap_1x1.tscn":"5ee7f09137827d4670d78ac3609b102479e61f6bd1921d740959a410cffd660a", "scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1.tscn":"e750d2422dc60e2dba28f6a542d1bf9530e9a146df96028354623c95e3f7b487", "scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x2.tscn":"20610e87253de62aa072cbc13e64f5a55993509de3cc0556e14dde923ddcd277", "scenes/wrappers/structural/ship_structural_v0/doorway_frame_blocked_1x1.tscn":"272ab56e78d71480aa999bc5c2d1069da62cfc1eb0716ffa81adc4ea3f400232", "scenes/wrappers/structural/ship_structural_v0/doorway_frame_open_1x1.tscn":"43e0c432bad7e3cbd45550f9899721fa8a4ba5fddf4a833d18ef126df8ab0806", "scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn":"517d909f25f25ed63a652d377dbe00530e68c485b8ecc12448894b3d89325279", "scenes/wrappers/structural/ship_structural_v0/floor_2x1.tscn":"c8cb654127957375b3abfbf78ea74964fcf1e9dd68e530995726c59e38437c75", "scenes/wrappers/structural/ship_structural_v0/pillar_support_1x1.tscn":"c119d5c7685e793faf549ada4b0ea473321911c26737e9583db915143cc1fa4f", "scenes/wrappers/structural/ship_structural_v0/ramp_up_1x2.tscn":"029e00034d79ff231eb84784bac3fb5db130c801004ad9d89151b6c30c4325dc", "scenes/wrappers/structural/ship_structural_v0/wall_end_cap.tscn":"d9289dd68eb2822ea05d9dc5d80475410fbf469ef94710fc9dee2cf847abae2b", "scenes/wrappers/structural/ship_structural_v0/wall_inner_corner.tscn":"9266c8fb479c789315b3b037776de7f92eb06c2de81a81fe9a543829ca8c733d", "scenes/wrappers/structural/ship_structural_v0/wall_outer_corner.tscn":"01433cfda588a74a3e2841f5771b6ece61c9fb329f9e11afde33aef5422b2426", "scenes/wrappers/structural/ship_structural_v0/wall_straight_1x1.tscn":"977a8f1bb2655b57a07218ce71615c9213895e3f951946a19746f972420ccfb0", "scenes/wrappers/structural/ship_structural_v0/wall_t_junction.tscn":"a88ab1c073523dbd82dc8a54427bfd4b73db70508e8a4eb513bab9d3503160be",
}
# Pins are SHA-256 over canonical UTF-8 text with LF newlines.  The original
# resource list above was authored in a CRLF checkout; these normalized values
# deliberately make the validator portable across Git line-ending settings.
MAPPING_SOURCE_HASHES.update({
    "scripts/procgen/ship_layout_generator.gd":"4f20e35b00afbe4321ef016b59edb1c08c613d5d1097e1d745e92885d77bf79c", "scripts/procgen/ship_generator.gd":"cf5ce38d0ad156b1bf2d9b3c88a2d95de96bc514638fc53191d1bbea9be4edd4", "data/procgen/templates/hive.json":"545ac3ad1b2fdba494c52a564e5a0b3c3dd7dea56a5366c399498e0e06a9f885", "data/kits/ship_structural_hazard.json":"8cdb3fa3dfadcb0dcc92d592dc7ed7af81e1dc545070ef23846e930376bd0731", "data/kits/ship_structural_industrial.json":"f9bd87a9f6d2a2e439b1444863093e442762889b37533b98e3416b532bc60f10", "data/kits/ship_structural_biomatter.json":"83691b19478b7d3882de5dc2a0ed69e9a769acc0faed92bf160b4030791993c4",
})
RESOURCE_HASHES.update({
    "data/placement/contracts/structural/ship_structural_v0/bulkhead_portal_2x1_contract.tres":"d07c66650a9b232b698178674ed899ddedbfe8901477c29f27ce7c8dde80d9c9", "data/placement/contracts/structural/ship_structural_v0/ceiling_cap_1x1_contract.tres":"021f5bf2fc731b2b03b8159157c1213d9d40f9aa3482ad19bfc739086a7218c5", "data/placement/contracts/structural/ship_structural_v0/corridor_floor_1x1_contract.tres":"74cc926ccb845f4e49abe3c3bfe586939e387b974a4ebe336af13fd1ab4733ff", "data/placement/contracts/structural/ship_structural_v0/corridor_floor_1x2_contract.tres":"4bc82547fa38a1a610243ce8dec70fc3a30455a43e53bb25194207f560053526", "data/placement/contracts/structural/ship_structural_v0/doorway_frame_blocked_1x1_contract.tres":"33c92f54456129d9ea44a8d182e5de1eb3b3c114576534f12de385af9ee31b3a", "data/placement/contracts/structural/ship_structural_v0/doorway_frame_open_1x1_contract.tres":"a4a5784957094a98cb685a0ee7401d60ed62d809156e6e0f483721615f01c0fb", "data/placement/contracts/structural/ship_structural_v0/floor_1x1_contract.tres":"4c071698bc0ffdb27dfd347f29c2ecd6c95bcaf2b8d1c3c78f2f35b891cadafe", "data/placement/contracts/structural/ship_structural_v0/floor_2x1_contract.tres":"c6155e91a5a87e4918b7e68686122f01d9ac7c2317f8257707630ada883d0e2a", "data/placement/contracts/structural/ship_structural_v0/pillar_support_1x1_contract.tres":"c2e9a1d70b616db853d4666cf68eaa0ab375dfd9eee798fc82d511c96a057335", "data/placement/contracts/structural/ship_structural_v0/ramp_up_1x2_contract.tres":"99426187bc0e57db1ff9d199e0441d4d0322222d4b9ed9ca89f470ac32537cb0", "data/placement/contracts/structural/ship_structural_v0/wall_end_cap_contract.tres":"49febf737c22befea8325f3c0da371257ec590a61ca02811563dbf388f19c726", "data/placement/contracts/structural/ship_structural_v0/wall_inner_corner_contract.tres":"811007a26149574c140599aaefa15b1656f5861e8a3caea1f1a498d873126fae", "data/placement/contracts/structural/ship_structural_v0/wall_outer_corner_contract.tres":"032d084cde643330bc456b6c629175e91f57f10779e6f090d02f5061e62ed00d", "data/placement/contracts/structural/ship_structural_v0/wall_straight_1x1_contract.tres":"d8eace8e1cea184d74d6cf9690bb01d56ad1cb8d1e35538c59f98d1cfa2038f2", "data/placement/contracts/structural/ship_structural_v0/wall_t_junction_contract.tres":"af51c0df26efc5f8999ec9fa4b78da7b8ee88fbcbf39d88029af31f9da70c758",
    "scenes/wrappers/structural/ship_structural_v0/bulkhead_portal_2x1.tscn":"d6b3c617dc38102213d9232b6e83d2b1bdff00cc16a74d8a6bc305f23a850215", "scenes/wrappers/structural/ship_structural_v0/ceiling_cap_1x1.tscn":"6faeccb2da02eb7c49f3f8a14a82c2462b3a070a6320e17432c846d423df4018", "scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x1.tscn":"fc5fa5bfa8e51715b003247e2167b7d6012948347e11e572abbe7281ad8ece61", "scenes/wrappers/structural/ship_structural_v0/corridor_floor_1x2.tscn":"3737673ea78006e9788917c8e65c6b33c873063f3acf50880c776c666a52c3dd", "scenes/wrappers/structural/ship_structural_v0/doorway_frame_blocked_1x1.tscn":"9337ca462edf384346c0e4a913d3743f953e2209ceee7ca24eba395eaea1845f", "scenes/wrappers/structural/ship_structural_v0/doorway_frame_open_1x1.tscn":"c3d57f82088f5b5ef971e03277459e64bad2bc69d32ab88d169507b04173efd1", "scenes/wrappers/structural/ship_structural_v0/floor_1x1.tscn":"f75cf442c93c494255f3a639a02669c25ea147377675ec246e5d72436406d29c", "scenes/wrappers/structural/ship_structural_v0/floor_2x1.tscn":"7038a95e017eccd9c0b13fb801cdb0aac0a5a897cebd2555808e38dc3ab118bd", "scenes/wrappers/structural/ship_structural_v0/pillar_support_1x1.tscn":"896124405db105aae6edcd1cd5ed229300c32e7b760c1b2618d5e82fe6bb8ccd", "scenes/wrappers/structural/ship_structural_v0/ramp_up_1x2.tscn":"7c84e8b7cec7cd757059e507f2dce6ef15113069f2cceac269c8cbf84717abab", "scenes/wrappers/structural/ship_structural_v0/wall_end_cap.tscn":"1fbabcd9ca6679ad9ef8ffef75f34c6e578a84a28fce6cf37a9071289dec5f4a", "scenes/wrappers/structural/ship_structural_v0/wall_inner_corner.tscn":"cb13ffb4e5bec4081db46250b4b448f63f3476f6d07d2778e386e97d25acc3b5", "scenes/wrappers/structural/ship_structural_v0/wall_outer_corner.tscn":"69c0f572803705475a83331d3c673601001449bfb74da1d5474761eb4510c957", "scenes/wrappers/structural/ship_structural_v0/wall_straight_1x1.tscn":"0915106c4d6d1446b6d0b66af618b7efef03adfd0e986eeb55cd7e149feba18d", "scenes/wrappers/structural/ship_structural_v0/wall_t_junction.tscn":"e12cafb2a56042f0141ab80aa6f9b9a5b35e012a47f03bae27d523676f43542c",
})
# A resource-pin refresh must still preserve this reviewed top-level runtime
# contract.  This semantic authority deliberately excludes the legacy nested
# `asset` copy in each .tres.
CONTRACT_SEMANTIC_HASHES = {
    "data/placement/contracts/structural/ship_structural_v0/bulkhead_portal_2x1_contract.tres":"d3451e1ca3f222a7a2f75ab2f115da990cc05f2eca9e32b06313ad8c5412f032", "data/placement/contracts/structural/ship_structural_v0/ceiling_cap_1x1_contract.tres":"9123dec0f60190a9fdc1c36916fe12ae2fac75be6f8dd4838e50c249d720237b", "data/placement/contracts/structural/ship_structural_v0/corridor_floor_1x1_contract.tres":"f5b3db7332f46bdbf4afcb407140a3b1280fd54e3de9fe2731218d51b7cdf40c", "data/placement/contracts/structural/ship_structural_v0/corridor_floor_1x2_contract.tres":"64c097d7bc836e5fb29d142606c4f3bc0891f0efd1e18ad7b28662a003799564", "data/placement/contracts/structural/ship_structural_v0/doorway_frame_blocked_1x1_contract.tres":"a0a27913a5e8109ad105ec9adf4904987e83ca17f5286e292d0468343649d9c7", "data/placement/contracts/structural/ship_structural_v0/doorway_frame_open_1x1_contract.tres":"fead0c4e287dc395b7e179353a663d3cd9a69b2da2132a93fe558eae55790202", "data/placement/contracts/structural/ship_structural_v0/floor_1x1_contract.tres":"15c16f6812df0e6874e068db487997fbbaaf2cd29febfa81f871cc8a8f1746ba", "data/placement/contracts/structural/ship_structural_v0/floor_2x1_contract.tres":"54a077d427ead8f1ff2d310ddcf31a1662631e80303508c8b97e0005a25f1a45", "data/placement/contracts/structural/ship_structural_v0/pillar_support_1x1_contract.tres":"ee7990d2d675e4a863681e49edf35111fa79a1f8476b93930ea5f6daeb388201", "data/placement/contracts/structural/ship_structural_v0/ramp_up_1x2_contract.tres":"9c6991be1bbe22e0713227b3e389a148d00e7c1ab58b339041ce4ccc097813e5", "data/placement/contracts/structural/ship_structural_v0/wall_end_cap_contract.tres":"e196d26f8a4463ff68d061bbcefbf909710b6068f3319c32ee611b02c0caa038", "data/placement/contracts/structural/ship_structural_v0/wall_inner_corner_contract.tres":"1275ed42a2c06fbc1a463c2a727520de570360d6888ed13aab63ae1286eace45", "data/placement/contracts/structural/ship_structural_v0/wall_outer_corner_contract.tres":"cc23521c37df7dc8fac8579bb1a4353478b87bcc38de230b04df4f757abd6513", "data/placement/contracts/structural/ship_structural_v0/wall_straight_1x1_contract.tres":"bde200f10f197727933d2deb88bfbce777cfa38d5338bb43d7173de3d1679084", "data/placement/contracts/structural/ship_structural_v0/wall_t_junction_contract.tres":"78b5b81e3fa961c5ff9aa58cab324ce4ba8c58175402a62ee9f49616eff879aa",
}
TOOL_CLASS_CONCRETE_ITEMS = {"welding_lance": frozenset(("welder",))}

def _read_json(path: Path) -> object:
    try: return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error: raise ValueError(f"invalid source {path.as_posix()}: {error}") from error

def _assert_hashes(root: Path, hashes: dict[str, str], label: str) -> None:
    for relative_path, expected_hash in hashes.items():
        path = root / relative_path
        if not path.is_file(): raise ValueError(f"not_verified {label} drift: {relative_path}")
        try: text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error: raise ValueError(f"not_verified {label} drift: {relative_path}") from error
        normalized = text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
        if hashlib.sha256(normalized).hexdigest() != expected_hash: raise ValueError(f"not_verified {label} drift: {relative_path}")

def _assert_mapping_authority(root: Path) -> None: _assert_hashes(root, MAPPING_SOURCE_HASHES, "mapping authority")

def _top_json_assignment(text: str, key: str, source: Path) -> object:
    matches = re.findall(rf"(?m)^{re.escape(key)}\s*=\s*(.+)$", text)
    if not matches: raise ValueError(f"invalid canonical contract {source.as_posix()}: missing_top_level_{key}")
    if len(matches) != 1: raise ValueError(f"invalid canonical contract {source.as_posix()}: duplicate_top_level_{key}")
    try: return json.loads(matches[0])
    except json.JSONDecodeError as error: raise ValueError(f"invalid canonical contract {source.as_posix()}: invalid_top_level_{key}") from error

def _contract_semantic_hash(text: str, source: Path) -> str:
    fields = {key: _top_json_assignment(text, key, source) for key in ("asset_id", "module_id", "kit_id", "footprint_cells", "sockets", "wrapper_scene", "contract_path")}
    return hashlib.sha256(json.dumps(fields, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()

def _validate_contract_and_wrapper(root: Path, module: dict[str, object]) -> None:
    contract_relative, wrapper_relative = str(module["godot_contract"]).removeprefix("res://"), str(module["godot_wrapper_scene"]).removeprefix("res://")
    contract_path, wrapper_path = root / contract_relative, root / wrapper_relative
    if not contract_path.is_file() or not wrapper_path.is_file(): raise ValueError(f"missing canonical resource {module['module_id']}")
    text = contract_path.read_text(encoding="utf-8"); module_id = module["module_id"]
    if CONTRACT_SEMANTIC_HASHES.get(contract_relative) != _contract_semantic_hash(text, contract_path): raise ValueError(f"invalid canonical contract {module_id}: semantic_drift")
    expected_sockets = [str(name).removeprefix("SOCK_") for name in module["socket_names"]]
    if _top_json_assignment(text, "asset_id", contract_path) != module_id or _top_json_assignment(text, "module_id", contract_path) != module_id or _top_json_assignment(text, "kit_id", contract_path) != "ship_structural_v0" or _top_json_assignment(text, "footprint_cells", contract_path) != module["footprint_cells"] or _top_json_assignment(text, "wrapper_scene", contract_path) != module["godot_wrapper_scene"] or _top_json_assignment(text, "contract_path", contract_path) != module["godot_contract"]: raise ValueError(f"invalid canonical contract {module_id}: identity")
    sockets = _top_json_assignment(text, "sockets", contract_path)
    if not isinstance(sockets, list) or not all(isinstance(socket, dict) and set(socket) == {"id", "kind", "position_m", "compatible_kinds"} for socket in sockets): raise ValueError(f"invalid canonical contract {module_id}: sockets")
    socket_ids = [socket["id"] for socket in sockets]
    if len(socket_ids) != len(set(socket_ids)) or not set(expected_sockets) <= set(socket_ids): raise ValueError(f"invalid canonical contract {module_id}: socket_ids")
    for socket in sockets:
        if not isinstance(socket["id"], str) or not isinstance(socket["kind"], str) or not isinstance(socket["compatible_kinds"], list) or not socket["compatible_kinds"] or not all(isinstance(kind, str) for kind in socket["compatible_kinds"]) or not isinstance(socket["position_m"], list) or len(socket["position_m"]) != 3 or not all(type(value) in (int, float) for value in socket["position_m"]): raise ValueError(f"invalid canonical contract {module_id}: socket_semantics")
    anchors = re.findall(r'(?m)^\[node name="(Anchor_[^"]+)" type="Marker3D" parent="\."\]$', wrapper_path.read_text(encoding="utf-8"))
    expected_anchors = {"Anchor_FloorCenter", *(f"Anchor_SOCK_{name}" for name in expected_sockets)}
    if len(anchors) != len(set(anchors)) or set(anchors) != expected_anchors: raise ValueError(f"invalid canonical wrapper {module_id}: anchors")

def canonical_rows(root: Path) -> dict[str, dict]:
    _assert_mapping_authority(root); _assert_hashes(root, RESOURCE_HASHES, "structural resource")
    kits: dict[str, dict[str, dict]] = {}
    for kit_id in ("ship_structural_v0", "ship_structural_biomatter"):
        data = _read_json(root / "data/kits" / f"{kit_id}.json")
        if not isinstance(data, dict) or not isinstance(data.get("modules"), list) or not all(isinstance(module, dict) for module in data["modules"]): raise ValueError(f"invalid structural kit {kit_id}")
        kits[kit_id] = {str(module.get("module_id", "")): module for module in data["modules"]}
    rows: dict[str, dict] = {}
    for layout_id, resolved_id in (("ship_structural_v0", "ship_structural_v0"), ("ship_structural_hazard", "ship_structural_v0"), ("ship_structural_industrial", "ship_structural_v0"), ("ship_structural_biomatter", "ship_structural_biomatter")):
        for module_id, (duration, materials) in BALANCE.items():
            module = kits[resolved_id].get(module_id)
            if not isinstance(module, dict) or not isinstance(module.get("socket_names"), list) or not isinstance(module.get("footprint_cells"), list): raise ValueError(f"invalid structural module {resolved_id}:{module_id}")
            _validate_contract_and_wrapper(root, module); row_id = f"{layout_id}:{module_id}"
            rows[row_id] = {"row_id": row_id, "active": True, "layout_kit_id": layout_id, "structural_kit_id": resolved_id, "structural_contract_id": module["godot_contract"], "original_structural_module_id": module_id, "replacement_structural_module_id": module_id, "replacement_wrapper_id": module["godot_wrapper_scene"], "footprint_cells": module["footprint_cells"], "socket_mapping": [{"original_socket": value, "replacement_socket": value} for value in module["socket_names"]], "action_id": "rebuild_structure", "requirements": {"materials": materials, "tool_class": "welding_lance", "skill_id": "repair", "min_skill": 0, "duration_seconds": duration}}
    return rows

def _positive_integral(value: object) -> bool: return type(value) is int and value > 0

def _valid_footprint(value: object) -> bool:
    return isinstance(value, list) and len(value) == 2 and all(type(dimension) is int and 0 <= dimension <= 2 for dimension in value) and value != [0, 0]

def _valid_p09_pairs(report: dict, action_ids: set[str]) -> tuple[set[str], set[tuple[str, str]]] | None:
    reachable, raw_pairs = report.get("reachable_ids"), report.get("compatible_tool_actions")
    if not isinstance(reachable, list) or not all(isinstance(value, str) for value in reachable) or not isinstance(raw_pairs, list): return None
    pairs: set[tuple[str, str]] = set()
    for pair in raw_pairs:
        if not isinstance(pair, dict) or set(pair) != {"item_id", "action_id"} or not isinstance(pair["item_id"], str) or not isinstance(pair["action_id"], str) or pair["item_id"] not in reachable or pair["action_id"] not in action_ids: return None
        pairs.add((pair["item_id"], pair["action_id"]))
    return set(reachable), pairs

def validate_catalog(catalog: object, *, expected_rows: dict[str, dict], item_ids: set[str], action_ids: set[str], p09_report: object) -> dict:
    blockers: set[str] = set(); tuple_mismatches: list[str] = []
    if not isinstance(catalog, dict) or set(catalog) != CATALOG_KEYS: return {"ok": False, "blockers": ["catalog_schema"], "tuple_mismatches": []}
    if catalog.get("schema") != "structural_rebuild_catalog_v1": blockers.add("schema")
    rows = catalog.get("rows")
    if not isinstance(rows, list): return {"ok": False, "blockers": ["rows"], "tuple_mismatches": []}
    if not all(isinstance(row, dict) and set(row) == ROW_KEYS and row.get("active") is True for row in rows): blockers.add("row_schema")
    active = [row for row in rows if isinstance(row, dict) and row.get("active") is True]; ids = [row.get("row_id") for row in active]
    if not all(isinstance(value, str) for value in ids) or len(ids) != len(set(ids)) or set(ids) != set(expected_rows): blockers.add("coverage")
    for row in active:
        row_id = row.get("row_id"); expected = expected_rows.get(row_id) if isinstance(row_id, str) else None
        if expected is None: continue
        if any(row.get(key) != expected.get(key) for key in ROW_KEYS - {"row_id", "active"}): tuple_mismatches.append(row_id)
        requirements = row.get("requirements")
        if not isinstance(requirements, dict) or set(requirements) != REQUIREMENT_KEYS: blockers.add("requirements"); continue
        materials = requirements.get("materials")
        if not isinstance(materials, dict) or not materials or not all(isinstance(item_id, str) and item_id in item_ids and _positive_integral(quantity) for item_id, quantity in materials.items()): blockers.add("materials")
        if requirements.get("tool_class") not in TOOL_CLASS_CONCRETE_ITEMS or requirements.get("tool_class") not in item_ids: blockers.add("tool")
        if row.get("action_id") not in action_ids: blockers.add("runtime_action_missing")
        if requirements.get("skill_id") != "repair" or type(requirements.get("min_skill")) is not int or requirements.get("min_skill") != 0: blockers.add("skill")
        if not _positive_integral(requirements.get("duration_seconds")): blockers.add("duration")
        mapping = row.get("socket_mapping")
        if not isinstance(mapping, list) or not all(isinstance(socket, dict) and set(socket) == SOCKET_MAPPING_KEYS and all(isinstance(value, str) for value in socket.values()) for socket in mapping): blockers.add("socket_mapping")
        if not _valid_footprint(row.get("footprint_cells")): blockers.add("footprint")
    if tuple_mismatches: blockers.add("tuple_mismatches")
    if not isinstance(p09_report, dict) or p09_report.get("schema") != "crafting_economy_report_v1" or p09_report.get("ok") is not True: blockers.add("p09_report_unverified")
    else:
        parsed = _valid_p09_pairs(p09_report, action_ids)
        if parsed is None: blockers.add("p09_report_unverified")
        else:
            reachable, compatible = parsed
            for row in active:
                requirements = row.get("requirements")
                if not isinstance(requirements, dict): continue
                materials = requirements.get("materials")
                if not isinstance(materials, dict) or not set(materials) <= reachable: blockers.add("p09_acquisition_unverified")
                concrete_items = TOOL_CLASS_CONCRETE_ITEMS.get(requirements.get("tool_class"), frozenset())
                if not concrete_items <= reachable or not all((item_id, row.get("action_id")) in compatible for item_id in concrete_items): blockers.add("p09_tool_action_unverified")
    return {"ok": not blockers, "blockers": sorted(blockers), "tuple_mismatches": sorted(set(tuple_mismatches))}

def main() -> int:
    root = Path(".")
    try:
        catalog = _read_json(root / CATALOG_PATH); expected = canonical_rows(root)
        items, tools, actions = _read_json(root / "data/items/item_definitions.json"), _read_json(root / "data/tools/tool_definitions.json"), _read_json(root / "data/work_actions/work_action_catalog.json")
        if not isinstance(items, dict) or not isinstance(tools, dict) or not isinstance(actions, dict) or not isinstance(actions.get("actions"), dict): raise ValueError("invalid dependent catalog")
        try:
            from tools.check_crafting_economy import check
        except ModuleNotFoundError:
            from check_crafting_economy import check
        try: p09 = check(root)
        except Exception: p09 = None
        report = validate_catalog(catalog, expected_rows=expected, item_ids=set(items) | set(tools), action_ids=set(actions["actions"]), p09_report=p09)
    except Exception as error: report = {"ok": False, "blockers": ["source_invalid"], "tuple_mismatches": [], "reason": str(error)}
    print("STRUCTURAL REBUILD CATALOG PASS" if report["ok"] else "STRUCTURAL REBUILD CATALOG BLOCKED", json.dumps(report, sort_keys=True))
    return 0 if report["ok"] else 1

if __name__ == "__main__": raise SystemExit(main())
