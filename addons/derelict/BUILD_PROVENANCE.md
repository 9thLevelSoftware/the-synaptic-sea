# Derelict GDExtension v5 build provenance

## Source

- Repository: https://github.com/9thLevelSoftware/worldgen
- Reviewed source commit: `74d40b0d52d6bf744cef414cc6910378f83fb08a`
- Merged by PR: https://github.com/9thLevelSoftware/worldgen/pull/16
- Merged `main` commit: `554dbe9cfb7eecd3d639f32aad9c28219303a8f0`
- Source tree (identical for reviewed and merged commits): `ec710d7b6d4c870cc7d5627f35ad4eeaaf228910`
- Generator contract: `GENERATOR_VERSION = 5`

## Installed artifacts

| Platform | Repository path | Architecture | Bytes | SHA-256 | Build |
| --- | --- | --- | ---: | --- | --- |
| macOS | `addons/derelict/bin/macos/libderelict_godot.dylib` | arm64 | 6,207,440 | `265a675a261d85c891251239c7bd34f82f4c4cbe111aefa1607bce3233271e10` | `cargo build --release -p derelict_godot` at reviewed source commit |
| Windows | `addons/derelict/bin/win64/derelict_godot.dll` | PE32+ x86-64 | 6,746,112 | `de2dde8842a152054005c868689d38d88118e654b66b002ef7f980ec2b83a8fb` | `scripts/build_windows.ps1` in GitHub Actions run below |

Windows build/runtime evidence:

- Run: https://github.com/9thLevelSoftware/worldgen/actions/runs/33917545171
- Artifact ID: `9953828263`
- Artifact: `derelict-godot-windows-v5-b053f595b000b4beb52ded6c44e2318217fa1b3e`
- Temporary build head: `b053f595b000b4beb52ded6c44e2318217fa1b3e`
- Difference from reviewed source: only the disposable workflow and native smoke script
- Runtime marker: `WINDOWS GDEXTENSION SMOKE PASS version=5 rooms=30`
- Unexpected Godot diagnostics: 0

## Replaced v2 artifacts

| Platform | Bytes | SHA-256 |
| --- | ---: | --- |
| macOS | 3,995,840 | `a17fbcaf4834d51ac8ddc05becbe0a762d07ab83e043f215532eccb40040cec1` |
| Windows | 5,279,744 | `3279db6338e7af6b54cb4e8c8886d39bdffec73549a25149a05a87d9ebdb8798` |

## Verification

Source commit verification:

- `cargo fmt --all -- --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace`: 129 passed
- `cargo test -p derelict_godot --test export_golden`: 6 passed
- `cargo run --release -p derelict_cli -- --stress`: 1,800 cases, 0 failures
- Disposable door-entity bijection probe: 1,798 generated ships checked; 2 unrelated placement-generation skips; 0 bijection failures

Synaptic Sea macOS focused runtime verification with Godot 4.7.1:

- `derelict_arc_smoke.gd`: full board/tick/save/reload/home/revisit lifecycle passed
- `worldgen_wired_travel_smoke.gd`: 9 cases passed
- `world_persist_restore_smoke.gd`: passed
- `world_save_anywhere_smoke.gd`: passed
- Unexpected Godot diagnostics in these focused runs: 0
