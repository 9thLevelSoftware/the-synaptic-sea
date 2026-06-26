#!/usr/bin/env python3
"""Task 15 documentation/manifest currency validators.

Pure host-side validators for docs, JSON, and the Hermes Kanban SQLite board.
They intentionally do not boot Godot because Task 15 validates source-of-truth
currency rather than gameplay scene behavior.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

ROOT_DEFAULT = Path("/Users/christopherwilloughby/the-synaptic-sea")
BOARD_DEFAULT = "synaptic-sea-e2e-systems"
BOARD_DB_DEFAULT = Path.home() / ".hermes" / "kanban" / "boards" / BOARD_DEFAULT / "kanban.db"

REQUIRED_TASK_IDS = [
    "t_0228a857", "t_34d0483b", "t_d569eba2", "t_be88f847", "t_af66b721",
    "t_67389b76", "t_cbe56420", "t_290ec958", "t_02146c59", "t_7a6849cb",
    "t_9e328a9f", "t_2d267b26", "t_4faf58cf", "t_3b217838", "t_12bf9f4a", "t_c7ac4d08",
]
DOC_REQ_IDS = [f"REQ-DOC-{i:03d}" for i in range(1, 9)]
REQUIRED_ADR_PATHS = [
    "docs/game/adr/0034-survival-vitals-architecture.md",
    "docs/game/adr/0034-food-cooking-spoilage-architecture.md",
    "docs/game/adr/0038-crafting-materials-stations-architecture.md",
    "docs/game/adr/0037-loot-ecosystem-rarity-container-architecture.md",
    "docs/game/adr/0036-consumable-effect-pipeline-architecture.md",
    "docs/game/adr/0037-combat-threat-architecture.md",
    "docs/game/adr/0035-ship-systems-sustenance-expansion-architecture.md",
    "docs/game/adr/0033-player-progression-meta-architecture.md",
    "docs/game/adr/0033-ui-ux-accessibility-architecture.md",
    "docs/game/adr/0029-audio-music-spatial-architecture.md",
    "docs/game/adr/0031-multi-slot-save-architecture.md",
    "docs/game/adr/0032-migration-permadeath-cloud-manifest.md",
    "docs/game/adr/0029-procedural-generation-expansion-architecture.md",
    "docs/game/adr/0029-release-distribution-architecture.md",
    "docs/game/adr/0030-achievement-catalog-and-triggers.md",
    "docs/game/adr/0031-localization-catalog-and-routing.md",
    "docs/game/adr/0039-cross-system-integration-audit-architecture.md",
    "docs/game/adr/0040-systems-map-task-graph-currency.md",
]
STALE_IN_SCOPE_PHRASES = [
    "No enemies, no AI, no weapons, no damage types",
    "Zero audio infrastructure",
    "No main menu, pause menu, or settings",
    "No hunger/thirst/temperature/radiation/sanity vitals",
    "No crafting — no stations",
    "No loot depth — no rarity tiers",
    "Multi-slot saves | ❌ MISSING",
    "Template C (stacked) | 📋 SPEC'D",
    "Main menu | ❌ MISSING",
    "Pause menu | ❌ MISSING",
    "Settings menu | ❌ MISSING",
    "Meta-progression (cross-run) | ❌ MISSING",
    "Skill tree (per-run) | ❌ MISSING",
    "Controller glyphs | ❌ MISSING",
]

@dataclass
class ValidationResult:
    ok: bool
    checked: int = 0
    errors: list[str] | None = None
    details: dict | None = None

    def require_ok(self) -> None:
        if not self.ok:
            raise SystemExit("\n".join(self.errors or ["validation failed"]))


def root_path() -> Path:
    return Path(os.environ.get("ROOT", str(ROOT_DEFAULT))).resolve()


def board_db_path(manifest: dict | None = None) -> Path:
    env = os.environ.get("KANBAN_DB")
    if env:
        return Path(env).expanduser().resolve()
    if manifest:
        path = manifest.get("board_currency", {}).get("board_db_path")
        if path:
            return Path(path).expanduser().resolve()
    return BOARD_DB_DEFAULT


def read_text(root: Path, rel: str) -> str:
    path = root / rel
    return path.read_text(encoding="utf-8")


def load_json(root: Path, rel: str) -> dict:
    return json.loads((root / rel).read_text(encoding="utf-8"))


def file_exists(root: Path, rel: str) -> bool:
    p = Path(rel)
    return p.exists() if p.is_absolute() else (root / p).exists()


def matrix_rows(root: Path) -> list[dict]:
    data = load_json(root, "data/integration/cross_system_integration_matrix.json")
    return list(data.get("systems", []))


class SystemsMapCurrencyValidator:
    def validate(self, root: Path) -> ValidationResult:
        text = read_text(root, "docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md")
        rows = matrix_rows(root)
        errors: list[str] = []
        checked = 0
        for tid in REQUIRED_TASK_IDS:
            checked += 1
            if tid not in text:
                errors.append(f"systems map missing task id {tid}")
        for row in rows:
            if row.get("package_id") == "kickoff":
                continue
            task_id = row.get("task_id", "")
            checked += 1
            if task_id and task_id not in text:
                errors.append(f"systems map missing matrix task {task_id}")
            evidence = []
            for field in ("code_files", "data_files", "docs_files", "smoke_files", "smoke_markers"):
                for value in row.get(field, []) or []:
                    value = str(value)
                    if value and value in text:
                        evidence.append(value)
            if len(evidence) < 3:
                errors.append(f"systems map has weak evidence for {task_id or row.get('package_id')}: found {len(evidence)} cited items")
        for phrase in STALE_IN_SCOPE_PHRASES:
            checked += 1
            if phrase in text:
                errors.append(f"stale in-scope phrase remains: {phrase}")
        for required_section in ("ADR Currency Index", "Board and manifest currency", "Completed package evidence ledger"):
            checked += 1
            if required_section not in text:
                errors.append(f"systems map missing section {required_section}")
        return ValidationResult(not errors, checked, errors, {"packages": len(rows), "stale_phrases": len(STALE_IN_SCOPE_PHRASES)})


class AdrIndexValidator:
    def validate(self, root: Path) -> ValidationResult:
        index_text = read_text(root, "docs/game/adr/README.md")
        systems_text = read_text(root, "docs/SYNAPTIC_SEA_COMPLETE_SYSTEMS_MAP.md")
        errors: list[str] = []
        checked = 0
        for rel in REQUIRED_ADR_PATHS:
            checked += 1
            if not file_exists(root, rel):
                errors.append(f"ADR file missing: {rel}")
            if rel not in index_text:
                errors.append(f"ADR index missing path: {rel}")
            if rel not in systems_text:
                errors.append(f"systems map ADR index missing path: {rel}")
        if "Task 15" not in index_text or "Artifact reference" not in index_text:
            errors.append("ADR index missing Task 15 currency header or artifact references")
        return ValidationResult(not errors, checked, errors, {"adrs": checked})


class RequirementTraceValidator:
    def validate(self, root: Path) -> ValidationResult:
        req_text = read_text(root, "docs/game/05_requirements.md")
        validation_text = read_text(root, "docs/game/06_validation_plan.md")
        errors: list[str] = []
        checked = 0
        for rid in DOC_REQ_IDS:
            checked += 1
            heading = f"## {rid}:"
            if heading not in req_text:
                errors.append(f"missing requirement heading {heading}")
                continue
            # Check the requirement block until next heading.
            start = req_text.index(heading)
            nxt = req_text.find("\n## ", start + 1)
            block = req_text[start:nxt if nxt != -1 else len(req_text)]
            if "Status: Validated" not in block:
                errors.append(f"{rid} is not Validated")
            if "systems_map_task_graph_currency.md" not in block:
                errors.append(f"{rid} missing feature spec source")
        for row in matrix_rows(root):
            for rid in row.get("requirements", []) or []:
                checked += 1
                if f"## {rid}:" not in req_text:
                    errors.append(f"matrix requirement missing from requirements doc: {rid}")
        for marker in ("SYSTEMS MAP CURRENCY PASS", "REQUIREMENT TRACE PASS", "KANBAN MANIFEST PASS"):
            checked += 1
            if marker not in validation_text:
                errors.append(f"Task 15 marker missing from validation plan: {marker}")
        adr_result = AdrIndexValidator().validate(root)
        checked += adr_result.checked
        if not adr_result.ok:
            errors.extend(adr_result.errors or [])
        return ValidationResult(not errors, checked, errors, {"doc_requirements": len(DOC_REQ_IDS), "adrs": adr_result.checked})


class KanbanManifestValidator:
    def validate(self, root: Path) -> ValidationResult:
        manifest = load_json(root, ".omh/kanban/synaptic-sea-e2e-systems-task-graph.json")
        errors: list[str] = []
        checked = 0
        if manifest.get("board") != BOARD_DEFAULT:
            errors.append(f"manifest board is {manifest.get('board')!r}, expected {BOARD_DEFAULT!r}")
        tasks = manifest.get("tasks", [])
        manifest_ids = [t.get("task_id") for t in tasks]
        if len(manifest_ids) != len(set(manifest_ids)):
            errors.append("manifest has duplicate task ids")
        db_path = board_db_path(manifest)
        if not db_path.exists():
            errors.append(f"kanban db missing: {db_path}")
            return ValidationResult(False, checked, errors)
        con = sqlite3.connect(db_path)
        db_tasks = {row[0]: {"status": row[1], "title": row[2]} for row in con.execute("select id,status,title from tasks")}
        db_links = {(row[0], row[1]) for row in con.execute("select parent_id, child_id from task_links")}
        db_status_counts = {row[0]: row[1] for row in con.execute("select status,count(*) from tasks group by status")}
        db_task_count = len(db_tasks)
        db_link_count = len(db_links)
        con.close()
        for tid in manifest_ids:
            checked += 1
            if tid not in db_tasks:
                errors.append(f"manifest task id not found in board db: {tid}")
        declared_edges = set()
        for task in tasks:
            child = task.get("task_id")
            for parent in task.get("parents", []) or []:
                edge = (parent, child)
                declared_edges.add(edge)
                checked += 1
                if edge not in db_links:
                    errors.append(f"manifest edge missing in board db: {parent}->{child}")
        currency = manifest.get("board_currency", {})
        checked += 3
        if currency.get("task_count") != db_task_count:
            errors.append(f"manifest task_count {currency.get('task_count')} != live {db_task_count}")
        if currency.get("link_count") != db_link_count:
            errors.append(f"manifest link_count {currency.get('link_count')} != live {db_link_count}")
        allowed_status_counts = [currency.get("status_counts")]
        allowed_status_counts.extend(currency.get("allowed_status_counts", []) or [])
        if db_status_counts not in allowed_status_counts:
            errors.append(f"manifest status_counts {currency.get('status_counts')} / allowed {allowed_status_counts} != live {db_status_counts}")
        for edge in currency.get("additional_links", []) or []:
            checked += 1
            tup = tuple(edge)
            if tup not in db_links:
                errors.append(f"additional live edge missing in board db: {edge}")
        return ValidationResult(not errors, checked, errors, {"tasks": db_task_count, "links": db_link_count, "status_counts": db_status_counts})


def run_systems_map(root: Path) -> str:
    result = SystemsMapCurrencyValidator().validate(root)
    result.require_ok()
    return f"SYSTEMS MAP CURRENCY PASS packages={result.details['packages']} checks={result.checked} stale_phrases=0"


def run_requirement_trace(root: Path) -> str:
    result = RequirementTraceValidator().validate(root)
    result.require_ok()
    return f"REQUIREMENT TRACE PASS doc_requirements={result.details['doc_requirements']} adrs={result.details['adrs']} checks={result.checked}"


def run_kanban_manifest(root: Path) -> str:
    result = KanbanManifestValidator().validate(root)
    result.require_ok()
    details = result.details or {}
    return f"KANBAN MANIFEST PASS board={BOARD_DEFAULT} tasks={details.get('tasks')} links={details.get('links')} statuses={json.dumps(details.get('status_counts', {}), sort_keys=True)}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Task 15 doc/manifest currency validators")
    parser.add_argument("target", choices=["systems-map", "requirement-trace", "kanban-manifest", "all"])
    args = parser.parse_args(argv)
    root = root_path()
    outputs: list[str] = []
    if args.target in ("systems-map", "all"):
        outputs.append(run_systems_map(root))
    if args.target in ("requirement-trace", "all"):
        outputs.append(run_requirement_trace(root))
    if args.target in ("kanban-manifest", "all"):
        outputs.append(run_kanban_manifest(root))
    for line in outputs:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
