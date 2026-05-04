#!/usr/bin/env bash
# =============================================================================
# Helios + Pi — One-Command Bootstrap
# =============================================================================
# Usage: curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh | bash
# =============================================================================

{

# ─── Windows Detection ────────────────────────────────────────────────────────
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    echo ""
    echo "Helios requires WSL. Run in PowerShell:"
    echo "  irm https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/install.ps1 | iex"
    echo "See: https://learn.microsoft.com/en-us/windows/wsl/install"
    exit 1
    ;;
esac

# ─── Strict mode — but with error trap so failures are VISIBLE ────────────────
set -euo pipefail
trap 'echo ""; echo "✗ Bootstrap failed at line $LINENO. Re-run to retry (safe — idempotent)."; echo "  If stuck, run manually: bash ~/helios-team-installer/install.sh"; echo "  Logs: /tmp/helios-bootstrap.log"' ERR

# ─── Restore stdin from terminal (critical for curl|bash piping) ─────────────
if [[ ! -t 0 ]]; then
  if [[ -e /dev/tty ]]; then
    exec < /dev/tty
  else
    echo "ERROR: No terminal available (/dev/tty). Run this script directly instead of piping." >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh -o /tmp/helios-bootstrap.sh && bash /tmp/helios-bootstrap.sh" >&2
    exit 1
  fi
fi

# ─── Immediate output — user sees this first, before anything can hang ────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-dumb}" != "dumb" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' DIM='' RESET=''
fi

PLATFORM="$(uname -s)"
INSTALLER_DIR="$HOME/helios-team-installer"
INSTALLER_REPO="https://github.com/helios-agi/helios-team-installer.git"

# Source shared platform detection lib (only available after installer is cloned)
_source_platform_lib() {
  if [[ -f "$INSTALLER_DIR/lib/platform.sh" ]]; then
    source "$INSTALLER_DIR/lib/platform.sh"
  fi
}

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
echo -e "  ${DIM}Setting up prerequisites — this may take 1-2 minutes...${RESET}"
echo ""

# ─── FIX #6: Network connectivity check ──────────────────────────────────────
if ! curl -fsSL --connect-timeout 5 --max-time 10 https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh -o /dev/null 2>/dev/null; then
  echo -e "  ${RED}✗${RESET} Cannot reach GitHub. Check your internet connection or VPN."
  echo -e "  ${DIM}If behind a firewall, ensure raw.githubusercontent.com is accessible.${RESET}"
  exit 1
fi

# ─── FIX #4: Rosetta 2 detection (Apple Silicon) ─────────────────────────────
if [[ "$PLATFORM" == "Darwin" ]] && [[ "$(uname -m)" == "x86_64" ]]; then
  if sysctl -n sysctl.proc_translated 2>/dev/null | grep -q 1; then
    echo -e "  ${RED}✗${RESET} Terminal is running under Rosetta 2 (Intel emulation)."
    echo -e "  ${DIM}Homebrew requires native ARM mode on Apple Silicon Macs.${RESET}"
    echo -e "  ${DIM}Fix: Right-click Terminal → Get Info → uncheck 'Open using Rosetta', then re-run.${RESET}"
    exit 1
  fi
fi

# ─── macOS: Xcode Command Line Tools (MUST come before git or brew) ──────────
# On fresh Macs, /usr/bin/git is a shim that triggers a GUI install dialog for
# Xcode CLT. This dialog appears BEHIND other windows and hangs the installer.
# Fix: detect and install CLT non-interactively before touching git or brew.
if [[ "$PLATFORM" == "Darwin" ]]; then
  if ! xcode-select -p &>/dev/null; then
    echo "  ⬇  Installing Xcode Command Line Tools (required for git + brew)..."
    echo "     This may take 2-5 minutes. Please wait..."
    echo ""

    # Method 1: Non-interactive install via softwareupdate (preferred — no GUI popup)
    # Create the trigger file that makes softwareupdate list CLT
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null || true
    CLT_PACKAGE=$(softwareupdate -l 2>/dev/null | grep -o ".*Command Line Tools.*" | grep -v "^\\*" | sed 's/^[[:space:]]*//' | { command -v gsort &>/dev/null && gsort -V || sort; } | tail -1)

    if [[ -n "$CLT_PACKAGE" ]]; then
      echo "     Found: $CLT_PACKAGE"
      echo "     Installing (this is the slow part)..."
      # FIX #3: softwareupdate -i requires sudo — check admin first, cache credentials
      if groups 2>/dev/null | grep -qw admin || sudo -n true 2>/dev/null; then
        sudo -v 2>/dev/null || true  # Cache sudo credentials
        if sudo softwareupdate -i "$CLT_PACKAGE" --verbose 2>&1 | while IFS= read -r line; do
        # Show progress dots so user knows it's working
        printf "." >&2
      done; then
        echo ""
        echo "  ✓  Xcode Command Line Tools installed"
      else
        echo ""
        echo "  ⚠  softwareupdate install failed — trying xcode-select..."
      fi
      else
        echo ""
        echo "  ⚠  Admin privileges required for softwareupdate — trying xcode-select fallback..."
      fi
    fi
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null || true

    # Method 2: Fallback to xcode-select --install (triggers GUI but we warn user)
    if ! xcode-select -p &>/dev/null; then
      echo ""
      echo "  ──────────────────────────────────────────────────────────"
      echo "  A dialog box should appear asking to install developer tools."
      echo "  Click 'Install' and wait for it to complete, then re-run:"
      echo ""
      echo "    curl -fsSL https://raw.githubusercontent.com/helios-agi/helios-team-installer/main/bootstrap.sh | bash"
      echo "  ──────────────────────────────────────────────────────────"
      echo ""
      xcode-select --install 2>/dev/null || true
      # Wait up to 60 seconds for CLT to appear (user clicking Install in dialog)
      echo "  Waiting for Xcode CLT installation..."
      for i in $(seq 1 60); do
        if xcode-select -p &>/dev/null; then
          echo "  ✓  Xcode Command Line Tools installed"
          break
        fi
        sleep 5
        printf "." >&2
      done
      echo ""

      if ! xcode-select -p &>/dev/null; then
        echo "  ✗  Xcode CLT not installed yet."
        echo "    Complete the install dialog, then re-run this command."
        exit 1
      fi
    fi
  else
    echo "  ✓  Xcode Command Line Tools"
  fi
fi

# ─── Auto-install Prerequisites ───────────────────────────────────────────────
echo -e "  ${BOLD}Installing prerequisites...${RESET}"

# Homebrew (macOS — REQUIRED)
if [[ "$PLATFORM" == "Darwin" ]] && ! command -v brew &>/dev/null; then
  echo -e "  ${CYAN}⬇${RESET}  Installing Homebrew (required for macOS)..."
  echo -e "  ${DIM}You may be prompted for your password.${RESET}"
  # Ensure we have admin access
  if ! sudo -v 2>/dev/null; then
    echo ""
    echo -e "  ${RED}✗${RESET}  Homebrew requires admin privileges."
    echo -e "    ${BOLD}Fix:${RESET} Run this command first to get admin access:"
    echo -e "    ${DIM}  su - admin_username  # switch to an admin account${RESET}"
    echo -e "    ${DIM}  # Or: System Settings → Users & Groups → make '$(whoami)' an Admin${RESET}"
    echo -e "    Then re-run the installer."
    exit 1
  fi
  HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/aec7285/install.sh"
  BREW_INSTALLER="/tmp/homebrew-install.sh"
  curl -fsSL "$HOMEBREW_INSTALL_URL" -o "$BREW_INSTALLER"
  echo -e "  ${DIM}Homebrew installer downloaded — pinned to known-good commit aec7285${RESET}"
  NONINTERACTIVE=1 /bin/bash "$BREW_INSTALLER"
  rm -f "$BREW_INSTALLER"
  # Add brew to PATH for this session
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || true
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)" 2>/dev/null || true
  fi
  if ! command -v brew &>/dev/null; then
    echo -e "  ${RED}✗${RESET}  Homebrew install failed."
    echo -e "    Install manually: ${BOLD}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${RESET}"
    echo -e "    Then re-run the installer."
    exit 1
  fi
  echo -e "  ${GREEN}✓${RESET} Homebrew installed"
  # Persist Homebrew PATH to shell profile
  brew_shellenv=""
  if [[ -x /opt/homebrew/bin/brew ]]; then
    brew_shellenv='eval "$(/opt/homebrew/bin/brew shellenv)"'
  elif [[ -x /usr/local/bin/brew ]]; then
    brew_shellenv='eval "$(/usr/local/bin/brew shellenv)"'
  fi
  if [[ -n "$brew_shellenv" ]]; then
    for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
      if [[ -f "$rc" ]] || [[ "$rc" == *"zprofile"* ]]; then
        if ! grep -qF 'brew shellenv' "$rc" 2>/dev/null; then
          echo "$brew_shellenv" >> "$rc"
        fi
      fi
    done
  fi
