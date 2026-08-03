#!/usr/bin/env python3
"""Validate recovered Blender structural sources against their source contracts."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any, Sequence

try:
    from tools.structural_source_contract import (
        STRUCTURAL_SOURCE_MODULE_IDS,
        StructuralSourceSpec,
        load_source_spec,
        source_output_paths,
    )
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools.structural_source_contract import (
        STRUCTURAL_SOURCE_MODULE_IDS,
        StructuralSourceSpec,
        load_source_spec,
        source_output_paths,
    )


_REPORT_PREFIX = "STRUCTURAL_SOURCE_REPORT "


def _coordinates_match(actual: object, expected: Sequence[float]) -> bool:
    if not isinstance(actual, (list, tuple)) or len(actual) != 3:
        return False
    try:
        return all(
            round(float(value), 6) == round(float(expected[index]), 6)
            for index, value in enumerate(actual)
        )
    except (TypeError, ValueError, OverflowError):
        return False


def _list_value_matches(actual: object, expected: Sequence[object]) -> bool:
    return isinstance(actual, (list, tuple)) and list(actual) == list(expected)


def validate_report(spec: StructuralSourceSpec, report: dict[str, Any]) -> list[str]:
    """Return deterministic contract diagnostics for one inspector report."""

    module_id = spec.module_id
    errors: list[str] = []
    expected_root_name = f"ModuleRoot_{module_id}"

    if not isinstance(report, dict):
        errors.append(f"source inspector report is not an object: {module_id}")
        return sorted(errors)

    if report.get("module_id") != module_id:
        errors.append(f"source report module_id does not match contract: {module_id}")
    if report.get("root_name") != expected_root_name:
        errors.append(f"source root name does not match contract: {module_id}")
    if report.get("root_identity") is not True:
        errors.append(f"source root transform is not identity: {module_id}")

    expected_helpers = sorted(
        [
            "Origin",
            "Anchor_FloorCenter",
            "CollisionProxy",
            *(socket.anchor_name for socket in spec.sockets),
        ]
    )
    raw_helper_names = report.get("helper_names")
    if not isinstance(raw_helper_names, list) or not all(
        isinstance(name, str) for name in raw_helper_names
    ):
        errors.append(f"source helper names are not a string list: {module_id}")
        helper_names: list[str] = []
    else:
        helper_names = raw_helper_names

    expected_helper_set = set(expected_helpers)
    actual_helper_set = set(helper_names)
    for name in sorted(expected_helper_set - actual_helper_set):
        errors.append(f"missing required helper {name}: {module_id}")
    for name in sorted(actual_helper_set - expected_helper_set):
        errors.append(f"unexpected source helper {name}: {module_id}")
    if len(helper_names) != len(actual_helper_set):
        errors.append(f"duplicate source helper names: {module_id}")

    raw_collision = report.get("collision")
    collision = raw_collision if isinstance(raw_collision, dict) else {}
    if not isinstance(raw_collision, dict):
        errors.append(f"source collision report is not an object: {module_id}")
    if collision.get("proxy_shape") != spec.collision_proxy_shape:
        errors.append(f"collision proxy shape does not match contract: {module_id}")
    if collision.get("nav_blocker") is not spec.nav_blocker:
        errors.append(f"collision nav_blocker does not match contract: {module_id}")

    raw_socket_records = report.get("socket_records")
    if not isinstance(raw_socket_records, list):
        errors.append(f"source socket records are not a list: {module_id}")
        socket_records: list[dict[str, Any]] = []
    else:
        socket_records = [
            record for record in raw_socket_records if isinstance(record, dict)
        ]
        if len(socket_records) != len(raw_socket_records):
            errors.append(f"source socket record is not an object: {module_id}")

    records_by_id: dict[str, dict[str, Any]] = {}
    for record in socket_records:
        socket_id = record.get("socket_id")
        if not isinstance(socket_id, str) or not socket_id:
            errors.append(f"source socket record has no socket_id: {module_id}")
            continue
        if socket_id in records_by_id:
            errors.append(f"duplicate socket record {socket_id}: {module_id}")
            continue
        records_by_id[socket_id] = record

    expected_socket_ids = {socket.socket_id for socket in spec.sockets}
    for socket in spec.sockets:
        if socket.socket_id not in records_by_id:
            errors.append(f"missing socket record {socket.socket_id}: {module_id}")
    for socket_id in sorted(set(records_by_id) - expected_socket_ids):
        errors.append(f"unexpected socket record {socket_id}: {module_id}")

    for socket in spec.sockets:
        record = records_by_id.get(socket.socket_id)
        if record is None:
            continue
        if record.get("name") != socket.anchor_name:
            errors.append(f"socket anchor name does not match {socket.socket_id}: {module_id}")
        if record.get("kind") != socket.kind:
            errors.append(f"socket kind does not match {socket.socket_id}: {module_id}")
        if not _list_value_matches(record.get("compatible_kinds"), socket.compatible_kinds):
            errors.append(
                f"socket compatible_kinds does not match {socket.socket_id}: {module_id}"
            )
        if not _coordinates_match(record.get("position_contract_y_up"), socket.position_y_up):
            errors.append(
                f"socket contract position does not match {socket.socket_id}: {module_id}"
            )
        if not _coordinates_match(record.get("location_z_up"), socket.position_z_up):
            errors.append(
                f"socket Blender location does not match {socket.socket_id}: {module_id}"
            )

    return sorted(errors)


def _validate_source_record(
    spec: StructuralSourceSpec, source_record: object
) -> list[str]:
    """Return provenance diagnostics for one recovered source record."""

    module_id = spec.module_id
    if not isinstance(source_record, dict):
        return [f"source record is not an object: {module_id}"]

    errors: list[str] = []
    if source_record.get("document_kind") != "structural_blender_source":
        errors.append(f"source record document_kind does not match contract: {module_id}")
    if source_record.get("schema_version") != "1.0.0":
        errors.append(f"source record schema_version does not match contract: {module_id}")
    if source_record.get("module_id") != module_id:
        errors.append(f"source record module_id does not match contract: {module_id}")

    contract = source_record.get("contract")
    if not isinstance(contract, dict) or contract.get("sha256") != spec.contract_sha256:
        errors.append(f"source record contract.sha256 does not match contract: {module_id}")

    source_glb = source_record.get("source_glb")
    if not isinstance(source_glb, dict) or source_glb.get("sha256") != spec.source_glb_sha256:
        errors.append(
            f"source record source_glb.sha256 does not match contract: {module_id}"
        )

    return sorted(errors)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project-root",
        required=True,
        type=Path,
        help="repository root containing structural contracts and imported GLBs",
    )
    parser.add_argument(
        "--source-root",
        required=True,
        type=Path,
        help="directory containing recovered module .blend files",
    )
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument(
        "--module",
        action="append",
        metavar="MODULE_ID",
        help="validate one module; repeat for multiple modules",
    )
    selection.add_argument(
        "--all",
        action="store_true",
        help="validate all allowlisted structural source modules",
    )
    parser.add_argument(
        "--blender",
        default=os.environ.get("BLENDER", "blender"),
        help="Blender executable (default: BLENDER environment variable or blender)",
    )
    return parser


def _selected_module_ids(args: argparse.Namespace) -> tuple[str, ...]:
    if args.all:
        return STRUCTURAL_SOURCE_MODULE_IDS
    return tuple(args.module)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = build_parser()
    args = parser.parse_args(argv)
    module_ids = _selected_module_ids(args)
    invalid = [
        module_id
        for module_id in module_ids
        if module_id not in STRUCTURAL_SOURCE_MODULE_IDS
    ]
    if invalid:
        parser.error(
            "unsupported structural source module(s): "
            + ", ".join(repr(module_id) for module_id in invalid)
        )
    return args


def _parse_report(stdout: str, module_id: str) -> tuple[dict[str, Any] | None, str | None]:
    report_lines = [line for line in stdout.splitlines() if line.startswith(_REPORT_PREFIX)]
    if len(report_lines) != 1:
        return None, f"inspector did not emit exactly one report: {module_id}"
    try:
        report = json.loads(report_lines[0][len(_REPORT_PREFIX) :])
    except json.JSONDecodeError as exc:
        return None, f"inspector report is invalid JSON for {module_id}: {exc.msg}"
    if not isinstance(report, dict):
        return None, f"inspector report is not an object: {module_id}"
    return report, None


def _run_inspector(
    blender: str,
    inspector_path: Path,
    project_root: Path,
    module_id: str,
    blend_path: Path,
) -> tuple[dict[str, Any] | None, str | None]:
    command = [
        blender,
        "--background",
        "--factory-startup",
        str(blend_path),
        "--python",
        str(inspector_path),
        "--",
        "--project-root",
        str(project_root),
        "--module",
        module_id,
    ]
    try:
        completed = subprocess.run(
            command,
            cwd=str(project_root),
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as exc:
        return None, f"cannot invoke Blender for {module_id}: {exc}"

    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        if detail:
            return None, f"Blender inspector failed for {module_id}: {detail}"
        return None, f"Blender inspector failed for {module_id}: exit {completed.returncode}"
    return _parse_report(completed.stdout, module_id)


def validate_sources(args: argparse.Namespace) -> list[str]:
    """Run the Blender inspector and contract checks for selected modules."""

    project_root = args.project_root.expanduser().resolve()
    source_root = args.source_root.expanduser()
    inspector_path = Path(__file__).resolve().with_name("inspect_structural_sources.py")
    errors: list[str] = []

    for module_id in _selected_module_ids(args):
        try:
            spec = load_source_spec(project_root, module_id)
            blend_path, record_path = source_output_paths(source_root, module_id)
        except (OSError, ValueError) as exc:
            errors.append(f"{module_id}: {exc}")
            continue

        blend_path = blend_path.expanduser().resolve()
        if not blend_path.is_file():
            errors.append(f"missing recovered Blender source: {blend_path}")
            continue

        report, inspector_error = _run_inspector(
            args.blender,
            inspector_path,
            project_root,
            module_id,
            blend_path,
        )
        if inspector_error:
            errors.append(inspector_error)
            continue
        errors.extend(validate_report(spec, report or {}))

        try:
            source_record = json.loads(record_path.read_text(encoding="utf-8"))
        except OSError as exc:
            errors.append(f"cannot read source record for {module_id}: {exc}")
            continue
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            errors.append(f"source record is invalid JSON for {module_id}: {exc}")
            continue
        errors.extend(_validate_source_record(spec, source_record))

    return errors


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    errors = validate_sources(args)
    if errors:
        for error in sorted(errors):
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    module_count = len(_selected_module_ids(args))
    print(f"STRUCTURAL_SOURCE_VALIDATION PASS modules={module_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
