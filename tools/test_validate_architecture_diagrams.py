from __future__ import annotations

import contextlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import validate_architecture_diagrams as vad


H2 = [
    "Purpose and conclusion", "Diagram", "Relationship legend", "Text equivalent",
    "Evidence", "Explicit, inferred, and omitted", "Known current gaps",
    "Export and regeneration",
]
README_H2 = [
    "Purpose", "Reading order", "Notation", "Evidence hierarchy",
    "Freshness policy", "Regeneration and validation", "Exhaustive maps",
]


def diagram_text(diagram_id: str, family: str, source_path: str = "project.godot") -> str:
    syntax = {
        "flowchart": "flowchart LR\n  A[Source] edge@--> B[Target]\n  classDef dataEdge stroke-dasharray:2\\,3;\n  class edge dataEdge;",
        "sequence": "sequenceDiagram\n  participant A\n  participant B\n  A->>B: call\n  B-->>A: return",
        "state": "stateDiagram-v2\n  state Decision <<choice>>\n  [*] --> IDLE\n  IDLE --> Decision: tick [always] / evaluate\n  Decision --> IDLE: otherwise [true] / wait",
    }[family]
    if diagram_id == "ARCH-COMP-RUNTIME":
        syntax += "\n  classDef signalEdge stroke-dasharray:8\\,4;"
    legend = {
        "flowchart": "Solid direct call; dataEdge is short-dot; labels carry meaning.",
        "sequence": "Solid direct call; dashed signal or return; labels carry meaning.",
        "state": "Standard labeled state transitions; line style carries no meaning.",
    }[family]
    parts = [
        f"# {diagram_id}", "", f"- **Diagram ID:** {diagram_id}",
        "- **Audience:** Developers", "- **Scope:** Current implementation",
        "- **Evidence baseline:** test", "- **Freshness date:** 2026-07-10", "",
        "## Purpose and conclusion", "", "Purpose. Conclusion.", "",
        "## Diagram", "", "```mermaid", syntax, "```", "",
        "## Relationship legend", "", legend, "",
        "## Text equivalent", "", "Source calls Target.", "",
        "## Evidence", "",
        "| Element or relationship | Source path | Symbol | Basis |",
        "| --- | --- | --- | --- |",
        f"| A to B | {source_path} | test_symbol | explicit |", "",
        "## Explicit, inferred, and omitted", "", "All shown edges are explicit.", "",
        "## Known current gaps", "", "None in this fixture.", "",
        "## Export and regeneration", "", "Run the repository validator.", "",
    ]
    return "\n".join(parts)


def index_text() -> str:
    lines = ["# Architecture", ""]
    for heading in README_H2:
        lines.extend([f"## {heading}", "", f"{heading} text.", ""])
    return "\n".join(lines)


class ValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        arch = self.root / "docs/game/architecture"
        arch.mkdir(parents=True)
        (arch / "README.md").write_text(index_text(), encoding="utf-8")
        for spec in vad.DIAGRAM_SPECS:
            (arch / spec.filename).write_text(
                diagram_text(spec.expected_id, spec.family), encoding="utf-8"
            )
        tool = self.root / "tools/architecture"
        package_root = tool / "node_modules/@mermaid-js/mermaid-cli"
        cli = package_root / "src/cli.js"
        cli.parent.mkdir(parents=True)
        cli.write_text("// fake cli\n", encoding="utf-8")
        (tool / "package.json").write_text(json.dumps({
            "private": True, "engines": {"node": "26.x"},
            "devDependencies": {"@mermaid-js/mermaid-cli": "11.16.0"},
        }), encoding="utf-8")
        (package_root / "package.json").write_text(json.dumps({
            "name": "@mermaid-js/mermaid-cli", "version": "11.16.0",
            "bin": {"mmdc": "./src/cli.js"},
        }), encoding="utf-8")
        (tool / "mermaid.config.json").write_text("{}\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def fake_runner(args: list[str], **_kwargs) -> subprocess.CompletedProcess[str]:
        output = Path(args[args.index("--output") + 1])
        output.write_text(
            '<svg xmlns="http://www.w3.org/2000/svg"><text>ok</text></svg>',
            encoding="utf-8",
        )
        return subprocess.CompletedProcess(args, 0, "", "")

    def run_main(self, *args: str, runner=None) -> tuple[int, str]:
        out = io.StringIO()
        selected = runner or self.fake_runner
        with (
            patch.object(vad.subprocess, "run", side_effect=selected),
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(out),
        ):
            code = vad.main([*args, "--root", str(self.root)])
        return code, out.getvalue()

    def test_valid_update_then_check(self) -> None:
        code, output = self.run_main("--update")
        self.assertEqual(0, code, output)
        self.assertRegex(
            output,
            r"ARCHITECTURE DIAGRAMS PASS diagrams=5 exports=5 references=5",
        )
        code, output = self.run_main("--check")
        self.assertEqual(0, code, output)

    def test_rejects_duplicate_mermaid_fence(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        path.write_text(
            path.read_text(encoding="utf-8")
            + "\n```mermaid\nflowchart LR\nX-->Y\n```\n",
            encoding="utf-8",
        )
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("exactly one Mermaid fence", output)

    def test_rejects_bad_heading_order_and_basis(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        text = path.read_text(encoding="utf-8").replace(
            "## Relationship legend", "## Evidence", 1
        )
        path.write_text(text, encoding="utf-8")
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("H2 headings", output)

    def test_rejects_missing_and_escaping_evidence_paths(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        path.write_text(
            diagram_text("ARCH-C4-CONTEXT", "flowchart", "../secret.txt"),
            encoding="utf-8",
        )
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("repository-relative", output)

    def test_rejects_retired_id_only_inside_mermaid(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("A[Source]", "A[FireState]"),
            encoding="utf-8",
        )
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("prohibited current-architecture ID", output)

    def test_rejects_any_flowchart_relationship_without_stable_edge_id(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        text = path.read_text(encoding="utf-8").replace(
            "  A[Source] edge@--> B[Target]",
            "  A[Source] edge@--> B[Target]\n  B --> C[Other]",
        )
        path.write_text(text, encoding="utf-8")
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("stable edge ID", output)

    def test_rejects_unidentified_chained_flowchart_relationship(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        text = path.read_text(encoding="utf-8").replace(
            "A[Source] edge@--> B[Target]",
            "A[Source] first@--> B[Target] --> C[Other]",
        )
        path.write_text(text, encoding="utf-8")
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("stable edge ID", output)

    def test_rejects_grouped_flowchart_endpoints(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        text = path.read_text(encoding="utf-8").replace(
            "A[Source] edge@--> B[Target]",
            "A[Source] & B[Other] edge@--> C[Target]",
        )
        path.write_text(text, encoding="utf-8")
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("grouped endpoints", output)

    def test_ignores_flowchart_operator_inside_node_text(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        text = path.read_text(encoding="utf-8").replace(
            "  A[Source] edge@--> B[Target]",
            '  Label["source --> target"]\n  A[Source] edge@--> B[Target]',
        )
        path.write_text(text, encoding="utf-8")
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(0, code, output)

    def test_rejects_edge_when_id_syntax_appears_only_inside_node_text(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        text = path.read_text(encoding="utf-8").replace(
            "A[Source] edge@--> B[Target]",
            'A["fake@-->"] --> B[Target]',
        )
        path.write_text(text, encoding="utf-8")
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("stable edge ID", output)

    def test_accepts_renderer_valid_flowchart_edge_ids(self) -> None:
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        for edge_id in ("1edge", "edge$", "ÉDGE"):
            with self.subTest(edge_id=edge_id):
                text = diagram_text("ARCH-C4-CONTEXT", "flowchart").replace(
                    "edge@-->",
                    f"{edge_id}@-->",
                )
                path.write_text(text, encoding="utf-8")
                code, output = self.run_main(
                    "--check-source", str(path.relative_to(self.root))
                )
                self.assertEqual(0, code, output)

    def test_rejects_unlabeled_ordinary_state_transition(self) -> None:
        path = self.root / "docs/game/architecture/04-threat-ai-state-machine.md"
        text = path.read_text(encoding="utf-8").replace(
            "IDLE --> Decision: tick [always] / evaluate",
            "IDLE --> Decision",
        )
        path.write_text(text, encoding="utf-8")
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("event [guard] / action", output)

    def test_rejects_empty_state_transition_notation_parts(self) -> None:
        path = self.root / "docs/game/architecture/04-threat-ai-state-machine.md"
        invalid_labels = (
            "  [always] / evaluate",
            "tick [ ] / evaluate",
            "tick [always] /  ",
        )
        for label in invalid_labels:
            with self.subTest(label=label):
                text = diagram_text("ARCH-STATE-THREAT-AI", "state").replace(
                    "tick [always] / evaluate",
                    label,
                )
                path.write_text(text, encoding="utf-8")
                code, output = self.run_main(
                    "--check-source", str(path.relative_to(self.root))
                )
                self.assertEqual(1, code)
                self.assertIn("event [guard] / action", output)

    def test_rejects_unlabeled_renderer_valid_state_transition_forms(self) -> None:
        path = self.root / "docs/game/architecture/04-threat-ai-state-machine.md"
        invalid_transitions = (
            "1STATE --> Decision",
            "A$ --> Decision",
            "ÉTAT --> Decision",
            (
                "IDLE --> Decision: tick [always] / evaluate; "
                "Decision --> IDLE"
            ),
        )
        for transition in invalid_transitions:
            with self.subTest(transition=transition):
                text = diagram_text("ARCH-STATE-THREAT-AI", "state").replace(
                    "IDLE --> Decision: tick [always] / evaluate",
                    transition,
                )
                path.write_text(text, encoding="utf-8")
                code, output = self.run_main(
                    "--check-source", str(path.relative_to(self.root))
                )
                self.assertEqual(1, code)
                self.assertIn("event [guard] / action", output)

    def test_rejects_unclassified_nested_state_transition(self) -> None:
        path = self.root / "docs/game/architecture/04-threat-ai-state-machine.md"
        text = path.read_text(encoding="utf-8").replace(
            "  state Decision <<choice>>",
            "  state Decision <<choice>>\n  state Composite { A --> B }",
        )
        path.write_text(text, encoding="utf-8")
        code, output = self.run_main(
            "--check-source", str(path.relative_to(self.root))
        )
        self.assertEqual(1, code)
        self.assertIn("cannot classify state transition", output)

    def test_stale_hash_fails_check(self) -> None:
        code, output = self.run_main("--update")
        self.assertEqual(0, code, output)
        path = self.root / "docs/game/architecture/01-c4-system-context.md"
        path.write_text(
            path.read_text(encoding="utf-8").replace("A[Source]", "A[Changed]"),
            encoding="utf-8",
        )
        code, output = self.run_main("--check")
        self.assertEqual(1, code)
        self.assertIn("source_sha256", output)

    def test_render_failure_keeps_all_exports(self) -> None:
        code, output = self.run_main("--update")
        self.assertEqual(0, code, output)
        exports = sorted((self.root / "docs/game/architecture/rendered").glob("*.svg"))
        before = {p.name: p.read_bytes() for p in exports}
        calls = {"n": 0}

        def fail_third(args: list[str], **kwargs):
            calls["n"] += 1
            if calls["n"] == 3:
                return subprocess.CompletedProcess(args, 2, "", "renderer exploded")
            return self.fake_runner(args, **kwargs)

        code, output = self.run_main("--update", runner=fail_third)
        self.assertEqual(1, code)
        self.assertIn("renderer exploded", output)
        self.assertEqual(before, {p.name: p.read_bytes() for p in exports})


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ValidatorTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        raise SystemExit(1)
    print("ARCHITECTURE DIAGRAM VALIDATOR SELFTEST PASS")
