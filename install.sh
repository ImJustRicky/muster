#!/usr/bin/env bash
# muster installer — curl https://raw.githubusercontent.com/ImJustRicky/muster/main/install.sh | bash
set -euo pipefail

REPO="ImJustRicky/muster"
INSTALL_DIR="${MUSTER_INSTALL_DIR:-$HOME/.muster}"
BIN_DIR="${MUSTER_BIN_DIR:-$HOME/.local/bin}"

echo ""
echo "  Installing muster..."
echo ""

# Clone or update
if [[ -d "${INSTALL_DIR}/repo" ]]; then
  echo "  Updating existing installation..."
  (cd "${INSTALL_DIR}/repo" && git pull --quiet)
else
  mkdir -p "$INSTALL_DIR"
  git clone --quiet "https://github.com/${REPO}.git" "${INSTALL_DIR}/repo"
fi

mkdir -p "$BIN_DIR"

# Link binaries
chmod +x "${INSTALL_DIR}/repo/bin/muster" "${INSTALL_DIR}/repo/bin/muster-mcp"
ln -sf "${INSTALL_DIR}/repo/bin/muster" "${BIN_DIR}/muster"
ln -sf "${INSTALL_DIR}/repo/bin/muster-mcp" "${BIN_DIR}/muster-mcp"

# Check PATH
if ! echo "$PATH" | tr ':' '\n' | grep -q "^${BIN_DIR}$"; then
  echo ""
  echo "  Add this to your shell profile:"
  echo ""
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "  Done! Run 'muster --version' to verify."
echo ""
