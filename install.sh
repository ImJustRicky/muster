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
  echo "  ${BIN_DIR} is not in your PATH."

  # Detect shell profile
  _shell_profile=""
  case "${SHELL:-}" in
    */zsh)  _shell_profile="$HOME/.zshrc" ;;
    */bash) _shell_profile="$HOME/.bashrc" ;;
  esac
  # Fallback: check what exists
  if [[ -z "$_shell_profile" ]]; then
    if [[ -f "$HOME/.zshrc" ]]; then
      _shell_profile="$HOME/.zshrc"
    elif [[ -f "$HOME/.bashrc" ]]; then
      _shell_profile="$HOME/.bashrc"
    elif [[ -f "$HOME/.profile" ]]; then
      _shell_profile="$HOME/.profile"
    fi
  fi

  _export_line="export PATH=\"\$HOME/.local/bin:\$PATH\""
  _added=false

  if [[ -n "$_shell_profile" && -t 0 ]]; then
    echo ""
    printf "  Add to %s? [Y/n] " "$_shell_profile"
    read -r _answer
    case "${_answer:-Y}" in
      [Yy]|"")
        echo "" >> "$_shell_profile"
        echo "# Added by muster installer" >> "$_shell_profile"
        echo "$_export_line" >> "$_shell_profile"
        echo "  Added to ${_shell_profile}."
        echo "  Run: source ${_shell_profile}"
        _added=true
        ;;
    esac
  fi

  if [[ "$_added" = false ]]; then
    echo "  Add this to your shell profile:"
    echo ""
    echo "    ${_export_line}"
  fi
fi
echo ""
