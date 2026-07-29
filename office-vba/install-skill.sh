#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET_ROOT=${AGENT_SKILLS_DIR:-"$HOME/.agents/skills"}
TARGET="$TARGET_ROOT/office-vba"

mkdir -p "$TARGET_ROOT"
if [ -e "$TARGET" ] || [ -L "$TARGET" ]; then
  echo "Target already exists: $TARGET" >&2
  echo "Remove it or set AGENT_SKILLS_DIR to another location." >&2
  exit 1
fi

ln -s "$ROOT" "$TARGET"
echo "Installed skill link: $TARGET -> $ROOT"

if [ "${OFFICE_VBA_SKIP_BINARY_INSTALL:-0}" != "1" ]; then
  "$TARGET/install.sh" "$@"
else
  echo "Skipped office-vba-mcp binary installation."
fi
