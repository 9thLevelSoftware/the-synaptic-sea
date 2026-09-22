"""Parent fault injection against the real multi-file stage publisher."""
import hashlib
import json
import tempfile
from pathlib import Path
from tools import structural_stage_publication as publication

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).parent
with tempfile.TemporaryDirectory(prefix="parent-publication-", dir=HERE / "tmp") as td:
    root = Path(td)
    incoming = root / "incoming"
    staging = root / "staging"
    incoming.mkdir()
    staging.mkdir()
    old_data = (ROOT / "assets/imported/structural/ship_structural_v0/floor_1x1/floor_1x1.glb").read_bytes()
    new_data = (HERE / "parent-fixtures/floor_1x1.glb").read_bytes()
    assert old_data != new_data
    pairs = []
    for role in ("intact", "damaged", "breached"):
        source = incoming / f"{role}.glb"
        target = staging / source.name
        source.write_bytes(new_data)
        target.write_bytes(old_data)
        pairs.append((source, target))
    before = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in staging.iterdir()}
    actual_replace = publication.os.replace
    new_sources = {source for source, _ in pairs}
    publications = 0
    def injected(source, destination):
        global publications
        if Path(source) in new_sources:
            publications += 1
            if publications == 2:
                raise OSError("parent injected failure on second new variant")
        return actual_replace(source, destination)
    publication.os.replace = injected
    try:
        try:
            publication.publish_staged_files(pairs)
        except publication.StagePublicationError as exc:
            assert "parent injected failure" in str(exc), str(exc)
        else:
            raise AssertionError("failed publication was accepted")
    finally:
        publication.os.replace = actual_replace
    after = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in staging.iterdir() if p.is_file()}
    assert before == after
    assert len(list(staging.iterdir())) == len(before)
    result = {"status": "pass", "variants": len(pairs), "failure_on_new_variant": publications,
              "previous_staging_restored": before == after, "recovery_cleanup_complete": True}
    (HERE / "parent-publication-rollback.json").write_text(json.dumps(result, indent=2))
    print("PARENT_PUBLICATION_ROLLBACK_PASS " + json.dumps(result, sort_keys=True))
