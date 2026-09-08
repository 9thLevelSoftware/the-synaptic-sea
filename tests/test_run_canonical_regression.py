import pytest

from tools.run_canonical_regression import extract_bundle


_CANONICAL_LINE = "echo 'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true'"


def document(command_count=1, claimed_count=1):
    calls = "\n".join("run_clean 'case' 'PASS' true" for _ in range(command_count))
    marker = _CANONICAL_LINE.replace("commands=1", f"commands={claimed_count}")
    return (
        "# Validation\n## Regression bundle\n\n```bash\nset -euo pipefail\n"
        + calls
        + "\n"
        + marker
        + "\n```\n"
    )


def document_with_layout(layout):
    return document().replace(_CANONICAL_LINE, layout)


def test_extract_preserves_exact_canonical_bytes():
    text = document()
    expected = text.split("```bash\n", 1)[1].split("\n```", 1)[0] + "\n"
    assert extract_bundle(text) == expected


def test_count_mismatch_is_not_a_pass():
    with pytest.raises(ValueError, match="count mismatch"):
        extract_bundle(document(command_count=2, claimed_count=1))


@pytest.mark.parametrize(
    "marker_line",
    [
        "# echo 'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true'",
        ": 'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true'",
        "if false; then echo 'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true'; fi",
    ],
)
def test_non_executable_count_markers_fail_closed(marker_line):
    text = document().replace(
        "echo 'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true'",
        marker_line,
    )
    with pytest.raises(ValueError, match="executable"):
        extract_bundle(text)


def test_executable_final_echo_marker_is_accepted():
    assert extract_bundle(document()).endswith(
        "echo 'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true'\n"
    )


def test_count_marker_inside_uninvoked_function_fails_closed():
    text = document().replace(
        _CANONICAL_LINE,
        f"f() {{\n  {_CANONICAL_LINE}\n}}",
    )
    with pytest.raises(ValueError, match="executable"):
        extract_bundle(text)


@pytest.mark.parametrize(
    "marker_line",
    [
        "echo  'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true'",
        'echo "SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true"',
        "echo 'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true';",
        "echo 'SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true' extra",
    ],
)
def test_marker_requires_exact_standalone_echo_line(marker_line):
    with pytest.raises(ValueError, match="canonical|executable"):
        extract_bundle(document_with_layout(marker_line))


@pytest.mark.parametrize("indentation", [" ", "  ", "\t", " \t"])
def test_marker_allows_only_ordinary_indentation(indentation):
    script = extract_bundle(document_with_layout(indentation + _CANONICAL_LINE))
    assert script.splitlines()[-1] == indentation + _CANONICAL_LINE


def test_trailing_comments_after_marker_are_allowed():
    text = document_with_layout(_CANONICAL_LINE + "\n  # trailing comment")
    assert extract_bundle(text).endswith(
        _CANONICAL_LINE + "\n  # trailing comment\n"
    )


def test_marker_must_be_last_non_comment_non_blank_line():
    text = document_with_layout(_CANONICAL_LINE + "\ntrue")
    with pytest.raises(ValueError, match="last|canonical|executable"):
        extract_bundle(text)


def test_marker_text_cannot_appear_elsewhere():
    text = document_with_layout(
        _CANONICAL_LINE
        + "\n# duplicate text: SYNAPTIC_SEA REGRESSION PASS commands=1 clean_output=true"
    )
    with pytest.raises(ValueError, match="exactly one|canonical"):
        extract_bundle(text)


@pytest.mark.parametrize(
    "layout",
    [
        f"f() {{\n  {_CANONICAL_LINE}\n}}",
        f"function f {{\n  {_CANONICAL_LINE}\n}}",
        f"function f() {{\n  {_CANONICAL_LINE}\n}}",
        f"if false\nthen\n  {_CANONICAL_LINE}\nfi",
        f"while false\ndo\n  {_CANONICAL_LINE}\ndone",
        f"{{\n  {_CANONICAL_LINE}\n}}",
        f"(\n  {_CANONICAL_LINE}\n)",
        f"marker=\"$(\n  {_CANONICAL_LINE}\n)\"",
    ],
)
def test_count_marker_inside_unsupported_multiline_layout_fails_closed(layout):
    with pytest.raises(ValueError, match="executable|unsupported"):
        extract_bundle(document_with_layout(layout))


def test_objectdb_teardown_warning_is_exactly_allowlisted():
    from pathlib import Path

    root = Path(__file__).resolve().parents[1]
    document_text = (root / "docs/game/06_validation_plan.md").read_text()
    script = extract_bundle(document_text)
    warning = "WARNING: ObjectDB instances leaked at exit (run with --verbose for details)."

    assert warning in document_text
    assert 'BASELINE_WARNING="^WARNING: ObjectDB instances leaked at exit \\\\(run with --verbose for details\\\\)\\\\.$"' in script
    assert any(
        "FILTERED=" in line and "$BASELINE_WARNING" in line
        for line in script.splitlines()
    )


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
    document_text = (root / "docs/game/06_validation_plan.md").read_text()
    section = document_text.split("## Regression bundle\n", 1)[1]
    expected = section.split("```bash\n", 1)[1].split("\n```", 1)[0] + "\n"
    script = extract_bundle(document_text)

    assert script == expected
    assert sum(line.lstrip().startswith("run_clean ") for line in script.splitlines()) == 652
