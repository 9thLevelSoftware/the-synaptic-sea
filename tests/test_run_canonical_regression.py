import pytest

from tools.run_canonical_regression import extract_bundle


def document(command_count=1, claimed_count=1):
    calls = "\n".join("run_clean 'case' 'PASS' true" for _ in range(command_count))
    return (
        "# Validation\n## Regression bundle\n\n```bash\nset -euo pipefail\n"
        + calls
        + "\necho 'SYNAPTIC_SEA REGRESSION PASS commands="
        + str(claimed_count)
        + " clean_output=true'\n```\n"
    )


def test_extract_preserves_exact_canonical_bytes():
    text = document()
    expected = text.split("```bash\n", 1)[1].split("\n```", 1)[0] + "\n"
    assert extract_bundle(text) == expected


def test_count_mismatch_is_not_a_pass():
    with pytest.raises(ValueError, match="count mismatch"):
        extract_bundle(document(command_count=2, claimed_count=1))


@pytest.mark.parametrize("text", ["", "## Regression bundle\n```bash\ntrue\n```\n"])
def test_missing_block_or_marker_fails_closed(text):
    with pytest.raises(ValueError):
        extract_bundle(text)


def test_duplicate_sections_fail_closed():
    with pytest.raises(ValueError, match="exactly one"):
        extract_bundle(document() + document())


def test_real_canonical_document_has_consistent_count():
    from pathlib import Path
    root = Path(__file__).resolve().parents[1]
    assert extract_bundle((root / "docs/game/06_validation_plan.md").read_text())
