#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST_DIR=${OFFICE_VBA_MCP_INSTALL_DIR:-"$ROOT/bin"}
PYTHON_BIN=${PYTHON:-python3}

exec "$PYTHON_BIN" "$ROOT/scripts/install-binary.py" --install-dir "$DEST_DIR" "$@"
