#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
GODOT=${GODOT:-/Users/christopherwilloughby/.local/bin/godot-4.6.2}
SYNAPSE_SEA_VERSION=${SYNAPSE_SEA_VERSION:-v0.1.0}
BUILD_STAMP=${SYNAPSE_SEA_BUILD_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}
EXPORT_DIR="$ROOT/build/exports"
RELEASE_DIR="$ROOT/build/release"
LOG_DIR="$ROOT/build/logs"
TEMPLATE_DIR="$HOME/Library/Application Support/Godot/export_templates/4.6.2.stable"
PROJECT_BACKUP=""

usage() {
  cat <<'USAGE'
Usage: scripts/export/build_release.sh [web] [linux] [macos] [windows]

Builds release exports with Godot 4.6.2. If no targets are supplied, all four
configured presets are exported. Artifacts are written under build/release/ and
named synapse-sea-of-stars-<version>-<stamp>-<target>.*.
USAGE
}

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "missing required file: $path" >&2
    exit 1
  fi
}

restore_project() {
  if [ -n "$PROJECT_BACKUP" ] && [ -f "$PROJECT_BACKUP" ]; then
    cp "$PROJECT_BACKUP" "$ROOT/project.godot"
    rm -f "$PROJECT_BACKUP"
  fi
}

prepare_release_project() {
  PROJECT_BACKUP=$(mktemp "${TMPDIR:-/tmp}/synapse_sea_project_godot.XXXXXX")
  cp "$ROOT/project.godot" "$PROJECT_BACKUP"
  python3 - "$ROOT/project.godot" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text(encoding='utf-8')
text = '\n'.join(line for line in text.splitlines() if not line.startswith('GDAIMCPRuntime=')) + '\n'
path.write_text(text, encoding='utf-8')
PY
}

package_dir() {
  local source_dir="$1"
  local artifact="$2"
  python3 - "$source_dir" "$artifact" <<'PY'
from pathlib import Path
import sys
import zipfile
source = Path(sys.argv[1])
artifact = Path(sys.argv[2])
artifact.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(artifact, 'w', zipfile.ZIP_DEFLATED) as zf:
    for path in sorted(source.rglob('*')):
        if path.is_file():
            zf.write(path, path.relative_to(source))
print(artifact)
PY
}

export_one() {
  local preset="$1"
  local output="$2"
  local artifact="$3"
  local output_dir
  output_dir=$(dirname "$output")
  mkdir -p "$output_dir" "$RELEASE_DIR" "$LOG_DIR"
  echo "=== exporting $preset -> $output ==="
  "$GODOT" --headless --path "$ROOT" --export-release "$preset" "$output" 2>&1 | tee "$LOG_DIR/export_${preset}.log"
  if grep -E '^(ERROR|SCRIPT ERROR):' "$LOG_DIR/export_${preset}.log" >/dev/null; then
    echo "unclassified Godot error during $preset export" >&2
    exit 1
  fi
  case "$preset" in
    web)
      package_dir "$output_dir" "$artifact"
      ;;
    linux)
      chmod +x "$output"
      package_dir "$output_dir" "$artifact"
      ;;
    macos)
      cp "$output" "$artifact"
      ;;
    windows)
      package_dir "$output_dir" "$artifact"
      ;;
    *)
      echo "unknown preset: $preset" >&2
      exit 1
      ;;
  esac
}

main() {
  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
  fi

  require_file "$GODOT"
  require_file "$ROOT/export_presets.cfg"
  require_file "$TEMPLATE_DIR/web_dlink_release.zip"
  require_file "$TEMPLATE_DIR/linux_release.x86_64"
  require_file "$TEMPLATE_DIR/macos.zip"
  require_file "$TEMPLATE_DIR/windows_release_x86_64.exe"

  local targets=("$@")
  if [ ${#targets[@]} -eq 0 ]; then
    targets=(web linux macos windows)
  fi

  rm -rf "$EXPORT_DIR" "$RELEASE_DIR" "$LOG_DIR"
  mkdir -p "$EXPORT_DIR" "$RELEASE_DIR" "$LOG_DIR"
  prepare_release_project
  trap restore_project EXIT

  for target in "${targets[@]}"; do
    case "$target" in
      web)
        export_one web "$EXPORT_DIR/web/index.html" "$RELEASE_DIR/synapse-sea-of-stars-${SYNAPSE_SEA_VERSION}-${BUILD_STAMP}-web.zip"
        ;;
      linux)
        export_one linux "$EXPORT_DIR/linux/synapse-sea-of-stars.x86_64" "$RELEASE_DIR/synapse-sea-of-stars-${SYNAPSE_SEA_VERSION}-${BUILD_STAMP}-linux-x86_64.zip"
        ;;
      macos)
        export_one macos "$EXPORT_DIR/macos/synapse-sea-of-stars.zip" "$RELEASE_DIR/synapse-sea-of-stars-${SYNAPSE_SEA_VERSION}-${BUILD_STAMP}-macos.zip"
        ;;
      windows)
        export_one windows "$EXPORT_DIR/windows/synapse-sea-of-stars.exe" "$RELEASE_DIR/synapse-sea-of-stars-${SYNAPSE_SEA_VERSION}-${BUILD_STAMP}-windows-x86_64.zip"
        ;;
      *)
        echo "unknown target '$target'" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  (
    cd "$RELEASE_DIR"
    shasum -a 256 * > artifacts.sha256
  )
  echo "SYNAPSE_SEA EXPORT PASS version=$SYNAPSE_SEA_VERSION stamp=$BUILD_STAMP targets=${targets[*]} release_dir=$RELEASE_DIR"
}

main "$@"