elif [[ "$PLATFORM" == "Darwin" ]]; then
  echo -e "  ${GREEN}✓${RESET} Homebrew $(brew --version 2>/dev/null | head -1 | awk '{print $2}')"
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
    # Pin to Node 22 LTS — tarball native modules require Node 22
    brew install node@22 2>&1
    brew link --overwrite node@22 2>&1 || true
  elif command -v apt-get &>/dev/null; then
    if command -v curl &>/dev/null; then
      NODE_SETUP="/tmp/nodesource_setup_22.x.sh"
      curl -fsSL https://deb.nodesource.com/setup_22.x -o "$NODE_SETUP"
      echo "  ℹ  NodeSource setup script downloaded to $NODE_SETUP — inspect before continuing"
      sudo bash "$NODE_SETUP"
      rm -f "$NODE_SETUP"
      sudo apt-get install -y nodejs
    else
      sudo apt-get update -y && sudo apt-get install -y nodejs npm
    fi
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y nodejs
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm nodejs npm
  else
    echo -e "  ${RED}✗${RESET} Unsupported package manager — install Node.js 18+ manually: https://nodejs.org"
    exit 1
  fi
  command -v node &>/dev/null && echo -e "  ${GREEN}✓${RESET} Node.js $(node -v) installed" || { echo -e "  ${RED}✗${RESET} Node.js install failed — install manually: https://nodejs.org"; exit 1; }
