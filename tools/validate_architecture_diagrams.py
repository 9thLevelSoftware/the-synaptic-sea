#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Sequence

ROOT_DEFAULT = Path(__file__).resolve().parents[1]
ARCH_REL = Path("docs/game/architecture")
RENDERER_REL = Path("tools/architecture")
H2_EXPECTED = [
    "Purpose and conclusion", "Diagram", "Relationship legend", "Text equivalent",
    "Evidence", "Explicit, inferred, and omitted", "Known current gaps",
    "Export and regeneration",
]
README_H2 = [
    "Purpose", "Reading order", "Notation", "Evidence hierarchy",
    "Freshness policy", "Regeneration and validation", "Exhaustive maps",
]
META_KEYS = ["Diagram ID", "Audience", "Scope", "Evidence baseline", "Freshness date"]
EVIDENCE_COLUMNS = ["Element or relationship", "Source path", "Symbol", "Basis"]
BASIS = {"explicit", "engine lifecycle", "inventory", "feature spec", "ADR", "requirement"}
PROHIBITED = {"ShipSystemState", "FireState", "MinimapPanel", "MapFogState", "GDAIMCPRuntime"}
MERMAID_RE = re.compile(r"```mermaid\s*\n(.*?)\n```", re.DOTALL)
H2_RE = re.compile(r"^## (.+)$", re.MULTILINE)
META_RE = re.compile(r"^- \*\*(.+?):\*\*\s+(.+)$", re.MULTILINE)
SVG_META_RE = re.compile(
    r'<metadata id="synaptic-sea-architecture">(.*?)</metadata>', re.DOTALL
)
FLOWCHART_OPERATOR = (
    r"(?:<--+>|--+>|-{3,}|-\.+(?:->|-)|={2,}>|={3,}|~{3,}|[ox]?--+[ox])"
)
FLOWCHART_RELATION_RE = re.compile(FLOWCHART_OPERATOR)
FLOWCHART_EDGE_ID_RE = re.compile(
    rf"(?<!\S)[^\s@]+@\s*(?P<operator>{FLOWCHART_OPERATOR})"
)
STATE_TRANSITION_RE = re.compile(
    r"^\s*(?P<source>\[\*\]|[^\s:;]+)\s*"
    r"-->\s*(?P<target>\[\*\]|[^\s:;]+)"
    r"(?P<label>\s*:.*)?\s*$"
)
STATE_LABEL_RE = re.compile(
    r"^\s*:\s*(?P<event>[^\[\]/]+?)\s+\[(?P<guard>[^\]]+)\]"
    r"\s*/\s*(?P<action>.+?)\s*$"
)


@dataclass(frozen=True)
class DiagramSpec:
    filename: str
    expected_id: str
    family: str


@dataclass(frozen=True)
class ParsedDiagram:
    spec: DiagramSpec
    path: Path
    metadata: dict[str, str]
    mermaid_source: str
    source_sha256: str
    evidence_paths: tuple[str, ...]


DIAGRAM_SPECS = (
    DiagramSpec("01-c4-system-context.md", "ARCH-C4-CONTEXT", "flowchart"),
    DiagramSpec("02-c4-containers.md", "ARCH-C4-CONTAINERS", "flowchart"),
    DiagramSpec("03-gameplay-interaction-sequence.md", "ARCH-SEQ-INTERACTION", "sequence"),
    DiagramSpec("04-threat-ai-state-machine.md", "ARCH-STATE-THREAT-AI", "state"),
    DiagramSpec("05-runtime-component-dependencies.md", "ARCH-COMP-RUNTIME", "flowchart"),
)
SPEC_BY_NAME = {spec.filename: spec for spec in DIAGRAM_SPECS}


class ValidationError(RuntimeError):
    pass


def normalize_source(source: str) -> str:
    return source.replace("\r\n", "\n").replace("\r", "\n").strip() + "\n"


def source_hash(source: str) -> str:
    return hashlib.sha256(normalize_source(source).encode("utf-8")).hexdigest()


