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

# Smoke test: verify muster runs after install
_path_has_bin_dir=true
if ! echo "$PATH" | tr ':' '\n' | grep -q "^${BIN_DIR}$"; then
  _path_has_bin_dir=false
fi

echo ""
if "${BIN_DIR}/muster" --version >/dev/null 2>&1; then
  _ver="$("${BIN_DIR}/muster" --version 2>/dev/null || true)"
  if [[ -n "$_ver" ]]; then
    echo "  Done! muster ${_ver} installed."
  else
    echo "  Done! muster installed."
  fi
else
  echo "  Warning: muster installed but failed to run."
  echo ""
  if [[ ! -e "${BIN_DIR}/muster" ]]; then
    echo "  Symlink is broken: ${BIN_DIR}/muster"
    echo "  Target: $(readlink "${BIN_DIR}/muster" 2>/dev/null || echo 'unknown')"
  elif [[ ! -x "${BIN_DIR}/muster" ]]; then
    echo "  Symlink target is not executable: ${BIN_DIR}/muster"
  else
    echo "  The binary at ${BIN_DIR}/muster exited with an error."
    echo "  Try running it directly to see the issue:"
    echo "    ${BIN_DIR}/muster --version"
  fi
fi

if [[ "$_path_has_bin_dir" = false ]]; then
  echo ""
  echo "  Note: ${BIN_DIR} is not in your PATH."
  echo "  Add this to your shell profile:"
  echo ""
  echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi
echo ""
