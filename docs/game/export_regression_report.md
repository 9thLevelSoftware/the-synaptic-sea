# Export Regression Report — Gate 5 RC Kickoff

## Run metadata

- Date (UTC): 2026-06-20T02:54:40Z
- Engine: Godot 4.6.2 (`4.6.2.stable.official.71f334935`)
- Export stamp: `20260620T000000Z`
- Build script: `scripts/export/build_release.sh web macos`
- Export presets: `export_presets.cfg`
- Export template path: `~/Library/Application Support/Godot/export_templates/4.6.2.stable`
- Regression method: run the validation scripts from `docs/game/06_validation_plan.md` against the exported PCKs with `godot-4.6.2 --headless --main-pack <exported.pck> --script res://scripts/validation/<script>.gd`.

## Artifacts

| Target | Artifact | SHA-256 | Size / notes |
|---|---|---|---|
| Web / HTML5 | `build/release/sargasso-of-stars-v0.1.0-20260620T000000Z-web.zip` | `e1e59ea8c094f7cfade3c9e448a25aa485cf402f31a9e8342815a92fc91df7e6` | 9 entries; excludes `addons/gdai-mcp-plugin-godot`. |
| macOS | `build/release/sargasso-of-stars-v0.1.0-20260620T000000Z-macos.zip` | `a6b7136a6934fe5e39f6a26e37771401e528409c2e60b43a44166c140b55e997` | 6 entries; excludes `addons/gdai-mcp-plugin-godot`. |

Hash manifest: `build/release/artifacts.sha256`.

## Export build result

Command:

```bash
SARGASSO_BUILD_STAMP=20260620T000000Z scripts/export/build_release.sh web macos
```

Result:

```text
SARGASSO EXPORT PASS version=v0.1.0 stamp=20260620T000000Z targets=web macos release_dir=/Users/christopherwilloughby/the-sargasso-of-stars/build/release
```

Logs:

- `build/logs/export_web.log`
- `build/logs/export_macos.log`

## Launch / packaging smokes

| Target | Smoke | Result | Evidence |
|---|---|---|---|
| macOS | Launch exported app with `--headless --quit` | PASS | `build/logs/macos_launch_smoke.log` contains `PLAYABLE SHIP READY player_spawned=true camera_spawned=true objectives=5 collision_shapes=31`, exit 0. |
| Web / HTML5 | Serve exported files with local HTTP server and fetch `index.html`, `index.wasm`, `index.pck` | PASS | `build/logs/web_http_asset_smoke.log`, all 3 requests returned HTTP 200. |

Note: the Web smoke verifies the exported HTML5 artifact is structurally serveable. It is not a browser/WebGL manual playthrough; that remains an itch.io-channel release-ops check before public upload.

## Exported-pack regression

The full validation bundle was run against both exported packs.

| Target | Exported pack | Commands | Result | Log |
|---|---|---:|---|---|
| Web / HTML5 | `build/exports/web/index.pck` | 31 | PASS / clean output | `build/logs/export_regression_web.log` |
| macOS | `build/run/macos/The Sargasso of Stars.app/Contents/Resources/The Sargasso of Stars.pck` | 31 | PASS / clean output | `build/logs/export_regression_macos.log` |

Summary output:

```text
SARGASSO EXPORT REGRESSION PASS target=web commands=31 clean_output=true log=/Users/christopherwilloughby/the-sargasso-of-stars/build/logs/export_regression_web.log
SARGASSO EXPORT REGRESSION PASS target=macos commands=31 clean_output=true log=/Users/christopherwilloughby/the-sargasso-of-stars/build/logs/export_regression_macos.log
export_regression_results=/Users/christopherwilloughby/the-sargasso-of-stars/build/logs/export_regression_results.tsv rows=62
```

Result table: `build/logs/export_regression_results.tsv`.

## Classified warnings / errors

No unclassified `ERROR:` or `WARNING:` lines appeared in the exported-pack regression logs. The strict allowlist from `docs/game/06_validation_plan.md` was applied:

- `ERROR: Capture not registered: 'gdaimcp'.`
- `WARNING: ObjectDB instances leaked at exit (run with --verbose for details).`
- `WARNING: SaveLoadService: save file rejected by from_dict (missing fields or version mismatch)`

The release exports also exclude the local-only GDAI addon (`addons/gdai-mcp-plugin-godot/**`), so the packaged artifacts do not contain that paid/local tooling.

## Gate 5 status

- Export pipeline: PASS for two RC kickoff targets (Web/HTML5 and macOS).
- Exported-pack regression: PASS for Web/HTML5 and macOS, 31/31 each.
- Store requirements checklist: `docs/game/store_requirements.md` exists and is cited by Gate 5.
- Release notes/postmortem templates: `docs/game/release_notes_template.md` and `docs/game/postmortem_template.md` exist and are cited by Gate 5.

Remaining release-ops items before a public release: in-browser HTML5 playthrough on the actual itch.io channel, Windows build/run smoke on a Windows host, optional Linux host smoke, butler authentication/upload evidence, pricing/account decisions, and legal/privacy text finalization.
