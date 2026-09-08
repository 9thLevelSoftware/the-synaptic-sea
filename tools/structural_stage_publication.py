"""Transactional publication of staged structural files.

The publisher uses same-filesystem renames for both recovery backups and new
files.  Existing targets are never deleted before a durable rename into the
hidden recovery directory, so a failed multi-file publication can restore the
complete previous set.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import tempfile
from typing import Sequence


class StagePublicationError(RuntimeError):
    """Raised when staged publication or its rollback cannot complete."""


def _absolute(path: Path | str) -> Path:
    return Path(path).expanduser().absolute()


def _lexists(path: Path) -> bool:
    return os.path.lexists(str(path))


def _validate_inputs(
    replacements: Sequence[tuple[Path, Path]],
    obsolete: Sequence[Path],
) -> tuple[list[tuple[Path, Path]], list[Path], Path]:
    try:
        normalized_replacements = [
            (_absolute(source), _absolute(target))
            for source, target in replacements
        ]
        normalized_obsolete = [_absolute(path) for path in obsolete]
    except (TypeError, ValueError) as exc:
        raise StagePublicationError(f"invalid publication inputs: {exc}") from exc

    if not normalized_replacements and not normalized_obsolete:
        raise StagePublicationError("publication has no replacements or obsolete files")

    targets = [target for _source, target in normalized_replacements]
    if len(set(targets)) != len(targets):
        raise StagePublicationError("publication contains duplicate targets")
    if len(set(normalized_obsolete)) != len(normalized_obsolete):
        raise StagePublicationError("publication contains duplicate obsolete paths")
    if set(targets) & set(normalized_obsolete):
        raise StagePublicationError("a publication target cannot also be obsolete")

    sources = [source for source, _target in normalized_replacements]
    if len(set(sources)) != len(sources):
        raise StagePublicationError("publication contains duplicate sources")
    if set(sources) & (set(targets) | set(normalized_obsolete)):
        raise StagePublicationError("publication sources overlap destination paths")

    destination_paths = targets + normalized_obsolete
    if not destination_paths:
        raise StagePublicationError("publication has no destination paths")
    destination_parents = {path.parent for path in destination_paths}
    for parent in destination_parents:
        if not parent.is_dir():
            raise StagePublicationError(f"publication destination directory is missing: {parent}")

    try:
        destination_device = os.stat(destination_paths[0].parent).st_dev
        for parent in destination_parents:
            if os.stat(parent).st_dev != destination_device:
                raise StagePublicationError(
                    "publication destinations must share one filesystem"
                )
        for source in sources:
            if not source.is_file():
                raise StagePublicationError(f"publication source is not a file: {source}")
            if os.stat(source).st_dev != destination_device:
                raise StagePublicationError(
                    f"publication source is on a different filesystem: {source}"
                )
    except OSError as exc:
        raise StagePublicationError(f"cannot validate publication paths: {exc}") from exc

    for path in destination_paths:
        if _lexists(path) and not (path.is_file() or path.is_symlink()):
            raise StagePublicationError(f"publication path is not a file: {path}")

    return normalized_replacements, normalized_obsolete, destination_paths[0].parent


def _manifest_payload(
    replacements: Sequence[tuple[Path, Path]],
    obsolete: Sequence[Path],
    backup_plan: Sequence[tuple[Path, Path]],
    moved: Sequence[tuple[Path, Path]],
    published: Sequence[Path],
    phase: str,
    errors: Sequence[str] = (),
) -> dict[str, object]:
    return {
        "version": 1,
        "phase": phase,
        "replacements": [
            {"source": str(source), "target": str(target)}
            for source, target in replacements
        ],
        "obsolete": [str(path) for path in obsolete],
        "backup_plan": [
            {"original": str(original), "backup": str(backup)}
            for original, backup in backup_plan
        ],
        "backups": [
            {"original": str(original), "backup": str(backup)}
            for original, backup in moved
        ],
        "published_targets": [str(path) for path in published],
        "errors": list(errors),
    }


def _write_manifest(path: Path, payload: dict[str, object]) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _remove_recovery_directory(path: Path) -> None:
    shutil.rmtree(path)


def publish_staged_files(
    replacements: Sequence[tuple[Path, Path]],
    obsolete: Sequence[Path] = (),
) -> None:
    """Publish staged files as one rollback-safe filesystem transaction.

    ``replacements`` contains temporary source files and their final targets.
    Existing targets and ``obsolete`` files are renamed into a hidden sibling
    recovery directory before any new source is renamed into place.  A
    publication failure removes only targets published by this call and
    restores every old file that was moved.  If restoration fails, the
    recovery directory and manifest are retained for manual recovery.
    """

    normalized_replacements, normalized_obsolete, recovery_parent = _validate_inputs(
        replacements, obsolete
    )
    all_old_paths = [target for _source, target in normalized_replacements] + normalized_obsolete

    recovery_dir: Path | None = None
    manifest: Path | None = None
    backup_plan: list[tuple[Path, Path]] = []
    backup_intents: list[tuple[Path, Path]] = []
    moved: list[tuple[Path, Path]] = []
    published: list[Path] = []

    try:
        recovery_dir = Path(
            tempfile.mkdtemp(prefix=".structural-stage-recovery-", dir=str(recovery_parent))
        )
        manifest = recovery_dir / "manifest.json"
        for index, original in enumerate(all_old_paths):
            backup_plan.append((original, recovery_dir / f"backup-{index:04d}-{original.name}"))
        _write_manifest(
            manifest,
            _manifest_payload(
                normalized_replacements,
                normalized_obsolete,
                backup_plan,
                moved,
                published,
                "prepared",
            ),
        )

        for original, backup in backup_plan:
            if not _lexists(original):
                continue
            # Record the intent before the rename.  An injected failure can
            # happen after os.replace has moved the old file but before this
            # loop can record a completed move.
            backup_intents.append((original, backup))
            _write_manifest(
                manifest,
                _manifest_payload(
                    normalized_replacements,
                    normalized_obsolete,
                    backup_plan,
                    backup_intents,
                    published,
                    "backing_up",
                ),
            )
            os.replace(str(original), str(backup))
            moved.append((original, backup))
            _write_manifest(
                manifest,
                _manifest_payload(
                    normalized_replacements,
                    normalized_obsolete,
                    backup_plan,
                    moved,
                    published,
                    "backing_up",
                ),
            )

        for source, target in normalized_replacements:
            # Every old target was moved (if present), so marking the target
            # before os.replace is safe even if an injected failure occurs after
            # the underlying rename has taken effect.
            published.append(target)
            os.replace(str(source), str(target))
            _write_manifest(
                manifest,
                _manifest_payload(
                    normalized_replacements,
                    normalized_obsolete,
                    backup_plan,
                    moved,
                    published,
                    "publishing",
                ),
            )

        _write_manifest(
            manifest,
            _manifest_payload(
                normalized_replacements,
                normalized_obsolete,
                backup_plan,
                moved,
                published,
                "complete",
            ),
        )
        # The publication is committed.  Recovery cleanup must not re-enter
        # the rollback path and delete the complete new variant set.
    except BaseException as failure:
        if recovery_dir is None or manifest is None:
            raise StagePublicationError(f"staged publication failed: {failure}") from failure

        rollback_errors: list[str] = []
        for target in reversed(published):
            try:
                if _lexists(target):
                    if not target.is_file() and not target.is_symlink():
                        raise OSError(f"published target is not removable: {target}")
                    target.unlink()
            except BaseException as rollback_failure:
                rollback_errors.append(f"remove {target}: {rollback_failure}")

        for original, backup in reversed(backup_intents):
            try:
                backup_exists = _lexists(backup)
                original_exists = _lexists(original)
                if backup_exists:
                    if original_exists:
                        raise OSError(
                            f"both original and backup exist for {original}"
                        )
                    os.replace(str(backup), str(original))
                elif not original_exists:
                    raise OSError(f"both original and backup are missing for {original}")
            except BaseException as rollback_failure:
                rollback_errors.append(f"restore {original}: {rollback_failure}")

        try:
            _write_manifest(
                manifest,
                _manifest_payload(
                    normalized_replacements,
                    normalized_obsolete,
                    backup_plan,
                    moved,
                    published,
                    "rollback_failed" if rollback_errors else "rolled_back",
                    [str(failure), *rollback_errors],
                ),
            )
        except BaseException as manifest_failure:
            rollback_errors.append(f"write recovery manifest: {manifest_failure}")

        if rollback_errors:
            raise StagePublicationError(
                f"staged publication failed: {failure}; rollback failed: "
                + "; ".join(rollback_errors)
                + f"; recovery directory: {recovery_dir}"
            ) from failure

        try:
            _remove_recovery_directory(recovery_dir)
        except BaseException as cleanup_failure:
            raise StagePublicationError(
                f"staged publication failed: {failure}; rollback completed but recovery "
                f"cleanup failed: {cleanup_failure}; recovery directory: {recovery_dir}"
            ) from failure
        raise StagePublicationError(f"staged publication failed: {failure}") from failure

    try:
        _remove_recovery_directory(recovery_dir)
    except BaseException as cleanup_failure:
        raise StagePublicationError(
            f"staged publication committed but recovery cleanup failed: {cleanup_failure}; "
            f"recovery directory: {recovery_dir}"
        ) from cleanup_failure
