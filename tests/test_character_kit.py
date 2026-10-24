from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

from tools.character_kit import character_kit_spec as spec
from tools.character_kit.validate_character_glb import GlbError, read_glb, validate

PROJECT_ROOT = Path(__file__).resolve().parents[1]
KIT_GLB = PROJECT_ROOT / spec.RUNTIME_ROOT / spec.GLB_LEAF
KIT_MANIFEST = PROJECT_ROOT / spec.RUNTIME_ROOT / spec.MANIFEST_LEAF
CATALOG = PROJECT_ROOT / "data/characters/character_visual_catalog.json"


def _aligned(payload: bytes, pad: bytes) -> bytes:
    return payload + pad * ((-len(payload)) % 4)


def make_glb(document: dict, binary: bytes = b"") -> bytes:
    json_chunk = _aligned(json.dumps(document, separators=(",", ":")).encode("utf-8"), b" ")
    chunks = [struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk]
    if binary:
        binary = _aligned(binary, b"\0")
        chunks.append(struct.pack("<I4s", len(binary), b"BIN\0") + binary)
    body = b"".join(chunks)
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


class SpecTests(unittest.TestCase):
    def test_bone_hierarchy_is_rooted_and_unique(self):
        names = [name for name, _parent in spec.BONE_HIERARCHY]
        self.assertEqual(len(names), len(set(names)))
        parents = {name: parent for name, parent in spec.BONE_HIERARCHY}
        for name, parent in spec.BONE_HIERARCHY:
            if parent:
                self.assertIn(parent, parents, f"{name} parent {parent} missing")
        self.assertEqual(sum(1 for _n, p in spec.BONE_HIERARCHY if not p), 1)

    def test_parts_and_sockets_bind_to_real_bones(self):
        for mapping in (spec.BODY_PARTS, spec.EQUIPMENT_PARTS, spec.SOCKETS):
            for node, bone in mapping.items():
                self.assertIn(bone, spec.BONE_NAMES, f"{node} binds unknown bone {bone}")

    def test_equipment_visual_prefixes_match_equipment_parts(self):
        for item_id, prefixes in spec.EQUIPMENT_VISUALS.items():
            for prefix in prefixes:
                self.assertTrue(
                    any(part.startswith(prefix) for part in spec.EQUIPMENT_PARTS),
                    f"{item_id} prefix {prefix} matches no equipment part",
                )

    def test_manifest_round_trip(self):
        document = spec.KitManifest().to_dict()
        self.assertEqual(document["document_kind"], spec.DOCUMENT_KIND)
        self.assertEqual(document["bones"], spec.BONE_NAMES)
        self.assertEqual(document["animations"], spec.ANIMATION_NAMES)
        self.assertEqual(json.loads(spec.canonical_json(document)), document)


class CatalogTests(unittest.TestCase):
    def test_catalog_matches_spec(self):
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        self.assertEqual(catalog["version"], "character-visual-1")
        entry = catalog["characters"]["player_survivor"]
        self.assertEqual(entry["kit_id"], spec.KIT_ID)
        self.assertEqual(entry["scene_path"], "res://" + str(spec.RUNTIME_ROOT / spec.GLB_LEAF).replace("\\", "/"))
        self.assertEqual(entry["equipment_visuals"], spec.EQUIPMENT_VISUALS)
        # Godot strips the glTF "-loop" suffix on import; the catalog uses the imported names.
        imported = {name[:-5] if name.endswith("-loop") else name for name in spec.ANIMATION_NAMES}
        self.assertEqual(set(entry["animations"].values()), imported)
        for logical in entry["looping_animations"]:
            self.assertIn(entry["animations"][logical] + "-loop", spec.ANIMATION_NAMES)
        self.assertEqual(set(entry["sockets"].values()), set(spec.SOCKETS))
        equipment_ids = json.loads((PROJECT_ROOT / "data/items/equipment_definitions.json").read_text(encoding="utf-8"))
        for item_id in entry["equipment_visuals"]:
            self.assertIn(item_id, equipment_ids, f"catalog references unknown equipment item {item_id}")


class ValidatorTests(unittest.TestCase):
    def test_rejects_non_glb(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.glb"
            path.write_bytes(b"not a glb at all")
            with self.assertRaises(GlbError):
                read_glb(path)

    def test_reports_missing_contract_pieces(self):
        document = {"asset": {"version": "2.0"}, "nodes": [{"name": "root"}], "meshes": [], "accessors": [], "skins": []}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "empty.glb"
            path.write_bytes(make_glb(document))
            report = validate(path)
        self.assertFalse(report["ok"])
        joined = "\n".join(report["errors"])
        self.assertIn("exactly one skin", joined)
        self.assertIn("missing mesh node Body_Head", joined)
        self.assertIn("animations != spec", joined)

    @unittest.skipUnless(KIT_GLB.exists(), "survivor_v1 kit not built")
    def test_built_kit_passes(self):
        report = validate(KIT_GLB, KIT_MANIFEST)
        self.assertTrue(report["ok"], report["errors"])
        self.assertEqual(set(report["bones"]), set(spec.BONE_NAMES))
        self.assertEqual(set(report["animations"]), set(spec.ANIMATION_NAMES))
        self.assertLessEqual(report["kit_triangles"], spec.TRIANGLE_BUDGET["kit_max"])
        self.assertTrue(report["forward_axis_ok"])


if __name__ == "__main__":
    unittest.main()
