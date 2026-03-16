#!/usr/bin/env bash
# =============================================================================
# Helios + Pi — One-Command Bootstrap
# =============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash
# =============================================================================

set -euo pipefail

# ─── Windows Detection — WSL-First Approach ──────────────────────────────────
# If running in Git Bash, MSYS2, MINGW, or Cygwin on Windows, guide user to WSL.
detect_windows() {
  local uname_out
  uname_out="$(uname -s 2>/dev/null || echo "Unknown")"
  
  case "$uname_out" in
    MINGW*|MSYS*|CYGWIN*)
      echo ""
      echo "═══════════════════════════════════════════════════════════════"
      echo "  Helios requires WSL (Windows Subsystem for Linux)"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""
      echo "  You're running in Git Bash/MSYS — this won't work."
      echo "  Helios needs a full Linux environment via WSL."
      echo ""
      echo "  Option 1 — PowerShell (recommended):"
      echo "  Open PowerShell and run:"
      echo ""
      echo "    irm https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/install.ps1 | iex"
      echo ""
      echo "  Option 2 — Command Prompt (no PowerShell needed):"
      echo "  Open CMD as Administrator and run:"
      echo ""
      echo "    curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/install.bat -o %TEMP%\\install-helios.bat && %TEMP%\\install-helios.bat"
      echo ""
      echo "  Option 3 — Manual WSL setup:"
      echo "  In PowerShell or CMD as Admin:"
      echo ""
      echo "    wsl --install"
      echo ""
      echo "  Then restart your computer, open Ubuntu from the Start"
      echo "  menu, and run:"
      echo ""
      echo "    curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh | bash"
      echo ""
      echo "  Need help? See: https://learn.microsoft.com/en-us/windows/wsl/install"
      echo "═══════════════════════════════════════════════════════════════"
      echo ""
      exit 1
      ;;
  esac
}

detect_windows

# ─── Restore stdin from terminal (critical for curl|bash piping) ─────────────
# When run via `curl ... | bash`, stdin is the pipe (EOF after script downloads).
# Reopen stdin from /dev/tty so git clone, read, etc. can interact with the user.
if [[ ! -t 0 ]]; then
  if [[ -e /dev/tty ]]; then
    exec < /dev/tty
  else
    echo "ERROR: No terminal available (/dev/tty). Run this script directly instead of piping." >&2
    echo "  bash <(curl -fsSL https://raw.githubusercontent.com/sweetcheeks72/helios-team-installer/main/bootstrap.sh)" >&2
    exit 1
  fi
fi

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

# ─── Auto-install Prerequisites ───────────────────────────────────────────────
echo -e "  ${BOLD}Installing prerequisites...${RESET}"

PLATFORM="$(uname -s)"
ARCH="$(uname -m)"

# Homebrew (macOS only)
if [[ "$PLATFORM" == "Darwin" ]] && ! command -v brew &>/dev/null; then
  echo -e "  ${CYAN}⬇${RESET}  Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
  # Add brew to PATH for this session
  if [[ "$ARCH" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  else
    eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
  fi
  command -v brew &>/dev/null && echo -e "  ${GREEN}✓${RESET} Homebrew installed" || { echo -e "  ${RED}✗${RESET} Homebrew install failed"; exit 1; }
fi

# Node.js 18+
node_ok=false
if command -v node &>/dev/null; then
  if node -e "process.exit(parseInt(process.version.slice(1)) < 18 ? 1 : 0)" 2>/dev/null; then
    node_ok=true
    echo -e "  ${GREEN}✓${RESET} Node.js $(node -v)"
  fi
fi
if [[ "$node_ok" == false ]]; then
  echo -e "  ${CYAN}⬇${RESET}  Installing Node.js..."
  if [[ "$PLATFORM" == "Darwin" ]] && command -v brew &>/dev/null; then
    brew install node 2>&1
  elif command -v apt-get &>/dev/null; then
    # Use NodeSource for Node 22 LTS on Ubuntu/Debian/WSL
    if command -v curl &>/dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo bash - 2>/dev/null
      sudo apt-get install -y nodejs 2>/dev/null
    else
      sudo apt-get update -y 2>/dev/null && sudo apt-get install -y nodejs npm 2>/dev/null
    fi
  fi
  command -v node &>/dev/null && echo -e "  ${GREEN}✓${RESET} Node.js $(node -v) installed" || { echo -e "  ${RED}✗${RESET} Node.js install failed — install manually: https://nodejs.org"; exit 1; }
fi

# git
if command -v git &>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} git $(git --version | awk '{print $3}')"
else
  echo -e "  ${CYAN}⬇${RESET}  Installing git..."
  if [[ "$PLATFORM" == "Darwin" ]] && command -v brew &>/dev/null; then
    brew install git 2>&1
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y git 2>/dev/null
  fi
  command -v git &>/dev/null && echo -e "  ${GREEN}✓${RESET} git installed" || { echo -e "  ${RED}✗${RESET} git install failed"; exit 1; }
fi

# npm (comes with node, but verify)
if command -v npm &>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} npm $(npm -v)"
else
  echo -e "  ${RED}✗${RESET} npm not found (should come with Node.js)"
  exit 1
fi

# python3
if command -v python3 &>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} python3 $(python3 --version 2>/dev/null | awk '{print $2}')"
else
  echo -e "  ${CYAN}⬇${RESET}  Installing python3..."
  if [[ "$PLATFORM" == "Darwin" ]]; then
    brew install python3 2>&1
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y python3 2>/dev/null
  fi
  command -v python3 &>/dev/null && echo -e "  ${GREEN}✓${RESET} python3 installed" || echo -e "  ${YELLOW}⚠${RESET} python3 not found — some features may be limited"
fi

echo ""

# ─── Clone or update installer ───────────────────────────────────────────────
if [ -d "$INSTALLER_DIR/.git" ]; then
  echo -e "  ${CYAN}ℹ${RESET} Installer already exists — pulling latest..."
  if ! git -C "$INSTALLER_DIR" pull --rebase --autostash -q 2>/dev/null; then
    echo -e "  ${YELLOW}⚠${RESET} Could not pull latest — using existing version"
  fi
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
exec bash "$INSTALLER_DIR/install.sh" "$@"
