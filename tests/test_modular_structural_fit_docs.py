"""Keep published modular-fit guidance aligned to the machine policy."""
from pathlib import Path
import pytest

ROOT = Path(__file__).resolve().parents[1]
DOCS = [
    "docs/game/features/modular_structural_fit.md",
    "docs/game/features/blender_room_kit_v2.md",
    "docs/game/features/blender_artist_workflow.md",
    "docs/game/features/blender_structural_source_pipeline.md",
    "docs/game/adr/0061-blender-room-kit-v2.md",
]

@pytest.mark.parametrize("relative", DOCS)
def test_guidance_does_not_invent_a_second_dimensional_policy(relative):
    text = (ROOT / relative).read_text()
    assert "structural_visual_dimensions.v1.json" in text
    assert "HOLD" in text
    for invented_value in ("`0.30`", "`0.05`", "`0.8 × 0.8`"):
        assert invented_value not in text, (relative, invented_value)


def test_canonical_runbook_names_the_actual_cli_and_profile_limit():
    text = (ROOT / DOCS[0]).read_text()
    for token in ("--python-exit-code 1", "--glb", "--report", "terminal_mating_band_m", "footprint_cells", "ramp_up_1x2"):
        assert token in text
    assert "--json" not in text
    for module in ("floor_1x1", "floor_2x1", "corridor_floor_1x1", "corridor_floor_1x2", "wall_straight_1x1", "doorway_frame_open_1x1", "pillar_support_1x1"):
        assert module in text
