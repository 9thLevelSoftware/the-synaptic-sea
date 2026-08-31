from pathlib import Path

import pytest

from tools.meshy_asset_contract import load_contract, render_prompt_packet

FIXTURES = Path(__file__).parent / "fixtures/meshy_asset_contract"


def test_valid_contract_renders_deterministic_prompt_packet() -> None:
    contract = load_contract(FIXTURES / "valid_loot_container.json")
    first = render_prompt_packet(contract)
    second = render_prompt_packet(contract)
    assert first == second
    assert first["asset_id"] == "loot_container_derelict_v1"
    assert first["geometry_request"]["should_texture"] is False
    assert first["reference_prompt"].endswith(
        "No environment, no floor, no cast shadow, no readable text, no logo, "
        "no floating parts, no duplicate components, no dramatic perspective, "
        "no depth of field, no baked lighting."
    )


@pytest.mark.parametrize(
    ("fixture", "message"),
    [
        ("invalid_structural_meshy.json", "structural geometry cannot use Meshy"),
        ("invalid_independent_states.json", "alternate states must derive from one master"),
        ("invalid_rigging_target.json", "Meshy rigging is limited to humanoid bipeds"),
        ("invalid_reference_rights.json", "reference rights must be explicit"),
    ],
)
def test_invalid_contracts_fail_closed(fixture: str, message: str) -> None:
    with pytest.raises(ValueError, match=message):
        load_contract(FIXTURES / fixture)
