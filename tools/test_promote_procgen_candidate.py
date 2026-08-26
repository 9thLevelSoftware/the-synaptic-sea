import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
import subprocess

try:
    from tools.promote_procgen_candidate import (
        MAX_CORPUS_BYTES,
        candidate_id_for,
        promote_candidate,
        validate_candidate,
    )
except ModuleNotFoundError:
    from promote_procgen_candidate import (
        MAX_CORPUS_BYTES,
        candidate_id_for,
        promote_candidate,
        validate_candidate,
    )


ROOT = Path(__file__).resolve().parents[1]
CONTENT_HASH = json.loads(
    (ROOT / "data/procgen/manifests/content_manifest.json").read_text()
)["content_manifest_hash"]
BUILD_MANIFEST = json.loads(
    (ROOT / "data/procgen/manifests/build/win64.json").read_text()
)
SOURCE_COMMIT = BUILD_MANIFEST["rust_source_commit"]
ARTIFACT_HASH = BUILD_MANIFEST["artifact"]["sha256"]


def request():
    return {
        "schema_version": "procgen-request-2",
        "generator_version": 3,
        "world_seed": 123,
        "site": {
            "site_id": "site-0001",
            "x": 2,
            "y": -3,
            "archetype_id": "shuttle",
            "kit_id": "ship_structural_v0",
            "intactness_override_bp": None,
            "cause_of_loss": None,
            "loot_richness_bp": 10000,
        },
        "difficulty_id": "standard",
        "player_model": {"schema_version": "player-model-2", "signals": []},
        "requested_domains": ["world", "site", "gameplay", "presentation"],
        "presentation": {"locale": "en", "seed": 7},
        "content_manifest_hash": CONTENT_HASH,
    }


def candidate(classification="approved_candidate"):
    expected = {
        "semantic_hash": "a" * 64,
        "failure_code": None,
        "fallback_id": None,
        "trace_code": None,
    }
    if classification == "failure_seed":
        expected["semantic_hash"] = None
        expected["semantic_hash"] = "f" * 64
        expected["failure_code"] = None
        expected["trace_code"] = "reconciled:fragment_metadata"
    elif classification == "authored_fallback":
        expected["semantic_hash"] = "b" * 64
        expected["fallback_id"] = "safe-return-v1"
        expected["trace_code"] = "site:selected_fallback"
    value = {
        "schema_version": "procgen-promotion-candidate-1",
        "classification": classification,
        "request": request(),
        "expected": expected,
        "source_diagnostic": {"identity_hash": "c" * 64, "capture_hash": "d" * 64},
        "provenance": {
            "tool_version": "seed-lab-1",
            "generator_version": 3,
            "content_manifest_hash": CONTENT_HASH,
            "rust_source_commit": SOURCE_COMMIT,
            "build_target": "x86_64-pc-windows-msvc",
            "artifact_sha256": ARTIFACT_HASH,
            "technical_validation_codes": ["bundle_valid", "replay_valid"],
        },
    }
    value["candidate_id"] = candidate_id_for(value["classification"], value["source_diagnostic"]["identity_hash"])
    return value


