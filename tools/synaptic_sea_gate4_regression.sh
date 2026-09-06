#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
PYTHON="${PYTHON:-python3}"
if [ "$#" -ne 0 ]; then
  printf '%s\n' 'Use shell redirection for logs; this entry point accepts no positional log directory.' >&2
  exit 2
fi
exec "$PYTHON" "$ROOT/tools/run_canonical_regression.py" --project-root "$ROOT"