fi

# git (CLT already installed above, so git should work now)
if command -v git &>/dev/null; then
  echo -e "  ${GREEN}✓${RESET} git $(git --version | awk '{print $3}')"
else
  echo -e "  ${CYAN}⬇${RESET}  Installing git..."
  if [[ "$PLATFORM" == "Darwin" ]] && command -v brew &>/dev/null; then
    brew install git 2>&1
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y git
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y git
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm git
  else
    echo -e "  ${RED}✗${RESET} Unsupported package manager — install git manually: https://git-scm.com"
    exit 1
  fi
  command -v git &>/dev/null && echo -e "  ${GREEN}✓${RESET} git installed" || { echo -e "  ${RED}✗${RESET} git install failed"; exit 1; }
fi

# npm (comes with node)
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
    # FIX #7: Check brew exists before calling it
    if command -v brew &>/dev/null; then
      brew install python3 2>&1
    else
      echo -e "  ${YELLOW}⚠${RESET} No Homebrew — python3 unavailable (non-critical)"
    fi
  elif command -v apt-get &>/dev/null; then
    sudo apt-get install -y python3
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y python3
  elif command -v pacman &>/dev/null; then
    sudo pacman -S --noconfirm python
  else
    echo -e "  ${YELLOW}⚠${RESET} Unsupported package manager — install python3 manually: https://python.org"
  fi
  command -v python3 &>/dev/null && echo -e "  ${GREEN}✓${RESET} python3 installed" || echo -e "  ${YELLOW}⚠${RESET} python3 not found — some features may be limited"