class PromotionBoundaryTests(unittest.TestCase):
    def test_gate5_standalone_schemas_are_parseable_and_closed(self):
        schema_dir = ROOT / "native/worldgen/schemas"
        for name in (
            "procgen-diagnostic-1.schema.json",
            "procgen-promotion-candidate-1.schema.json",
            "procgen-regression-corpus-1.schema.json",
        ):
            schema = json.loads((schema_dir / name).read_text())
            self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
            self.assertFalse(schema["additionalProperties"])

    def test_checked_corpus_entries_pass_the_repository_contract(self):
        corpus = json.loads((ROOT / "data/procgen/corpora/procgen_regression_v1.json").read_text())
        self.assertEqual(corpus["schema_version"], "procgen-regression-corpus-1")
        for entry in corpus["entries"]:
            self.assertEqual(validate_candidate(entry, ROOT, promoted=True), entry)

    def test_consumer_supported_archetypes_difficulties_and_exact_kit(self):
        for archetype in ("shuttle", "corvette", "freighter", "frigate"):
            value = candidate()
            value["request"]["site"]["archetype_id"] = archetype
            self.assertEqual(validate_candidate(value, ROOT)["request"]["site"]["kit_id"], "ship_structural_v0")
        for difficulty in ("standard", "hardened", "deep_dive"):
            value = candidate()
            value["request"]["difficulty_id"] = difficulty
            self.assertEqual(validate_candidate(value, ROOT)["request"]["difficulty_id"], difficulty)

    def test_canonical_requested_domain_subsets_are_promotable(self):
        for domains in (["world"], ["site", "presentation"], ["world", "site", "gameplay", "presentation"]):
            value = candidate()
            value["request"]["requested_domains"] = domains
            self.assertEqual(validate_candidate(value, ROOT)["request"]["requested_domains"], domains)
        for domains in ([], ["site", "world"], ["world", "world"]):
            value = candidate()
            value["request"]["requested_domains"] = domains
            with self.assertRaises(ValueError):
                validate_candidate(value, ROOT)

    def test_pending_candidate_requires_approval_only_at_promotion(self):
        value = candidate()
        value.pop("approval_ref", None)
        with tempfile.TemporaryDirectory() as directory:
            candidate_path = Path(directory) / "candidate.json"
            corpus_path = Path(directory) / "corpus.json"
            candidate_path.write_text(json.dumps(value))
            with self.assertRaises(ValueError):
                promote_candidate(candidate_path, corpus_path, ROOT)
            promote_candidate(candidate_path, corpus_path, ROOT, approval_ref="synaptic-sea-stage-gate:t_bdced4e5")

    def test_failure_seed_and_authored_fallback_evidence_rules(self):
        failure = candidate("failure_seed")
        failure["expected"]["semantic_hash"] = "f" * 64
        failure["expected"]["failure_code"] = None
        failure["expected"]["trace_code"] = "reconciled:fragment_metadata"
        self.assertEqual(validate_candidate(failure, ROOT)["classification"], "failure_seed")
        fallback = candidate("authored_fallback")
        self.assertEqual(validate_candidate(fallback, ROOT)["expected"]["trace_code"], "site:selected_fallback")
        fallback["expected"]["fallback_id"] = "world:authored-safe-hub|site:authored-safe-return"
        self.assertEqual(validate_candidate(fallback, ROOT)["expected"]["fallback_id"], "world:authored-safe-hub|site:authored-safe-return")

    def test_rejects_unknown_nested_keys_and_case_variant_privacy(self):
        value = candidate()
        value["request"]["site"]["UNKNOWN"] = 1
        with self.assertRaises(ValueError):
            validate_candidate(value, ROOT)
        value = candidate()
        value["provenance"]["UserName"] = "x"
        with self.assertRaises(ValueError):
            validate_candidate(value, ROOT)

    def test_candidate_id_is_content_addressed(self):
        value = candidate()
        self.assertEqual(
            value["candidate_id"],
            hashlib.sha256(b"approved_candidate:" + b"c" * 64).hexdigest(),
        )
        self.assertEqual(validate_candidate(value, ROOT), value)

    def test_all_classifications_require_consistent_expected_evidence(self):
        for classification in ("approved_candidate", "failure_seed", "authored_fallback"):
            self.assertEqual(validate_candidate(candidate(classification), ROOT)["classification"], classification)
        invalid = candidate("approved_candidate")
        invalid["expected"]["fallback_id"] = "safe-return-v1"
        with self.assertRaises(ValueError):
            validate_candidate(invalid, ROOT)

    def test_rejects_privacy_unknown_keys_and_stale_identity(self):
        for path in (("request", "username"), ("provenance", "notes"), ("source_diagnostic", "path")):
            invalid = candidate()
            invalid[path[0]][path[1]] = "private"
            with self.assertRaises(ValueError):
                validate_candidate(invalid, ROOT)
        invalid = candidate()
        invalid["provenance"]["content_manifest_hash"] = "f" * 64
        with self.assertRaises(ValueError):
            validate_candidate(invalid, ROOT)

    def test_promote_is_sorted_unique_atomic_and_supports_dry_run_check(self):
        first = candidate("failure_seed")
        second = candidate("approved_candidate")
        with tempfile.TemporaryDirectory() as directory:
            candidate_path = Path(directory) / "candidate.json"
            corpus_path = Path(directory) / "corpus.json"
            candidate_path.write_text(json.dumps(first))
            promote_candidate(candidate_path, corpus_path, ROOT, approval_ref="synaptic-sea-stage-gate:t_bdced4e5")
            candidate_path.write_text(json.dumps(second))
            promote_candidate(candidate_path, corpus_path, ROOT, approval_ref="synaptic-sea-stage-gate:t_bdced4e5")
            corpus = json.loads(corpus_path.read_text())
            self.assertEqual(corpus["schema_version"], "procgen-regression-corpus-1")
            self.assertEqual([x["candidate_id"] for x in corpus["entries"]], sorted(x["candidate_id"] for x in corpus["entries"]))
            before = corpus_path.read_bytes()
            prospective = candidate("approved_candidate")
            prospective["source_diagnostic"]["identity_hash"] = "f" * 64
            prospective["candidate_id"] = candidate_id_for("approved_candidate", "f" * 64)
            candidate_path.write_text(json.dumps(prospective))
            self.assertTrue(promote_candidate(candidate_path, corpus_path, ROOT, approval_ref="synaptic-sea-stage-gate:t_bdced4e5", dry_run=True))
            self.assertEqual(corpus_path.read_bytes(), before)
            self.assertTrue(promote_candidate(None, corpus_path, ROOT, check=True))
            duplicate = copy.deepcopy(second)
            candidate_path.write_text(json.dumps(duplicate))
            with self.assertRaises(ValueError):
                promote_candidate(candidate_path, corpus_path, ROOT, approval_ref="synaptic-sea-stage-gate:t_bdced4e5")

    def test_size_cap_is_fail_closed(self):
        invalid = candidate()
        invalid["provenance"]["technical_validation_codes"] = ["x" * 128] * 64
        with self.assertRaises(ValueError):
            validate_candidate(invalid, ROOT)

    def test_corpus_file_byte_cap_is_checked_before_parsing(self):
        with tempfile.TemporaryDirectory() as directory:
            corpus_path = Path(directory) / "oversized.json"
            with corpus_path.open("wb") as stream:
                stream.truncate(MAX_CORPUS_BYTES + 1)
            with self.assertRaisesRegex(ValueError, "corpus exceeds byte cap"):
                promote_candidate(None, corpus_path, ROOT, check=True)


if __name__ == "__main__":
    unittest.main()
