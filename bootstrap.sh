#!/usr/bin/env bash
# =============================================================================
# Helios + Pi — One-Command Bootstrap
# =============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

INSTALLER_DIR="$HOME/helios-team-installer"
INSTALLER_REPO="https://github.com/sweetcheeks72/helios-team-installer.git"

echo ""
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  ╔═══════════════════════════════════════════════════════════════╗
  ║                                                               ║
  ║    ██╗  ██╗███████╗██╗     ██╗ ██████╗ ███████╗              ║
  ║    ██║  ██║██╔════╝██║     ██║██╔═══██╗██╔════╝              ║
  ║    ███████║█████╗  ██║     ██║██║   ██║███████╗              ║
  ║    ██╔══██║██╔══╝  ██║     ██║██║   ██║╚════██║              ║
  ║    ██║  ██║███████╗███████╗██║╚██████╔╝███████║              ║
  ║    ╚═╝  ╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚══════╝              ║
  ║                                                               ║
  ║              One-Command Bootstrap                            ║
  ║                                                               ║
  ╚═══════════════════════════════════════════════════════════════╝
BANNER
echo -e "${RESET}"

# ─── Prerequisites ────────────────────────────────────────────────────────────
echo -e "  ${BOLD}Checking prerequisites...${RESET}"

fail=false

if command -v node &>/dev/null; then
  if node -e "process.exit(parseInt(process.version.slice(1)) < 18 ? 1 : 0)" 2>/dev/null; then
    echo -e "  ${GREEN}✓${RESET} Node.js $(node -v)"
  else
    echo -e "  ${RED}✗${RESET} Node.js 18+ required (found $(node -v))"
    fail=true
  fi
else
  echo -e "  ${RED}✗${RESET} Node.js not found — install from https://nodejs.org or: brew install node"
  fail=true
fi

if command -v git &>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} git $(git --version | awk '{print $3}')"
else
  echo -e "  ${RED}✗${RESET} git not found — install with: brew install git"
  fail=true
fi

if command -v npm &>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} npm $(npm -v)"
else
  echo -e "  ${RED}✗${RESET} npm not found"
  fail=true
fi

if [ "$fail" = true ]; then
  echo ""
  echo -e "  ${RED}${BOLD}✗ Missing prerequisites. Install them and try again.${RESET}"
  exit 1
fi

echo ""

# ─── Clone or update installer ───────────────────────────────────────────────
if [ -d "$INSTALLER_DIR/.git" ]; then
  echo -e "  ${CYAN}ℹ${RESET} Installer already exists — pulling latest..."
  git -C "$INSTALLER_DIR" pull --rebase --autostash -q 2>/dev/null || true
else
  if [ -d "$INSTALLER_DIR" ]; then
    echo -e "  ${YELLOW}⚠${RESET} $INSTALLER_DIR exists but isn't a git repo — backing up"
    mv "$INSTALLER_DIR" "${INSTALLER_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
  fi
  echo -e "  ${CYAN}⬇${RESET}  Downloading installer..."
  git clone -q "$INSTALLER_REPO" "$INSTALLER_DIR"
fi

echo -e "  ${GREEN}✓${RESET} Installer ready at $INSTALLER_DIR"
echo ""

# ─── Hand off to full installer ──────────────────────────────────────────────
echo -e "  ${BOLD}Launching full installer...${RESET}"
echo ""
exec bash "$INSTALLER_DIR/install.sh"
