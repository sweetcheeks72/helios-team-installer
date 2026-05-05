#!/usr/bin/env bash
# =============================================================================
# Helios — Single command install or update (no git required, all repos private)
# =============================================================================
# curl -fsSL https://github.com/helios-agi/helios-team-installer/releases/latest/download/bootstrap.sh | bash
# =============================================================================

{
set -euo pipefail

RELEASE_URL="https://github.com/helios-agi/helios-team-installer/releases/latest/download"
INSTALLER_DIR="$HOME/helios-team-installer"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

trap 'echo ""; echo -e "${RED}✗ Bootstrap failed at line $LINENO.${RESET}"; echo "  Re-run to retry (safe — idempotent)."; echo "  Or run manually: bash ~/helios-team-installer/install.sh"' ERR

# Restore stdin for interactive prompts when piped
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec < /dev/tty 2>/dev/null || true
fi

echo ""
echo -e "${BOLD}${CYAN}  Helios — Installing...${RESET}"
echo ""

# Detect platform
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "Helios requires WSL on Windows."
    echo "  Run in PowerShell: wsl --install"
    exit 1
    ;;
esac

# Require curl
if ! command -v curl &>/dev/null; then
  echo -e "${RED}✗${RESET} curl is required. Install it first."
  exit 1
fi

# Download installer package
echo -e "  ${DIM}Downloading installer...${RESET}"
tmp_tarball="$(mktemp)"
if ! curl -fsSL --retry 3 --max-time 60 -o "$tmp_tarball" "$RELEASE_URL/helios-installer.tar.gz"; then
  echo -e "${RED}✗${RESET} Failed to download installer"
  rm -f "$tmp_tarball"
  exit 1
fi

# Extract installer (overwrites previous version — this IS the update mechanism)
rm -rf "$INSTALLER_DIR"
mkdir -p "$INSTALLER_DIR"
if ! tar -xzf "$tmp_tarball" -C "$INSTALLER_DIR" --strip-components=1 2>/dev/null; then
  echo -e "${RED}✗${RESET} Failed to extract installer"
  rm -f "$tmp_tarball"
  exit 1
fi
rm -f "$tmp_tarball"

echo -e "  ${GREEN}✓${RESET} Installer ready"
echo ""

# Run the installer (auto-detects fresh install vs update)
exec bash "$INSTALLER_DIR/install.sh" "$@"
}
