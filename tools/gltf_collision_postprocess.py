#!/usr/bin/env python3
"""Post-process exported GLB to convert collision proxy nodes to Godot collision format.

The recipe system uses FocusedNine_ namespace for all objects. This script
renames collision proxy nodes (tagged with is_collision_proxy custom property)
to Collision_ format so Godot imports them as collision shapes.
"""

from __future__ import annotations

import json
import struct
import sys
from pathlib import Path


def process_glb(glb_path: Path) -> bool:
    """Rename collision proxy nodes in a GLB file. Returns True if modified."""
    data = glb_path.read_bytes()
    
    # Parse GLB header
    magic, version, length = struct.unpack_from('<III', data, 0)
    if magic != 0x46546C67:  # glTF
        return False
    
    # Find JSON chunk
    chunk_offset = 12
    json_data = None
    while chunk_offset < len(data):
        chunk_len, chunk_type = struct.unpack_from('<II', data, chunk_offset)
        if chunk_type == 0x4E4F534A:  # JSON
            json_data = bytearray(data[chunk_offset + 8:chunk_offset + 8 + chunk_len])
            break
        chunk_offset += 8 + chunk_len
    
    if json_data is None:
        return False
    
    # Parse JSON
    doc = json.loads(json_data)
    modified = False
    
    # Find and rename collision proxy nodes
    for node in doc.get('nodes', []):
        name = node.get('name', '')
        # Check for FocusedNine_*_collision_body pattern
        if '_collision_body' in name:
            # Extract asset_id from FocusedNine_<asset_id>_collision_body
            parts = name.split('_')
            # Find the collision_body suffix and extract the module id
            try:
                cb_idx = parts.index('collision')
                # Everything between FocusedNine and collision_body is the asset_id
                asset_id = '_'.join(parts[1:cb_idx])
                new_name = f'Collision_{asset_id}'
                node['name'] = new_name
                # Also rename the mesh if present
                if 'mesh' in node:
                    mesh_idx = node['mesh']
                    if mesh_idx < len(doc.get('meshes', [])):
                        doc['meshes'][mesh_idx]['name'] = f'{new_name}_Mesh'
                modified = True
            except (ValueError, IndexError):
                pass
    
    if not modified:
        return False
    
    # Re-encode JSON
    new_json = json.dumps(doc, separators=(',', ':')).encode('utf-8')
    
    # Pad to 4-byte alignment
    while len(new_json) % 4 != 0:
        new_json += b' '
    
    # Rebuild GLB
    # Header: magic + version + total_length
    # JSON chunk: chunk_len + chunk_type + data
    # BIN chunk (if present): original BIN
    
    # Find original BIN chunk
    chunk_offset = 12
    bin_data = None
    while chunk_offset < len(data):
        chunk_len, chunk_type = struct.unpack_from('<II', data, chunk_offset)
        if chunk_type == 0x004E4942:  # BIN
            bin_data = data[chunk_offset + 8:chunk_offset + 8 + chunk_len]
            break
        chunk_offset += 8 + chunk_len
    
    # Build new GLB
    json_chunk = struct.pack('<II', len(new_json), 0x4E4F534A) + new_json
    
    if bin_data is not None:
        # Pad BIN to 4-byte alignment
        bin_padded = bin_data
        while len(bin_padded) % 4 != 0:
            bin_padded += b'\x00'
        bin_chunk = struct.pack('<II', len(bin_padded), 0x004E4942) + bin_padded
    else:
        bin_chunk = b''
    
    total_length = 12 + len(json_chunk) + len(bin_chunk)
    header = struct.pack('<III', 0x46546C67, 2, total_length)
    
    glb_path.write_bytes(header + json_chunk + bin_chunk)
    return True


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: gltf_collision_postprocess.py <glb_file> [glb_file ...]")
        sys.exit(1)
    
    for path_str in sys.argv[1:]:
        path = Path(path_str)
        if not path.exists():
            print(f"SKIP (not found): {path}")
            continue
        if process_glb(path):
            print(f"PROCESSED: {path}")
        else:
            print(f"UNCHANGED: {path}")


if __name__ == "__main__":
    main()
