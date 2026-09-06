import copy
import json
import re
import shutil
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

import tools.check_crafting_economy as crafting_economy

from tools.check_crafting_economy import (
    SourceError,
    _load_runtime_contracts,
    _runtime_loot_table_sources,
    analyze_model,
    analyze_zero_power_cycles,
    check,
    merged_defs,
    model,
    read,
)


ROOT = Path(__file__).parents[1]


RUNTIME_SOURCE_PATHS = (
    "scripts/procgen/playable_generated_ship.gd",
    "scripts/systems/ship_work_transaction.gd",
    "scripts/systems/work_action_driver.gd",
    "scripts/systems/work_action_state.gd",
    "scripts/systems/work_action_catalog.gd",
    "scripts/systems/item_quality_effects.gd",
    "scripts/systems/quality_tier_resolver.gd",
    "scripts/systems/inventory_state.gd",
    "scripts/systems/item_lot_ledger.gd",
    "scripts/systems/item_defs.gd",
    "scripts/systems/ship_work_context.gd",
    "scripts/systems/ship_instance.gd",
    "scripts/tools/production_station.gd",
    "scripts/systems/water_recycler_state.gd",
    "scripts/systems/component_catalog.gd",
    "scripts/systems/component_placement_state.gd",
    "scripts/procgen/wall_door_resolver.gd",
)

RUNTIME_TOOL_ACTION_DATA_PATHS = (
    "data/items/quality_effects.json",
    "data/work_actions/work_action_catalog.json",
    "data/recipes/recipe_definitions.json",
    "data/tools/tool_definitions.json",
    "data/items/item_definitions.json",
    "data/items/medicine_definitions.json",
    "data/items/stimulant_definitions.json",
    "data/combat/ammo_definitions.json",
    "data/items/utility_item_definitions.json",
    "data/items/trade_item_definitions.json",
)


def _copy_runtime_sources(destination: Path, *, omit: tuple[str, ...] = ()) -> None:
    for relative_path in RUNTIME_SOURCE_PATHS + RUNTIME_TOOL_ACTION_DATA_PATHS:
        if relative_path in omit:
            continue
        target = destination / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative_path, target)


def _remove_calls(source: str, function_name: str) -> str:
    return re.sub(
        rf"(?m)^(?!func\s+{re.escape(function_name)}\b)[ \t]*{re.escape(function_name)}\(\)[ \t]*\r?\n",
        "",
        source,
    )


def _remove_from_function(source: str, function_name: str, statement: str) -> str:
    match = re.search(
        rf"(?ms)^func\s+{re.escape(function_name)}\b.*?(?=^func\s|\Z)", source
    )
    if match is None or statement not in match.group(0):
        raise AssertionError(f"missing {statement!r} in {function_name}")
    replacement = match.group(0).replace(statement, "", 1)
    return source[:match.start()] + replacement + source[match.end():]


def _replace_in_function(
    source: str, function_name: str, statement: str, replacement: str
) -> str:
    match = re.search(
        rf"(?ms)^func\s+{re.escape(function_name)}\b.*?(?=^func\s|\Z)", source
    )
    if match is None or statement not in match.group(0):
        raise AssertionError(f"missing {statement!r} in {function_name}")
    body = match.group(0).replace(statement, replacement, 1)
    return source[:match.start()] + body + source[match.end():]


def _current_reviewed_tool_action_hashes() -> dict[str, str]:
    """Test-only frozen snapshot for source-adapter cases.

    Production deliberately keeps the coordinator pin pending P10 review.  The
    adapter tests still need an exact, local baseline so their individual
    semantic mutants reach the assertion they were written to exercise.
    """

    return {
        relative_path: crafting_economy._normalized_source_hash(
            (ROOT / relative_path).read_text(encoding="utf-8")
        )
        for relative_path in crafting_economy.REVIEWED_TOOL_ACTION_FILE_HASHES
    }


def _definition(item_id: str, **overrides) -> dict:
    row = {
        "display_name": item_id.replace("_", " ").title(),
        "category": "part",
        "weight": 1.0,
        "max_stack": 20,
    }
    row.update(overrides)
    return row


def _recipe(
    recipe_id: str,
    inputs: dict,
    output_id: str,
    output_quantity: int = 1,
    power_cost: float = 0.0,
    **overrides,
) -> dict:
    row = {
        "recipe_id": recipe_id,
        "ingredients": inputs,
        "produces": {"item_id": output_id, "quantity": output_quantity},
        "power_cost": power_cost,
        "station_kind": "workbench",
        "station_tier_min": 0,
        "knowledge_source": "starter",
    }
    row.update(overrides)
    return row


def _synthetic_model(recipes: list, roots=(), definitions=None) -> dict:
    ids = set(roots)
    for recipe in recipes:
        ids.update(recipe["ingredients"])
        ids.add(recipe["produces"]["item_id"])
    return {
        "recipes": copy.deepcopy(recipes),
        "definitions": definitions
        or {item_id: _definition(item_id) for item_id in ids},
        "loot_roots": [
            {"item_id": item_id, "source": "fixture:loot", "quantity": 1}
            for item_id in roots
        ],
        "junk_conversions": [],
        "production_routes": [],
        "components": {},
        "role_sets": {},
        "component_source_ids": [],
        "systems": [],
        "repair_parts": [],
        "repair_tools": [],
        "work_actions": {
            "weld_patch": {"tool_class": "welding_lance"},
            "cut_wall": {"tool_class": "welding_lance"},
        },
        "quality_effects": {
            "welder": {"consumer": "tool_work_speed"},
            "plasma_cutter": {"consumer": "tool_work_speed"},
        },
        "pickups": [],
    }


class RealSourceAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self._reviewed_path_patch = patch.object(
            crafting_economy,
            "REVIEWED_TOOL_ACTION_FILE_HASHES",
            _current_reviewed_tool_action_hashes(),
        )
        self._reviewed_path_patch.start()

    def tearDown(self) -> None:
        self._reviewed_path_patch.stop()

    def test_real_adapters_match_runtime_shapes(self):
        source_model = model(ROOT)
        self.assertEqual(len(source_model["recipes"]), 61)
        self.assertEqual(
            {row["item_id"] for row in source_model["pickups"]},
            {"portable_oxygen_pump", "junction_calibrator"},
        )
        self.assertEqual(source_model["water_route"]["power_cost"], 5.0)
        self.assertEqual(len(source_model["components"]), 11)
        self.assertTrue(source_model["component_source_ids"])
        self.assertTrue(source_model["repair_parts"])
        self.assertEqual(
            set(source_model["repair_tools"]), {"welder", "plasma_cutter"}
        )
        self.assertNotIn(
            "loot:repair_tools",
            {row["source"] for row in source_model["loot_roots"]},
        )

    def test_runtime_contract_requires_live_pickup_and_station_invocations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/playable_generated_ship.gd"
            self.assertEqual(len(_load_runtime_contracts(root)["pickups"]), 2)
            source = _remove_calls(
                path.read_text(encoding="utf-8"), "_build_tool_pickup"
            )
            path.write_text(source, encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "not reachable from runtime lifecycle"):
                _load_runtime_contracts(root)

    def test_owner_scoped_crafting_builder_has_a_live_positive_contract(self):
        contracts = _load_runtime_contracts(ROOT)
        hashes = contracts["source_hashes"]
        self.assertTrue(contracts["crafting_stations"])
        self.assertIn(
            "scripts/procgen/playable_generated_ship.gd:_ensure_crafting_stations_for_owner",
            hashes,
        )

    def test_owner_scoped_crafting_builder_rejects_lifecycle_and_binding_mutants(self):
        mutants = (
            (
                "_build_crafting_stations",
                "\t_ensure_crafting_stations_for_owner(owner)\n",
                "owner builder invocation missing",
            ),
            (
                "_ensure_crafting_stations_for_owner",
                "\tvar context = _ship_work_context_for(str(owner.ship_id))\n",
                "owner context missing",
            ),
            (
                "_ensure_crafting_stations_for_owner",
                "\t\t\tor not context.matches_binding(owner):\n",
                "owner binding missing",
            ),
            (
                "_ensure_crafting_stations_for_owner",
                "\t\towner.scene_root.add_child(st)\n",
                "scene registration missing",
            ),
            (
                "_ensure_crafting_stations_for_owner",
                "\t\tcrafting_stations.append(st)\n",
                "interaction registration missing",
            ),
        )
        for function_name, statement, expected in mutants:
            with self.subTest(expected=expected), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _copy_runtime_sources(root)
                path = root / "scripts/procgen/playable_generated_ship.gd"
                path.write_text(
                    _remove_from_function(
                        path.read_text(encoding="utf-8"), function_name, statement
                    ),
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(SourceError, expected):
                    _load_runtime_contracts(root)

    def test_owner_scoped_crafting_builder_rejects_shared_state_and_all_owner_path_mutants(self):
        mutants = (
            (
                "shared_constructor",
                "shared crafting state is not constructed",
            ),
            (
                "derelict_attach",
                "derelict attach builder invocation missing",
            ),
            (
                "restoration_rebind",
                "restoration rebind builder invocation missing",
            ),
            (
                "first_kind_only",
                "full kind loop missing",
            ),
            (
                "isolated_station_state",
                "shared state configure missing",
            ),
        )
        for mutant, expected in mutants:
            with self.subTest(mutant=mutant), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _copy_runtime_sources(root)
                path = root / "scripts/procgen/playable_generated_ship.gd"
                source = path.read_text(encoding="utf-8")
                if mutant == "shared_constructor":
                    source = _remove_from_function(
                        source,
                        "_build_runtime_nodes",
                        "\tcrafting_state = CraftingStateScript.new()\n",
                    )
                    # Comments, string literals, and a real constructor in an
                    # unreachable helper cannot replace the live bootstrap.
                    source += '''
# crafting_state = CraftingStateScript.new()
func _dead_crafting_state_constructor() -> void:
\tvar decoy := "crafting_state = CraftingStateScript.new()"
\tcrafting_state = CraftingStateScript.new()
'''
                elif mutant == "derelict_attach":
                    source = _remove_from_function(
                        source,
                        "_attach_derelict_active",
                        "\t_ensure_crafting_stations_for_owner(inst)\n",
                    )
                    source += '''
# _ensure_crafting_stations_for_owner(inst)
func _dead_derelict_station_attach(inst) -> void:
\tvar decoy := "_ensure_crafting_stations_for_owner(inst)"
\t_ensure_crafting_stations_for_owner(inst)
'''
                elif mutant == "restoration_rebind":
                    source = _remove_from_function(
                        source,
                        "_bind_current_ship_restoration_owners",
                        "\t_ensure_crafting_stations_for_owner(current_ship)\n",
                    )
                elif mutant == "first_kind_only":
                    source = _replace_in_function(
                        source,
                        "_ensure_crafting_stations_for_owner",
                        "\tfor kind in CRAFTING_STATION_KINDS:\n",
                        "\tfor kind in [CRAFTING_STATION_KINDS[0]]:\n",
                    )
                else:
                    source = _replace_in_function(
                        source,
                        "_ensure_crafting_stations_for_owner",
                        "st.configure(kind, context.crafting_state,",
                        "st.configure(kind, CraftingStateScript.new(),",
                    )
                path.write_text(source, encoding="utf-8")
                with self.assertRaisesRegex(SourceError, expected):
                    _load_runtime_contracts(root)

    def test_full_file_tool_action_guard_requires_final_review_and_catches_closure_drift(self):
        self._reviewed_path_patch.stop()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            with self.assertRaisesRegex(SourceError, "proof pin pending review"):
                crafting_economy._require_reviewed_tool_action_path(root)

            # The production coordinator pin intentionally remains pending until
            # reviewed R11 integration.  Do not compare the remaining historical
            # hashes to the moving worktree: this fixture approves its copied
            # snapshot only, then verifies full-file and semantic drift rejection.
            self.assertIsNone(
                crafting_economy.REVIEWED_TOOL_ACTION_FILE_HASHES[
                    crafting_economy.COORDINATOR_PATH
                ]
            )
            reviewed_hashes = {
                relative_path: crafting_economy._normalized_source_hash(
                    (root / relative_path).read_text(encoding="utf-8")
                )
                for relative_path in crafting_economy.REVIEWED_TOOL_ACTION_FILE_HASHES
            }
            with patch.object(
                crafting_economy,
                "REVIEWED_TOOL_ACTION_FILE_HASHES",
                reviewed_hashes,
            ):
                crafting_economy._require_reviewed_tool_action_path(root)
                for relative_path in reviewed_hashes:
                    with self.subTest(path=relative_path):
                        candidate = root / relative_path
                        original = candidate.read_text(encoding="utf-8")
                        candidate.write_text(original + "\n# reviewed-path-drift\n", encoding="utf-8")
                        with self.assertRaisesRegex(SourceError, "compatible tool action proof drift"):
                            crafting_economy._require_reviewed_tool_action_path(root)
                        candidate.write_text(original, encoding="utf-8")

                semantic_mutants = (
                    (
                        "scripts/systems/ship_work_transaction.gd",
                        'driver.call("start_action",',
                        'driver.call("start_other",',
                    ),
                    (
                        "scripts/systems/work_action_state.gd",
                        'context.get("work_speed_mult", 1.0)',
                        'context.get("unused_speed", 1.0)',
                    ),
                    (
                        "scripts/systems/work_action_driver.gd",
                        'preload("res://scripts/systems/work_action_state.gd")',
                        'preload("res://scripts/systems/other_action_state.gd")',
                    ),
                    (
                        "scripts/systems/item_quality_effects.gd",
                        '\t\t_items = ((parsed as Dictionary).get("items", {}) as Dictionary).duplicate(true)',
                        "\t\t_items = {}",
                    ),
                    (
                        "data/items/quality_effects.json",
                        '"tool_work_speed"',
                        '"quantity_only"',
                    ),
                )
                for relative_path, statement, replacement in semantic_mutants:
                    with self.subTest(semantic_path=relative_path):
                        candidate = root / relative_path
                        original = candidate.read_text(encoding="utf-8")
                        self.assertIn(statement, original)
                        candidate.write_text(original.replace(statement, replacement, 1), encoding="utf-8")
                        with self.assertRaisesRegex(SourceError, "compatible tool action proof drift"):
                            crafting_economy._require_reviewed_tool_action_path(root)
                        candidate.write_text(original, encoding="utf-8")

    def test_runtime_tool_action_extractor_ignores_comment_string_and_dead_helper_calls(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/playable_generated_ship.gd"
            source = _remove_from_function(
                path.read_text(encoding="utf-8"),
                "_try_work_action_interact",
                '\t\tvar has_weld_tool: bool = _has_compatible_work_tool("weld_patch", "welding_lance")\n',
            )
            source += '''
# _has_compatible_work_tool("weld_patch", "welding_lance")
func _dead_weld_action_probe() -> void:
\tvar decoy := "_has_compatible_work_tool(\\\"weld_patch\\\", \\\"welding_lance\\\")"
\t_has_compatible_work_tool("weld_patch", "welding_lance")
'''
            path.write_text(source, encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "compatible tool action proof drift"):
                _load_runtime_contracts(root)

    def test_runtime_tool_action_extractor_requires_the_live_action_dispatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/playable_generated_ship.gd"
            source = _remove_from_function(
                path.read_text(encoding="utf-8"),
                "_try_work_action_interact",
                '\t\t\t\t\taction_id = "weld_patch"\n',
            )
            source += '''
# action_id = "weld_patch"
func _dead_weld_action_dispatch() -> void:
\tvar decoy := "action_id = \\\"weld_patch\\\""
\taction_id = "weld_patch"
\ttool_class = "welding_lance"
'''
            path.write_text(source, encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "compatible tool action proof drift"):
                _load_runtime_contracts(root)

    def test_reviewed_tool_path_rejects_gate_lot_compatibility_and_dispatch_mutants(self):
        mutants = (
            (
                "_try_work_action_interact",
                "if has_weld_tool and has_plate:",
                "if false and has_plate:",
            ),
            (
                "_try_work_action_interact",
                'ctx["selected_tool_lot"] = _selected_work_tool_lot(tool_class, action_id)\n',
                "",
            ),
            (
                "_work_tool_item_is_compatible",
                "if str(action_v) == action_id:",
                "if false:",
            ),
            (
                "_try_work_action_interact",
                "\t\taction_id, target_id, target_kind, target_revision, ctx, work_payload,\n",
                "\t\t\"pry_panel\", target_id, target_kind, target_revision, ctx, work_payload,\n",
            ),
        )
        for function_name, statement, replacement in mutants:
            with self.subTest(function=function_name, statement=statement), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _copy_runtime_sources(root)
                path = root / "scripts/procgen/playable_generated_ship.gd"
                path.write_text(
                    _replace_in_function(
                        path.read_text(encoding="utf-8"),
                        function_name,
                        statement,
                        replacement,
                    ),
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(SourceError, "compatible tool action proof drift"):
                    _load_runtime_contracts(root)

    def test_reviewed_tool_quality_path_rejects_consumer_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/systems/work_action_driver.gd"
            path.write_text(
                _replace_in_function(
                    path.read_text(encoding="utf-8"),
                    "start_action",
                    '== "tool_work_speed"',
                    '== "quantity_only"',
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SourceError, "compatible tool action proof drift"):
                _load_runtime_contracts(root)

    def test_reviewed_tool_path_rejects_signature_parameter_order_mutants(self):
        mutants = (
            (
                "scripts/procgen/playable_generated_ship.gd",
                "_has_compatible_work_tool",
                "func _has_compatible_work_tool(action_id: String, tool_class: String) -> bool:",
                "func _has_compatible_work_tool(tool_class: String, action_id: String) -> bool:",
            ),
            (
                "scripts/systems/work_action_driver.gd",
                "start_action",
                "func start_action(action_id: String, target_id: String, context: Dictionary = {}) -> bool:",
                "func start_action(target_id: String, action_id: String, context: Dictionary = {}) -> bool:",
            ),
            (
                "scripts/systems/item_quality_effects.gd",
                "multiplier_for_lot",
                "func multiplier_for_lot(item_id: String, lot: Dictionary) -> float:",
                "func multiplier_for_lot(lot: Dictionary, item_id: String) -> float:",
            ),
        )
        for relative_path, function_name, statement, replacement in mutants:
            with self.subTest(path=relative_path, function=function_name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _copy_runtime_sources(root)
                path = root / relative_path
                path.write_text(
                    _replace_in_function(
                        path.read_text(encoding="utf-8"),
                        function_name,
                        statement,
                        replacement,
                    ),
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(SourceError, "compatible tool action proof drift"):
                    _load_runtime_contracts(root)

    def test_dead_helper_calls_do_not_authorize_bootstrap_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/playable_generated_ship.gd"
            source = path.read_text(encoding="utf-8")
            for function_name in (
                "_build_tool_pickup",
                "_build_junction_calibrator_pickup",
                "_build_crafting_stations",
                "_build_production_stations",
            ):
                source = _remove_calls(source, function_name)
            source += """

func _dead_economy_bootstrap() -> void:
	_build_tool_pickup()
	_build_junction_calibrator_pickup()
	_build_crafting_stations()
	_build_production_stations()
"""
            path.write_text(source, encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "not reachable from runtime lifecycle"):
                _load_runtime_contracts(root)

    def test_string_literals_do_not_authorize_bootstrap_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/playable_generated_ship.gd"
            source = path.read_text(encoding="utf-8")
            for function_name in (
                "_build_tool_pickup",
                "_build_junction_calibrator_pickup",
                "_build_crafting_stations",
                "_build_production_stations",
            ):
                source = _remove_calls(source, function_name)
            source = source.replace(
                "func _on_ship_loaded(summary: Dictionary) -> void:\n",
                'func _on_ship_loaded(summary: Dictionary) -> void:\n\tvar source_decoy := "_build_tool_pickup() _build_junction_calibrator_pickup() _build_crafting_stations() _build_production_stations()"\n',
            )
            path.write_text(source, encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "not reachable from runtime lifecycle"):
                _load_runtime_contracts(root)

    def test_production_station_requires_scene_and_interaction_registration(self):
        for removed_line, expected in (
            ("\t\thome_ship.scene_root.add_child(st)\n", "scene registration"),
            ("\t\tproduction_stations.append(st)\n", "interaction registration"),
        ):
            with self.subTest(removed_line=removed_line), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _copy_runtime_sources(root)
                path = root / "scripts/procgen/playable_generated_ship.gd"
                source = path.read_text(encoding="utf-8")
                path.write_text(
                    _remove_from_function(
                        source, "_build_production_stations", removed_line
                    ),
                    encoding="utf-8",
                )
                with self.assertRaisesRegex(SourceError, expected):
                    _load_runtime_contracts(root)

    def test_production_contract_requires_each_live_consumer(self):
        for omitted in (
            "scripts/tools/production_station.gd",
            "scripts/systems/water_recycler_state.gd",
        ):
            with self.subTest(omitted=omitted), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                _copy_runtime_sources(root, omit=(omitted,))
                with self.assertRaisesRegex(SourceError, f"missing {re.escape(omitted)}"):
                    _load_runtime_contracts(root)

    def test_runtime_contract_rejects_comment_only_calls_and_production_builder(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/playable_generated_ship.gd"
            source = path.read_text(encoding="utf-8")
            for function_name in (
                "_build_tool_pickup",
                "_build_junction_calibrator_pickup",
                "_build_crafting_stations",
                "_build_production_stations",
            ):
                source = _remove_calls(source, function_name)
                source += f"\n# {function_name}()\n"
            path.write_text(source, encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "not reachable from runtime lifecycle"):
                _load_runtime_contracts(root)

    def test_production_routes_require_live_production_bootstrap(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/playable_generated_ship.gd"
            source = path.read_text(encoding="utf-8")
            source = re.sub(
                r"(?ms)^func _build_production_stations\b.*?(?=^func |\Z)",
                "",
                source,
            )
            path.write_text(source, encoding="utf-8")
            with self.assertRaisesRegex(SourceError, "missing _build_production_stations"):
                _load_runtime_contracts(root)

    def test_comment_only_loot_table_identifier_is_not_a_runtime_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative_path in (
                "scripts/procgen/ship_generator.gd",
                "scripts/procgen/gameplay_slice_builder.gd",
                "scripts/procgen/room_variant_selector.gd",
                "scripts/procgen/playable_generated_ship.gd",
                "data/combat/threat_archetypes.json",
            ):
                path = root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(
                    "{}" if relative_path.endswith(".json") else '# only mentions "orphan_table"\n',
                    encoding="utf-8",
                )
            self.assertEqual(
                _runtime_loot_table_sources(root, {"orphan_table"}), {}
            )

    def test_unrelated_function_literal_is_not_a_runtime_loot_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = {
                "scripts/procgen/ship_generator.gd": "func generate():\n\treturn null\n",
                "scripts/procgen/gameplay_slice_builder.gd": "func build(_layout):\n\treturn {}\n",
                "scripts/procgen/room_variant_selector.gd": (
                    "func effects_for(_variant):\n\treturn {}\n\n"
                    "func unrelated_label():\n\tvar label = \"orphan_table\"\n"
                ),
                "scripts/procgen/playable_generated_ship.gd": "func _ready():\n\tpass\n",
            }
            for relative_path, source in sources.items():
                path = root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source, encoding="utf-8")
            threat_path = root / "data/combat/threat_archetypes.json"
            threat_path.parent.mkdir(parents=True, exist_ok=True)
            threat_path.write_text("{}", encoding="utf-8")
            self.assertEqual(
                _runtime_loot_table_sources(root, {"orphan_table"}), {}
            )

    def test_unrelated_loot_bias_mapping_is_not_a_runtime_loot_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative_path in (
                "scripts/procgen/ship_generator.gd",
                "scripts/procgen/gameplay_slice_builder.gd",
                "scripts/procgen/room_variant_selector.gd",
            ):
                target = root / relative_path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative_path, target)
            variant_path = root / "scripts/procgen/room_variant_selector.gd"
            variant_path.write_text(
                variant_path.read_text(encoding="utf-8")
                + '\nfunc unrelated_mapping() -> Dictionary:\n'
                + '\treturn {"loot_bias": "orphan_table"}\n',
                encoding="utf-8",
            )
            threat_path = root / "data/combat/threat_archetypes.json"
            threat_path.parent.mkdir(parents=True, exist_ok=True)
            threat_path.write_text("{}", encoding="utf-8")

            self.assertEqual(
                _runtime_loot_table_sources(root, {"orphan_table"}), {}
            )

    def test_incompatible_role_slot_does_not_create_a_component_source(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            catalog_path = root / "data/components/component_catalog.json"
            catalog_path.parent.mkdir(parents=True, exist_ok=True)
            catalog_path.write_text(
                json.dumps(
                    {
                        "components": {
                            "deck_machine": {
                                "item_form": "deck_machine",
                                "mass": 1,
                                "slot": "center",
                                "footprint_cells": [1, 1],
                                "socket_type": "deck_mount",
                                "component_type": "machinery",
                            }
                        },
                        "slot_profiles": {
                            "wall_utility_mount_v1": {
                                "footprint_cells": [1, 1],
                                "socket_type": "wall_mount",
                                "allowed_component_types": ["machinery"],
                            }
                        },
                        "role_sets": {
                            "hydroponics": {
                                "wall": [{"component_id": "deck_machine", "weight": 1}],
                                "center": [],
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            from tools.check_crafting_economy import _load_components

            _components, _role_sets, source_ids = _load_components(root)
            self.assertEqual(source_ids, [])

    def test_component_fit_method_name_must_be_a_real_call(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/systems/component_placement_state.gd"
            source = path.read_text(encoding="utf-8")
            source = _remove_from_function(
                source,
                "_fill_slots",
                'catalog.call("validate_component_fit",',
            )
            source = source.replace(
                "\tvar slots: Array = _extract_slots(room, slot_key)\n",
                '\tvar source_decoy := "validate_component_fit"\n'
                "\tvar slots: Array = _extract_slots(room, slot_key)\n",
                1,
            )
            path.write_text(source, encoding="utf-8")
            from tools.check_crafting_economy import _verify_component_consumers

            with self.assertRaisesRegex(SourceError, "placement fit chain is incomplete"):
                _verify_component_consumers(root)

    def test_component_role_profile_selector_drift_is_not_silently_mirrored(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/wall_door_resolver.gd"
            source = path.read_text(encoding="utf-8")
            source = source.replace(
                '"corridor", "hydroponics"',
                '"corridor", "hydroponics_disabled"',
                1,
            )
            path.write_text(source, encoding="utf-8")
            from tools.check_crafting_economy import _verify_component_consumers

            with self.assertRaisesRegex(SourceError, "unsupported role/profile selector"):
                _verify_component_consumers(root)

    def test_component_donors_require_live_coordinator_population(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _copy_runtime_sources(root)
            path = root / "scripts/procgen/playable_generated_ship.gd"
            source = _remove_from_function(
                path.read_text(encoding="utf-8"),
                "_restore_or_populate_component_placement_for_current_ship",
                "component_placement_state.populate(",
            )
            path.write_text(source, encoding="utf-8")
            from tools.check_crafting_economy import _verify_component_consumers

            with self.assertRaisesRegex(SourceError, "component placement does not populate"):
                _verify_component_consumers(root)

    def test_threat_loot_table_requires_the_live_threat_consumer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = {
                "scripts/procgen/ship_generator.gd": "func generate_from_seed():\n\tpass\n",
                "scripts/procgen/gameplay_slice_builder.gd": "func build():\n\tpass\n",
                "scripts/procgen/room_variant_selector.gd": "func effects_for():\n\treturn {}\n",
            }
            for relative_path, source in sources.items():
                path = root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source, encoding="utf-8")
            threat_path = root / "data/combat/threat_archetypes.json"
            threat_path.parent.mkdir(parents=True, exist_ok=True)
            threat_path.write_text(
                json.dumps({"mutant": {"loot_table": "orphan_table"}}),
                encoding="utf-8",
            )

            self.assertEqual(
                _runtime_loot_table_sources(root, {"orphan_table"}), {}
            )

    def test_threat_loot_requires_live_coordinator_tick(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative_path in (
                "scripts/procgen/ship_generator.gd",
                "scripts/procgen/gameplay_slice_builder.gd",
                "scripts/procgen/room_variant_selector.gd",
                "scripts/procgen/playable_generated_ship.gd",
                "scripts/systems/threat_manager.gd",
                "data/combat/threat_archetypes.json",
            ):
                target = root / relative_path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative_path, target)
            coordinator = root / "scripts/procgen/playable_generated_ship.gd"
            source = coordinator.read_text(encoding="utf-8")
            tick_call = (
                "\tthreat_manager.tick_threats(delta, vitals_state, "
                "status_effects_state, _player_armor_profile(), player_pos)\n"
            )
            source = _remove_from_function(source, "_tick_threat_runtime", tick_call)
            coordinator.write_text(source, encoding="utf-8")

            with self.assertRaisesRegex(SourceError, "threat manager is not ticked"):
                _runtime_loot_table_sources(root, {"combat_drop_common"})

    def test_item_defs_merge_matches_runtime_precedence(self):
        definitions = merged_defs(ROOT)
        self.assertEqual(definitions["portable_oxygen_pump"]["category"], "tool")
        self.assertEqual(definitions["portable_oxygen_pump"]["weight"], 2.0)
        # Item definitions precede material fill-only rows. The live inventory's
        # authored scrap weight is therefore 5.0, not the material row's 0.5.
        self.assertEqual(definitions["scrap_metal"]["weight"], 5.0)
        self.assertEqual(
            definitions["captains_black_box"]["codex_entry_id"],
            "captains_black_box",
        )

    def test_missing_source_is_a_hard_error(self):
        with self.assertRaises(SourceError):
            merged_defs(ROOT / "missing")

    def test_malformed_present_source_is_a_hard_error(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bad.json"
            path.write_text("{present but malformed", encoding="utf-8")
            with self.assertRaises(SourceError):
                read(directory, "bad.json")


class GraphAnalysisTests(unittest.TestCase):
    def test_recipe_outputs_are_definition_checked(self):
        source_model = _synthetic_model(
            [_recipe("forge", {"ore": 1}, "forged_relic")], roots=("ore",)
        )
        del source_model["definitions"]["forged_relic"]
        report = analyze_model(source_model)
        self.assertEqual(report["unknown_ids"], ["forged_relic"])
        self.assertFalse(report["ok"])

    def test_unseeded_self_dependency_is_unreachable(self):
        source_model = _synthetic_model(
            [_recipe("catalyze", {"coolant": 1, "ore": 1}, "coolant", 2)],
            roots=("ore",),
        )
        report = analyze_model(source_model)
        self.assertEqual(report["self_dependencies"], ["catalyze"])
        self.assertEqual(report["unreachable_output_ids"], ["coolant"])

    def test_mandatory_prerequisite_cycle_requires_a_reachable_entry_item(self):
        recipes = [
            _recipe("a_to_b", {"a": 1}, "b", power_cost=1),
            _recipe("b_to_a", {"b": 1}, "a", power_cost=1),
        ]
        report = analyze_model(_synthetic_model(recipes))
        self.assertEqual(
            report["mandatory_prerequisite_cycles"],
            [{"item_ids": ["a", "b"], "conversion_ids": ["a_to_b", "b_to_a"]}],
        )
        self.assertIn(
            {"finding": "mandatory_prerequisite_cycles", "count": 1},
            report["blockers"],
        )
        seeded = analyze_model(_synthetic_model(recipes, roots=("a",)))
        self.assertEqual(seeded["mandatory_prerequisite_cycles"], [])
        self.assertNotIn(
            {"finding": "mandatory_prerequisite_cycles", "count": 1},
            seeded["blockers"],
        )

    def test_dependency_gated_production_is_not_an_unconditional_root(self):
        source_model = _synthetic_model([], roots=("contaminated_water",))
        source_model["definitions"]["purified_water"] = _definition("purified_water")
        source_model["definitions"]["greens"] = _definition("greens")
        source_model["production_routes"] = [
            {
                "route_id": "water_recycler",
                "inputs": {"contaminated_water": 1},
                "outputs": {"purified_water": 1},
                "power_cost": 5.0,
            },
            {
                "route_id": "greens",
                "inputs": {"purified_water": 2},
                "outputs": {"greens": 3},
                "power_cost": 3.0,
            },
        ]
        report = analyze_model(source_model)
        self.assertNotIn("purified_water", report["root_ids"])
        self.assertIn("purified_water", report["reachable_ids"])
        self.assertIn("greens", report["reachable_ids"])

    def test_component_form_requires_definition_and_matching_positive_mass(self):
        source_model = _synthetic_model([], roots=())
        source_model["components"] = {
            "console": {"item_form": "console_unit", "mass": 12.0},
            "pump": {"item_form": "pump_unit", "mass": 0.0},
        }
        source_model["definitions"]["pump_unit"] = _definition("pump_unit", weight=2.0)
        report = analyze_model(source_model)
        self.assertEqual(report["missing_component_item_forms"], ["console_unit"])
        self.assertEqual(
            [row["component_id"] for row in report["component_mass_mismatches"]],
            ["pump"],
        )

    def test_component_form_is_single_stack_inventory_part(self):
        source_model = _synthetic_model([], roots=())
        source_model["components"] = {
            "console": {"item_form": "console_unit", "mass": 12.0}
        }
        source_model["definitions"]["console_unit"] = _definition(
            "console_unit", category="supply", weight=12.0, max_stack=2
        )
        gaps = analyze_model(source_model)["component_definition_gaps"]
        self.assertEqual(
            gaps[0]["reasons"], ["invalid_category", "max_stack_must_equal_one"]
        )

    def test_component_form_must_remain_in_base_item_definitions(self):
        source_model = _synthetic_model([], roots=())
        source_model["components"] = {
            "console": {"item_form": "console_unit", "mass": 12.0}
        }
        source_model["definitions"]["console_unit"] = _definition(
            "console_unit", category="component", weight=12.0, max_stack=1
        )
        source_model["base_item_definition_ids"] = []
        gaps = analyze_model(source_model)["component_definition_gaps"]
        self.assertIn("must_be_in_base_item_definitions", gaps[0]["reasons"])

    def test_crafted_tool_requires_exact_action_compatibility(self):
        source_model = _synthetic_model(
            [
                _recipe("craft_welder", {"ore": 1}, "welder", power_cost=1),
                _recipe("craft_plasma", {"ore": 1}, "plasma_cutter", power_cost=1),
            ],
            roots=("ore",),
        )
        report = analyze_model(source_model)
        self.assertEqual(
            [row["item_id"] for row in report["tool_compatibility_gaps"]],
            ["plasma_cutter", "welder"],
        )
        source_model["definitions"]["welder"]["compatible_work_action_ids"] = ["weld_patch"]
        source_model["definitions"]["plasma_cutter"]["compatible_work_action_ids"] = ["cut_wall"]
        self.assertEqual(analyze_model(source_model)["tool_compatibility_gaps"], [])

    def test_book_knowledge_requires_definition_and_reachable_trigger(self):
        source_model = _synthetic_model(
            [
                _recipe(
                    "advanced",
                    {"ore": 1},
                    "advanced_part",
                    power_cost=1,
                    knowledge_source="book",
                    knowledge_book_id="schematic",
                )
            ],
            roots=("ore",),
        )
        report = analyze_model(source_model)
        self.assertEqual(report["knowledge_bootstrap_gaps"][0]["reason"], "unknown_book")
        source_model["definitions"]["schematic"] = _definition(
            "schematic", use_kind="read_skill_book", book_id="schematic"
        )
        report = analyze_model(source_model)
        self.assertEqual(report["knowledge_bootstrap_gaps"][0]["reason"], "unreachable_book")
        source_model["loot_roots"].append(
            {"item_id": "schematic", "source": "fixture:loot", "quantity": 1}
        )
        self.assertEqual(analyze_model(source_model)["knowledge_bootstrap_gaps"], [])

    def test_reverse_knowledge_maps_component_id_to_reachable_item_form(self):
        source_model = _synthetic_model(
            [
                _recipe(
                    "reverse_console",
                    {"ore": 1},
                    "advanced_part",
                    power_cost=1,
                    knowledge_source="reverse_engineer",
                    reverse_engineer_component="console_generic",
                    reverse_engineer_count=1,
                )
            ],
            roots=("ore", "console_unit"),
        )
        source_model["components"] = {
            "console_generic": {"item_form": "console_unit", "mass": 12.0}
        }
        source_model["definitions"]["console_unit"] = _definition(
            "console_unit", category="component", weight=12.0, max_stack=1
        )
        self.assertEqual(analyze_model(source_model)["knowledge_bootstrap_gaps"], [])

    def test_reverse_knowledge_rejects_insufficient_finite_sources(self):
        source_model = _synthetic_model(
            [
                _recipe(
                    "reverse_console",
                    {"ore": 1},
                    "advanced_part",
                    power_cost=1,
                    knowledge_source="reverse_engineer",
                    reverse_engineer_component="console_generic",
                    reverse_engineer_count=3,
                )
            ],
            roots=("ore", "console_unit"),
        )
        source_model["components"] = {
            "console_generic": {"item_form": "console_unit", "mass": 12.0}
        }
        source_model["definitions"]["console_unit"] = _definition(
            "console_unit", category="component", weight=12.0, max_stack=1
        )
        gaps = analyze_model(source_model)["knowledge_bootstrap_gaps"]
        self.assertEqual(gaps[0]["reason"], "insufficient_reverse_source_quantity")

    def test_reverse_knowledge_accepts_repeatable_or_sufficient_finite_sources(self):
        recipe = _recipe(
            "reverse_console",
            {"ore": 1},
            "advanced_part",
            power_cost=1,
            knowledge_source="reverse_engineer",
            reverse_engineer_component="console_generic",
            reverse_engineer_count=3,
        )
        for source_row in (
            {
                "item_id": "console_unit",
                "source": "fixture:repeatable_donor",
                "quantity": 1,
                "repeatable": True,
            },
            {
                "item_id": "console_unit",
                "source": "fixture:finite_cache",
                "quantity": 3,
                "repeatable": False,
            },
        ):
            with self.subTest(source=source_row["source"]):
                source_model = _synthetic_model([recipe], roots=("ore",))
                source_model["components"] = {
                    "console_generic": {"item_form": "console_unit", "mass": 12.0}
                }
                source_model["definitions"]["console_unit"] = _definition(
                    "console_unit", category="component", weight=12.0, max_stack=1
                )
                source_model["loot_roots"].append(source_row)
                self.assertEqual(
                    analyze_model(source_model)["knowledge_bootstrap_gaps"], []
                )

    def test_reverse_knowledge_count_must_be_a_positive_integer(self):
        source_model = _synthetic_model(
            [
                _recipe(
                    "reverse_console",
                    {"ore": 1},
                    "advanced_part",
                    power_cost=1,
                    knowledge_source="reverse_engineer",
                    reverse_engineer_component="console_generic",
                    reverse_engineer_count=0,
                )
            ],
            roots=("ore", "console_unit"),
        )
        source_model["components"] = {
            "console_generic": {"item_form": "console_unit", "mass": 12.0}
        }
        with self.assertRaisesRegex(SourceError, "reverse_engineer_count"):
            analyze_model(source_model)

    def test_codex_knowledge_requires_a_reachable_discovery(self):
        source_model = _synthetic_model(
            [
                _recipe(
                    "codex_recipe",
                    {"ore": 1},
                    "advanced_part",
                    power_cost=1,
                    knowledge_source="codex",
                    knowledge_codex_id="engineering_note",
                )
            ],
            roots=("ore",),
        )
        self.assertEqual(
            analyze_model(source_model)["knowledge_bootstrap_gaps"][0]["reason"],
            "unreachable_codex_source",
        )
        source_model["codex_root_ids"] = ["engineering_note"]
        self.assertEqual(analyze_model(source_model)["knowledge_bootstrap_gaps"], [])

    def test_station_tier_requires_reachable_physical_donor(self):
        source_model = _synthetic_model(
            [
                _recipe(
                    "tier_two",
                    {"ore": 1},
                    "advanced_part",
                    power_cost=1,
                    station_kind="fabricator",
                    station_tier_min=2,
                )
            ],
            roots=("ore",),
        )
        report = analyze_model(source_model)
        self.assertEqual(report["station_tier_gaps"][0]["available_tier"], 0)
        source_model["components"] = {
            "reactor_console": {
                "item_form": "reactor_console",
                "mass": 15.0,
                "station_affinity": "fabricator",
                "station_tier_bonus": 2,
            }
        }
        source_model["definitions"]["reactor_console"] = _definition(
            "reactor_console", weight=15.0, max_stack=1
        )
        source_model["component_source_ids"] = ["reactor_console"]
        self.assertEqual(analyze_model(source_model)["station_tier_gaps"], [])

    def test_titanium_donor_routes_require_live_loot_and_skill_one_workbench(self):
        recipes = [
            _recipe("deconstruct_thruster", {"thruster_nozzle": 1}, "titanium_ingot", power_cost=0,
                    category="deconstruction", required_skill_level=1, station_kind="workbench"),
            _recipe("deconstruct_plasma_cutter", {"plasma_cutter": 1}, "titanium_ingot", power_cost=0,
                    category="deconstruction", required_skill_level=1, station_kind="workbench"),
        ]
        source_model = _synthetic_model(recipes, roots=("thruster_nozzle", "plasma_cutter"))
        source_model["loot_roots"] = [
            {"item_id": "thruster_nozzle", "source": "loot:salvage", "quantity": 1},
            {"item_id": "plasma_cutter", "source": "loot:locker", "quantity": 1},
        ]
        report = analyze_model(source_model)
        self.assertEqual(report["titanium_donor_deconstruction_gaps"], [])
        self.assertEqual(
            report["titanium_donor_deconstruction_routes"],
            [
                {"recipe_id": "deconstruct_plasma_cutter", "donor_id": "plasma_cutter", "loot_sources": ["loot:locker"], "station_kind": "workbench", "required_skill_level": 1},
                {"recipe_id": "deconstruct_thruster", "donor_id": "thruster_nozzle", "loot_sources": ["loot:salvage"], "station_kind": "workbench", "required_skill_level": 1},
            ],
        )

        # A well-typed but wrong integer is an authored contract blocker.
        source_model["recipes"][1]["required_skill_level"] = 0
        self.assertEqual(
            analyze_model(source_model)["titanium_donor_deconstruction_gaps"][0]["reasons"],
            ["invalid_skill_level"],
        )

        # JSON values that merely coerce to one are malformed schema, not
        # equivalent to the authored integer skill requirement.
        for invalid_value in (True, 1.9, "1", "one", None):
            with self.subTest(required_skill_level=repr(invalid_value)):
                source_model["recipes"][1]["required_skill_level"] = invalid_value
                with self.assertRaisesRegex(SourceError, "required_skill_level must be an integer"):
                    analyze_model(source_model)

        source_model["recipes"][1]["required_skill_level"] = 1
        self.assertEqual(analyze_model(source_model)["titanium_donor_deconstruction_gaps"], [])


class StoichiometryTests(unittest.TestCase):
    def test_zero_input_zero_power_generator_is_profitable_without_an_scc(self):
        recipes = [_recipe("free_matter", {}, "matter", 1)]
        groups = analyze_zero_power_cycles(recipes)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["classification"], "profitable")
        self.assertEqual(groups[0]["firing_witness"], {"free_matter": 1})
        self.assertEqual(groups[0]["net_items"], {"matter": 1.0})

    def test_neutral_zero_power_cycle_is_reported_and_allowed(self):
        recipes = [
            _recipe("a_to_b", {"a": 1}, "b"),
            _recipe("b_to_a", {"b": 1}, "a"),
        ]
        groups = analyze_zero_power_cycles(recipes)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0]["classification"], "neutral")
        self.assertEqual(groups[0]["neutral_witness"], {"a_to_b": 1, "b_to_a": 1})

    def test_multi_input_profitable_cycle_is_blocked_with_witness(self):
        recipes = [
            _recipe("combine", {"a": 1, "b": 1}, "c", 3),
            _recipe("split_a", {"c": 1}, "a"),
            _recipe("split_b", {"c": 1}, "b"),
        ]
        groups = analyze_zero_power_cycles(recipes)
        self.assertEqual(groups[0]["classification"], "profitable")
        self.assertEqual(groups[0]["net_items"], {"c": 1})
        self.assertTrue(groups[0]["firing_witness"])

    def test_inconclusive_bounded_group_is_a_blocker(self):
        recipes = [
            _recipe("a_to_b", {"a": 1}, "b"),
            _recipe("b_to_a", {"b": 1}, "a"),
        ]
        groups = analyze_zero_power_cycles(
            recipes,
            max_firing_count=0,
            max_firing_combinations=0,
            max_certificate_weight=0,
            max_certificate_combinations=0,
        )
        self.assertEqual(groups[0]["classification"], "not_verified")

    def test_normalized_junk_conversion_participates_in_cycle_analysis(self):
        conversions = [
            {
                "conversion_id": "junk:a",
                "kind": "junk",
                "inputs": {"a": 1},
                "outputs": {"b": 1},
                "power_cost": 0,
            },
            {
                "conversion_id": "recipe:b_to_a",
                "kind": "recipe",
                "inputs": {"b": 1},
                "outputs": {"a": 1},
                "power_cost": 0,
            },
        ]
        groups = analyze_zero_power_cycles(conversions)
        self.assertEqual(groups[0]["classification"], "neutral")
        self.assertEqual(
            groups[0]["conversion_ids"], ["junk:a", "recipe:b_to_a"]
        )


class RealCatalogClosureTests(unittest.TestCase):
    def setUp(self) -> None:
        self._reviewed_path_patch = patch.object(
            crafting_economy,
            "REVIEWED_TOOL_ACTION_FILE_HASHES",
            _current_reviewed_tool_action_hashes(),
        )
        self._reviewed_path_patch.start()

    def tearDown(self) -> None:
        self._reviewed_path_patch.stop()

    def test_real_catalog_closes_every_required_graph(self):
        report = check(ROOT)
        self.assertEqual(report["schema"], "crafting_economy_report_v1")
        self.assertEqual(report["recipe_count"], 61)
        self.assertEqual(report["distinct_recipe_output_count"], 54)
        self.assertEqual(report["unknown_ids"], [])
        self.assertEqual(report["unreachable_prerequisite_ids"], [])
        self.assertEqual(report["unreachable_output_ids"], [])
        self.assertEqual(report["missing_component_item_forms"], [])
        self.assertEqual(report["component_mass_mismatches"], [])
        self.assertEqual(report["component_definition_gaps"], [])
        self.assertEqual(report["tool_compatibility_gaps"], [])
        self.assertEqual(report["knowledge_bootstrap_gaps"], [])
        self.assertEqual(report["station_tier_gaps"], [])
        self.assertEqual(report["unreachable_repair_parts"], [])
        self.assertEqual(report["unreachable_repair_tools"], [])
        self.assertEqual(report["mandatory_prerequisite_cycles"], [])
        self.assertEqual(report["titanium_donor_deconstruction_gaps"], [])
        self.assertEqual(report["self_dependencies"], ["splice_circuit", "synthesize_coolant"])
        self.assertEqual(report["zero_power_cycle_groups"], [])
        self.assertTrue(report["ok"])

    def test_real_catalog_has_distinct_mountable_plating_route(self):
        source_model = model(ROOT)
        repair_recipe = next(
            row for row in source_model["recipes"] if row["recipe_id"] == "weld_plating"
        )
        self.assertEqual(
            repair_recipe["ingredients"], {"scrap_metal": 2, "adhesive_paste": 1}
        )
        self.assertEqual(
            repair_recipe["produces"], {"item_id": "plating", "quantity": 1}
        )
        conversion_recipe = next(
            row
            for row in source_model["recipes"]
            if row["recipe_id"] == "form_plating_plate"
        )
        self.assertEqual(conversion_recipe["ingredients"], {"plating": 1})
        self.assertEqual(conversion_recipe["power_cost"], 2.0)
        self.assertEqual(
            conversion_recipe["produces"],
            {"item_id": "plating_plate", "quantity": 1},
        )
        self.assertIn("hull_plating", source_model["components"])

    def test_real_catalog_sources_air_recycler_from_hydroponics_role(self):
        source_model = model(ROOT)
        self.assertIn("air_recycler_unit", source_model["component_source_ids"])
        for role in ("hydroponics", "life_support"):
            role_set = source_model["role_sets"].get(role, {})
            self.assertTrue(
                any(
                    row.get("component_id") == "air_recycler_unit"
                    and float(row.get("weight", 0)) > 0
                    for row in role_set.get("center", [])
                ),
                role,
            )

        source_model["component_source_ids"] = [
            component_id
            for component_id in source_model["component_source_ids"]
            if component_id != "air_recycler_unit"
        ]
        report = analyze_model(source_model)
        self.assertIn("air_recycler_unit", report["unsourced_component_ids"])

    def test_real_catalog_requires_every_recipe_station_to_be_live(self):
        source_model = model(ROOT)
        source_model["crafting_station_kinds"] = ["fabricator"]
        report = analyze_model(source_model)
        self.assertIn("workbench", report["station_binding_gaps"])
        self.assertFalse(report["ok"])

    def test_real_crafted_tools_advertise_live_quality_consumer(self):
        source_model = model(ROOT)
        for item_id, action_id in (
            ("welder", "weld_patch"),
            ("plasma_cutter", "cut_wall"),
        ):
            self.assertEqual(
                source_model["definitions"][item_id]["compatible_work_action_ids"],
                [action_id],
            )
            self.assertEqual(
                source_model["quality_effects"][item_id]["consumer"],
                "tool_work_speed",
            )

    def test_compatible_tool_actions_require_reachable_item_data_and_live_action(self):
        source_model = _synthetic_model(
            [_recipe("craft_welder", {"ore": 1}, "welder", power_cost=1)],
            roots=("ore",),
        )
        source_model["definitions"]["welder"]["compatible_work_action_ids"] = [
            "weld_patch"
        ]
        source_model["runtime_tool_action_classes"] = [
            {"action_id": "weld_patch", "tool_class": "welding_lance"}
        ]
        self.assertEqual(
            analyze_model(source_model)["compatible_tool_actions"],
            [{"item_id": "welder", "action_id": "weld_patch"}],
        )

        source_model["quality_effects"]["welder"] = {"consumer": "quantity_only"}
        self.assertEqual(analyze_model(source_model)["compatible_tool_actions"], [])
        source_model["quality_effects"]["welder"] = {"consumer": "tool_work_speed"}

        # An authored but unsupported action does not become a successful pair.
        source_model["definitions"]["welder"]["compatible_work_action_ids"] = [
            "rebuild_structure"
        ]
        self.assertEqual(analyze_model(source_model)["compatible_tool_actions"], [])

        # A compatible item must be producible from the current acquisition roots.
        source_model["definitions"]["welder"]["compatible_work_action_ids"] = [
            "weld_patch"
        ]
        source_model["loot_roots"] = []
        self.assertEqual(analyze_model(source_model)["compatible_tool_actions"], [])

        # Catalog metadata alone cannot replace the reachable action implementation.
        source_model["loot_roots"] = [
            {"item_id": "ore", "source": "fixture:loot", "quantity": 1}
        ]
        source_model["runtime_tool_action_classes"] = []
        self.assertEqual(analyze_model(source_model)["compatible_tool_actions"], [])


if __name__ == "__main__":
    unittest.main()