def sections(text: str) -> tuple[list[str], dict[str, str]]:
    matches = list(H2_RE.finditer(text))
    names = [match.group(1).strip() for match in matches]
    content: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        content[names[index]] = text[match.end():end].strip()
    return names, content


def parse_pipe_row(line: str) -> list[str]:
    if not line.strip().startswith("|") or not line.strip().endswith("|"):
        raise ValidationError("evidence table row must start and end with '|'")
    return [
        cell.strip().replace("\\|", "|")
        for cell in re.split(r"(?<!\\)\|", line.strip())[1:-1]
    ]


def parse_evidence(block: str, root: Path, rel: str) -> tuple[str, ...]:
    lines = [line for line in block.splitlines() if line.strip().startswith("|")]
    if len(lines) < 3 or parse_pipe_row(lines[0]) != EVIDENCE_COLUMNS:
        raise ValidationError(f"{rel}: evidence columns must be {EVIDENCE_COLUMNS}")
    separator = parse_pipe_row(lines[1])
    if len(separator) != 4 or not all(
        re.fullmatch(r":?-{3,}:?", cell) for cell in separator
    ):
        raise ValidationError(f"{rel}: invalid evidence table separator")
    paths: list[str] = []
    for line in lines[2:]:
        row = parse_pipe_row(line)
        if len(row) != 4:
            raise ValidationError(f"{rel}: evidence row must have four cells")
        path_text = row[1].strip("`")
        if row[3] not in BASIS:
            raise ValidationError(f"{rel}: invalid Basis {row[3]!r}")
        candidate = Path(path_text)
        if (
            not path_text
            or candidate.is_absolute()
            or "\\" in path_text
            or ".." in candidate.parts
        ):
            raise ValidationError(
                f"{rel}: evidence path must be a non-escaping "
                f"repository-relative POSIX path: {path_text!r}"
            )
        if not (root / candidate).exists():
            raise ValidationError(f"{rel}: evidence path does not exist: {path_text}")
        paths.append(path_text)
    if not paths:
        raise ValidationError(f"{rel}: evidence table has no data rows")
    return tuple(paths)


def mask_mermaid_label_text(line: str) -> str:
    masked = list(line)
    delimiters: list[str] = []
    quote = ""
    escaped = False
    in_pipe_label = False
    closing = {"[": "]", "(": ")", "{": "}"}
    for index, character in enumerate(line):
        if quote:
            masked[index] = " "
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = ""
            continue
        if in_pipe_label:
            masked[index] = " "
            if character == "|":
                in_pipe_label = False
            continue
        if character in {'"', "'"}:
            quote = character
            masked[index] = " "
            continue
        if character == "|" and not delimiters:
            in_pipe_label = True
            masked[index] = " "
            continue
        if character in closing:
            delimiters.append(closing[character])
            masked[index] = " "
            continue
        if delimiters:
            masked[index] = " "
            if character == delimiters[-1]:
                delimiters.pop()
    return "".join(masked)


