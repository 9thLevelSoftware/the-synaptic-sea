"""Validate the authored crafting economy against real acquisition routes.

The checker intentionally keeps three concepts separate:

* a defined item can be carried by the runtime inventory;
* an acquisition root can enter a cold run without another item;
* a reachable item follows from roots through dependency-satisfied conversions.

Zero-power conversion groups are never assumed safe because a bounded search did
not find an exploit. A group is accepted only with a positive conservation
certificate. Otherwise it is reported as ``not_verified`` and blocks the check.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
import re
from pathlib import Path
from typing import Iterable


class SourceError(ValueError):
    """A required source is missing or violates its authored JSON shape."""


ITEM_DEFINITION_PATHS = (
    "data/items/item_definitions.json",
    "data/items/medicine_definitions.json",
    "data/items/stimulant_definitions.json",
    "data/combat/ammo_definitions.json",
    "data/items/utility_item_definitions.json",
    "data/items/trade_item_definitions.json",
)

CRAFTED_TOOL_COMPATIBILITY = {
    "welder": ("weld_patch",),
    "plasma_cutter": ("cut_wall",),
}

# These are authored donor routes, rather than claims about a particular loot
# roll. Both donors must remain obtainable from a live loot table and retain a
# skill-1 workbench deconstruction path to titanium.
TITANIUM_DONOR_DECONSTRUCTIONS = {
    "deconstruct_thruster": "thruster_nozzle",
    "deconstruct_plasma_cutter": "plasma_cutter",
}

EPSILON = 1.0e-9

COORDINATOR_PATH = "scripts/procgen/playable_generated_ship.gd"
PRODUCTION_STATION_PATH = "scripts/tools/production_station.gd"
WATER_RECYCLER_PATH = "scripts/systems/water_recycler_state.gd"
COMPONENT_CATALOG_RUNTIME_PATH = "scripts/systems/component_catalog.gd"
COMPONENT_PLACEMENT_RUNTIME_PATH = "scripts/systems/component_placement_state.gd"
COMPONENT_SLOT_RESOLVER_PATH = "scripts/procgen/wall_door_resolver.gd"
THREAT_MANAGER_PATH = "scripts/systems/threat_manager.gd"
WORK_ACTION_DRIVER_PATH = "scripts/systems/work_action_driver.gd"
SHIP_WORK_TRANSACTION_PATH = "scripts/systems/ship_work_transaction.gd"
WORK_ACTION_STATE_PATH = "scripts/systems/work_action_state.gd"
WORK_ACTION_CATALOG_PATH = "scripts/systems/work_action_catalog.gd"
ITEM_QUALITY_EFFECTS_PATH = "scripts/systems/item_quality_effects.gd"
QUALITY_TIER_RESOLVER_PATH = "scripts/systems/quality_tier_resolver.gd"
INVENTORY_STATE_PATH = "scripts/systems/inventory_state.gd"
ITEM_LOT_LEDGER_PATH = "scripts/systems/item_lot_ledger.gd"
ITEM_DEFS_RUNTIME_PATH = "scripts/systems/item_defs.gd"
SHIP_WORK_CONTEXT_PATH = "scripts/systems/ship_work_context.gd"
SHIP_INSTANCE_PATH = "scripts/systems/ship_instance.gd"

# These are the complete, manually reviewed production files and data resources
# that authorize the two positive crafted-tool/action pairs.  The coordinator
# changes under P10 have not completed independent review, so its pin remains
# intentionally pending.  This keeps the production report fail-closed until
# that single frozen source revision is supplied; do not replace it with a
# current working-tree hash during P10 development.
REVIEWED_TOOL_ACTION_FILE_HASHES: dict[str, str | None] = {
    COORDINATOR_PATH: None,
    SHIP_WORK_TRANSACTION_PATH: "28c351a2b6fae2ab5a5752639018c289289872a324b38e64e8a39d0d83c6e4fd",
    WORK_ACTION_DRIVER_PATH: "f93e5df2b0d8bc585911d6b16fc6ff90cf489e1e5b530d45d0198025c3fa9938",
    WORK_ACTION_STATE_PATH: "942b5f358b0d2ca0284f7778504afe06e3e88b5564191d91cf2ff60448af3a2d",
    WORK_ACTION_CATALOG_PATH: "87dffe39ca852acd27f230a6ae77b657f40b9e86f829f9ab8cb10afdec0eb339",
    ITEM_QUALITY_EFFECTS_PATH: "4c6a69b926ca16adc472dbb0907de5b951c35e250b0b55ed5e38adc7bf9c7e59",
    QUALITY_TIER_RESOLVER_PATH: "e83d30574b285f0c4fe00abf42df170c3f581f144936157983401263564e5523",
    INVENTORY_STATE_PATH: "5a9a6045ab0d48da416cc51fe2f82b9b37eae45b69070cc40d6a56445fb03d03",
    ITEM_LOT_LEDGER_PATH: "765c7f1dda8e03b26b17b9ca680497bf702ddabac26119a968c32ed4f8a0e2fc",
    ITEM_DEFS_RUNTIME_PATH: "f5dadb41f9d988a28eeaf330dd648a1f91edfd80ebb4a9c635598902afd24e3b",
    SHIP_WORK_CONTEXT_PATH: "68254f2890b9a9091ed9bc3f06435c48289d2997a1a89f60e592d0093396c376",
    SHIP_INSTANCE_PATH: "53977552d2e4ca0441dee2187a2f55718c30c607c144dbd58711174c95a02bd1",
    "data/items/quality_effects.json": "61f60c498a56a97689b4c0aa6a2f8e89f539343bcad96b3798087ac99ebb294a",
    "data/work_actions/work_action_catalog.json": "122ee805d694fe09cadb7276c71b323e49ec619a2dbffd1a1d5adcf8fd3e58d2",
    "data/recipes/recipe_definitions.json": "cd4ba44e4e68fb22eea11d3872d7ab088c97b526324ef01c9677b9d39906bf4c",
    "data/tools/tool_definitions.json": "74aab73aeb90f27d9585fb5d87ab6b5f1df8cdd87364d2ad2d19482f5310159b",
    "data/items/item_definitions.json": "8263fba804c2fb8595e395861dec37dcadda88a8cb66fd0d1d3c16a35bf1605d",
    "data/items/medicine_definitions.json": "e34eac835125bb80856aad1601422c4df127cbb99d4e7d61fdc3e4cfbafdb86b",
    "data/items/stimulant_definitions.json": "85dd982dfb4990ab00823b90bc1e0fff8b0c086597d4a100d7d7655370f742b9",
    "data/combat/ammo_definitions.json": "1c4982739ba352e00309172184f840c69a5b8b6e2ab28331d1c9c00362f5aa38",
    "data/items/utility_item_definitions.json": "991bd3947449e0b29a47be9426370f3adbf19fa44d6d6f9416e58a5bc4a04857",
    "data/items/trade_item_definitions.json": "bb3f8675c1f24861026cff6b9c99f99e1b71d822cf7379276dae1484c7a0ec3b",
}

# Fine-grained function hashes remain diagnostics for the originally reviewed
# gate, lot propagation, and quality calls.  Full-file hashes above are the
# authorization boundary because they also cover signatures, preloads, data
# bindings, and intermediate consumers.
REVIEWED_TOOL_ACTION_FUNCTION_HASHES = {
    COORDINATOR_PATH: {
        "_try_work_action_interact": "01a6aff8b352475fe35ebbf7a9cff0c8d906765264c6734a878f64566fbec48d",
        "_start_transactional_work": "dab7224209c2b83196b75df4ab1eefd9056a6898483e87cfc4dcf68aaf60c179",
        "_has_compatible_work_tool": "20873c37963be2dbe8f21db018f596f418dd19bfff85617494f3c6e949ad7d91",
        "_selected_work_tool_lot": "ca8e0418269b74215dbba74c7c7530cbcbd703dcfe1c470f0a6cb27e634835f9",
        "_work_tool_item_is_compatible": "4a2e044c25246dad9cb2266b44f19be73f6325aefde2cb6cf28a7acefc6ad708",
    },
    WORK_ACTION_DRIVER_PATH: {
        "build_context": "65a28ef9fe6bb995da33861b8134a0cd79674b540954783d789c297ce98c05b1",
        "start_action": "1e2bcb66f2ebd8f3be7dbf010cae9cadb8baf283b7f84ba634c72b59c8ab1d22",
        "tick": "df5ffefd0e08f28cb128c5001ee940f307b9f2c101e731d6275c3c89677f90f4",
    },
    ITEM_QUALITY_EFFECTS_PATH: {
        "consumer_for": "551b847ceb395de6cccb33bc0e4693ac974f3b7f1157126f93b0b68526cb54ff",
        "multiplier_for_lot": "3dff2dba0953c199757f9e3d159fc6c340a06f89d492137ff2568dd89ba0f9d5",
    },
}


def read(root: Path | str, relative_path: str) -> dict:
    """Read a required JSON object without masking malformed-present data."""

    path = Path(root) / relative_path
    if not path.is_file():
        raise SourceError(f"missing {relative_path}")
    try:
        parsed = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise SourceError(f"invalid {relative_path}: {error}") from error
    if not isinstance(parsed, dict):
        raise SourceError(f"schema {relative_path}: expected object")
    return parsed


def read_text(root: Path | str, relative_path: str) -> str:
    """Read a required runtime source without treating absence as evidence."""

    path = Path(root) / relative_path
    if not path.is_file():
        raise SourceError(f"missing {relative_path}")
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise SourceError(f"invalid {relative_path}: {error}") from error


def _lex_gdscript(source: str, relative_path: str) -> tuple[str, list[dict]]:
    """Mask comments and strings while retaining string-token positions.

    This is deliberately a lexer for the small source adapter below, not a
    general GDScript parser. New syntax that the lexer cannot delimit is a
    source error so non-executable text can never become acquisition evidence.
    """

    masked = list(source)
    literals: list[dict] = []
    index = 0
    while index < len(source):
        character = source[index]
        if character == "#":
            end = source.find("\n", index)
            if end < 0:
                end = len(source)
            for position in range(index, end):
                masked[position] = " "
            index = end
            continue
        if character not in ("'", '"'):
            index += 1
            continue
        delimiter = character * (3 if source.startswith(character * 3, index) else 1)
        content_start = index + len(delimiter)
        cursor = content_start
        escaped = False
        while cursor < len(source):
            if len(delimiter) == 3 and source.startswith(delimiter, cursor):
                break
            if len(delimiter) == 1:
                if escaped:
                    escaped = False
                    cursor += 1
                    continue
                if source[cursor] == "\\":
                    escaped = True
                    cursor += 1
                    continue
                if source[cursor] == character:
                    break
            cursor += 1
        if cursor >= len(source):
            raise SourceError(f"runtime {relative_path}: unterminated string literal")
        token_end = cursor + len(delimiter)
        raw_value = source[content_start:cursor]
        # The adapter compares authored ASCII identifiers. Keeping escape text
        # literal makes unfamiliar escape syntax fail closed and avoids
        # corrupting valid non-ASCII source through a byte round trip.
        value = raw_value
        literals.append(
            {"start": index, "end": token_end, "value": value, "raw": raw_value}
        )
        for position in range(index, token_end):
            if masked[position] != "\n":
                masked[position] = " "
        index = token_end
    return "".join(masked), literals


def _strip_gdscript_comments(source: str) -> str:
    """Compatibility helper used by older callers and focused tests."""

    masked, literals = _lex_gdscript(source, "<memory>")
    restored = list(masked)
    for literal in literals:
        restored[literal["start"]:literal["end"]] = source[
            literal["start"]:literal["end"]
        ]
    return "".join(restored)


def _parse_gdscript(source: str, relative_path: str) -> dict:
    masked, literals = _lex_gdscript(source, relative_path)
    declarations = list(
        re.finditer(r"(?m)^(?:static\s+)?func\s+([A-Za-z_]\w*)\b", masked)
    )
    functions: dict[str, dict] = {}
    for declaration_index, declaration in enumerate(declarations):
        name = declaration.group(1)
        if name in functions:
            raise SourceError(f"runtime {relative_path}: duplicate function {name}")
        next_start = (
            declarations[declaration_index + 1].start()
            if declaration_index + 1 < len(declarations)
            else len(source)
        )
        header_cursor = declaration.end()
        body_start = -1
        while header_cursor < next_start:
            line_end = masked.find("\n", header_cursor, next_start)
            if line_end < 0:
                line_end = next_start
            if masked[header_cursor:line_end].rstrip().endswith(":"):
                body_start = min(line_end + 1, next_start)
                break
            header_cursor = line_end + 1
        if body_start < 0:
            raise SourceError(f"runtime {relative_path}: unsupported declaration {name}")
        functions[name] = {
            "name": name,
            "declaration_start": declaration.start(),
            "raw": source[body_start:next_start],
            "full_raw": source[declaration.start():next_start],
            "code": masked[body_start:next_start],
            "start": body_start,
            "end": next_start,
            "literals": [
                {**literal, "start": literal["start"] - body_start, "end": literal["end"] - body_start}
                for literal in literals
                if body_start <= literal["start"] < next_start
            ],
        }
    return {
        "path": relative_path,
        "source": source,
        "code": masked,
        "literals": literals,
        "functions": functions,
    }


def _load_gdscript(root: Path, relative_path: str) -> dict:
    return _parse_gdscript(read_text(root, relative_path), relative_path)


def _require_function(unit: dict, function_name: str) -> dict:
    function = unit["functions"].get(function_name)
    if function is None:
        raise SourceError(f"runtime {unit['path']}: missing {function_name}")
    return function


def _reachable_functions(unit: dict, roots: Iterable[str]) -> set[str]:
    """Follow direct local calls and signal callbacks from explicit roots."""

    names = set(unit["functions"])
    reachable: set[str] = set()
    pending = list(roots)
    while pending:
        name = pending.pop()
        if name in reachable:
            continue
        function = unit["functions"].get(name)
        if function is None:
            raise SourceError(f"runtime {unit['path']}: missing lifecycle root {name}")
        reachable.add(name)
        code = function["code"]
        direct = set(
            match.group(1)
            for match in re.finditer(r"(?<![\w.])([A-Za-z_]\w*)\s*\(", code)
            if match.group(1) in names
        )
        callbacks = set(
            match.group(1)
            for match in re.finditer(
                r"\.connect\s*\(\s*([A-Za-z_]\w*)\b", code
            )
            if match.group(1) in names
        )
        pending.extend(sorted(direct | callbacks))
    return reachable


def _source_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _function_source_hash(function: dict) -> str:
    return _source_hash(_strip_gdscript_comments(function["raw"]))


def _normalized_function_hash(function: dict) -> str:
    source = function["full_raw"].replace("\r\n", "\n").replace("\r", "\n")
    return _source_hash(source)


def _normalized_source_hash(source: str) -> str:
    """Hash a reviewed source file without making checkout line endings semantic."""

    return _source_hash(source.replace("\r\n", "\n").replace("\r", "\n"))


def _reviewed_tool_action_source_hashes(root: Path) -> dict[str, str]:
    return {
        relative_path: _normalized_source_hash(read_text(root, relative_path))
        for relative_path in REVIEWED_TOOL_ACTION_FILE_HASHES
    }


def _require_reviewed_tool_action_path(root: Path) -> None:
    """Fail closed unless every reviewed production dependency is unchanged."""

    actual_hashes = _reviewed_tool_action_source_hashes(root)
    for relative_path, expected_hash in REVIEWED_TOOL_ACTION_FILE_HASHES.items():
        if expected_hash is None:
            raise SourceError(
                f"runtime {relative_path}: compatible tool action proof pin pending review"
            )
        if actual_hashes[relative_path] != expected_hash:
            raise SourceError(
                f"runtime {relative_path}: compatible tool action proof drift"
            )


def _object_rows(document: dict, source: str, key: str | None = None) -> dict:
    rows = document if key is None else document.get(key)
    if not isinstance(rows, dict):
        raise SourceError(f"schema {source}: expected object at {key or '<root>'}")
    for row_id, row in rows.items():
        if not isinstance(row_id, str) or not row_id or not isinstance(row, dict):
            raise SourceError(f"schema {source}: invalid row {row_id!r}")
    return rows


def _array_rows(document: dict, source: str, key: str) -> list:
    rows = document.get(key)
    if not isinstance(rows, list):
        raise SourceError(f"schema {source}: expected array at {key}")
    if not all(isinstance(row, dict) for row in rows):
        raise SourceError(f"schema {source}: {key} contains a non-object row")
    return rows


def _merge_fields(previous: dict | None, incoming: dict) -> dict:
    merged = dict(previous or {})
    merged.update(incoming)
    return merged


def merged_defs(root: Path | str) -> dict:
    """Mirror ``ItemDefs.load_definitions`` merge order and precedence."""

    root = Path(root)
    definitions: dict[str, dict] = {}

    tool_path = "data/tools/tool_definitions.json"
    for item_id, raw in _object_rows(read(root, tool_path), tool_path).items():
        row = dict(raw)
        row["category"] = "tool"
        row.setdefault("weight", 2.0)
        definitions[item_id] = row

    item_path = ITEM_DEFINITION_PATHS[0]
    for item_id, row in _object_rows(read(root, item_path), item_path).items():
        definitions[item_id] = dict(row)

    for extra_path in ITEM_DEFINITION_PATHS[1:]:
        for item_id, row in _object_rows(read(root, extra_path), extra_path).items():
            definitions[item_id] = _merge_fields(definitions.get(item_id), row)

    material_path = "data/materials/material_definitions.json"
    materials = _object_rows(read(root, material_path), material_path, "materials")
    for item_id, row in materials.items():
        if item_id not in definitions:
            definitions[item_id] = dict(row)

    equipment_path = "data/items/equipment_definitions.json"
    for item_id, row in _object_rows(
        read(root, equipment_path), equipment_path
    ).items():
        definitions[item_id] = dict(row)

    for relative_path in (
        "data/items/junk_items.json",
        "data/items/unique_items.json",
    ):
        rows = _object_rows(read(root, relative_path), relative_path, "items")
        for source_id, row in rows.items():
            item_id = str(row.get("item_id", source_id))
            if not item_id:
                raise SourceError(f"schema {relative_path}: empty item_id")
            definitions[item_id] = _merge_fields(definitions.get(item_id), row)

    return definitions


def _positive_number(value, source: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise SourceError(f"schema {source}: expected positive number")
    result = float(value)
    if not math.isfinite(result) or result <= 0.0:
        raise SourceError(f"schema {source}: expected positive number")
    return result


def _nonnegative_number(value, source: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise SourceError(f"schema {source}: expected nonnegative number")
    result = float(value)
    if not math.isfinite(result) or result < 0.0:
        raise SourceError(f"schema {source}: expected nonnegative number")
    return result


def _quantity_map(value, source: str, *, allow_empty: bool = False) -> dict[str, float]:
    if not isinstance(value, dict) or (not value and not allow_empty):
        expected = "quantity object" if allow_empty else "nonempty quantity object"
        raise SourceError(f"schema {source}: expected {expected}")
    result: dict[str, float] = {}
    for item_id, quantity in value.items():
        if not isinstance(item_id, str) or not item_id:
            raise SourceError(f"schema {source}: empty item id")
        result[item_id] = _positive_number(quantity, f"{source}.{item_id}")
    return result


def _recipe_conversion(row: dict, index: int) -> dict:
    source = f"recipe[{index}]"
    recipe_id = row.get("recipe_id")
    if not isinstance(recipe_id, str) or not recipe_id:
        raise SourceError(f"schema {source}: missing recipe_id")
    # Empty ingredients are a semantic economy finding, not a schema error: a
    # zero-power positive-output row is an immediately repeatable generator and
    # must be reported even though it has no SCC edge.
    inputs = _quantity_map(
        row.get("ingredients"), f"{source}.ingredients", allow_empty=True
    )
    produced = row.get("produces")
    if not isinstance(produced, dict):
        raise SourceError(f"schema {source}.produces: expected object")
    item_id = produced.get("item_id")
    if not isinstance(item_id, str) or not item_id:
        raise SourceError(f"schema {source}.produces: missing item_id")
    quantity = _positive_number(produced.get("quantity"), f"{source}.produces.quantity")
    return {
        "conversion_id": recipe_id,
        "kind": "recipe",
        "inputs": inputs,
        "outputs": {item_id: quantity},
        "power_cost": _nonnegative_number(row.get("power_cost", 0.0), f"{source}.power_cost"),
        "recipe": row,
    }


def _load_recipes(root: Path) -> list[dict]:
    relative_path = "data/recipes/recipe_definitions.json"
    recipes = _array_rows(read(root, relative_path), relative_path, "recipes")
    seen: set[str] = set()
    for index, row in enumerate(recipes):
        conversion = _recipe_conversion(row, index)
        recipe_id = conversion["conversion_id"]
        if recipe_id in seen:
            raise SourceError(f"schema {relative_path}: duplicate recipe_id {recipe_id}")
        seen.add(recipe_id)
    return recipes


def _runtime_loot_table_sources(root: Path, table_ids: set[str]) -> dict[str, list[str]]:
    """Return tables selected by the bounded production selector surfaces."""

    sources: dict[str, list[str]] = {table_id: [] for table_id in table_ids}

    def record(values: Iterable[str], relative_path: str) -> None:
        for table_id in sorted(table_ids.intersection(values)):
            if relative_path not in sources[table_id]:
                sources[table_id].append(relative_path)

    ship_path = "scripts/procgen/ship_generator.gd"
    ship = _load_gdscript(root, ship_path)
    if "generate_from_seed" in ship["functions"]:
        reachable = _reachable_functions(ship, ("generate_from_seed",))
        if "_map_worldgen_loot_table" in reachable:
            mapper = _require_function(ship, "_map_worldgen_loot_table")
            record(_assigned_string_values(mapper, r"\bcandidate\b"), ship_path)

    slice_path = "scripts/procgen/gameplay_slice_builder.gd"
    slice_unit = _load_gdscript(root, slice_path)
    if "build" in slice_unit["functions"]:
        reachable = _reachable_functions(slice_unit, ("build",))
        build = _require_function(slice_unit, "build")
        record(_assigned_string_values(build, r"\bkind2\b"), slice_path)
        if "_salvage_loot_table_for_role" in reachable:
            selector = _require_function(slice_unit, "_salvage_loot_table_for_role")
            record(_returned_string_values(selector), slice_path)

        if "_loot_table_for_room" in reachable:
            room_selector = _require_function(slice_unit, "_loot_table_for_room")
            if re.search(r"\._?effects_for\s*\(", room_selector["code"]):
                variant_path = "scripts/procgen/room_variant_selector.gd"
                variants = _load_gdscript(root, variant_path)
                effects = variants["functions"].get("effects_for")
                if effects and re.search(r"\bVARIANT_EFFECTS\b", effects["code"]):
                    record(
                        _keyed_string_values(
                            _constant_scope(variants, "VARIANT_EFFECTS", "{", "}"),
                            "loot_bias",
                        ),
                        variant_path,
                    )

    threat_path = "data/combat/threat_archetypes.json"
    threat_rows = _object_rows(read(root, threat_path), threat_path)
    authored_threat_tables = {
        str(row.get("loot_table", ""))
        for row in threat_rows.values()
        if isinstance(row.get("loot_table"), str)
    }
    if table_ids.intersection(authored_threat_tables):
        live_threat_tables = _verified_threat_loot_tables(root, threat_rows)
        record(live_threat_tables, threat_path)

    # The default playable scene names one concrete starting slice. Its loot
    # declarations are finite one-run routes, distinct from procedural tables.
    scene_path = root / "scenes/procgen/playable_coherent_ship.tscn"
    if scene_path.is_file():
        scene_text = scene_path.read_text(encoding="utf-8")
        match = re.search(
            r'(?m)^gameplay_slice_path\s*=\s*"res://([^"\r\n]+)"\s*$',
            scene_text,
        )
        if match:
            gameplay_path = match.group(1)
            gameplay = read(root, gameplay_path)
            containers = gameplay.get("loot_containers", [])
            if not isinstance(containers, list):
                raise SourceError(f"schema {gameplay_path}: expected loot_containers array")
            record(
                (
                    str(row.get("loot_table", ""))
                    for row in containers
                    if isinstance(row, dict) and isinstance(row.get("loot_table"), str)
                ),
                gameplay_path,
            )
    return {key: value for key, value in sources.items() if value}


def _verified_threat_loot_tables(root: Path, threat_rows: dict) -> set[str]:
    """Verify the bounded threat death -> corpse container loot path."""

    manager_file = root / THREAT_MANAGER_PATH
    coordinator_file = root / COORDINATOR_PATH
    if not manager_file.is_file() or not coordinator_file.is_file():
        return set()

    manager = _load_gdscript(root, THREAT_MANAGER_PATH)
    if _constant_string_value(manager, "THREAT_ARCHETYPE_PATH") != (
        "res://data/combat/threat_archetypes.json"
    ):
        raise SourceError(
            f"runtime {THREAT_MANAGER_PATH}: unsupported threat archetype source"
        )
    ready = _require_function(manager, "_ready")
    _require_code(
        ready,
        r"\bthreat_archetypes\s*=\s*_load_json_dict\s*\(\s*THREAT_ARCHETYPE_PATH\s*\)",
        "threat archetypes are not loaded",
        THREAT_MANAGER_PATH,
    )
    manager_reachable = _reachable_functions(manager, ("tick_threats",))
    if "_sweep_dead_threats" not in manager_reachable:
        raise SourceError(
            f"runtime {THREAT_MANAGER_PATH}: death sweep is not reachable from tick_threats"
        )
    sweep = _require_function(manager, "_sweep_dead_threats")
    signal_calls = _call_string_arguments(sweep, r"(?<![\w.])emit_signal")
    get_calls = _call_string_arguments(sweep, r"\.get")
    if not any(call and call[0] == "threat_killed" for call in signal_calls):
        raise SourceError(
            f"runtime {THREAT_MANAGER_PATH}: death sweep does not emit threat_killed"
        )
    if "threat_archetypes" not in sweep["code"] or not any(
        call and call[0] == "loot_table" for call in get_calls
    ):
        raise SourceError(
            f"runtime {THREAT_MANAGER_PATH}: death record omits archetype loot_table"
        )

    coordinator = _load_gdscript(root, COORDINATOR_PATH)
    build = _require_function(coordinator, "_build_runtime_nodes")
    for pattern, message in (
        (r"\bthreat_manager\s*=\s*ThreatManagerScript\.new\s*\(", "threat manager is not constructed"),
        (r"\badd_child\s*\(\s*threat_manager\s*\)", "threat manager is not registered"),
        (r"\bthreat_manager\.threat_killed\.connect\s*\(\s*_on_threat_killed\s*\)", "threat death consumer is not connected"),
    ):
        _require_code(build, pattern, message, COORDINATOR_PATH)
    process_reachable = _reachable_functions(coordinator, ("_process",))
    if "_tick_threat_runtime" not in process_reachable:
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: threat runtime is not reachable from _process"
        )
    threat_tick = _require_function(coordinator, "_tick_threat_runtime")
    _require_code(
        threat_tick,
        r"\bthreat_manager\.tick_threats\s*\(",
        "threat manager is not ticked",
        COORDINATOR_PATH,
    )
    callback = _require_function(coordinator, "_on_threat_killed")
    callback_gets = _call_string_arguments(callback, r"\brecord\.get")
    if not any(call and call[0] == "loot_table" for call in callback_gets):
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: threat callback omits loot_table"
        )
    if "_spawn_corpse_loot_container" not in _reachable_functions(
        coordinator, ("_on_threat_killed",)
    ):
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: corpse loot spawn is unreachable"
        )
    spawn = _require_function(coordinator, "_spawn_corpse_loot_container")
    for pattern, message in (
        (r"\bLootContainerScript\.new\s*\(", "corpse loot container is not constructed"),
        (r"\blc\.configure\s*\(", "corpse loot table is not configured"),
        (r"\bparent_node\.add_child\s*\(\s*lc\s*\)", "corpse loot container is not registered"),
        (r"\bloot_containers\.append\s*\(\s*lc\s*\)", "corpse loot interaction is not registered"),
    ):
        _require_code(spawn, pattern, message, COORDINATOR_PATH)

    return {
        str(row.get("loot_table", ""))
        for row in threat_rows.values()
        if isinstance(row.get("loot_table"), str) and row.get("loot_table")
    }


def _loot_runtime_source_hashes(root: Path) -> dict[str, str]:
    """Fingerprint the exact runtime functions used as loot provenance."""

    function_sets = {
        "scripts/procgen/ship_generator.gd": (
            "generate_from_seed",
            "_map_worldgen_loot_table",
        ),
        "scripts/procgen/gameplay_slice_builder.gd": (
            "build",
            "_salvage_loot_table_for_role",
            "_loot_table_for_room",
        ),
        "scripts/procgen/room_variant_selector.gd": ("effects_for",),
        THREAT_MANAGER_PATH: ("_ready", "tick_threats", "_sweep_dead_threats"),
        COORDINATOR_PATH: (
            "_build_runtime_nodes",
            "_process",
            "_tick_threat_runtime",
            "_on_threat_killed",
            "_spawn_corpse_loot_container",
        ),
    }
    hashes: dict[str, str] = {}
    for relative_path, function_names in function_sets.items():
        unit = _load_gdscript(root, relative_path)
        for function_name in function_names:
            hashes[f"{relative_path}:{function_name}"] = _function_source_hash(
                _require_function(unit, function_name)
            )
    return hashes


def _load_loot_roots(root: Path) -> list[dict]:
    relative_path = "data/items/loot_tables.json"
    document = read(root, relative_path)
    table_ids = {str(key) for key in document if not str(key).startswith("_")}
    runtime_sources = _runtime_loot_table_sources(root, table_ids)
    roots: list[dict] = []
    for table_id, table in document.items():
        if table_id.startswith("_"):
            continue
        if not isinstance(table, dict):
            raise SourceError(f"schema {relative_path}: table {table_id} is not an object")
        entries = table.get("entries")
        if not isinstance(entries, list):
            raise SourceError(f"schema {relative_path}: table {table_id} has no entries array")
        # Orphan authored tables are valid data, but they are not cold-run
        # roots until a production builder/archetype actually references them.
        if table_id not in runtime_sources:
            continue
        for index, entry in enumerate(entries):
            source = f"{relative_path}:{table_id}[{index}]"
            if not isinstance(entry, dict):
                raise SourceError(f"schema {source}: expected object")
            item_id = entry.get("item_id")
            if not isinstance(item_id, str) or not item_id:
                raise SourceError(f"schema {source}: missing item_id")
            weight = _nonnegative_number(entry.get("weight", 0), f"{source}.weight")
            quantity = _nonnegative_number(
                entry.get("qty_max", entry.get("quantity", 0)), f"{source}.qty_max"
            )
            if weight > 0.0 and quantity > 0.0:
                root_row = {
                        "item_id": item_id,
                        "source": f"loot:{table_id}",
                        "runtime_sources": runtime_sources[table_id],
                        "quantity": quantity,
                        "weight": weight,
                    }
                codex_entry_id = entry.get("codex_entry_id")
                if isinstance(codex_entry_id, str) and codex_entry_id:
                    root_row["codex_entry_id"] = codex_entry_id
                root_row["repeatable"] = not all(
                    source.startswith("data/procgen/")
                    for source in runtime_sources[table_id]
                )
                roots.append(root_row)
    return sorted(roots, key=lambda row: (row["item_id"], row["source"]))


def _line_bounds(text: str, position: int) -> tuple[int, int]:
    start = text.rfind("\n", 0, position) + 1
    end = text.find("\n", position)
    return start, len(text) if end < 0 else end


def _literals_between(scope: dict, start: int, end: int) -> list[str]:
    return [
        str(literal["value"])
        for literal in scope["literals"]
        if start <= literal["start"] < end
    ]


def _assigned_string_values(function: dict, lhs_pattern: str) -> set[str]:
    values: set[str] = set()
    for match in re.finditer(rf"(?m)^\s*(?:var\s+)?{lhs_pattern}[^=\n]*=", function["code"]):
        _start, end = _line_bounds(function["code"], match.start())
        values.update(_literals_between(function, match.end(), end))
    return values


def _adjacent_string_assignment_pairs(
    function: dict, first_name: str, second_name: str
) -> set[tuple[str, str]]:
    """Read two consecutive literal assignments from lexer-backed code."""

    pairs: set[tuple[str, str]] = set()
    code = function["code"]
    for first in re.finditer(rf"(?m)^\s*{re.escape(first_name)}\s*=", code):
        _start, first_end = _line_bounds(code, first.start())
        first_values = _literals_between(function, first.end(), first_end)
        if len(first_values) != 1:
            continue
        cursor = first_end
        while cursor < len(code) and code[cursor].isspace():
            cursor += 1
        second = re.match(rf"{re.escape(second_name)}\s*=", code[cursor:])
        if second is None:
            continue
        _second_start, second_end = _line_bounds(code, cursor)
        second_values = _literals_between(function, cursor + second.end(), second_end)
        if len(second_values) == 1:
            pairs.add((first_values[0], second_values[0]))
    return pairs


def _returned_string_values(function: dict) -> set[str]:
    values: set[str] = set()
    for match in re.finditer(r"(?m)^\s*return\b", function["code"]):
        _start, end = _line_bounds(function["code"], match.start())
        values.update(_literals_between(function, match.end(), end))
    return values


def _keyed_string_values(scope: dict, key: str) -> set[str]:
    values: set[str] = set()
    literals = scope["literals"]
    code = scope["code"]
    for index, literal in enumerate(literals[:-1]):
        if literal["value"] != key:
            continue
        following = literals[index + 1]
        if re.fullmatch(r"\s*:\s*", code[literal["end"]:following["start"]]):
            values.add(str(following["value"]))
    return values


def _constant_scope(unit: dict, name: str, opener: str, closer: str) -> dict:
    """Return one balanced constant initializer as a lexer-backed scope."""

    match = re.search(
        rf"(?m)^const\s+{re.escape(name)}\b[^=\n]*=\s*{re.escape(opener)}",
        unit["code"],
    )
    if match is None:
        raise SourceError(f"runtime {unit['path']}: missing constant {name}")
    start = match.end() - 1
    depth = 1
    cursor = start + 1
    while cursor < len(unit["code"]) and depth:
        if unit["code"][cursor] == opener:
            depth += 1
        elif unit["code"][cursor] == closer:
            depth -= 1
        cursor += 1
    if depth:
        raise SourceError(f"runtime {unit['path']}: unsupported constant {name}")
    return {
        "code": unit["code"][start:cursor],
        "literals": [
            {
                **literal,
                "start": literal["start"] - start,
                "end": literal["end"] - start,
            }
            for literal in unit["literals"]
            if start <= literal["start"] < cursor
        ],
    }


def _constant_array_values(unit: dict, constant_name: str) -> set[str]:
    match = re.search(
        rf"(?m)^const\s+{re.escape(constant_name)}\b[^=\n]*=\s*\[",
        unit["code"],
    )
    if match is None:
        raise SourceError(f"runtime {unit['path']}: missing constant {constant_name}")
    end = unit["code"].find("]", match.end())
    if end < 0:
        raise SourceError(f"runtime {unit['path']}: unsupported constant {constant_name}")
    return set(_literals_between(unit, match.end(), end))


def _call_string_arguments(function: dict, call_pattern: str) -> list[list[str]]:
    calls: list[list[str]] = []
    for match in re.finditer(rf"{call_pattern}\s*\(", function["code"]):
        depth = 1
        cursor = match.end()
        while cursor < len(function["code"]) and depth:
            if function["code"][cursor] == "(":
                depth += 1
            elif function["code"][cursor] == ")":
                depth -= 1
            cursor += 1
        if depth:
            raise SourceError("runtime source: unsupported unterminated call")
        calls.append(_literals_between(function, match.end(), cursor - 1))
    return calls


def _require_code(function: dict, pattern: str, message: str, path: str) -> None:
    if re.search(pattern, function["code"]) is None:
        raise SourceError(f"runtime {path}: {message}")


def _verify_production_consumers(root: Path) -> dict:
    station = _load_gdscript(root, PRODUCTION_STATION_PATH)
    station_reachable = _reachable_functions(
        station, ("try_interact", "try_plant_crop")
    )
    for function_name in ("_interact_hydro", "_interact_recycler"):
        if function_name not in station_reachable:
            raise SourceError(
                f"runtime {PRODUCTION_STATION_PATH}: {function_name} is not reachable from try_interact"
            )
    hydro = _require_function(station, "_interact_hydro")
    plant = _require_function(station, "try_plant_crop")
    recycler = _require_function(station, "_interact_recycler")
    for pattern, description in (
        (r"\bmodel\.harvest\s*\(", "hydroponics consumer lacks harvest"),
        (r"(?<![\w.])_deposit\s*\(", "hydroponics consumer lacks output deposit"),
    ):
        _require_code(hydro, pattern, description, PRODUCTION_STATION_PATH)
    for pattern, description in (
        (r"\bmodel\.plant\s*\(", "hydroponics consumer lacks plant"),
        (r"\binventory_state\.remove_item\s*\(", "hydroponics consumer lacks input debit"),
    ):
        _require_code(plant, pattern, description, PRODUCTION_STATION_PATH)
    for pattern, description in (
        (r"\bmodel\.load_input\s*\(", "water consumer lacks load_input"),
        (r"\bmodel\.collect_output\s*\(", "water consumer lacks collect_output"),
        (r"\binventory_state\.remove_item\s*\(", "water consumer lacks input debit"),
        (r"(?<![\w.])_deposit\s*\(", "water consumer lacks output deposit"),
    ):
        _require_code(recycler, pattern, description, PRODUCTION_STATION_PATH)
    input_literals = _call_string_arguments(recycler, r"\bmodel\.load_input")[0]
    if not input_literals:
        raise SourceError(f"runtime {PRODUCTION_STATION_PATH}: water input id is not literal")
    input_item_id = input_literals[0]

    water = _load_gdscript(root, WATER_RECYCLER_PATH)
    for function_name in ("load_input", "tick", "collect_output"):
        _require_function(water, function_name)
    output_match = re.search(
        r"(?m)^var\s+output_item_id\b[^=\n]*=", water["code"]
    )
    if output_match is None:
        raise SourceError(f"runtime {WATER_RECYCLER_PATH}: missing output_item_id")
    _start, output_end = _line_bounds(water["code"], output_match.start())
    output_literals = _literals_between(water, output_match.end(), output_end)
    if len(output_literals) != 1:
        raise SourceError(f"runtime {WATER_RECYCLER_PATH}: output_item_id is not literal")

    def numeric_default(name: str) -> float:
        match = re.search(
            rf"(?m)^var\s+{re.escape(name)}\b[^=\n]*=\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+))",
            water["code"],
        )
        if match is None:
            raise SourceError(f"runtime {WATER_RECYCLER_PATH}: missing numeric {name}")
        return _positive_number(float(match.group(1)), f"runtime {WATER_RECYCLER_PATH}:{name}")

    return {
        "input_item_id": input_item_id,
        "output_item_id": output_literals[0],
        "conversion_ratio": numeric_default("conversion_ratio"),
        "power_cost": numeric_default("power_cost"),
        "source_hashes": {
            PRODUCTION_STATION_PATH: _source_hash(station["source"]),
            WATER_RECYCLER_PATH: _source_hash(water["source"]),
        },
    }


def _load_runtime_contracts(root: Path) -> dict:
    """Verify the bounded coordinator lifecycle and its source consumers."""

    unit = _load_gdscript(root, COORDINATOR_PATH)
    ready = _require_function(unit, "_ready")
    runtime_nodes = _require_function(unit, "_build_runtime_nodes")
    _require_code(
        ready, r"(?<![\w.])_build_runtime_nodes\s*\(",
        "_ready does not build runtime nodes", COORDINATOR_PATH,
    )
    _require_code(
        ready, r"\bloader\.load_from_paths\s*\(",
        "_ready does not trigger the ship load lifecycle", COORDINATOR_PATH,
    )
    for pattern, message in (
        (r"\bloader\s*=\s*GeneratedShipLoaderScript\.new\s*\(", "loader is not constructed"),
        (r"\bloader\.ship_loaded\.connect\s*\(\s*_on_ship_loaded\b", "ship_loaded callback is not registered"),
        (r"\badd_child\s*\(\s*loader\s*\)", "loader is not in the scene tree"),
        (r"\bcrafting_state\s*=\s*CraftingStateScript\.new\s*\(", "shared crafting state is not constructed"),
        (r"\bfield_crafting_state\s*=\s*FieldCraftingStateScript\.new\s*\(", "field_crafting state is not constructed"),
    ):
        _require_code(runtime_nodes, pattern, message, COORDINATOR_PATH)
    reachable = _reachable_functions(unit, ("_ready",))
    work_interact = _require_function(unit, "_try_work_action_interact")
    if "_try_work_action_interact" not in reachable:
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: _try_work_action_interact is not reachable from runtime lifecycle"
        )
    work_tool_reachable = _reachable_functions(unit, ("_try_work_action_interact",))
    for function_name in (
        "_has_compatible_work_tool",
        "_selected_work_tool_lot",
        "_work_tool_item_is_compatible",
    ):
        if function_name not in work_tool_reachable:
            raise SourceError(
                f"runtime {COORDINATOR_PATH}: {function_name} is not reachable from work interaction"
            )
    compatible_tool_calls: set[tuple[str, str]] = set()
    for arguments in _call_string_arguments(
        work_interact, r"(?<![\w.])_has_compatible_work_tool"
    ):
        if len(arguments) != 2 or not all(arguments):
            raise SourceError(
                f"runtime {COORDINATOR_PATH}: unsupported compatible work-tool invocation"
            )
        compatible_tool_calls.add((arguments[0], arguments[1]))
    runtime_tool_action_classes = compatible_tool_calls & _adjacent_string_assignment_pairs(
        work_interact, "action_id", "tool_class"
    )
    pickups: list[dict] = []
    for function_name in ("_build_tool_pickup", "_build_junction_calibrator_pickup"):
        function = _require_function(unit, function_name)
        if function_name not in reachable:
            raise SourceError(
                f"runtime {COORDINATOR_PATH}: {function_name} is not reachable from runtime lifecycle"
            )
        _require_code(function, r"\bToolPickupScript\.new\s*\(",
                      f"{function_name} lacks pickup construction", COORDINATOR_PATH)
        configure_calls = _call_string_arguments(function, r"\.configure")
        if not configure_calls or not configure_calls[0]:
            raise SourceError(
                f"runtime {COORDINATOR_PATH}: {function_name} has no literal pickup configure"
            )
        _require_code(function, r"\btool_pickup_root\.add_child\s*\(",
                      f"{function_name} lacks scene registration", COORDINATOR_PATH)
        item_id = configure_calls[0][0]
        pickups.append(
            {
                "item_id": item_id,
                "source": f"fixed_pickup:{item_id}",
                "quantity": 1,
                "repeatable": False,
                "runtime_source": f"{COORDINATOR_PATH}:{function_name}",
            }
        )

    station_entry = _require_function(unit, "_build_crafting_stations")
    if "_build_crafting_stations" not in reachable:
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: _build_crafting_stations is not reachable from runtime lifecycle"
        )
    # Crafting stations are owner-scoped: the lifecycle entry resolves the live
    # ship and delegates construction to the helper that validates its binding.
    # Keep these two responsibilities separate so moving construction out of the
    # entry does not silently authorize an unreachable or owner-agnostic helper.
    _require_code(
        station_entry,
        r"\bcurrent_occupancy\b.*\bcurrent_ship\b",
        "crafting station owner resolution missing",
        COORDINATOR_PATH,
    )
    _require_code(
        station_entry,
        r"(?<![\w.])_ensure_crafting_stations_for_owner\s*\(\s*owner\s*\)",
        "crafting station owner builder invocation missing",
        COORDINATOR_PATH,
    )
    station_builder = _require_function(unit, "_ensure_crafting_stations_for_owner")
    station_entry_reachable = _reachable_functions(unit, ("_build_crafting_stations",))
    if "_ensure_crafting_stations_for_owner" not in station_entry_reachable:
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: _ensure_crafting_stations_for_owner is not reachable from _build_crafting_stations"
        )
    for function_name, owner_name, label in (
        ("_attach_derelict_active", "inst", "derelict attach"),
        ("_bind_current_ship_restoration_owners", "current_ship", "restoration rebind"),
    ):
        lifecycle_function = _require_function(unit, function_name)
        if function_name not in reachable:
            raise SourceError(
                f"runtime {COORDINATOR_PATH}: {function_name} is not reachable from runtime lifecycle"
            )
        _require_code(
            lifecycle_function,
            rf"(?<![\w.])_ensure_crafting_stations_for_owner\s*\(\s*{owner_name}\s*\)",
            f"crafting station {label} builder invocation missing",
            COORDINATOR_PATH,
        )
    for pattern, message in (
        (r"\bCraftingStationScript\.new\s*\(", "crafting station construction missing"),
        (r"(?m)^\s*for\s+kind\s+in\s+CRAFTING_STATION_KINDS\s*:", "crafting station full kind loop missing"),
        (r"\bst\.configure\s*\(\s*kind\s*,\s*context\.crafting_state\s*,", "crafting station shared state configure missing"),
        (r"\b_ship_work_context_for\s*\(\s*str\s*\(\s*owner\.ship_id\s*\)\s*\)", "crafting station owner context missing"),
        (r"\bcontext\.crafting_state\s*!=\s*crafting_state\b", "crafting station shared state binding missing"),
        (r"\bcontext\.matches_binding\s*\(\s*owner\s*\)", "crafting station owner binding missing"),
        (r"\bowner\.get_pending_output_store\s*\(\s*\)", "crafting station owner pending store missing"),
        (r"\bowner\.scene_root\.add_child\s*\(\s*st\s*\)", "crafting station scene registration missing"),
        (r"\bcrafting_stations\.append\s*\(\s*st\s*\)", "crafting station interaction registration missing"),
    ):
        _require_code(station_builder, pattern, message, COORDINATOR_PATH)
    crafting_station_kinds = _constant_array_values(unit, "CRAFTING_STATION_KINDS")
    if not crafting_station_kinds:
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: _build_crafting_stations has no station kinds"
        )

    production_function = _require_function(unit, "_build_production_stations")
    if "_build_production_stations" not in reachable:
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: _build_production_stations is not reachable from runtime lifecycle"
        )
    for pattern, message in (
        (r"\bProductionStationScript\.new\s*\(", "production station construction missing"),
        (r"\.configure\s*\(", "production station configure missing"),
        (r"\bhome_ship\.scene_root\.add_child\s*\(\s*st\s*\)", "production station scene registration missing"),
        (r"\bproduction_stations\.append\s*\(\s*st\s*\)", "production station interaction registration missing"),
    ):
        _require_code(production_function, pattern, message, COORDINATOR_PATH)
    production_station_kinds = _keyed_string_values(production_function, "kind")
    required_production_kinds = {"water_recycler", "hydroponics"}
    missing_production_kinds = sorted(required_production_kinds - production_station_kinds)
    if missing_production_kinds:
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: _build_production_stations missing kinds "
            + ", ".join(missing_production_kinds)
        )
    production_consumer = _verify_production_consumers(root)
    crafting_station_kinds.add("field_crafting")
    _require_reviewed_tool_action_path(root)
    return {
        "pickups": pickups,
        "crafting_stations": True,
        "crafting_station_kinds": sorted(crafting_station_kinds),
        "production_stations": True,
        "production_station_kinds": sorted(production_station_kinds),
        "runtime_tool_action_classes": [
            {"action_id": action_id, "tool_class": tool_class}
            for action_id, tool_class in sorted(runtime_tool_action_classes)
        ],
        "production_consumer": production_consumer,
        "source_hashes": {
            **{
                f"{COORDINATOR_PATH}:{function_name}": _function_source_hash(
                    _require_function(unit, function_name)
                )
                for function_name in (
                    "_ready",
                    "_build_runtime_nodes",
                    "_on_ship_loaded",
                    "_try_work_action_interact",
                    "_has_compatible_work_tool",
                    "_selected_work_tool_lot",
                    "_work_tool_item_is_compatible",
                    "_attach_derelict_active",
                    "_build_tool_pickup",
                    "_build_junction_calibrator_pickup",
                    "_build_crafting_stations",
                    "_ensure_crafting_stations_for_owner",
                    "_bind_current_ship_restoration_owners",
                    "_build_production_stations",
                )
            },
            **production_consumer["source_hashes"],
            **_reviewed_tool_action_source_hashes(root),
        },
    }


def _load_junk_conversions(root: Path) -> list[dict]:
    relative_path = "data/items/junk_items.json"
    rows = _object_rows(read(root, relative_path), relative_path, "items")
    conversions: list[dict] = []
    for junk_id, row in sorted(rows.items()):
        yields = row.get("yields")
        if not isinstance(yields, list) or not yields:
            raise SourceError(f"schema {relative_path}:{junk_id}.yields")
        outputs: dict[str, float] = {}
        for index, yield_row in enumerate(yields):
            if not isinstance(yield_row, dict):
                raise SourceError(f"schema {relative_path}:{junk_id}.yields[{index}]")
            item_id = yield_row.get("material_id")
            if not isinstance(item_id, str) or not item_id:
                raise SourceError(f"schema {relative_path}:{junk_id}.yields[{index}].material_id")
            outputs[item_id] = outputs.get(item_id, 0.0) + _positive_number(
                yield_row.get("quantity"),
                f"{relative_path}:{junk_id}.yields[{index}].quantity",
            )
        conversions.append(
            {
                "conversion_id": f"junk:{junk_id}",
                "kind": "junk",
                "inputs": {junk_id: 1.0},
                "outputs": outputs,
                "power_cost": 0.0,
            }
        )
    return conversions


def _constant_string_value(unit: dict, constant_name: str) -> str:
    match = re.search(
        rf"(?m)^const\s+{re.escape(constant_name)}\b[^=\n]*=", unit["code"]
    )
    if match is None:
        raise SourceError(f"runtime {unit['path']}: missing constant {constant_name}")
    _start, end = _line_bounds(unit["code"], match.start())
    values = _literals_between(unit, match.end(), end)
    if len(values) != 1:
        raise SourceError(
            f"runtime {unit['path']}: {constant_name} is not one literal"
        )
    return values[0]


def _verify_component_consumers(root: Path) -> dict:
    coordinator = _load_gdscript(root, COORDINATOR_PATH)
    coordinator_reachable = _reachable_functions(coordinator, ("_ready",))
    restore_name = "_restore_or_populate_component_placement_for_current_ship"
    if restore_name not in coordinator_reachable:
        raise SourceError(
            f"runtime {COORDINATOR_PATH}: component placement is not reachable from runtime lifecycle"
        )
    restore = _require_function(coordinator, restore_name)
    for pattern, message in (
        (r"\bcomponent_catalog\s*=\s*ComponentCatalogScript\.new\s*\(", "component catalog is not constructed"),
        (r"\bcomponent_catalog\.load_default\s*\(", "component catalog is not loaded"),
        (r"\bcomponent_placement_state\s*=\s*ComponentPlacementStateScript\.new\s*\(", "component placement is not constructed"),
        (r"\bcomponent_placement_state\.populate\s*\(", "component placement does not populate"),
    ):
        _require_code(restore, pattern, message, COORDINATOR_PATH)

    catalog = _load_gdscript(root, COMPONENT_CATALOG_RUNTIME_PATH)
    fit = _require_function(catalog, "validate_component_fit")
    for token in (
        "component_slot_profile_id",
        "footprint_cells",
        "socket_type",
        "allowed_component_types",
    ):
        if token not in {literal["value"] for literal in fit["literals"]}:
            raise SourceError(
                f"runtime {COMPONENT_CATALOG_RUNTIME_PATH}: fit consumer omits {token}"
            )

    placement = _load_gdscript(root, COMPONENT_PLACEMENT_RUNTIME_PATH)
    reachable = _reachable_functions(placement, ("populate",))
    if "_fill_slots" not in reachable:
        raise SourceError(
            f"runtime {COMPONENT_PLACEMENT_RUNTIME_PATH}: _fill_slots is not reachable from populate"
        )
    fill = _require_function(placement, "_fill_slots")
    for pattern, message in (
        (r"\.call\s*\(\s*", "role/profile calls are absent"),
        (r"(?<![\w.])_weighted_pick\s*\(", "weighted donor selection is absent"),
        (r"\bplaced\.append\s*\(", "selected donors are not registered"),
    ):
        _require_code(fill, pattern, message, COMPONENT_PLACEMENT_RUNTIME_PATH)
    required_call_methods = {"role_set", "get_slot_profile", "validate_component_fit"}
    called_methods = {
        call[0]
        for call in _call_string_arguments(fill, r"\.call")
        if call
    }
    if not required_call_methods.issubset(called_methods):
        raise SourceError(
            f"runtime {COMPONENT_PLACEMENT_RUNTIME_PATH}: placement fit chain is incomplete"
        )

    resolver = _load_gdscript(root, COMPONENT_SLOT_RESOLVER_PATH)
    profile_function = _require_function(resolver, "component_slot_profile_for")
    for token in ("slot_kind", "slot_index"):
        if token not in profile_function["code"]:
            raise SourceError(
                f"runtime {COMPONENT_SLOT_RESOLVER_PATH}: slot profile selector omits {token}"
            )
    profile_constants = {
        name: _constant_string_value(resolver, name)
        for name in (
            "WALL_CONSOLE_PROFILE",
            "WALL_UTILITY_PROFILE",
            "DECK_MACHINERY_PROFILE",
            "DECK_CONSOLE_PROFILE",
        )
    }
    for name in profile_constants:
        if name not in profile_function["code"]:
            raise SourceError(
                f"runtime {COMPONENT_SLOT_RESOLVER_PATH}: selector omits {name}"
            )
    _verify_role_profile_selector(profile_function)
    return {
        "profile_constants": profile_constants,
        "source_hashes": {
            f"{COORDINATOR_PATH}:{restore_name}": _function_source_hash(restore),
            COMPONENT_CATALOG_RUNTIME_PATH: _source_hash(catalog["source"]),
            COMPONENT_PLACEMENT_RUNTIME_PATH: _source_hash(placement["source"]),
            COMPONENT_SLOT_RESOLVER_PATH: _source_hash(resolver["source"]),
        },
    }


def _verify_role_profile_selector(profile_function: dict) -> None:
    """Fail closed if the small selector mirrored below changes shape."""

    role_lines: list[tuple[set[str], str, str]] = []
    code = profile_function["code"]
    cursor = 0
    while cursor < len(code):
        line_start = cursor
        line_end = code.find("\n", cursor)
        if line_end < 0:
            line_end = len(code)
        line_code = code[line_start:line_end]
        if re.search(r"\brole\s+in\s*\[", line_code):
            next_start = min(line_end + 1, len(code))
            next_end = code.find("\n", next_start)
            if next_end < 0:
                next_end = len(code)
            role_lines.append(
                (
                    set(_literals_between(profile_function, line_start, line_end)),
                    line_code,
                    code[next_start:next_end],
                )
            )
        cursor = line_end + 1

    expected = [
        (
            {"bridge", "cockpit"},
            {"DECK_CONSOLE_PROFILE", "DECK_MACHINERY_PROFILE"},
        ),
        (
            {"cargo", "storage", "airlock", "medical", "corridor", "hydroponics"},
            {"WALL_UTILITY_PROFILE"},
        ),
        (
            {"engineering", "reactor", "bridge", "cockpit"},
            {"WALL_CONSOLE_PROFILE"},
        ),
    ]
    if len(role_lines) != len(expected):
        raise SourceError(
            f"runtime {COMPONENT_SLOT_RESOLVER_PATH}: unsupported role/profile selector"
        )
    for (actual_roles, line_code, next_code), (expected_roles, expected_constants) in zip(
        role_lines, expected
    ):
        if actual_roles != expected_roles or not expected_constants.issubset(
            set(re.findall(r"\b[A-Z][A-Z0-9_]*PROFILE\b", line_code + next_code))
        ):
            raise SourceError(
                f"runtime {COMPONENT_SLOT_RESOLVER_PATH}: unsupported role/profile selector"
            )

    comparison_literals: set[str] = set()
    for match in re.finditer(r"(?m)^.*\bslot_kind\s*[!=]=.*$", code):
        comparison_literals.update(
            _literals_between(profile_function, match.start(), match.end())
        )
    if not {"center", "wall"}.issubset(comparison_literals):
        raise SourceError(
            f"runtime {COMPONENT_SLOT_RESOLVER_PATH}: unsupported role/profile selector"
        )


def _component_fits_profile(component: dict, slot_kind: str, profile: dict) -> bool:
    required_slot = str(component.get("slot", ""))
    if not required_slot or required_slot not in ("any", slot_kind):
        return False
    footprint = component.get("footprint_cells")
    if not isinstance(footprint, list) or not footprint:
        return False
    profile_footprint = profile.get("footprint_cells")
    if not isinstance(profile_footprint, list) or [int(v) for v in footprint] != [
        int(v) for v in profile_footprint
    ]:
        return False
    sockets = component.get("socket_types")
    if not isinstance(sockets, list) or not sockets:
        singular = component.get("socket_type")
        sockets = [singular] if isinstance(singular, str) and singular else []
    if str(profile.get("socket_type", "")) not in sockets:
        return False
    allowed = profile.get("allowed_component_types")
    return isinstance(allowed, list) and str(component.get("component_type", "")) in allowed


def _generated_role_ids(root: Path) -> set[str]:
    template_root = root / "data/procgen/templates"
    roles: set[str] = set()
    if not template_root.is_dir():
        return roles
    for path in sorted(template_root.glob("*.json")):
        relative_path = path.relative_to(root).as_posix()
        document = read(root, relative_path)
        nodes = document.get("nodes", [])
        if not isinstance(nodes, list):
            raise SourceError(f"schema {relative_path}: expected nodes array")
        for node in nodes:
            if not isinstance(node, dict):
                continue
            pool = node.get("role_pool", [])
            if isinstance(pool, list):
                roles.update(str(role) for role in pool if isinstance(role, str) and role)
    return roles


def _profiles_for_role_slot(
    role: str, slot_kind: str, profile_constants: dict
) -> set[str]:
    if slot_kind == "center":
        name = (
            "DECK_CONSOLE_PROFILE"
            if role in {"bridge", "cockpit"}
            else "DECK_MACHINERY_PROFILE"
        )
        return {profile_constants[name]}
    if slot_kind != "wall":
        return set()
    if role in {"cargo", "storage", "airlock", "medical", "corridor", "hydroponics"}:
        return {profile_constants["WALL_UTILITY_PROFILE"]}
    if role in {"engineering", "reactor", "bridge", "cockpit"}:
        return {profile_constants["WALL_CONSOLE_PROFILE"]}
    return {
        profile_constants["WALL_CONSOLE_PROFILE"],
        profile_constants["WALL_UTILITY_PROFILE"],
    }


def _load_components(root: Path) -> tuple[dict, dict, list[str]]:
    relative_path = "data/components/component_catalog.json"
    document = read(root, relative_path)
    components = _object_rows(document, relative_path, "components")
    role_sets = _object_rows(document, relative_path, "role_sets")
    slot_profiles = _object_rows(document, relative_path, "slot_profiles")
    runtime = _verify_component_consumers(root)
    generated_roles = _generated_role_ids(root)
    referenced: set[str] = set()
    for role_id, slots in role_sets.items():
        if not isinstance(slots, dict):
            raise SourceError(f"schema {relative_path}: role {role_id}")
        for slot_id, entries in slots.items():
            if not isinstance(entries, list):
                raise SourceError(f"schema {relative_path}: role {role_id}.{slot_id}")
            for index, entry in enumerate(entries):
                if not isinstance(entry, dict):
                    raise SourceError(f"schema {relative_path}: role {role_id}.{slot_id}[{index}]")
                component_id = entry.get("component_id")
                if not isinstance(component_id, str) or component_id not in components:
                    raise SourceError(
                        f"schema {relative_path}: unknown role component {component_id!r}"
                    )
                weight = _nonnegative_number(
                    entry.get("weight", 0),
                    f"{relative_path}: role {role_id}.{slot_id}[{index}].weight",
                )
                if weight <= 0.0:
                    continue
                if generated_roles and role_id != "default" and role_id not in generated_roles:
                    continue
                profile_ids = _profiles_for_role_slot(
                    role_id, slot_id, runtime["profile_constants"]
                )
                if any(
                    profile_id in slot_profiles
                    and _component_fits_profile(
                        components[component_id], slot_id, slot_profiles[profile_id]
                    )
                    for profile_id in profile_ids
                ):
                    referenced.add(component_id)
    return components, role_sets, sorted(referenced)


def _load_systems(root: Path) -> tuple[list, list[str], list[str]]:
    relative_path = "data/ship_systems/systems.json"
    systems = _array_rows(read(root, relative_path), relative_path, "systems")
    parts: set[str] = set()
    tools: set[str] = set()
    for system_index, system in enumerate(systems):
        subcomponents = system.get("subcomponents")
        if not isinstance(subcomponents, list):
            raise SourceError(f"schema {relative_path}: systems[{system_index}].subcomponents")
        for sub_index, subcomponent in enumerate(subcomponents):
            if not isinstance(subcomponent, dict):
                raise SourceError(
                    f"schema {relative_path}: systems[{system_index}].subcomponents[{sub_index}]"
                )
            for field, destination in (("required_parts", parts), ("required_tools", tools)):
                values = subcomponent.get(field, [])
                if not isinstance(values, list) or not all(
                    isinstance(value, str) and value for value in values
                ):
                    raise SourceError(
                        f"schema {relative_path}: systems[{system_index}].{field}"
                    )
                destination.update(values)
    return systems, sorted(parts), sorted(tools)


def _load_production_routes(
    root: Path, runtime_contracts: dict
) -> tuple[list[dict], list[dict], dict]:
    if not bool(runtime_contracts.get("production_stations", False)):
        raise SourceError("runtime production stations are not verified")
    crop_path = "data/crops/hydroponics_crops.json"
    crops = _array_rows(read(root, crop_path), crop_path, "crops")
    consumer = runtime_contracts.get("production_consumer")
    if not isinstance(consumer, dict):
        raise SourceError("runtime production consumers are not verified")
    water_route = {
        "route_id": "water_recycler",
        "inputs": {str(consumer["input_item_id"]): 1.0},
        "outputs": {
            str(consumer["output_item_id"]): float(consumer["conversion_ratio"])
        },
        "power_cost": float(consumer["power_cost"]),
        "evidence": [PRODUCTION_STATION_PATH, WATER_RECYCLER_PATH],
    }
    routes = [water_route]
    for index, crop in enumerate(crops):
        source = f"{crop_path}:crops[{index}]"
        crop_id = crop.get("crop_id")
        output_id = crop.get("produce_item_id")
        if not isinstance(crop_id, str) or not crop_id:
            raise SourceError(f"schema {source}: missing crop_id")
        if not isinstance(output_id, str) or not output_id:
            raise SourceError(f"schema {source}: missing produce_item_id")
        routes.append(
            {
                "route_id": f"hydroponics:{crop_id}",
                "inputs": {
                    "purified_water": _positive_number(
                        crop.get("water_cost"), f"{source}.water_cost"
                    )
                },
                "outputs": {
                    output_id: _positive_number(
                        crop.get("produce_quantity"), f"{source}.produce_quantity"
                    )
                },
                "power_cost": _positive_number(
                    crop.get("power_cost"), f"{source}.power_cost"
                ),
                "required_skill_level": int(crop.get("required_skill_level", 0)),
            }
        )
    return crops, routes, water_route


def _load_work_actions(root: Path) -> dict:
    relative_path = "data/work_actions/work_action_catalog.json"
    return _object_rows(read(root, relative_path), relative_path, "actions")


def _load_quality_effects(root: Path) -> dict:
    relative_path = "data/items/quality_effects.json"
    return _object_rows(read(root, relative_path), relative_path, "items")


def model(root: Path | str) -> dict:
    """Load and normalize every P09 graph source."""

    root = Path(root)
    components, role_sets, component_source_ids = _load_components(root)
    systems, repair_parts, repair_tools = _load_systems(root)
    runtime_contracts = _load_runtime_contracts(root)
    crops, production_routes, water_route = _load_production_routes(root, runtime_contracts)
    base_item_path = ITEM_DEFINITION_PATHS[0]
    base_item_definition_ids = sorted(
        _object_rows(read(root, base_item_path), base_item_path).keys()
    )
    definitions = merged_defs(root)
    loot_roots = _load_loot_roots(root)
    loot_source_hashes = _loot_runtime_source_hashes(root)
    codex_root_ids = sorted(
        {
            str(
                row.get(
                    "codex_entry_id",
                    definitions.get(row["item_id"], {}).get("codex_entry_id", ""),
                )
            )
            for row in loot_roots
            if str(definitions.get(row["item_id"], {}).get("codex_entry_id", ""))
        }
    )
    return {
        "recipes": _load_recipes(root),
        "definitions": definitions,
        "base_item_definition_ids": base_item_definition_ids,
        "loot_roots": loot_roots,
        "codex_root_ids": codex_root_ids,
        "junk_conversions": _load_junk_conversions(root),
        "production_routes": production_routes,
        "crops": crops,
        "water_route": water_route,
        "components": components,
        "role_sets": role_sets,
        "component_source_ids": component_source_ids,
        "require_component_sources": True,
        "systems": systems,
        "repair_parts": repair_parts,
        "repair_tools": repair_tools,
        "work_actions": _load_work_actions(root),
        "quality_effects": _load_quality_effects(root),
        "runtime_tool_action_classes": runtime_contracts["runtime_tool_action_classes"],
        "pickups": runtime_contracts["pickups"],
        "crafting_stations": runtime_contracts["crafting_stations"],
        "crafting_station_kinds": runtime_contracts["crafting_station_kinds"],
        "require_station_bindings": True,
        "runtime_source_hashes": {
            **runtime_contracts["source_hashes"],
            **loot_source_hashes,
            **{
                path: _source_hash(read_text(root, path))
                for path in (
                    COMPONENT_CATALOG_RUNTIME_PATH,
                    COMPONENT_PLACEMENT_RUNTIME_PATH,
                    COMPONENT_SLOT_RESOLVER_PATH,
                )
            },
            f"{COORDINATOR_PATH}:_restore_or_populate_component_placement_for_current_ship": (
                _function_source_hash(
                    _require_function(
                        _load_gdscript(root, COORDINATOR_PATH),
                        "_restore_or_populate_component_placement_for_current_ship",
                    )
                )
            ),
        },
    }


def _all_conversions(source_model: dict) -> list[dict]:
    conversions = [
        _recipe_conversion(row, index)
        for index, row in enumerate(source_model.get("recipes", []))
    ]
    for key in ("junk_conversions", "production_routes"):
        for index, raw in enumerate(source_model.get(key, [])):
            if not isinstance(raw, dict):
                raise SourceError(f"schema model.{key}[{index}]")
            conversion_id = raw.get("conversion_id", raw.get("route_id"))
            if not isinstance(conversion_id, str) or not conversion_id:
                raise SourceError(f"schema model.{key}[{index}].conversion_id")
            conversions.append(
                {
                    "conversion_id": conversion_id,
                    "kind": raw.get("kind", "production"),
                    "inputs": _quantity_map(
                        raw.get("inputs"),
                        f"model.{key}[{index}].inputs",
                        allow_empty=True,
                    ),
                    "outputs": _quantity_map(raw.get("outputs"), f"model.{key}[{index}].outputs"),
                    "power_cost": _nonnegative_number(
                        raw.get("power_cost", 0.0), f"model.{key}[{index}].power_cost"
                    ),
                }
            )
    return conversions


def _root_rows(source_model: dict) -> list[dict]:
    roots = list(source_model.get("loot_roots", [])) + list(
        source_model.get("pickups", [])
    )
    components = source_model.get("components", {})
    for component_id in source_model.get("component_source_ids", []):
        row = components.get(component_id, {})
        item_form = row.get("item_form") if isinstance(row, dict) else None
        if isinstance(item_form, str) and item_form:
            roots.append(
                {
                    "item_id": item_form,
                    "source": f"generated_component:{component_id}",
                    "quantity": 1,
                    "repeatable": True,
                }
            )
    normalized: list[dict] = []
    for index, row in enumerate(roots):
        if not isinstance(row, dict):
            raise SourceError(f"schema model.roots[{index}]")
        item_id = row.get("item_id")
        if not isinstance(item_id, str) or not item_id:
            raise SourceError(f"schema model.roots[{index}].item_id")
        quantity = _positive_number(row.get("quantity", 1), f"model.roots[{index}].quantity")
        normalized.append({**row, "item_id": item_id, "quantity": quantity})
    return sorted(normalized, key=lambda row: (row["item_id"], str(row.get("source", ""))))


def _source_cardinality(
    source_model: dict, conversions: list[dict], roots: list[dict]
) -> dict[str, dict]:
    finite: dict[str, float] = {}
    repeatable: set[str] = set()
    for row in roots:
        item_id = row["item_id"]
        if bool(row.get("repeatable", False)):
            repeatable.add(item_id)
        else:
            finite[item_id] = finite.get(item_id, 0.0) + float(row["quantity"])

    # Only unconditional conversions propagate repeatability here. Finite
    # conversion planning shares consumable pools and is intentionally left
    # unverified rather than overestimated by an independent per-item count.
    changed = True
    while changed:
        changed = False
        for conversion in conversions:
            if conversion["kind"] == "recipe":
                source = str(conversion["recipe"].get("knowledge_source", "starter"))
                if source not in ("", "starter"):
                    continue
            if not set(conversion["inputs"]).issubset(repeatable):
                continue
            for output_id in conversion["outputs"]:
                if output_id not in repeatable:
                    repeatable.add(output_id)
                    changed = True
    item_ids = set(finite) | repeatable
    return {
        item_id: {
            "repeatable": item_id in repeatable,
            "finite_quantity": finite.get(item_id, 0.0),
        }
        for item_id in sorted(item_ids)
    }


def _station_tiers(source_model: dict) -> dict[str, int]:
    available: dict[str, int] = {}
    sourced = set(source_model.get("component_source_ids", []))
    for component_id, row in source_model.get("components", {}).items():
        if component_id not in sourced or not isinstance(row, dict):
            continue
        affinity = str(row.get("station_affinity", ""))
        bonus = int(row.get("station_tier_bonus", 0))
        if affinity and bonus > 0:
            available[affinity] = max(available.get(affinity, 0), bonus)
    return available


def _knowledge_reason(
    recipe: dict,
    reachable: set[str],
    definitions: dict,
    components: dict,
    codex_root_ids: set[str],
    source_cardinality: dict[str, dict],
) -> str:
    source = str(recipe.get("knowledge_source", "starter"))
    if source == "starter" or not source:
        return ""
    if source == "book":
        book_id = str(recipe.get("knowledge_book_id", ""))
        if not book_id or book_id not in definitions:
            return "unknown_book"
        book = definitions[book_id]
        if (
            str(book.get("use_kind", "")) != "read_skill_book"
            or str(book.get("book_id", "")) != book_id
        ):
            return "invalid_book_definition"
        return "" if book_id in reachable else "unreachable_book"
    if source == "reverse_engineer":
        component_id = str(recipe.get("reverse_engineer_component", ""))
        component = components.get(component_id)
        if not component_id or not isinstance(component, dict):
            return "unknown_reverse_component"
        count = recipe.get("reverse_engineer_count", 3)
        if isinstance(count, bool) or not isinstance(count, int) or count <= 0:
            raise SourceError(
                f"schema recipe {recipe.get('recipe_id', '<unknown>')}: reverse_engineer_count must be a positive integer"
            )
        item_form = str(component.get("item_form", ""))
        if not item_form or item_form not in reachable:
            return "unreachable_reverse_source"
        cardinality = source_cardinality.get(item_form, {})
        if bool(cardinality.get("repeatable", False)):
            return ""
        finite_quantity = float(cardinality.get("finite_quantity", 0.0))
        if finite_quantity >= count:
            return ""
        if finite_quantity > 0.0:
            return "insufficient_reverse_source_quantity"
        return "unverified_reverse_source_quantity"
    if source == "codex":
        codex_id = str(recipe.get("knowledge_codex_id", ""))
        if not codex_id:
            return "missing_codex_id"
        return "" if codex_id in codex_root_ids else "unreachable_codex_source"
    return f"unknown_{source}_source"


def _recipe_gate_reason(
    recipe: dict,
    reachable: set[str],
    definitions: dict,
    station_tiers: dict[str, int],
    components: dict,
    codex_root_ids: set[str],
    source_cardinality: dict[str, dict],
) -> str:
    knowledge_reason = _knowledge_reason(
        recipe, reachable, definitions, components, codex_root_ids,
        source_cardinality,
    )
    if knowledge_reason:
        return knowledge_reason
    required_tier = int(recipe.get("station_tier_min", 0))
    station_kind = str(recipe.get("station_kind", ""))
    if required_tier > station_tiers.get(station_kind, 0):
        return "unreachable_station_tier"
    return ""


def _reachable_closure(
    source_model: dict, conversions: list[dict], roots: list[dict]
) -> set[str]:
    reachable = {row["item_id"] for row in roots}
    definitions = source_model.get("definitions", {})
    station_tiers = _station_tiers(source_model)
    components = source_model.get("components", {})
    codex_root_ids = set(source_model.get("codex_root_ids", []))
    source_cardinality = _source_cardinality(source_model, conversions, roots)
    changed = True
    while changed:
        changed = False
        for conversion in conversions:
            if not set(conversion["inputs"]).issubset(reachable):
                continue
            if conversion["kind"] == "recipe":
                if _recipe_gate_reason(
                    conversion["recipe"], reachable, definitions, station_tiers,
                    components, codex_root_ids, source_cardinality,
                ):
                    continue
            for item_id in conversion["outputs"]:
                if item_id not in reachable:
                    reachable.add(item_id)
                    changed = True
    return reachable


def _referenced_item_ids(source_model: dict, conversions: list[dict], roots: list[dict]) -> set[str]:
    referenced = {row["item_id"] for row in roots}
    for conversion in conversions:
        referenced.update(conversion["inputs"])
        referenced.update(conversion["outputs"])
    referenced.update(source_model.get("repair_parts", []))
    referenced.update(source_model.get("repair_tools", []))
    for recipe in source_model.get("recipes", []):
        if str(recipe.get("knowledge_source", "starter")) == "book":
            book_id = str(recipe.get("knowledge_book_id", ""))
            if book_id:
                referenced.add(book_id)
    for row in source_model.get("components", {}).values():
        if isinstance(row, dict):
            item_form = str(row.get("item_form", ""))
            if item_form:
                referenced.add(item_form)
    return referenced


def _component_findings(source_model: dict) -> tuple[list[str], list[dict], list[dict]]:
    definitions = source_model.get("definitions", {})
    base_definition_ids = set(
        source_model.get("base_item_definition_ids", definitions.keys())
    )
    missing: list[str] = []
    mass_mismatches: list[dict] = []
    definition_gaps: list[dict] = []
    for component_id, component in sorted(source_model.get("components", {}).items()):
        item_form = str(component.get("item_form", ""))
        if not item_form or item_form not in definitions:
            if item_form:
                missing.append(item_form)
            else:
                definition_gaps.append(
                    {"component_id": component_id, "item_form": item_form, "reason": "missing_item_form"}
                )
            continue
        definition = definitions[item_form]
        catalog_mass = float(component.get("mass", 0.0))
        item_weight = float(definition.get("weight", 0.0))
        if (
            catalog_mass <= 0.0
            or item_weight <= 0.0
            or not math.isclose(catalog_mass, item_weight, rel_tol=0.0, abs_tol=EPSILON)
        ):
            mass_mismatches.append(
                {
                    "component_id": component_id,
                    "item_form": item_form,
                    "catalog_mass": catalog_mass,
                    "item_weight": item_weight,
                }
            )
        category = str(definition.get("category", ""))
        max_stack = int(definition.get("max_stack", 99))
        reasons = []
        if item_form not in base_definition_ids:
            reasons.append("must_be_in_base_item_definitions")
        if category not in ("component", "part"):
            reasons.append("invalid_category")
        if max_stack != 1:
            reasons.append("max_stack_must_equal_one")
        if reasons:
            definition_gaps.append(
                {
                    "component_id": component_id,
                    "item_form": item_form,
                    "reasons": reasons,
                }
            )
    return sorted(set(missing)), mass_mismatches, definition_gaps


def _tool_compatibility_findings(source_model: dict) -> list[dict]:
    outputs = {
        str(recipe.get("produces", {}).get("item_id", ""))
        for recipe in source_model.get("recipes", [])
        if isinstance(recipe.get("produces"), dict)
    }
    definitions = source_model.get("definitions", {})
    work_actions = source_model.get("work_actions", {})
    quality_effects = source_model.get("quality_effects", {})
    findings: list[dict] = []
    for item_id, expected_tuple in sorted(CRAFTED_TOOL_COMPATIBILITY.items()):
        if item_id not in outputs:
            continue
        expected = set(expected_tuple)
        row = definitions.get(item_id, {})
        raw = row.get("compatible_work_action_ids", []) if isinstance(row, dict) else []
        actual = set(raw) if isinstance(raw, list) and all(isinstance(v, str) for v in raw) else set()
        reasons = []
        if actual != expected:
            reasons.append("compatibility_mismatch")
        for action_id in sorted(expected):
            action = work_actions.get(action_id, {})
            if not isinstance(action, dict) or str(action.get("tool_class", "")) != "welding_lance":
                reasons.append(f"invalid_action_contract:{action_id}")
        quality_row = quality_effects.get(item_id, {})
        if (
            not isinstance(quality_row, dict)
            or str(quality_row.get("consumer", "")) != "tool_work_speed"
        ):
            reasons.append("quality_consumer_mismatch")
        if reasons:
            findings.append(
                {
                    "item_id": item_id,
                    "expected_action_ids": sorted(expected),
                    "actual_action_ids": sorted(actual),
                    "reasons": reasons,
                }
            )
    return findings


def _compatible_tool_actions(source_model: dict, reachable: set[str]) -> list[dict]:
    """Return only crafted item/action pairs proved by data and live work flow."""

    definitions = source_model.get("definitions", {})
    work_actions = source_model.get("work_actions", {})
    quality_effects = source_model.get("quality_effects", {})
    raw_runtime_pairs = source_model.get("runtime_tool_action_classes", [])
    if not isinstance(definitions, dict) or not isinstance(work_actions, dict) \
            or not isinstance(quality_effects, dict) or not isinstance(raw_runtime_pairs, list):
        return []
    runtime_pairs: set[tuple[str, str]] = set()
    for row in raw_runtime_pairs:
        if not isinstance(row, dict) or set(row) != {"action_id", "tool_class"}:
            continue
        action_id, tool_class = row.get("action_id"), row.get("tool_class")
        if isinstance(action_id, str) and action_id and isinstance(tool_class, str) and tool_class:
            runtime_pairs.add((action_id, tool_class))

    pairs: list[dict] = []
    for item_id, expected_actions in sorted(CRAFTED_TOOL_COMPATIBILITY.items()):
        if item_id not in reachable:
            continue
        definition = definitions.get(item_id)
        if not isinstance(definition, dict):
            continue
        raw_actions = definition.get("compatible_work_action_ids", [])
        if not isinstance(raw_actions, list) or not all(isinstance(value, str) for value in raw_actions):
            continue
        if set(raw_actions) != set(expected_actions):
            continue
        quality = quality_effects.get(item_id)
        if not isinstance(quality, dict) or quality.get("consumer") != "tool_work_speed":
            continue
        for action_id in sorted(expected_actions):
            action = work_actions.get(action_id)
            if not isinstance(action, dict):
                continue
            tool_class = action.get("tool_class")
            if not isinstance(tool_class, str) or not tool_class:
                continue
            if (action_id, tool_class) not in runtime_pairs:
                continue
            pairs.append({"item_id": item_id, "action_id": action_id})
    return pairs


def _tarjan_components(graph: dict[str, set[str]]) -> list[list[str]]:
    index = 0
    stack: list[str] = []
    on_stack: set[str] = set()
    indices: dict[str, int] = {}
    low_links: dict[str, int] = {}
    components: list[list[str]] = []

    def visit(node: str) -> None:
        nonlocal index
        indices[node] = index
        low_links[node] = index
        index += 1
        stack.append(node)
        on_stack.add(node)
        for neighbor in sorted(graph.get(node, set())):
            if neighbor not in indices:
                visit(neighbor)
                low_links[node] = min(low_links[node], low_links[neighbor])
            elif neighbor in on_stack:
                low_links[node] = min(low_links[node], indices[neighbor])
        if low_links[node] == indices[node]:
            component: list[str] = []
            while True:
                member = stack.pop()
                on_stack.remove(member)
                component.append(member)
                if member == node:
                    break
            components.append(sorted(component))

    for node in sorted(graph):
        if node not in indices:
            visit(node)
    return sorted(components)


def _mandatory_prerequisite_cycles(
    conversions: list[dict], reachable: set[str]
) -> list[dict]:
    """Report conversion SCCs that have no reachable entry item.

    A cyclic conversion is harmless when a root or another conversion reaches
    one of its items. When none is reachable, every member depends on the
    cycle itself and the group is a mandatory-prerequisite deadlock.
    """

    graph: dict[str, set[str]] = {}
    for conversion in conversions:
        for input_id in conversion["inputs"]:
            graph.setdefault(input_id, set())
            for output_id in conversion["outputs"]:
                graph[input_id].add(output_id)
                graph.setdefault(output_id, set())

    groups: list[dict] = []
    for item_ids in _tarjan_components(graph):
        item_set = set(item_ids)
        has_cycle = len(item_ids) > 1 or any(
            item_id in graph.get(item_id, set()) for item_id in item_ids
        )
        if not has_cycle or item_set.intersection(reachable):
            continue
        conversion_ids = sorted(
            conversion["conversion_id"]
            for conversion in conversions
            if set(conversion["inputs"]).intersection(item_set)
            and set(conversion["outputs"]).intersection(item_set)
        )
        if conversion_ids:
            groups.append(
                {"item_ids": item_ids, "conversion_ids": conversion_ids}
            )
    return groups


def _titanium_donor_deconstruction_routes(
    recipes: list[dict], roots: list[dict], reachable: set[str]
) -> tuple[list[dict], list[dict]]:
    """Validate the two authored loot-to-titanium donor paths.

    This deliberately verifies table reachability, not a deterministic roll;
    a donor absent from one observed container never invalidates its catalog
    route. The returned route rows make the exact donor evidence inspectable.
    """

    by_id = {str(recipe.get("recipe_id", "")): recipe for recipe in recipes}
    routes: list[dict] = []
    gaps: list[dict] = []
    for recipe_id, donor_id in sorted(TITANIUM_DONOR_DECONSTRUCTIONS.items()):
        recipe = by_id.get(recipe_id)
        reasons: list[str] = []
        if not isinstance(recipe, dict):
            gaps.append({"recipe_id": recipe_id, "donor_id": donor_id, "reasons": ["missing_recipe"]})
            continue
        if str(recipe.get("category", "")) != "deconstruction":
            reasons.append("invalid_category")
        if recipe.get("ingredients") != {donor_id: 1}:
            reasons.append("invalid_donor_bom")
        if recipe.get("produces") != {"item_id": "titanium_ingot", "quantity": 1}:
            reasons.append("invalid_titanium_output")
        required_skill_level = recipe.get("required_skill_level")
        if isinstance(required_skill_level, bool) or not isinstance(required_skill_level, int):
            raise SourceError(
                f"schema recipe {recipe_id}: required_skill_level must be an integer"
            )
        if required_skill_level != 1:
            reasons.append("invalid_skill_level")
        if str(recipe.get("station_kind", "")) != "workbench":
            reasons.append("invalid_station")
        loot_sources = sorted(
            str(row.get("source", ""))
            for row in roots
            if row.get("item_id") == donor_id
            and str(row.get("source", "")).startswith("loot:")
        )
        if not loot_sources:
            reasons.append("missing_live_loot_source")
        if donor_id not in reachable:
            reasons.append("unreachable_donor")
        if "titanium_ingot" not in reachable:
            reasons.append("unreachable_titanium_output")
        route = {
            "recipe_id": recipe_id,
            "donor_id": donor_id,
            "loot_sources": loot_sources,
            "station_kind": str(recipe.get("station_kind", "")),
            "required_skill_level": required_skill_level,
        }
        routes.append(route)
        if reasons:
            gaps.append({**route, "reasons": reasons})
    return routes, gaps


def _zero_power_conversions(rows: Iterable[dict]) -> list[dict]:
    conversions = []
    for index, row in enumerate(rows):
        if "inputs" in row and "outputs" in row:
            conversion_id = row.get("conversion_id", row.get("route_id"))
            if not isinstance(conversion_id, str) or not conversion_id:
                raise SourceError(f"schema conversion[{index}].conversion_id")
            conversion = {
                "conversion_id": conversion_id,
                "kind": str(row.get("kind", "conversion")),
                "inputs": _quantity_map(
                    row.get("inputs"),
                    f"conversion[{index}].inputs",
                    allow_empty=True,
                ),
                "outputs": _quantity_map(row.get("outputs"), f"conversion[{index}].outputs"),
                "power_cost": _nonnegative_number(
                    row.get("power_cost", 0.0), f"conversion[{index}].power_cost"
                ),
            }
        else:
            conversion = _recipe_conversion(row, index)
        if conversion["power_cost"] <= EPSILON:
            conversions.append(conversion)
    return conversions


def _net_vector(conversions: list[dict], firing_counts: tuple[int, ...]) -> dict[str, float]:
    net: dict[str, float] = {}
    for conversion, count in zip(conversions, firing_counts):
        if count <= 0:
            continue
        for item_id, quantity in conversion["outputs"].items():
            net[item_id] = net.get(item_id, 0.0) + quantity * count
        for item_id, quantity in conversion["inputs"].items():
            net[item_id] = net.get(item_id, 0.0) - quantity * count
    return {
        item_id: quantity
        for item_id, quantity in sorted(net.items())
        if not math.isclose(quantity, 0.0, rel_tol=0.0, abs_tol=EPSILON)
    }


def _witness(conversions: list[dict], firing_counts: tuple[int, ...]) -> dict[str, int]:
    return {
        conversion["conversion_id"]: count
        for conversion, count in zip(conversions, firing_counts)
        if count > 0
    }


def _search_firing_witnesses(
    conversions: list[dict], max_firing_count: int, max_combinations: int
) -> tuple[tuple[int, ...] | None, tuple[int, ...] | None, bool]:
    if max_firing_count <= 0 or max_combinations <= 0:
        return None, None, False
    profitable = None
    neutral = None
    examined = 0
    exhausted = True
    for counts in itertools.product(range(max_firing_count + 1), repeat=len(conversions)):
        if not any(counts):
            continue
        if examined >= max_combinations:
            exhausted = False
            break
        examined += 1
        net = _net_vector(conversions, counts)
        if not net:
            if neutral is None:
                neutral = counts
            continue
        if all(quantity >= -EPSILON for quantity in net.values()) and any(
            quantity > EPSILON for quantity in net.values()
        ):
            profitable = counts
            break
    return profitable, neutral, exhausted


def _find_conservation_certificate(
    conversions: list[dict],
    max_weight: int,
    max_combinations: int,
) -> tuple[dict[str, int] | None, bool]:
    if max_weight <= 0 or max_combinations <= 0:
        return None, False
    item_ids = sorted(
        {
            item_id
            for conversion in conversions
            for item_id in (*conversion["inputs"], *conversion["outputs"])
        }
    )
    examined = 0
    exhausted = True
    for values in itertools.product(range(1, max_weight + 1), repeat=len(item_ids)):
        if examined >= max_combinations:
            exhausted = False
            break
        examined += 1
        weights = dict(zip(item_ids, values))
        conservative = True
        for conversion in conversions:
            delta = sum(
                weights[item_id] * quantity
                for item_id, quantity in conversion["outputs"].items()
            ) - sum(
                weights[item_id] * quantity
                for item_id, quantity in conversion["inputs"].items()
            )
            if delta > EPSILON:
                conservative = False
                break
        if conservative:
            return weights, exhausted
    return None, exhausted


def analyze_zero_power_cycles(
    conversions_or_recipes: Iterable[dict],
    *,
    max_firing_count: int = 6,
    max_firing_combinations: int = 100_000,
    max_certificate_weight: int = 8,
    max_certificate_combinations: int = 100_000,
) -> list[dict]:
    """Classify every zero-power SCC with a witness or safety certificate."""

    conversions = _zero_power_conversions(conversions_or_recipes)
    graph: dict[str, set[str]] = {}
    for conversion in conversions:
        for input_id in conversion["inputs"]:
            graph.setdefault(input_id, set())
            for output_id in conversion["outputs"]:
                graph[input_id].add(output_id)
                graph.setdefault(output_id, set())

    groups: list[dict] = []
    for conversion in conversions:
        if conversion["inputs"]:
            continue
        firing = (1,)
        groups.append(
            {
                "item_ids": sorted(conversion["outputs"]),
                "conversion_ids": [conversion["conversion_id"]],
                "classification": "profitable",
                "firing_witness": {conversion["conversion_id"]: 1},
                "neutral_witness": {},
                "net_items": _net_vector([conversion], firing),
                "conservation_certificate": {},
                "firing_search_exhausted": True,
                "certificate_search_exhausted": True,
            }
        )
    for item_ids in _tarjan_components(graph):
        item_set = set(item_ids)
        has_cycle = len(item_ids) > 1 or any(
            item_id in graph.get(item_id, set()) for item_id in item_ids
        )
        if not has_cycle:
            continue
        group_conversions = [
            conversion
            for conversion in conversions
            if set(conversion["outputs"]) & item_set
            and set(conversion["inputs"]) & item_set
        ]
        group_conversions.sort(key=lambda row: row["conversion_id"])
        profitable, neutral, firing_exhausted = _search_firing_witnesses(
            group_conversions, max_firing_count, max_firing_combinations
        )
        certificate = None
        certificate_exhausted = False
        classification = "profitable" if profitable is not None else "not_verified"
        if profitable is None:
            certificate, certificate_exhausted = _find_conservation_certificate(
                group_conversions,
                max_certificate_weight,
                max_certificate_combinations,
            )
            if certificate is not None:
                classification = "neutral" if neutral is not None else "non_profitable"
        chosen = profitable or neutral
        groups.append(
            {
                "item_ids": item_ids,
                "conversion_ids": [row["conversion_id"] for row in group_conversions],
                "classification": classification,
                "firing_witness": _witness(group_conversions, profitable) if profitable else {},
                "neutral_witness": _witness(group_conversions, neutral) if neutral else {},
                "net_items": _net_vector(group_conversions, chosen) if chosen else {},
                "conservation_certificate": certificate or {},
                "firing_search_exhausted": firing_exhausted,
                "certificate_search_exhausted": certificate_exhausted,
            }
        )
    return sorted(groups, key=lambda row: (row["item_ids"], row["conversion_ids"]))


def analyze_model(source_model: dict) -> dict:
    recipes = source_model.get("recipes", [])
    if not isinstance(recipes, list):
        raise SourceError("schema model.recipes")
    conversions = _all_conversions(source_model)
    roots = _root_rows(source_model)
    definitions = source_model.get("definitions", {})
    if not isinstance(definitions, dict):
        raise SourceError("schema model.definitions")
    reachable = _reachable_closure(source_model, conversions, roots)
    source_cardinality = _source_cardinality(source_model, conversions, roots)
    referenced = _referenced_item_ids(source_model, conversions, roots)
    unknown_ids = sorted(referenced - set(definitions))

    recipe_conversions = [row for row in conversions if row["kind"] == "recipe"]
    output_ids = sorted(
        {item_id for conversion in recipe_conversions for item_id in conversion["outputs"]}
    )
    prerequisite_ids = sorted(
        {item_id for conversion in recipe_conversions for item_id in conversion["inputs"]}
    )
    self_dependencies = sorted(
        conversion["conversion_id"]
        for conversion in recipe_conversions
        if set(conversion["inputs"]) & set(conversion["outputs"])
    )

    missing_forms, mass_mismatches, component_definition_gaps = _component_findings(
        source_model
    )
    sourced_components = set(source_model.get("component_source_ids", []))
    unsourced_component_ids = []
    if bool(source_model.get("require_component_sources", False)):
        for component_id, component in sorted(source_model.get("components", {}).items()):
            item_form = str(component.get("item_form", "")) if isinstance(component, dict) else ""
            if component_id not in sourced_components and item_form not in reachable:
                unsourced_component_ids.append(component_id)
    tool_gaps = _tool_compatibility_findings(source_model)
    compatible_tool_actions = _compatible_tool_actions(source_model, reachable)
    station_tiers = _station_tiers(source_model)
    knowledge_gaps = []
    station_tier_gaps = []
    station_binding_gaps: set[str] = set()
    runtime_station_kinds = set(source_model.get("crafting_station_kinds", []))
    for recipe in sorted(recipes, key=lambda row: str(row.get("recipe_id", ""))):
        recipe_id = str(recipe.get("recipe_id", ""))
        knowledge_reason = _knowledge_reason(
            recipe,
            reachable,
            definitions,
            source_model.get("components", {}),
            set(source_model.get("codex_root_ids", [])),
            source_cardinality,
        )
        if knowledge_reason:
            knowledge_gaps.append({"recipe_id": recipe_id, "reason": knowledge_reason})
        required_tier = int(recipe.get("station_tier_min", 0))
        station_kind = str(recipe.get("station_kind", ""))
        if bool(source_model.get("require_station_bindings", False)) and (
            not station_kind or station_kind not in runtime_station_kinds
        ):
            station_binding_gaps.add(station_kind or "<missing>")
        available_tier = station_tiers.get(station_kind, 0)
        if required_tier > available_tier:
            station_tier_gaps.append(
                {
                    "recipe_id": recipe_id,
                    "station_kind": station_kind,
                    "required_tier": required_tier,
                    "available_tier": available_tier,
                }
            )

    # Junk salvage is also a zero-power conversion and participates in the same
    # economy. Production routes retain their authored power costs and therefore
    # cannot be part of a zero-power SCC.
    cycle_groups = analyze_zero_power_cycles(conversions)
    cycle_blockers = [
        row
        for row in cycle_groups
        if row["classification"] in ("profitable", "not_verified")
    ]
    unreachable_prerequisites = sorted(set(prerequisite_ids) - reachable)
    unreachable_outputs = sorted(set(output_ids) - reachable)
    unreachable_repair_parts = sorted(set(source_model.get("repair_parts", [])) - reachable)
    unreachable_repair_tools = sorted(set(source_model.get("repair_tools", [])) - reachable)
    mandatory_cycles = _mandatory_prerequisite_cycles(conversions, reachable)
    titanium_donor_routes, titanium_donor_gaps = _titanium_donor_deconstruction_routes(
        recipes, roots, reachable
    )

    blockers = []
    finding_groups = {
        "unknown_ids": unknown_ids,
        "unreachable_prerequisite_ids": unreachable_prerequisites,
        "unreachable_output_ids": unreachable_outputs,
        "missing_component_item_forms": missing_forms,
        "component_mass_mismatches": mass_mismatches,
        "component_definition_gaps": component_definition_gaps,
        "unsourced_component_ids": unsourced_component_ids,
        "tool_compatibility_gaps": tool_gaps,
        "knowledge_bootstrap_gaps": knowledge_gaps,
        "station_binding_gaps": sorted(station_binding_gaps),
        "station_tier_gaps": station_tier_gaps,
        "unreachable_repair_parts": unreachable_repair_parts,
        "unreachable_repair_tools": unreachable_repair_tools,
        "mandatory_prerequisite_cycles": mandatory_cycles,
        "titanium_donor_deconstruction_gaps": titanium_donor_gaps,
        "zero_power_cycle_blockers": cycle_blockers,
    }
    for finding_name, rows in finding_groups.items():
        if rows:
            blockers.append({"finding": finding_name, "count": len(rows)})

    return {
        "schema": "crafting_economy_report_v1",
        "recipe_count": len(recipes),
        "distinct_recipe_output_count": len(output_ids),
        "root_ids": sorted({row["item_id"] for row in roots}),
        "root_evidence": roots,
        "source_cardinality": source_cardinality,
        "runtime_source_hashes": dict(
            sorted(source_model.get("runtime_source_hashes", {}).items())
        ),
        "reachable_ids": sorted(reachable),
        "unreachable_prerequisite_ids": unreachable_prerequisites,
        "unreachable_output_ids": unreachable_outputs,
        "unknown_ids": unknown_ids,
        "self_dependencies": self_dependencies,
        "missing_component_item_forms": missing_forms,
        "component_mass_mismatches": mass_mismatches,
        "component_definition_gaps": component_definition_gaps,
        "unsourced_component_ids": unsourced_component_ids,
        "tool_compatibility_gaps": tool_gaps,
        "compatible_tool_actions": compatible_tool_actions,
        "knowledge_bootstrap_gaps": knowledge_gaps,
        "station_binding_gaps": sorted(station_binding_gaps),
        "station_tier_gaps": station_tier_gaps,
        "available_station_tiers": dict(sorted(station_tiers.items())),
        "unreachable_repair_parts": unreachable_repair_parts,
        "unreachable_repair_tools": unreachable_repair_tools,
        "mandatory_prerequisite_cycles": mandatory_cycles,
        "titanium_donor_deconstruction_routes": titanium_donor_routes,
        "titanium_donor_deconstruction_gaps": titanium_donor_gaps,
        "zero_power_cycle_groups": cycle_groups,
        "blockers": blockers,
        "ok": not blockers,
    }


def check(root: Path | str) -> dict:
    return analyze_model(model(root))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args(argv)
    try:
        report = check(arguments.root)
    except SourceError as error:
        print(f"CRAFTING ECONOMY BLOCKED source_error={error}")
        return 1
    if arguments.json:
        print(json.dumps(report, sort_keys=True))
    else:
        marker = "CRAFTING ECONOMY PASS" if report["ok"] else "CRAFTING ECONOMY BLOCKED"
        print(marker)
        print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
