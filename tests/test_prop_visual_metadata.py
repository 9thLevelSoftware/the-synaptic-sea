from __future__ import annotations

import hashlib
import json
import math
import re
import struct
import tempfile
import unittest
from pathlib import Path

from tools.prop_visual_metadata import (
    FORBIDDEN_GAMEPLAY_FIELDS,
    read_glb_metadata,
    validate_sidecar,
    write_canonical_json,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
REACTOR_GLB = PROJECT_ROOT / "assets/imported/props/components/reactor_console.glb"
FIXTURE_ROOT = PROJECT_ROOT / "tests/fixtures/prop_visual_metadata"
SCHEMA_PATH = PROJECT_ROOT / "data/placement/schemas/prop_visual_binding_v1.schema.json"


def load_fixture(name: str) -> dict:
    return json.loads((FIXTURE_ROOT / name).read_text(encoding="utf-8"))


def aligned_json_bytes(document: dict) -> bytes:
    payload = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return payload + b" " * ((-len(payload)) % 4)


def make_glb(document: dict, binary: bytes = b"") -> bytes:
    json_chunk = aligned_json_bytes(document)
    chunks = [struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk]
    if binary:
        binary = binary + b"\0" * ((-len(binary)) % 4)
        chunks.append(struct.pack("<I4s", len(binary), b"BIN\0") + binary)
    body = b"".join(chunks)
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def make_raw_glb(chunks: list[tuple[bytes, bytes]]) -> bytes:
    body = b"".join(struct.pack("<I4s", len(payload), chunk_type) + payload for chunk_type, payload in chunks)
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def valid_sidecar(*, kind: str = "component", path: str | None = None) -> dict:
    visual_path = path or "res://assets/imported/props/components/reactor_console.glb"
    return {
        "schema_version": "1.0.0",
        "document_kind": "prop_visual_binding",
        "asset_id": "reactor_console",
        "prop_kind": kind,
        "visual_scene_path": visual_path,
        "binding": {"namespace": "component_id", "ids": ["reactor_console"]},
        "placement": {
            "origin": "scene_origin",
            "offset_m": [0, 0, 0],
            "rotation_degrees": [0, 0, 0],
            "allowed_yaw_deg": [0, 90, 180, 270],
            "scale": 1.0,
        },
        "source": {
            "sha256": "0" * 64,
            "byte_size": 0,
            "mesh_count": 1,
            "gltf_version": "2.0",
        },
        "bounds": {"local_min_m": [0, 0, 0], "local_max_m": [1, 1, 1]},
        "collision_policy": "none_visual_only",
        "provenance": {"license_state": "self-authored", "source_platform": "self-authored"},
        "extensions": {},
    }


class PropVisualMetadataTests(unittest.TestCase):
    def test_schema_tuple_vectors_require_exactly_three_items(self) -> None:
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        placement_properties = schema["properties"]["placement"]["properties"]
        bounds_properties = schema["properties"]["bounds"]["properties"]
        for field in ("offset_m", "rotation_degrees"):
            self.assertEqual(placement_properties[field].get("minItems"), 3, field)
        for field in ("local_min_m", "local_max_m"):
            self.assertEqual(bounds_properties[field].get("minItems"), 3, field)

    def test_schema_visual_scene_path_pattern_rejects_parent_components(self) -> None:
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        pattern = schema["properties"]["visual_scene_path"]["pattern"]
        matcher = re.compile(pattern)
        self.assertIsNotNone(matcher.fullmatch("res://assets/imported/props/reactor_console.glb"))
        for path in (
            "res://../reactor_console.glb",
            "res://assets/../reactor_console.glb",
            "res://assets/props/../reactor_console.glb",
        ):
            with self.subTest(path=path):
                self.assertIsNone(matcher.fullmatch(path))

    def test_sidecar_rejects_invalid_origin_and_duplicate_numeric_yaw(self) -> None:
        sidecar = valid_sidecar()
        sidecar["placement"]["origin"] = "unsupported_origin"
        sidecar["placement"]["allowed_yaw_deg"] = [0, 0.0, 90]
        self.assertEqual(
            validate_sidecar(sidecar, REACTOR_GLB, PROJECT_ROOT),
            [
                "placement.origin must be one of: marker_anchor, scene_origin",
                "duplicate placement.allowed_yaw_deg: 0",
            ],
        )

    def test_sidecar_huge_numbers_return_deterministic_errors(self) -> None:
        huge = 10**4000
        sidecar = valid_sidecar()
        sidecar["placement"]["offset_m"] = [huge, 0, 0]
        sidecar["placement"]["allowed_yaw_deg"] = [huge]
        sidecar["placement"]["scale"] = huge
        sidecar["source"]["byte_size"] = huge
        self.assertEqual(
            validate_sidecar(sidecar, REACTOR_GLB, PROJECT_ROOT),
            [
                "placement.offset_m must be a finite 3-vector",
                "placement.allowed_yaw_deg must contain finite numbers",
                "placement.scale must be a finite positive number",
                "source.byte_size must be a finite non-negative number",
            ],
        )

    def test_reactor_console_glb_has_stable_hash_and_ordered_bounds(self) -> None:
        record = read_glb_metadata(REACTOR_GLB)
        self.assertEqual(len(record["sha256"]), 64)
        self.assertEqual(record["sha256"], hashlib.sha256(REACTOR_GLB.read_bytes()).hexdigest())
        self.assertGreater(record["byte_size"], 0)
        self.assertEqual(record["gltf_version"], "2.0")
        self.assertGreater(record["mesh_count"], 0)
        self.assertEqual(len(record["local_min_m"]), 3)
        self.assertEqual(len(record["local_max_m"]), 3)
        for low, high in zip(record["local_min_m"], record["local_max_m"]):
            self.assertLessEqual(low, high)
            self.assertTrue(math.isfinite(low))
            self.assertTrue(math.isfinite(high))

    def test_sidecar_rejects_parent_path(self) -> None:
        errors = validate_sidecar(load_fixture("invalid_parent_path.sidecar.json"), REACTOR_GLB, PROJECT_ROOT)
        self.assertIn("path must be a contained res:// path", "\n".join(errors))

    def test_sidecar_rejects_component_gameplay_fields(self) -> None:
        errors = validate_sidecar(load_fixture("invalid_gameplay_field.sidecar.json"), REACTOR_GLB, PROJECT_ROOT)
        self.assertIn("forbidden gameplay field: mass", errors)

    def test_valid_component_sidecar_has_no_errors(self) -> None:
        self.assertEqual(validate_sidecar(valid_sidecar(), REACTOR_GLB, PROJECT_ROOT), [])

    def test_sidecar_contract_errors_are_deterministic(self) -> None:
        sidecar = valid_sidecar()
        sidecar["schema_version"] = "2.0.0"
        sidecar["document_kind"] = "wrong"
        sidecar["collision_policy"] = "generated_collision"
        sidecar["binding"]["ids"] = ["reactor_console", "reactor_console"]
        sidecar["unexpected"] = True
        errors = validate_sidecar(sidecar, REACTOR_GLB, PROJECT_ROOT)
        self.assertEqual(
            errors,
            [
                "unsupported schema major version: 2",
                "document_kind must be prop_visual_binding",
                "collision_policy must be none_visual_only",
                "duplicate binding id: reactor_console",
                "unknown root field: unexpected",
            ],
        )

    def test_sidecar_rejects_absolute_path_and_basename_mismatch(self) -> None:
        sidecar = valid_sidecar(path="/tmp/reactor_console.glb")
        sidecar["asset_id"] = "other_asset"
        errors = validate_sidecar(sidecar, REACTOR_GLB, PROJECT_ROOT)
        self.assertIn("path must be a contained res:// path", errors)
        self.assertIn("asset_id must match GLB basename: reactor_console", errors)

    def test_sidecar_rejects_forbidden_keys_wherever_they_occur_but_allows_extensions(self) -> None:
        sidecar = valid_sidecar()
        sidecar["extensions"] = {"studio": {"mass": 99, "nested": [{"type": "decorative"}]}}
        sidecar["provenance"]["condition_default"] = 1
        sidecar["placement"]["surface"] = "floor"
        sidecar["binding"]["metadata"] = {"loot_table": "x"}
        errors = validate_sidecar(sidecar, REACTOR_GLB, PROJECT_ROOT)
        self.assertEqual(
            [error for error in errors if error.startswith("forbidden gameplay field:")],
            ["forbidden gameplay field: condition_default", "forbidden gameplay field: loot_table"],
        )
        self.assertIn("placement.surface is only allowed for dressing or objective", errors)
        self.assertNotIn("forbidden gameplay field: mass", errors)
        self.assertNotIn("forbidden gameplay field: type", errors)

    def test_dressing_surface_is_allowed(self) -> None:
        sidecar = valid_sidecar(kind="dressing")
        sidecar["prop_kind"] = "dressing"
        sidecar["binding"] = {"namespace": "visual_prop_id", "ids": ["reactor_console"]}
        sidecar["placement"]["surface"] = "floor"
        self.assertEqual(validate_sidecar(sidecar, REACTOR_GLB, PROJECT_ROOT), [])

    def test_glb_scans_position_accessor_when_min_max_absent(self) -> None:
        positions = struct.pack("<6f", -1.5, 2.0, 3.25, 4.0, -5.0, 6.5)
        document = {
            "asset": {"version": "2.0"},
            "buffers": [{"byteLength": len(positions)}],
            "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(positions)}],
            "accessors": [{
                "bufferView": 0,
                "componentType": 5126,
                "count": 2,
                "type": "VEC3",
            }],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "scan.glb"
            path.write_bytes(make_glb(document, positions))
            record = read_glb_metadata(path)
        self.assertEqual(record["mesh_count"], 1)
        self.assertEqual(record["local_min_m"], [-1.5, -5.0, 3.25])
        self.assertEqual(record["local_max_m"], [4.0, 2.0, 6.5])

    def test_glb_uses_accessor_min_max_without_binary_chunk(self) -> None:
        document = {
            "asset": {"version": "2.0"},
            "accessors": [{
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [-2, -3, -4],
                "max": [5, 6, 7],
            }],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "minmax.glb"
            path.write_bytes(make_glb(document))
            record = read_glb_metadata(path)
        self.assertEqual(record["local_min_m"], [-2.0, -3.0, -4.0])
        self.assertEqual(record["local_max_m"], [5.0, 6.0, 7.0])

    def test_glb_rejects_non_2_0_asset_version(self) -> None:
        document = {
            "asset": {"version": "1.0"},
            "accessors": [{
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [-1, -2, -3],
                "max": [4, 5, 6],
            }],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "gltf_1.glb"
            path.write_bytes(make_glb(document))
            with self.assertRaises(ValueError):
                read_glb_metadata(path)

    def test_glb_position_accessors_require_strict_structure(self) -> None:
        base_accessor = {
            "componentType": 5126,
            "count": 3,
            "type": "VEC3",
            "min": [-1, -2, -3],
            "max": [4, 5, 6],
        }
        invalid_accessors = {
            "component_type": {**base_accessor, "componentType": 5123},
            "accessor_type": {**base_accessor, "type": "SCALAR"},
            "count_zero": {**base_accessor, "count": 0},
            "count_float": {**base_accessor, "count": 3.0},
            "sparse_with_bounds": {**base_accessor, "sparse": {}},
            "partial_min": {key: value for key, value in base_accessor.items() if key != "max"},
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, accessor in invalid_accessors.items():
                with self.subTest(name=name):
                    document = {
                        "asset": {"version": "2.0"},
                        "accessors": [accessor],
                        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
                    }
                    path = root / f"{name}.glb"
                    path.write_bytes(make_glb(document))
                    with self.assertRaises(ValueError):
                        read_glb_metadata(path)

            scan_document = {
                "asset": {"version": "2.0"},
                "buffers": [{"byteLength": 12}],
                "bufferViews": [{"buffer": 0, "byteLength": 12}],
                "accessors": [{
                    "componentType": 5126,
                    "count": 1,
                    "type": "VEC3",
                    "sparse": {},
                }],
                "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
            }
            scan_path = root / "sparse_scan.glb"
            scan_path.write_bytes(make_glb(scan_document, struct.pack("<3f", 1, 2, 3)))
            with self.assertRaises(ValueError):
                read_glb_metadata(scan_path)

    def test_glb_rejects_overflowing_accessor_bounds_as_value_error(self) -> None:
        huge = 10**4000
        document = {
            "asset": {"version": "2.0"},
            "accessors": [{
                "componentType": 5126,
                "count": 1,
                "type": "VEC3",
                "min": [huge, 0, 0],
                "max": [huge, 1, 1],
            }],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "overflow.glb"
            path.write_bytes(make_glb(document))
            with self.assertRaises(ValueError):
                read_glb_metadata(path)

    def test_glb_rejects_unaligned_chunks_and_illegal_chunk_sequences(self) -> None:
        document = {
            "asset": {"version": "2.0"},
            "accessors": [{
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [-1, -2, -3],
                "max": [4, 5, 6],
            }],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        }
        json_chunk = aligned_json_bytes(document)
        misaligned_json_chunk = json_chunk[:-1]
        nul_padded_json_chunk = json_chunk[:-1] + b"\0"
        tab_padded_json_chunk = json_chunk[:-1] + b"\t"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cases = {
                "misaligned_json": [(b"JSON", misaligned_json_chunk)],
                "nul_padded_json": [(b"JSON", nul_padded_json_chunk)],
                "tab_padded_json": [(b"JSON", tab_padded_json_chunk)],
                "bin_before_json": [(b"BIN\0", b"\0\0\0\0"), (b"JSON", json_chunk)],
                "junk_before_json": [(b"JUNK", b"\0\0\0\0"), (b"JSON", json_chunk)],
                "unknown_then_bin": [(b"JSON", json_chunk), (b"JUNK", b"\0\0\0\0"), (b"BIN\0", b"\0\0\0\0")],
                "duplicate_json": [(b"JSON", json_chunk), (b"JSON", json_chunk)],
                "duplicate_bin": [(b"JSON", json_chunk), (b"BIN\0", b"\0\0\0\0"), (b"BIN\0", b"\0\0\0\0")],
                "json_absent": [(b"BIN\0", b"\0\0\0\0")],
            }
            for name, chunks in cases.items():
                with self.subTest(name=name):
                    path = root / f"{name}.glb"
                    path.write_bytes(make_raw_glb(chunks))
                    with self.assertRaises(ValueError):
                        read_glb_metadata(path)

    def test_glb_accepts_unknown_chunks_after_json_and_bin(self) -> None:
        document = {
            "asset": {"version": "2.0"},
            "accessors": [{
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [-1, -2, -3],
                "max": [4, 5, 6],
            }],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        }
        json_chunk = aligned_json_bytes(document)
        unknown_chunk = (b"JUNK", b"\0\0\0\0")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            after_json = root / "unknown_after_json.glb"
            after_json.write_bytes(make_raw_glb([(b"JSON", json_chunk), unknown_chunk]))
            after_json_record = read_glb_metadata(after_json)

            after_bin = root / "unknown_after_bin.glb"
            after_bin.write_bytes(make_raw_glb([(b"JSON", json_chunk), (b"BIN\0", b"\0\0\0\0"), unknown_chunk]))
            after_bin_record = read_glb_metadata(after_bin)
        self.assertEqual(after_json_record["local_min_m"], [-1.0, -2.0, -3.0])
        self.assertEqual(after_bin_record["local_max_m"], [4.0, 5.0, 6.0])

    def test_glb_bounds_are_rounded_to_six_decimals_without_negative_zero(self) -> None:
        document = {
            "asset": {"version": "2.0"},
            "accessors": [{
                "componentType": 5126,
                "count": 3,
                "type": "VEC3",
                "min": [-1.23456789, 2.34567891, -0.0000004],
                "max": [3.14159265, 2.3456794, 9.87654321],
            }],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "precision.glb"
            path.write_bytes(make_glb(document))
            record = read_glb_metadata(path)
        self.assertEqual(record["local_min_m"], [-1.234568, 2.345679, 0.0])
        self.assertEqual(record["local_max_m"], [3.141593, 2.345679, 9.876543])
        self.assertEqual(math.copysign(1.0, record["local_min_m"][2]), 1.0)

    def test_glb_rejects_malformed_header_json_meshes_and_nonfinite_bounds(self) -> None:
        invalid_documents = [
            {"asset": {"version": "2.0"}, "meshes": []},
            {
                "asset": {"version": "2.0"},
                "accessors": [{"type": "VEC3", "min": ["NaN", 0, 0], "max": [1, 1, 1]}],
                "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bad_magic = root / "bad_magic.glb"
            bad_magic.write_bytes(b"nope" + b"\0" * 20)
            with self.assertRaises(ValueError):
                read_glb_metadata(bad_magic)

            bad_length = root / "bad_length.glb"
            valid = make_glb({"asset": {"version": "2.0"}, "meshes": [{"primitives": []}]})
            bad_length.write_bytes(valid[:8] + struct.pack("<I", len(valid) + 100) + valid[12:])
            with self.assertRaises(ValueError):
                read_glb_metadata(bad_length)

            bad_json = root / "bad_json.glb"
            payload = b"{" + b" " * 3
            body = struct.pack("<I4s", len(payload), b"JSON") + payload
            bad_json.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)
            with self.assertRaises(ValueError):
                read_glb_metadata(bad_json)

            for index, document in enumerate(invalid_documents):
                path = root / f"invalid_{index}.glb"
                path.write_bytes(make_glb(document))
                with self.assertRaises(ValueError):
                    read_glb_metadata(path)

    def test_canonical_json_is_sorted_compact_and_newline_terminated(self) -> None:
        document = {"z": 1, "nested": {"b": 2, "a": [3, 4]}, "a": "é"}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "canonical.json"
            write_canonical_json(path, document)
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                '{"a":"é","nested":{"a":[3,4],"b":2},"z":1}\n',
            )

    def test_forbidden_key_constant_matches_plan(self) -> None:
        self.assertEqual(
            FORBIDDEN_GAMEPLAY_FIELDS,
            {
                "mass", "power_draw", "condition_default", "linked_system", "linked_subcomponent",
                "role_weights", "room_id", "cell", "approach_cell", "sequence", "type", "kind",
                "steps", "loot_table", "item_form",
            },
        )


if __name__ == "__main__":
    unittest.main()