fi

echo ""

# ─── Clone or update installer ───────────────────────────────────────────────
if [ -d "$INSTALLER_DIR/.git" ]; then
  echo -e "  ${CYAN}ℹ${RESET} Installer already exists — pulling latest..."
  # Abort any in-progress rebase from a previous failed run
  if [ -d "$INSTALLER_DIR/.git/rebase-merge" ] || [ -d "$INSTALLER_DIR/.git/rebase-apply" ]; then
    git -C "$INSTALLER_DIR" rebase --abort 2>/dev/null || true
  fi
  if ! git -C "$INSTALLER_DIR" pull --ff-only -q 2>/dev/null; then
    # Fast-forward failed (local diverged from upstream) — hard reset
    echo -e "  ${YELLOW}⚠${RESET} Local installer modified — resetting to latest release..."
    git -C "$INSTALLER_DIR" fetch origin main -q 2>/dev/null || true
    git -C "$INSTALLER_DIR" reset --hard origin/main -q 2>/dev/null || {
      echo -e "  ${YELLOW}⚠${RESET} Could not update — using existing version"
    }
  fi
else
  if [ -d "$INSTALLER_DIR" ]; then
    echo -e "  ${YELLOW}⚠${RESET} $INSTALLER_DIR exists but isn't a git repo — backing up"
    mv "$INSTALLER_DIR" "${INSTALLER_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
  fi
  echo -e "  ${CYAN}⬇${RESET}  Downloading installer..."
  # FIX #8: Add timeout to git clone to prevent hanging on bad network
  timeout 60 git clone -q "$INSTALLER_REPO" "$INSTALLER_DIR" || {
    echo -e "  ${RED}✗${RESET} Git clone timed out or failed. Check your internet connection."
    echo -e "  ${DIM}Alternative: git clone $INSTALLER_REPO ~/helios-team-installer && bash ~/helios-team-installer/install.sh${RESET}"
    exit 1
  }
fi

# Sanity check: verify working tree is clean after pull
if [ ! -f "$INSTALLER_DIR/install.sh" ]; then
  echo -e "  ${YELLOW}⚠${RESET} Working tree corrupt — re-cloning..."
  rm -rf "$INSTALLER_DIR"
  git clone -q "$INSTALLER_REPO" "$INSTALLER_DIR"
fi

echo -e "  ${GREEN}✓${RESET} Installer ready at $INSTALLER_DIR"

# Source shared platform lib now that the installer directory is available
_source_platform_lib

echo ""

# ─── Hand off to full installer ──────────────────────────────────────────────
echo -e "  ${BOLD}Launching full installer...${RESET}"
echo ""

# Verify install.sh exists
if [[ ! -f "$INSTALLER_DIR/install.sh" ]]; then
  echo -e "  ${RED}✗${RESET} install.sh not found in cloned repo. Repository structure may have changed." >&2
  echo -e "    Check: https://github.com/helios-agi/helios-team-installer" >&2
  exit 1
fi

# Show what we're about to execute
INSTALLER_COMMIT="$(git -C "$INSTALLER_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
echo -e "  ${DIM}Running install.sh from commit ${INSTALLER_COMMIT}${RESET}"

exec bash "$INSTALLER_DIR/install.sh" "$@"
# FIX #10: exec replaces the process — this line is the fallback if exec itself fails
echo -e "  ${RED}✗${RESET} exec failed. Running directly instead..."
bash "$INSTALLER_DIR/install.sh" "$@"
}
