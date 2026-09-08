import copy
import json
import tempfile
import unittest
from pathlib import Path

from tools.build_feature_acceptance import (
    PLAN,
    PLAN_REL,
    SUPERSESSIONS_REL,
    _digest,
    _natural_feature_criterion_id,
    _natural_requirement_criterion_id,
    _supersession_set_fingerprint,
    build,
    build_card_manifest,
    validate,
    write_registry,
)


class TemporaryAcceptanceSources:
    def __init__(self, root: Path):
        self.root = root
        self.requirements = root / "docs/game/05_requirements.md"
        self.features = root / "docs/game/features"
        self.registry = root / "docs/game/inventory/feature_acceptance.json"
        self.supersessions = root / SUPERSESSIONS_REL
        self.features.mkdir(parents=True)
        self.registry.parent.mkdir(parents=True)
        self.requirements.write_text(
            """# Requirements

## REQ-TEST-001: Stable behavior

- Source: `features/example.md`
- Status: Approved
- Acceptance criteria:
  - Alpha remains observable.
  - Beta remains observable.
- Verification:
  - `example_smoke.gd`

## REQ-TEST-002: Deferred behavior

- Source: `features/example.md`
- Status: Deferred — expected-unbuilt
- Acceptance criteria:
  - Deferred behavior stays visible.
- Verification:
  - Future player scenario.

## REQ-TEST-003: Qualified acceptance label

- Source: `features/numbered.md`
- Status: Approved
- Acceptance criteria (historical wording retained):
  - A qualified acceptance label is still extracted.
- Verification:
  - `qualified_smoke.gd`
""",
            encoding="utf-8",
        )
        fc_rows = "\n".join(
            f"| FC-{number:02d} | Program outcome {number:02d}. | P{number:02d} |"
            for number in range(1, 25)
        )
        (self.features / "crafting_derelict_feature_completion.md").write_text(
            "# Program\n\n## Acceptance register\n\n"
            "| ID | Observable outcome | Owner |\n|---|---|---|\n"
            + fc_rows
            + "\n",
            encoding="utf-8",
        )
        self.example = self.features / "example.md"
        self.example.write_text(
            """# Example feature

## Acceptance criteria

- A player-visible feature leaf.
- A second feature leaf.
- **Workflow:** A workflow leaf remains active.
- **Deferred:** A separately promised future leaf remains accounted.

## Implementation notes

- This implementation bullet is not acceptance.
""",
            encoding="utf-8",
        )
        (self.features / "missing_acceptance.md").write_text(
            "# Design source without acceptance\n\n- A design note.\n",
            encoding="utf-8",
        )
        (self.features / "numbered.md").write_text(
            """# Numbered feature

## Status

Deferred — expected-unbuilt

## Acceptance criteria

1. The first numbered criterion spans
   a continuation line.
2. The second numbered criterion remains separate.
""",
            encoding="utf-8",
        )
        (self.features / "mapped.md").write_text(
            """# Mapped feature

## Acceptance criteria

Mapped 1:1 to REQ-TEST-001..003 in `docs/game/05_requirements.md`.
""",
            encoding="utf-8",
        )
        self.ui_proposal = self.features / "ui_presentation_program.md"
        self.ui_proposal.write_text(
            "# UI presentation proposal\n\n"
            "**Status:** Proposed for review, 2026-09-05. Planning only; no UI implementation or visual acceptance is claimed.\n\n"
            "## Acceptance criteria\n\n"
            + "\n".join(f"- Proposed UI leaf {number:02d}." for number in range(1, 22))
            + "\n",
            encoding="utf-8",
        )

    def reviewed_supersession(
        self,
        original: str,
        replacement: str,
        requirement_id: str = "REQ-TEST-001",
    ) -> dict:
        source_path = "docs/game/05_requirements.md"
        stable_id = _natural_requirement_criterion_id(requirement_id, original)
        replacement_id = _natural_requirement_criterion_id(requirement_id, replacement)
        adr_path = "docs/game/adr/0066-test-supersession.md"
        adr = self.root / adr_path
        adr.parent.mkdir(parents=True, exist_ok=True)
        adr.write_text("# Test supersession authority\n", encoding="utf-8")
        return {
            "stable_criterion_id": stable_id,
            "source": {"path": source_path, "heading": requirement_id},
            "original": {
                "criterion": original,
                "natural_id": stable_id,
                "criterion_fingerprint": _digest(source_path, requirement_id, original),
            },
            "replacement": {
                "criterion": replacement,
                "natural_id": replacement_id,
                "criterion_fingerprint": _digest(source_path, requirement_id, replacement),
            },
            "review": {
                "status": "accepted",
                "adr": adr_path,
                "reviewer": "root_coordinator",
                "reviewed_on": "2026-09-05",
            },
            "accounting": {
                "metric_disposition": "one_for_one_active_leaf",
                "acceptance_kind": "requirement",
                "deferred": False,
                "counts_toward_proposed_denominator": True,
                "representative_id": stable_id,
                "denominator_delta": 0,
            },
        }

    def reviewed_feature_supersession(self, original: str, replacement: str) -> dict:
        source_path = "docs/game/features/structural_wrapper_collision.md"
        heading = "Acceptance criteria"
        original_id = _natural_feature_criterion_id(source_path, heading, original)
        replacement_id = _natural_feature_criterion_id(source_path, heading, replacement)
        return {
            "stable_criterion_id": original_id,
            "source": {"path": source_path, "heading": heading},
            "original": {
                "criterion": original,
                "natural_id": original_id,
                "criterion_fingerprint": _digest(source_path, heading, original),
            },
            "replacement": {
                "criterion": replacement,
                "natural_id": replacement_id,
                "criterion_fingerprint": _digest(source_path, heading, replacement),
            },
            "review": {
                "status": "accepted",
                "adr": "docs/game/adr/0066-test-feature-supersession.md",
                "reviewer": "root_coordinator",
                "reviewed_on": "2026-09-08",
            },
            "accounting": {
                "metric_disposition": "one_for_one_active_leaf",
                "acceptance_kind": "feature",
                "deferred": False,
                "counts_toward_proposed_denominator": True,
                "representative_id": original_id,
                "denominator_delta": 0,
            },
        }

    def write_supersessions(self, rows: list[dict]) -> None:
        self.supersessions.parent.mkdir(parents=True, exist_ok=True)
        self.supersessions.write_text(
            json.dumps(
                {
                    "schema_version": "reviewed-criterion-supersessions-v1",
                    "program": "crafting-derelict-feature-completion",
                    "reviewed_supersessions": rows,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )


class FeatureAcceptanceRegistryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.sources = TemporaryAcceptanceSources(self.root)

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def _criterion(registry, text):
        return next(entry for entry in registry["criteria"] if entry["criterion"] == text)

    def test_regenerating_twice_preserves_unchanged_evidence_and_is_idempotent(self):
        first = write_registry(self.root)
        alpha = self._criterion(first, "Alpha remains observable.")
        stored = json.loads(self.sources.registry.read_text(encoding="utf-8"))
        stored_alpha = next(entry for entry in stored["criteria"] if entry["id"] == alpha["id"])
        stored_alpha["evidence"] = {
            "implemented": True,
            "production_reachable": True,
            "fresh_validation": True,
            "player_accepted": False,
            "state": "verified_scene",
            "refs": ["artifacts/feature-completion/P01/alpha.log"],
        }
        self.sources.registry.write_text(json.dumps(stored, indent=2) + "\n", encoding="utf-8")

        regenerated = write_registry(self.root)
        first_bytes = self.sources.registry.read_bytes()
        regenerated_again = write_registry(self.root)

        self.assertEqual(first_bytes, self.sources.registry.read_bytes())
        self.assertEqual(regenerated, regenerated_again)
        self.assertEqual(
            "verified_scene",
            self._criterion(regenerated, "Alpha remains observable.")["evidence"]["state"],
        )

    def test_changed_criterion_invalidates_prior_evidence(self):
        registry = write_registry(self.root)
        alpha = self._criterion(registry, "Alpha remains observable.")
        alpha["evidence"] = {
            "implemented": True,
            "production_reachable": True,
            "fresh_validation": True,
            "player_accepted": True,
            "state": "accepted",
            "refs": ["artifacts/feature-completion/P01/alpha.log"],
        }
        self.sources.registry.write_text(json.dumps(registry, indent=2) + "\n", encoding="utf-8")
        text = self.sources.requirements.read_text(encoding="utf-8")
        self.sources.requirements.write_text(
            text.replace("Alpha remains observable.", "Alpha remains observable after reload."),
            encoding="utf-8",
        )

        changed = write_registry(self.root)
        replacement = self._criterion(changed, "Alpha remains observable after reload.")

        self.assertNotEqual(alpha["criterion_fingerprint"], replacement["criterion_fingerprint"])
        self.assertEqual("not_verified", replacement["evidence"]["state"])
        self.assertEqual([], replacement["evidence"]["refs"])

    def test_reviewed_supersession_preserves_stable_scope_and_resets_old_evidence(self):
        original_text = "Alpha remains observable."
        replacement_text = "Alpha remains observable after reviewed replacement."
        (self.sources.features / "missing_acceptance.md").unlink()
        initial = write_registry(self.root)
        initial_count = initial["accounting"]["active_metric_denominator"]
        frozen_fingerprint = initial["scope_freeze_candidate"]["source_leaf_set_fingerprint"]
        original = self._criterion(initial, original_text)
        original["evidence"] = {
            "implemented": True,
            "production_reachable": True,
            "fresh_validation": True,
            "player_accepted": True,
            "state": "accepted",
            "refs": ["artifacts/accepted-old-claim.log"],
        }
        self.sources.registry.write_text(json.dumps(initial, indent=2) + "\n", encoding="utf-8")
        mapping = self.sources.reviewed_supersession(original_text, replacement_text)
        self.sources.write_supersessions([mapping])
        self.sources.requirements.write_text(
            self.sources.requirements.read_text(encoding="utf-8").replace(
                original_text,
                replacement_text,
            ),
            encoding="utf-8",
        )
        frozen = {
            "frozen_on": "2026-09-05",
            "source_leaf_set_fingerprint": frozen_fingerprint,
            "reviewed_supersession_set_fingerprint": _supersession_set_fingerprint([mapping]),
        }

        changed = write_registry(self.root, frozen_scope_contract=frozen)
        replacement = self._criterion(changed, replacement_text)

        self.assertEqual(original["id"], replacement["id"])
        self.assertEqual(mapping["replacement"]["criterion_fingerprint"], replacement["criterion_fingerprint"])
        self.assertEqual(mapping["replacement"]["natural_id"], replacement["criterion_supersession"]["replacement_natural_id"])
        self.assertEqual("not_verified", replacement["evidence"]["state"])
        self.assertEqual([], replacement["evidence"]["refs"])
        self.assertEqual([mapping], changed["criterion_supersession_review"])
        self.assertEqual(initial_count, changed["accounting"]["active_metric_denominator"])
        self.assertEqual(frozen_fingerprint, changed["scope_freeze_candidate"]["source_leaf_set_fingerprint"])
        self.assertFalse(any(entry["id"] == mapping["replacement"]["natural_id"] for entry in changed["criteria"]))

        before_reversion = self.sources.registry.read_bytes()
        self.sources.supersessions.unlink()
        self.sources.requirements.write_text(
            self.sources.requirements.read_text(encoding="utf-8").replace(
                replacement_text,
                original_text,
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(AssertionError, "reviewed supersession set drift"):
            write_registry(self.root, frozen_scope_contract=frozen)
        self.assertEqual(before_reversion, self.sources.registry.read_bytes())

    def test_reviewed_supersession_rejects_unapproved_third_wording_before_write(self):
        original_text = "Alpha remains observable."
        replacement_text = "Alpha remains observable after reviewed replacement."
        initial = write_registry(self.root)
        before = self.sources.registry.read_bytes()
        self.sources.write_supersessions([
            self.sources.reviewed_supersession(original_text, replacement_text)
        ])
        self.sources.requirements.write_text(
            self.sources.requirements.read_text(encoding="utf-8").replace(
                original_text,
                "Alpha has unreviewed third wording.",
            ),
            encoding="utf-8",
        )

        with self.assertRaisesRegex(AssertionError, "reviewed supersession target missing"):
            write_registry(self.root)
        self.assertEqual(before, self.sources.registry.read_bytes())
        self.assertTrue(initial["criteria"])

    def test_reviewed_feature_supersession_preserves_scope_and_resets_only_changed_evidence(self):
        original = "A feature-owned frozen geometry leaf."
        replacement = "A feature-owned reviewed geometry leaf."
        (self.sources.features / "missing_acceptance.md").unlink()
        feature_source = self.sources.features / "structural_wrapper_collision.md"
        feature_source.write_text(
            "# Structural wrapper collision\n\n## Acceptance criteria\n\n"
            f"- {original}\n",
            encoding="utf-8",
        )
        adr = self.root / "docs/game/adr/0066-test-feature-supersession.md"
        adr.parent.mkdir(parents=True, exist_ok=True)
        adr.write_text("# Test feature supersession authority\n", encoding="utf-8")
        initial = write_registry(self.root)
        original_entry = self._criterion(initial, original)
        original_entry["evidence"] = {
            "implemented": True,
            "production_reachable": True,
            "fresh_validation": True,
            "player_accepted": True,
            "state": "accepted",
            "refs": ["artifacts/accepted-feature.log"],
        }
        unchanged = self._criterion(initial, "A second feature leaf.")
        unchanged["evidence"] = {
            "implemented": True,
            "production_reachable": True,
            "fresh_validation": True,
            "player_accepted": False,
            "state": "verified_scene",
            "refs": ["artifacts/unchanged-feature.log"],
        }
        self.sources.registry.write_text(json.dumps(initial, indent=2) + "\n", encoding="utf-8")
        mapping = self.sources.reviewed_feature_supersession(original, replacement)
        self.sources.write_supersessions([mapping])
        feature_source.write_text(
            feature_source.read_text(encoding="utf-8").replace(original, replacement),
            encoding="utf-8",
        )
        frozen = {
            "frozen_on": "2026-09-05",
            "source_leaf_set_fingerprint": initial["scope_freeze_candidate"]["source_leaf_set_fingerprint"],
            "reviewed_supersession_set_fingerprint": _supersession_set_fingerprint([mapping]),
        }

        changed = write_registry(self.root, frozen_scope_contract=frozen)
        replacement_entry = self._criterion(changed, replacement)
        self.assertEqual(original_entry["id"], replacement_entry["id"])
        self.assertEqual("not_verified", replacement_entry["evidence"]["state"])
        self.assertEqual([], replacement_entry["evidence"]["refs"])
        self.assertEqual(
            "verified_scene",
            self._criterion(changed, "A second feature leaf.")["evidence"]["state"],
        )
        self.assertEqual(
            initial["scope_freeze_candidate"]["source_leaf_set_fingerprint"],
            changed["scope_freeze_candidate"]["source_leaf_set_fingerprint"],
        )
        self.assertEqual([mapping], changed["criterion_supersession_review"])

    def test_reviewed_feature_supersession_rejects_unknown_feature_source(self):
        mapping = self.sources.reviewed_feature_supersession(
            "A feature-owned frozen geometry leaf.",
            "Reviewed replacement.",
        )
        mapping["source"]["path"] = "docs/game/features/mapped.md"
        with self.assertRaisesRegex(AssertionError, "not an approved supersession source"):
            self.sources.write_supersessions([mapping])
            build(self.root)

    def test_reviewed_supersession_rejects_missing_target_before_write(self):
        original_text = "Alpha remains observable."
        replacement_text = "Alpha remains observable after reviewed replacement."
        write_registry(self.root)
        before = self.sources.registry.read_bytes()
        self.sources.write_supersessions([
            self.sources.reviewed_supersession(original_text, replacement_text)
        ])
        self.sources.requirements.write_text(
            self.sources.requirements.read_text(encoding="utf-8").replace(
                f"  - {original_text}\n",
                "",
            ),
            encoding="utf-8",
        )

        with self.assertRaisesRegex(AssertionError, "reviewed supersession target missing"):
            write_registry(self.root)
        self.assertEqual(before, self.sources.registry.read_bytes())

    def test_reviewed_supersession_rejects_duplicate_cycle_and_accounting_drift(self):
        alpha = "Alpha remains observable."
        beta = "Beta remains observable."
        gamma = "Gamma is the reviewed replacement."
        alpha_to_beta = self.sources.reviewed_supersession(alpha, beta)
        beta_to_alpha = self.sources.reviewed_supersession(beta, alpha)

        with self.subTest("duplicate"):
            self.sources.write_supersessions([alpha_to_beta, copy.deepcopy(alpha_to_beta)])
            with self.assertRaisesRegex(AssertionError, "duplicate reviewed supersession stable IDs"):
                build(self.root)

        with self.subTest("duplicate replacement"):
            alpha_to_gamma = self.sources.reviewed_supersession(alpha, gamma)
            beta_to_gamma = self.sources.reviewed_supersession(beta, gamma)
            self.sources.write_supersessions([alpha_to_gamma, beta_to_gamma])
            with self.assertRaisesRegex(AssertionError, "duplicate reviewed supersession replacement IDs"):
                build(self.root)

        with self.subTest("cycle"):
            self.sources.write_supersessions([alpha_to_beta, beta_to_alpha])
            with self.assertRaisesRegex(AssertionError, "cyclic reviewed criterion supersession mapping"):
                build(self.root)

        with self.subTest("fingerprint"):
            tampered = copy.deepcopy(alpha_to_beta)
            tampered["replacement"]["criterion_fingerprint"] = "0" * 64
            self.sources.write_supersessions([tampered])
            with self.assertRaisesRegex(AssertionError, "replacement criterion fingerprint mismatch"):
                build(self.root)

        with self.subTest("accounting"):
            drifted = copy.deepcopy(alpha_to_beta)
            drifted["accounting"]["denominator_delta"] = 1
            self.sources.write_supersessions([drifted])
            with self.assertRaisesRegex(AssertionError, "changes the frozen denominator"):
                build(self.root)

    def test_source_leaf_addition_and_removal_update_the_denominator(self):
        initial = write_registry(self.root)
        initial_count = initial["accounting"]["recorded"]
        original = self.sources.example.read_text(encoding="utf-8")
        self.sources.example.write_text(
            original.replace(
                "- A second feature leaf.",
                "- A second feature leaf.\n- A newly discovered feature leaf.",
            ),
            encoding="utf-8",
        )
        added = write_registry(self.root)
        self.assertEqual(initial_count + 1, added["accounting"]["recorded"])
        self._criterion(added, "A newly discovered feature leaf.")

        self.sources.example.write_text(
            self.sources.example.read_text(encoding="utf-8").replace(
                "- A player-visible feature leaf.\n", ""
            ),
            encoding="utf-8",
        )
        removed = write_registry(self.root)
        self.assertEqual(initial_count, removed["accounting"]["recorded"])
        self.assertFalse(
            any(entry["criterion"] == "A player-visible feature leaf." for entry in removed["criteria"])
        )

    def test_source_without_acceptance_is_explicitly_unassessed(self):
        registry = build(self.root)
        source = next(
            entry
            for entry in registry["source_documents"]
            if entry["path"] == "docs/game/features/missing_acceptance.md"
        )
        self.assertEqual("unassessed_no_acceptance_section", source["assessment"])
        self.assertIn(source["path"], registry["accounting"]["metric_blockers"])
        self.assertEqual(
            {"implemented": None, "validated": None, "accepted": None},
            registry["accounting"]["percentages"],
        )

    def test_reviewed_planning_proposal_is_catalogued_without_scope_rows(self):
        registry = build(self.root)
        proposal = registry["reviewed_out_of_scope_proposals"]
        self.assertEqual(1, len(proposal))
        self.assertEqual(
            {
                "path": "docs/game/features/ui_presentation_program.md",
                "disposition": "excluded_reviewed_planning_proposal",
                "actual_status": "Proposed for review, 2026-09-05. Planning only; no UI implementation or visual acceptance is claimed.",
                "reason": "Planning-only UI presentation proposal is outside the frozen crafting/derelict completion program.",
                "extracted_leaf_count": 21,
            },
            proposal[0],
        )
        self.assertFalse(any(
            entry["source"]["path"] == proposal[0]["path"]
            for entry in registry["criteria"]
        ))
        self.assertFalse(any(
            entry["path"] == proposal[0]["path"]
            for entry in registry["source_documents"]
        ))
        self.assertTrue(any(
            entry["source"]["path"] == "docs/game/features/example.md"
            for entry in registry["criteria"]
        ))

    def test_reviewed_planning_proposal_rejects_status_drift_or_missing_source(self):
        exact_status = "Proposed for review, 2026-09-05. Planning only; no UI implementation or visual acceptance is claimed."
        for label, contents in (
            ("accepted", "# UI\n\n**Status:** Accepted.\n"),
            ("ambiguous", "# UI\n\n**Status:** Proposed for review.\n"),
            ("accepted_with_old_phrases", "# UI\n\n**Status:** Accepted; formerly Proposed for review. Planning only previously.\n"),
            ("initial_then_accepted", f"# UI\n\n**Status:** {exact_status}\n\n**Status:** Accepted.\n"),
            ("duplicate_initial", f"# UI\n\n**Status:** {exact_status}\n\n**Status:** {exact_status}\n"),
        ):
            with self.subTest(label=label):
                self.sources.ui_proposal.write_text(contents, encoding="utf-8")
                with self.assertRaisesRegex(AssertionError, "catalogued out-of-scope proposal status"):
                    build(self.root)
        self.sources.ui_proposal.unlink()
        with self.assertRaisesRegex(AssertionError, "catalogued out-of-scope proposal is missing"):
            build(self.root)

    def test_unexpected_feature_source_still_rejects_frozen_scope(self):
        (self.sources.features / "missing_acceptance.md").unlink()
        initial = write_registry(self.root)
        frozen = {
            "frozen_on": "2026-09-05",
            "source_leaf_set_fingerprint": initial["scope_freeze_candidate"]["source_leaf_set_fingerprint"],
        }
        (self.sources.features / "unexpected.md").write_text(
            "# Unexpected feature\n\n## Acceptance criteria\n\n- New source leaf.\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(AssertionError, "frozen scope drift"):
            write_registry(self.root, frozen_scope_contract=frozen)
        (self.sources.features / "unexpected.md").unlink()
        (self.sources.features / "example.md").unlink()
        with self.assertRaisesRegex(AssertionError, "frozen scope drift"):
            write_registry(self.root, frozen_scope_contract=frozen)

    def test_only_genuine_acceptance_leaves_are_registered_once(self):
        registry = build(self.root)
        criteria = [entry["criterion"] for entry in registry["criteria"]]
        self.assertIn("A player-visible feature leaf.", criteria)
        self.assertNotIn("This implementation bullet is not acceptance.", criteria)
        anchors = [entry["anchor"] for entry in registry["source_leaf_coverage"]]
        self.assertEqual(len(anchors), len(set(anchors)))
        self.assertTrue(all(entry["criterion_ids"] for entry in registry["source_leaf_coverage"]))

    def test_leaf_kind_and_deferred_scope_are_explicit(self):
        registry = build(self.root)
        workflow = self._criterion(registry, "**Workflow:** A workflow leaf remains active.")
        deferred = self._criterion(
            registry,
            "**Deferred:** A separately promised future leaf remains accounted.",
        )
        self.assertEqual("workflow", workflow["acceptance_kind"])
        self.assertFalse(workflow["deferred"])
        self.assertEqual("deferred", deferred["acceptance_kind"])
        self.assertTrue(deferred["deferred"])

    def test_numbered_and_qualified_acceptance_leaves_are_extracted(self):
        registry = build(self.root)
        criteria = [entry["criterion"] for entry in registry["criteria"]]
        self.assertIn("A qualified acceptance label is still extracted.", criteria)
        self.assertIn("The first numbered criterion spans a continuation line.", criteria)
        self.assertIn("The second numbered criterion remains separate.", criteria)
        numbered = self._criterion(registry, "The first numbered criterion spans a continuation line.")
        self.assertTrue(numbered["deferred"])
        self.assertIn("expected-unbuilt", numbered["declared_status"])
        mapped = next(
            entry
            for entry in registry["source_documents"]
            if entry["path"] == "docs/game/features/mapped.md"
        )
        self.assertEqual("acceptance_mapped_to_requirements", mapped["assessment"])
        self.assertEqual(["REQ-TEST-001", "REQ-TEST-002", "REQ-TEST-003"], mapped["mapped_requirement_ids"])
        self.assertNotIn(mapped["path"], registry["accounting"]["metric_blockers"])

    def test_generated_registry_is_complete_and_conservative(self):
        registry = build()
        cards = build_card_manifest()
        validate(registry, cards)
        self.assertEqual(24, len([c for c in registry["criteria"] if c["id"].startswith("FC-")]))
        self.assertTrue(any(c["deferred"] for c in registry["criteria"]))
        self.assertEqual(len(registry["criteria"]), registry["accounting"]["recorded"])
        self.assertNotIn("source_directory", cards)

    def test_partial_evidence_mapping_keeps_headline_counts_unknown(self):
        registry = write_registry(self.root)
        target = next(entry for entry in registry["criteria"] if not entry["deferred"] and entry["metric_equivalence"]["counts_toward_proposed_denominator"])
        target["evidence"] = {"implemented": True, "production_reachable": True,
                              "fresh_validation": True, "player_accepted": False,
                              "state": "verified_scene", "refs": ["artifact://partial"]}
        self.sources.registry.write_text(json.dumps(registry), encoding="utf-8")
        rebuilt = build(self.root)
        accounting = rebuilt["accounting"]
        self.assertEqual("incomplete", accounting["evidence_mapping"]["status"])
        self.assertEqual(1, accounting["evidence_mapping"]["mapped_criteria"])
        self.assertEqual(1, accounting["promoted_evidence_counts"]["implemented"])
        self.assertEqual(1, accounting["promoted_evidence_counts"]["freshly_validated"])
        self.assertTrue(all(accounting[field] is None for field in ("implemented", "production_reachable", "freshly_validated", "player_accepted", "accepted")))
        self.assertTrue(all(value is None for value in accounting["percentages"].values()))

    def test_complete_evidence_mapping_publishes_derived_counts(self):
        (self.sources.features / "missing_acceptance.md").unlink()
        registry = write_registry(self.root)
        frozen = {"frozen_on": "2026-09-05", "source_leaf_set_fingerprint": registry["scope_freeze_candidate"]["source_leaf_set_fingerprint"]}
        denominator = [entry for entry in registry["criteria"] if not entry["deferred"] and entry["metric_equivalence"]["counts_toward_proposed_denominator"]]
        for index, entry in enumerate(denominator):
            entry["evidence"] = {"implemented": index % 2 == 0, "production_reachable": index % 3 == 0,
                                 "fresh_validation": index % 4 == 0, "player_accepted": index % 5 == 0,
                                 "state": "accepted" if index % 6 == 0 else "verified_scene", "refs": [f"artifact://{index}"]}
        self.sources.registry.write_text(json.dumps(registry), encoding="utf-8")
        rebuilt = build(self.root, frozen_scope_contract=frozen)
        accounting = rebuilt["accounting"]
        self.assertEqual("complete", accounting["evidence_mapping"]["status"])
        self.assertEqual(0, accounting["evidence_mapping"]["unknown_criteria"])
        self.assertEqual(len(denominator), accounting["evidence_mapping"]["mapped_criteria"])
        expected = {"implemented": sum(index % 2 == 0 for index in range(len(denominator))), "production_reachable": sum(index % 3 == 0 for index in range(len(denominator))), "freshly_validated": sum(index % 4 == 0 for index in range(len(denominator))), "player_accepted": sum(index % 5 == 0 for index in range(len(denominator))), "accepted": sum(index % 6 == 0 for index in range(len(denominator)))}
        self.assertEqual(expected, {key: accounting[key] for key in expected})
        self.assertEqual(expected, accounting["promoted_evidence_counts"])
        self.assertEqual(round(expected["implemented"] * 100 / len(denominator), 2), accounting["percentages"]["implemented"])
        self.assertEqual(round(expected["freshly_validated"] * 100 / len(denominator), 2), accounting["percentages"]["validated"])
        self.assertEqual(round(expected["accepted"] * 100 / len(denominator), 2), accounting["percentages"]["accepted"])
        plan = self.root / PLAN_REL
        plan.parent.mkdir(parents=True, exist_ok=True)
        plan.write_text(PLAN.read_text(encoding="utf-8"), encoding="utf-8")
        validate(rebuilt, build_card_manifest(self.root), self.root)
        damaged = copy.deepcopy(rebuilt)
        damaged["accounting"]["promoted_evidence_counts"]["implemented"] += 1
        with self.assertRaisesRegex(AssertionError, "promoted evidence count mismatch"):
            validate(damaged, build_card_manifest(self.root), self.root)
        unfrozen = build(self.root)
        self.assertTrue(all(value is None for value in unfrozen["accounting"]["percentages"].values()))

    def test_real_source_accounting_matches_the_reviewed_frozen_scope(self):
        registry = build()
        self.assertEqual([], registry["accounting"]["metric_blockers"])
        self.assertEqual(0, registry["accounting"]["unassessed_source_count"])
        self.assertEqual("frozen", registry["accounting"]["denominator_status"])
        self.assertEqual("2026-09-05", registry["scope_frozen"]["frozen_on"])
        self.assertEqual("root_coordinator", registry["scope_frozen"]["reviewer"])
        self.assertEqual(
            "54f7c6f782eac4ca7e4a589304b9a74fc754ab3f3384bdf0d5ee3121ec482a8f",
            registry["scope_frozen"]["reviewed_supersession_set_fingerprint"],
        )
        self.assertEqual(
            registry["scope_frozen"]["source_leaf_set_fingerprint"],
            registry["scope_freeze_candidate"]["source_leaf_set_fingerprint"],
        )
        self.assertEqual("matches_frozen_contract", registry["scope_freeze_candidate"]["status"])
        self.assertEqual("frozen", registry["scope_review"]["status"])
        self.assertEqual(
            {"implemented": None, "validated": None, "accepted": None},
            registry["accounting"]["percentages"],
        )
        self.assertEqual(
            {
                "status": "incomplete",
                "mapped_criteria": 0,
                "unknown_criteria": 622,
                "coverage_percent": 0.0,
                "definition": "Only reviewed criterion-level evidence mappings count as coverage; historical status and standalone/helper PASS output do not create one.",
            },
            registry["accounting"]["evidence_mapping"],
        )
        self.assertEqual(
            {
                "implemented": 0,
                "production_reachable": 0,
                "freshly_validated": 0,
                "player_accepted": 0,
                "accepted": 0,
            },
            registry["accounting"]["promoted_evidence_counts"],
        )
        self.assertGreater(registry["accounting"]["equivalence_alias_count"], 0)
        self.assertEqual(622, registry["accounting"]["active_metric_denominator"])
        self.assertEqual(35, registry["accounting"]["equivalence_alias_count"])
        dispositions = [group["disposition"] for group in registry["duplicate_criterion_review"]]
        self.assertEqual(14, dispositions.count("reviewed_equivalent_same_package_boilerplate"))
        self.assertEqual(3, dispositions.count("reviewed_same_text_distinct_scope"))
        self.assertTrue(all(group["review"]["reviewer"] == "root_coordinator" for group in registry["duplicate_criterion_review"]))
        superseded = next(
            entry
            for entry in registry["criteria"]
            if entry["id"] == "REQ-SMOD-001::acceptance-cc93b99b2016"
        )
        self.assertEqual(
            "Catalog-linked installs connect the installed lot's preserved condition to the hub ship-system subcomponent; dismounting the last provider disconnects it without changing intrinsic health or item condition.",
            superseded["criterion"],
        )
        self.assertEqual(
            "a4d1e10d64d29fbfe185be8cb8fac3cf95c98f2748a943f453739001caa1fea2",
            superseded["criterion_fingerprint"],
        )
        self.assertEqual("not_verified", superseded["evidence"]["state"])
        self.assertEqual([], superseded["evidence"]["refs"])
        self.assertEqual(4, registry["criterion_supersession_source"]["reviewed_mapping_count"])
        self.assertEqual(
            "ca2c7292b2639e65d66a3ccb3f6dfeda65a924a1b16c6f411f33b4b6454996cc",
            registry["criterion_supersession_review"][0]["original"]["criterion_fingerprint"],
        )

        expected_maps = {
            "docs/game/features/crafting_materials_recipes.md": ["REQ-CS-001", "REQ-CS-005", "REQ-CS-014"],
            "docs/game/features/loot_ecosystem.md": ["REQ-LE-001", "REQ-LE-002", "REQ-LE-005"],
            "docs/game/features/player_progression.md": ["REQ-PM-001", "REQ-PM-006", "REQ-PM-007"],
        }
        sources = {source["path"]: source for source in registry["source_documents"]}
        for path, requirement_ids in expected_maps.items():
            self.assertEqual(requirement_ids, sources[path]["mapped_requirement_ids"])
            self.assertEqual("acceptance_extracted", sources[path]["assessment"])

    def test_same_text_in_different_requirement_contexts_stays_distinct(self):
        shared = "A shared sentence has context-specific meaning."
        with self.sources.requirements.open("a", encoding="utf-8") as handle:
            handle.write(
                f"""

## REQ-CONTEXT-001: First context

- Source: `features/first.md`
- Status: Approved
- Acceptance criteria:
  - {shared}
- Verification:
  - `first_smoke.gd`

## REQ-CONTEXT-002: Second context

- Source: `features/second.md`
- Status: Approved
- Acceptance criteria:
  - {shared}
- Verification:
  - `second_smoke.gd`
"""
            )
        registry = build(self.root)
        entries = [entry for entry in registry["criteria"] if entry["criterion"] == shared]
        self.assertEqual(2, len(entries))
        self.assertTrue(all(entry["metric_equivalence"]["counts_toward_proposed_denominator"] for entry in entries))
        self.assertEqual(2, len({entry["metric_equivalence"]["group_id"] for entry in entries}))
        group = next(item for item in registry["duplicate_criterion_review"] if item["criterion"] == shared)
        self.assertEqual("reviewed_same_text_distinct_scope", group["disposition"])
        self.assertEqual([], group["alias_ids"])

    def test_validation_rejects_silently_dropped_source_documents(self):
        registry = build()
        cards = build_card_manifest()
        damaged = copy.deepcopy(registry)
        damaged["source_documents"] = damaged["source_documents"][:-1]
        with self.assertRaisesRegex(AssertionError, "source document inventory"):
            validate(damaged, cards)

    def test_validation_rejects_proposed_denominator_drift(self):
        registry = build()
        cards = build_card_manifest()
        damaged = copy.deepcopy(registry)
        damaged["accounting"]["active_metric_denominator"] += 1
        with self.assertRaisesRegex(AssertionError, "active metric denominator mismatch"):
            validate(damaged, cards)

    def test_validation_rejects_tampered_supersession_history(self):
        registry = build()
        cards = build_card_manifest()
        damaged = copy.deepcopy(registry)
        damaged["criterion_supersession_review"][0]["review"]["reviewer"] = "unreviewed"
        with self.assertRaisesRegex(AssertionError, "reviewed supersession history mismatch"):
            validate(damaged, cards)

    def test_frozen_scope_drift_fails_before_stored_evidence_is_rewritten(self):
        (self.sources.features / "missing_acceptance.md").unlink()
        registry = write_registry(self.root)
        alpha = self._criterion(registry, "Alpha remains observable.")
        alpha["evidence"] = {
            "implemented": True,
            "production_reachable": True,
            "fresh_validation": True,
            "player_accepted": False,
            "state": "verified_scene",
            "refs": ["artifacts/feature-completion/P01/alpha.log"],
        }
        self.sources.registry.write_text(json.dumps(registry, indent=2) + "\n", encoding="utf-8")
        before = self.sources.registry.read_bytes()
        frozen = {
            "frozen_on": "2026-09-04",
            "source_leaf_set_fingerprint": "not-the-current-fingerprint",
        }
        with self.assertRaisesRegex(AssertionError, "frozen scope drift"):
            write_registry(self.root, frozen_scope_contract=frozen)
        self.assertEqual(before, self.sources.registry.read_bytes())

    def test_card_dependencies_are_verified_against_the_tracked_plan(self):
        plan = self.root / "docs/superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md"
        plan.parent.mkdir(parents=True)
        source = PLAN.read_text(encoding="utf-8")
        plan.write_text(
            source.replace(
                "**Depends:** P01-P02. **Requirements:** FC-05, FC-12.",
                "**Depends:** P01. **Requirements:** FC-05, FC-12.",
                1,
            ),
            encoding="utf-8",
        )
        with self.assertRaisesRegex(AssertionError, "plan dependencies"):
            build_card_manifest(self.root)

    def test_all_cards_use_tracked_plan_anchors_paths_and_executable_checks(self):
        self.assertTrue(PLAN.is_file())
        manifest = build_card_manifest()
        self.assertEqual([f"P{number:02d}" for number in range(25)], [c["id"] for c in manifest["cards"]])
        for card in manifest["cards"]:
            self.assertEqual(
                "docs/superpowers/plans/2026-09-04-crafting-derelict-feature-completion.md",
                card["plan_anchor"]["path"],
            )
            self.assertEqual(card["id"], card["plan_anchor"]["heading"])
            self.assertTrue(card["allowlist"])
            self.assertTrue(all("/" in item["path"] or item["path"] in {".gitattributes", "README.md", "AGENTS.md", "STATUS.md", "export_presets.cfg"} for item in card["allowlist"]))
            self.assertTrue(card["verification"])
            for check in card["verification"]:
                self.assertTrue(check["command"])
                self.assertEqual(0, check["success"]["exit_code"])
                self.assertTrue(check["success"]["required_output"])
        p06 = next(card for card in manifest["cards"] if card["id"] == "P06")
        self.assertIn(
            "data/items/item_definitions.json",
            [entry["path"] for entry in p06["allowlist"]],
        )
        self.assertEqual([], p06["scope_decisions_pending"])
        p00 = next(card for card in manifest["cards"] if card["id"] == "P00")
        self.assertIn(
            "scripts/procgen/ship_generator.gd",
            [entry["path"] for entry in p00["allowlist"]],
        )
        self.assertIn(
            "scripts/procgen/playable_generated_ship.gd",
            [entry["path"] for entry in p00["allowlist"]],
        )
        for expected_path in (
            "docs/game/adr/0061-persist-resolved-generation-context.md",
            "docs/game/adr/0063-lifeboat-compiled-biome-contract.md",
            "docs/game/adr/0064-versioned-current-topology-parity-fixture.md",
            "data/procgen/golden/compact_seed17_current/**",
            "scripts/procgen/ship_blueprint.gd",
            "scripts/procgen/life_boat.gd",
            "scripts/validation/derelict_arc_smoke.gd",
            "scripts/validation/main_playable_lifeboat_biome_skin_smoke.gd",
            "scripts/validation/item_economy_smoke.gd",
            "scripts/validation/main_playable_item_economy_smoke.gd",
            "scripts/validation/main_playable_survival_stakes_smoke.gd",
            "scripts/validation/audio_spatial_playback_smoke.gd",
        ):
            self.assertIn(expected_path, [entry["path"] for entry in p00["allowlist"]])
        self.assertTrue(any("main_playable_survival_stakes_smoke.gd" in check["command"] for check in p00["verification"]))
        self.assertTrue(any("audio_spatial_playback_smoke.gd" in check["command"] for check in p00["verification"]))
        p04 = next(card for card in manifest["cards"] if card["id"] == "P04")
        for expected_path in (
            "scripts/systems/ship_instance.gd",
            "scripts/systems/world_snapshot.gd",
            "scripts/tools/crafting_station.gd",
            "scripts/validation/fc_p04_holder_atomicity_smoke.gd",
            "scripts/validation/fc_p04_floor_drop_persistence_smoke.gd",
            "scripts/validation/fc_p04_objective_lots_smoke.gd",
            "scripts/validation/equipment_carts_smoke.gd",
            "scripts/validation/main_playable_slice_inventory_ui_smoke.gd",
            "scripts/validation/crafting_quality_knowledge_smoke.gd",
        ):
            self.assertIn(expected_path, [entry["path"] for entry in p04["allowlist"]])
        p04_commands = [check["command"] for check in p04["verification"]]
        self.assertTrue(any("fc_p04_holder_atomicity_smoke.gd" in command for command in p04_commands))
        self.assertTrue(any("fc_p04_floor_drop_persistence_smoke.gd" in command for command in p04_commands))
        self.assertTrue(any("fc_p04_objective_lots_smoke.gd" in command for command in p04_commands))
        self.assertTrue(any("crafting_quality_knowledge_smoke.gd" in command for command in p04_commands))
        p05 = next(card for card in manifest["cards"] if card["id"] == "P05")
        for expected_path in (
            "scripts/systems/work_action_driver.gd",
            "scripts/procgen/playable_generated_ship.gd",
            "docs/game/balance/crafting_materials_tuning.md",
            "scripts/systems/medicine_state.gd",
            "scripts/systems/stimulant_state.gd",
            "scripts/systems/effect_dispatcher.gd",
            "scripts/systems/ship_modification_state.gd",
        ):
            self.assertIn(expected_path, [entry["path"] for entry in p05["allowlist"]])
        p07 = next(card for card in manifest["cards"] if card["id"] == "P07")
        self.assertIn("scripts/tools/crafting_station.gd", [entry["path"] for entry in p07["allowlist"]])
        self.assertIn("scripts/procgen/playable_generated_ship.gd", [entry["path"] for entry in p07["allowlist"]])
        self.assertIn("scripts/validation/station_tiers_batch_smoke.gd", [entry["path"] for entry in p07["allowlist"]])
        self.assertIn("scripts/validation/fc_p06_smoke.gd", [entry["path"] for entry in p07["allowlist"]])
        self.assertTrue(any("fc_p06_smoke.gd" in check["command"] for check in p07["verification"]))
        p11 = next(card for card in manifest["cards"] if card["id"] == "P11")
        for expected_path in (
            "scripts/procgen/wall_door_resolver.gd",
            "scripts/procgen/layout_serializer.gd",
            "scripts/procgen/ship_generator.gd",
        ):
            self.assertIn(expected_path, [entry["path"] for entry in p11["allowlist"]])
        for golden_path in (
            "data/procgen/golden/coherent_ship_001/layout.json",
            "data/procgen/golden/coherent_ship_002/layout.json",
        ):
            self.assertIn(golden_path, [entry["path"] for entry in p11["allowlist"]])
        for fixture_path in (
            "scripts/validation/fc_p11_live_smoke.gd",
            "scripts/validation/ship_modification_panel_smoke.gd",
            "scripts/validation/ship_mod_power_budget_scene_away_smoke.gd",
            "scripts/validation/ship_mod_restore_effects_away_smoke.gd",
            "scripts/validation/ship_mod_system_effect_away_smoke.gd",
        ):
            self.assertIn(fixture_path, [entry["path"] for entry in p11["allowlist"]])
        p12 = next(card for card in manifest["cards"] if card["id"] == "P12")
        for expected_path in (
            "scripts/procgen/playable_generated_ship.gd",
            "scripts/validation/fc_p11_live_smoke.gd",
            "scripts/validation/ship_modification_panel_smoke.gd",
            "scripts/validation/ship_mod_system_effect_away_smoke.gd",
            "scripts/validation/ship_mod_power_budget_scene_away_smoke.gd",
            "scripts/validation/ship_mod_restore_effects_away_smoke.gd",
            "scripts/systems/component_placement_state.gd",
        ):
            self.assertIn(expected_path, [entry["path"] for entry in p12["allowlist"]])
        p14 = next(card for card in manifest["cards"] if card["id"] == "P14")
        for expected_path in (
            "docs/game/adr/0066-durable-machinery-condition-and-effective-system-health.md",
            "docs/game/05_requirements.md",
            "data/validation/reviewed_criterion_supersessions_v1.json",
            "docs/game/inventory/feature_acceptance.json",
            "tools/build_feature_acceptance.py",
            "tests/test_feature_acceptance_registry.py",
            "scripts/systems/component_placement_state.gd",
            "scripts/systems/ship_systems_manager.gd",
            "scripts/tools/repair_point.gd",
            "scripts/validation/fc_p14_smoke.gd",
            "scripts/validation/ship_mod_run_snapshot_smoke.gd",
        ):
            self.assertIn(expected_path, [entry["path"] for entry in p14["allowlist"]])
        p14_commands = [check["command"] for check in p14["verification"]]
        self.assertTrue(any("fc_p14_smoke.gd" in command for command in p14_commands))
        self.assertFalse(any("ship_mod_restore_effects_smoke.gd" in command for command in p14_commands))
        p16 = next(card for card in manifest["cards"] if card["id"] == "P16")
        self.assertIn(
            "scripts/procgen/playable_generated_ship.gd",
            [entry["path"] for entry in p16["allowlist"]],
        )
        p17 = next(card for card in manifest["cards"] if card["id"] == "P17")
        for expected_path in (
            "docs/game/features/structural_wrapper_collision.md",
            "docs/game/05_requirements.md",
            "scripts/procgen/layout_serializer.gd",
            "tools/rebuild_vertex_span_modules.py",
            "scenes/wrappers/structural/ship_structural_v0/wall_inner_corner.tscn",
            "scenes/wrappers/structural/ship_structural_v0/wall_t_junction.tscn",
            "scripts/validation/structural_rebuild_collision_query_smoke.gd",
        ):
            self.assertIn(expected_path, [entry["path"] for entry in p17["allowlist"]])
        self.assertTrue(any("vertex-owned 2 m by 3 m by 0.2 m rays" in decision for decision in p17["scope_decisions_pending"]))


if __name__ == "__main__":
    unittest.main()