def validate_flowchart_relationships(source: str, rel: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("%%"):
            continue
        semantic_line = mask_mermaid_label_text(line)
        relationships = list(FLOWCHART_RELATION_RE.finditer(semantic_line))
        if relationships and "&" in semantic_line:
            raise ValidationError(
                f"{rel}: flowchart relationship on Mermaid line {line_number} "
                "must not use grouped endpoints"
            )
        identified = {
            match.span("operator")
            for match in FLOWCHART_EDGE_ID_RE.finditer(semantic_line)
        }
        for relationship in relationships:
            if relationship.span() not in identified:
                raise ValidationError(
                    f"{rel}: flowchart relationship on Mermaid line {line_number} "
                    "requires a stable edge ID"
                )


def validate_state_transitions(source: str, rel: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("%%"):
            continue
        for statement in line.split(";"):
            transition = STATE_TRANSITION_RE.fullmatch(statement.strip())
            if not transition:
                if "-->" in statement:
                    raise ValidationError(
                        f"{rel}: cannot classify state transition on Mermaid line "
                        f"{line_number}"
                    )
                continue
            if "[*]" in (transition.group("source"), transition.group("target")):
                continue
            label = transition.group("label") or ""
            label_match = STATE_LABEL_RE.fullmatch(label)
            if not label_match or not all(
                label_match.group(part).strip()
                for part in ("event", "guard", "action")
            ):
                raise ValidationError(
                    f"{rel}: ordinary state transition on Mermaid line {line_number} "
                    "requires ': event [guard] / action' notation"
                )


def parse_diagram(path: Path, root: Path, spec: DiagramSpec) -> ParsedDiagram:
    rel = path.relative_to(root).as_posix()
    if not path.is_file():
        raise ValidationError(f"{rel}: missing diagram document")
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
    first = next((line for line in text.splitlines() if line.strip()), "")
    if (
        not first.startswith("# ")
        or first.startswith("## ")
        or len(re.findall(r"^# ", text, re.MULTILINE)) != 1
    ):
        raise ValidationError(f"{rel}: expected exactly one H1 as the first non-empty line")
    names, content = sections(text)
    if names != H2_EXPECTED:
        raise ValidationError(f"{rel}: H2 headings must equal {H2_EXPECTED}, got {names}")
    metadata_pairs = META_RE.findall(text[:text.index("## Purpose and conclusion")])
    if [key for key, _ in metadata_pairs] != META_KEYS:
        raise ValidationError(f"{rel}: metadata keys must equal {META_KEYS}")
    metadata = dict(metadata_pairs)
    if metadata["Diagram ID"] != spec.expected_id:
        raise ValidationError(f"{rel}: Diagram ID must be {spec.expected_id}")
    try:
        date.fromisoformat(metadata["Freshness date"])
    except ValueError as exc:
        raise ValidationError(f"{rel}: invalid Freshness date") from exc
    fences = MERMAID_RE.findall(text)
    if len(fences) != 1:
        raise ValidationError(
            f"{rel}: expected exactly one Mermaid fence, found {len(fences)}"
        )
    if len(MERMAID_RE.findall(content["Diagram"])) != 1:
        raise ValidationError(f"{rel}: Mermaid fence must be inside ## Diagram")
    source = normalize_source(fences[0])
    expected_prefix = {
        "flowchart": "flowchart ",
        "sequence": "sequenceDiagram",
        "state": "stateDiagram-v2",
    }[spec.family]
    if not source.startswith(expected_prefix):
        raise ValidationError(f"{rel}: expected {spec.family} Mermaid source")
    legend = content["Relationship legend"].lower()
    if spec.family == "flowchart":
        validate_flowchart_relationships(source, rel)
        if "classDef dataEdge" not in source or "solid" not in legend:
            raise ValidationError(
                f"{rel}: flowchart notation requires edge IDs, dataEdge class, "
                "and solid-edge legend"
            )
        if spec.expected_id == "ARCH-COMP-RUNTIME" and "classDef signalEdge" not in source:
            raise ValidationError(
                f"{rel}: component view requires signalEdge and dataEdge classes"
            )
    elif spec.family == "sequence":
        if (
            "->>" not in source
            or "-->>" not in source
            or "solid" not in legend
            or "dashed" not in legend
        ):
            raise ValidationError(
                f"{rel}: sequence notation requires solid calls and dashed signals/returns"
            )
    elif spec.family == "state":
        validate_state_transitions(source, rel)
        if "<<choice>>" not in source:
            raise ValidationError(
                f"{rel}: state notation requires a choice and labeled transitions"
            )
    for retired in sorted(PROHIBITED):
        if re.search(rf"\b{re.escape(retired)}\b", source):
            raise ValidationError(f"{rel}: prohibited current-architecture ID {retired}")
    evidence = parse_evidence(content["Evidence"], root, rel)
    return ParsedDiagram(spec, path, metadata, source, source_hash(source), evidence)


def validate_index(path: Path, root: Path) -> None:
    rel = path.relative_to(root).as_posix()
    text = path.read_text(encoding="utf-8")
    first = next((line for line in text.splitlines() if line.strip()), "")
    if (
        not first.startswith("# ")
        or first.startswith("## ")
        or len(re.findall(r"^# ", text, re.MULTILINE)) != 1
    ):
        raise ValidationError(f"{rel}: expected exactly one H1 as the first non-empty line")
    names, _content = sections(text)
    if names != README_H2:
        raise ValidationError(f"{rel}: H2 headings must equal {README_H2}, got {names}")
    if MERMAID_RE.search(text):
        raise ValidationError(f"{rel}: README must not contain a Mermaid fence")


def renderer_info(root: Path) -> tuple[str, Path, Path, Path]:
    tool = root / RENDERER_REL
    declared = json.loads((tool / "package.json").read_text(encoding="utf-8"))
    wanted = declared.get("devDependencies", {}).get("@mermaid-js/mermaid-cli")
    if wanted != "11.16.0":
        raise ValidationError(
            "tools/architecture/package.json: Mermaid CLI must be exact version 11.16.0"
        )
    installed_path = tool / "node_modules/@mermaid-js/mermaid-cli/package.json"
    if not installed_path.is_file():
        raise ValidationError(
            "tools/architecture: renderer not installed; "
            "run npm --prefix tools/architecture ci"
        )
    installed = json.loads(installed_path.read_text(encoding="utf-8"))
    if installed.get("version") != wanted:
        raise ValidationError(
            f"tools/architecture: installed renderer {installed.get('version')} != {wanted}"
        )
    bin_value = installed.get("bin", {})
    cli_rel = bin_value.get("mmdc") if isinstance(bin_value, dict) else bin_value
    cli = installed_path.parent / str(cli_rel)
    node = shutil.which("node")
    config = tool / "mermaid.config.json"
    if not node or not cli.is_file() or not config.is_file():
        raise ValidationError(
            "tools/architecture: node, Mermaid CLI entry, or config is missing"
        )
    return wanted, Path(node), cli, config


def render(diagram: ParsedDiagram, root: Path, temp: Path) -> Path:
    _version, node, cli, config = renderer_info(root)
    source_file = temp / f"{diagram.path.stem}.mmd"
    output_file = temp / f"{diagram.path.stem}.svg"
    source_file.write_text(diagram.mermaid_source, encoding="utf-8", newline="\n")
    command = [
        str(node),
        str(cli),
        "--input",
        str(source_file),
        "--output",
        str(output_file),
        "--configFile",
        str(config),
        "--width",
        "1600",
        "--height",
        "1200",
        "--backgroundColor",
        "transparent",
        "--svgId",
        diagram.spec.expected_id.lower(),
    ]
    result = subprocess.run(
        command, cwd=root, text=True, capture_output=True, check=False
    )
    if result.returncode != 0:
        raise ValidationError(
            f"{diagram.path.relative_to(root).as_posix()}: Mermaid render failed: "
            f"{result.stderr.strip()}"
        )
    if not output_file.is_file() or "<svg" not in output_file.read_text(encoding="utf-8"):
        raise ValidationError(
            f"{diagram.path.relative_to(root).as_posix()}: renderer produced no SVG"
        )
    return output_file


def metadata_payload(diagram: ParsedDiagram, version: str) -> str:
    return json.dumps(
        {
            "renderer": "@mermaid-js/mermaid-cli",
            "renderer_version": version,
            "source_sha256": diagram.source_sha256,
        },
        sort_keys=True,
        separators=(",", ":"),
    )


def inject_metadata(svg: str, diagram: ParsedDiagram, version: str) -> str:
    if SVG_META_RE.search(svg):
        raise ValidationError(
            f"{diagram.path.name}: renderer unexpectedly emitted reserved metadata id"
        )
    opening_end = svg.find(">", svg.find("<svg"))
    if opening_end < 0:
        raise ValidationError(f"{diagram.path.name}: malformed SVG root")
    tag = (
        '<metadata id="synaptic-sea-architecture">'
        f"{metadata_payload(diagram, version)}</metadata>"
    )
    return svg[:opening_end + 1] + tag + svg[opening_end + 1:]


def verify_export(path: Path, diagram: ParsedDiagram, version: str) -> None:
    if not path.is_file():
        raise ValidationError(f"{path.name}: missing committed export")
    match = SVG_META_RE.search(path.read_text(encoding="utf-8"))
    if not match:
        raise ValidationError(f"{path.name}: missing architecture metadata")
    payload = json.loads(match.group(1))
    expected = json.loads(metadata_payload(diagram, version))
    for key, value in expected.items():
        if payload.get(key) != value:
            raise ValidationError(
                f"{path.name}: stale {key}: {payload.get(key)!r} != {value!r}"
            )


def parse_all(root: Path) -> tuple[ParsedDiagram, ...]:
    arch = root / ARCH_REL
    validate_index(arch / "README.md", root)
    return tuple(
        parse_diagram(arch / spec.filename, root, spec) for spec in DIAGRAM_SPECS
    )


def render_all(
    root: Path, diagrams: Sequence[ParsedDiagram]
) -> tuple[Path, tuple[Path, ...]]:
    temp_dir = Path(tempfile.mkdtemp(prefix=".architecture-render-", dir=root / ARCH_REL))
    try:
        outputs = tuple(render(diagram, root, temp_dir) for diagram in diagrams)
        return temp_dir, outputs
    except Exception:
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise


def full_run(root: Path, update: bool) -> tuple[int, int, int]:
    diagrams = parse_all(root)
    version, _node, _cli, _config = renderer_info(root)
    temp_dir, rendered = render_all(root, diagrams)
    try:
        export_dir = root / ARCH_REL / "rendered"
        if update:
            export_dir.mkdir(parents=True, exist_ok=True)
            staged: list[tuple[Path, Path]] = []
            for diagram, source_svg in zip(diagrams, rendered):
                final_temp = temp_dir / f"final-{diagram.path.stem}.svg"
                final_temp.write_text(
                    inject_metadata(
                        source_svg.read_text(encoding="utf-8"), diagram, version
                    ),
                    encoding="utf-8",
                )
                staged.append(
                    (final_temp, export_dir / f"{diagram.path.stem}.svg")
                )
            for source, destination in staged:
                os.replace(source, destination)
        for diagram in diagrams:
            verify_export(
                export_dir / f"{diagram.path.stem}.svg", diagram, version
            )
        return (
            len(diagrams),
            len(diagrams),
            sum(len(diagram.evidence_paths) for diagram in diagrams),
        )
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def source_run(root: Path, names: Sequence[str]) -> tuple[int, int]:
    docs = 0
    diagrams: list[ParsedDiagram] = []
    for name in names:
        candidate = (root / name).resolve()
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise ValidationError(f"{name}: source path escapes repository") from exc
        docs += 1
        if candidate.name == "README.md":
            validate_index(candidate, root)
        else:
            spec = SPEC_BY_NAME.get(candidate.name)
            if not spec:
                raise ValidationError(f"{name}: not an approved architecture document")
            diagrams.append(parse_diagram(candidate, root, spec))
    if diagrams:
        temp_dir, _outputs = render_all(root, diagrams)
        shutil.rmtree(temp_dir, ignore_errors=True)
    return docs, sum(len(diagram.evidence_paths) for diagram in diagrams)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate Synaptic Sea architecture diagrams"
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--update", action="store_true")
    mode.add_argument("--check-source", nargs="+", metavar="PATH")
    parser.add_argument("--root", type=Path, default=ROOT_DEFAULT)
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        if args.check_source:
            documents, references = source_run(root, args.check_source)
            diagrams = sum(
                1 for name in args.check_source if Path(name).name != "README.md"
            )
            print(
                "ARCHITECTURE DIAGRAM SOURCE PASS "
                f"documents={documents} diagrams={diagrams} references={references}"
            )
        else:
            diagrams, exports, references = full_run(root, update=args.update)
            print(
                "ARCHITECTURE DIAGRAMS PASS "
                f"diagrams={diagrams} exports={exports} references={references}"
            )
        return 0
    except (OSError, ValueError, json.JSONDecodeError, ValidationError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
