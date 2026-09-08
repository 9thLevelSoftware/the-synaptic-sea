from __future__ import annotations

import json
import os
import struct
from pathlib import Path

import pytest

from tools.room_kit_contract import ROOT, glb_document, load_rows, validate_static


ROWS = load_rows()
ASSETS = Path(
    os.environ.get("ROOM_KIT_ASSET_ROOT", str(ROOT / "assets/imported/props/dressing"))
)


@pytest.mark.parametrize("row", ROWS, ids=[row["asset_id"] for row in ROWS])
def test_asset(row: dict) -> None:
    validate_static(ASSETS / f'{row["asset_id"]}.glb', row)



def replace_json_chunk(raw: bytes, document: dict) -> bytes:
    old_count = struct.unpack_from("<I", raw, 12)[0]
    payload = json.dumps(document, separators=(",", ":")).encode("utf-8")
    payload += b" " * ((-len(payload)) % 4)
    rest = raw[20 + old_count :]
    total = 20 + len(payload) + len(rest)
    return (
        struct.pack("<III", 0x46546C67, 2, total)
        + struct.pack("<II", len(payload), 0x4E4F534A)
        + payload
        + rest
    )



def test_transformed_scene_is_rejected(tmp_path) -> None:
    row = ROWS[0]
    source = ASSETS / f'{row["asset_id"]}.glb'
    document = glb_document(source)
    document["nodes"][0]["translation"] = [100, 0, 0]
    bad = tmp_path / "translated.glb"
    bad.write_bytes(replace_json_chunk(source.read_bytes(), document))

    with pytest.raises(AssertionError, match="identity|translation"):
        validate_static(bad, row)



def test_identity_transform_and_helper_rules_are_static_contracts() -> None:
    row = ROWS[0]
    source = ASSETS / f'{row["asset_id"]}.glb'
    document = glb_document(source)
    assert document["nodes"]
    assert all("POSITION" in primitive["attributes"] for mesh in document["meshes"] for primitive in mesh["primitives"])
