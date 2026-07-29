#!/usr/bin/env sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEST_DIR=${OFFICE_VBA_MCP_INSTALL_DIR:-"$ROOT/bin"}
BASE_URL=${OFFICE_VBA_MCP_RELEASE_BASE_URL:-"https://github.com/miclip/office-vba-mcp/releases/latest/download"}

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

case "$OS/$ARCH" in
  darwin/arm64) ASSET=office-vba-mcp-darwin-arm64 ;;
  darwin/amd64) ASSET=office-vba-mcp-darwin-amd64 ;;
  linux/amd64) ASSET=office-vba-mcp-linux-amd64 ;;
  *) echo "No upstream release is documented for $OS/$ARCH" >&2; exit 1 ;;
esac

mkdir -p "$DEST_DIR"
TMP="$DEST_DIR/.office-vba-mcp.download"
DEST="$DEST_DIR/office-vba-mcp"
trap 'rm -f "$TMP"' EXIT HUP INT TERM

if command -v curl >/dev/null 2>&1; then
  curl -fL "$BASE_URL/$ASSET" -o "$TMP"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$TMP" "$BASE_URL/$ASSET"
else
  echo "curl or wget is required" >&2
  exit 1
fi

chmod 0755 "$TMP"
mv "$TMP" "$DEST"
trap - EXIT HUP INT TERM

echo "Installed: $DEST"
OFFICE_VBA_MCP="$DEST" "${PYTHON:-python3}" "$ROOT/scripts/office-vba.py" doctor
