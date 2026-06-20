# Export Pipeline

## Scope

Gate 5 RC exports use Godot 4.6.2 and the checked-in `export_presets.cfg` at the project root. The release pipeline targets:

- HTML5/Web for itch.io browser embedding (`web`).
- Linux x86_64 (`linux`).
- macOS desktop zip (`macos`).
- Windows x86_64 (`windows`).

The primary Gate 5 downloadable targets remain Windows x86_64 and macOS. HTML5 is the itch.io embed target; Linux is optional unless it stays under the RC time budget.

## Prerequisites

- Godot binary: `/Users/christopherwilloughby/.local/bin/godot-4.6.2`.
- Godot export templates installed at `~/Library/Application Support/Godot/export_templates/4.6.2.stable`.
- Required template files:
  - `web_dlink_release.zip`
  - `linux_release.x86_64`
  - `macos.zip`
  - `windows_release_x86_64.exe`
- Python 3 for artifact packaging.

The local GDAI automation addon is excluded from release exports. The build script temporarily removes the local-only `GDAIMCPRuntime` autoload from `project.godot` during export and restores the file on exit. The export presets also exclude `addons/gdai-mcp-plugin-godot/**`, `.godot/**`, and `build/**` so local tooling and generated artifacts are not packaged.

## Build command

Run all configured release exports:

```bash
scripts/export/build_release.sh
```

Run only selected targets:

```bash
scripts/export/build_release.sh web macos
scripts/export/build_release.sh linux windows
```

Useful environment overrides:

```bash
GODOT=/path/to/godot-4.6.2 \
SARGASSO_VERSION=v0.1.0 \
SARGASSO_BUILD_STAMP=20260620T000000Z \
scripts/export/build_release.sh web macos
```

## Outputs

Raw Godot exports are written under `build/exports/`. Packaged release artifacts are written under `build/release/` using stamped names:

- `sargasso-of-stars-v0.1.0-<stamp>-web.zip`
- `sargasso-of-stars-v0.1.0-<stamp>-linux-x86_64.zip`
- `sargasso-of-stars-v0.1.0-<stamp>-macos.zip`
- `sargasso-of-stars-v0.1.0-<stamp>-windows-x86_64.zip`
- `artifacts.sha256`

## Verification

1. Static pipeline check:

```bash
python3 tools/check_export_pipeline.py /Users/christopherwilloughby/the-sargasso-of-stars
```

Expected marker:

```text
EXPORT PIPELINE CHECK PASS presets=4 build_script=true docs=true
```

2. Export smoke for at least two platforms:

```bash
SARGASSO_BUILD_STAMP=<stamp> scripts/export/build_release.sh web macos
```

Expected marker:

```text
SARGASSO EXPORT PASS version=v0.1.0 stamp=<stamp> targets=web macos release_dir=.../build/release
```

3. Launch smoke:

- HTML5: serve `build/exports/web/` locally and verify the browser loads `index.html` with the Godot canvas.
- macOS: unzip the macOS artifact and launch the app bundle locally. For unsigned RC builds, macOS Gatekeeper/notarization is an expected external release-ops step, not a local export failure.
- Linux/Windows: run the exported executable on a matching host or VM before Gate 5 exit.

4. Regression on export builds:

Record exported-build smoke results in `docs/game/export_regression_report.md`. Editor/headless smokes from `docs/game/06_validation_plan.md` remain the baseline, but Gate 5 requires exported-build evidence before exit.

## Stop conditions

- Missing official Godot 4.6.2 export templates.
- Any Godot export command exits non-zero.
- Any unclassified `ERROR:` / `SCRIPT ERROR:` appears in an export log.
- Exported build cannot launch on its target platform.
- Exported build fails a smoke that passes in editor.
