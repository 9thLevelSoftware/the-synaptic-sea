# Task 1 report: Gate 0 manifest integrity

## Status

DONE_WITH_CONCERNS

## Requirement summary

- Added the canonical `procgen-build-manifest-1` and `procgen-content-manifest-1` documents at the required paths, including source commit, generator version, content hash, Windows target, artifact hash/path, and all eight export schema versions.
- Added deterministic Python stdlib-only generation/checking. Content is an explicit sorted file list over the Rust embedded assets and authored procgen roots; each entry hashes normalized repository-relative path bytes, NUL, file bytes, NUL. `--check` never writes.
- Added JSON Schema and Rust `BuildManifest` parsing/validation without Godot dependencies, with focused valid, unknown-major, and malformed-hash tests.
- Added typed Godot validation result codes for schema, target, generator version, content manifest, and artifact checks; the native `ShipGenerator` path returns before any GDScript generation fallback when the manifest is invalid.
- Updated inventory source and regenerated `SYSTEM_INVENTORY.md` and `system_map.html` through the inventory builder.

## Files changed

- `data/procgen/manifests/content_manifest.json`
- `data/procgen/manifests/build/win64.json`
- `native/worldgen/schemas/procgen-build-manifest-1.schema.json`
- `native/worldgen/crates/derelict_core/src/manifest.rs`, `src/lib.rs`, `Cargo.toml`, `Cargo.lock`
- `native/worldgen/crates/derelict_core/tests/manifest_contract.rs`
- `scripts/validation/validate_procgen_build_manifest.py`, `procgen_manifest_smoke.gd`
- `scripts/procgen/procgen_manifest_validator.gd`, `ship_generator.gd`
- `docs/game/inventory/system_inventory.json`, generated `SYSTEM_INVENTORY.md`, `system_map.html`

## RED evidence

`cargo test --manifest-path native/worldgen/Cargo.toml -p derelict_core --test manifest_contract` initially failed because `src/manifest.rs` did not exist (`E0583: file not found for module manifest`).

## GREEN evidence

- `cargo test --manifest-path native/worldgen/Cargo.toml --workspace`: PASS (all workspace tests, including 3 manifest contract tests).
- `python scripts/validation/validate_procgen_build_manifest.py --check`: PASS; 47 content files, hash `e45770cf36ca296644b291a1c12d750281c8fcd3e520430b3ae2995d03ab14d2`.
- `python tools/build_system_inventory.py --check`: PASS; 192 systems verified.
- `git diff --check`: PASS.
- Focused Godot smoke was not run: no Godot executable was available in the Windows environment.

## Self-review and concerns

- The checked artifact exists and is hashed by the generator; runtime Godot validation remains unverified because the required binary is unavailable.
- The manifest targets Windows x86_64 by contract, so non-Windows native runs correctly return a target mismatch on the Rust path; this is intentional and should be covered by platform-specific smoke once Godot is available.
- Broader Gate 1 bundle/oracle cutover was not implemented.

## Commits

Focused implementation commit: `e732981f` (amended once to include the ignored canonical build manifest and this report).
